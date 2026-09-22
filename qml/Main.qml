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

    function tapChrome() {
        if (app.chrome && !app.pinned)
            app.chrome = false;
        else
            app.flashChrome();
    }

    Timer {
        id: hideTimer
        interval: 4500
        onTriggered: if (!app.pinned && !overlayOpen && !barHover.hovered) app.chrome = false
    }

    readonly property bool overlayOpen: thumbs.showing || help.showing || videoSheet.showing

    onPinnedChanged: if (pinned) chrome = true

    // ---- reading surface ---------------------------------------------------
    // One of two surfaces, chosen by what was opened. Both answer to the same
    // Book.index, so next() and previous() turn a page or change an episode
    // without either surface knowing which it is doing.
    Reader {
        id: reader
        anchors.fill: parent
        visible: Book.ready && Book.kind === Book.Images
        onToggleChrome: app.tapChrome()
    }

    Loader {
        id: video
        anchors.fill: parent
        // Left unloaded until a video is actually opened, so a comic session
        // never builds a player interface it will not show.
        active: Book.kind === Book.Video
        visible: active
        sourceComponent: VideoView {
            onToggleChrome: app.tapChrome()
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
        visible: Book.ready && !app.playing
        y: app.chrome ? parent.height - height : parent.height
        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    }

    Loader {
        id: videoBar
        anchors { left: parent.left; right: parent.right }
        active: app.playing
        visible: active
        y: app.chrome ? parent.height - height : parent.height
        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        sourceComponent: VideoBar {
            onTracksRequested: { videoSheet.section = "tracks"; videoSheet.showing = true; }
            onSpeedRequested: { videoSheet.section = "speed"; videoSheet.showing = true; }
        }
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

    Loader {
        id: videoSheetLoader
        anchors.fill: parent
        active: app.playing
        sourceComponent: VideoSheet {
            showing: videoSheet.showing
            section: videoSheet.section
            onClosed: videoSheet.showing = false
        }
    }

    // The sheet's state lives out here so the Loader can come and go with the
    // video without losing it. That also means it has to be put back when the
    // video goes away: left standing, it keeps overlayOpen true forever, the
    // bars never auto-hide again, and the next Escape is swallowed closing a
    // sheet nobody can see.
    QtObject {
        id: videoSheet
        property bool showing: false
        property string section: "tracks"
    }

    Connections {
        target: Book
        function onKindChanged() { videoSheet.showing = false; }
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

    // ---- playback ----------------------------------------------------------
    // Book decides what is current; the player is told about it here. Keeping
    // the sequencing in one place is what makes resume and subtitle attachment
    // predictable: a file has to be loaded before a subtitle can be added to
    // it, and before there is anywhere to seek to.
    Connections {
        target: Book
        enabled: Book.kind === Book.Video

        function onMediaUrlChanged() {
            if (Book.mediaUrl !== "")
                Player.open(Book.mediaUrl);
        }
    }

    Connections {
        target: Player
        enabled: Book.kind === Book.Video

        function onFileLoaded() {
            // Subtitles found in nested folders, best match first. They are
            // added rather than selected, so an embedded track that mpv already
            // chose keeps its place.
            const found = Book.mediaSubtitles;
            for (let i = 0; i < found.length; ++i)
                Player.addSubtitle(found[i].url, found[i].title, found[i].lang);

            // Nothing embedded was selected, so the best thing we found becomes
            // the subtitle -- otherwise a film whose only subtitles live in a
            // Subs/ folder would start with none showing.
            if (found.length > 0 && Player.subtitleTrack <= 0)
                subtitlePick.restart();

            const resume = Book.mediaResumeTime();
            if (resume > 0)
                Player.seekTo(resume);
        }

        function onEndOfFile() {
            // Straight on to the next episode, which is the whole point of
            // opening a season folder rather than a file.
            if (Book.index < Book.count - 1)
                Book.next();
        }

        function onPausedChanged() {
            // Only once there is a real position to keep. keep-open flips the
            // pause flag around every file change, and a pause seen while the
            // position is still zero would read as "barely watched" and throw
            // away the resume point for the episode just starting.
            if (Player.paused && Player.duration > 0 && Player.position > 1)
                Book.rememberMediaTime(Player.position, Player.duration);
        }
    }

    // sub-add is asynchronous: the track does not appear in the list until mpv
    // has read the file, so the selection waits a beat rather than racing it.
    Timer {
        id: subtitlePick
        interval: 120
        onTriggered: {
            const tracks = Player.subtitleTracks;
            for (let i = 0; i < tracks.length; ++i) {
                if (tracks[i].external) {
                    Player.subtitleTrack = tracks[i].id;
                    return;
                }
            }
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
        title: qsTr("Open a video, an image, or an archive")
        currentFolder: StandardPaths.writableLocation(StandardPaths.DownloadLocation)
        nameFilters: [
            qsTr("Everything r9view plays (*.mkv *.mp4 *.m4v *.avi *.mov *.webm *.ts *.m2ts *.wmv *.flv *.mpg *.mpeg *.ogv *.rmvb *.3gp *.mp3 *.flac *.m4a *.aac *.ogg *.opus *.wav *.mka *.zip *.cbz *.rar *.cbr *.7z *.cb7 *.tar *.cbt *.png *.jpg *.jpeg *.webp *.avif *.jxl *.heic *.heif *.gif *.bmp *.tif *.tiff *.psd *.svg)"),
            qsTr("Video (*.mkv *.mp4 *.m4v *.avi *.mov *.webm *.ts *.m2ts *.mts *.wmv *.asf *.flv *.mpg *.mpeg *.m2v *.vob *.ogv *.rm *.rmvb *.3gp *.divx *.mxf)"),
            qsTr("Audio (*.mp3 *.flac *.m4a *.aac *.ogg *.oga *.opus *.wav *.wma *.alac *.ape *.mka *.dts *.ac3 *.aiff *.dsf)"),
            qsTr("Comic archives (*.zip *.cbz *.rar *.cbr *.7z *.cb7 *.tar *.cbt)"),
            qsTr("Images (*.png *.jpg *.jpeg *.webp *.avif *.jxl *.heic *.heif *.gif *.bmp *.tif *.tiff *.psd *.svg)"),
            qsTr("Everything (*)")
        ]
        onAccepted: Book.openUrl(selectedFile)
    }

    FolderDialog {
        id: folderDialog
        title: qsTr("Open a folder")
        onAccepted: Book.openUrl(selectedFolder)
    }

    // Wherever playback stops for good -- closing the book, quitting, being
    // closed -- the position is worth keeping. Book decides whether it is far
    // enough in to be worth reopening at.
    function keepPlaybackPosition() {
        if (Book.kind === Book.Video && Player.duration > 0)
            Book.rememberMediaTime(Player.position, Player.duration);
    }

    onClosing: app.keepPlaybackPosition()
    Component.onDestruction: app.keepPlaybackPosition()

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

    readonly property bool playing: Book.kind === Book.Video

    function goBack() {
        if (videoSheet.showing)
            videoSheet.showing = false;
        else if (help.showing)
            help.showing = false;
        else if (thumbs.showing)
            thumbs.showing = false;
        else if (app.playing && video.item && video.item.zoomed)
            video.item.resetZoom();
        else if (!app.playing && reader.zoomed)
            reader.resetZoom();
        else if (app.visibility === Window.FullScreen)
            app.visibility = Window.AutomaticVisibility;
        else if (Book.ready) {
            app.keepPlaybackPosition();
            Book.close();          // back to the start screen before quitting
        } else {
            Qt.quit();
        }
    }

    // The same physical key does the mpv thing while a video is open and the
    // viewer thing otherwise. That is the only way both halves can feel native:
    // arrows step pages in a comic and seek in a film, Space turns a page and
    // pauses playback, and F cycles the fit but is fullscreen in a player, as it
    // has been in mpv forever.
    Shortcut {
        sequences: ["Right"]
        onActivated: { if (app.playing) Player.seekBy(5); else Book.next(); app.flashChrome(); }
    }
    Shortcut {
        sequences: ["Left"]
        onActivated: { if (app.playing) Player.seekBy(-5); else Book.previous(); app.flashChrome(); }
    }
    Shortcut {
        sequences: ["Shift+Right"]
        onActivated: if (app.playing) { Player.seekBy(60); app.flashChrome(); }
    }
    Shortcut {
        sequences: ["Shift+Left"]
        onActivated: if (app.playing) { Player.seekBy(-60); app.flashChrome(); }
    }
    Shortcut {
        sequences: ["Up"]
        onActivated: app.playing ? Player.volume = Math.min(130, Player.volume + 5) : reader.zoomIn()
    }
    Shortcut {
        sequences: ["Down"]
        onActivated: app.playing ? Player.volume = Math.max(0, Player.volume - 5) : reader.zoomOut()
    }
    Shortcut {
        sequences: ["Space"]
        onActivated: { if (app.playing) Player.togglePause(); else Book.next(); }
    }
    Shortcut { sequences: ["P"];  onActivated: if (app.playing) Player.togglePause() }
    Shortcut { sequences: ["M"];  onActivated: if (app.playing) Player.muted = !Player.muted }
    Shortcut { sequences: ["V"];  onActivated: if (app.playing) Player.subtitleVisible = !Player.subtitleVisible }
    Shortcut { sequences: ["J"];  onActivated: if (app.playing) Player.cycle("sub") }
    Shortcut { sequences: ["Shift+J"]; onActivated: if (app.playing) Player.cycle("sub", true) }
    Shortcut { sequences: ["#"];  onActivated: if (app.playing) Player.cycle("audio") }
    Shortcut { sequences: ["S"];  onActivated: if (app.playing) Player.screenshot() }
    Shortcut { sequences: ["["];  onActivated: if (app.playing) Player.speed = Player.speed / 1.1 }
    Shortcut { sequences: ["]"];  onActivated: if (app.playing) Player.speed = Player.speed * 1.1 }
    Shortcut { sequences: ["{"];  onActivated: if (app.playing) Player.speed = Player.speed / 2 }
    Shortcut { sequences: ["}"];  onActivated: if (app.playing) Player.speed = Player.speed * 2 }
    Shortcut { sequences: [","];  onActivated: if (app.playing) Player.frameStep(-1) }
    Shortcut { sequences: ["."];  onActivated: if (app.playing) Player.frameStep(1) }
    Shortcut { sequences: ["<", "PgUp"];  onActivated: Book.previous() }
    Shortcut { sequences: [">", "PgDown"]; onActivated: Book.next() }
    Shortcut {
        sequences: ["Backspace"]
        // mpv resets the speed with Backspace; the reader steps back a page.
        onActivated: app.playing ? Player.speed = 1.0 : Book.previous()
    }
    Shortcut { sequences: ["9"]; onActivated: if (app.playing) Player.volume = Math.max(0, Player.volume - 2) }
    Shortcut {
        sequences: ["0"]
        // mpv's 0 raises the volume. With no page zoom to reset in a video, the
        // mpv meaning wins there and the reader keeps its own.
        onActivated: app.playing ? Player.volume = Math.min(130, Player.volume + 2) : reader.resetZoom()
    }
    Shortcut {
        sequences: ["Ctrl+0"]
        onActivated: app.playing ? (video.item ? video.item.resetZoom() : 0) : reader.resetZoom()
    }
    Shortcut { sequences: ["Home"]; onActivated: app.playing ? Player.seekTo(0) : Book.first() }
    Shortcut { sequences: ["End"];  onActivated: Book.last() }
    Shortcut {
        sequences: ["F"]
        onActivated: app.playing ? app.toggleFullscreen() : Book.fitMode = (Book.fitMode + 1) % 4
    }
    Shortcut { sequences: ["D"];  onActivated: if (!app.playing) Book.rightToLeft = !Book.rightToLeft }
    Shortcut { sequences: ["G"];  onActivated: if (Book.ready && !app.playing) thumbs.showing = !thumbs.showing }
    Shortcut { sequences: ["O", "Ctrl+O"];  onActivated: fileDialog.open() }
    Shortcut { sequences: ["Ctrl+Shift+O"]; onActivated: folderDialog.open() }
    Shortcut { sequences: ["F11"];          onActivated: app.toggleFullscreen() }
    Shortcut { sequences: ["?", "F1"];      onActivated: help.showing = !help.showing }
    Shortcut { sequences: ["Escape"];       onActivated: app.goBack() }
    Shortcut { sequences: ["Ctrl+Q"];       onActivated: { app.keepPlaybackPosition(); Qt.quit(); } }
}
