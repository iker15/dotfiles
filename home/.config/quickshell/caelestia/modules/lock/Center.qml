import "center"
import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

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

    ProfilePic {
        Layout.alignment: Qt.AlignHCenter
        Layout.bottomMargin: Tokens.spacing.extraLarge * root.centerScale
        centerWidth: root.centerWidth
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
