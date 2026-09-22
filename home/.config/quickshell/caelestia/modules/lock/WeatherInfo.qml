import "weather"
import QtQuick
import Caelestia.Config
import qs.components
import qs.services

StyledRect {
    id: root

    required property int rootHeight
    readonly property bool showForecast: rootHeight >= Tokens.sizes.lock.showForecastHeight

    implicitHeight: {
        const base = brief.implicitHeight + brief.anchors.topMargin;
        if (showForecast)
            return base + Tokens.spacing.largeIncreased + forecast.implicitHeight + forecast.anchors.margins;
        return base + brief.anchors.topMargin;
    }
    radius: Tokens.rounding.extraLarge  // igual que el de recursos
    color: Colours.tPalette.m3surfaceContainer

    Timer {
        running: true
        triggeredOnStart: true
        repeat: true
        interval: 900000 // 15 minutes
        onTriggered: Weather.reload()
    }

    BriefInfo {
        id: brief

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: root.showForecast ? parent.top : undefined
        anchors.topMargin: Tokens.padding.extraLarge
        // Sin previsión: centrado en vertical (el cuadro puede ser más alto que el contenido)
        anchors.verticalCenter: root.showForecast ? undefined : parent.verticalCenter

        rootHeight: root.rootHeight
    }

    Loader {
        id: forecast

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.padding.large

        active: root.showForecast
        asynchronous: true

        sourceComponent: Forecast {}
    }
}
