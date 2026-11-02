import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io as Io
import "../components"

// Circle-opacity icon. Click opens Apps and Satty transparency sliders.
// Apps sets Hyprland window opacity for every application window.
// Satty sets only class com.gabm.satty. Fullscreen and the Settings
// window stay solid. 0 in the state file means that slider was never moved.
Rectangle {
    id: root

    required property var bar
    required property Item barBg

    readonly property real _ws: (bar.widgetScale ? bar.widgetScale("opacity") : 1.0)
    readonly property string scriptPath: (bar.opacityApplyScript && String(bar.opacityApplyScript).length)
        ? String(bar.opacityApplyScript)
        : "/home/crome/.config/quickshell/scripts/opacity-apply.sh"
    // 0 = never applied. The slider shows 100 until the user moves it.
    property int appsRaw: 0
    property int sattyRaw: 0
    property int appsShown: 100
    property int sattyShown: 100
    property bool stateReady: false
    property bool userMoved: false

    Layout.preferredWidth: Math.round(42 * _ws)
    Layout.preferredHeight: bar.pillHeight
    Layout.alignment: Qt.AlignVCenter
    clip: false

    function clampPct(v) {
        let n = Math.round(Number(v))
        if (!(n >= 5))
            n = 5
        if (n > 100)
            n = 100
        return n
    }

    function shownFor(raw) {
        return raw >= 5 ? raw : 100
    }

    function applyState(apps, satty) {
        root.appsRaw = apps
        root.sattyRaw = satty
        root.appsShown = root.shownFor(apps)
        root.sattyShown = root.shownFor(satty)
    }

    function parseState(text) {
        let apps = 0
        let satty = 0
        const lines = String(text || "").split("\n")
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i]
            const eq = line.indexOf("=")
            if (eq < 1)
                continue
            const key = line.slice(0, eq).trim()
            const val = parseInt(line.slice(eq + 1), 10)
            if (!(val === 0 || (val >= 5 && val <= 100)))
                continue
            if (key === "apps")
                apps = val
            else if (key === "satty")
                satty = val
        }
        if (!root.userMoved)
            root.applyState(apps, satty)
        root.stateReady = true
    }

    function unchanged(n, shown, raw) {
        return (n === shown && raw === 0) || (n === raw && raw !== 0)
    }

    function onAppsMoved(v, flush) {
        const n = root.clampPct(v)
        if (root.unchanged(n, root.appsShown, root.appsRaw)) {
            if (flush && applyDelay.running)
                root.scheduleApply(true)
            return
        }
        root.userMoved = true
        root.appsShown = n
        root.appsRaw = n
        root.scheduleApply(!!flush)
    }

    function onSattyMoved(v, flush) {
        const n = root.clampPct(v)
        if (root.unchanged(n, root.sattyShown, root.sattyRaw)) {
            if (flush && applyDelay.running)
                root.scheduleApply(true)
            return
        }
        root.userMoved = true
        root.sattyShown = n
        root.sattyRaw = n
        root.scheduleApply(!!flush)
    }

    function scheduleApply(immediate) {
        if (!root.stateReady)
            return
        if (immediate) {
            applyDelay.stop()
            root.kickApply()
        } else {
            applyDelay.restart()
        }
    }

    function kickApply() {
        if (!root.stateReady)
            return
        if (applyProc.running) {
            applyProc.queued = true
            return
        }
        applyProc.command = [root.scriptPath, "set", String(root.appsRaw), String(root.sattyRaw)]
        applyProc.running = true
    }

    function hideMenu() {
        opacityPopup.visible = false
    }

    function showMenu() {
        const popupW = opacityPopup.implicitWidth
        const popupH = opacityPopup.implicitHeight
        if (typeof bar.placePopup === "function") {
            bar.placePopup(opacityPopup, root, popupW, popupH, 2, root.width / 2)
        } else {
            const pos = root.mapToItem(barBg, root.width / 2, 0)
            const screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920
            const targetX = bar.sideMargin + pos.x - (popupW / 2)
            opacityPopup.anchor.rect.x = Math.max(12, Math.min(targetX, screenW - popupW - 12))
            opacityPopup.anchor.rect.y = bar.popupAnchorY(popupH, 2)
        }
        opacityPopup.visible = true
    }

    function toggleMenu() {
        if (opacityPopup.visible)
            root.hideMenu()
        else
            root.showMenu()
    }

    DockFace {
        id: dockFx
        bar: root.bar
        host: root
        hovered: opacityMouse.containsMouse
    }
    transform: [
        Scale {
            xScale: dockFx.mag
            yScale: dockFx.mag
            origin.x: root.width / 2
            origin.y: dockFx.growUp ? root.height : 0
        },
        Translate { y: dockFx.jumpY }
    ]

    radius: bar.pillRadius
    color: opacityMouse.containsMouse || opacityPopup.visible ? bar.glassHover : bar.pillBg
    border.width: bar.controlBorderWidth
    border.color: opacityMouse.containsMouse || opacityPopup.visible ? bar.accent : bar.pillBorder

    Text {
        anchors.centerIn: parent
        text: bar.iconOpacity
        font.pixelSize: Math.max(10, Math.round(bar.iconSizePillLarge * _ws))
        font.family: bar.fontFamily
        color: opacityMouse.containsMouse || opacityPopup.visible
               ? bar.accent
               : (bar.iconColor !== undefined ? bar.iconColor : bar.subtext)
    }

    MouseArea {
        id: opacityMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            dockFx.jump()
            root.toggleMenu()
        }
        BarToolTip {
            bar: root.bar
            widgetId: "opacity"
            visible: opacityMouse.containsMouse && !opacityPopup.visible
            text: "Window transparency"
            anchorItem: opacityMouse
        }
    }

    Timer {
        id: applyDelay
        interval: 70
        repeat: false
        onTriggered: root.kickApply()
    }

    Io.Process {
        id: readProc
        command: [root.scriptPath, "get"]
        running: true
        stdout: Io.StdioCollector {
            onStreamFinished: {
                if (root.stateReady && (applyDelay.running || applyProc.running))
                    return
                root.parseState(text)
            }
        }
    }

    Io.Process {
        id: applyProc
        property bool queued: false
        stdout: Io.StdioCollector { }
        stderr: Io.StdioCollector {
            onStreamFinished: {
                const msg = String(text || "").trim()
                if (msg.length)
                    console.warn("opacity-apply: " + msg)
            }
        }
        onRunningChanged: {
            if (running)
                return
            if (queued) {
                queued = false
                Qt.callLater(root.kickApply)
            }
        }
    }

    PopupWindow {
        id: opacityPopup
        anchor.window: bar
        implicitWidth: bar.sp(360)
        implicitHeight: Math.max(bar.sp(248), opacityColumn.implicitHeight + bar.popupSpacing * 2)
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
                id: opacityColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: bar.popupSpacing
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "Transparency"
                    color: bar.text
                    font.pixelSize: bar.popupTitleSize
                    font.bold: true
                    font.family: bar.fontFamily
                }

                Text {
                    Layout.fillWidth: true
                    text: "Apps"
                    color: bar.text
                    font.pixelSize: 13
                    font.bold: true
                    font.family: bar.fontFamily
                }
                Text {
                    Layout.fillWidth: true
                    text: "Background transparency for application windows"
                    color: bar.subtext
                    font.pixelSize: bar.popupHintSize
                    font.family: bar.fontFamily
                    wrapMode: Text.WordWrap
                }
                OptValueSlider {
                    bar: root.bar
                    from: 5
                    to: 100
                    stepSize: 1
                    suffix: "%"
                    value: root.appsShown
                    onValueEdited: (v) => root.onAppsMoved(v, false)
                    onValueCommitted: (v) => root.onAppsMoved(v, true)
                }

                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    text: "Satty"
                    color: bar.text
                    font.pixelSize: 13
                    font.bold: true
                    font.family: bar.fontFamily
                }
                Text {
                    Layout.fillWidth: true
                    text: "Satty window only"
                    color: bar.subtext
                    font.pixelSize: bar.popupHintSize
                    font.family: bar.fontFamily
                    wrapMode: Text.WordWrap
                }
                OptValueSlider {
                    bar: root.bar
                    from: 5
                    to: 100
                    stepSize: 1
                    suffix: "%"
                    value: root.sattyShown
                    onValueEdited: (v) => root.onSattyMoved(v, false)
                    onValueCommitted: (v) => root.onSattyMoved(v, true)
                }

                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    text: "100% is solid. Fullscreen and Settings stay solid."
                    color: bar.subtext
                    font.pixelSize: bar.popupHintSize
                    font.family: bar.fontFamily
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    function show() { root.showMenu() }
    function hide() { root.hideMenu() }
    function toggle() { root.toggleMenu() }
}
