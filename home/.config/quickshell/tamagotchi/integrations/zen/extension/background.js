// Puente con Mochi (host nativo "mochi"): reenvía lo que cuentan las pestañas con vídeo y
// guarda el estado de Mochi para la nueva pestaña.
let port = null;
let last = { state: null, colours: {}, mode: "dark" };
let videoTab = null;   // pestaña que manda el vídeo ahora

function connect() {
    try {
        port = browser.runtime.connectNative("mochi");
    } catch (e) {
        port = null;
        return;
    }
    port.onMessage.addListener(msg => {
        if (msg.type === "state") {
            last = msg;
            browser.runtime.sendMessage({ type: "state", ...msg }).catch(() => {});
        }
    });
    port.onDisconnect.addListener(() => {
        port = null;
        setTimeout(connect, 5000);
    });
}
connect();

browser.runtime.onMessage.addListener((msg, sender) => {
    if (msg.type === "video") {
        // solo cuenta la pestaña visible que tiene el vídeo en marcha (o la última que lo tuvo)
        if (msg.visible && (msg.playing || sender.tab.id === videoTab)) {
            videoTab = sender.tab.id;
            port?.postMessage({ ...msg, tab: sender.tab.id, windowTitle: sender.tab.title });
        } else if (sender.tab.id === videoTab && !msg.visible) {
            videoTab = null;
            port?.postMessage({ type: "gone" });
        }
    } else if (msg.type === "getState") {
        return Promise.resolve(last);
    } else if (msg.type === "ipc") {
        port?.postMessage(msg);
    } else if (msg.type === "search") {
        browser.search.search({ query: msg.query, tabId: sender.tab.id });
    }
});

browser.tabs.onRemoved.addListener(id => {
    if (id === videoTab) {
        videoTab = null;
        port?.postMessage({ type: "gone" });
    }
});
