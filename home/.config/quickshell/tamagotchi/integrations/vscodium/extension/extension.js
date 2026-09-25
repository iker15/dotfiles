// Mochi en el editor (Code - OSS / VSCodium): cuando entras al editor, el Mochi del escritorio
// se mete dentro y vive en su panel (abajo a la izquierda, en el explorador). Mientras programas
// gana experiencia y sube de nivel (y evoluciona). Dentro te mira escribir, se duerme si lo dejas
// solo, se agobia con los errores, se alegra cuando los arreglas y celebra los commits. Además:
// su cara en la barra de estado.
//
// XP (se manda a Mochi cada 30 s y al salir del editor: `qs ipc call pet codeXp N`):
//   +10 por minuto programando de verdad (≥ 20 caracteres escritos ese minuto en el archivo activo)
//   +1 al guardar (como mucho cada 20 s) · +3 archivo nuevo · +5 al depurar
//   +25 al dejar a cero los errores si había 3 o más (como mucho cada 10 min) · +20 por commit
const vscode = require("vscode");
const fs = require("fs");
const path = require("path");
const { execFile, execFileSync } = require("child_process");

const STATE = path.join(process.env.XDG_RUNTIME_DIR || `/run/user/${process.getuid()}`, "mochi-state.json");
// Solo ojos, como él
const EYES = {
    normal: "• •", happy: "^ ^", love: "♥ ♥", excited: "^ ^", sad: "╥ ╥", sulky: "¬ ¬",
    asleep: "- -", sleepy: "ᴗ ᴗ", hot: "> <", curious: "• •", surprised: "O O", squint: "> <",
    focused: "• •", proud: "^ ^"
};
const BREAK_AFTER = 90;   // minutos seguidos programando: te propone descansar

let view = null, bar = null, state = null, alive = true, reaction = null, errors = 0, peakErrors = 0, lastFixXp = 0;
let pendingXp = 0, typedThisMinute = 0, lastSaveXp = 0, langThisMinute = "", memento = null;
let lastTypeAt = 0, typingPing = 0, streak = 0, breakSaid = false, failsInARow = 0;
// Nombres bonitos de los lenguajes (el resto, tal cual)
const LANGS = { php: "PHP", javascript: "JavaScript", javascriptreact: "JavaScript", typescriptreact: "TypeScript", python: "Python", typescript: "TypeScript", html: "HTML", css: "CSS", json: "JSON", jsonc: "JSON", shellscript: "Shell", sql: "SQL", markdown: "Markdown", rust: "Rust", go: "Go", java: "Java", c: "C", cpp: "C++", csharp: "C#", qml: "QML", lua: "Lua" };
const langName = id => LANGS[id] ?? id;
const fmtMin = n => n >= 60 ? `${Math.floor(n / 60)} h${n % 60 ? ` ${n % 60} min` : ""}` : `${n} min`;
// Minutos programados en cada lenguaje (se guardan en el editor)
function langMinutes() {
    return memento?.get("mochi.langMinutes", {}) ?? {};
}
function langSummary() {
    const top = Object.entries(langMinutes()).sort((a, b) => b[1] - a[1]).slice(0, 3);
    return top.map(([l, n]) => `${langName(l)} ${fmtMin(n)}`).join(" · ");
}
// Lo de hoy (minutos programando y XP ganada), se reinicia cada día
function today() {
    const d = new Date().toLocaleDateString("sv");
    const t = memento?.get("mochi.today");
    return t?.date === d ? t : { date: d, minutes: 0, xp: 0 };
}
function addToday(minutes, xp) {
    const t = today();
    t.minutes += minutes;
    t.xp += xp;
    memento?.update("mochi.today", t);
}

function readState() {
    let next = null;
    try {
        next = JSON.parse(fs.readFileSync(STATE, "utf8"));
    } catch (e) {}
    // subida de nivel: la celebra el del panel
    if (state && next && next.level > state.level)
        post({ type: "levelUp", level: next.level, evolved: next.stage > state.stage, stageName: next.stageName });
    state = next;
    update();
}

// ¿Sigue en marcha el Mochi del escritorio? (el archivo de estado se queda aunque lo cierres)
function checkAlive() {
    execFile("qs", ["-c", "tamagotchi", "ipc", "call", "pet", "state"], { timeout: 4000 }, err => {
        if (alive !== !err) {
            alive = !err;
            update();
        }
    });
}

function face() {
    if (reaction && Date.now() < reaction.until)
        return reaction.face;
    if (errors >= 5)
        return "sad";
    return state?.feeling ?? "normal";
}

function post(m) {
    view?.webview.postMessage(m);
}

// Solo está dentro de la ventana del editor que usas (con dos ventanas, no sale en las dos)
function here() {
    return !!state && alive && state.where === "app" && vscode.window.state.focused;
}

function update() {
    const f = face(), t = today();
    if (bar) {
        const lv = state?.level ? ` Nv ${state.level}` : "";
        bar.text = `(${EYES[f] ?? "• •"})${lv}`;
        const langs = langSummary();
        bar.tooltip = state ? `${state.stageName ?? "Mochi"} · nivel ${state.level} (${state.xp - state.levelStart}/${state.levelEnd - state.levelStart} XP)\n♥ ${state.bond} · ${state.text}${errors ? ` · ${errors} errores` : ""}\nHoy: ${fmtMin(t.minutes)} · +${t.xp} XP${langs ? `\nProgramado: ${langs}` : ""}` : "Mochi";
    }
    post({
        type: "state",
        state,
        alive,
        here: here(),
        face: f,
        errors,
        today: t,
        langs: langSummary(),
        lang: langName(vscode.window.activeTextEditor?.document.languageId ?? "")
    });
}

// Una cara un rato y, si hace falta, una frase corta en un bocadillo
function react(f, ms, say) {
    reaction = { face: f, until: Date.now() + ms };
    if (say)
        post({ type: "say", text: say, ms: Math.max(ms, 2600) });
    update();
    setTimeout(update, ms + 50);
}

function desktop(...args) {
    execFile("qs", ["-c", "tamagotchi", "ipc", "call", "pet", ...args], () => {});
}

function gain(n, why) {
    pendingXp += n;
    addToday(0, n);
    post({ type: "xp", n, why });
}
function flushXp(sync) {
    if (pendingXp <= 0)
        return;
    const args = ["-c", "tamagotchi", "ipc", "call", "pet", "codeXp", String(pendingXp)];
    pendingXp = 0;
    if (sync) {
        try {
            execFileSync("qs", args, { timeout: 1500 });
        } catch (e) {}
    } else {
        execFile("qs", args, () => {});
    }
}

// Errores en los archivos abiertos (los de archivos que ni has abierto no le agobian)
function countErrors() {
    let n = 0;
    for (const doc of vscode.workspace.textDocuments) {
        if (doc.uri.scheme !== "file" && doc.uri.scheme !== "untitled")
            continue;
        n += vscode.languages.getDiagnostics(doc.uri).filter(d => d.severity === vscode.DiagnosticSeverity.Error).length;
    }
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
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src ${v.webview.cspSource}; style-src ${v.webview.cspSource} 'unsafe-inline';">
<link rel="stylesheet" href="${src("view.css")}">
</head><body>
<canvas id="c"></canvas>
<div id="bubble"></div>
<div id="info">
  <div id="name"><span id="nick">Mochi</span> <span id="stage"></span></div>
  <div id="lvl"><span id="lvlN"></span><span id="lvlXp"></span></div>
  <div id="bar"><div id="fill"></div></div>
  <div id="today"></div>
  <div id="mood"></div>
  <div id="langs"></div>
  <div id="row"><button id="errs" title="Ver los problemas"></button><button id="out" title="Que salga al escritorio">Sacar al escritorio</button></div>
</div>
<div id="away"><div id="awayText"></div></div>
<script src="${src("mochi-draw.js")}"></script><script src="${src("view.js")}"></script></body></html>`;
            v.webview.onDidReceiveMessage(m => {
                if (m.type === "ready") {
                    update();
                } else if (m.type === "poke") {
                    react("happy", 1200);
                    desktop("codePoke");   // (cuenta como cariño, como tocarlo en el escritorio)
                } else if (m.type === "call") {
                    desktop("appear");     // sale del editor al escritorio
                } else if (m.type === "problems") {
                    vscode.commands.executeCommand("workbench.actions.view.problems");
                }
            });
            // (oculto no recibe mensajes: al volver a verse, que se ponga al día)
            v.onDidChangeVisibility(() => v.visible && update());
            v.onDidDispose(() => {
                if (view === v)
                    view = null;
            });
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
    checkAlive();
    const aliveTimer = setInterval(checkAlive, 60000);
    ctx.subscriptions.push({ dispose: () => clearInterval(aliveTimer) });
    ctx.subscriptions.push(vscode.window.onDidChangeWindowState(s => {
        if (!s.focused)
            flushXp(false);   // (por si cierras sin volver)
        update();
    }));

    // ── Experiencia ──
    ctx.subscriptions.push(vscode.workspace.onDidChangeTextDocument(e => {
        // solo lo que escribes tú en el archivo que tienes delante (ni deshacer/rehacer, ni
        // cambios en otros archivos por renombrar, formatear en bloque, etc.)
        if (e.document.uri.scheme !== "file" || e.document !== vscode.window.activeTextEditor?.document)
            return;
        if (e.reason === vscode.TextDocumentChangeReason?.Undo || e.reason === vscode.TextDocumentChangeReason?.Redo)
            return;
        let n = 0;
        for (const c of e.contentChanges)
            n += Math.min(c.text.length, 200) || (c.rangeLength ? 1 : 0);
        if (!n)
            return;
        typedThisMinute += n;
        langThisMinute = e.document.languageId;
        const now = Date.now();
        lastTypeAt = now;
        if (now - typingPing > 400) {
            typingPing = now;
            post({ type: "typing" });
        }
    }));
    const minute = setInterval(() => {
        // solo si el editor tiene el foco (no cuenta pegar cosas con el editor en segundo plano)
        if (typedThisMinute >= 20 && vscode.window.state.focused) {
            gain(10, langName(langThisMinute));
            addToday(1, 0);
            const m = langMinutes();
            m[langThisMinute] = (m[langThisMinute] ?? 0) + 1;
            memento.update("mochi.langMinutes", m);
            // racha sin parar: a la hora y media te propone descansar (una vez)
            streak++;
            if (streak >= BREAK_AFTER && !breakSaid) {
                breakSaid = true;
                react("sleepy", 4000, `Llevas ${fmtMin(streak)} sin parar… ¿estiramos un poco?`);
            }
            update();
        } else if (Date.now() - lastTypeAt > 10 * 60000) {
            streak = 0;   // (10 min sin escribir: ya has descansado)
            breakSaid = false;
        }
        typedThisMinute = 0;
    }, 60000);
    const flush = setInterval(() => flushXp(false), 30000);
    ctx.subscriptions.push({ dispose: () => { clearInterval(minute); clearInterval(flush); } });
    ctx.subscriptions.push(vscode.window.onDidChangeActiveTextEditor(() => update()));
    // (moverte por el código o hacer scroll también es estar ahí: así no se duerme mientras lees)
    let activePing = 0;
    const activeNow = () => {
        if (Date.now() - activePing > 3000) {
            activePing = Date.now();
            post({ type: "active" });
        }
    };
    ctx.subscriptions.push(vscode.window.onDidChangeTextEditorSelection(activeNow));
    ctx.subscriptions.push(vscode.window.onDidChangeTextEditorVisibleRanges(activeNow));
    ctx.subscriptions.push(vscode.workspace.onDidSaveTextDocument(() => {
        post({ type: "blink" });
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
    // Tareas (compilar, tests…) y comandos de la terminal: se preocupa si fallan y se alegra
    // cuando vuelven a ir
    const ended = code => {
        if (code === undefined || code === null)
            return;
        if (code !== 0) {
            failsInARow++;
            react(failsInARow >= 3 ? "sad" : "surprised", 1600, failsInARow === 3 ? "Uf… ya van tres fallos seguidos" : "");
        } else {
            if (failsInARow >= 2)
                react("happy", 2200, "¡Ahora sí!");
            failsInARow = 0;
        }
    };
    ctx.subscriptions.push(vscode.tasks.onDidEndTaskProcess(e => ended(e.exitCode)));
    if (vscode.window.onDidEndTerminalShellExecution)
        ctx.subscriptions.push(vscode.window.onDidEndTerminalShellExecution(e => ended(e.exitCode)));
    // commits (con la extensión de git del editor)
    try {
        const git = vscode.extensions.getExtension("vscode.git");
        const hook = api => {
            const heads = new Map();
            const watch = repo => {
                heads.set(repo, { commit: repo.state.HEAD?.commit, branch: repo.state.HEAD?.name });
                ctx.subscriptions.push(repo.state.onDidChange(() => {
                    const c = repo.state.HEAD?.commit, branch = repo.state.HEAD?.name, before = heads.get(repo);
                    heads.set(repo, { commit: c, branch });
                    if (!c || !before?.commit || c === before.commit || branch !== before.branch)
                        return;
                    // commit nuevo encima del de antes, en la misma rama (no un cambio de rama ni
                    // un pull: con rama remota, el pull no deja commits por subir)
                    const up = repo.state.HEAD?.upstream;
                    if (up && !(repo.state.HEAD?.ahead > 0))
                        return;
                    repo.getCommit(c).then(info => {
                        if (info?.parents?.[0] === before.commit) {
                            react("love", 2400, "¡Commit!");
                            post({ type: "hop" });
                            gain(20, "commit");
                        }
                    }, () => {});
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
    const recount = () => {
        clearTimeout(debounce);
        debounce = setTimeout(() => {
            const n = countErrors(), before = errors;
            errors = n;
            if (n > before && n - before >= 3)
                react("surprised", 1400, n >= 5 ? `Uy… ${n} errores` : "");
            if (n > 0)
                peakErrors = Math.max(peakErrors, n);
            if (n === 0 && before > 0) {
                const big = peakErrors >= 3;
                react("happy", 2200, big ? "¡Arreglado!" : "");
                if (big && Date.now() - lastFixXp > 10 * 60000) {
                    lastFixXp = Date.now();
                    gain(25, "errores arreglados");
                }
                peakErrors = 0;
            }
            update();
        }, 1500);
    };
    ctx.subscriptions.push(vscode.languages.onDidChangeDiagnostics(recount));
    ctx.subscriptions.push(vscode.workspace.onDidCloseTextDocument(recount));
}

function deactivate() {
    flushXp(true);   // (síncrono: si no, al cerrar el editor se perdía)
}

module.exports = { activate, deactivate };
