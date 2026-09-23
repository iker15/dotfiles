pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components.misc

Scope {
    property alias lock: lock

    WlSessionLock {
        id: lock

        signal unlock

        LockSurface {
            lock: lock
            pam: pam
        }
    }

    Pam {
        id: pam

        lock: lock
    }

    // Avisa a Mochi (tamagotchi): con la pantalla bloqueada no escucha ni obedece, y se viene
    // a la pantalla de bloqueo. (Se comprueba también cada medio segundo: al desbloquear la
    // señal no siempre llegaba a escribir el fichero.)
    QtObject {
        id: lockFlag

        property int written: -1

        function sync(): void {
            const v = lock.locked ? 1 : 0;
            if (v === written)
                return;
            written = v;
            Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" > "$2"', "sh", String(v), `${Quickshell.env("XDG_RUNTIME_DIR")}/caelestia-locked`]);
        }
    }

    Connections {
        target: lock

        function onLockedChanged(): void {
            lockFlag.sync();
        }
    }

    Timer {
        running: true
        repeat: true
        triggeredOnStart: true
        interval: 500
        onTriggered: lockFlag.sync()
    }

    Loader {
        asynchronous: true
        active: true
        onLoaded: active = false

        // Force a load of a screencopy so the one in the lock works
        // My guess is the ICC backend loads async on first request, which if the lock is
        // the first request it fails to capture (because it's async and the compositor
        // refuses capture when locked)
        sourceComponent: ScreencopyView {
            captureSource: Quickshell.screens[0]
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "lock"
        description: "Lock the current session"
        onPressed: lock.locked = true
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "unlock"
        description: "Unlock the current session"
        onPressed: lock.unlock()
    }

    IpcHandler {
        function lock(): void {
            lock.locked = true;
        }

        function unlock(): void {
            lock.unlock();
        }

        function isLocked(): bool {
            return lock.locked;
        }

        target: "lock"
    }
}
