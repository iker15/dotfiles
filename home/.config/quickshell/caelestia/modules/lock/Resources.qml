pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.services
import qs.utils

// Recursos en cuadrícula 2x2 de arcos circulares con icono: CPU, temperatura,
// memoria y disco, con la batería debajo
StyledRect {
    id: root

    implicitHeight: layout.implicitHeight + layout.anchors.margins * 2
    radius: Tokens.rounding.extraLarge
    color: Colours.tPalette.m3surfaceContainer

    ServiceRef {
        service: Cpu
    }

    ServiceRef {
        service: Memory
    }

    ServiceRef {
        service: Storage
    }

    GridLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.large * 1.5
        columns: 2
        rowSpacing: Tokens.spacing.large * 1.5
        columnSpacing: Tokens.spacing.large * 1.5

        Resource {
            icon: "memory"
            value: Cpu.percentage
        }

        Resource {
            icon: "device_thermostat"
            value: Cpu.temperature / 100
            fgColour: Cpu.temperature > 90 ? Colours.palette.m3error : Colours.palette.m3primary
        }

        Resource {
            icon: "memory_alt"
            value: Memory.percentage
        }

        Resource {
            icon: "hard_disk"
            value: Storage.percentage
        }

        // Batería: icono, barra y porcentaje a lo ancho de las dos columnas
        RowLayout {
            id: batt

            readonly property real pct: UPower.displayDevice.percentage
            readonly property bool charging: [UPowerDeviceState.Charging, UPowerDeviceState.FullyCharged, UPowerDeviceState.PendingCharge].includes(UPower.displayDevice.state)
            readonly property color colour: !charging && pct <= 0.2 ? Colours.palette.m3error : Colours.palette.m3primary

            Layout.columnSpan: 2
            Layout.fillWidth: true
            visible: UPower.displayDevice.isLaptopBattery
            spacing: Tokens.spacing.medium

            MaterialIcon {
                text: Icons.getBatteryIcon(batt.pct, batt.charging)
                font: Tokens.font.icon.large
                color: batt.colour
                fill: 1
            }

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: Math.max(6, Math.round(Tokens.font.body.medium.pointSize * 0.7))
                radius: height / 2
                color: Colours.tPalette.m3surfaceContainerHighest

                StyledRect {
                    width: parent.width * Math.max(0, Math.min(1, batt.pct))
                    height: parent.height
                    radius: parent.radius
                    color: batt.colour

                    Behavior on width {
                        Anim {}
                    }
                }
            }

            StyledText {
                text: `${Math.round(batt.pct * 100)}%${batt.charging ? " ⚡" : ""}`
                color: Colours.palette.m3onSurfaceVariant
            }
        }
    }

    component Resource: Item {
        id: res

        required property string icon
        property real value
        property color fgColour: Colours.palette.m3primary

        Layout.fillWidth: true
        implicitHeight: width * 0.62

        CircularProgress {
            id: arc

            anchors.centerIn: parent
            width: parent.height
            height: parent.height
            value: res.value
            startAngle: 120
            sweepAngle: 300
            strokeWidth: Math.max(4, Math.round(res.height / 16))
            fgColour: res.fgColour
            bgColour: Colours.tPalette.m3surfaceContainerHighest

            Behavior on clampedVal {
                Anim {}
            }
        }

        MaterialIcon {
            anchors.centerIn: parent
            text: res.icon
            font: Tokens.font.icon.large
            color: Colours.palette.m3onSurfaceVariant
        }
    }
}
