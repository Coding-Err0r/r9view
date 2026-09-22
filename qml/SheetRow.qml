import QtQuick

// One choice in a sheet: a tall, full-width target with room for a second line
// saying what it actually is. Wider and taller than a menu item on purpose --
// these get tapped with a thumb, often one-handed.
Item {
    id: row

    property string label
    property string detail
    property bool current: false
    signal clicked()

    implicitHeight: row.detail !== "" ? 56 : 48

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: Theme.radius
        color: row.current ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                           : (tap.pressed ? Qt.rgba(1, 1, 1, 0.10) : "transparent")
        border.width: row.current ? 1 : 0
        border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55)
        Behavior on color { ColorAnimation { duration: Theme.anim } }
    }

    // A tick rather than a radio button: this is which one is playing, not a
    // form to be filled in.
    Text {
        id: tick
        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
        width: 18
        text: row.current ? "✓" : ""
        color: Theme.accent2
        font.pixelSize: Theme.fontMd
        font.weight: Font.Bold
    }

    Column {
        anchors {
            left: tick.right; leftMargin: 8
            right: parent.right; rightMargin: 12
            verticalCenter: parent.verticalCenter
        }
        spacing: 2

        Text {
            width: parent.width
            text: row.label
            color: Theme.text
            font.pixelSize: Theme.fontMd
            elide: Text.ElideMiddle
        }
        Text {
            width: parent.width
            visible: row.detail !== ""
            text: row.detail
            color: Theme.textDim
            font.pixelSize: Theme.fontSm
            elide: Text.ElideMiddle
        }
    }

    TapHandler {
        id: tap
        onTapped: row.clicked()
    }
}
