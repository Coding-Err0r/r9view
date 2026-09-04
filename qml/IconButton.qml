import QtQuick
import QtQuick.Controls.Basic

// A 44px square icon button. Flat until touched, then a soft fill -- enough
// feedback to feel pressed on a touchscreen without adding chrome.
Item {
    id: root

    property string icon
    property string tip
    property bool checked: false
    property bool enabledWhen: true
    signal clicked()

    implicitWidth: Theme.touch
    implicitHeight: Theme.touch
    opacity: root.enabledWhen ? 1 : 0.35

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: Theme.radius
        color: root.checked ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.28)
                            : (tap.pressed || hover.hovered ? Qt.rgba(1, 1, 1, 0.10) : "transparent")
        border.width: root.checked ? 1 : 0
        border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55)
        Behavior on color { ColorAnimation { duration: Theme.anim } }
    }

    Image {
        anchors.centerIn: parent
        source: "icons/" + root.icon + ".svg"
        sourceSize: Qt.size(22, 22)
        opacity: root.checked ? 1 : 0.86
        smooth: true
    }

    HoverHandler { id: hover }
    TapHandler {
        id: tap
        enabled: root.enabledWhen
        onTapped: root.clicked()
    }

    ToolTip.visible: hover.hovered && root.tip !== ""
    ToolTip.text: root.tip
    ToolTip.delay: 600
}
