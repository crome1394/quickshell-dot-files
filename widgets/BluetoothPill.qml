import QtQuick
import "../components"
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Io as Io

// =============================================================================
// BluetoothPill.qml — Bluetooth adapter + device manager pill
// =============================================================================
//
// Purpose:
//   Glassmorphic Bluetooth pill for the status bar. Manages adapter power,
//   scanning/pairing, connect/disconnect, trust/block/remove, device info,
//   battery, and PipeWire/BlueZ audio card profiles for connected headsets.
//
// Theme Properties Consumed:
//   - bar.pillRadius, bar.pillBg, bar.pillBorder, bar.accent, bar.glassHover
//   - bar.iconHoverBg, bar.workspaceRadius, bar.controlBorderWidth
//   - bar.popupRadius, bar.glassPopupBg, bar.glassPopupBorder,
//     bar.glassPopupHighlight, bar.popupHeaderHighlightHeight,
//     bar.popupSpacing, bar.popupTitleSize, bar.popupSectionSize,
//     bar.popupHintSize, bar.popupButtonHoverBg, bar.dividerStrong
//   - bar.buttonRadius, bar.smallButtonRadius, bar.surface
//   - bar.text, bar.subtext, bar.overlay, bar.muted, bar.bg
//   - bar.fontFamily, bar.fontTiny, bar.fontSmall, bar.iconSizeTray
//   - bar.popupBluetoothWidth, bar.popupBluetoothHeight
//   - bar.bluetoothScanSeconds
//   - bar.iconBluetooth, bar.iconBluetoothOff, bar.iconBluetoothConnected,
//     bar.iconBluetoothScanning, bar.iconAudioBattery
//   - bar.tooltipDelay, bar.popupAnchorY()
//
// Dependencies:
//   - required property var bar
//   - required property Item barBg (for popup positioning)
//   - property bool embedded (optional) — when true, omit pill chrome so a
//     parent shell (shell.qml connectivityPill) can group Network + Bluetooth
//   - Quickshell.Bluetooth (adapter + devices)
//   - scripts/audio-control.sh (list-card-profiles / set-card-profile)
//
// Notes:
//   - Adapter power only (BluetoothAdapter.enabled), not systemctl bluetooth.service.
//   - Pairing may open a system agent dialog (Blueman); keep Blueman installed.
//   - Selection is address-keyed so destroyed BlueZ objects do not crash qs.
//   - Rename TextField needs HyprlandFocusGrab so the popup receives keyboard focus
//     (layer-shell panels are not focusable by default).
//   - Perf: one-pass device snapshot (bar + popup lists); popup-only address arrays;
//     slow poll while open; Blueman checked on open / after toggle (not every frame).
// =============================================================================

Rectangle {
    id: root

    required property var bar
    required property Item barBg

    // When true, this widget is a section inside a shared connectivity pill
    // (no own background/border; hover uses iconHoverBg like SysStats sections).
    property bool embedded: false
    // Horizontal scale only (BarControlBar Sizes). Height stays bar.pillHeight.
    property real pillScale: 1.0
    readonly property real _s: (pillScale > 0 ? pillScale : 1)
    readonly property real _h: bar.pillHeight
    readonly property int _padW: embedded ? 12 : 14
    readonly property int _naturalW: btContent.implicitWidth + _padW

    readonly property string audioControlScript: "/home/crome/.config/quickshell/scripts/audio-control.sh"
    readonly property string bluemanControlScript: "/home/crome/.config/quickshell/scripts/blueman-applet-control.sh"

    // Address of expanded / detail device (stable key; never store live object long-term)
    property string expandedAddress: ""
    property string detailAddress: ""   // non-empty → info panel view
    property string confirmForgetAddress: ""
    property string renameAddress: ""   // address currently being renamed
    property string renameDraft: ""
    property string profileCard: ""
    property string profileActive: ""
    property var profileList: []
    property bool bluemanRunning: false
    // false when ~/.config/autostart/blueman.desktop masks login start
    property bool bluemanAutostartEnabled: true
    property string appletStatusMsg: ""

    // Standalone: full pill size. Embedded: content chip sized for shared shell.
    implicitWidth: Math.round(_naturalW * _s)
    implicitHeight: embedded ? Math.max(18, _h - 8) : _h
    width: implicitWidth
    height: implicitHeight
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight
    Layout.alignment: Qt.AlignVCenter

    HoverHandler {
        id: btHoverVis
    }
    readonly property bool btHovered: btHoverVis.hovered || btMouse.containsMouse

    // Standalone: stable outer chrome. Embedded: this rect is the content chip.
    radius: embedded ? bar.workspaceRadius : bar.pillRadius
    color: {
        if (embedded)
            return root.btHovered ? bar.iconHoverBg : "transparent"
        return bar.pillBg
    }
    border.width: embedded
        ? (root.btHovered ? bar.controlBorderWidth : 0)
        : bar.controlBorderWidth
    border.color: embedded
        ? (root.btHovered ? bar.accent : "transparent")
        : bar.pillBorder

    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }
    Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }

    // =========================================================================
    // Bluetooth state helpers
    // =========================================================================
    QtObject {
        id: bt

        readonly property var adapter: {
            try { return Bluetooth.defaultAdapter }
            catch (e) { return null }
        }

        readonly property bool hasAdapter: !!adapter

        readonly property bool powered: {
            try {
                if (!adapter) return false
                // Prefer enabled; also treat Enabling as "on-ish" for UI
                return !!adapter.enabled
            } catch (e) { return false }
        }

        readonly property string adapterStateText: {
            try {
                if (!adapter) return "No adapter"
                if (typeof BluetoothAdapterState !== "undefined" && BluetoothAdapterState.toString)
                    return BluetoothAdapterState.toString(adapter.state)
                // Fallback labels
                var s = adapter.state
                if (s === 0) return "Disabled"
                if (s === 1) return "Enabled"
                if (s === 2) return "Enabling"
                if (s === 3) return "Disabling"
                if (s === 4) return "Blocked"
                return String(s)
            } catch (e) { return "?" }
        }

        readonly property bool discovering: {
            try { return adapter ? !!adapter.discovering : false }
            catch (e) { return false }
        }

        readonly property bool discoverable: {
            try { return adapter ? !!adapter.discoverable : false }
            catch (e) { return false }
        }

        readonly property string adapterName: {
            try { return adapter ? (adapter.name || adapter.adapterId || "Bluetooth") : "No adapter" }
            catch (e) { return "No adapter" }
        }

        // Bumped while popup is open so connect/pair/battery re-bind if BlueZ
        // notifies are sparse. Keep interval modest (see deviceRefreshTimer).
        property int deviceEpoch: 0

        // True while the main popup is open — gates heavy list work.
        readonly property bool popupOpen: btPopup.visible

        // Single pass over Bluetooth.devices → bar metrics + (when open) address lists.
        // Avoids N separate O(devices) walks for count / primary / connected / paired / available.
        readonly property var snapshot: {
            var __ = deviceEpoch
            var wantLists = popupOpen
            var connected = []
            var paired = []
            var available = []
            var connectedCount = 0
            var primaryName = ""
            var primaryBattery = -1
            var primaryHasBat = false

            try {
                var vals = (Bluetooth.devices && Bluetooth.devices.values)
                    ? Bluetooth.devices.values : []
                for (var i = 0; i < vals.length; i++) {
                    var d = vals[i]
                    if (!d) continue
                    try {
                        // Touch properties so QML re-evaluates on BlueZ notifies.
                        var isConn = !!d.connected
                        var isPaired = !!d.paired
                        var isBonded = !!d.bonded
                        var isPairing = !!d.pairing
                        var isTrusted = !!d.trusted
                        var isBlocked = !!d.blocked
                        var nm = d.name || d.deviceName || ""
                        var addr = String(d.address || "")
                        if (!addr.length) continue

                        if (isConn) {
                            connectedCount++
                            if (wantLists) connected.push(addr)

                            var bat = -1
                            if (d.batteryAvailable) {
                                var b = Number(d.battery)
                                if (!isNaN(b)) {
                                    bat = (b >= 0 && b <= 1.01) ? Math.round(b * 100)
                                          : Math.max(0, Math.min(100, Math.round(b)))
                                }
                            }
                            // Prefer a device that reports battery as "primary" for the pill.
                            if (!primaryName.length || (bat >= 0 && !primaryHasBat)) {
                                primaryName = nm.length ? nm : addr
                                primaryBattery = bat
                                primaryHasBat = bat >= 0
                            }
                        } else if (wantLists) {
                            if (isPaired || isBonded)
                                paired.push(addr)
                            else
                                available.push(addr)
                        } else {
                            // Bar path: still touch pairing/name lightly when not listing.
                            var _touch = isPairing || isTrusted || isBlocked || nm
                        }
                    } catch (e1) {}
                }
            } catch (e) {}

            return {
                connectedCount: connectedCount,
                primaryName: primaryName,
                primaryBattery: primaryBattery,
                connectedAddresses: connected,
                pairedAddresses: paired,
                availableAddresses: available
            }
        }

        readonly property int connectedCount: snapshot.connectedCount
        readonly property string primaryName: snapshot.primaryName
        readonly property int primaryBattery: snapshot.primaryBattery
        readonly property var connectedAddresses: snapshot.connectedAddresses
        readonly property var pairedAddresses: snapshot.pairedAddresses
        readonly property var availableAddresses: snapshot.availableAddresses

        function deviceLabel(d) {
            if (!d) return "Unknown"
            try {
                var n = d.name || d.deviceName || ""
                if (n && n.length) return n
                return d.address || "Unknown"
            } catch (e) { return "Unknown" }
        }

        function deviceAddress(d) {
            try { return d ? String(d.address || "") : "" }
            catch (e) { return "" }
        }

        function normalizeMac(addr) {
            return String(addr || "").replace(/[^0-9A-Fa-f]/g, "").toUpperCase()
        }

        // Direct walk — used by actions/IPC; does not allocate section lists.
        function findByAddress(addr) {
            if (!addr) return null
            var want = normalizeMac(addr)
            if (!want.length) return null
            try {
                var vals = (Bluetooth.devices && Bluetooth.devices.values)
                    ? Bluetooth.devices.values : []
                for (var i = 0; i < vals.length; i++) {
                    try {
                        var d = vals[i]
                        if (!d) continue
                        if (normalizeMac(d.address) === want) return d
                    } catch (e1) {}
                }
            } catch (e) {}
            return null
        }

        function batteryPercent(d) {
            if (!d) return -1
            try {
                if (!d.batteryAvailable) return -1
                var b = Number(d.battery)
                if (isNaN(b)) return -1
                if (b >= 0 && b <= 1.01) return Math.round(b * 100)
                return Math.max(0, Math.min(100, Math.round(b)))
            } catch (e) { return -1 }
        }

        function batteryColor(pct) {
            if (pct < 0) return bar ? bar.subtext : "#a8b4c8"
            if (pct <= 15) return "#EF4444"
            if (pct <= 30) return "#F59E0B"
            return "#10B981"
        }

        function stateLabel(d) {
            if (!d) return ""
            try {
                if (d.pairing) return "Pairing…"
                if (d.connected) return "Connected"
                // Connecting / Disconnecting via state enum if available
                var s = d.state
                if (s === 2) return "Disconnecting…"
                if (s === 3) return "Connecting…"
                if (d.blocked) return "Blocked"
                if (d.paired) return "Paired"
                return "Available"
            } catch (e) { return "" }
        }

        // PipeWire/Pulse bluez card: A0:0C:… → bluez_card.A0_0C_…
        function cardName(addr) {
            if (!addr) return ""
            return "bluez_card." + String(addr).replace(/:/g, "_")
        }

        function setPowered(on) {
            try {
                if (!adapter) return
                adapter.enabled = !!on
            } catch (e) {}
        }

        function togglePower() {
            setPowered(!powered)
        }

        function setDiscovering(on) {
            try {
                if (!adapter) return
                if (on) {
                    try { adapter.pairable = true } catch (e1) {}
                    adapter.discovering = true
                    scanStopTimer.restart()
                } else {
                    adapter.discovering = false
                    scanStopTimer.stop()
                }
            } catch (e) {}
        }

        function toggleScan() {
            setDiscovering(!discovering)
        }

        function setDiscoverable(on) {
            try {
                if (!adapter) return
                adapter.discoverable = !!on
            } catch (e) {}
        }

        function connectDevice(addr) {
            var d = findByAddress(addr)
            if (!d) return
            try {
                if (d.connect) d.connect()
                else d.connected = true
            } catch (e) {}
        }

        function disconnectDevice(addr) {
            var d = findByAddress(addr)
            if (!d) return
            try {
                if (d.disconnect) d.disconnect()
                else d.connected = false
            } catch (e) {}
        }

        function pairDevice(addr) {
            var d = findByAddress(addr)
            if (!d) return
            try {
                if (adapter) {
                    try { adapter.pairable = true } catch (e1) {}
                }
                d.pair()
            } catch (e) {}
        }

        function cancelPairDevice(addr) {
            var d = findByAddress(addr)
            if (!d) return
            try { d.cancelPair() } catch (e) {}
        }

        function forgetDevice(addr) {
            var d = findByAddress(addr)
            if (!d) return
            try {
                d.forget()
            } catch (e) {}
            if (root.expandedAddress === addr) root.expandedAddress = ""
            if (root.detailAddress === addr) root.detailAddress = ""
            if (root.confirmForgetAddress === addr) root.confirmForgetAddress = ""
            if (root.renameAddress === addr)
                root.endRename()
            root.clearProfiles()
            deviceEpoch++
        }

        function setTrusted(addr, on) {
            var d = findByAddress(addr)
            if (!d) return
            try { d.trusted = !!on } catch (e) {}
        }

        function setBlocked(addr, on) {
            var d = findByAddress(addr)
            if (!d) return
            try { d.blocked = !!on } catch (e) {}
        }

        // Alias / display name (BlueZ Alias). Writable via Quickshell BluetoothDevice.name.
        function renameDevice(addr, newName) {
            var d = findByAddress(addr)
            if (!d) return false
            var n = String(newName || "").trim()
            if (!n.length) return false
            try {
                d.name = n
                return true
            } catch (e) {
                return false
            }
        }

        function startBlueman() {
            // Session-only start (does not re-enable login autostart)
            root.runBluemanControl(["start"])
        }

        function stopBlueman() {
            // Session-only stop (does not disable login autostart)
            root.runBluemanControl(["stop"])
        }

        function toggleBlueman() {
            if (root.bluemanRunning)
                stopBlueman()
            else
                startBlueman()
        }

        // Sticky: survives reboot via XDG autostart override
        function enableBluemanAutostart() {
            root.runBluemanControl(["enable"])
        }

        function disableBluemanAutostart() {
            root.runBluemanControl(["disable"])
        }

        function setBluemanAutostart(enabled) {
            root.runBluemanControl(["set-autostart", enabled ? "true" : "false"])
        }

        readonly property string pillGlyph: {
            if (!hasAdapter || !powered)
                return (bar && bar.iconBluetoothOff) ? bar.iconBluetoothOff : "󰂲"
            if (discovering)
                return (bar && bar.iconBluetoothScanning) ? bar.iconBluetoothScanning : "󰂰"
            if (connectedCount > 0)
                return (bar && bar.iconBluetoothConnected) ? bar.iconBluetoothConnected : "󰂱"
            return (bar && bar.iconBluetooth) ? bar.iconBluetooth : "󰂯"
        }

        readonly property color pillGlyphColor: {
            if (!hasAdapter || !powered) return bar ? bar.muted : "#6e7a90"
            if (discovering) return bar ? bar.accent : "#00F0E0"
            if (connectedCount > 0) return bar ? (bar.iconColor !== undefined ? bar.iconColor : bar.subtext) : "#ffffff"
            return bar ? (bar.iconColor !== undefined ? bar.iconColor : bar.subtext) : "#a8b4c8"
        }
    }

    Timer {
        id: scanStopTimer
        interval: Math.max(10, (bar && bar.bluetoothScanSeconds) ? bar.bluetoothScanSeconds : 45) * 1000
        repeat: false
        onTriggered: bt.setDiscovering(false)
    }

    // While the popup is open, periodically refresh derived lists (connect/pair/battery).
    // Faster during active discovery; quieter otherwise. Idle bar relies on BlueZ notifies.
    Timer {
        id: deviceRefreshTimer
        interval: bt.discovering ? 1200 : 3000
        repeat: true
        running: btPopup.visible
        onTriggered: bt.deviceEpoch++
    }

    // Blueman applet — status + control via blueman-applet-control.sh
    function runBluemanControl(args) {
        if (bluemanControlProcess.running)
            bluemanControlProcess.running = false
        var cmd = [root.bluemanControlScript]
        for (var i = 0; i < args.length; i++)
            cmd.push(String(args[i]))
        bluemanControlProcess.command = cmd
        bluemanControlProcess.running = true
    }

    function refreshBluemanStatus() {
        if (bluemanCheckProcess.running)
            bluemanCheckProcess.running = false
        bluemanCheckProcess.command = [root.bluemanControlScript, "status"]
        bluemanCheckProcess.running = true
    }

    function applyBluemanStatus(data) {
        if (!data) return
        if (data.running !== undefined)
            root.bluemanRunning = !!data.running
        if (data.autostart_enabled !== undefined)
            root.bluemanAutostartEnabled = !!data.autostart_enabled
        if (data.message)
            root.flashAppletStatus(String(data.message))
        else if (data.error)
            root.flashAppletStatus(String(data.error))
    }

    function flashAppletStatus(msg) {
        root.appletStatusMsg = msg || ""
        appletStatusClear.restart()
    }

    Io.Process {
        id: bluemanCheckProcess
        running: false
        stdout: Io.StdioCollector { id: bluemanCheckStdout }
        onExited: (code) => {
            var data = root._parseJson(bluemanCheckStdout.text)
            if (data)
                root.applyBluemanStatus(data)
            else
                root.bluemanRunning = false
        }
    }

    Io.Process {
        id: bluemanControlProcess
        running: false
        stdout: Io.StdioCollector { id: bluemanControlStdout }
        onExited: (code) => {
            var data = root._parseJson(bluemanControlStdout.text)
            if (data)
                root.applyBluemanStatus(data)
            // Always re-query after a short delay (process may still be settling)
            bluemanRefreshTimer.restart()
        }
    }

    // Slow optional recheck while popup is open (external start/stop of Blueman).
    Timer {
        id: bluemanPollTimer
        interval: 8000
        repeat: true
        running: btPopup.visible
        onTriggered: root.refreshBluemanStatus()
    }

    // One-shot recheck after start/stop/enable/disable
    Timer {
        id: bluemanRefreshTimer
        interval: 600
        repeat: false
        onTriggered: root.refreshBluemanStatus()
    }

    Timer {
        id: appletStatusClear
        interval: 4000
        onTriggered: root.appletStatusMsg = ""
    }

    // On bar load: refresh sticky/running state (does not start the applet).
    Component.onCompleted: {
        root.refreshBluemanStatus()
    }

    // =========================================================================
    // Audio profile fetch (bluez_card.*)
    // =========================================================================
    function clearProfiles() {
        root.profileCard = ""
        root.profileActive = ""
        root.profileList = []
    }

    function _parseJson(text) {
        var t = (text || "").trim()
        if (!t.length) return null
        try { return JSON.parse(t) } catch (e1) {}
        var lines = t.split("\n")
        var last = ""
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (line.length) last = line
        }
        if (last.length) {
            try { return JSON.parse(last) } catch (e2) {}
        }
        var start = t.lastIndexOf("{")
        if (start >= 0) {
            try { return JSON.parse(t.substring(start)) } catch (e3) {}
        }
        return null
    }

    function refreshProfilesForAddress(addr) {
        if (!addr) {
            root.clearProfiles()
            return
        }
        var d = bt.findByAddress(addr)
        if (!d) {
            root.clearProfiles()
            return
        }
        try {
            if (!d.connected) {
                root.clearProfiles()
                return
            }
        } catch (e) {
            root.clearProfiles()
            return
        }
        var card = bt.cardName(addr)
        if (!card.length) {
            root.clearProfiles()
            return
        }
        if (profileListProcess.running)
            profileListProcess.running = false
        profileListProcess.command = [root.audioControlScript, "list-card-profiles", card]
        profileListProcess.running = true
    }

    // Internal: card is a PipeWire name like bluez_card.A0_0C_…
    function applyCardProfile(card, profileName) {
        if (!card || !profileName) return
        if (profileSetProcess.running)
            profileSetProcess.running = false
        profileSetProcess.command = [
            root.audioControlScript, "set-card-profile", card, profileName
        ]
        profileSetProcess.running = true
    }

    function profileLabel() {
        if (!root.profileActive || !root.profileActive.length)
            return "No profile"
        var list = root.profileList || []
        for (var i = 0; i < list.length; i++) {
            if (list[i].name === root.profileActive)
                return list[i].description || root.profileActive
        }
        return root.profileActive
    }

    // Cached for Repeater model (function-as-model re-evaluates poorly / allocates often).
    readonly property var usableProfileList: {
        var list = root.profileList || []
        var active = root.profileActive || ""
        var out = []
        for (var i = 0; i < list.length; i++) {
            var p = list[i]
            if (!p || !p.name) continue
            if (p.name === "off" && p.name !== active) continue
            out.push(p)
        }
        return out
    }

    Io.Process {
        id: profileListProcess
        running: false
        stdout: Io.StdioCollector { id: profileListStdout }
        onExited: (code) => {
            if (code !== 0) {
                root.clearProfiles()
                return
            }
            var data = root._parseJson(profileListStdout.text)
            if (!data) {
                root.clearProfiles()
                return
            }
            root.profileCard = data.card || ""
            root.profileActive = data.active || ""
            root.profileList = data.profiles || []
        }
    }

    Io.Process {
        id: profileSetProcess
        running: false
        onExited: (code) => {
            if (code === 0 && root.expandedAddress.length)
                root.refreshProfilesForAddress(root.expandedAddress)
        }
    }

    // =========================================================================
    // Pill content (chip highlights; outer pill border stays stable)
    // =========================================================================
    Rectangle {
        id: btChip
        anchors.centerIn: parent
        width: Math.max(18, btContent.implicitWidth + (embedded ? 4 : 10))
        height: embedded ? parent.height : Math.max(18, parent.height - 8)
        radius: bar.workspaceRadius
        color: {
            if (embedded)
                return "transparent"
            return root.btHovered ? bar.iconHoverBg : "transparent"
        }
        border.width: (!embedded && root.btHovered) ? bar.controlBorderWidth : 0
        border.color: (!embedded && root.btHovered) ? bar.accent : "transparent"

        Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }
        Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }

        Item {
            id: btContent
            anchors.centerIn: parent
            implicitWidth: pillRow.implicitWidth
            implicitHeight: pillRow.implicitHeight

            Row {
                id: pillRow
                spacing: Math.max(3, Math.round(6 * root._s))
                anchors.centerIn: parent

                Item {
                    width: Math.max(12, Math.round(bar.iconSizeTray * root._s))
                    height: Math.max(12, Math.round(bar.iconSizeTray * root._s))
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        anchors.centerIn: parent
                        text: bt.pillGlyph
                        font.pixelSize: Math.max(12, Math.round(bar.iconSizeTray * root._s))
                        font.family: bar.fontFamily
                        color: bt.pillGlyphColor
                    }
                }

                // Compact status: battery of primary, or connected count
                Text {
                    visible: bt.powered && (bt.primaryBattery >= 0 || bt.connectedCount > 0)
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        if (bt.primaryBattery >= 0)
                            return bt.primaryBattery + "%"
                        if (bt.connectedCount > 0)
                            return String(bt.connectedCount)
                        return ""
                    }
                    color: bt.primaryBattery >= 0
                           ? bt.batteryColor(bt.primaryBattery)
                           : (bar
                              ? ((bar.barText !== undefined) ? bar.barText : bar.text)
                              : "#e6edf7")
                    // Bar widget text size/family
                    font.pixelSize: {
                        var base = (bar && bar.fontBarFace !== undefined) ? bar.fontBarFace : 13
                        return Math.max(9, Math.round(base * root._s))
                    }
                    font.bold: true
                    font.family: (bar && bar.fontBarResolved !== undefined && String(bar.fontBarResolved).length)
                                 ? bar.fontBarResolved : bar.fontFamily
                }
            }
        }
    }

    MouseArea {
        id: btMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        BarToolTip {
            bar: root.bar
            widgetId: "bluetooth"
            visible: btMouse.containsMouse && !btPopup.visible
            anchorItem: btMouse
            text: {
                if (!bt.hasAdapter) return "No Bluetooth adapter"
                if (!bt.powered) return "Bluetooth off · left-click menu · right-click power"
                if (bt.primaryName.length)
                    return bt.primaryName
                        + (bt.primaryBattery >= 0 ? (" · " + bt.primaryBattery + "%") : "")
                        + " · left-click menu · right-click power"
                return "Bluetooth · left-click menu · right-click power"
            }
        }

        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                bt.togglePower()
                return
            }
            if (btPopup.visible) {
                closePopup()
            } else {
                showPopup()
            }
        }
    }

    // Keyboard focus for rename TextField (and any future inputs). Popup/layer
    // surfaces do not receive keys under Hyprland unless a focus grab is active.
    HyprlandFocusGrab {
        id: btFocusGrab
        // Whitelist popup + bar so clicking the pill still works while grabbing.
        windows: [btPopup, bar]
        onCleared: {
            // Outside click released the grab; leave the popup open so the user
            // can click the field again (beginRename re-arms the grab).
        }
    }

    // =========================================================================
    // Main popup
    // =========================================================================
    PopupWindow {
        id: btPopup
        anchor.window: bar
        implicitWidth: bar.popupBluetoothWidth || 380
        implicitHeight: bar.popupBluetoothHeight || 480
        visible: false
        color: "transparent"
        // Request compositor dismiss-on-outside only while we are not mid-rename
        // (rename uses HyprlandFocusGrab for keyboard; grabFocus would also close).
        // Keep false so left-clicking the pill remains the primary close path.
        grabFocus: false

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
                spacing: 10

                // ---- Header ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: root.detailAddress.length ? "Device info" : "Bluetooth"
                        color: bar.text
                        font.pixelSize: bar.popupTitleSize
                        font.bold: true
                        font.family: bar.fontFamily
                    }

                    Item { Layout.fillWidth: true }

                    // Back from detail
                    Rectangle {
                        visible: root.detailAddress.length > 0
                        width: backLbl.implicitWidth + 14
                        height: 26
                        radius: bar.buttonRadius
                        color: backMa.containsMouse ? bar.popupButtonHoverBg : bar.surface
                        border.width: bar.controlBorderWidth
                        border.color: bar.dividerStrong
                        Text {
                            id: backLbl
                            anchors.centerIn: parent
                            text: "← Back"
                            color: bar.text
                            font.pixelSize: 11
                            font.bold: true
                            font.family: bar.fontFamily
                        }
                        MouseArea {
                            id: backMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.detailAddress = ""
                        }
                    }

                    Rectangle {
                        width: 26
                        height: 26
                        radius: bar.buttonRadius
                        color: btCloseMa.containsMouse
                               ? Qt.rgba(1, 0.24, 0.54, 0.22)
                               : bar.surface
                        border.width: 1
                        border.color: btCloseMa.containsMouse ? "#FF3D8A" : bar.dividerStrong
                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: btCloseMa.containsMouse ? "#FF3D8A" : bar.subtext
                            font.pixelSize: 12
                            font.bold: true
                            font.family: bar.fontFamily
                        }
                        MouseArea {
                            id: btCloseMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.closePopup()
                        }
                    }
                }

                Text {
                    visible: root.appletStatusMsg.length > 0
                    Layout.fillWidth: true
                    text: root.appletStatusMsg
                    color: bar.subtext
                    font.pixelSize: 10
                    font.family: bar.fontFamily
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: bt.adapterName + " · " + bt.adapterStateText
                    color: bar.subtext
                    font.pixelSize: 11
                    font.family: bar.fontFamily
                    elide: Text.ElideRight
                }

                // ---- Detail panel ----
                Flickable {
                    id: detailFlick
                    visible: root.detailAddress.length > 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: detailCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    ColumnLayout {
                        id: detailCol
                        width: detailFlick.width
                        spacing: 8

                        Repeater {
                            model: {
                                var d = bt.findByAddress(root.detailAddress)
                                if (!d) return []
                                var bat = bt.batteryPercent(d)
                                var rows = [
                                    { k: "Name", v: bt.deviceLabel(d) },
                                    { k: "Address", v: bt.deviceAddress(d) },
                                    { k: "Status", v: bt.stateLabel(d) },
                                    { k: "Icon", v: (function(){ try { return d.icon || "—" } catch(e){ return "—" } })() },
                                    { k: "Paired", v: (function(){ try { return d.paired ? "Yes" : "No" } catch(e){ return "?" } })() },
                                    { k: "Bonded", v: (function(){ try { return d.bonded ? "Yes" : "No" } catch(e){ return "?" } })() },
                                    { k: "Trusted", v: (function(){ try { return d.trusted ? "Yes" : "No" } catch(e){ return "?" } })() },
                                    { k: "Blocked", v: (function(){ try { return d.blocked ? "Yes" : "No" } catch(e){ return "?" } })() },
                                    { k: "Wake allowed", v: (function(){ try { return d.wakeAllowed ? "Yes" : "No" } catch(e){ return "?" } })() },
                                    { k: "Battery", v: bat >= 0 ? (bat + "%") : "n/a" },
                                    { k: "Adapter", v: (function(){
                                        try {
                                            return (d.adapter && (d.adapter.name || d.adapter.adapterId)) || bt.adapterName
                                        } catch(e){ return bt.adapterName }
                                    })() },
                                    { k: "D-Bus path", v: (function(){ try { return d.dbusPath || "—" } catch(e){ return "—" } })() }
                                ]
                                return rows
                            }
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 8
                                Text {
                                    text: modelData.k
                                    color: bar.subtext
                                    font.pixelSize: 12
                                    font.family: bar.fontFamily
                                    Layout.preferredWidth: 100
                                }
                                Text {
                                    text: modelData.v
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.family: bar.fontFamily
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    wrapMode: Text.WrapAnywhere
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            radius: bar.buttonRadius
                            color: bluemanMa.containsMouse ? bar.popupButtonHoverBg : bar.surface
                            border.width: bar.controlBorderWidth
                            border.color: bar.dividerStrong
                            Text {
                                anchors.centerIn: parent
                                text: "Open Blueman manager"
                                color: bar.text
                                font.pixelSize: 12
                                font.family: bar.fontFamily
                            }
                            MouseArea {
                                id: bluemanMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Quickshell.execDetached(["blueman-manager"])
                            }
                        }
                    }
                }

                // ---- Main list view ----
                ColumnLayout {
                    visible: root.detailAddress.length === 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8

                    // Controls row (only when powered)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: bt.powered

                        // Scan — fixed width to longest label so "Stop scan" never clips
                        Rectangle {
                            width: Math.max(scanMetrics.width, stopScanMetrics.width) + 20
                            height: 26
                            radius: bar.buttonRadius
                            color: scanMa.containsMouse
                                   ? bar.popupButtonHoverBg
                                   : (bt.discovering ? Qt.rgba(0.20, 0.35, 0.55, 0.55) : bar.surface)
                            border.width: bar.controlBorderWidth
                            border.color: bt.discovering ? bar.accent : bar.dividerStrong
                            Text {
                                id: scanMetrics
                                visible: false
                                text: "Scan"
                                font.pixelSize: 11
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            Text {
                                id: stopScanMetrics
                                visible: false
                                text: "Stop scan"
                                font.pixelSize: 11
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            Text {
                                anchors.centerIn: parent
                                text: bt.discovering ? "Stop scan" : "Scan"
                                color: bar.text
                                font.pixelSize: 11
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            MouseArea {
                                id: scanMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: bt.toggleScan()
                            }
                        }

                        Rectangle {
                            width: Math.max(discMetrics.width, discOnMetrics.width) + 20
                            height: 26
                            radius: bar.buttonRadius
                            color: discMa.containsMouse
                                   ? bar.popupButtonHoverBg
                                   : (bt.discoverable ? Qt.rgba(0.20, 0.35, 0.55, 0.55) : bar.surface)
                            border.width: bar.controlBorderWidth
                            border.color: bt.discoverable ? bar.accent : bar.dividerStrong
                            Text {
                                id: discMetrics
                                visible: false
                                text: "Discoverable"
                                font.pixelSize: 11
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            Text {
                                id: discOnMetrics
                                visible: false
                                text: "Discoverable on"
                                font.pixelSize: 11
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            Text {
                                anchors.centerIn: parent
                                text: bt.discoverable ? "Discoverable on" : "Discoverable"
                                color: bar.text
                                font.pixelSize: 11
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            MouseArea {
                                id: discMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: bt.setDiscoverable(!bt.discoverable)
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            visible: bt.discovering
                            text: "Scanning…"
                            color: bar.accent
                            font.pixelSize: 11
                            font.family: bar.fontFamily
                        }
                    }

                    // Powered off empty state
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: !bt.powered

                        Column {
                            anchors.centerIn: parent
                            spacing: 10
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: (bar && bar.iconBluetoothOff) ? bar.iconBluetoothOff : "󰂲"
                                color: bar.muted
                                font.pixelSize: 36
                                font.family: bar.fontFamily
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: bt.hasAdapter ? "Bluetooth is off" : "No Bluetooth adapter"
                                color: bar.subtext
                                font.pixelSize: 13
                                font.family: bar.fontFamily
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Use Power on above, or right-click the pill"
                                color: bar.subtext
                                font.pixelSize: bar.fontTiny
                                font.family: bar.fontFamily
                            }
                        }
                    }

                    // Device lists
                    Flickable {
                        id: listFlick
                        visible: bt.powered
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: width
                        contentHeight: listCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        ColumnLayout {
                            id: listCol
                            width: listFlick.width
                            spacing: 12

                            // Connected
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                visible: bt.connectedAddresses.length > 0

                                Text {
                                    text: "Connected"
                                    color: bar.subtext
                                    font.pixelSize: bar.popupSectionSize || 11
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }

                                Repeater {
                                    model: bt.connectedAddresses
                                    delegate: deviceRow
                                }
                            }

                            // Paired (not connected)
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                visible: bt.pairedAddresses.length > 0

                                Text {
                                    text: "Paired"
                                    color: bar.subtext
                                    font.pixelSize: bar.popupSectionSize || 11
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }

                                Repeater {
                                    model: bt.pairedAddresses
                                    delegate: deviceRow
                                }
                            }

                            // Available (unpaired)
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                visible: bt.availableAddresses.length > 0

                                Text {
                                    text: "Available"
                                    color: bar.subtext
                                    font.pixelSize: bar.popupSectionSize || 11
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }

                                Repeater {
                                    model: bt.availableAddresses
                                    delegate: deviceRow
                                }
                            }

                            Text {
                                visible: bt.powered
                                         && bt.connectedAddresses.length === 0
                                         && bt.pairedAddresses.length === 0
                                         && bt.availableAddresses.length === 0
                                Layout.fillWidth: true
                                text: bt.discovering
                                      ? "Searching for devices…"
                                      : "No devices · press Scan to discover"
                                color: bar.subtext
                                font.pixelSize: 12
                                font.family: bar.fontFamily
                                horizontalAlignment: Text.AlignHCenter
                                Layout.topMargin: 24
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Right-click pill to toggle on/off bluetooth"
                        color: bar.subtext
                        font.pixelSize: bar.popupHintSize || bar.fontTiny
                        font.family: bar.fontFamily
                        horizontalAlignment: Text.AlignHCenter
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Rectangle {
                            Layout.fillWidth: true
                            height: 26
                            radius: bar.buttonRadius
                            color: powerMa.containsMouse
                                   ? (bt.powered ? Qt.rgba(0.55, 0.14, 0.14, 0.55) : bar.accent)
                                   : (bt.powered ? bar.surface : Qt.rgba(0.12, 0.35, 0.22, 0.55))
                            border.width: bar.controlBorderWidth
                            border.color: bar.dividerStrong
                            Text {
                                id: powerOnMetrics
                                visible: false
                                text: "Power on"
                                font.pixelSize: 11
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            Text {
                                id: powerOffMetrics
                                visible: false
                                text: "Power off"
                                font.pixelSize: 11
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            Text {
                                anchors.centerIn: parent
                                text: bt.powered ? "Power off" : "Power on"
                                color: powerMa.containsMouse && !bt.powered ? bar.bg : bar.text
                                font.pixelSize: 11
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            MouseArea {
                                id: powerMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: bt.togglePower()
                            }
                        }
                    }
                }
            }
        }

        // Click-outside close layer is not available inside PopupWindow the same
        // way; rely on pill toggle. Escape via Keys if focused.
        Component.onCompleted: {}
    }

    // Shared device row component
    Component {
        id: deviceRow

        ColumnLayout {
            id: rowRoot
            required property var modelData   // address string
            readonly property string addr: String(modelData || "")
            readonly property var device: bt.findByAddress(addr)
            readonly property bool expanded: root.expandedAddress === addr
            readonly property bool confirmingForget: root.confirmForgetAddress === addr
            readonly property int bat: bt.batteryPercent(device)
            readonly property bool isConnected: {
                try { return device ? !!device.connected : false }
                catch (e) { return false }
            }
            readonly property bool isPaired: {
                try { return device ? !!(device.paired || device.bonded) : false }
                catch (e) { return false }
            }
            readonly property bool isTrusted: {
                try { return device ? !!device.trusted : false }
                catch (e) { return false }
            }
            readonly property bool isBlocked: {
                try { return device ? !!device.blocked : false }
                catch (e) { return false }
            }
            readonly property bool isPairing: {
                try { return device ? !!device.pairing : false }
                catch (e) { return false }
            }
            readonly property bool renaming: root.renameAddress === addr

            function commitRename() {
                var name = renameField.text
                if (bt.renameDevice(addr, name)) {
                    root.endRename()
                    bt.deviceEpoch++
                }
            }

            function beginRename() {
                root.renameAddress = addr
                root.renameDraft = bt.deviceLabel(device)
                root.confirmForgetAddress = ""
                // Arm keyboard grab before focusing the field.
                btFocusGrab.active = true
                renameFocusTimer.restart()
            }

            Layout.fillWidth: true
            spacing: 0

            Timer {
                id: renameFocusTimer
                interval: 30
                repeat: false
                onTriggered: {
                    if (!renaming) return
                    renameField.text = root.renameDraft
                    renameField.forceActiveFocus()
                    renameField.selectAll()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                radius: bar.buttonRadius
                color: rowMa.containsMouse || expanded
                       ? bar.popupButtonHoverBg
                       : Qt.rgba(0.10, 0.10, 0.12, 0.35)
                border.width: bar.controlBorderWidth
                border.color: isConnected ? bar.accent : bar.dividerStrong

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    // Status dot
                    Rectangle {
                        width: 8
                        height: 8
                        radius: 4
                        color: isConnected ? "#10B981"
                               : (isPairing ? bar.accent
                                  : (isBlocked ? "#EF4444" : bar.overlay))
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Text {
                        Layout.fillWidth: true
                        text: bt.deviceLabel(device)
                        color: bar.text
                        font.pixelSize: 12
                        font.family: bar.fontFamily
                        elide: Text.ElideRight
                    }

                    // Battery
                    Row {
                        visible: bat >= 0
                        spacing: 3
                        Layout.alignment: Qt.AlignVCenter
                        Text {
                            text: (bar && bar.iconAudioBattery) ? bar.iconAudioBattery : "󰁹"
                            color: bt.batteryColor(bat)
                            font.pixelSize: 12
                            font.family: bar.fontFamily
                        }
                        Text {
                            text: bat + "%"
                            color: bt.batteryColor(bat)
                            font.pixelSize: 11
                            font.bold: true
                            font.family: bar.fontFamily
                        }
                    }

                    Text {
                        text: bt.stateLabel(device)
                        color: bar.subtext
                        font.pixelSize: 10
                        font.family: bar.fontFamily
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Text {
                        text: expanded ? "▾" : "▸"
                        color: bar.subtext
                        font.pixelSize: 11
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                MouseArea {
                    id: rowMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.expandedAddress === addr) {
                            root.expandedAddress = ""
                            root.confirmForgetAddress = ""
                            root.endRename()
                            root.clearProfiles()
                        } else {
                            root.expandedAddress = addr
                            root.confirmForgetAddress = ""
                            root.endRename()
                            root.refreshProfilesForAddress(addr)
                        }
                    }
                }
            }

            // Expanded actions
            Rectangle {
                visible: expanded
                Layout.fillWidth: true
                Layout.preferredHeight: actionsCol.implicitHeight + 12
                radius: bar.buttonRadius
                color: Qt.rgba(0.08, 0.08, 0.10, 0.55)
                border.width: bar.controlBorderWidth
                border.color: bar.dividerStrong

                ColumnLayout {
                    id: actionsCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 8
                    spacing: 6

                    // Action chips row 1: connect / pair
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6

                        // Connect / Disconnect
                        Rectangle {
                            visible: isPaired || isConnected
                            width: Math.max(connMetrics.width, discMetrics2.width) + 14
                            height: 24
                            radius: bar.smallButtonRadius
                            color: connMa.containsMouse ? bar.accent : bar.surface
                            border.width: 1
                            border.color: bar.dividerStrong
                            Text {
                                id: connMetrics
                                visible: false
                                text: "Connect"
                                font.pixelSize: 11
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            Text {
                                id: discMetrics2
                                visible: false
                                text: "Disconnect"
                                font.pixelSize: 11
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            Text {
                                anchors.centerIn: parent
                                text: isConnected ? "Disconnect" : "Connect"
                                color: connMa.containsMouse ? bar.bg : bar.text
                                font.pixelSize: 11
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            MouseArea {
                                id: connMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (isConnected) bt.disconnectDevice(addr)
                                    else bt.connectDevice(addr)
                                }
                            }
                        }

                        // Pair / Cancel pair
                        Rectangle {
                            visible: !isPaired || isPairing
                            width: Math.max(pairMetrics.width, cancelPairMetrics.width) + 14
                            height: 24
                            radius: bar.smallButtonRadius
                            color: pairMa.containsMouse ? bar.accent : bar.surface
                            border.width: 1
                            border.color: bar.dividerStrong
                            Text {
                                id: pairMetrics
                                visible: false
                                text: "Pair"
                                font.pixelSize: 11
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            Text {
                                id: cancelPairMetrics
                                visible: false
                                text: "Cancel pair"
                                font.pixelSize: 11
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            Text {
                                anchors.centerIn: parent
                                text: isPairing ? "Cancel pair" : "Pair"
                                color: pairMa.containsMouse ? bar.bg : bar.text
                                font.pixelSize: 11
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            MouseArea {
                                id: pairMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (isPairing) bt.cancelPairDevice(addr)
                                    else bt.pairDevice(addr)
                                }
                            }
                        }

                        // Rename (paired devices only)
                        Rectangle {
                            visible: isPaired || isConnected
                            width: Math.max(renameMetrics.width, cancelRenameMetrics.width) + 14
                            height: 24
                            radius: bar.smallButtonRadius
                            color: renameBtnMa.containsMouse || renaming
                                   ? bar.popupButtonHoverBg : bar.surface
                            border.width: 1
                            border.color: renaming ? bar.accent : bar.dividerStrong
                            Text {
                                id: renameMetrics
                                visible: false
                                text: "Rename"
                                font.pixelSize: 11
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            Text {
                                id: cancelRenameMetrics
                                visible: false
                                text: "Cancel rename"
                                font.pixelSize: 11
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            Text {
                                anchors.centerIn: parent
                                text: renaming ? "Cancel rename" : "Rename"
                                color: bar.text
                                font.pixelSize: 11
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            MouseArea {
                                id: renameBtnMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (renaming)
                                        root.endRename()
                                    else
                                        rowRoot.beginRename()
                                }
                            }
                        }

                        // Trust
                        Rectangle {
                            visible: isPaired || isConnected
                            width: Math.max(trustMetrics.width, untrustMetrics.width) + 14
                            height: 24
                            radius: bar.smallButtonRadius
                            color: trustMa.containsMouse ? bar.popupButtonHoverBg : bar.surface
                            border.width: 1
                            border.color: isTrusted ? bar.accent : bar.dividerStrong
                            Text {
                                id: trustMetrics
                                visible: false
                                text: "Trust"
                                font.pixelSize: 11
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            Text {
                                id: untrustMetrics
                                visible: false
                                text: "Untrust"
                                font.pixelSize: 11
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            Text {
                                anchors.centerIn: parent
                                text: isTrusted ? "Untrust" : "Trust"
                                color: bar.text
                                font.pixelSize: 11
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            MouseArea {
                                id: trustMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: bt.setTrusted(addr, !isTrusted)
                            }
                        }

                        // Block
                        Rectangle {
                            width: blockLbl.implicitWidth + 14
                            height: 24
                            radius: bar.smallButtonRadius
                            color: blockMa.containsMouse ? Qt.rgba(0.55, 0.14, 0.14, 0.45) : bar.surface
                            border.width: 1
                            border.color: isBlocked ? "#EF4444" : bar.dividerStrong
                            Text {
                                id: blockLbl
                                anchors.centerIn: parent
                                text: isBlocked ? "Unblock" : "Block"
                                color: bar.text
                                font.pixelSize: 11
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            MouseArea {
                                id: blockMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: bt.setBlocked(addr, !isBlocked)
                            }
                        }

                        // Info
                        Rectangle {
                            width: infoLbl.implicitWidth + 14
                            height: 24
                            radius: bar.smallButtonRadius
                            color: infoMa.containsMouse ? bar.popupButtonHoverBg : bar.surface
                            border.width: 1
                            border.color: bar.dividerStrong
                            Text {
                                id: infoLbl
                                anchors.centerIn: parent
                                text: "Info"
                                color: bar.text
                                font.pixelSize: 11
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            MouseArea {
                                id: infoMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.detailAddress = addr
                            }
                        }

                        // Remove
                        Rectangle {
                            visible: isPaired || isConnected
                            width: rmLbl.implicitWidth + 14
                            height: 24
                            radius: bar.smallButtonRadius
                            color: rmMa.containsMouse ? Qt.rgba(0.55, 0.14, 0.14, 0.45) : bar.surface
                            border.width: 1
                            border.color: bar.dividerStrong
                            Text {
                                id: rmLbl
                                anchors.centerIn: parent
                                text: confirmingForget ? "Confirm remove" : "Remove"
                                color: confirmingForget ? "#EF4444" : bar.text
                                font.pixelSize: 11
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            MouseArea {
                                id: rmMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.confirmForgetAddress === addr) {
                                        bt.forgetDevice(addr)
                                    } else {
                                        root.confirmForgetAddress = addr
                                    }
                                }
                            }
                        }

                        // Cancel remove confirm
                        Rectangle {
                            visible: confirmingForget
                            width: cancelRmLbl.implicitWidth + 14
                            height: 24
                            radius: bar.smallButtonRadius
                            color: cancelRmMa.containsMouse ? bar.popupButtonHoverBg : bar.surface
                            border.width: 1
                            border.color: bar.dividerStrong
                            Text {
                                id: cancelRmLbl
                                anchors.centerIn: parent
                                text: "Cancel"
                                color: bar.subtext
                                font.pixelSize: 11
                                font.family: bar.fontFamily
                            }
                            MouseArea {
                                id: cancelRmMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.confirmForgetAddress = ""
                            }
                        }
                    }

                    // Rename editor
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: renaming

                        Text {
                            text: "Name"
                            color: bar.subtext
                            font.pixelSize: 11
                            font.family: bar.fontFamily
                            Layout.preferredWidth: 40
                        }

                        TextField {
                            id: renameField
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            color: bar.text
                            placeholderText: "Device name"
                            placeholderTextColor: bar.overlay
                            font.pixelSize: 12
                            font.family: bar.fontFamily
                            selectByMouse: true
                            // Ensure clicks on the field re-arm compositor keyboard focus.
                            activeFocusOnPress: true
                            focus: renaming
                            background: Rectangle {
                                radius: bar.smallButtonRadius
                                color: Qt.rgba(0.10, 0.10, 0.12, 0.65)
                                border.width: 1
                                border.color: renameField.activeFocus ? bar.accent : bar.dividerStrong
                            }
                            onActiveFocusChanged: {
                                // Clicking the field after an outside-click clear re-grabs keys.
                                if (activeFocus && renaming)
                                    btFocusGrab.active = true
                            }
                            Keys.onReturnPressed: rowRoot.commitRename()
                            Keys.onEnterPressed: rowRoot.commitRename()
                            Keys.onEscapePressed: root.endRename()
                        }

                        Rectangle {
                            width: saveRenameLbl.implicitWidth + 14
                            height: 28
                            radius: bar.smallButtonRadius
                            color: saveRenameMa.containsMouse ? bar.accent : bar.surface
                            border.width: 1
                            border.color: bar.dividerStrong
                            Text {
                                id: saveRenameLbl
                                anchors.centerIn: parent
                                text: "Save"
                                color: saveRenameMa.containsMouse ? bar.bg : bar.text
                                font.pixelSize: 11
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            MouseArea {
                                id: saveRenameMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: rowRoot.commitRename()
                            }
                        }
                    }

                    // Profile picker (connected audio)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: isConnected && root.expandedAddress === addr
                                 && root.profileList && root.profileList.length > 0

                        Text {
                            text: "Profile"
                            color: bar.subtext
                            font.pixelSize: 11
                            font.family: bar.fontFamily
                            Layout.preferredWidth: 48
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 26
                            radius: bar.buttonRadius
                            color: profMa.containsMouse ? bar.popupButtonHoverBg : Qt.rgba(0.10, 0.10, 0.12, 0.45)
                            border.width: bar.controlBorderWidth
                            border.color: bar.dividerStrong

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 6
                                Text {
                                    Layout.fillWidth: true
                                    text: root.profileLabel()
                                    color: bar.text
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                    font.family: bar.fontFamily
                                }
                                Text {
                                    text: "▼"
                                    color: bar.subtext
                                    font.pixelSize: 11
                                }
                            }

                            MouseArea {
                                id: profMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: openProfileMenu(addr)
                            }
                        }
                    }

                    Text {
                        visible: confirmingForget
                        Layout.fillWidth: true
                        text: "Removes the pairing permanently from this computer."
                        color: "#EF4444"
                        font.pixelSize: 10
                        font.family: bar.fontFamily
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }

    // Profile picker popup
    PopupWindow {
        id: profilePopup
        anchor.window: bar
        implicitWidth: 320
        implicitHeight: Math.min(280, 16 + profileMenuCol.implicitHeight)
        visible: false
        color: "transparent"

        property string forAddress: ""

        Rectangle {
            anchors.fill: parent
            radius: bar.popupRadius
            color: bar.glassPopupBg
            border.width: bar.controlBorderWidth
            border.color: bar.glassPopupBorder

            ColumnLayout {
                id: profileMenuCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                spacing: 4

                Text {
                    text: "Audio profile"
                    color: bar.subtext
                    font.pixelSize: 11
                    font.bold: true
                    font.family: bar.fontFamily
                    Layout.leftMargin: 4
                    Layout.bottomMargin: 4
                }

                Repeater {
                    model: root.usableProfileList
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        height: 30
                        radius: bar.buttonRadius
                        color: pItemMa.containsMouse ? bar.popupButtonHoverBg
                               : (modelData.name === root.profileActive
                                  ? Qt.rgba(0.20, 0.35, 0.55, 0.40) : "transparent")
                        border.width: modelData.name === root.profileActive ? 1 : 0
                        border.color: bar.accent

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            verticalAlignment: Text.AlignVCenter
                            text: modelData.description || modelData.name
                            color: bar.text
                            font.pixelSize: 12
                            font.family: bar.fontFamily
                            elide: Text.ElideRight
                        }
                        MouseArea {
                            id: pItemMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.applyCardProfile(root.profileCard, modelData.name)
                                profilePopup.visible = false
                            }
                        }
                    }
                }
            }
        }
    }

    function openProfileMenu(addr) {
        if (!root.profileList || root.profileList.length === 0) {
            root.refreshProfilesForAddress(addr)
            return
        }
        profilePopup.forAddress = addr
        var popupWidth = profilePopup.implicitWidth
        if (typeof bar.placePopup === "function") {
            bar.placePopup(profilePopup, root, popupWidth, profilePopup.implicitHeight, 8, root.width / 2)
        } else {
            var pos = root.mapToItem(barBg, root.width / 2, root.height)
            var targetX = bar.sideMargin + pos.x - (popupWidth / 2)
            var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920
            profilePopup.anchor.rect.x = Math.max(12, Math.min(targetX, screenW - popupWidth - 12))
            profilePopup.anchor.rect.y = bar.popupAnchorY(profilePopup.implicitHeight, 8)
        }
        profilePopup.visible = true
    }

    function endRename() {
        root.renameAddress = ""
        root.renameDraft = ""
        // Drop keyboard grab when not editing (popup can stay open).
        if (btFocusGrab.active)
            btFocusGrab.active = false
    }

    function showPopup() {
        root.detailAddress = ""
        root.confirmForgetAddress = ""
        root.endRename()
        root.refreshBluemanStatus()
        // Refresh profiles if something is expanded
        if (root.expandedAddress.length)
            root.refreshProfilesForAddress(root.expandedAddress)

        var popupWidth = btPopup.implicitWidth
        if (typeof bar.placePopup === "function") {
            bar.placePopup(btPopup, root, popupWidth, btPopup.implicitHeight, 2, root.width / 2)
        } else {
            var pos = root.mapToItem(barBg, root.width / 2, root.height)
            var targetX = bar.sideMargin + pos.x - (popupWidth / 2)
            var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920
            var minX = 12
            var maxX = screenW - popupWidth - 12
            btPopup.anchor.rect.x = Math.max(minX, Math.min(targetX, maxX))
            btPopup.anchor.rect.y = bar.popupAnchorY(btPopup.implicitHeight, 2)
        }
        btPopup.visible = true
    }

    function closePopup() {
        btPopup.visible = false
        profilePopup.visible = false
        root.confirmForgetAddress = ""
        root.expandedAddress = ""
        root.detailAddress = ""
        root.endRename()
        root.clearProfiles()
        // Stop discovery when the menu closes — saves radio/CPU work.
        if (bt.discovering)
            bt.setDiscovering(false)
    }

    // =========================================================================
    // Public API — used by shell.qml Io.IpcHandler target "bluetoothPill"
    // =========================================================================
    //
    // Popup:
    //   qs ipc call bluetoothPill showPopup
    //   qs ipc call bluetoothPill hidePopup
    //   qs ipc call bluetoothPill togglePopup
    // Adapter:
    //   qs ipc call bluetoothPill setPower true|false
    //   qs ipc call bluetoothPill togglePower / enable / disable
    //   qs ipc call bluetoothPill setDiscoverable true|false
    //   qs ipc call bluetoothPill toggleDiscoverable
    // Scan:
    //   qs ipc call bluetoothPill startScan / stopScan / toggleScan
    // Blueman tray:
    //   qs ipc call bluetoothPill startApplet / stopApplet / toggleApplet   (session only)
    //   qs ipc call bluetoothPill disableApplet / enableApplet              (survives reboot)
    //   qs ipc call bluetoothPill setAppletAutostart true|false
    // Devices (MAC as string, e.g. "A0:0C:E2:66:FB:7D"):
    //   qs ipc call bluetoothPill connectDevice "AA:BB:…"
    //   qs ipc call bluetoothPill disconnectDevice "AA:BB:…"
    //   qs ipc call bluetoothPill pairDevice "AA:BB:…"
    //   qs ipc call bluetoothPill cancelPair "AA:BB:…"
    //   qs ipc call bluetoothPill forgetDevice "AA:BB:…"
    //   qs ipc call bluetoothPill setTrusted "AA:BB:…" true|false
    //   qs ipc call bluetoothPill setBlocked "AA:BB:…" true|false
    //   qs ipc call bluetoothPill renameDevice "AA:BB:…" "New Name"
    //   qs ipc call bluetoothPill setCardProfile "AA:BB:…" "a2dp-sink"
    // =========================================================================

    function hidePopup() {
        closePopup()
    }

    function togglePopup() {
        if (btPopup.visible)
            closePopup()
        else
            showPopup()
    }

    function setPower(enabled) {
        bt.setPowered(!!enabled)
    }

    function enable() {
        bt.setPowered(true)
    }

    function disable() {
        bt.setPowered(false)
    }

    function togglePower() {
        bt.togglePower()
    }

    function startScan() {
        bt.setDiscovering(true)
    }

    function stopScan() {
        bt.setDiscovering(false)
    }

    function toggleScan() {
        bt.toggleScan()
    }

    function setDiscoverable(enabled) {
        bt.setDiscoverable(!!enabled)
    }

    function toggleDiscoverable() {
        bt.setDiscoverable(!bt.discoverable)
    }

    // Session-only (comes back after reboot if autostart still enabled)
    function startApplet() {
        bt.startBlueman()
    }

    function stopApplet() {
        bt.stopBlueman()
    }

    function toggleApplet() {
        bt.toggleBlueman()
    }

    // Sticky across reboots (XDG autostart override + stop/start now)
    function disableApplet() {
        bt.disableBluemanAutostart()
    }

    function enableApplet() {
        bt.enableBluemanAutostart()
    }

    function setAppletAutostart(enabled) {
        bt.setBluemanAutostart(!!enabled)
    }

    function connectDevice(address) {
        bt.connectDevice(String(address || ""))
    }

    function disconnectDevice(address) {
        bt.disconnectDevice(String(address || ""))
    }

    function pairDevice(address) {
        bt.pairDevice(String(address || ""))
    }

    function cancelPair(address) {
        bt.cancelPairDevice(String(address || ""))
    }

    function forgetDevice(address) {
        bt.forgetDevice(String(address || ""))
    }

    function setTrusted(address, trusted) {
        bt.setTrusted(String(address || ""), !!trusted)
    }

    function setBlocked(address, blocked) {
        bt.setBlocked(String(address || ""), !!blocked)
    }

    function renameDevice(address, name) {
        bt.renameDevice(String(address || ""), String(name || ""))
        bt.deviceEpoch++
    }

    // address = device MAC; profileName = PipeWire card profile (e.g. a2dp-sink)
    function setCardProfile(address, profileName) {
        var addr = String(address || "")
        var prof = String(profileName || "")
        if (!addr.length || !prof.length) return
        var card = bt.cardName(addr)
        if (!card.length) return
        root.applyCardProfile(card, prof)
    }
}
