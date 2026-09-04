import QtQuick

// The controls, in one screen. Reachable from the ? button or the ? key.
Rectangle {
    id: sheet

    property bool showing: false
    signal closed()

    color: Qt.rgba(0, 0, 0, 0.82)
    visible: opacity > 0
    opacity: showing ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.anim } }

    TapHandler { onTapped: sheet.closed() }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 620)
        height: Math.min(parent.height - 40, content.implicitHeight + 2 * Theme.pad * 2)
        radius: 18
        color: Theme.surface
        border.width: 1
        border.color: Theme.line

        TapHandler {} // keep taps inside the card from closing it

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: Theme.pad * 2
            contentHeight: content.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: content
                width: flick.width
                spacing: 14

                Text {
                    text: qsTr("Controls")
                    color: Theme.text
                    font.pixelSize: Theme.fontLg
                    font.weight: Font.Bold
                }

                Repeater {
                    model: [
                        { head: qsTr("Touch") },
                        { key: qsTr("swipe"), what: qsTr("turn the page") },
                        { key: qsTr("tap left / right edge"), what: qsTr("previous / next page") },
                        { key: qsTr("tap the middle"), what: qsTr("show or hide the bars") },
                        { key: qsTr("pinch"), what: qsTr("zoom in and out") },
                        { key: qsTr("drag while zoomed"), what: qsTr("pan around the page") },
                        { key: qsTr("double tap"), what: qsTr("zoom to that spot, and back") },
                        { head: qsTr("Keyboard") },
                        { key: "←  →", what: qsTr("previous / next page") },
                        { key: "↑  ↓", what: qsTr("zoom in / out") },
                        { key: qsTr("Space / Backspace"), what: qsTr("next / previous page") },
                        { key: "Home / End", what: qsTr("first / last page") },
                        { key: "0", what: qsTr("reset zoom") },
                        { key: "F", what: qsTr("cycle fit: page, width, height, actual size") },
                        { key: "D", what: qsTr("flip reading order (manga)") },
                        { key: "G", what: qsTr("all pages") },
                        { key: "O", what: qsTr("open something else") },
                        { key: "F11", what: qsTr("fullscreen") },
                        { key: "Esc", what: qsTr("close what is open, then quit") }
                    ]
                    delegate: Item {
                        required property var modelData
                        width: content.width
                        height: modelData.head ? 26 : 24

                        Text {
                            visible: !!modelData.head
                            anchors.bottom: parent.bottom
                            text: modelData.head || ""
                            color: Theme.accent2
                            font.pixelSize: Theme.fontSm
                            font.weight: Font.Bold
                        }
                        Text {
                            visible: !modelData.head
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width * 0.42
                            text: modelData.key || ""
                            color: Theme.text
                            font.pixelSize: Theme.fontMd
                            font.family: "monospace"
                            elide: Text.ElideRight
                        }
                        Text {
                            visible: !modelData.head
                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: parent.width * 0.44; right: parent.right }
                            text: modelData.what || ""
                            color: Theme.textDim
                            font.pixelSize: Theme.fontMd
                            elide: Text.ElideRight
                        }
                    }
                }

                // ---- about ------------------------------------------------
                Item { width: 1; height: 6 }

                Rectangle {
                    width: content.width
                    height: 1
                    color: Theme.line
                }

                Text {
                    text: qsTr("About")
                    color: Theme.accent2
                    font.pixelSize: Theme.fontSm
                    font.weight: Font.Bold
                }

                Row {
                    spacing: 12

                    Image {
                        source: "icons/r9view.svg"
                        sourceSize: Qt.size(40, 40)
                        smooth: true
                    }

                    Column {
                        spacing: 2

                        Text {
                            text: "r9view " + Qt.application.version
                            color: Theme.text
                            font.pixelSize: Theme.fontMd
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: qsTr("A touch-first image and comic viewer.")
                            color: Theme.textDim
                            font.pixelSize: Theme.fontSm
                        }
                        Text {
                            text: qsTr("Built by Rhineul Islam")
                            color: Theme.text
                            font.pixelSize: Theme.fontSm
                        }
                        Text {
                            text: "r9xcode@gmail.com"
                            color: Theme.accent2
                            font.pixelSize: Theme.fontSm
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: Qt.openUrlExternally("mailto:r9xcode@gmail.com") }
                        }
                        Text {
                            text: "github.com/Coding-Err0r/r9view"
                            color: Theme.accent2
                            font.pixelSize: Theme.fontSm
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: Qt.openUrlExternally("https://github.com/Coding-Err0r/r9view") }
                        }
                    }
                }
            }
        }
    }
}
