import QtQuick

// What you see with nothing open: the two ways in, and whatever you read last.
Item {
    id: welcome

    signal openFolder()
    signal openFile()

    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 520)
        spacing: 18

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            source: "icons/r9view.svg"
            sourceSize: Qt.size(96, 96)
            smooth: true
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "r9view"
            color: Theme.text
            font.pixelSize: 30
            font.weight: Font.Bold
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: qsTr("Open a comic archive or a folder of images.\nDrop one on this window, or pick one below.")
            color: Theme.textDim
            font.pixelSize: Theme.fontMd
            lineHeight: 1.35
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12

            Repeater {
                model: [
                    { label: qsTr("Open archive"), icon: "archive", file: true },
                    { label: qsTr("Open folder"), icon: "folder", file: false }
                ]
                delegate: Rectangle {
                    required property var modelData
                    width: 168
                    height: 52
                    radius: Theme.radius
                    color: tap.pressed ? Theme.surfaceHigh : Theme.surface
                    border.width: 1
                    border.color: Theme.line
                    Behavior on color { ColorAnimation { duration: Theme.anim } }

                    Row {
                        anchors.centerIn: parent
                        spacing: 10
                        Image {
                            anchors.verticalCenter: parent.verticalCenter
                            source: "icons/" + modelData.icon + ".svg"
                            sourceSize: Qt.size(20, 20)
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            color: Theme.text
                            font.pixelSize: Theme.fontMd
                        }
                    }
                    TapHandler {
                        id: tap
                        onTapped: modelData.file ? welcome.openFile() : welcome.openFolder()
                    }
                }
            }
        }

        // ---- recent -------------------------------------------------------
        Column {
            width: parent.width
            spacing: 6
            visible: Book.recent.length > 0

            Item { width: 1; height: 8 }

            Text {
                text: qsTr("Recent")
                color: Theme.textDim
                font.pixelSize: Theme.fontSm
                font.weight: Font.DemiBold
            }

            Repeater {
                model: Book.recent.slice(0, 6)
                delegate: Rectangle {
                    required property string modelData
                    width: parent.width
                    height: 38
                    radius: 8
                    color: rtap.pressed ? Theme.surfaceHigh : "transparent"

                    Text {
                        anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        text: Book.shortName(modelData)
                        color: Theme.text
                        font.pixelSize: Theme.fontMd
                        elide: Text.ElideMiddle
                    }
                    TapHandler {
                        id: rtap
                        onTapped: Book.openPath(modelData)
                    }
                }
            }
        }
    }
}
