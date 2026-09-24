// Mochi en VSCodium: un Mochi pequeñito en el explorador (mismo aspecto y estado que el del
// escritorio: cara, gorro, cariño) y su cara en la barra de estado. Reacciona a tu código:
// si aparecen errores se preocupa; si los arreglas todos, se alegra (y el del escritorio también).
const vscode = require("vscode");
const fs = require("fs");
const path = require("path");
const { execFile } = require("child_process");

const STATE = path.join(process.env.XDG_RUNTIME_DIR || `/run/user/${process.getuid()}`, "mochi-state.json");
// Solo ojos, como él
const EYES = {
    normal: "• •", happy: "^ ^", love: "♥ ♥", excited: "^ ^", sad: "╥ ╥", sulky: "¬ ¬",
    asleep: "- -", sleepy: "ᴗ ᴗ", hot: "> <", curious: "• •?", surprised: "O O", squint: "> <"
};

let view = null, bar = null, state = null, reaction = null, errors = 0, peakErrors = 0;

function readState() {
    try {
        state = JSON.parse(fs.readFileSync(STATE, "utf8"));
    } catch (e) {
        state = null;
    }
    update();
}

function face() {
    if (reaction && Date.now() < reaction.until)
        return reaction.face;
    if (errors >= 5)
        return "sad";
    return state?.feeling ?? "normal";
}

function update() {
    const f = face();
    if (bar) {
        bar.text = `(${EYES[f] ?? "• •"})`;
        bar.tooltip = state ? `Mochi · ❤ ${state.bond} · ${state.text}${errors ? ` · ${errors} errores` : ""}` : "Mochi";
    }
    view?.webview.postMessage({ type: "state", state, face: f });
}

function react(f, ms) {
    reaction = { face: f, until: Date.now() + ms };
    update();
    setTimeout(update, ms + 50);
}

function desktop(...args) {
    execFile("qs", ["-c", "tamagotchi", "ipc", "call", "pet", ...args], () => {});
}

function countErrors() {
    let n = 0;
    for (const [, diags] of vscode.languages.getDiagnostics())
        n += diags.filter(d => d.severity === vscode.DiagnosticSeverity.Error).length;
    return n;
}

function activate(ctx) {
    bar = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 1000);
    bar.command = "mochi.show";
    bar.show();
    ctx.subscriptions.push(bar);
    ctx.subscriptions.push(vscode.commands.registerCommand("mochi.show", () => vscode.commands.executeCommand("mochi.view.focus")));

    ctx.subscriptions.push(vscode.window.registerWebviewViewProvider("mochi.view", {
        resolveWebviewView(v) {
            view = v;
            const media = vscode.Uri.file(path.join(ctx.extensionPath, "media"));
            v.webview.options = { enableScripts: true, localResourceRoots: [media] };
            const src = f => v.webview.asWebviewUri(vscode.Uri.joinPath(media, f));
            v.webview.html = `<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src ${v.webview.cspSource}; style-src 'unsafe-inline';">
<style>html,body{margin:0;height:100%;overflow:hidden;background:transparent}canvas{display:block;margin:0 auto;cursor:pointer}
#s{text-align:center;font-size:12px;opacity:.75;font-family:var(--vscode-font-family);color:var(--vscode-foreground);padding-bottom:6px}</style>
</head><body><canvas id="c" width="220" height="150"></canvas><div id="s"></div>
<script src="${src("mochi-draw.js")}"></script><script src="${src("view.js")}"></script></body></html>`;
            v.webview.onDidReceiveMessage(m => {
                if (m.type === "poke")
                    react("happy", 1200);
            });
            v.onDidDispose(() => (view = null));
            update();
        }
    }));

    // Estado de Mochi (lo publica él)
    readState();
    try {
        const w = fs.watch(path.dirname(STATE), (ev, file) => {
            if (file === path.basename(STATE))
                readState();
        });
        ctx.subscriptions.push({ dispose: () => w.close() });
    } catch (e) {
        const t = setInterval(readState, 2000);
        ctx.subscriptions.push({ dispose: () => clearInterval(t) });
    }

    // Errores del código
    errors = countErrors();
    let debounce = null;
    ctx.subscriptions.push(vscode.languages.onDidChangeDiagnostics(() => {
        clearTimeout(debounce);
        debounce = setTimeout(() => {
            const n = countErrors(), before = errors;
            errors = n;
            if (n > before && n - before >= 3)
                react("surprised", 1200);
            if (n > 0)
                peakErrors = Math.max(peakErrors, n);
            if (n === 0 && before > 0) {
                react("happy", 2200);
                // arreglados muchos de golpe: también se alegra el del escritorio
                if (peakErrors >= 3)
                    desktop("face", "happy");
                peakErrors = 0;
            }
            update();
        }, 1500);
    }));

    // Guardar: parpadea contento; depurar: se emociona
    ctx.subscriptions.push(vscode.workspace.onDidSaveTextDocument(() => view?.webview.postMessage({ type: "blink" })));
    ctx.subscriptions.push(vscode.debug.onDidStartDebugSession(() => react("excited", 1800)));
}

function deactivate() {}

module.exports = { activate, deactivate };
