import QtQuick

// The pager. A horizontal ListView that snaps one page at a time gives real
// touch page-turning -- momentum, rubber-band at the ends, the page following
// the finger -- for free, and stays in step with the keyboard because both just
// move Book.index.
Item {
    id: reader

    property alias currentPage: view.currentItem
    property bool zoomed: view.currentItem ? view.currentItem.zoomed : false
    signal toggleChrome()

    function zoomIn()    { if (view.currentItem) view.currentItem.zoomBy(1.35); }
    function zoomOut()   { if (view.currentItem) view.currentItem.zoomBy(1 / 1.35); }
    function resetZoom() { if (view.currentItem) view.currentItem.resetZoom(); }
    function toggleZoom() {
        if (!view.currentItem)
            return;
        if (view.currentItem.zoomed)
            view.currentItem.resetZoom();
        else
            view.currentItem.zoomAt(Qt.point(reader.width / 2, reader.height / 2), 2.5);
    }

    ListView {
        id: view
        anchors.fill: parent

        model: Book.count
        orientation: ListView.Horizontal
        layoutDirection: Book.rightToLeft ? Qt.RightToLeft : Qt.LeftToRight
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: 0
        preferredHighlightEnd: width
        highlightMoveDuration: 220
        boundsBehavior: Flickable.DragOverBounds
        keyNavigationEnabled: false  // arrow keys belong to the window shortcuts
        maximumFlickVelocity: 6000
        // Keep a page either side decoded so a swipe lands on a drawn page
        // instead of a spinner.
        cacheBuffer: Math.round(width * 2)
        // While a page is zoomed in the drag belongs to panning, not paging.
        interactive: !reader.zoomed

        delegate: Page {
            width: view.width
            height: view.height
            generation: Book.generation
            fitMode: Book.fitMode
            active: ListView.isCurrentItem

            onRequestPrevious: Book.previous()
            onRequestNext: Book.next()
            onRequestChrome: reader.toggleChrome()
        }

        onCurrentIndexChanged: if (currentIndex >= 0) Book.index = currentIndex

        Connections {
            target: Book
            function onIndexChanged() {
                if (view.currentIndex !== Book.index)
                    view.currentIndex = Book.index;
            }
            function onOpened() {
                view.positionViewAtIndex(Book.index, ListView.Beginning);
                view.currentIndex = Book.index;
            }
        }
    }

    // Mouse: wheel turns pages, ctrl+wheel zooms.
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function (event) {
            if (event.modifiers & Qt.ControlModifier) {
                if (view.currentItem)
                    view.currentItem.zoomAt(event.position, view.currentItem.zoom * (event.angleDelta.y > 0 ? 1.2 : 1 / 1.2));
            } else if (reader.zoomed) {
                view.currentItem.panY += event.angleDelta.y;
                view.currentItem.clampPan();
            } else if (event.angleDelta.y < 0 || event.angleDelta.x < 0) {
                Book.next();
            } else {
                Book.previous();
            }
        }
    }
}
