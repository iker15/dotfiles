pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Colores del esquema actual de Caelestia (cambian con el wallpaper)
Singleton {
    id: root

    property var scheme: ({})
    property string mode: "dark"

    // Material de la barra de Caelestia: superficie translúcida (transparency.base = 0.85,
    // 0.1 menos en tema claro) con desenfoque de Hyprland y sombra
    readonly property bool light: mode === "light"
    readonly property real surfaceAlpha: 0.85 - (light ? 0.1 : 0)
    readonly property color shadow: c("shadow", "000000")

    function c(name: string, fallback: string): color {
        return "#" + (root.scheme[name] ?? fallback);
    }

    readonly property color primary: c("primary", "d0c88b")
    readonly property color onPrimary: c("onPrimary", "464112")
    readonly property color primaryContainer: c("primaryContainer", "595422")
    readonly property color onPrimaryContainer: c("onPrimaryContainer", "ede5a6")
    readonly property color tertiary: c("tertiary", "ffddb4")
    readonly property color error: c("error", "f97758")
    readonly property color surface: c("surface", "0f0e08")
    readonly property color surfaceContainer: c("surfaceContainer", "1b1a10")
    readonly property color surfaceContainerHigh: c("surfaceContainerHigh", "212015")
    readonly property color surfaceContainerHighest: c("surfaceContainerHighest", "28261a")
    readonly property color onSurface: c("onSurface", "ebe6d2")
    readonly property color onSurfaceVariant: c("onSurfaceVariant", "afab99")
    readonly property color outlineVariant: c("outlineVariant", "4b483a")

    readonly property string font: "Rubik"
    readonly property string mono: "CaskaydiaCove NF"
    readonly property string icons: "Material Symbols Rounded"

    FileView {
        path: Quickshell.env("HOME") + "/.local/state/caelestia/scheme.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.scheme = d.colours ?? {};
                root.mode = d.mode ?? "dark";
            } catch (e) {}
        }
    }
}
