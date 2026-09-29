pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// El estado sale siempre de lo que pasa de verdad (gpu-screen-recorder vivo + el fichero de
// pausa de caelestia-record), así que da igual si se graba desde aquí o con el atajo.
Singleton {
    id: root

    readonly property alias running: props.running
    readonly property alias paused: props.paused
    readonly property alias elapsed: props.elapsed
    property int refCount: 0 // (lo usa Ref; ya no hace falta para sondear)

    // Mismo script que los atajos: pide nombre al parar y apunta la pausa
    readonly property string wrapper: `${Quickshell.env("HOME")}/.local/bin/caelestia-record`
    property bool stopping
    property real holdUntil

    function start(extraArgs = []): void {
        if (props.running || startProc.running)
            return;
        props.running = true;
        props.paused = false;
        props.elapsed = 0;
        startProc.exec([wrapper, ...extraArgs]);
    }

    function stop(): void {
        if (!props.running)
            return;
        props.running = false;
        props.paused = false;
        // (suelto: parar se queda esperando al nombre y a la notificación)
        stopping = true;
        holdUntil = Date.now() + 15000;
        Quickshell.execDetached([wrapper]);
    }

    function togglePause(): void {
        if (!props.running)
            return;
        props.paused = !props.paused;
        holdUntil = Date.now() + 1500;
        Quickshell.execDetached([wrapper, "-p"]);
    }

    function reconcile(out: string): void {
        const [rec, pause, secs] = out.trim().split("\n");
        const running = rec === "1";

        // Arrancando (slurp, etc.): el propio proceso manda
        if (startProc.running)
            return;
        if (stopping) {
            if (running && Date.now() < holdUntil)
                return;
            stopping = false;
        } else if (Date.now() < holdUntil) {
            return;
        }

        if (running !== props.running) {
            // Empezada/parada fuera de la shell (atajo): cuenta desde que arrancó el grabador
            props.running = running;
            props.elapsed = running ? (parseInt(secs) || 0) : 0;
        }
        props.paused = running && pause === "1";
    }

    PersistentProperties {
        id: props

        property bool running: false
        property bool paused: false
        property real elapsed: 0 // Might get too large for int

        reloadableId: "recorder"
    }

    Process {
        id: checkProc

        command: ["sh", "-c", `
            pid=$(pidof -s gpu-screen-recorder) && echo 1 || echo 0
            [ -e "\${XDG_RUNTIME_DIR:-/tmp}/caelestia-record-paused" ] && echo 1 || echo 0
            [ -n "$pid" ] && ps -o etimes= -p "$pid" || echo 0
        `]
        stdout: StdioCollector {
            onStreamFinished: root.reconcile(text)
        }
    }

    Process {
        id: startProc

        onExited: checkProc.running = true // qmllint disable signal-handler-parameters
    }

    // Siempre, no solo con el panel abierto: si no, lo que se empieza con el atajo no se ve
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true

        onTriggered: checkProc.running = true
    }

    Connections {
        function onSecondsChanged(): void {
            props.elapsed++;
        }

        enabled: props.running && !props.paused
        target: Time // qmllint disable incompatible-type
    }
}
