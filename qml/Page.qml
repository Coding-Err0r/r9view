import QtQuick

// One page: the image, plus the pinch/drag/tap gestures that act on it.
//
// Zoom is kept as a multiplier on top of the current fit, so 1.0 always means
// "as the fit mode says" no matter which mode that is, and panning is clamped so
// the page can never be dragged off into empty space.
Item {
    id: cell

    required property int index
    property int generation: 0
    property bool active: false          // is this the page being read right now
    property int fitMode: 0
    property real maxZoom: 8.0

    signal requestPrevious()
    signal requestNext()
    signal requestChrome()

    property real zoom: 1.0
    property real panX: 0
    property real panY: 0
    readonly property bool zoomed: zoom > 1.005
    readonly property bool loaded: img.status === Image.Ready

    // Size the image would have at zoom 1.0 under the current fit mode.
    readonly property real fitW: fitScale * img.implicitWidth
    readonly property real fitH: fitScale * img.implicitHeight
    readonly property real fitScale: {
        const iw = img.implicitWidth;
        const ih = img.implicitHeight;
        if (iw <= 0 || ih <= 0 || width <= 0 || height <= 0)
            return 1;
        switch (cell.fitMode) {
        case 1: return width / iw;                       // fit width
        case 2: return height / ih;                      // fit height
        case 3: return 1;                                // original pixels
        default:
            // Fit the window, but never blow a small picture up: a thumbnail
            // stretched across the screen is worse than a small sharp one.
            return Math.min(1, Math.min(width / iw, height / ih));
        }
    }

    function clampPan() {
        const slackX = Math.max(0, (fitW * zoom - width) / 2);
        const slackY = Math.max(0, (fitH * zoom - height) / 2);
        panX = Math.max(-slackX, Math.min(slackX, panX));
        panY = Math.max(-slackY, Math.min(slackY, panY));
    }

    // Zoom about a point so whatever is under the fingers stays under them.
    function zoomAt(pt, target) {
        const next = Math.max(1, Math.min(maxZoom, target));
        if (Math.abs(next - zoom) < 0.0005)
            return;
        const k = next / zoom;
        const dx = pt.x - (width / 2 + panX);
        const dy = pt.y - (height / 2 + panY);
        panX += (1 - k) * dx;
        panY += (1 - k) * dy;
        zoom = next;
        clampPan();
    }

    function zoomBy(factor) {
        zoomAt(Qt.point(width / 2, height / 2), zoom * factor);
    }

    function resetZoom() {
        zoom = 1;
        panX = 0;
        panY = 0;
    }

    onFitModeChanged: resetZoom()
    onActiveChanged: if (!active) resetZoom()
    onWidthChanged: clampPan()
    onHeightChanged: clampPan()

    Image {
        id: img
        source: cell.generation > 0 ? "image://page/" + cell.generation + "/" + cell.index : ""
        asynchronous: true
        cache: true
        smooth: true
        mipmap: cell.zoom < 1.5
        fillMode: Image.PreserveAspectFit

        width: cell.fitW * cell.zoom
        height: cell.fitH * cell.zoom
        x: (cell.width - width) / 2 + cell.panX
        y: (cell.height - height) / 2 + cell.panY

        Behavior on width  { enabled: !pinch.active; NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
        Behavior on height { enabled: !pinch.active; NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
        Behavior on x      { enabled: !pinch.active && !pan.active; NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
        Behavior on y      { enabled: !pinch.active && !pan.active; NumberAnimation { duration: Theme.anim; easing.type: Easing.OutCubic } }
    }

    // ---- loading / failure ------------------------------------------------
    Item {
        anchors.centerIn: parent
        width: 44
        height: 44
        visible: img.status === Image.Loading

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
                running: img.status === Image.Loading
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

    Text {
        anchors.centerIn: parent
        visible: img.status === Image.Error
        text: qsTr("Page %1 could not be decoded").arg(cell.index + 1)
        color: Theme.textDim
        font.pixelSize: Theme.fontMd
    }

    // ---- gestures ---------------------------------------------------------
    // Tap zones live here rather than on the pager: the delegate is the item the
    // touch actually lands on, so this fires reliably even mid-flick.
    TapHandler {
        id: taps
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onSingleTapped: function (event) {
            pendingTap.pos = event.position;
            pendingTap.restart();
        }
        onDoubleTapped: function (event) {
            pendingTap.stop();
            if (cell.zoomed)
                cell.resetZoom();
            else
                cell.zoomAt(event.position, 2.5);
        }
    }

    // A single tap waits out the double-tap window so a double tap does not
    // flash the bars on its way past.
    Timer {
        id: pendingTap
        interval: 210
        property point pos: Qt.point(0, 0)
        onTriggered: {
            const edge = Math.max(56, cell.width * 0.2);
            if (!cell.zoomed && pos.x < edge)
                cell.requestPrevious();
            else if (!cell.zoomed && pos.x > cell.width - edge)
                cell.requestNext();
            else
                cell.requestChrome();
        }
    }

    PinchHandler {
        id: pinch
        target: null
        minimumScale: 0.2
        maximumScale: 12

        property real startZoom: 1
        property point lastCentroid
        property bool tracking: false

        onActiveChanged: {
            if (active) {
                startZoom = cell.zoom;
                lastCentroid = centroid.position;
                tracking = true;
            } else {
                tracking = false;
                if (cell.zoom < 1.02)
                    cell.resetZoom();
            }
        }
        // Two fingers zoom and drag at the same time: the scale change is
        // applied about the centroid, and the centroid's own movement pans.
        onCentroidChanged: {
            if (!active || !tracking)
                return;
            cell.panX += centroid.position.x - lastCentroid.x;
            cell.panY += centroid.position.y - lastCentroid.y;
            lastCentroid = centroid.position;
            cell.clampPan();
        }
        onActiveScaleChanged: {
            if (!tracking)
                return;
            cell.zoomAt(centroid.position, startZoom * activeScale);
        }
    }

    // Panning only exists while zoomed in; otherwise the drag belongs to the
    // pager so a swipe still turns the page.
    DragHandler {
        id: pan
        target: null
        enabled: cell.zoomed
        property real startX: 0
        property real startY: 0
        onActiveChanged: {
            if (active) {
                startX = cell.panX;
                startY = cell.panY;
            }
        }
        onTranslationChanged: {
            if (!active)
                return;
            cell.panX = startX + activeTranslation.x;
            cell.panY = startY + activeTranslation.y;
            cell.clampPan();
        }
    }
}
