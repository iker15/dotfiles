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
    // Cara que pone Mochi: idle, thinking, talking, happy, sad, o una emoción (ver persona.md)
    // o la de la herramienta que usa (reading, searching, focused, working)
    property string mood: "idle"
    property string toolName: ""
    property string sessionId: ""
    property string reply: ""       // respuesta actual, sin etiquetas (para el bocadillo)
    property string rawReply: ""    // tal cual llega de Claude, con las etiquetas [[emoción]]
    property string blockRaw: ""
    property string emotion: ""     // última emoción que ha marcado Claude
    property bool talking: false    // escribiendo la respuesta

    readonly property var emotions: ["happy", "excited", "love", "proud", "curious", "thinking", "confused", "surprised", "sad", "sorry", "playful", "sleepy", "focused", "calm"]

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

    // Reacción inmediata a lo que le dices, antes de que Claude conteste
    function guessMood(text: string): string {
        const t = text.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
        if (/te quiero|te adoro|eres (el|la) mejor|mono|cuqui|precioso/.test(t))
            return "love";
        if (/gracias|genial|perfecto|bien hecho|guay|crack|increible|funciona/.test(t) && !/no funciona/.test(t))
            return "happy";
        if (/triste|mal dia|cansad|estresad|agobiad|harto|fatal/.test(t))
            return "sorry";
        if (/error|falla|no funciona|roto|problema|bug|ayuda|socorro|no va\b/.test(t))
            return "focused";
        if (/chiste|broma|jugar|juego|adivina/.test(t))
            return "playful";
        if (/^(hola|buenas|hey|ey|buenos|holi)/.test(t))
            return "excited";
        if (/\?\s*$|^(que|como|por que|cual|donde|quien|cuando|sabes)\b/.test(t))
            return "curious";
        return "";
    }

    // Cara según la herramienta: leer, buscar en internet, editar…
    function toolMood(name: string): string {
        if (/^(Read|Grep|Glob|NotebookRead)$/.test(name))
            return "reading";
        if (/^Web/.test(name))
            return "searching";
        if (/^(Edit|Write|NotebookEdit)$/.test(name))
            return "focused";
        return "working";
    }

    // Quita las etiquetas [[emoción]] (y una a medio llegar al final)
    function clean(text: string): string {
        return text.replace(/\[\[\w*\]\]\s*/g, "").replace(/\[\[?\w*$/, "");
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
        rawReply = "";
        emotion = "";
        talking = false;
        busy = true;
        mood = guessMood(text) || "thinking";
        startThinking.restart();
        streamIdx = -1;
        quick.command = [Quickshell.shellDir + "/quick.sh", text];
        quick.running = true;
    }

    function askClaude(text: string): void {
        if (!proc.running)
            proc.running = true;
        // Contexto de lo que pasa en el escritorio (Claude no lo ve si no)
        const content = `<contexto automático, no lo menciones si no viene al caso: ${Mind.context()}>\n\n${text}`;
        write({ type: "user", message: { role: "user", content: content } });
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
                    blockRaw = "";
                    if (clean(rawReply).trim())
                        rawReply += "\n\n";
                    talking = true;
                    mood = emotion || "talking";
                } else if (b.type === "thinking") {
                    talking = false;
                    mood = "thinking";
                } else if (b.type === "tool_use") {
                    toolName = b.name ?? "";
                    talking = false;
                    mood = toolMood(toolName);
                }
            } else if (e.type === "content_block_delta" && e.delta?.type === "text_delta" && streamIdx >= 0) {
                blockRaw += e.delta.text;
                rawReply += e.delta.text;
                messages.setProperty(streamIdx, "text", clean(blockRaw));
                reply = clean(rawReply).trim();
                // La última emoción marcada manda en la cara
                const tags = [...rawReply.matchAll(/\[\[(\w+)\]\]/g)].map(m => m[1].toLowerCase()).filter(t => emotions.includes(t));
                if (tags.length && tags[tags.length - 1] !== emotion) {
                    emotion = tags[tags.length - 1];
                    mood = emotion;
                }
            }
        } else if (d.type === "assistant") {
            // Los textos llegan por stream_event; aquí solo las herramientas (con su input completo)
            for (const b of d.message?.content ?? [])
                if (b.type === "tool_use")
                    messages.append({ role: "tool", text: `${b.name}  ${describeTool(b.name, b.input)}`.trim() });
        } else if (d.type === "result") {
            busy = false;
            talking = false;
            streamIdx = -1;
            toolName = "";
            if (d.session_id && d.session_id !== sessionId)
                saveSession(d.session_id);
            mood = d.is_error ? "sad" : emotion || "happy";
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

    // La reacción al mensaje dura un momento; luego, a pensar
    Timer {
        id: startThinking

        interval: 1500
        onTriggered: if (root.busy && !root.talking && !root.toolName) root.mood = "thinking"
    }

    Timer {
        id: moodTimer

        interval: 3500
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
