import QtQuick
import qs.components
import qs.services

// Icono de disco externo: solo ocupa sitio en la barra si hay alguno conectado
Item {
    id: root

    required property color colour

    property real shown: Drives.present ? icon.implicitHeight : 0

    implicitWidth: icon.implicitWidth
    implicitHeight: Math.round(shown)

    Behavior on shown {
        Anim {
            type: Anim.SlowEffects
        }
    }

    MaterialIcon {
        id: icon

        anchors.centerIn: parent

        scale: Drives.present ? 1 : 0.5
        opacity: Drives.present ? 1 : 0

        animate: true
        text: Drives.list.some(d => d.usb) ? "usb" : "hard_drive"
        color: root.colour
        fill: 1

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Behavior on scale {
            Anim {}
        }
    }
}
