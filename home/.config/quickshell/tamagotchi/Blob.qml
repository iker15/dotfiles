import QtQuick

// Mochi: burbuja negra con ojos blancos. Mira hacia (lookX, lookY) en [-1, 1].
Item {
    id: root

    property string mood: "idle"   // idle, listening, thinking, working, talking, happy, sad
    property bool dragging: false
    property real lookX: 0
    property real lookY: 0
    property bool blinking: false
    property real bob: 0

    implicitWidth: 72
    implicitHeight: 72

    SequentialAnimation on bob {
        loops: Animation.Infinite
        running: !root.dragging

        NumberAnimation {
            to: root.mood === "working" ? 1 : 0.6
            duration: root.mood === "working" ? 220 : 1100
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            to: 0
            duration: root.mood === "working" ? 220 : 1100
            easing.type: Easing.InOutSine
        }
    }

    Rectangle {
        id: body

        anchors.centerIn: parent
        width: 64 * (root.dragging ? 0.92 : 1 + root.bob * 0.04)
        height: 58 * (root.dragging ? 1.12 : 1 - root.bob * 0.04)
        radius: width / 2
        color: "#0b0b0b"
        // Borde muy sutil para que se vea sobre fondos oscuros
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)

        Behavior on width {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutBack
            }
        }
        Behavior on height {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutBack
            }
        }

        // Ojos
        Repeater {
            model: [-1, 1]

            Item {
                id: eye

                required property int modelData

                readonly property bool happy: root.mood === "happy"
                readonly property real lx: root.mood === "thinking" ? 0.6 : root.mood === "listening" ? 0 : root.lookX
                readonly property real ly: root.mood === "thinking" ? -0.8 : root.mood === "listening" ? -0.5 : root.lookY

                x: body.width / 2 + modelData * 12 - width / 2 + lx * 6
                y: body.height * 0.42 - height / 2 + ly * 5
                width: 12
                height: 18

                Behavior on x {
                    NumberAnimation {
                        duration: 120
                    }
                }
                Behavior on y {
                    NumberAnimation {
                        duration: 120
                    }
                }

                Rectangle {
                    visible: !eye.happy
                    anchors.centerIn: parent
                    width: root.dragging ? 12 : 10
                    height: root.blinking ? 2 : root.dragging ? 16 : root.mood === "working" ? 7 : root.mood === "sad" ? 9 : 15
                    radius: width / 2
                    color: "white"

                    Behavior on height {
                        NumberAnimation {
                            duration: 70
                        }
                    }
                }

                // ^ ^
                Text {
                    visible: eye.happy
                    anchors.centerIn: parent
                    text: "^"
                    font.pixelSize: 22
                    font.bold: true
                    color: "white"
                }
            }
        }

        // Boca pequeña solo al hablar
        Rectangle {
            visible: root.mood === "talking"
            anchors.horizontalCenter: parent.horizontalCenter
            y: body.height * 0.68
            width: 7
            radius: 4
            color: "white"

            SequentialAnimation on height {
                loops: Animation.Infinite
                running: root.mood === "talking"

                NumberAnimation {
                    to: 6
                    duration: 120
                }
                NumberAnimation {
                    to: 2
                    duration: 120
                }
            }
        }
    }

    // Puntitos al pensar / trabajar
    Row {
        visible: root.mood === "thinking" || root.mood === "working"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: body.top
        anchors.bottomMargin: 2
        spacing: 4

        Repeater {
            model: 3

            Rectangle {
                id: dot

                required property int index

                width: 5
                height: 5
                radius: 3
                color: "white"
                opacity: 0.2

                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    running: root.mood === "thinking" || root.mood === "working"

                    PauseAnimation {
                        duration: dot.index * 150
                    }
                    NumberAnimation {
                        to: 1
                        duration: 220
                    }
                    NumberAnimation {
                        to: 0.2
                        duration: 420
                    }
                    PauseAnimation {
                        duration: (2 - dot.index) * 150
                    }
                }
            }
        }
    }

    Timer {
        running: root.visible
        repeat: true
        interval: 3000
        onTriggered: {
            root.blinking = true;
            unblink.restart();
            interval = 2500 + Math.random() * 3000;
        }
    }

    Timer {
        id: unblink

        interval: 120
        onTriggered: root.blinking = false
    }
}
