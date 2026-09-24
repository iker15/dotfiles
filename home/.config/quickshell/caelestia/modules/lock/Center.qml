import "center"
import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services
import "mochi" as Mochi

ColumnLayout {
    id: root

    required property var lock
    readonly property real centerScale: Math.min(1, (lock.screen?.height ?? 1440) / 1440)
    readonly property int centerWidth: Tokens.sizes.lock.centerWidth * centerScale

    Layout.preferredWidth: centerWidth
    Layout.fillWidth: false
    Layout.fillHeight: true

    spacing: Tokens.spacing.largeIncreased

    Clock {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Tokens.padding.large
        centerScale: root.centerScale
    }

    // Fecha completa en monoespaciada (Sunday, 22 March 2026)
    Text {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: -Tokens.spacing.medium

        text: Time.format("dddd, d MMMM yyyy")
        color: Colours.palette.m3onSurfaceVariant
        renderType: Text.NativeRendering
        font.family: "CaskaydiaCove NF"
        font.pixelSize: Math.round(21 * root.centerScale)
    }

    // Hueco para bajar la foto hacia el centro
    Item {
        Layout.fillHeight: true
    }

    // Mochi (~/.config/quickshell/tamagotchi/LockTile.qml) en el sitio de la foto de perfil: una
    // ficha como las demás que se va transformando en cosas (reloj, candado, pila, sol/luna)
    Mochi.LockTile {
        Layout.alignment: Qt.AlignHCenter
        Layout.bottomMargin: Tokens.spacing.extraLarge * root.centerScale
        implicitWidth: Math.round(root.centerWidth * 0.5)
        implicitHeight: implicitWidth

        pam: root.lock.pam
        failState: root.lock.pam.state === Pam.MaxTries ? 2 : root.lock.pam.state === Pam.Failed || root.lock.pam.state === Pam.Error ? 1 : 0
        capsLock: Hypr.capsLock
        unlocking: root.lock.unlocking
        tileColor: Colours.tPalette.m3surfaceContainer
        radius: Tokens.rounding.extraLarge
    }

    PasswordInput {
        Layout.alignment: Qt.AlignHCenter
        centerScale: Math.max(0.8, root.centerScale)
        centerWidth: root.centerWidth
        lock: root.lock
    }

    StateMessage {
        Layout.fillWidth: true
        pam: root.lock.pam
    }

    Item {
        Layout.fillHeight: true
        Layout.maximumHeight: Tokens.spacing.extraExtraLarge * 3
    }
}
