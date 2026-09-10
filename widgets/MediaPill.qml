import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Widgets

import "../components"

// =============================================================================
// MediaPill.qml — Centered media player pill + rich popup
// =============================================================================
//
// Purpose:
//   Centered media player pill with live Cava visualizer background + rich
//   popup (art, controls, seek, player selector, PipeWire sources).
//
// Theme Properties Consumed:
//   - bar.glassPillBg, bar.glassHover, bar.glassBorder, bar.glassHighlight
//   - bar.pillRadius, bar.controlBorderWidth, bar.accent, bar.subtext, bar.text,
//     bar.overlay, bar.surface
//   - bar.iconSizePill, bar.fontFamily, bar.fontMono
//   - bar.popupRadius, bar.glassPopupBg, bar.glassPopupBorder,
//     bar.glassPopupHighlight, bar.popupHeaderHighlightHeight,
//     bar.popupSpacing, bar.popupTitleSize, bar.popupSectionSize,
//     bar.popupHintSize, bar.popupButtonHoverBg, bar.dividerStrong,
//     bar.buttonRadius
//   - bar.popupMediaWidth, bar.popupMediaHeight
//
// Dependencies:
//   - required property var bar
//   - required property Item barBg (for popup positioning)
//   - Quickshell.Services.Mpris
//   - Quickshell.Services.Pipewire
//   - Quickshell.Widgets (ClippingRectangle, IconImage)
//
// Notes:
//   - All MPRIS logic, player management, seek behavior, browser audio node
//     detection, and popup functionality are preserved exactly.
//   - CavaVisualizer integration remains clean (we just templated the component).
// =============================================================================

Rectangle {
    id: root

    required property var bar
    required property Item barBg

    // Whether any media is currently playing (drives visibility + coupling with SysStatsPill)
    readonly property bool hasMedia: media.title !== ""

    readonly property real _ws: (bar.widgetScale ? bar.widgetScale("media") : 1.0)
    Layout.preferredWidth: Math.round(600 * _ws)
    Layout.preferredHeight: bar.pillHeight
    Layout.alignment: Qt.AlignVCenter
    visible: hasMedia
    implicitWidth: 600
    implicitHeight: Layout.preferredHeight
    radius: bar.pillRadius
    color: mediaHover.containsMouse ? bar.glassHover : bar.glassPillBg
    border.width: bar.controlBorderWidth
    border.color: mediaHover.containsMouse ? bar.accent : bar.pillBorder

    // ===== MEDIA STATE (logic preserved exactly) =====
    QtObject {
        id: media

        readonly property var allPlayers: (Mpris.players && Mpris.players.values) ? Mpris.players.values : []

        property var players: []
        property int currentIndex: 0
        readonly property var currentPlayer: (players.length > 0 && currentIndex >= 0 && currentIndex < players.length)
            ? players[currentIndex] : null

        property var firstSeen: ({})

        property var browserAudioNodes: []

        readonly property string title: currentPlayer ? (currentPlayer.trackTitle || (currentPlayer.metadata ? currentPlayer.metadata["xesam:title"] || "" : "")) : ""
        readonly property string artist: {
            if (!currentPlayer) return "";
            const md = currentPlayer.metadata || {};
            const a = md["xesam:artist"];
            if (Array.isArray(a)) return a.join(", ");
            if (typeof a === "string") return a;
            return currentPlayer.identity || "";
        }
        readonly property string album: currentPlayer ? ((currentPlayer.metadata || {})["xesam:album"] || "") : ""
        readonly property string artUrl: currentPlayer ? ((currentPlayer.metadata || {})["mpris:artUrl"] || "") : ""
        readonly property string appName: currentPlayer ? (currentPlayer.identity || currentPlayer.desktopEntry || "Media") : ""
        readonly property bool isPlaying: currentPlayer ? !!currentPlayer.isPlaying : false
        readonly property bool canToggle: currentPlayer ? !!currentPlayer.canTogglePlaying : false
        readonly property bool canNext: currentPlayer ? !!currentPlayer.canGoNext : false
        readonly property bool canPrev: currentPlayer ? !!currentPlayer.canGoPrevious : false
        readonly property bool canSeek: currentPlayer ? !!currentPlayer.canSeek : false
        readonly property real position: currentPlayer ? currentPlayer.position : 0
        readonly property real length: currentPlayer ? currentPlayer.length : 0
        readonly property bool lengthSupported: currentPlayer ? !!currentPlayer.lengthSupported : false

        function refreshPlayers() {
            Qt.callLater(media._actuallyRefreshPlayers);
        }

        function _actuallyRefreshPlayers() {
            const raw = (Mpris.players && Mpris.players.values) ? Mpris.players.values : [];
            let candidates = [];
            let currentKeys = new Set();

            for (let i = 0; i < raw.length; i++) {
                const p = raw[i];
                if (!p) continue;
                const t = p.trackTitle || (p.metadata ? p.metadata["xesam:title"] : "") || "";
                if (!t) continue;
                if (!p.isPlaying) continue;

                candidates.push(p);

                const key = p.dbusName || ("id:" + p.uniqueId);
                if (key) {
                    currentKeys.add(key);
                    if (media.firstSeen[key] === undefined) {
                        media.firstSeen[key] = Date.now();
                    }
                }
            }

            for (let k in media.firstSeen) {
                if (!currentKeys.has(k)) {
                    delete media.firstSeen[k];
                }
            }

            if (candidates.length === 0) {
                media.players = [];
                media.currentIndex = 0;
                return;
            }

            let newIdx = 0;

            if (media.currentPlayer && candidates.length > 0) {
                let found = -1;
                for (let i = 0; i < candidates.length; i++) {
                    if (candidates[i] === media.currentPlayer) { found = i; break; }
                }
                if (found !== -1) {
                    newIdx = found;
                } else {
                    newIdx = 0;
                }
            }

            media.players = candidates;
            if (newIdx >= candidates.length) newIdx = 0;
            media.currentIndex = newIdx;
        }

        function cycleNext() {
            if (players.length < 2) return;
            currentIndex = (currentIndex + 1) % players.length;
        }
        function cyclePrev() {
            if (players.length < 2) return;
            currentIndex = (currentIndex - 1 + players.length) % players.length;
        }
        function selectPlayer(idx) {
            if (idx >= 0 && idx < players.length) currentIndex = idx;
        }

        function forceRescan() {
            console.log("Media: user requested force rescan of MPRIS players");
            firstSeen = ({});
            _actuallyRefreshPlayers();
            refreshBrowserAudioNodes();
        }

        function refreshBrowserAudioNodes() {
            const vals = (Pipewire.nodes && Pipewire.nodes.values) ? Pipewire.nodes.values : [];
            let result = [];

            const browserHints = ["brave", "firefox", "chrome", "chromium", "audacious", "mpv", "vlc", "spotify", "deadbeef", "rhythmbox", "clementine"];

            for (let i = 0; i < vals.length; i++) {
                const n = vals[i];
                if (!n || !n.audio) continue;

                const props = n.properties || {};
                const appName = props["application.name"] || n.name || "";
                const lower = appName.toLowerCase();

                let isBrowser = false;
                for (let b = 0; b < browserHints.length; b++) {
                    if (lower.indexOf(browserHints[b]) !== -1) {
                        isBrowser = true;
                        break;
                    }
                }
                if (!isBrowser) continue;

                const mediaName = props["media.name"] || "";
                const nodeName = n.name || "";
                const role = props["media.role"] || "";
                const mediaClass = props["media.class"] || "";

                result.push({
                    app: appName,
                    mediaName: mediaName,
                    nodeName: nodeName,
                    role: role,
                    mediaClass: mediaClass,
                    isOutput: !!n.isStream || !n.isSink,
                    volume: (n.audio.volume !== undefined) ? n.audio.volume : 0,
                    muted: !!n.audio.muted
                });
            }

            media.browserAudioNodes = result;
        }

        function toggleCurrent() {
            if (currentPlayer && currentPlayer.canTogglePlaying) {
                currentPlayer.togglePlaying();
            } else if (currentPlayer && currentPlayer.canPause && currentPlayer.isPlaying) {
                currentPlayer.pause();
            } else if (currentPlayer && currentPlayer.canPlay) {
                currentPlayer.play();
            }
        }

        function nextTrack() {
            if (currentPlayer && currentPlayer.canGoNext) currentPlayer.next();
        }
        function prevTrack() {
            if (currentPlayer && currentPlayer.canGoPrevious) currentPlayer.previous();
        }

        function seekTo(ms) {
            if (!currentPlayer || !currentPlayer.canSeek) return;
            const clamped = Math.max(0, Math.min(ms, currentPlayer.length || ms));
            if (currentPlayer.setPosition) {
                currentPlayer.setPosition(clamped);
            } else if (currentPlayer.seek) {
                currentPlayer.seek(clamped - (currentPlayer.position || 0));
            }
        }

        function seekRelative(deltaMs) {
            if (!currentPlayer || !currentPlayer.canSeek) return;
            seekTo((currentPlayer.position || 0) + deltaMs);
        }
    }

    Connections {
        target: Mpris.players
        function onValuesChanged() { media.refreshPlayers(); }
    }

    // Lightweight periodic rescan for MPRIS (self-contained now that media state lives here).
    // Catches players that mutate metadata/playback in place without emitting valuesChanged
    // (Audacious, mpv, some VLC, browser edge cases, etc.).
    Timer {
        interval: 1500
        running: true
        repeat: true
        onTriggered: media.refreshPlayers()
    }

    Component.onCompleted: {
        // Pick up any already-registered MPRIS players (Spotify, browsers left open, etc.)
        Qt.callLater(media.refreshPlayers);
        media.refreshBrowserAudioNodes();
    }

    // === Appearance via Theme ===
    // Subtle top highlight
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: bar.glassHighlight
        radius: parent.radius
    }

    // Cava visualizer background
    CavaVisualizer {
        anchors.fill: parent
        anchors.margins: 4
        bar: bar
        active: Qt.binding(function(){ return media.isPlaying; })
    }

    Row {
        id: mediaRow
        anchors.centerIn: parent
        spacing: 8
        z: 1

        // Play/pause indicator
        Text {
            text: media.isPlaying ? "▶" : "⏸"
            font.pixelSize: bar.iconSizePill
            font.family: bar.fontFamily
            color: media.isPlaying ? bar.accent : (bar.iconColor !== undefined ? bar.iconColor : bar.subtext)
            anchors.verticalCenter: parent.verticalCenter
        }

        // Title (bar face — Themes → Bar widget text)
        Text {
            text: media.title || "No media"
            color: (bar.barText !== undefined) ? bar.barText : bar.text
            font.pixelSize: 15
            font.bold: true
            font.family: bar.fontFamily
            elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: mediaHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                if (event.angleDelta.y > 0) {
                    media.cyclePrev();
                } else {
                    media.cycleNext();
                }
            }
        }

        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton) {
                media.toggleCurrent();
            } else if (mouse.button === Qt.RightButton) {
                showMediaPopup();
            }
        }
    }

    // ===== MEDIA POPUP HELPERS (logic preserved exactly) =====
    function showMediaPopup() {
        if (mediaPopup.visible) {
            mediaPopup.visible = false;
            return;
        }

        // Force a fresh player scan (synchronous internal call) before the guard.
        // refreshPlayers() itself is async via callLater; we need up-to-date players here.
        media._actuallyRefreshPlayers();

        if (!root.visible || !media.currentPlayer) {
            console.log("MediaPill: not showing popup (visible:", root.visible, "currentPlayer:", media.currentPlayer, "players.length:", media.players ? media.players.length : 0);
            return;
        }

        // Position under the bar, centered on the media pill
        var popupW = mediaPopup.implicitWidth;
        if (typeof bar.placePopup === "function") {
            bar.placePopup(mediaPopup, root, popupW, mediaPopup.implicitHeight, undefined, root.width / 2);
        } else {
            var pos = root.mapToItem(barBg, root.width / 2, root.height);
            var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920;
            var targetX = bar.sideMargin + pos.x - (popupW / 2);
            var minX = 12;
            var maxX = screenW - popupW - 12;
            mediaPopup.anchor.rect.x = Math.max(minX, Math.min(targetX, maxX));
            mediaPopup.anchor.rect.y = bar.popupAnchorY(mediaPopup.implicitHeight);
        }

        media.refreshBrowserAudioNodes();

        mediaPopup.visible = true;
    }

    function hideMediaPopup() {
        mediaPopup.visible = false;
    }

    // ===== MEDIA POPUP (rich controls, art, seek, player selector) =====
    PopupWindow {
        id: mediaPopup
        anchor.window: bar
        implicitWidth: bar.popupMediaWidth
        implicitHeight: bar.popupMediaHeight
        visible: false
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: bar.popupRadius
            color: bar.glassPopupBg
            border.width: bar.controlBorderWidth
            border.color: bar.glassPopupBorder

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: bar.popupHeaderHighlightHeight
                color: bar.glassPopupHighlight
                radius: parent.radius
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: bar.popupSpacing
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: media.appName
                        color: bar.text
                        font.pixelSize: bar.popupSectionSize
                        font.bold: true
                    }
                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredWidth: 68
                        Layout.preferredHeight: 20
                        radius: bar.buttonRadius
                        color: rescanMa.containsMouse ? bar.glassHover : bar.surface
                        border.width: bar.controlBorderWidth
                        border.color: bar.glassBorder

                        Row {
                            anchors.centerIn: parent
                            spacing: 4
                            Text {
                                text: "⟳"
                                font.pixelSize: 12
                                color: bar.accent
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "Rescan"
                                font.pixelSize: bar.popupHintSize
                                color: bar.text
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea {
                            id: rescanMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: media.forceRescan()
                        }
                    }

                    Text {
                        text: "click outside to close"
                        color: bar.subtext
                        font.pixelSize: bar.popupHintSize
                        Layout.leftMargin: 8
                    }
                }

                // Art + metadata
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    Rectangle {
                        Layout.preferredWidth: 110
                        Layout.preferredHeight: 110
                        radius: 8
                        color: bar.surface
                        border.width: bar.controlBorderWidth
                        border.color: bar.dividerStrong

                        ClippingRectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: 6
                            color: "transparent"

                            Image {
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop
                                source: media.artUrl
                                visible: media.artUrl !== ""
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: media.artUrl === ""
                            text: "󰝚"
                            font.pixelSize: 42
                            color: bar.subtext
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            Layout.fillWidth: true
                            text: media.title || "(no title)"
                            color: bar.text
                            font.pixelSize: 18
                            font.bold: true
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: media.artist !== ""
                            text: media.artist
                            color: bar.subtext
                            font.pixelSize: 14
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: media.album !== ""
                            text: media.album
                            color: bar.subtext
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }
                    }
                }

                // Transport controls
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 24
                    Layout.topMargin: 6

                    Rectangle {
                        width: 42; height: 42; radius: 21
                        color: prevMa.containsMouse ? bar.glassHover : "transparent"
                        border.width: bar.controlBorderWidth
                        border.color: media.canPrev ? bar.glassBorder : "#333"
                        opacity: media.canPrev ? 1.0 : 0.4

                        Text {
                            anchors.centerIn: parent
                            text: "󰒮"
                            font.pixelSize: 20
                            color: bar.text
                        }
                        MouseArea {
                            id: prevMa
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            enabled: media.canPrev
                            onClicked: media.prevTrack()
                        }
                    }

                    Rectangle {
                        width: 58; height: 58; radius: 29
                        color: playMa.containsMouse ? bar.accent : bar.glassHover
                        border.width: bar.controlBorderWidth
                        border.color: bar.accent

                        Text {
                            anchors.centerIn: parent
                            text: media.isPlaying ? "󰏤" : "󰐊"
                            font.pixelSize: 26
                            color: playMa.containsMouse ? bar.bg : bar.text
                        }
                        MouseArea {
                            id: playMa
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: media.toggleCurrent()
                        }
                    }

                    Rectangle {
                        width: 42; height: 42; radius: 21
                        color: nextMa.containsMouse ? bar.glassHover : "transparent"
                        border.width: bar.controlBorderWidth
                        border.color: media.canNext ? bar.glassBorder : "#333"
                        opacity: media.canNext ? 1.0 : 0.4

                        Text {
                            anchors.centerIn: parent
                            text: "󰒭"
                            font.pixelSize: 20
                            color: bar.text
                        }
                        MouseArea {
                            id: nextMa
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            enabled: media.canNext
                            onClicked: media.nextTrack()
                        }
                    }
                }

                // Seek bar
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: media.canSeek && media.lengthSupported && media.length > 0
                    spacing: 4

                    Rectangle {
                        id: seekTrack
                        Layout.fillWidth: true
                        Layout.preferredHeight: 6
                        radius: 3
                        color: bar.surface

                        Rectangle {
                            width: Math.max(0, Math.min(parent.width, (media.position / media.length) * parent.width))
                            height: parent.height
                            radius: 3
                            color: bar.accent
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (m) => {
                                if (media.length > 0) {
                                    const frac = m.x / width;
                                    media.seekTo(frac * media.length);
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: Qt.formatTime(new Date(media.position), "mm:ss")
                            color: bar.subtext
                            font.pixelSize: 11
                            font.family: bar.fontMono
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: Qt.formatTime(new Date(media.length), "mm:ss")
                            color: bar.subtext
                            font.pixelSize: 11
                            font.family: bar.fontMono
                        }
                    }
                }

                // Player selector
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: media.players.length > 1
                    spacing: 4

                    Text {
                        text: "Active streams"
                        color: bar.text
                        font.pixelSize: bar.popupHintSize
                        font.bold: true
                    }

                    Flickable {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 58
                        contentWidth: playerRow.implicitWidth
                        clip: true

                        Row {
                            id: playerRow
                            spacing: 6

                            Repeater {
                                model: media.players
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index

                                    width: 170
                                    height: 52
                                    radius: 6
                                    color: index === media.currentIndex ? Qt.rgba(0.55, 0.71, 0.98, 0.18) : bar.surface
                                    border.width: index === media.currentIndex ? 1 : 0
                                    border.color: bar.accent

                                    Column {
                                        anchors.fill: parent
                                        anchors.margins: 5
                                        spacing: 1

                                        Row {
                                            width: parent.width
                                            spacing: 4
                                            Text {
                                                text: modelData.identity || modelData.desktopEntry || "Player"
                                                color: bar.text
                                                font.pixelSize: 11
                                                font.bold: true
                                                elide: Text.ElideRight
                                            }
                                        }
                                        Text {
                                            text: (modelData.trackTitle || "").substring(0, 26)
                                            color: bar.subtext
                                            font.pixelSize: 10
                                            elide: Text.ElideRight
                                            width: parent.width
                                        }
                                        Text {
                                            visible: modelData.dbusName
                                            text: (modelData.dbusName || "").replace("org.mpris.MediaPlayer2.", "")
                                            color: bar.subtext
                                            font.pixelSize: 8
                                            elide: Text.ElideRight
                                            width: parent.width
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: media.selectPlayer(index);
                                    }
                                }
                            }
                        }
                    }
                }

                // PipeWire section
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: media.browserAudioNodes.length > 0
                    spacing: 4
                    Layout.topMargin: 8

                    Text {
                        text: "Audio sources from PipeWire"
                        color: bar.text
                        font.pixelSize: bar.popupHintSize
                        font.bold: true
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 2

                        Repeater {
                            model: media.browserAudioNodes
                            delegate: Text {
                                required property var modelData
                                readonly property string volInfo: modelData.muted ? " (muted)" :
                                    (modelData.volume > 0 ? " • vol " + Math.round(modelData.volume * 100) + "%" : "")

                                text: modelData.app + (modelData.mediaName ? " — " + modelData.mediaName : "") + (modelData.role ? " [" + modelData.role + "]" : "") + volInfo
                                color: bar.subtext
                                font.pixelSize: 10
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }
                    }

                    Text {
                        text: "Direct PipeWire nodes (browsers + Audacious, mpv, etc). Independent of MPRIS."
                        color: bar.subtext
                        font.pixelSize: 9
                        font.italic: true
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: mediaPopup.visible = false
        }
    }
}
