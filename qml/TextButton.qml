import QtQuick
import QtQuick.Controls.Basic

// A labelled pill. Used where an icon would be a guessing game: the fit mode and
// the reading direction both change something you cannot see at a glance, so
// they say what they are and the label changes when you press them.
Item {
    id: root

    property string label
    property string tip
    property bool checked: false
    signal clicked()

    implicitWidth: Math.max(Theme.touch, text.implicitWidth + 22)
    implicitHeight: Theme.touch

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        radius: Theme.radius
        color: root.checked ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.28)
                            : (tap.pressed || hover.hovered ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05))
        border.width: 1
        border.color: root.checked ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55) : Theme.line
        Behavior on color { ColorAnimation { duration: Theme.anim } }
    }

    Text {
        id: text
        anchors.centerIn: parent
        text: root.label
        color: Theme.text
        font.pixelSize: Theme.fontSm
        font.weight: Font.DemiBold
        font.family: "monospace"
    }

    HoverHandler { id: hover }
    TapHandler { id: tap; onTapped: root.clicked() }

    ToolTip.visible: hover.hovered && root.tip !== ""
    ToolTip.text: root.tip
    ToolTip.delay: 600
}
