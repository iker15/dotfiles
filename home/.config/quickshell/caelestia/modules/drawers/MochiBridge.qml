import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.services

// Para Mochi (~/.config/quickshell/tamagotchi): publica dónde están los paneles abiertos de esta
// pantalla (para que se aparte y no se quede debajo de ellos), la notificación nueva (para ir a
// mirarla) y si están activos No molestar y la cafeína. Escribe
// $XDG_RUNTIME_DIR/caelestia-panels-<pantalla>.json = {"rects": [[x, y, w, h], ...], "notif": {id,
// urgent, rect} | null, "dnd": bool, "caffeine": bool} (coordenadas de la pantalla, tamaño final
// del panel), solo cuando algo cambia.
Item {
    id: root

    required property Panels panels
    required property var bar
    required property var win

    readonly property real border: win.borderThickness

    // Abierto = asomado más de un 5 % (offsetScale: 1 cerrado → 0 abierto)
    function opened(p: Item, off: real): bool {
        return p.visible && p.width > 2 && p.height > 2 && (1 - (off ?? 0)) > 0.05;
    }

    readonly property string json: {
        const P = panels, W = win.width, H = win.height, bw = bar.implicitWidth;
        const rects = [];
        const add = (x, y, w, h) => rects.push([Math.round(x), Math.round(y), Math.round(w), Math.round(h)]);
        if (opened(P.dashboard, P.dashboard.offsetScale))
            add(P.dashboard.x + bw, 0, P.dashboard.width, P.dashboard.height + border);
        if (opened(P.launcher, P.launcher.offsetScale))
            add(P.launcher.x + bw, H - P.launcher.height - border, P.launcher.width, P.launcher.height + border);
        if (opened(P.sidebar, P.sidebar.offsetScale))
            add(W - P.sidebar.width - border, P.sidebar.y + border, P.sidebar.width + border, P.sidebar.height);
        if (opened(P.session, P.session.offsetScale))
            add(W - P.sessionWrapper.anchors.rightMargin - P.session.width - border, P.sessionWrapper.y + border, P.session.width + border, P.session.height);
        if (opened(P.osd, P.osd.offsetScale))
            add(W - P.osdWrapper.anchors.rightMargin - P.osd.width - border, P.osdWrapper.y + border, P.osd.width + border, P.osd.height);
        if (opened(P.notifications, 0))
            add(P.notifications.x + bw, 0, P.notifications.width, P.notifications.height + border);
        if (opened(P.utilities, P.utilities.offsetScale))
            add(P.utilities.x + bw, H - P.utilities.height - border, P.utilities.width, P.utilities.height + border);
        if (opened(P.popoutsWrapper, P.popoutsWrapper.offsetScale))
            add(P.popoutsWrapper.x + bw, P.popoutsWrapper.y + border, P.popoutsWrapper.width, P.popoutsWrapper.height);
        // La notificación emergente más reciente (y dónde se ve)
        const pops = Notifs.popups, last = pops.length ? pops[pops.length - 1] : null;
        const notif = last && opened(P.notifications, 0) ? {
            id: `${new Date(last.time).getTime()}|${last.summary}`,   // ("id" no se puede leer en QML)
            urgent: last.urgency === NotificationUrgency.Critical,
            rect: [Math.round(P.notifications.x + bw), 0, Math.round(P.notifications.width), Math.round(P.notifications.height + border)]
        } : null;
        return JSON.stringify({
            rects: rects,
            notif: notif,
            dnd: Notifs.dnd,
            caffeine: IdleInhibitor.enabled
        });
    }

    onJsonChanged: debounce.restart()

    Timer {
        id: debounce

        interval: 60
        onTriggered: file.setText(root.json)
    }

    FileView {
        id: file

        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/caelestia-panels-${root.win.screen?.name ?? "x"}.json`
        atomicWrites: true
        preload: false
        printErrors: false
        Component.onCompleted: debounce.restart()
    }
}
