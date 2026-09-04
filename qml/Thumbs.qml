import QtQuick

// Every page at a glance. Tap one to jump to it; pinch the grid to make the
// thumbnails bigger or smaller.
Rectangle {
    id: sheet

    property bool showing: false
    signal closed()

    color: Theme.background
    visible: opacity > 0
    opacity: showing ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.anim } }

    // Swallow taps so they never reach the reader underneath.
    MouseArea { anchors.fill: parent }

    property real cell: 156

    Rectangle {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: Theme.touch + Theme.pad
        color: Theme.surface

        Text {
            anchors { left: parent.left; leftMargin: Theme.pad + 4; verticalCenter: parent.verticalCenter }
            text: qsTr("%1 pages").arg(Book.count)
            color: Theme.text
            font.pixelSize: Theme.fontMd
            font.weight: Font.DemiBold
        }
        IconButton {
            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
            icon: "close"
            tip: qsTr("Back to reading (Esc)")
            onClicked: sheet.closed()
        }
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 1
            color: Theme.line
        }
    }

    GridView {
        id: grid
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.margins: 8
        clip: true
        model: sheet.showing ? Book.count : 0
        cellWidth: Math.floor(width / Math.max(1, Math.round(width / sheet.cell)))
        cellHeight: Math.round(cellWidth * 1.42)
        cacheBuffer: cellHeight * 3

        onModelChanged: positionViewAtIndex(Book.index, GridView.Center)

        delegate: Item {
            required property int index
            width: grid.cellWidth
            height: grid.cellHeight

            Rectangle {
                anchors.fill: parent
                anchors.margins: 5
                radius: Theme.radius
                color: Theme.surface
                border.width: index === Book.index ? 2 : 1
                border.color: index === Book.index ? Theme.accent2 : Theme.line

                Image {
                    anchors.fill: parent
                    anchors.margins: 4
                    anchors.bottomMargin: 20
                    source: sheet.showing ? "image://thumb/" + Book.generation + "/" + index : ""
                    sourceSize: Qt.size(Math.round(grid.cellWidth * 1.2), Math.round(grid.cellHeight * 1.2))
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    smooth: true
                }

                Text {
                    anchors { bottom: parent.bottom; bottomMargin: 4; horizontalCenter: parent.horizontalCenter }
                    text: index + 1
                    color: index === Book.index ? Theme.accent2 : Theme.textDim
                    font.pixelSize: Theme.fontSm
                }

                TapHandler {
                    onTapped: {
                        Book.index = index;
                        sheet.closed();
                    }
                }
            }
        }
    }

    PinchHandler {
        target: null
        property real startCell: 156
        onActiveChanged: if (active) startCell = sheet.cell
        onActiveScaleChanged: sheet.cell = Math.max(96, Math.min(340, startCell * activeScale))
    }
}
