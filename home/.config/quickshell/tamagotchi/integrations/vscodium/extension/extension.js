// Mochi en el editor (Code - OSS / VSCodium): cuando entras al editor, el Mochi del escritorio
// se mete dentro y vive en su panel (abajo a la izquierda, en el explorador). Mientras programas
// gana experiencia y sube de nivel (y evoluciona). Además: su cara en la barra de estado, se
// preocupa con los errores y se alegra cuando los arreglas.
//
// XP (se manda a Mochi cada 30 s: `qs ipc call pet codeXp N`, él la guarda con su cariño):
//   +10 por minuto programando de verdad (≥ 20 caracteres escritos ese minuto)
//   +1 al guardar (como mucho cada 20 s) · +3 archivo nuevo · +5 al depurar
//   +25 al dejar a cero los errores si había 3 o más · +20 por commit
const vscode = require("vscode");
const fs = require("fs");
const path = require("path");
const { execFile } = require("child_process");

const STATE = path.join(process.env.XDG_RUNTIME_DIR || `/run/user/${process.getuid()}`, "mochi-state.json");
// Solo ojos, como él
const EYES = {
    normal: "• •", happy: "^ ^", love: "♥ ♥", excited: "^ ^", sad: "╥ ╥", sulky: "¬ ¬",
    asleep: "- -", sleepy: "ᴗ ᴗ", hot: "> <", curious: "• •", surprised: "O O", squint: "> <",
    focused: "• •", proud: "^ ^"
};

let view = null, bar = null, state = null, reaction = null, errors = 0, peakErrors = 0;
let pendingXp = 0, typedThisMinute = 0, lastSaveXp = 0, langThisMinute = "", memento = null;
// Nombres bonitos de los lenguajes (el resto, tal cual)
const LANGS = { php: "PHP", javascript: "JavaScript", javascriptreact: "JavaScript", python: "Python", typescript: "TypeScript", html: "HTML", css: "CSS", json: "JSON", shellscript: "Shell", sql: "SQL" };
const langName = id => LANGS[id] ?? id;
// Minutos programados en cada lenguaje (se guardan en el editor)
function langMinutes() {
    return memento?.get("mochi.langMinutes", {}) ?? {};
}
function langSummary() {
    const m = langMinutes(), top = Object.entries(m).sort((a, b) => b[1] - a[1]).slice(0, 3);
    const fmt = n => n >= 60 ? `${Math.floor(n / 60)} h ${n % 60 ? (n % 60) + " min" : ""}`.trim() : `${n} min`;
    return top.map(([l, n]) => `${langName(l)} ${fmt(n)}`).join(" · ");
}

function readState() {
    let next = null;
    try {
        next = JSON.parse(fs.readFileSync(STATE, "utf8"));
    } catch (e) {}
    // subida de nivel: la celebra el del panel
    if (state && next && next.level > state.level)
        view?.webview.postMessage({ type: "levelUp", level: next.level, evolved: next.stage > state.stage, stageName: next.stageName });
    state = next;
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
        const lv = state?.level ? ` Nv ${state.level}` : "";
        bar.text = `(${EYES[f] ?? "• •"})${lv}`;
        const langs = langSummary();
        bar.tooltip = state ? `${state.stageName ?? "Mochi"} · nivel ${state.level} (${state.xp - state.levelStart}/${state.levelEnd - state.levelStart} XP)\n♥ ${state.bond} · ${state.text}${errors ? ` · ${errors} errores` : ""}${langs ? `\nProgramado: ${langs}` : ""}` : "Mochi";
    }
    view?.webview.postMessage({ type: "state", state, face: f, langs: langSummary(), lang: langName(vscode.window.activeTextEditor?.document.languageId ?? "") });
}

function react(f, ms) {
    reaction = { face: f, until: Date.now() + ms };
    update();
    setTimeout(update, ms + 50);
}

function desktop(...args) {
    execFile("qs", ["-c", "tamagotchi", "ipc", "call", "pet", ...args], () => {});
}

function gain(n, why) {
    pendingXp += n;
    view?.webview.postMessage({ type: "xp", n, why });
}

function countErrors() {
    let n = 0;
    for (const [, diags] of vscode.languages.getDiagnostics())
        n += diags.filter(d => d.severity === vscode.DiagnosticSeverity.Error).length;
    return n;
}

function activate(ctx) {
    memento = ctx.globalState;
    bar = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, -1000);
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
<style>
html,body{margin:0;height:100%;overflow:hidden;background:transparent;font-family:var(--vscode-font-family);color:var(--vscode-foreground)}
canvas{position:absolute;left:0;bottom:0;cursor:pointer}
#info{position:absolute;left:150px;bottom:14px;right:10px;font-size:12px}
#name{font-weight:600}
#lvl{opacity:.8;margin:2px 0 5px}
#bar{height:5px;border-radius:3px;background:var(--vscode-editorWidget-border,rgba(128,128,128,.3));overflow:hidden}
#fill{height:100%;width:0;background:var(--vscode-progressBar-background,#4d8);transition:width .6s}
#mood{opacity:.7;margin-top:5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
#langs{opacity:.55;margin-top:2px;font-size:11px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
#away{position:absolute;left:12px;bottom:12px;right:10px;font-size:12px;opacity:.6;display:none}
</style></head><body>
<canvas id="c"></canvas>
<div id="info"><div id="name">Mochi</div><div id="lvl"></div><div id="bar"><div id="fill"></div></div><div id="mood"></div><div id="langs"></div></div>
<div id="away"></div>
<script src="${src("mochi-draw.js")}"></script><script src="${src("view.js")}"></script></body></html>`;
            v.webview.onDidReceiveMessage(m => {
                if (m.type === "poke")
                    react("happy", 1200);
                else if (m.type === "call")
                    desktop("appear");
            });
            v.onDidDispose(() => (view = null));
            update();
        }
    }));

    // La primera vez, abre su panel (y vuelve al editor)
    if (!ctx.globalState.get("mochi.revealed")) {
        ctx.globalState.update("mochi.revealed", true);
        vscode.commands.executeCommand("mochi.view.focus").then(() => vscode.commands.executeCommand("workbench.action.focusActiveEditorGroup"), () => {});
    }

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

    // ── Experiencia ──
    ctx.subscriptions.push(vscode.workspace.onDidChangeTextDocument(e => {
        if (e.document.uri.scheme !== "file")
            return;
        for (const c of e.contentChanges)
            typedThisMinute += Math.min(c.text.length, 200) || (c.rangeLength ? 1 : 0);
        langThisMinute = e.document.languageId;
    }));
    const minute = setInterval(() => {
        // solo si el editor tiene el foco (no cuenta pegar cosas con el editor en segundo plano)
        if (typedThisMinute >= 20 && vscode.window.state.focused) {
            gain(10, langName(langThisMinute));
            const m = langMinutes();
            m[langThisMinute] = (m[langThisMinute] ?? 0) + 1;
            memento.update("mochi.langMinutes", m);
            update();
        }
        typedThisMinute = 0;
    }, 60000);
    const flush = setInterval(() => {
        if (pendingXp > 0) {
            desktop("codeXp", String(pendingXp));
            pendingXp = 0;
        }
    }, 30000);
    ctx.subscriptions.push({ dispose: () => { clearInterval(minute); clearInterval(flush); } });
    ctx.subscriptions.push(vscode.window.onDidChangeActiveTextEditor(() => update()));
    ctx.subscriptions.push(vscode.workspace.onDidSaveTextDocument(() => {
        view?.webview.postMessage({ type: "blink" });
        if (Date.now() - lastSaveXp > 20000) {
            lastSaveXp = Date.now();
            gain(1, "guardado");
        }
    }));
    ctx.subscriptions.push(vscode.workspace.onDidCreateFiles(e => gain(3 * Math.min(e.files.length, 3), "archivo nuevo")));
    ctx.subscriptions.push(vscode.debug.onDidStartDebugSession(() => {
        react("excited", 1800);
        gain(5, "depurando");
    }));
    // commits (con la extensión de git del editor)
    try {
        const git = vscode.extensions.getExtension("vscode.git");
        const hook = api => {
            const heads = new Map();
            const watch = repo => {
                heads.set(repo, repo.state.HEAD?.commit);
                ctx.subscriptions.push(repo.state.onDidChange(() => {
                    const c = repo.state.HEAD?.commit, before = heads.get(repo);
                    heads.set(repo, c);
                    // commit nuevo en la misma rama (no un cambio de rama)
                    if (c && before && c !== before && repo.state.HEAD?.ahead > 0) {
                        react("proud", 2000);
                        gain(20, "commit");
                    }
                }));
            };
            api.repositories.forEach(watch);
            ctx.subscriptions.push(api.onDidOpenRepository(watch));
        };
        if (git)
            (git.isActive ? Promise.resolve(git.exports) : git.activate()).then(e => hook(e.getAPI(1)), () => {});
    } catch (e) {}

    // ── Errores del código ──
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
                if (peakErrors >= 3)
                    gain(25, "errores arreglados");
                peakErrors = 0;
            }
            update();
        }, 1500);
    }));
}

function deactivate() {
    if (pendingXp > 0)
        desktop("codeXp", String(pendingXp));
}

module.exports = { activate, deactivate };
