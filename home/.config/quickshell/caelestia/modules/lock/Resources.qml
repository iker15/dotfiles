pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.services

// Recursos en cuadrícula 2x2 de arcos circulares con icono: CPU, temperatura,
// memoria y disco
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
