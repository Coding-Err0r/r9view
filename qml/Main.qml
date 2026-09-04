import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtCore

ApplicationWindow {
    id: app

    width: 1180
    height: 780
    visible: true
    color: Theme.background
    title: Book.ready ? Book.title + " — r9view" : "r9view"

    // ---- chrome ------------------------------------------------------------
    // The bars are in the way of the picture, so they leave on their own a few
    // seconds after you stop touching them.
    property bool chrome: true
    property bool pinned: !Book.ready

    function flashChrome() {
        chrome = true;
        hideTimer.restart();
    }

    Timer {
        id: hideTimer
        interval: 4500
        onTriggered: if (!app.pinned && !overlayOpen && !barHover.hovered) app.chrome = false
    }

    readonly property bool overlayOpen: thumbs.showing || help.showing

    onPinnedChanged: if (pinned) chrome = true

    // ---- reading surface ---------------------------------------------------
    Reader {
        id: reader
        anchors.fill: parent
        visible: Book.ready
        onToggleChrome: {
            if (app.chrome && !app.pinned)
                app.chrome = false;
            else
                app.flashChrome();
        }
    }

    Welcome {
        anchors.fill: parent
        visible: !Book.ready && !Book.busy
        onOpenFile: fileDialog.open()
        onOpenFolder: folderDialog.open()
    }

    // ---- busy --------------------------------------------------------------
    Rectangle {
        anchors.centerIn: parent
        visible: Book.busy
        width: busyText.implicitWidth + 40
        height: 48
        radius: Theme.radius
        color: Theme.surface
        Text {
            id: busyText
            anchors.centerIn: parent
            text: qsTr("Reading the archive…")
            color: Theme.text
            font.pixelSize: Theme.fontMd
        }
    }

    // ---- bars --------------------------------------------------------------
    HoverHandler { id: barHover }

    TopBar {
        id: top
        anchors { left: parent.left; right: parent.right }
        y: app.chrome ? 0 : -height
        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        onOpenRequested: fileDialog.open()
        onBackRequested: Book.close()
        onGridRequested: thumbs.showing = true
        onHelpRequested: help.showing = true
        fullscreen: app.visibility === Window.FullScreen
        onFullscreenToggled: app.toggleFullscreen()
    }

    BottomBar {
        id: bottom
        anchors { left: parent.left; right: parent.right }
        visible: Book.ready
        y: app.chrome ? parent.height - height : parent.height
        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    }

    // Any mouse movement brings the bars back -- on a desktop the pointer is the
    // clearest "I am here" signal there is, and hunting for a hidden bar is not a
    // game anyone wants to play.
    HoverHandler {
        id: pointerWake
        onPointChanged: app.flashChrome()
    }

    Thumbs {
        id: thumbs
        anchors.fill: parent
        onClosed: showing = false
    }

    HelpSheet {
        id: help
        anchors.fill: parent
        onClosed: showing = false
    }

    // ---- messages ----------------------------------------------------------
    Rectangle {
        id: toast
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 90 }
        width: toastText.implicitWidth + 32
        height: 42
        radius: 21
        color: Theme.surfaceHigh
        border.width: 1
        border.color: Theme.line
        opacity: 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Text {
            id: toastText
            anchors.centerIn: parent
            color: Theme.text
            font.pixelSize: Theme.fontMd
        }
        Timer {
            id: toastTimer
            interval: 2600
            onTriggered: toast.opacity = 0
        }
        function show(message) {
            toastText.text = message;
            opacity = 1;
            toastTimer.restart();
        }
    }

    Connections {
        target: Book
        function onErrorChanged() {
            if (Book.error !== "") {
                toast.show(Book.error);
                Book.clearError();
            }
        }
        function onOpened() {
            app.flashChrome();
        }
        function onFitModeChanged() {
            toast.show([qsTr("Fit page"), qsTr("Fit width"), qsTr("Fit height"), qsTr("Actual size")][Book.fitMode]);
        }
        function onRightToLeftChanged() {
            toast.show(Book.rightToLeft ? qsTr("Right to left") : qsTr("Left to right"));
        }
    }

    // ---- open --------------------------------------------------------------
    FileDialog {
        id: fileDialog
        title: qsTr("Open an image or a comic archive")
        currentFolder: StandardPaths.writableLocation(StandardPaths.DownloadLocation)
        nameFilters: [
            qsTr("Comics and images (*.zip *.cbz *.rar *.cbr *.7z *.cb7 *.tar *.cbt *.png *.jpg *.jpeg *.webp *.avif *.jxl *.heic *.heif *.gif *.bmp *.tif *.tiff *.psd *.svg)"),
            qsTr("Comic archives (*.zip *.cbz *.rar *.cbr *.7z *.cb7 *.tar *.cbt)"),
            qsTr("Images (*.png *.jpg *.jpeg *.webp *.avif *.jxl *.heic *.heif *.gif *.bmp *.tif *.tiff *.psd *.svg)"),
            qsTr("Everything (*)")
        ]
        onAccepted: Book.openUrl(selectedFile)
    }

    FolderDialog {
        id: folderDialog
        title: qsTr("Open a folder of images")
        onAccepted: Book.openUrl(selectedFolder)
    }

    DropArea {
        anchors.fill: parent
        onDropped: function (drop) {
            if (drop.hasUrls && drop.urls.length > 0) {
                Book.openUrl(drop.urls[0]);
                drop.acceptProposedAction();
            }
        }
    }

    // ---- keyboard ----------------------------------------------------------
    function toggleFullscreen() {
        app.visibility = (app.visibility === Window.FullScreen) ? Window.AutomaticVisibility
                                                                : Window.FullScreen;
    }

    function goBack() {
        if (help.showing)
            help.showing = false;
        else if (thumbs.showing)
            thumbs.showing = false;
        else if (reader.zoomed)
            reader.resetZoom();
        else if (app.visibility === Window.FullScreen)
            app.visibility = Window.AutomaticVisibility;
        else if (Book.ready)
            Book.close();          // back to the start screen before quitting
        else
            Qt.quit();
    }

    Shortcut { sequences: ["Right"];            onActivated: { Book.next(); app.flashChrome(); } }
    Shortcut { sequences: ["Left"];             onActivated: { Book.previous(); app.flashChrome(); } }
    Shortcut { sequences: ["Up"];               onActivated: reader.zoomIn() }
    Shortcut { sequences: ["Down"];             onActivated: reader.zoomOut() }
    Shortcut { sequences: ["Space", "PgDown"];  onActivated: Book.next() }
    Shortcut { sequences: ["Backspace", "PgUp"]; onActivated: Book.previous() }
    Shortcut { sequences: ["Home"];             onActivated: Book.first() }
    Shortcut { sequences: ["End"];              onActivated: Book.last() }
    Shortcut { sequences: ["0"];                onActivated: reader.resetZoom() }
    Shortcut { sequences: ["F"];                onActivated: Book.fitMode = (Book.fitMode + 1) % 4 }
    Shortcut { sequences: ["D"];                onActivated: Book.rightToLeft = !Book.rightToLeft }
    Shortcut { sequences: ["G"];                onActivated: if (Book.ready) thumbs.showing = !thumbs.showing }
    Shortcut { sequences: ["O", "Ctrl+O"];      onActivated: fileDialog.open() }
    Shortcut { sequences: ["Ctrl+Shift+O"];     onActivated: folderDialog.open() }
    Shortcut { sequences: ["F11"];              onActivated: app.toggleFullscreen() }
    Shortcut { sequences: ["?", "F1"];          onActivated: help.showing = !help.showing }
    Shortcut { sequences: ["Escape"];           onActivated: app.goBack() }
    Shortcut { sequences: ["Ctrl+Q"];           onActivated: Qt.quit() }
}
