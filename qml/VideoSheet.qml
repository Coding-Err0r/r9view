import QtQuick
import R9View

// Audio, subtitles and speed, in one full-screen panel.
//
// A sheet rather than a menu, for the same reason Thumbs.qml is one: a dropdown
// is a mouse control. Every row here is a 52px target with its language and its
// source written out, because "Track 2" and "Track 3" is not a choice anybody
// can make -- and with subtitles pulled out of nested Subs/ folders, two of them
// really can both be English from different DVD masters.
Rectangle {
    id: sheet

    property bool showing: false
    // Which section to open on: "tracks" or "speed".
    property string section: "tracks"
    signal closed()

    color: Theme.background
    visible: opacity > 0
    opacity: showing ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.anim } }

    // Swallow taps so nothing reaches the video underneath.
    MouseArea { anchors.fill: parent }

    readonly property var speeds: [0.5, 0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 3.0]

    function languageName(code) {
        return code === "" ? "" : code;
    }

    // "English  ·  Signs & Songs  ·  ass" without the empty pieces.
    function describe(track) {
        const bits = [];
        if (track.lang !== "")
            bits.push(track.lang);
        if (track.title !== "")
            bits.push(track.title);
        if (track.codec !== "")
            bits.push(track.codec);
        if (track.external)
            bits.push(qsTr("external file"));
        if (track.forced)
            bits.push(qsTr("forced"));
        return bits.join("   ·   ");
    }

    Rectangle {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: Theme.touch + Theme.pad
        color: Theme.surface

        Text {
            anchors { left: parent.left; leftMargin: Theme.pad + 4; verticalCenter: parent.verticalCenter }
            text: Book.pageName
            color: Theme.text
            font.pixelSize: Theme.fontMd
            font.weight: Font.DemiBold
            elide: Text.ElideMiddle
            width: parent.width - 2 * Theme.touch
        }
        IconButton {
            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
            icon: "close"
            tip: qsTr("Back to the video (Esc)")
            onClicked: sheet.closed()
        }
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 1
            color: Theme.line
        }
    }

    Flickable {
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.margins: Theme.pad
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: body
            width: parent.width
            spacing: 6

            // ---- audio ----------------------------------------------------
            SheetHeading { text: qsTr("Audio") }

            Repeater {
                model: Player.audioTracks
                delegate: SheetRow {
                    required property var modelData
                    width: body.width
                    label: modelData.title !== "" ? modelData.title
                         : (modelData.lang !== "" ? modelData.lang : qsTr("Track %1").arg(modelData.id))
                    detail: sheet.describe(modelData)
                    current: Player.audioTrack === modelData.id
                    onClicked: Player.audioTrack = modelData.id
                }
            }
            SheetRow {
                width: body.width
                visible: Player.audioTracks.length > 0
                label: qsTr("No audio")
                current: Player.audioTrack <= 0
                onClicked: Player.audioTrack = 0
            }
            Text {
                visible: Player.audioTracks.length === 0
                text: qsTr("This file has no audio tracks.")
                color: Theme.textDim
                font.pixelSize: Theme.fontMd
                bottomPadding: 6
            }

            // ---- subtitles ------------------------------------------------
            SheetHeading { text: qsTr("Subtitles") }

            Repeater {
                model: Player.subtitleTracks
                delegate: SheetRow {
                    required property var modelData
                    width: body.width
                    label: modelData.title !== "" ? modelData.title
                         : (modelData.lang !== "" ? modelData.lang : qsTr("Track %1").arg(modelData.id))
                    detail: sheet.describe(modelData)
                    current: Player.subtitleTrack === modelData.id
                    onClicked: {
                        Player.subtitleTrack = modelData.id;
                        Player.subtitleVisible = true;
                    }
                }
            }
            SheetRow {
                width: body.width
                label: qsTr("No subtitles")
                current: Player.subtitleTrack <= 0
                onClicked: Player.subtitleTrack = 0
            }
            Text {
                visible: Player.subtitleTracks.length === 0
                text: qsTr("Nothing found in the folder, the archive, or the file itself.")
                color: Theme.textDim
                font.pixelSize: Theme.fontSm
                bottomPadding: 6
            }

            // Nudging the timing is the one subtitle setting people really do
            // reach for, so it is here rather than buried.
            Row {
                visible: Player.subtitleTrack > 0
                spacing: 8
                height: Theme.touch

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Delay")
                    color: Theme.textDim
                    font.pixelSize: Theme.fontMd
                    width: 70
                }
                TextButton {
                    label: "−0.1s"
                    onClicked: Player.subDelay -= 0.1
                }
                TextButton {
                    label: Player.subDelay.toFixed(1) + "s"
                    checked: Math.abs(Player.subDelay) > 0.001
                    tip: qsTr("Tap to clear")
                    onClicked: Player.subDelay = 0
                }
                TextButton {
                    label: "+0.1s"
                    onClicked: Player.subDelay += 0.1
                }
            }

            // ---- speed ----------------------------------------------------
            SheetHeading { text: qsTr("Speed") }

            Flow {
                width: body.width
                spacing: 8

                Repeater {
                    model: sheet.speeds
                    delegate: TextButton {
                        required property real modelData
                        label: (Math.abs(modelData - Math.round(modelData)) < 0.005
                                ? String(Math.round(modelData))
                                : String(modelData)) + "×"
                        checked: Math.abs(Player.speed - modelData) < 0.005
                        onClicked: Player.speed = modelData
                    }
                }
            }

            Item { width: 1; height: Theme.pad }
        }
    }
}
