pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Discos externos conectados: nombre, espacio libre, abrir la carpeta y expulsar
ColumnLayout {
    id: root

    spacing: Tokens.spacing.small
    width: Tokens.sizes.bar.batteryWidth

    StyledText {
        Layout.topMargin: Tokens.padding.medium
        Layout.rightMargin: Tokens.padding.small
        text: Drives.present ? (Drives.list.length === 1 ? "1 disco conectado" : `${Drives.list.length} discos conectados`) : "Ningún disco conectado"
        font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
    }

    Repeater {
        model: ScriptModel {
            values: Drives.list
        }

        RowLayout {
            id: drive

            required property var modelData
            readonly property var mounted: modelData.parts.filter(p => p.mounts.length > 0)
            readonly property real avail: mounted.reduce((a, p) => a + p.avail, 0)
            readonly property real total: mounted.reduce((a, p) => a + p.size, 0)
            readonly property bool busy: Drives.ejecting === modelData.path

            Layout.fillWidth: true
            Layout.rightMargin: Tokens.padding.small
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: drive.modelData.usb ? "usb" : "hard_drive"
                fill: 1
            }

            ColumnLayout {
                Layout.leftMargin: Tokens.spacing.extraSmall
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: drive.modelData.name
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: drive.total > 0 ? `${Drives.formatSize(drive.avail)} libres de ${Drives.formatSize(drive.total)}` : `${Drives.formatSize(drive.modelData.size)} · sin montar`
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }
            }

            IconButton {
                visible: drive.mounted.length > 0
                type: IconButton.Text
                icon: "folder_open"
                onClicked: Drives.open(drive.mounted[0].mounts[0])
            }

            IconButton {
                type: IconButton.Text
                icon: drive.busy ? "hourglass_top" : "eject"
                disabled: drive.busy
                onClicked: Drives.eject(drive.modelData)
            }
        }
    }
}
