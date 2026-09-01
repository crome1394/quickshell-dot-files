import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io as Io

// Clickable equirectangular timezone map (installer-style) for the Clock panel.
// Zones from zone1970.tab; land from assets/world-land.json (Natural Earth, public domain).
Item {
    id: root

    property bool active: false
    property var keyboardGrab: null
    // Called just before timedatectl/pkexec so the control-bar popup can hide
    // and not cover the password prompt.
    property var beforeApply: null

    property color textColor: "#f0f4fc"
    property color subtextColor: "#a8b4c8"
    property color accentColor: "#00F0E0"
    property color surfaceColor: "#141a24"
    property color oceanColor: "#0b1220"
    property color landColor: "#2a3a4e"
    property color gridColor: Qt.rgba(1, 1, 1, 0.07)
    property color fieldBg: Qt.rgba(0.10, 0.12, 0.18, 0.92)
    property color fieldBgFocus: Qt.rgba(0.14, 0.16, 0.24, 0.95)
    property color pillBorder: Qt.rgba(1, 1, 1, 0.12)
    property color okColor: "#2ee59a"
    property color errorColor: "#FF3D8A"
    property string fontFamily: "sans-serif"
    property string fontMono: "monospace"
    property int chipR: 8

    property var zones: []
    property var landRings: []
    property string currentId: ""
    property string pendingId: ""
    property string hoverId: ""
    property string searchText: ""
    property string statusMsg: ""
    property string errorMsg: ""
    property var pendingPreview: ({})
    property bool loading: false
    property bool applying: false
    property int dataVersion: 0

    readonly property var pendingZone: root.findZone(root.pendingId)
    readonly property var currentZone: root.findZone(root.currentId)
    readonly property bool dirty: root.pendingId.length > 0 && root.pendingId !== root.currentId

    implicitWidth: 480

    onOceanColorChanged: if (mapCanvas) mapCanvas.requestPaint()
    onLandColorChanged: if (mapCanvas) mapCanvas.requestPaint()
    onGridColorChanged: if (mapCanvas) mapCanvas.requestPaint()
    onAccentColorChanged: if (mapCanvas) mapCanvas.requestPaint()

    function scriptPath() {
        const u = Qt.resolvedUrl("../scripts/timezone-control.sh").toString()
        return u.replace(/^file:\/\//, "")
    }

    function findZone(id) {
        const want = String(id || "")
        const list = root.zones || []
        for (let i = 0; i < list.length; i++) {
            if (list[i] && list[i].id === want)
                return list[i]
        }
        return null
    }

    function lonToX(lon, w) {
        return ((Number(lon) + 180) / 360) * w
    }
    function latToY(lat, h) {
        return ((90 - Number(lat)) / 180) * h
    }
    function xToLon(x, w) {
        return (x / Math.max(1, w)) * 360 - 180
    }
    function yToLat(y, h) {
        return 90 - (y / Math.max(1, h)) * 180
    }

    function nearestZone(lat, lon) {
        const list = root.zones || []
        let best = null
        let bestD = 1e15
        const cos = Math.cos(lat * Math.PI / 180)
        for (let i = 0; i < list.length; i++) {
            const z = list[i]
            if (!z)
                continue
            const dLat = Number(z.lat) - lat
            let dLon = Number(z.lon) - lon
            if (dLon > 180)
                dLon -= 360
            if (dLon < -180)
                dLon += 360
            const d = dLat * dLat + (dLon * cos) * (dLon * cos)
            if (d < bestD) {
                bestD = d
                best = z
            }
        }
        return best
    }

    function filteredZones() {
        void root.dataVersion
        const q = String(root.searchText || "").trim().toLowerCase()
        const list = root.zones || []
        if (!q.length)
            return list
        const out = []
        for (let i = 0; i < list.length; i++) {
            const z = list[i]
            if (!z)
                continue
            const hay = (z.id + " " + z.city + " " + z.region + " " + (z.comment || "")).toLowerCase()
            if (hay.indexOf(q) >= 0)
                out.push(z)
        }
        return out
    }

    function zoneLabel(z) {
        if (!z)
            return ""
        if (z.comment && String(z.comment).length)
            return z.city + " · " + z.comment
        return z.city
    }

    function cssColor(c, alpha) {
        if (!c)
            return "rgba(0,0,0,1)"
        const a = (alpha === undefined || alpha === null) ? (c.a !== undefined ? c.a : 1) : alpha
        return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + ","
                + Math.round(c.b * 255) + "," + a + ")"
    }

    function selectZone(id, applyNow) {
        const z = root.findZone(id)
        if (!z)
            return
        root.pendingId = z.id
        root.errorMsg = ""
        root.refreshPreview(z.id)
        if (applyNow)
            root.applyPending()
        mapCanvas.requestPaint()
    }

    function refreshAll() {
        root.loadStatus()
        root.loadList()
        root.loadLand()
    }

    function loadStatus() {
        if (statusProc.running)
            return
        statusProc.exec([root.scriptPath(), "status-json"])
    }

    function loadList() {
        if (listProc.running)
            return
        root.loading = true
        listProc.exec([root.scriptPath(), "list-json"])
    }

    function loadLand() {
        if (landProc.running)
            return
        landProc.exec([root.scriptPath(), "land-json"])
    }

    function refreshPreview(id) {
        const tz = String(id || "")
        if (!tz.length)
            return
        previewProc.exec([root.scriptPath(), "preview", tz])
    }

    function applyPending() {
        if (!root.dirty || root.applying)
            return
        const tz = String(root.pendingId || "")
        if (!tz.length)
            return
        root.applying = true
        root.errorMsg = ""
        root.statusMsg = "Setting " + tz + "…"
        applyDelay.tz = tz
        if (typeof root.beforeApply === "function")
            root.beforeApply()
        // Let the layer-shell popup unmap before pkexec so the prompt is visible.
        applyDelay.restart()
    }

    Timer {
        id: applyDelay
        property string tz: ""
        interval: 180
        repeat: false
        onTriggered: {
            const tz = String(applyDelay.tz || "")
            applyDelay.tz = ""
            if (!tz.length) {
                root.applying = false
                return
            }
            setProc.exec([root.scriptPath(), "set", tz])
        }
    }

    onActiveChanged: {
        if (active) {
            root.refreshAll()
        } else {
            root.hoverId = ""
            root.statusMsg = ""
            root.errorMsg = ""
        }
    }

    Io.Process {
        id: statusProc
        running: false
        stdout: Io.StdioCollector {
            id: statusOut
            onStreamFinished: {
                const t = (statusOut.text || "").trim()
                if (!t.startsWith("{"))
                    return
                try {
                    const j = JSON.parse(t)
                    root.currentId = String(j.timezone || "")
                    if (!root.pendingId.length)
                        root.pendingId = root.currentId
                    if (root.pendingId === root.currentId)
                        root.pendingPreview = j
                    root.dataVersion++
                    mapCanvas.requestPaint()
                } catch (e) {}
            }
        }
    }

    Io.Process {
        id: listProc
        running: false
        stdout: Io.StdioCollector {
            id: listOut
            onStreamFinished: {
                root.loading = false
                const t = (listOut.text || "").trim()
                if (!t.startsWith("["))
                    return
                try {
                    root.zones = JSON.parse(t)
                    root.dataVersion++
                    mapCanvas.requestPaint()
                } catch (e) {
                    root.zones = []
                }
            }
        }
    }

    Io.Process {
        id: landProc
        running: false
        stdout: Io.StdioCollector {
            id: landOut
            onStreamFinished: {
                const t = (landOut.text || "").trim()
                if (!t.startsWith("{"))
                    return
                try {
                    const j = JSON.parse(t)
                    root.landRings = j.rings || []
                    mapCanvas.requestPaint()
                } catch (e) {}
            }
        }
    }

    Io.Process {
        id: previewProc
        running: false
        stdout: Io.StdioCollector {
            id: previewOut
            onStreamFinished: {
                const t = (previewOut.text || "").trim()
                if (!t.startsWith("{"))
                    return
                try {
                    root.pendingPreview = JSON.parse(t)
                } catch (e) {}
            }
        }
    }

    Io.Process {
        id: setProc
        running: false
        stdout: Io.StdioCollector {
            id: setOut
            onStreamFinished: {
                const t = (setOut.text || "").trim()
                if (t.startsWith("{")) {
                    try {
                        const j = JSON.parse(t)
                        root.currentId = String(j.timezone || root.pendingId)
                        root.pendingId = root.currentId
                        root.pendingPreview = j
                        root.statusMsg = "Region set to " + root.currentId
                        root.errorMsg = ""
                        root.dataVersion++
                        mapCanvas.requestPaint()
                    } catch (e) {}
                }
            }
        }
        onExited: (code) => {
            root.applying = false
            if (code !== 0) {
                const t = (setOut.text || "").trim()
                root.errorMsg = t.replace(/^error:\s*/i, "").slice(0, 160) || ("Could not set timezone (" + code + ")")
                root.statusMsg = ""
            }
        }
    }

    ColumnLayout {
        id: col
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
                text: "Region"
                color: root.textColor
                font.pixelSize: 13
                font.bold: true
                font.family: root.fontFamily
            }
            Item { Layout.fillWidth: true }
            Text {
                text: {
                    const z = root.currentZone
                    const p = root.pendingPreview || {}
                    const abbr = p.abbr ? (" · " + p.abbr) : ""
                    if (z)
                        return z.id + abbr
                    return root.currentId || "Detecting…"
                }
                color: root.subtextColor
                font.pixelSize: 11
                font.family: root.fontMono
                elide: Text.ElideMiddle
                Layout.maximumWidth: 280
            }
        }

        Text {
            Layout.fillWidth: true
            text: "Click the map or pick a city — same idea as a Linux installer region step."
            color: root.subtextColor
            font.pixelSize: 11
            font.family: root.fontFamily
            wrapMode: Text.WordWrap
        }

        Rectangle {
            id: mapFrame
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(168, Math.min(268, Math.round(width * 0.5)))
            radius: root.chipR
            color: root.oceanColor
            border.width: 1
            border.color: root.pillBorder
            clip: true

            Canvas {
                id: mapCanvas
                anchors.fill: parent
                antialiasing: true
                renderTarget: Canvas.FramebufferObject
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d")
                    const w = width
                    const h = height
                    if (w < 8 || h < 8)
                        return
                    ctx.reset()
                    ctx.fillStyle = root.cssColor(root.oceanColor)
                    ctx.fillRect(0, 0, w, h)

                    ctx.strokeStyle = root.cssColor(root.gridColor)
                    ctx.lineWidth = 1
                    for (let lon = -180; lon <= 180; lon += 15) {
                        const x = root.lonToX(lon, w)
                        ctx.beginPath()
                        ctx.moveTo(x, 0)
                        ctx.lineTo(x, h)
                        ctx.stroke()
                    }
                    ctx.beginPath()
                    ctx.moveTo(0, root.latToY(0, h))
                    ctx.lineTo(w, root.latToY(0, h))
                    ctx.stroke()

                    const rings = root.landRings || []
                    ctx.fillStyle = root.cssColor(root.landColor)
                    ctx.lineWidth = 0.6
                    for (let r = 0; r < rings.length; r++) {
                        const ring = rings[r]
                        if (!ring || ring.length < 3)
                            continue
                        ctx.beginPath()
                        for (let i = 0; i < ring.length; i++) {
                            const p = ring[i]
                            const x = root.lonToX(p[0], w)
                            const y = root.latToY(p[1], h)
                            if (i === 0)
                                ctx.moveTo(x, y)
                            else
                                ctx.lineTo(x, y)
                        }
                        ctx.closePath()
                        ctx.fill()
                    }

                    const zones = root.zones || []
                    const sel = root.pendingId
                    const hov = root.hoverId
                    for (let i = 0; i < zones.length; i++) {
                        const z = zones[i]
                        if (!z || z.id === sel || z.id === hov)
                            continue
                        ctx.fillStyle = "rgba(220, 230, 245, 0.35)"
                        const x = root.lonToX(z.lon, w)
                        const y = root.latToY(z.lat, h)
                        ctx.beginPath()
                        ctx.arc(x, y, 1.6, 0, 6.283)
                        ctx.fill()
                    }
                }
            }

            Rectangle {
                visible: root.hoverId.length && root.hoverId !== root.pendingId && !!root.findZone(root.hoverId)
                width: 8
                height: 8
                radius: 4
                color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.85)
                x: {
                    const z = root.findZone(root.hoverId)
                    return z ? root.lonToX(z.lon, mapCanvas.width) - 4 : 0
                }
                y: {
                    const z = root.findZone(root.hoverId)
                    return z ? root.latToY(z.lat, mapCanvas.height) - 4 : 0
                }
            }

            Rectangle {
                visible: !!root.pendingZone
                width: 16
                height: 16
                radius: 8
                color: "transparent"
                border.width: 2
                border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
                x: root.pendingZone ? root.lonToX(root.pendingZone.lon, mapCanvas.width) - 8 : 0
                y: root.pendingZone ? root.latToY(root.pendingZone.lat, mapCanvas.height) - 8 : 0
            }
            Rectangle {
                visible: !!root.pendingZone
                width: 8
                height: 8
                radius: 4
                color: root.accentColor
                border.width: 1
                border.color: "#ffffff"
                x: root.pendingZone ? root.lonToX(root.pendingZone.lon, mapCanvas.width) - 4 : 0
                y: root.pendingZone ? root.latToY(root.pendingZone.lat, mapCanvas.height) - 4 : 0
            }

            Rectangle {
                visible: root.hoverId.length > 0 && !!root.findZone(root.hoverId)
                x: Math.min(mapCanvas.width - width - 8, Math.max(8, mapMa.mouseX + 12))
                y: Math.min(mapCanvas.height - height - 8, Math.max(8, mapMa.mouseY + 12))
                width: hoverLbl.implicitWidth + 12
                height: hoverLbl.implicitHeight + 8
                radius: 4
                color: Qt.rgba(0.06, 0.08, 0.12, 0.92)
                border.width: 1
                border.color: root.pillBorder
                z: 4
                Text {
                    id: hoverLbl
                    anchors.centerIn: parent
                    text: {
                        const z = root.findZone(root.hoverId)
                        return z ? (z.city + "  " + z.id) : ""
                    }
                    color: root.textColor
                    font.pixelSize: 10
                    font.family: root.fontFamily
                }
            }

            MouseArea {
                id: mapMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: (mouse) => {
                    const z = root.nearestZone(root.yToLat(mouse.y, height), root.xToLon(mouse.x, width))
                    root.hoverId = z ? z.id : ""
                }
                onExited: root.hoverId = ""
                onClicked: (mouse) => {
                    const z = root.nearestZone(root.yToLat(mouse.y, height), root.xToLon(mouse.x, width))
                    if (z)
                        root.selectZone(z.id, false)
                }
            }
        }

        TextField {
            id: tzSearch
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            placeholderText: "Search city or region…"
            color: root.textColor
            placeholderTextColor: root.subtextColor
            font.pixelSize: 12
            font.family: root.fontFamily
            background: Rectangle {
                radius: root.chipR
                color: parent.activeFocus ? root.fieldBgFocus : root.fieldBg
                border.width: 1
                border.color: tzSearch.activeFocus ? root.accentColor : root.pillBorder
            }
            onPressed: {
                if (typeof root.keyboardGrab === "function")
                    root.keyboardGrab()
            }
            onActiveFocusChanged: {
                if (activeFocus && typeof root.keyboardGrab === "function")
                    root.keyboardGrab()
            }
            onTextChanged: root.searchText = text
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 148
            Layout.minimumHeight: 96
            radius: root.chipR
            color: Qt.rgba(0.08, 0.09, 0.12, 0.55)
            border.width: 1
            border.color: root.pillBorder
            clip: true

            ListView {
                id: tzList
                anchors.fill: parent
                anchors.margins: 4
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.filteredZones()
                spacing: 2
                ScrollBar.vertical: ScrollBar {
                    policy: tzList.contentHeight > tzList.height + 4 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                    width: 8
                    contentItem: Rectangle {
                        implicitWidth: 6
                        radius: 3
                        color: root.accentColor
                        opacity: 0.5
                    }
                }
                delegate: Rectangle {
                    required property var modelData
                    width: tzList.width - 8
                    height: 32
                    radius: 5
                    readonly property bool selected: modelData && modelData.id === root.pendingId
                    readonly property bool current: modelData && modelData.id === root.currentId
                    color: selected
                           ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                           : (rowMa.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
                    border.width: selected ? 1 : 0
                    border.color: selected ? root.accentColor : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                text: modelData ? (modelData.city + (current ? "  · current" : "")) : ""
                                color: selected ? root.accentColor : root.textColor
                                font.pixelSize: 12
                                font.bold: selected
                                font.family: root.fontFamily
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData ? (modelData.id + (modelData.comment ? (" · " + modelData.comment) : "")) : ""
                                color: root.subtextColor
                                font.pixelSize: 10
                                font.family: root.fontFamily
                                elide: Text.ElideRight
                            }
                        }
                    }
                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (modelData)
                                root.selectZone(modelData.id, false)
                        }
                    }
                }
            }

            Text {
                visible: !root.loading && root.filteredZones().length === 0
                anchors.centerIn: parent
                text: root.loading ? "Loading…" : "No matching cities"
                color: root.subtextColor
                font.pixelSize: 11
                font.family: root.fontFamily
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: {
                        const z = root.pendingZone
                        if (!z)
                            return "Select a region"
                        const p = root.pendingPreview || {}
                        const when = p.local ? (p.local + (p.abbr ? (" " + p.abbr) : "")) : ""
                        return z.city + (when ? (" · " + when) : "")
                    }
                    color: root.textColor
                    font.pixelSize: 12
                    font.family: root.fontFamily
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    visible: root.errorMsg.length > 0 || root.statusMsg.length > 0
                    text: root.errorMsg.length ? root.errorMsg : root.statusMsg
                    color: root.errorMsg.length ? root.errorColor : root.okColor
                    font.pixelSize: 10
                    font.family: root.fontFamily
                    elide: Text.ElideRight
                }
            }
            Rectangle {
                Layout.preferredHeight: 30
                Layout.preferredWidth: applyTzLbl.implicitWidth + 16
                radius: root.chipR
                enabled: root.dirty && !root.applying
                opacity: enabled ? 1 : 0.45
                color: applyTzMa.containsMouse && enabled
                       ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.28)
                       : root.fieldBg
                border.width: 1
                border.color: enabled ? root.accentColor : root.pillBorder
                Text {
                    id: applyTzLbl
                    anchors.centerIn: parent
                    text: root.applying ? "Applying…" : "Apply region"
                    color: enabled ? root.accentColor : root.subtextColor
                    font.pixelSize: 12
                    font.family: root.fontFamily
                }
                MouseArea {
                    id: applyTzMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    enabled: parent.enabled
                    onClicked: root.applyPending()
                }
            }
        }
    }
}
