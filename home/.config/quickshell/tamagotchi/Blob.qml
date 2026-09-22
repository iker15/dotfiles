import QtQuick

// Mochi: un blob con cara que cambia según el estado del cerebro
Item {
    id: root

    property string mood: "idle"
    property bool blinking: false

    implicitWidth: 96
    implicitHeight: 96

    // Sombra en el suelo que se encoge cuando el blob sube
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: body.width * (0.75 - bob.offset / 60)
        height: 6
        radius: 3
        color: Qt.alpha("black", 0.35)
    }

    Item {
        id: bob

        property real offset: 0

        anchors.fill: parent

        SequentialAnimation on offset {
            loops: Animation.Infinite
            running: true

            NumberAnimation {
                to: root.mood === "working" || root.mood === "talking" ? 7 : 4
                duration: root.mood === "working" ? 260 : 900
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                to: 0
                duration: root.mood === "working" ? 260 : 900
                easing.type: Easing.InOutSine
            }
        }

        Rectangle {
            id: body

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 5 + bob.offset
            width: 78
            height: 66 + bob.offset * 0.6
            radius: 34
            color: root.mood === "sad" ? Qt.tint(Theme.primary, Qt.alpha(Theme.error, 0.45)) : Theme.primary

            Behavior on color {
                ColorAnimation {
                    duration: 400
                }
            }

            // Brillo
            Rectangle {
                x: 14
                y: 10
                width: 16
                height: 9
                radius: 5
                rotation: -25
                color: Qt.alpha("white", 0.35)
            }

            // Mejillas
            Repeater {
                model: [-1, 1]

                Rectangle {
                    required property int modelData

                    x: body.width / 2 + modelData * 24 - width / 2
                    y: body.height * 0.58
                    width: 13
                    height: 7
                    radius: 4
                    color: Qt.alpha(Theme.error, root.mood === "happy" ? 0.7 : 0.4)
                }
            }

            // Ojos
            Repeater {
                model: [-1, 1]

                Item {
                    id: eye

                    required property int modelData

                    readonly property bool arc: root.mood === "happy"

                    x: body.width / 2 + modelData * 15 - width / 2 + (root.mood === "thinking" ? -4 : 0)
                    y: body.height * 0.34 + (root.mood === "thinking" ? -5 : 0)
                    width: 10
                    height: 14

                    Behavior on x {
                        NumberAnimation {
                            duration: 250
                        }
                    }
                    Behavior on y {
                        NumberAnimation {
                            duration: 250
                        }
                    }

                    Rectangle {
                        visible: !eye.arc
                        anchors.centerIn: parent
                        width: 9
                        height: root.blinking ? 2 : root.mood === "working" ? 6 : root.mood === "sad" ? 10 : 13
                        radius: width / 2
                        color: Theme.onPrimary

                        Behavior on height {
                            NumberAnimation {
                                duration: 70
                            }
                        }

                        // Brillito del ojo
                        Rectangle {
                            visible: parent.height > 8
                            x: 5
                            y: 2
                            width: 3
                            height: 3
                            radius: 2
                            color: Qt.alpha("white", 0.8)
                        }
                    }

                    // Ojos felices ^ ^
                    Text {
                        visible: eye.arc
                        anchors.centerIn: parent
                        text: "^"
                        font.pixelSize: 20
                        font.bold: true
                        color: Theme.onPrimary
                    }
                }
            }

            // Boca
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                y: body.height * 0.6
                width: 16
                height: 10

                Text {
                    visible: root.mood !== "talking" && root.mood !== "sad"
                    anchors.centerIn: parent
                    text: "ω"
                    font.pixelSize: 13
                    color: Theme.onPrimary
                }

                Text {
                    visible: root.mood === "sad"
                    anchors.centerIn: parent
                    text: "︵"
                    font.pixelSize: 12
                    color: Theme.onPrimary
                }

                Rectangle {
                    id: mouth

                    visible: root.mood === "talking"
                    anchors.centerIn: parent
                    width: 9
                    radius: 4
                    color: Theme.onPrimary

                    SequentialAnimation on height {
                        loops: Animation.Infinite
                        running: root.mood === "talking"

                        NumberAnimation {
                            to: 8
                            duration: 120
                        }
                        NumberAnimation {
                            to: 3
                            duration: 120
                        }
                    }
                }
            }
        }

        // Burbuja de pensamiento
        Row {
            visible: root.mood === "thinking"
            anchors.right: body.right
            anchors.rightMargin: -10
            anchors.bottom: body.top
            anchors.bottomMargin: -4
            spacing: 3

            Repeater {
                model: 3

                Rectangle {
                    id: dot

                    required property int index

                    width: 6
                    height: 6
                    radius: 3
                    color: Theme.onSurfaceVariant

                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: root.mood === "thinking"

                        PauseAnimation {
                            duration: dot.index * 150
                        }
                        NumberAnimation {
                            to: 1
                            duration: 250
                        }
                        NumberAnimation {
                            to: 0.2
                            duration: 450
                        }
                    }
                }
            }
        }

        // Engranaje cuando usa herramientas
        Text {
            visible: root.mood === "working"
            anchors.right: body.right
            anchors.rightMargin: -8
            anchors.top: body.top
            anchors.topMargin: -10
            text: "settings"
            font.family: Theme.icons
            font.pixelSize: 20
            color: Theme.tertiary

            RotationAnimation on rotation {
                loops: Animation.Infinite
                running: root.mood === "working"
                from: 0
                to: 360
                duration: 1600
            }
        }
    }

    // Parpadeo aleatorio
    Timer {
        running: root.visible
        repeat: true
        interval: 2800 + Math.random() * 2500
        onTriggered: {
            root.blinking = true;
            unblink.restart();
            interval = 2800 + Math.random() * 2500;
        }
    }

    Timer {
        id: unblink

        interval: 130
        onTriggered: root.blinking = false
    }
}
