import QtQuick
import QtQuick.Controls.Basic
import R9View

// The player's footer: what BottomBar is to a comic, but scrubbing time rather
// than pages.
//
// Everything on it is at least 44px, and the things wanted most often -- pause,
// scrub, the next episode -- are the ones reachable without a second tap. Track
// and speed choices live behind a sheet, because they get settled once and then
// left alone.
Rectangle {
    id: bar

    signal tracksRequested()
    signal speedRequested()

    height: Theme.touch + Theme.pad
    color: Theme.overlay

    Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 1
        color: Theme.line
    }

    // While a finger is on the scrub bar the slider owns the position; otherwise
    // it follows playback. Without this the handle fights the thumb.
    property bool scrubbing: false

    Row {
        id: leftGroup
        anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
        spacing: 2

        IconButton {
            icon: "skipprev"
            tip: qsTr("Previous (PgUp)")
            enabledWhen: Book.index > 0
            onClicked: Book.previous()
        }
        IconButton {
            icon: Player.paused ? "play" : "pause"
            tip: Player.paused ? qsTr("Play (Space)") : qsTr("Pause (Space)")
            onClicked: Player.togglePause()
        }
        IconButton {
            icon: "skipnext"
            tip: qsTr("Next (PgDown)")
            enabledWhen: Book.index < Book.count - 1
            onClicked: Book.next()
        }
    }

    Text {
        id: elapsed
        anchors { left: leftGroup.right; leftMargin: Theme.pad; verticalCenter: parent.verticalCenter }
        text: Player.formatTime(bar.scrubbing ? scrub.value : Player.position)
        color: Theme.text
        font.pixelSize: Theme.fontSm
        font.family: "monospace"
    }

    Row {
        id: rightGroup
        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
        spacing: 2

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Player.formatTime(Player.duration)
            color: Theme.textDim
            font.pixelSize: Theme.fontSm
            font.family: "monospace"
            rightPadding: Theme.pad
        }
        TextButton {
            label: bar.speedLabel
            tip: qsTr("Playback speed — tap to choose ([ and ])")
            checked: Math.abs(Player.speed - 1) > 0.001
            onClicked: bar.speedRequested()
        }
        IconButton {
            icon: Player.muted ? "mute" : "volume"
            tip: Player.muted ? qsTr("Unmute (M)") : qsTr("Mute (M)")
            checked: Player.muted
            onClicked: Player.muted = !Player.muted
        }
        IconButton {
            icon: "tracks"
            tip: qsTr("Audio and subtitles")
            checked: Player.subtitleTrack > 0
            onClicked: bar.tracksRequested()
        }
    }

    // 1× rather than 1.00×, 1.5× rather than 1.50×.
    readonly property string speedLabel: {
        const n = Player.speed;
        const text = Math.abs(n - Math.round(n)) < 0.005
                   ? String(Math.round(n))
                   : n.toFixed(2).replace(/0$/, "");
        return text + "×";
    }

    Slider {
        id: scrub
        anchors {
            left: elapsed.right; leftMargin: Theme.pad
            right: rightGroup.left; rightMargin: Theme.pad
            verticalCenter: parent.verticalCenter
        }
        from: 0
        to: Math.max(0.1, Player.duration)
        enabled: Player.seekable && Player.duration > 0

        value: Player.position
        onPressedChanged: {
            bar.scrubbing = pressed;
            if (!pressed)
                Player.seekTo(value);
        }

        background: Rectangle {
            x: scrub.leftPadding
            y: scrub.topPadding + scrub.availableHeight / 2 - height / 2
            width: scrub.availableWidth
            height: 6
            radius: 3
            color: Qt.rgba(1, 1, 1, 0.13)

            Rectangle {
                width: scrub.visualPosition * parent.width
                height: parent.height
                radius: 3
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Theme.accent }
                    GradientStop { position: 1; color: Theme.accent2 }
                }
            }
        }

        handle: Rectangle {
            x: scrub.leftPadding + scrub.visualPosition * (scrub.availableWidth - width)
            y: scrub.topPadding + scrub.availableHeight / 2 - height / 2
            width: 22
            height: 22
            radius: 11
            color: scrub.pressed ? Theme.accent2 : Theme.text
            border.width: 2
            border.color: Qt.rgba(0, 0, 0, 0.35)
            scale: scrub.pressed ? 1.25 : 1
            Behavior on scale { NumberAnimation { duration: Theme.anim } }
        }
    }
}
