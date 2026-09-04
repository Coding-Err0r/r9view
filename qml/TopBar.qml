import QtQuick

// Auto-hiding header: what is open, where we are in it, and the controls that
// change how it is displayed.
Rectangle {
    id: bar

    signal openRequested()
    signal backRequested()
    signal gridRequested()
    signal helpRequested()
    signal fullscreenToggled()
    property bool fullscreen: false

    height: Theme.touch + Theme.pad
    color: Theme.overlay

    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1
        color: Theme.line
    }

    Row {
        id: leftGroup
        anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
        spacing: 2

        IconButton {
            icon: "left"
            tip: qsTr("Back to the start screen (Esc)")
            enabledWhen: Book.ready
            onClicked: bar.backRequested()
        }
        IconButton {
            icon: "folder"
            tip: qsTr("Open… (O)")
            onClicked: bar.openRequested()
        }
        IconButton {
            icon: "grid"
            tip: qsTr("All pages (G)")
            enabledWhen: Book.ready
            onClicked: bar.gridRequested()
        }
    }

    Column {
        anchors {
            left: leftGroup.right; leftMargin: Theme.pad
            right: rightGroup.left; rightMargin: Theme.pad
            verticalCenter: parent.verticalCenter
        }
        spacing: 1

        Text {
            width: parent.width
            text: Book.ready ? Book.title : qsTr("r9view")
            color: Theme.text
            font.pixelSize: Theme.fontMd
            font.weight: Font.DemiBold
            elide: Text.ElideMiddle
        }
        Text {
            width: parent.width
            visible: Book.ready
            text: Book.pageName + "   ·   " + qsTr("%1 of %2").arg(Book.index + 1).arg(Book.count)
            color: Theme.textDim
            font.pixelSize: Theme.fontSm
            elide: Text.ElideMiddle
        }
    }

    Row {
        id: rightGroup
        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
        spacing: 2

        TextButton {
            visible: Book.ready
            label: ["FIT", "WIDTH", "HEIGHT", "1:1"][Book.fitMode]
            tip: qsTr("How the page is sized — tap to cycle (F)")
            onClicked: Book.fitMode = (Book.fitMode + 1) % 4
        }
        TextButton {
            visible: Book.ready
            label: Book.rightToLeft ? "R←L" : "L→R"
            checked: Book.rightToLeft
            tip: qsTr("Reading direction — tap for manga order (D)")
            onClicked: Book.rightToLeft = !Book.rightToLeft
        }
        IconButton {
            icon: bar.fullscreen ? "collapse" : "expand"
            tip: qsTr("Fullscreen (F11)")
            onClicked: bar.fullscreenToggled()
        }
        IconButton {
            icon: "help"
            tip: qsTr("Controls (?)")
            onClicked: bar.helpRequested()
        }
    }
}
