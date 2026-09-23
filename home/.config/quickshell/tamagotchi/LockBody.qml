import QtQuick

// Cuerpo de Mochi cuando está pegado a la tarjeta del bloqueo. Va DENTRO de la capa de la
// tarjeta (caelestia/modules/lock/LockSurface.qml, junto a lockBg): así la tarjeta y Mochi son
// una sola pieza del mismo material, con una única sombra, y la unión no se nota.
ShaderEffect {
    id: root

    required property var pet      // el LockPet
    required property Item cardItem   // la tarjeta (lockBg, hermana de este item)

    readonly property real half: 140
    readonly property point c: parent.mapFromItem(pet, pet.cx, pet.cy)

    visible: pet.glued
    x: c.x - half
    y: c.y - half
    width: 2 * half
    height: 2 * half

    property vector2d size: Qt.vector2d(width, height)
    property vector4d body: Qt.vector4d(half, half, pet.blob.bodyRx, pet.blob.bodyRy)
    property vector4d mass: Qt.vector4d(half + pet.blob.massX - pet.blob.width / 2, half + pet.blob.massY - pet.blob.height / 2, pet.blob.massR, 0)
    property vector4d tail: Qt.vector4d(half + pet.blob.tailX - pet.blob.width / 2, half + pet.blob.tailY - pet.blob.height / 2, pet.blob.tailR, 0)
    property vector4d wobA: pet.blob.wobA
    property vector4d wobB: pet.blob.wobB
    property vector4d frame: Qt.vector4d(-1e5, -1e5, 1e5, 1e5)   // sin marco
    property color color: cardItem.color
    property vector4d view: Qt.vector4d(0, 0, 1, 0)
    property var edge: pet.noEdgeTex
    property real blobK: 26
    property real frameK: pet.smoothing
    property real bandOnly: 0
    property vector4d shape: pet.shapeVec
    property vector4d card: Qt.vector4d(cardItem.x - x, cardItem.y - y, cardItem.width, cardItem.height)
    property real cardR: cardItem.radius
    property real cardOn: 2      // se pinta la unión entera (misma capa)
    property real baseAlpha: 1

    fragmentShader: Qt.resolvedUrl("mochi.frag.qsb")
}
