import QtQuick
import R9View

// The video surface and every gesture that acts on it.
//
// This is the reason the project exists: mpv plays anything but has no touch
// input at all, so the whole vocabulary a phone player has taught people to
// expect is built here -- double tap the sides to skip, drag for volume and
// brightness, hold for fast-forward, pinch to zoom.
//
// Deliberately close to Page.qml where the two can agree: a single tap in the
// middle shows or hides the bars, and the same 210ms wait keeps a double tap
// from flashing them on its way past. Where they differ they differ on purpose.
// A single tap near the edge turns the page in a comic, but on a video the
// edges belong to seeking, which every player on a phone puts on a double tap --
// so a single tap anywhere on a video means only "show me the controls".
Item {
    id: view

    signal toggleChrome()

    readonly property bool zoomed: Player.videoZoom > 0.01

    // How far one skip goes. Ten seconds is the convention everywhere and there
    // is no reason to be different.
    readonly property int skipSeconds: 10

    function resetZoom() {
        Player.videoZoom = 0;
    }

    // ---- the picture ------------------------------------------------------
    VideoSurface {
        id: surface
        anchors.fill: parent
    }

    // A still, honest placeholder for audio-only files, so the window is not
    // just black with a scrub bar on it.
    Column {
        anchors.centerIn: parent
        spacing: 14
        visible: Player.ready && !Player.hasVideo

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            source: "icons/r9view.svg"
            sourceSize: Qt.size(72, 72)
            opacity: 0.5
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Player.mediaTitle !== "" ? Player.mediaTitle : Book.pageName
            color: Theme.text
            font.pixelSize: Theme.fontLg
        }
    }

    // ---- loading ----------------------------------------------------------
    // The same spinner Page.qml draws, so waiting for a video looks like
    // waiting for a page rather than like a different program.
    Item {
        id: spinner
        anchors.centerIn: parent
        width: 44
        height: 44
        visible: Player.buffering || (Book.kind === Book.Video && !Player.ready)

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 3
            border.color: Qt.rgba(1, 1, 1, 0.10)
        }
        Item {
            anchors.fill: parent
            RotationAnimator on rotation {
                running: spinner.visible
                loops: Animation.Infinite
                from: 0; to: 360; duration: 900
            }
            Rectangle {
                width: 9; height: 9; radius: 4.5
                color: Theme.accent2
                x: parent.width / 2 - 4.5
                y: -1.5
            }
        }
    }

    // ---- taps: chrome, play/pause, and skipping ---------------------------
    TapHandler {
        id: taps
        gesturePolicy: TapHandler.ReleaseWithinBounds

        onSingleTapped: function (event) {
            pendingTap.pos = event.position;
            pendingTap.restart();
        }

        // Every tap past the first lands here, which is what gives skipping its
        // accumulation for free: tap twice for ten seconds, keep tapping for
        // twenty and thirty, without waiting for the animation to finish.
        onTapped: function (event) {
            if (taps.tapCount < 2)
                return;
            pendingTap.stop();
            const third = view.width / 3;
            if (event.position.x < third)
                view.skip(-view.skipSeconds, event.position);
            else if (event.position.x > view.width - third)
                view.skip(view.skipSeconds, event.position);
            else if (taps.tapCount === 2)
                Player.togglePause();
        }

        onLongPressed: {
            // Hold to run fast, release to go back to normal -- the one gesture
            // people reach for without being told it is there.
            held.previousSpeed = Player.speed;
            held.active = true;
            Player.speed = 2.0;
        }
    }

    // A single tap waits out the double-tap window so a double tap does not
    // flash the bars on its way past. Straight out of Page.qml.
    Timer {
        id: pendingTap
        interval: 210
        property point pos: Qt.point(0, 0)
        onTriggered: view.toggleChrome()
    }

    // Long-press ends when the finger lifts, whichever handler noticed it.
    QtObject {
        id: held
        property bool active: false
        property real previousSpeed: 1.0
    }

    function releaseHold() {
        if (!held.active)
            return;
        held.active = false;
        Player.speed = held.previousSpeed;
    }

    HoverHandler { id: hover }

    PointHandler {
        id: release
        acceptedDevices: PointerDevice.TouchScreen | PointerDevice.Mouse | PointerDevice.Stylus
        onActiveChanged: if (!active) view.releaseHold()
    }

    // ---- skipping feedback ------------------------------------------------
    property int skipTotal: 0
    property bool skipForward: true

    function skip(seconds, at) {
        Player.seekBy(seconds);
        // Reset the running total when the last burst has faded, so a fresh
        // double tap reads "10s" rather than carrying on from the last one.
        if (!skipFade.running || (seconds > 0) !== skipForward)
            skipTotal = 0;
        skipForward = seconds > 0;
        skipTotal += Math.abs(seconds);
        skipFade.restart();
    }

    Timer {
        id: skipFade
        interval: 850
        onTriggered: view.skipTotal = 0
    }

    // The two skip zones, written out rather than generated, so that each one is
    // anchored to the edge it belongs to and there is no arithmetic to get wrong.
    component SkipRipple: Item {
        id: ripple
        property bool forward: true

        width: view.width / 3
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        opacity: view.skipTotal > 0 && view.skipForward === ripple.forward ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 180 } }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(ripple.width, ripple.height) * 0.9
            height: width
            radius: width / 2
            color: Qt.rgba(1, 1, 1, 0.12)
        }

        // The number sits on a solid pill rather than straight on the picture.
        // Thin text over video is only legible when the video happens to be
        // dark, which is not something to rely on.
        Rectangle {
            anchors.centerIn: parent
            width: badge.implicitWidth + 30
            height: 46
            radius: 23
            color: Qt.rgba(0.05, 0.05, 0.07, 0.82)
            border.width: 1
            border.color: Theme.line

            Text {
                id: badge
                anchors.centerIn: parent
                text: (ripple.forward ? "▶▶  " : "◀◀  ") + view.skipTotal + "s"
                color: Theme.text
                font.pixelSize: Theme.fontLg
                font.weight: Font.DemiBold
            }
        }
    }

    SkipRipple {
        forward: false
        anchors.left: parent.left
    }

    SkipRipple {
        forward: true
        anchors.right: parent.right
    }

    // ---- a badge while held at speed --------------------------------------
    Rectangle {
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 72 }
        width: speedBadge.implicitWidth + 26
        height: 40
        radius: 20
        color: Theme.surfaceHigh
        border.width: 1
        border.color: Theme.line
        opacity: held.active ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 140 } }

        Text {
            id: speedBadge
            anchors.centerIn: parent
            text: qsTr("%1×  speed").arg(Player.speed.toFixed(1))
            color: Theme.text
            font.pixelSize: Theme.fontMd
            font.weight: Font.DemiBold
        }
    }

    // ---- vertical drags: volume on the right, brightness on the left ------
    DragHandler {
        id: vertical
        target: null
        xAxis.enabled: false
        // Touch only. A mouse drag on a video should do nothing surprising, and
        // mpv users expect the wheel for volume, which WheelHandler below keeps.
        acceptedDevices: PointerDevice.TouchScreen

        property bool onRight: true
        property real startValue: 0

        onActiveChanged: {
            if (active) {
                onRight = centroid.pressPosition.x > view.width / 2;
                startValue = onRight ? Player.volume : Player.brightness;
                nudge.show(onRight);
            } else {
                nudge.hide();
            }
        }
        onTranslationChanged: {
            if (!active)
                return;
            // A full swipe up the screen covers the whole range, which is about
            // right for a thumb on a tablet.
            const fraction = -activeTranslation.y / Math.max(1, view.height * 0.6);
            if (onRight)
                Player.volume = Math.max(0, Math.min(130, startValue + fraction * 130));
            else
                Player.brightness = Math.max(-100, Math.min(100, startValue + fraction * 200));
        }
    }

    // A compact readout while a vertical drag is in progress.
    Rectangle {
        id: nudge
        property bool forVolume: true
        anchors.verticalCenter: parent.verticalCenter
        x: forVolume ? parent.width - width - 28 : 28
        width: 64
        height: 210
        radius: 18
        color: Qt.rgba(0.05, 0.05, 0.07, 0.86)
        border.width: 1
        border.color: Theme.line
        opacity: 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 140 } }

        function show(right) { forVolume = right; opacity = 1; }
        function hide() { opacity = 0; }

        readonly property real fraction: forVolume
            ? Player.volume / 130
            : (Player.brightness + 100) / 200

        Text {
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 12 }
            text: nudge.forVolume ? "▲" : "☀"
            color: Theme.text
            font.pixelSize: 16
        }
        Rectangle {
            id: track
            anchors.centerIn: parent
            width: 8
            height: parent.height - 76
            radius: 4
            color: Qt.rgba(1, 1, 1, 0.14)

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: parent.height * Math.max(0, Math.min(1, nudge.fraction))
                radius: 4
                gradient: Gradient {
                    GradientStop { position: 0; color: Theme.accent2 }
                    GradientStop { position: 1; color: Theme.accent }
                }
            }
        }
        Text {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 10 }
            text: nudge.forVolume ? Math.round(Player.volume) : Player.brightness
            color: Theme.textDim
            font.pixelSize: Theme.fontSm
            font.family: "monospace"
        }
    }

    // ---- pinch to zoom ----------------------------------------------------
    PinchHandler {
        target: null
        minimumScale: 0.5
        maximumScale: 6

        property real startZoom: 0
        onActiveChanged: {
            if (active)
                startZoom = Player.videoZoom;
            else if (Player.videoZoom < 0.02)
                Player.videoZoom = 0;
        }
        onActiveScaleChanged: {
            if (!active)
                return;
            // video-zoom is logarithmic, so a pinch multiplies rather than adds.
            Player.videoZoom = startZoom + Math.log2(Math.max(0.05, activeScale));
        }
    }

    // ---- mouse: as mpv has always behaved --------------------------------
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function (event) {
            if (event.modifiers & Qt.ControlModifier)
                Player.videoZoom += event.angleDelta.y > 0 ? 0.15 : -0.15;
            else
                Player.volume = Math.max(0, Math.min(130, Player.volume + (event.angleDelta.y > 0 ? 5 : -5)));
        }
    }
}
