import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// Minimalista: tiempo a la izquierda, recursos + batería a la derecha, los dos
// cuadros con la misma altura y centrados en vertical junto al bloque central
RowLayout {
    id: root

    required property var lock

    spacing: Tokens.spacing.largeIncreased * 2

    WeatherInfo {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.preferredHeight: resources.implicitHeight
        Layout.alignment: Qt.AlignVCenter
        Layout.leftMargin: Tokens.padding.extraLarge
        rootHeight: root.height
    }

    Center {
        lock: root.lock
        tileHeight: resources.implicitHeight   // (Mochi, alineado con las otras fichas)
    }

    Resources {
        id: resources

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignVCenter
        Layout.rightMargin: Tokens.padding.extraLarge
    }
}
