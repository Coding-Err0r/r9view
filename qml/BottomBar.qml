import QtQuick
import QtQuick.Controls.Basic

// Auto-hiding footer: a scrub bar for jumping around a long chapter, sized for
// a thumb rather than a mouse pointer.
Rectangle {
    id: bar

    height: Theme.touch + Theme.pad
    color: Theme.overlay

    Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 1
        color: Theme.line
    }

    IconButton {
        id: prev
        anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
        icon: "left"
        tip: qsTr("Previous page (←)")
        enabledWhen: Book.index > 0
        onClicked: Book.previous()
    }

    IconButton {
        id: next
        anchors { right: counter.left; rightMargin: 2; verticalCenter: parent.verticalCenter }
        icon: "right"
        tip: qsTr("Next page (→)")
        enabledWhen: Book.index < Book.count - 1
        onClicked: Book.next()
    }

    Text {
        id: counter
        anchors { right: parent.right; rightMargin: Theme.pad; verticalCenter: parent.verticalCenter }
        text: (Book.index + 1) + " / " + Book.count
        color: Theme.textDim
        font.pixelSize: Theme.fontSm
        font.family: "monospace"
    }

    Slider {
        id: scrub
        anchors {
            left: prev.right; leftMargin: Theme.pad
            right: next.left; rightMargin: Theme.pad
            verticalCenter: parent.verticalCenter
        }
        from: 0
        to: Math.max(0, Book.count - 1)
        stepSize: 1
        snapMode: Slider.SnapAlways
        // Right-to-left books scrub in the direction they read.
        property bool flip: Book.rightToLeft

        value: flip ? (Book.count - 1 - Book.index) : Book.index
        onMoved: {
            const target = flip ? (Book.count - 1 - value) : value;
            Book.index = Math.round(target);
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
