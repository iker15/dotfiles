import QtQuick
import qs.services

// Hora en una sola línea (23:27), Rubik en negrita
Text {
    id: root

    required property real centerScale

    text: Time.format("hh:mm")
    color: Colours.palette.m3onSurfaceVariant
    renderType: Text.NativeRendering
    font.family: "Rubik"
    font.weight: Font.Bold
    font.pixelSize: Math.round(118 * root.centerScale)
    font.letterSpacing: 4 * root.centerScale

    Behavior on color {
        ColorAnimation {
            duration: 400
        }
    }
}
