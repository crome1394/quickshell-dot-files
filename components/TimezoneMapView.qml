import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io as Io

// Clickable equirectangular timezone map (GNOME Date & Time style) for the Clock panel.
// Zones from zone1970.tab; land from assets/world-land.json; offset bands from assets/tz-raster.json.
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
    property color oceanColor: "#8aa0b5"
    property color landColor: "#e7e2d6"
    property color highlightColor: "#6fbf3a"
    property color gridColor: Qt.rgba(1, 1, 1, 0.14)
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
    property var tzRaster: []
    property int tzRasterW: 0
    property int tzRasterH: 0
    property string currentId: ""
    property string pendingId: ""
    property string hoverId: ""
    property int hoverBucket: -1
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

    onOceanColorChanged: root.schedulePaint()
    onLandColorChanged: root.schedulePaint()
    onHighlightColorChanged: root.schedulePaint()
    onGridColorChanged: root.schedulePaint()
    onAccentColorChanged: root.schedulePaint()
    onPendingIdChanged: root.schedulePaint()

    function schedulePaint() {
        if (mapCanvas)
            mapCanvas.requestPaint()
        paintRetry.restart()
    }
    Timer {
        id: paintRetry
        interval: 90
        repeat: false
        onTriggered: {
            if (mapCanvas)
                mapCanvas.requestPaint()
        }
    }

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
        root.schedulePaint()
    }

    function offsetBucket(hours) {
        return Math.round((Number(hours) + 14) * 4)
    }

    function zoneBucket(z) {
        if (!z)
            return -1
        if (z.offsetHours !== undefined && z.offsetHours !== null)
            return root.offsetBucket(z.offsetHours)
        return -1
    }

    function sampleRaster(lon, lat) {
        const w = root.tzRasterW
        const h = root.tzRasterH
        const data = root.tzRaster
        if (!w || !h || !data || !data.length)
            return 0
        let x = Math.floor(((Number(lon) + 180) / 360) * w)
        let y = Math.floor(((90 - Number(lat)) / 180) * h)
        if (x < 0)
            x = 0
        if (y < 0)
            y = 0
        if (x >= w)
            x = w - 1
        if (y >= h)
            y = h - 1
        return data[y * w + x] || 0
    }

    function unpackRaster(hex) {
        const s = String(hex || "")
        const n = Math.floor(s.length / 2)
        const out = []
        out.length = n
        for (let i = 0; i < n; i++)
            out[i] = parseInt(s.substr(i * 2, 2), 16) || 0
        return out
    }

    function bandColor(bucket, selected, hovered) {
        if (selected)
            return root.highlightColor
        if (hovered)
            return Qt.rgba(root.highlightColor.r * 0.72 + 0.18,
                           root.highlightColor.g * 0.72 + 0.22,
                           root.highlightColor.b * 0.55 + 0.12, 1)
        const pal = [
            Qt.rgba(0.86, 0.84, 0.72, 1),
            Qt.rgba(0.78, 0.86, 0.70, 1),
            Qt.rgba(0.90, 0.82, 0.68, 1),
            Qt.rgba(0.74, 0.82, 0.66, 1),
            Qt.rgba(0.88, 0.88, 0.76, 1),
            Qt.rgba(0.82, 0.78, 0.64, 1)
        ]
        const i = Math.abs(Number(bucket) || 0) % pal.length
        return pal[i]
    }

    function utcLabel(hours) {
        const h = Number(hours)
        if (isNaN(h))
            return "UTC"
        const sign = h < 0 ? "-" : "+"
        const ah = Math.abs(h)
        const hh = Math.floor(ah)
        const mm = Math.round((ah - hh) * 60)
        if (mm)
            return "UTC" + sign + hh + ":" + (mm < 10 ? "0" : "") + mm
        return "UTC" + sign + hh
    }

    function refreshAll() {
        root.loadStatus()
        root.loadList()
        root.loadLand()
        root.loadRaster()
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

    function loadRaster() {
        if (rasterProc.running)
            return
        rasterProc.exec([root.scriptPath(), "raster-json"])
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
            root.schedulePaint()
        } else {
            root.hoverId = ""
            root.hoverBucket = -1
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
                    root.schedulePaint()
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
                    root.schedulePaint()
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
                    root.schedulePaint()
                } catch (e) {}
            }
        }
    }

    Io.Process {
        id: rasterProc
        running: false
        stdout: Io.StdioCollector {
            id: rasterOut
            onStreamFinished: {
                const t = (rasterOut.text || "").trim()
                if (!t.startsWith("{"))
                    return
                try {
                    const j = JSON.parse(t)
                    root.tzRasterW = Number(j.w) || 0
                    root.tzRasterH = Number(j.h) || 0
                    root.tzRaster = root.unpackRaster(j.data)
                    root.schedulePaint()
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
                        root.schedulePaint()
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

        Rectangle {
            id: mapFrame
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 240
            Layout.preferredHeight: 360
            radius: root.chipR
            color: root.oceanColor
            border.width: 1
            border.color: root.pillBorder
            clip: true

            Canvas {
                id: mapCanvas
                anchors.fill: parent
                antialiasing: true
                renderTarget: Canvas.Image
                renderStrategy: Canvas.Immediate
                onWidthChanged: root.schedulePaint()
                onHeightChanged: root.schedulePaint()
                visible: true
                onVisibleChanged: if (visible) root.schedulePaint()
                onPaint: {
                    const ctx = getContext("2d")
                    const w = Math.floor(width)
                    const h = Math.floor(height)
                    if (w < 8 || h < 8)
                        return
                    ctx.reset()
                    const ocean = root.oceanColor
                    const oR = Math.round(ocean.r * 255)
                    const oG = Math.round(ocean.g * 255)
                    const oB = Math.round(ocean.b * 255)
                    ctx.fillStyle = root.cssColor(ocean)
                    ctx.fillRect(0, 0, w, h)

                    ctx.strokeStyle = "rgba(255,255,255,0.16)"
                    ctx.lineWidth = 1
                    for (let lon = -180; lon <= 180; lon += 15) {
                        const x = root.lonToX(lon, w)
                        ctx.beginPath()
                        ctx.moveTo(x, 0)
                        ctx.lineTo(x, h)
                        ctx.stroke()
                    }

                    const rings = root.landRings || []
                    ctx.fillStyle = root.cssColor(root.landColor)
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

                    const selB = root.zoneBucket(root.pendingZone)
                    const hovB = root.hoverBucket
                    const activeB = (hovB >= 0) ? hovB : selB
                    const rw = root.tzRasterW
                    const rh = root.tzRasterH
                    const raster = root.tzRaster
                    if (rw > 0 && rh > 0 && raster && raster.length >= rw * rh) {
                        try {
                            const img = ctx.getImageData(0, 0, w, h)
                            const px = img.data
                            const n = px.length
                            const hR = Math.round(root.highlightColor.r * 255)
                            const hG = Math.round(root.highlightColor.g * 255)
                            const hB = Math.round(root.highlightColor.b * 255)
                            for (let i = 0; i < n; i += 4) {
                                const p = i / 4
                                const x = p % w
                                const y = (p - x) / w
                                const b = root.sampleRaster(root.xToLon(x + 0.5, w), root.yToLat(y + 0.5, h))
                                const isOcean = (px[i] === oR && px[i + 1] === oG && px[i + 2] === oB)
                                const lit = activeB >= 0 && b === activeB
                                if (isOcean) {
                                    if (!lit)
                                        continue
                                    px[i] = hR
                                    px[i + 1] = hG
                                    px[i + 2] = hB
                                    continue
                                }
                                const col = lit ? root.highlightColor : root.bandColor(b, false, false)
                                px[i] = Math.round(col.r * 255)
                                px[i + 1] = Math.round(col.g * 255)
                                px[i + 2] = Math.round(col.b * 255)
                            }
                            ctx.putImageData(img, 0, 0)
                        } catch (e) {}
                    }
                }
            }

            Rectangle {
                id: hoverBubble
                visible: root.hoverId.length > 0 && root.hoverId !== root.pendingId && !!root.findZone(root.hoverId)
                x: Math.min(mapCanvas.width - width - 8, Math.max(8, mapMa.mouseX + 14))
                y: Math.min(mapCanvas.height - height - 8, Math.max(8, mapMa.mouseY + 14))
                width: hoverCol.implicitWidth + 16
                height: hoverCol.implicitHeight + 12
                radius: 6
                color: Qt.rgba(0.10, 0.11, 0.13, 0.92)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.12)
                z: 5
                Column {
                    id: hoverCol
                    anchors.centerIn: parent
                    spacing: 1
                    Text {
                        text: {
                            const z = root.findZone(root.hoverId)
                            const p = (root.hoverId === root.pendingId) ? (root.pendingPreview || {}) : {}
                            const abbr = p.abbr || ""
                            const hours = (p.offsetHours !== undefined) ? p.offsetHours : (z ? z.offsetHours : 0)
                            const utc = root.utcLabel(hours)
                            return abbr ? (abbr + "  (" + utc + ")") : utc
                        }
                        color: "#f4f6fa"
                        font.pixelSize: 11
                        font.bold: true
                        font.family: root.fontFamily
                    }
                    Text {
                        text: {
                            const z = root.findZone(root.hoverId)
                            if (!z)
                                return ""
                            return z.comment ? (z.city + ", " + z.comment) : (z.city + ", " + z.region)
                        }
                        color: "#c8d0dc"
                        font.pixelSize: 10
                        font.family: root.fontFamily
                    }
                    Text {
                        visible: {
                            const p = (root.hoverId === root.pendingId) ? (root.pendingPreview || {}) : {}
                            return !!(p.local && String(p.local).length)
                        }
                        text: (root.pendingPreview && root.pendingPreview.local) ? root.pendingPreview.local : ""
                        color: "#f4f6fa"
                        font.pixelSize: 12
                        font.bold: true
                        font.family: root.fontMono
                    }
                }
            }

            Rectangle {
                id: selBubble
                visible: !!root.pendingZone && (!root.hoverId.length || root.hoverId === root.pendingId)
                z: 5
                width: selCol.implicitWidth + 16
                height: selCol.implicitHeight + 12
                radius: 6
                color: Qt.rgba(0.10, 0.11, 0.13, 0.92)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.12)
                x: {
                    if (!root.pendingZone)
                        return 8
                    const px = root.lonToX(root.pendingZone.lon, mapCanvas.width) + 14
                    return Math.min(mapCanvas.width - width - 8, Math.max(8, px))
                }
                y: {
                    if (!root.pendingZone)
                        return 8
                    const py = root.latToY(root.pendingZone.lat, mapCanvas.height) - height / 2
                    return Math.min(mapCanvas.height - height - 8, Math.max(8, py))
                }
                Column {
                    id: selCol
                    anchors.centerIn: parent
                    spacing: 1
                    Text {
                        text: {
                            const z = root.pendingZone
                            const p = root.pendingPreview || {}
                            const abbr = p.abbr || ""
                            const hours = (p.offsetHours !== undefined) ? p.offsetHours : (z ? z.offsetHours : 0)
                            const utc = root.utcLabel(hours)
                            return abbr ? (abbr + "  (" + utc + ")") : utc
                        }
                        color: "#f4f6fa"
                        font.pixelSize: 11
                        font.bold: true
                        font.family: root.fontFamily
                    }
                    Text {
                        text: {
                            const z = root.pendingZone
                            if (!z)
                                return ""
                            return z.comment ? (z.city + ", " + z.comment) : (z.city + ", " + z.region)
                        }
                        color: "#c8d0dc"
                        font.pixelSize: 10
                        font.family: root.fontFamily
                    }
                    Text {
                        visible: !!(root.pendingPreview && root.pendingPreview.local)
                        text: (root.pendingPreview && root.pendingPreview.local) ? root.pendingPreview.local : ""
                        color: "#f4f6fa"
                        font.pixelSize: 12
                        font.bold: true
                        font.family: root.fontMono
                    }
                }
            }

            // GNOME-style pin for the selected city
            Item {
                visible: !!root.pendingZone
                width: 18
                height: 22
                z: 6
                x: root.pendingZone ? root.lonToX(root.pendingZone.lon, mapCanvas.width) - 9 : 0
                y: root.pendingZone ? root.latToY(root.pendingZone.lat, mapCanvas.height) - 20 : 0
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 14
                    height: 14
                    radius: 7
                    color: "#e24b4b"
                    border.width: 2
                    border.color: "#ffffff"
                    y: 0
                }
                Canvas {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 10
                    width: 10
                    height: 10
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        ctx.fillStyle = "#e24b4b"
                        ctx.beginPath()
                        ctx.moveTo(1, 0)
                        ctx.lineTo(9, 0)
                        ctx.lineTo(5, 10)
                        ctx.closePath()
                        ctx.fill()
                    }
                }
            }

            TextField {
                id: tzSearch
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: 10
                width: Math.min(parent.width - 24, 460)
                height: 32
                z: 7
                placeholderText: "Search for a city"
                color: "#1a1d22"
                placeholderTextColor: "#667084"
                font.pixelSize: 13
                font.family: root.fontFamily
                background: Rectangle {
                    radius: 6
                    color: "#f7f8fa"
                    border.width: 1
                    border.color: tzSearch.activeFocus ? root.accentColor : "#c5ccd6"
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

            MouseArea {
                id: mapMa
                z: 1
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: (mouse) => {
                    const lat = root.yToLat(mouse.y, height)
                    const lon = root.xToLon(mouse.x, width)
                    const z = root.nearestZone(lat, lon)
                    root.hoverId = z ? z.id : ""
                    const rb = root.sampleRaster(lon, lat)
                    const zb = z ? root.zoneBucket(z) : -1
                    const b = (rb > 0) ? rb : zb
                    if (root.hoverBucket !== b) {
                        root.hoverBucket = b
                        mapCanvas.requestPaint()
                    }
                }
                onExited: {
                    root.hoverId = ""
                    if (root.hoverBucket !== -1) {
                        root.hoverBucket = -1
                        mapCanvas.requestPaint()
                    }
                }
                onClicked: (mouse) => {
                    const z = root.nearestZone(root.yToLat(mouse.y, height), root.xToLon(mouse.x, width))
                    if (z)
                        root.selectZone(z.id, false)
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 100
            Layout.maximumHeight: 120
            Layout.minimumHeight: 72
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
