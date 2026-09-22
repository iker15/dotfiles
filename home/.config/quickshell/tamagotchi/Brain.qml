pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Conexión con Claude Code (brain.sh) y estado de la conversación
Singleton {
    id: root

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/tamagotchi"

    property ListModel messages: ListModel {}
    property bool busy: false
    // idle, thinking, working, talking, happy, sad
    property string mood: "idle"
    property string toolName: ""
    property string sessionId: ""
    property string reply: ""       // respuesta actual (para el bocadillo)

    property int streamIdx: -1      // burbuja que se está escribiendo
    property bool gotInit: false
    property bool retried: false
    property string lastPrompt: ""
    property string pendingPrompt: ""

    // Historial en Markdown, un archivo por día
    readonly property string historyDir: Quickshell.env("HOME") + "/Documentos/Mochi"

    readonly property string status: {
        switch (mood) {
        case "thinking":
            return "Pensando…";
        case "working":
            return toolName ? `Usando ${toolName}…` : "Trabajando…";
        case "talking":
            return "Escribiendo…";
        case "happy":
            return "¡Hecho!";
        case "sad":
            return "Algo ha salido mal";
        default:
            return sessionId ? "¿Qué hacemos?" : "¡Hola! ¿Qué hacemos?";
        }
    }

    // Primero prueba los comandos rápidos (quick.sh); si no lo entiende, a Claude
    function send(text: string, byVoice = false): void {
        text = text.trim();
        if (!text || busy)
            return;
        if (text === "/nuevo" || text === "/new") {
            reset();
            return;
        }
        messages.append({ role: "user", text: text });
        log(byVoice ? "Tú 🎙" : "Tú", text);
        lastPrompt = text;
        reply = "";
        busy = true;
        mood = "thinking";
        streamIdx = -1;
        quick.command = [Quickshell.shellDir + "/quick.sh", text];
        quick.running = true;
    }

    function askClaude(text: string): void {
        if (!proc.running)
            proc.running = true;
        write({ type: "user", message: { role: "user", content: text } });
    }

    function log(who: string, text: string): void {
        const now = new Date();
        const day = Qt.formatDate(now, "yyyy-MM-dd");
        const entry = `**${who}** · ${Qt.formatTime(now, "HH:mm")}\n\n${text.trim()}\n\n`;
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && f="$1/$2.md" && { [ -s "$f" ] || printf "# Mochi · %s\\n\\n" "$2"; printf "%s\\n" "$3"; } >> "$f"', "sh", historyDir, day, entry]);
    }

    function stop(): void {
        if (busy)
            write({ type: "control_request", request_id: "stop-" + Date.now(), request: { subtype: "interrupt" } });
    }

    function reset(): void {
        proc.running = false;
        warmAgain.restart();
        saveSession("");
        messages.clear();
        reply = "Empezamos de cero ✨";
        busy = false;
        mood = "happy";
        moodTimer.restart();
        messages.append({ role: "info", text: "Conversación nueva" });
    }

    function write(obj: var): void {
        proc.write(JSON.stringify(obj) + "\n");
    }

    function saveSession(id: string): void {
        sessionId = id;
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && printf %s "$2" > "$1/session"', "sh", stateDir, id]);
    }

    function describeTool(name: string, input: var): string {
        const i = input ?? {};
        const base = s => String(s ?? "").split("/").pop();
        switch (name) {
        case "Bash":
            return i.command ?? "";
        case "Read":
        case "Write":
        case "Edit":
        case "NotebookEdit":
            return base(i.file_path);
        case "Grep":
        case "Glob":
            return i.pattern ?? "";
        case "WebFetch":
            return i.url ?? "";
        case "WebSearch":
            return i.query ?? "";
        default:
            return i.description ?? "";
        }
    }

    function handle(line: string): void {
        let d;
        try {
            d = JSON.parse(line);
        } catch (e) {
            return;
        }

        if (d.type === "system" && d.subtype === "init") {
            gotInit = true;
            if (d.session_id && d.session_id !== sessionId)
                saveSession(d.session_id);
        } else if (d.type === "stream_event") {
            const e = d.event ?? {};
            if (e.type === "content_block_start") {
                const b = e.content_block ?? {};
                if (b.type === "text") {
                    messages.append({ role: "assistant", text: "" });
                    streamIdx = messages.count - 1;
                    if (reply)
                        reply += "\n\n";
                    mood = "talking";
                } else if (b.type === "thinking") {
                    mood = "thinking";
                } else if (b.type === "tool_use") {
                    toolName = b.name ?? "";
                    mood = "working";
                }
            } else if (e.type === "content_block_delta" && e.delta?.type === "text_delta" && streamIdx >= 0) {
                messages.setProperty(streamIdx, "text", messages.get(streamIdx).text + e.delta.text);
                reply += e.delta.text;
            }
        } else if (d.type === "assistant") {
            // Los textos llegan por stream_event; aquí solo las herramientas (con su input completo)
            for (const b of d.message?.content ?? [])
                if (b.type === "tool_use")
                    messages.append({ role: "tool", text: `${b.name}  ${describeTool(b.name, b.input)}`.trim() });
        } else if (d.type === "result") {
            busy = false;
            streamIdx = -1;
            toolName = "";
            if (d.session_id && d.session_id !== sessionId)
                saveSession(d.session_id);
            mood = d.is_error ? "sad" : "happy";
            if (d.is_error && d.result) {
                messages.append({ role: "info", text: String(d.result) });
                reply = String(d.result);
            }
            if (reply)
                log("Mochi", reply);
            moodTimer.restart();
        }
    }

    Timer {
        id: warmAgain

        interval: 800
        onTriggered: if (!proc.running) proc.running = true
    }

    Timer {
        id: moodTimer

        interval: 2500
        onTriggered: if (!root.busy) root.mood = "idle"
    }

    Process {
        id: quick

        stdout: StdioCollector {
            id: quickOut
        }

        onExited: code => {
            if (code === 0 && quickOut.text.trim()) {
                root.reply = quickOut.text.trim();
                root.messages.append({ role: "assistant", text: root.reply });
                root.log("Mochi ⚡", root.reply);
                root.busy = false;
                root.mood = "happy";
                moodTimer.restart();
            } else {
                root.askClaude(root.lastPrompt);
            }
        }
    }

    Process {
        id: proc

        command: [Quickshell.shellDir + "/brain.sh"]
        environment: ({ MOCHI_SESSION: root.sessionId })
        stdinEnabled: true

        onStarted: root.gotInit = false

        stdout: SplitParser {
            onRead: data => root.handle(data)
        }

        stderr: SplitParser {
            onRead: data => console.warn("brain:", data)
        }

        onExited: (code, status) => {
            // La sesión guardada no se pudo reanudar: empezar una nueva y reenviar
            // (con la precarga puede pasar antes de que haya ningún mensaje pendiente)
            if (!root.gotInit && root.sessionId && !root.retried && code !== 0) {
                root.retried = true;
                root.saveSession("");
                Qt.callLater(() => {
                    proc.running = true;
                    if (root.busy)
                        root.askClaude(root.lastPrompt);
                });
                return;
            }
            if (root.busy) {
                root.busy = false;
                root.mood = "sad";
                root.messages.append({ role: "info", text: `Me he quedado sin cerebro (código ${code}). Prueba otra vez.` });
                root.reply = `Me he quedado sin cerebro (código ${code}). Prueba otra vez.`;
                moodTimer.restart();
            }
        }
    }

    FileView {
        path: root.stateDir + "/session"
        onLoaded: root.sessionId = text().trim()
    }

    // Arrancar Claude ya, para que la primera respuesta no espere al arranque
    Timer {
        running: true
        interval: 1500
        onTriggered: if (!proc.running) proc.running = true
    }
}
