import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Networking
import Quickshell.Hyprland
import Quickshell.Io as Io
import "../components"

// =============================================================================
// NetworkPill.qml — NetworkManager connection manager pill (nm-applet replacement)
// =============================================================================
//
// Purpose:
//   Glassmorphic network pill for the status bar. Manage wired/WiFi adapters,
//   radio power, networking on/off, WiFi scan/connect/forget, and view
//   connection details (IP/DNS/gateway) similar to nm-applet Connection Info.
//
// Theme Properties Consumed:
//   - bar.pillRadius, bar.pillBg, bar.pillBorder, bar.accent, bar.glassHover
//   - bar.iconHoverBg, bar.controlBorderWidth, bar.popupRadius, bar.glassPopupBg
//   - bar.glassPopupBorder, bar.glassPopupHighlight, bar.popupHeaderHighlightHeight
//   - bar.popupSpacing, bar.popupTitleSize, bar.popupSectionSize, bar.popupHintSize
//   - bar.popupButtonHoverBg, bar.dividerStrong, bar.buttonRadius, bar.surface
//   - bar.text, bar.subtext, bar.overlay, bar.muted, bar.bg
//   - bar.fontFamily, bar.fontTiny, bar.fontSmall, bar.iconSizeTray, bar.fontPillLabel
//   - bar.popupNetworkWidth, bar.popupNetworkWifiWidth, bar.popupNetworkHeight
//   - bar.iconNetwork*, bar.tooltipDelay, bar.popupAnchorY()
//
// Dependencies:
//   - required property var bar
//   - required property Item barBg
//   - property bool embedded (optional) — when true, omit pill chrome so a
//     parent shell (shell.qml connectivityPill) can group Network + Bluetooth
//   - Quickshell.Networking (devices, wifi radio, connect/scan)
//   - scripts/network-control.sh (live IP/DNS, networking on/off, nm-applet)
//
// Notes:
//   - Device/network selection is iface- and SSID-keyed (no long-lived NM objects).
//   - Advanced profile editing opens nm-connection-editor (escape hatch).
//   - WiFi scanner enabled only while the popup is open.
//   - Perf: one-pass snapshot for bar + (when open) WiFi lists; status poll slow
//     when closed / faster when open; connection model + rate history only while open.
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

    readonly property string controlScript: "/home/crome/.config/quickshell/scripts/network-control.sh"

    // UI navigation
    property string detailIface: ""          // non-empty → details panel
    property string pskSsid: ""              // SSID awaiting password
    property string pskDraft: ""
    property string confirmForgetSsid: ""
    property string statusMessage: ""        // transient footer hint
    property bool appletRunning: false
    // false when sticky-disabled (XDG mask and/or unit disabled) — survives reboot
    property bool appletAutostartEnabled: true
    property var statusData: ({})            // from network-control.sh status
    property int statusEpoch: 0
    property var _failBoundNetwork: null      // last WifiNetwork with connectionFailed handler
    property var rxHistory: []               // downstream B/s samples for graph
    property var txHistory: []               // upstream B/s samples for graph
    property real lastRxRate: 0
    property real lastTxRate: 0
    readonly property int rateHistoryMax: 48
    // Main view is always two columns: Adapters (left) | WiFi (right)
    readonly property int networkMainWidth: (bar && bar.popupNetworkWidth) ? bar.popupNetworkWidth : 520
    readonly property int networkWifiWidth: (bar && bar.popupNetworkWifiWidth) ? bar.popupNetworkWifiWidth : 340
    readonly property int networkPopupGap: 10
    readonly property bool twoColumnMain: detailIface.length === 0
    readonly property int networkPopupWidth: twoColumnMain ? (networkMainWidth + networkWifiWidth + networkPopupGap) : networkMainWidth

    // Saved NM connections for the dropdown (from network-control.sh status)
    property var connectionModel: []
    property int connectionIndex: -1
    property bool _suppressConnectionActivate: false

    // Standalone: full pill size. Embedded: content chip sized for shared shell.
    // Horizontal scale only: layout width grows with _s; content is x-scaled to match.
    readonly property int _padW: embedded ? 12 : 14
    readonly property int _naturalW: netContent.implicitWidth + _padW
    implicitWidth: Math.round(_naturalW * _s)
    implicitHeight: embedded ? Math.max(18, _h - (bar.pillChipInset !== undefined ? bar.pillChipInset : 4)) : _h
    width: implicitWidth
    height: implicitHeight
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight
    Layout.alignment: Qt.AlignVCenter

    HoverHandler {
        id: netHoverVis
    }
    readonly property bool netHovered: netHoverVis.hovered || netMouse.containsMouse

    // Standalone: stable outer chrome; content chip highlights on hover.
    // Embedded (connectivity pill): this rect IS the content chip — hover rim + glow.
    radius: embedded ? bar.workspaceRadius : bar.pillRadius
    color: {
        if (embedded)
            return root.netHovered ? bar.iconHoverBg : "transparent"
        return bar.pillBg
    }
    border.width: embedded
        ? (root.netHovered ? bar.controlBorderWidth : 0)
        : bar.controlBorderWidth
    border.color: embedded
        ? (root.netHovered ? bar.accent : "transparent")
        : bar.pillBorder

    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }
    Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }

    readonly property bool _showTrafficGraph: bar.showNetTrafficGraph !== undefined
        ? !!bar.showNetTrafficGraph : true

    // =========================================================================
    // Network state helpers
    // =========================================================================
    QtObject {
        id: net

        property int deviceEpoch: 0
        readonly property bool popupOpen: netPopup.visible

        readonly property bool wifiEnabled: {
            try { return !!Networking.wifiEnabled } catch (e) { return false }
        }
        readonly property bool wifiHardwareEnabled: {
            try { return !!Networking.wifiHardwareEnabled } catch (e) { return true }
        }
        readonly property bool networkingEnabled: {
            var d = root.statusData || {}
            if (d.networking !== undefined) return !!d.networking
            return true
        }
        readonly property string connectivity: {
            try {
                if (typeof NetworkConnectivity !== "undefined" && NetworkConnectivity.toString)
                    return NetworkConnectivity.toString(Networking.connectivity)
            } catch (e1) {}
            var d = root.statusData || {}
            return d.connectivity || "unknown"
        }
        readonly property bool isPortal: {
            try {
                return Networking.connectivity === NetworkConnectivity.Portal
                    || Networking.connectivity === 2
            } catch (e) {
                return String(net.connectivity).toLowerCase() === "portal"
            }
        }

        // Single pass over Networking.devices → bar metrics + (when open) WiFi SSID list.
        // Avoids separate O(devices) walks for wifiConnected / connectedWifiSsid / lists.
        readonly property var snapshot: {
            var __ = deviceEpoch
            var __s = root.statusEpoch
            var wantLists = popupOpen
            var devices = []
            var wifiScored = []   // {ssid, conn, known, sig} when wantLists
            var primaryLabel = ""
            var primaryIp = ""
            var primaryIface = ""
            var primaryKind = "none"   // wired | wifi | none
            var anyConnected = false
            var wifiConnected = false
            var connectedWifiSsid = ""
            var wifiStrength = -1
            var hasWifi = false
            var seenSsid = ({})

            try {
                var vals = (Networking.devices && Networking.devices.values)
                    ? Networking.devices.values : []
                for (var i = 0; i < vals.length; i++) {
                    var dev = vals[i]
                    if (!dev) continue
                    try {
                        var name = String(dev.name || "")
                        if (!name.length) continue
                        var dtype = dev.type
                        var isWifi = (dtype === DeviceType.Wifi || dtype === 1)
                        var isWired = (dtype === DeviceType.Wired || dtype === 2)
                        var connected = !!dev.connected
                        // Touch state lightly for notify re-eval
                        var _st = dev.state
                        devices.push(name)
                        if (isWifi) hasWifi = true

                        if (connected) {
                            anyConnected = true
                            if (isWifi) wifiConnected = true
                            if (!primaryLabel.length || isWired) {
                                primaryKind = isWifi ? "wifi" : (isWired ? "wired" : "other")
                                primaryLabel = name
                                primaryIface = name
                                var st = root.deviceStatus(name)
                                if (st && st.connection) primaryLabel = st.connection
                                if (st && st.ip4 && st.ip4.length) primaryIp = st.ip4[0]
                            }
                        }

                        if (isWifi) {
                            try {
                                var nets = (dev.networks && dev.networks.values)
                                    ? dev.networks.values : []
                                for (var j = 0; j < nets.length; j++) {
                                    var n = nets[j]
                                    if (!n) continue
                                    var ssid = String(n.name || "")
                                    if (!ssid.length) continue
                                    var nConn = !!n.connected
                                    if (nConn) {
                                        wifiConnected = true
                                        if (!connectedWifiSsid.length)
                                            connectedWifiSsid = ssid
                                        var sig = Number(n.signalStrength)
                                        if (!isNaN(sig))
                                            wifiStrength = Math.round((sig <= 1.01 ? sig * 100 : sig))
                                        if (connected || !primaryLabel.length || primaryKind !== "wired") {
                                            primaryKind = "wifi"
                                            primaryLabel = ssid
                                            primaryIface = name
                                            var stw = root.deviceStatus(name)
                                            if (stw && stw.ip4 && stw.ip4.length) primaryIp = stw.ip4[0]
                                        }
                                    }
                                    // Full AP list only while popup is open (scanner may be active)
                                    if (wantLists && !seenSsid[ssid]) {
                                        seenSsid[ssid] = true
                                        var known = !!n.known
                                        var sig2 = Number(n.signalStrength)
                                        if (isNaN(sig2)) sig2 = 0
                                        wifiScored.push({
                                            ssid: ssid,
                                            conn: nConn ? 1 : 0,
                                            known: known ? 1 : 0,
                                            sig: sig2
                                        })
                                    }
                                }
                            } catch (e1) {}
                        }
                    } catch (e0) {}
                }
            } catch (e) {}

            // Sort SSIDs once: connected → known → signal → name
            if (wantLists && wifiScored.length > 1) {
                wifiScored.sort(function(a, b) {
                    if (b.conn !== a.conn) return b.conn - a.conn
                    if (b.known !== a.known) return b.known - a.known
                    if (b.sig !== a.sig) return b.sig - a.sig
                    return String(a.ssid).localeCompare(String(b.ssid))
                })
            }
            var wifiSsids = []
            for (var s = 0; s < wifiScored.length; s++)
                wifiSsids.push(wifiScored[s].ssid)

            return {
                deviceIfaces: devices,
                wifiSsids: wifiSsids,
                primaryLabel: primaryLabel,
                primaryIp: primaryIp,
                primaryIface: primaryIface,
                primaryKind: primaryKind,
                anyConnected: anyConnected,
                wifiStrength: wifiStrength,
                wifiConnected: wifiConnected,
                connectedWifiSsid: connectedWifiSsid,
                hasWifi: hasWifi
            }
        }

        readonly property var deviceIfaces: snapshot.deviceIfaces
        readonly property var wifiSsids: snapshot.wifiSsids
        readonly property string primaryLabel: snapshot.primaryLabel
        readonly property string primaryIp: snapshot.primaryIp
        readonly property string primaryIface: snapshot.primaryIface
        readonly property string primaryKind: snapshot.primaryKind
        readonly property bool anyConnected: snapshot.anyConnected
        readonly property int wifiStrength: snapshot.wifiStrength
        readonly property bool wifiConnected: snapshot.wifiConnected
        readonly property string connectedWifiSsid: snapshot.connectedWifiSsid
        readonly property bool hasWifi: snapshot.hasWifi

        // Right pane always present; scanner/list only when radio is on
        readonly property bool showWifiNetworkList: wifiEnabled

        readonly property string pillGlyph: {
            if (!networkingEnabled)
                return (bar && bar.iconNetworkOff) ? bar.iconNetworkOff : "󰲛"
            if (isPortal)
                return (bar && bar.iconNetworkPortal) ? bar.iconNetworkPortal : "󰖟"
            if (primaryKind === "wired")
                return (bar && bar.iconNetworkWired) ? bar.iconNetworkWired : "󰈀"
            if (primaryKind === "wifi") {
                var s = wifiStrength
                if (s < 0)
                    return (bar && bar.iconNetworkWifi) ? bar.iconNetworkWifi : "󰤨"
                if (s >= 75) return (bar && bar.iconNetworkWifi) ? bar.iconNetworkWifi : "󰤨"
                if (s >= 50) return (bar && bar.iconNetworkWifiFair) ? bar.iconNetworkWifiFair : "󰤥"
                if (s >= 25) return (bar && bar.iconNetworkWifiWeak) ? bar.iconNetworkWifiWeak : "󰤢"
                return (bar && bar.iconNetworkWifiNone) ? bar.iconNetworkWifiNone : "󰤟"
            }
            if (!wifiEnabled && hasWifiDevice())
                return (bar && bar.iconNetworkWifiOff) ? bar.iconNetworkWifiOff : "󰤭"
            return (bar && bar.iconNetworkDisconnected) ? bar.iconNetworkDisconnected : "󰤮"
        }

        readonly property color pillGlyphColor: {
            if (!networkingEnabled) return bar ? bar.muted : "#6e7a90"
            if (isPortal) return "#F59E0B"
            if (anyConnected) return bar ? (bar.iconColor !== undefined ? bar.iconColor : bar.subtext) : "#ffffff"
            return bar ? (bar.iconColor !== undefined ? bar.iconColor : bar.subtext) : "#a8b4c8"
        }

        function hasWifiDevice() {
            return hasWifi
        }

        function findDevice(iface) {
            if (!iface) return null
            try {
                var vals = (Networking.devices && Networking.devices.values)
                    ? Networking.devices.values : []
                for (var i = 0; i < vals.length; i++) {
                    var d = vals[i]
                    if (d && String(d.name || "") === String(iface))
                        return d
                }
            } catch (e) {}
            return null
        }

        function findWifiNetwork(ssid) {
            if (!ssid) return null
            try {
                var vals = (Networking.devices && Networking.devices.values)
                    ? Networking.devices.values : []
                for (var i = 0; i < vals.length; i++) {
                    var d = vals[i]
                    if (!d) continue
                    var t = d.type
                    if (!(t === DeviceType.Wifi || t === 1)) continue
                    var nets = (d.networks && d.networks.values) ? d.networks.values : []
                    for (var j = 0; j < nets.length; j++) {
                        var n = nets[j]
                        if (n && String(n.name || "") === String(ssid))
                            return n
                    }
                }
            } catch (e) {}
            return null
        }

        function isWifiDevice(dev) {
            if (!dev) return false
            try {
                var t = dev.type
                return t === DeviceType.Wifi || t === 1
            } catch (e) { return false }
        }

        function isWiredDevice(dev) {
            if (!dev) return false
            try {
                var t = dev.type
                return t === DeviceType.Wired || t === 2
            } catch (e) { return false }
        }

        function deviceTypeLabel(dev) {
            if (!dev) return "?"
            if (isWifiDevice(dev)) return "WiFi"
            if (isWiredDevice(dev)) return "Wired"
            try {
                if (typeof DeviceType !== "undefined" && DeviceType.toString)
                    return DeviceType.toString(dev.type)
            } catch (e) {}
            return "Device"
        }

        function stateLabel(dev) {
            if (!dev) return ""
            try {
                if (typeof ConnectionState !== "undefined" && ConnectionState.toString)
                    return ConnectionState.toString(dev.state)
                if (dev.connected) return "Connected"
                var s = dev.state
                if (s === 1) return "Connecting"
                if (s === 2) return "Connected"
                if (s === 3) return "Disconnecting"
                if (s === 4) return "Disconnected"
            } catch (e) {}
            return dev.connected ? "Connected" : "Disconnected"
        }

        function securityLabel(sec) {
            try {
                if (typeof WifiSecurityType !== "undefined" && WifiSecurityType.toString)
                    return WifiSecurityType.toString(sec)
            } catch (e) {}
            // Fallback common values
            var map = {
                0: "WPA3-SuiteB", 1: "SAE", 2: "WPA2-EAP", 3: "WPA2",
                4: "WPA-EAP", 5: "WPA", 6: "WEP", 7: "DynWEP",
                8: "LEAP", 9: "OWE", 10: "Open", 11: "?"
            }
            return map[sec] !== undefined ? map[sec] : String(sec)
        }

        function needsPsk(sec) {
            try {
                if (sec === WifiSecurityType.WpaPsk || sec === WifiSecurityType.Wpa2Psk
                        || sec === WifiSecurityType.Sae)
                    return true
                // numeric fallbacks from qmltypes order
                if (sec === 1 || sec === 3 || sec === 5) return true
            } catch (e) {}
            return false
        }

        function isOpenSecurity(sec) {
            try {
                if (sec === WifiSecurityType.Open || sec === WifiSecurityType.Owe)
                    return true
                if (sec === 9 || sec === 10) return true
            } catch (e) {}
            return false
        }

        function signalBars(strength01) {
            var s = Number(strength01)
            if (isNaN(s)) return "·"
            var pct = s <= 1.01 ? s * 100 : s
            if (pct >= 75) return "▂▄▆█"
            if (pct >= 50) return "▂▄▆_"
            if (pct >= 25) return "▂▄__"
            if (pct > 0) return "▂___"
            return "____"
        }

        function setWifiEnabled(on) {
            var turningOn = !!on && !wifiEnabled
            try {
                Networking.wifiEnabled = !!on
            } catch (e) {
                root.runControl(["wifi", on ? "on" : "off"])
            }
            deviceEpoch++
            root.refreshStatusSoon()
            // First enable → wait for radio, then scan for APs
            if (turningOn)
                root.scheduleWifiScanAfterEnable()
        }

        function toggleWifi() {
            setWifiEnabled(!wifiEnabled)
        }

        function setNetworking(on) {
            root.runControl(["networking", on ? "on" : "off"])
        }

        function toggleNetworking() {
            root.runControl(["networking", "toggle"])
        }

        function setScanner(on) {
            try {
                var vals = (Networking.devices && Networking.devices.values)
                    ? Networking.devices.values : []
                for (var i = 0; i < vals.length; i++) {
                    var d = vals[i]
                    if (!d || !isWifiDevice(d)) continue
                    try { d.scannerEnabled = !!on } catch (e1) {}
                }
            } catch (e) {}
            deviceEpoch++
        }

        function rescanWifi() {
            setScanner(false)
            Qt.callLater(function() { setScanner(true) })
            deviceEpoch++
        }

        function disconnectDevice(iface) {
            var d = findDevice(iface)
            if (d) {
                try { d.disconnect(); deviceEpoch++; root.refreshStatusSoon(); return } catch (e) {}
            }
            root.runControl(["device", "disconnect", iface])
        }

        function enableDevice(iface) {
            var d = findDevice(iface)
            if (d && isWifiDevice(d) && !wifiEnabled)
                setWifiEnabled(true)
            root.runControl(["device", "connect", iface])
            deviceEpoch++
            root.refreshStatusSoon()
        }

        function setAdapterEnabled(iface, on) {
            var d = findDevice(iface)
            if (d && isWifiDevice(d)) {
                setWifiEnabled(!!on)
                if (on)
                    enableDevice(iface)
                return
            }
            if (on)
                enableDevice(iface)
            else
                disconnectDevice(iface)
        }

        function disableAllAdapters() {
            var ifaces = deviceIfaces || []
            for (var i = 0; i < ifaces.length; i++)
                disconnectDevice(ifaces[i])
            if (wifiEnabled)
                setWifiEnabled(false)
            root.flashStatus("All adapters off")
        }

        function setAutoconnect(iface, on) {
            var d = findDevice(iface)
            if (!d) return
            try { d.autoconnect = !!on } catch (e) {}
            deviceEpoch++
        }

        function connectNetwork(ssid, psk) {
            var n = findWifiNetwork(ssid)
            if (!n) {
                root.flashStatus("Network not found: " + ssid)
                return
            }
            try {
                if (root._failBoundNetwork && root._failBoundNetwork !== n) {
                    try { root._failBoundNetwork.connectionFailed.disconnect(root._onConnectionFailed) } catch (eD) {}
                }
                if (root._failBoundNetwork !== n) {
                    n.connectionFailed.connect(root._onConnectionFailed)
                    root._failBoundNetwork = n
                }
            } catch (e0) {}
            try {
                if (psk !== undefined && psk !== null && String(psk).length) {
                    if (n.connectWithPsk) n.connectWithPsk(String(psk))
                    else n.connect()
                } else {
                    n.connect()
                }
                root.flashStatus("Connecting to " + ssid + "…")
                // Keep the AP column open after connect (default two-column view)
            } catch (e) {
                root.flashStatus("Connect failed")
            }
            deviceEpoch++
            root.refreshStatusSoon()
        }

        function forgetNetwork(ssid) {
            var n = findWifiNetwork(ssid)
            if (n) {
                try { n.forget() } catch (e) {}
            }
            if (root.confirmForgetSsid === ssid) root.confirmForgetSsid = ""
            if (root.pskSsid === ssid) root.clearPsk()
            deviceEpoch++
            root.refreshStatusSoon()
        }

        function checkConnectivity() {
            try { Networking.checkConnectivity() } catch (e) {}
            root.refreshStatusSoon()
        }
    }

    function deviceStatus(iface) {
        var data = statusData || {}
        var list = data.devices || []
        for (var i = 0; i < list.length; i++) {
            if (list[i] && list[i].iface === iface)
                return list[i]
        }
        return null
    }

    function flashStatus(msg) {
        statusMessage = msg || ""
        statusClearTimer.restart()
    }

    function scheduleWifiScanAfterEnable() {
        if (wifiScanAfterEnableTimer)
            wifiScanAfterEnableTimer.restart()
    }

    property string _connectionFingerprint: ""

    function updateConnectionModel(data) {
        // ComboBox model only needed while the popup is open
        if (!netPopup.visible) return
        var list = (data && data.connections) ? data.connections : []
        var fpParts = []
        var model = []
        var activeIdx = -1
        for (var i = 0; i < list.length; i++) {
            var c = list[i]
            if (!c) continue
            var active = !!c.active
            var uuid = c.uuid || ""
            fpParts.push(uuid + (active ? ":1" : ":0"))
            model.push({
                text: (active ? "● " : "○ ") + (c.name || uuid || "Connection"),
                uuid: uuid,
                name: c.name || "",
                type: c.type || "",
                device: c.device || "",
                active: active
            })
            if (active && activeIdx < 0)
                activeIdx = i
        }
        var fp = fpParts.join("|")
        if (fp === _connectionFingerprint && model.length === connectionModel.length)
            return
        _connectionFingerprint = fp
        _suppressConnectionActivate = true
        connectionModel = model
        connectionIndex = model.length ? (activeIdx >= 0 ? activeIdx : 0) : -1
        Qt.callLater(function() { root._suppressConnectionActivate = false })
    }

    function activateConnectionAt(index) {
        if (_suppressConnectionActivate) return
        if (index < 0 || index >= connectionModel.length) return
        var c = connectionModel[index]
        if (!c || !c.uuid) return
        if (c.active) {
            flashStatus("Already active: " + c.name)
            return
        }
        runControl(["connection", "up", c.uuid])
        flashStatus("Activating " + c.name + "…")
    }

    function selectedConnectionUuid() {
        if (connectionIndex < 0 || connectionIndex >= connectionModel.length) return ""
        return connectionModel[connectionIndex].uuid || ""
    }

    function copyToClipboard(text) {
        var t = String(text || "")
        if (!t.length || t === "—") return
        Quickshell.execDetached([
            "sh", "-c",
            'printf "%s" "$1" | wl-copy',
            "wl-copy",
            t
        ])
        flashStatus("Copied: " + (t.length > 48 ? t.substring(0, 48) + "…" : t))
    }

    function formatRate(bytesPerSec) {
        var b = Number(bytesPerSec) || 0
        if (b < 0) b = 0
        if (b >= 1048576) return (b / 1048576).toFixed(1) + " MB/s"
        if (b >= 1024) return (b / 1024).toFixed(1) + " KB/s"
        return Math.round(b) + " B/s"
    }

    function pushRateSample(rx, tx) {
        // Graph history only while the popup is open and traffic graph is enabled
        lastRxRate = Number(rx) || 0
        lastTxRate = Number(tx) || 0
        if (!netPopup.visible || !root._showTrafficGraph)
            return
        var rh = rxHistory.slice()
        var th = txHistory.slice()
        rh.push(lastRxRate)
        th.push(lastTxRate)
        while (rh.length > rateHistoryMax) rh.shift()
        while (th.length > rateHistoryMax) th.shift()
        rxHistory = rh
        txHistory = th
    }

    function clearRateHistory() {
        rxHistory = []
        txHistory = []
        lastRxRate = 0
        lastTxRate = 0
    }

    function refreshIp(iface) {
        var arg = iface || detailIface || ""
        if (arg.length)
            runControl(["refresh-ip", arg])
        else
            runControl(["refresh-ip"])
        flashStatus("Refreshing IP…")
        refreshStatusSoon()
    }

    function refreshDns(iface) {
        var arg = iface || detailIface || ""
        if (arg.length)
            runControl(["refresh-dns", arg])
        else
            runControl(["refresh-dns"])
        flashStatus("Refreshing DNS…")
        refreshStatusSoon()
    }

    function clearPsk() {
        pskSsid = ""
        pskDraft = ""
        pskFocusGrab.active = false
    }

    function beginPsk(ssid) {
        pskSsid = ssid
        pskDraft = ""
        pskFocusGrab.active = true
        Qt.callLater(function() {
            if (pskField) pskField.forceActiveFocus()
        })
    }

    function _onConnectionFailed(reason) {
        var noSecrets = false
        try {
            noSecrets = (reason === ConnectionFailReason.NoSecrets || reason === 1)
        } catch (e) {
            noSecrets = (reason === 1)
        }
        if (noSecrets && pskSsid.length === 0) {
            // Best-effort: if we were connecting, show generic prompt via detail
            flashStatus("Password required")
        } else if (noSecrets) {
            flashStatus("Wrong or missing password")
        } else {
            var label = String(reason)
            try {
                if (typeof ConnectionFailReason !== "undefined" && ConnectionFailReason.toString)
                    label = ConnectionFailReason.toString(reason)
            } catch (e2) {}
            flashStatus("Connection failed: " + label)
        }
        net.deviceEpoch++
        refreshStatusSoon()
    }

    // =========================================================================
    // network-control.sh integration
    // =========================================================================
    function runControl(args) {
        var cmd = [controlScript].concat(args)
        if (controlProcess.running)
            controlProcess.running = false
        controlProcess.command = cmd
        controlProcess.running = true
    }

    function refreshStatus(force) {
        // Skip overlapping polls — avoids thrashing nmcli when a slow status is in flight
        if (statusProcess.running) {
            if (force)
                statusProcess.running = false
            else
                return
        }
        statusProcess.command = [controlScript, "status"]
        statusProcess.running = true
    }

    function refreshStatusSoon() {
        statusSoonTimer.restart()
    }

    function refreshAppletStatus() {
        if (appletCheckProcess.running)
            appletCheckProcess.running = false
        appletCheckProcess.command = [controlScript, "applet", "status"]
        appletCheckProcess.running = true
    }

    function startApplet() {
        // Session-only start (does not re-enable login autostart if sticky-disabled)
        runControl(["applet", "start"])
        appletRefreshTimer.restart()
    }

    function stopApplet() {
        // Session-only stop (does not change login autostart)
        runControl(["applet", "stop"])
        appletRefreshTimer.restart()
    }

    function toggleApplet() {
        if (appletRunning) stopApplet()
        else startApplet()
    }

    // Sticky (survives reboot): XDG autostart mask + systemctl enable/disable
    function enableApplet() {
        runControl(["applet", "enable"])
        appletRefreshTimer.restart()
        flashStatus("nm-applet enabled (starts at login)")
    }

    function disableApplet() {
        runControl(["applet", "disable"])
        appletRefreshTimer.restart()
        flashStatus("nm-applet disabled (stays off after reboot)")
    }

    function setAppletAutostart(enabled) {
        runControl(["applet", "set-autostart", enabled ? "true" : "false"])
        appletRefreshTimer.restart()
        flashStatus(enabled
                    ? "nm-applet enabled (starts at login)"
                    : "nm-applet disabled (stays off after reboot)")
    }

    function openEditor(uuidOrName) {
        if (uuidOrName && String(uuidOrName).length)
            Quickshell.execDetached(["nm-connection-editor", "--edit", String(uuidOrName)])
        else
            Quickshell.execDetached(["nm-connection-editor"])
    }

    Io.Process {
        id: statusProcess
        running: false
        stdout: Io.StdioCollector { id: statusStdout }
        onExited: (code) => {
            if (code !== 0) return
            var t = (statusStdout.text || "").trim()
            if (!t.length) return
            try {
                var data = JSON.parse(t)
                root.statusData = data
                if (data.applet_running !== undefined)
                    root.appletRunning = !!data.applet_running
                if (data.applet_enabled !== undefined)
                    root.appletAutostartEnabled = !!data.applet_enabled
                else if (data.autostart_enabled !== undefined)
                    root.appletAutostartEnabled = !!data.autostart_enabled
                root.updateConnectionModel(data)
                if (data.rx_rate !== undefined || data.tx_rate !== undefined)
                    root.pushRateSample(data.rx_rate, data.tx_rate)
                root.statusEpoch++
            } catch (e) {}
        }
    }

    Io.Process {
        id: controlProcess
        running: false
        stdout: Io.StdioCollector { id: controlStdout }
        onExited: (code) => {
            root.refreshStatusSoon()
            net.deviceEpoch++
            if (code !== 0) {
                var t = (controlStdout.text || "").trim()
                try {
                    var j = JSON.parse(t)
                    if (j && j.error) root.flashStatus(j.error)
                } catch (e) {
                    if (t.length) root.flashStatus(t)
                }
            }
        }
    }

    Io.Process {
        id: appletCheckProcess
        running: false
        stdout: Io.StdioCollector { id: appletStdout }
        onExited: (code) => {
            var t = (appletStdout.text || "").trim()
            try {
                var j = JSON.parse(t)
                if (j && j.running !== undefined)
                    root.appletRunning = !!j.running
                if (j && j.autostart_enabled !== undefined)
                    root.appletAutostartEnabled = !!j.autostart_enabled
                else if (j && j.enabled !== undefined)
                    root.appletAutostartEnabled = !!j.enabled
            } catch (e) {
                root.appletRunning = (code === 0)
            }
        }
    }

    Timer {
        id: statusPollTimer
        // Slow when closed (bar glyph/IP only); ~1.5s when open for graph + lists
        interval: netPopup.visible ? 1500 : 12000
        repeat: true
        running: true
        onTriggered: root.refreshStatus()
        onIntervalChanged: {
            if (running) {
                stop()
                start()
            }
        }
    }

    Timer {
        id: wifiScanAfterEnableTimer
        interval: 900
        repeat: false
        onTriggered: {
            if (!net.wifiEnabled) return
            // Ensure scanner is on and force a rescan after radio comes up
            net.setScanner(true)
            net.rescanWifi()
            root.flashStatus("Scanning for WiFi…")
            net.deviceEpoch++
        }
    }

    Timer {
        id: statusSoonTimer
        interval: 450
        repeat: false
        onTriggered: root.refreshStatus()
    }

    Timer {
        id: statusClearTimer
        interval: 4000
        repeat: false
        onTriggered: root.statusMessage = ""
    }

    // Sparse epoch bump while open so weak NM notifies still refresh lists
    Timer {
        id: deviceRefreshTimer
        interval: 3000
        repeat: true
        running: netPopup.visible
        onTriggered: net.deviceEpoch++
    }

    // Applet status comes from status JSON; only recheck after start/stop/enable/disable
    Timer {
        id: appletRefreshTimer
        interval: 600
        repeat: false
        onTriggered: root.refreshAppletStatus()
    }

    Component.onCompleted: {
        refreshStatus()
    }

    // =========================================================================
    // Pill content (chip highlights; outer pill border stays stable)
    // =========================================================================
    Rectangle {
        id: netChip
        anchors.centerIn: parent
        width: Math.max(18, netContent.implicitWidth + (embedded ? 4 : 10))
        height: embedded ? parent.height : Math.max(18, parent.height - (bar.pillChipInset !== undefined ? bar.pillChipInset : 4))
        radius: bar.workspaceRadius
        color: {
            if (embedded)
                return "transparent"
            return root.netHovered ? bar.iconHoverBg : "transparent"
        }
        border.width: (!embedded && root.netHovered) ? bar.controlBorderWidth : 0
        border.color: (!embedded && root.netHovered) ? bar.accent : "transparent"

        Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }
        Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }

        Item {
            id: netContent
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: embedded ? 0 : (bar.pillFaceTopPad !== undefined ? bar.pillFaceTopPad : 3)
            implicitWidth: pillRow.implicitWidth
            implicitHeight: pillRow.implicitHeight
            width: implicitWidth
            height: implicitHeight
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
                        text: net.pillGlyph
                        font.pixelSize: Math.max(12, Math.round(bar.iconSizeTray * root._s))
                        font.family: bar.fontFamily
                        color: net.pillGlyphColor
                    }
                }

                Text {
                    visible: {
                        void (bar ? bar.showNetworkDeviceName : false)
                        void (bar ? bar.showNetworkFullIp : false)
                        void (bar ? bar.showNetworkLastOctet : true)
                        if (!net.anyConnected)
                            return false
                        if (bar && bar.showNetworkDeviceName && net.primaryIface.length)
                            return true
                        if (bar && bar.showNetworkFullIp && net.primaryIp.length)
                            return true
                        if (bar && bar.showNetworkLastOctet !== false && net.primaryIp.length)
                            return true
                        return false
                    }
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        void (bar ? bar.showNetworkFullIp : false)
                        void (bar ? bar.showNetworkLastOctet : true)
                        void (bar ? bar.showNetworkDeviceName : false)
                        var ip = net.primaryIp
                        var slash = ip.indexOf("/")
                        if (slash > 0) ip = ip.substring(0, slash)
                        var ipText = ""
                        if (bar && bar.showNetworkFullIp)
                            ipText = ip
                        else if (bar && bar.showNetworkLastOctet !== false) {
                            var parts = ip.split(".")
                            if (parts.length === 4) ipText = parts[3]
                        }
                        var nameText = (bar && bar.showNetworkDeviceName) ? String(net.primaryIface || "") : ""
                        if (nameText.length && ipText.length)
                            return nameText + " " + ipText
                        if (nameText.length)
                            return nameText
                        return ipText
                    }
                    // Bar widget text (Themes → Fonts → Bar widget text)
                    color: bar
                           ? ((bar.barText !== undefined) ? bar.barText : bar.text)
                           : "#e6edf7"
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
        id: netMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton

        BarToolTip {
            bar: root.bar
            widgetId: "network"
            visible: netMouse.containsMouse && !netPopup.visible
            anchorItem: netMouse
            text: {
                if (!net.networkingEnabled)
                    return "Networking off · left-click for menu"
                var bits = []
                if (net.primaryLabel.length) bits.push(net.primaryLabel)
                if (net.primaryIface.length && net.primaryIface !== net.primaryLabel)
                    bits.push(net.primaryIface)
                if (net.primaryIp.length) bits.push(net.primaryIp)
                bits.push("connectivity: " + net.connectivity)
                bits.push("left-click menu")
                return bits.join(" · ")
            }
        }

        onClicked: {
            if (netPopup.visible)
                closePopup()
            else
                showPopup()
        }
    }

    HyprlandFocusGrab {
        id: pskFocusGrab
        windows: [netPopup, bar]
        onCleared: {}
    }

    // =========================================================================
    // Popup
    // =========================================================================
    PopupWindow {
        id: netPopup
        anchor.window: bar
        // Grows to the right when the WiFi AP column is open
        implicitWidth: root.networkPopupWidth
        implicitHeight: bar.popupNetworkHeight || 580
        visible: false
        color: "transparent"
        grabFocus: false

        Shortcut {
            sequences: ["Escape"]
            enabled: netPopup.visible
            context: Qt.ApplicationShortcut
            onActivated: {
                if (root.pskSsid.length)
                    root.clearPsk()
                else
                    root.closePopup()
            }
        }

        // Keep on-screen when the second column opens/closes
        onImplicitWidthChanged: {
            if (visible)
                root.repositionPopup()
        }

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
                spacing: 8

                // ---- Header (title + back only; power toggles live at bottom) ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: root.detailIface.length ? "Connection info" : "Network"
                        color: bar.text
                        font.pixelSize: bar.popupTitleSize
                        font.bold: true
                        font.family: bar.fontFamily
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        visible: root.detailIface.length > 0
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
                            onClicked: root.detailIface = ""
                        }
                    }

                    Rectangle {
                        width: 26
                        height: 26
                        radius: bar.buttonRadius
                        color: netCloseMa.containsMouse
                               ? Qt.rgba(1, 0.24, 0.54, 0.22)
                               : bar.surface
                        border.width: 1
                        border.color: netCloseMa.containsMouse ? "#FF3D8A" : bar.dividerStrong
                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: netCloseMa.containsMouse ? "#FF3D8A" : bar.subtext
                            font.pixelSize: 12
                            font.bold: true
                            font.family: bar.fontFamily
                        }
                        MouseArea {
                            id: netCloseMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.closePopup()
                        }
                    }
                }

                // Connectivity (IP / DNS live at the bottom)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        Layout.fillWidth: true
                        text: {
                            var c = net.connectivity
                            var bits = ["Connectivity: " + c]
                            if (!net.wifiHardwareEnabled) bits.push("WiFi HW blocked")
                            else if (!net.wifiEnabled) bits.push("WiFi radio off")
                            return bits.join(" · ")
                        }
                        color: bar.subtext
                        font.pixelSize: 11
                        font.family: bar.fontFamily
                        elide: Text.ElideRight

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            BarToolTip {
                            bar: root.bar
                            preferSide: "above"
                            visible: parent.containsMouse
                            text: "Re-check connectivity"
                            anchorItem: parent
                        }
                            onClicked: net.checkConnectivity()
                        }
                    }
                }

                // Traffic graph (downstream + upstream) — Options → Network → Traffic graph
                Rectangle {
                    visible: root._showTrafficGraph
                    Layout.fillWidth: true
                    Layout.preferredHeight: root._showTrafficGraph ? 72 : 0
                    radius: bar.buttonRadius
                    color: bar.surface
                    border.width: bar.controlBorderWidth
                    border.color: bar.dividerStrong

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                text: "↓ " + root.formatRate(root.lastRxRate)
                                color: "#00F0E0"
                                font.pixelSize: 11
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            Text {
                                text: "↑ " + root.formatRate(root.lastTxRate)
                                color: "#2ee59a"
                                font.pixelSize: 11
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: "Traffic"
                                color: bar.muted
                                font.pixelSize: 10
                                font.family: bar.fontFamily
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            // Shared Y scale so up/down are comparable
                            readonly property real rateMax: {
                                var m = 1024 // floor 1 KB/s so idle graphs aren't flat-noise
                                var i
                                for (i = 0; i < root.rxHistory.length; i++)
                                    m = Math.max(m, Number(root.rxHistory[i]) || 0)
                                for (i = 0; i < root.txHistory.length; i++)
                                    m = Math.max(m, Number(root.txHistory[i]) || 0)
                                return m
                            }

                            Sparkline {
                                id: rxSpark
                                anchors.fill: parent
                                history: root.rxHistory
                                maxPoints: root.rateHistoryMax
                                fixedRange: true
                                minValue: 0
                                maxValue: parent.rateMax
                                leftPadding: 0
                                lineColor: "#00F0E0"
                                fillColor: Qt.rgba(0.53, 0.71, 0.98, 0.20)
                                lineWidth: 1.5
                            }

                            Sparkline {
                                id: txSpark
                                anchors.fill: parent
                                history: root.txHistory
                                maxPoints: root.rateHistoryMax
                                fixedRange: true
                                minValue: 0
                                maxValue: parent.rateMax
                                leftPadding: 0
                                lineColor: "#2ee59a"
                                fillColor: Qt.rgba(0.65, 0.89, 0.63, 0.12)
                                lineWidth: 1.5
                            }
                        }
                    }
                }

                // ---- Detail panel ----
                Flickable {
                    id: detailFlick
                    visible: root.detailIface.length > 0
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
                                void root.statusEpoch
                                void net.deviceEpoch
                                var iface = root.detailIface
                                if (!iface.length) return []
                                var dev = net.findDevice(iface)
                                var st = root.deviceStatus(iface) || {}
                                var rows = []
                                rows.push({ k: "Interface", v: iface })
                                rows.push({ k: "Type", v: net.deviceTypeLabel(dev) })
                                rows.push({ k: "State", v: st.state || net.stateLabel(dev) })
                                rows.push({ k: "Connection", v: st.connection || "—" })
                                rows.push({ k: "UUID", v: st.uuid || "—" })
                                rows.push({ k: "MAC", v: (st.mac || (dev ? dev.address : "")) || "—" })
                                if (dev && net.isWiredDevice(dev)) {
                                    try {
                                        rows.push({ k: "Cable", v: dev.hasLink ? "Plugged in" : "Unplugged" })
                                        rows.push({ k: "Link speed", v: (dev.linkSpeed > 0)
                                            ? (dev.linkSpeed + " Mb/s")
                                            : (st.speed_mbps > 0 ? st.speed_mbps + " Mb/s" : "—") })
                                    } catch (e) {
                                        if (st.speed_mbps > 0)
                                            rows.push({ k: "Link speed", v: st.speed_mbps + " Mb/s" })
                                    }
                                }
                                try {
                                    if (dev)
                                        rows.push({ k: "Autoconnect", v: dev.autoconnect ? "Yes" : "No" })
                                } catch (e2) {}
                                if (st.ip4 && st.ip4.length)
                                    rows.push({ k: "IPv4", v: st.ip4.join(", ") })
                                if (st.gateway4)
                                    rows.push({ k: "Gateway", v: st.gateway4 })
                                if (st.ip6 && st.ip6.length)
                                    rows.push({ k: "IPv6", v: st.ip6.join(", ") })
                                if (st.gateway6)
                                    rows.push({ k: "Gateway v6", v: st.gateway6 })
                                if (st.dns && st.dns.length)
                                    rows.push({ k: "DNS", v: st.dns.join(", ") })
                                if (st.routes4 && st.routes4.length) {
                                    for (var r = 0; r < Math.min(st.routes4.length, 6); r++)
                                        rows.push({ k: r === 0 ? "Routes" : "", v: st.routes4[r] })
                                }
                                // WiFi extras
                                if (dev && net.isWifiDevice(dev)) {
                                    try {
                                        var nets = (dev.networks && dev.networks.values) ? dev.networks.values : []
                                        for (var i = 0; i < nets.length; i++) {
                                            if (nets[i] && nets[i].connected) {
                                                rows.push({ k: "SSID", v: nets[i].name || "—" })
                                                rows.push({ k: "Security", v: net.securityLabel(nets[i].security) })
                                                var sig = Number(nets[i].signalStrength)
                                                if (!isNaN(sig))
                                                    rows.push({ k: "Signal", v: Math.round((sig <= 1.01 ? sig * 100 : sig)) + "%" })
                                                rows.push({ k: "Known", v: nets[i].known ? "Yes" : "No" })
                                                break
                                            }
                                        }
                                    } catch (e3) {}
                                }
                                return rows
                            }
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                height: Math.max(detailRow.implicitHeight + 6, 24)
                                radius: 4
                                color: detailRowMa.containsMouse ? bar.popupButtonHoverBg : "transparent"

                                RowLayout {
                                    id: detailRow
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 8
                                    Text {
                                        text: modelData.k
                                        color: bar.muted
                                        font.pixelSize: 11
                                        font.family: bar.fontFamily
                                        Layout.preferredWidth: 88
                                    }
                                    Text {
                                        text: modelData.v
                                        color: detailRowMa.containsMouse ? bar.accent : bar.text
                                        font.pixelSize: 11
                                        font.family: bar.fontFamily
                                        Layout.fillWidth: true
                                        wrapMode: Text.WrapAnywhere
                                    }
                                    Text {
                                        visible: detailRowMa.containsMouse && modelData.v && modelData.v !== "—"
                                        text: "⧉"
                                        color: bar.muted
                                        font.pixelSize: 11
                                        font.family: bar.fontFamily
                                    }
                                }
                                MouseArea {
                                    id: detailRowMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    BarToolTip {
                                        bar: root.bar
                                        preferSide: "above"
                                        visible: detailRowMa.containsMouse && modelData.v && modelData.v !== "—"
                                        text: "Click to copy"
                                        anchorItem: detailRowMa
                                    }
                                    onClicked: root.copyToClipboard(modelData.v)
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Click any value to copy"
                            color: bar.muted
                            font.pixelSize: 10
                            font.family: bar.fontFamily
                        }

                        // Detail actions
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Rectangle {
                                visible: {
                                    var d = net.findDevice(root.detailIface)
                                    return !!(d && d.connected)
                                }
                                width: discLbl.implicitWidth + 14
                                height: 28
                                radius: bar.buttonRadius
                                color: discMa.containsMouse ? Qt.rgba(0.55, 0.14, 0.14, 0.55) : bar.surface
                                border.width: bar.controlBorderWidth
                                border.color: bar.dividerStrong
                                Text {
                                    id: discLbl
                                    anchors.centerIn: parent
                                    text: "Disconnect"
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
                                    onClicked: {
                                        net.disconnectDevice(root.detailIface)
                                        root.flashStatus("Disconnecting " + root.detailIface)
                                    }
                                }
                            }

                            Rectangle {
                                visible: {
                                    var d = net.findDevice(root.detailIface)
                                    return !(d && d.connected)
                                }
                                width: enLbl.implicitWidth + 14
                                height: 28
                                radius: bar.buttonRadius
                                color: enMa.containsMouse ? bar.accent : bar.surface
                                border.width: bar.controlBorderWidth
                                border.color: bar.dividerStrong
                                Text {
                                    id: enLbl
                                    anchors.centerIn: parent
                                    text: "Enable"
                                    color: enMa.containsMouse ? bar.bg : bar.text
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                MouseArea {
                                    id: enMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        net.enableDevice(root.detailIface)
                                        root.flashStatus("Enabling " + root.detailIface)
                                    }
                                }
                            }

                            Rectangle {
                                width: editLbl.implicitWidth + 14
                                height: 28
                                radius: bar.buttonRadius
                                color: editMa.containsMouse ? bar.popupButtonHoverBg : bar.surface
                                border.width: bar.controlBorderWidth
                                border.color: bar.dividerStrong
                                Text {
                                    id: editLbl
                                    anchors.centerIn: parent
                                    text: "Edit connection…"
                                    color: bar.text
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                MouseArea {
                                    id: editMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var st = root.deviceStatus(root.detailIface) || {}
                                        root.openEditor(st.uuid || st.connection || "")
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Rectangle {
                                width: dipLbl.implicitWidth + 14
                                height: 26
                                radius: bar.buttonRadius
                                color: dipMa.containsMouse ? bar.popupButtonHoverBg : bar.surface
                                border.width: bar.controlBorderWidth
                                border.color: bar.dividerStrong
                                Text {
                                    id: dipLbl
                                    anchors.centerIn: parent
                                    text: "↻ Refresh IP"
                                    color: bar.text
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                MouseArea {
                                    id: dipMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.refreshIp(root.detailIface)
                                }
                            }
                            Rectangle {
                                width: ddnsLbl.implicitWidth + 14
                                height: 26
                                radius: bar.buttonRadius
                                color: ddnsMa.containsMouse ? bar.popupButtonHoverBg : bar.surface
                                border.width: bar.controlBorderWidth
                                border.color: bar.dividerStrong
                                Text {
                                    id: ddnsLbl
                                    anchors.centerIn: parent
                                    text: "↻ Refresh DNS"
                                    color: bar.text
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                MouseArea {
                                    id: ddnsMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.refreshDns(root.detailIface)
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }

                        // Reconnect if we have a UUID
                        Rectangle {
                            visible: {
                                var st = root.deviceStatus(root.detailIface) || {}
                                return !!(st.uuid || st.connection)
                            }
                            Layout.fillWidth: true
                            height: 28
                            radius: bar.buttonRadius
                            color: reconMa.containsMouse ? bar.accent : bar.surface
                            border.width: bar.controlBorderWidth
                            border.color: bar.dividerStrong
                            Text {
                                anchors.centerIn: parent
                                text: "Activate connection"
                                color: reconMa.containsMouse ? bar.bg : bar.text
                                font.pixelSize: 11
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            MouseArea {
                                id: reconMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var st = root.deviceStatus(root.detailIface) || {}
                                    var id = st.uuid || st.connection
                                    if (id) root.runControl(["connection", "up", id])
                                }
                            }
                        }
                    }
                }

                // ---- Main body: left Adapters | right WiFi (always two columns) ----
                RowLayout {
                    id: mainBody
                    visible: root.detailIface.length === 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: root.networkPopupGap

                    Flickable {
                        id: mainFlick
                        Layout.preferredWidth: root.networkMainWidth - 2 * (bar.popupSpacing || 12)
                        Layout.fillHeight: true
                        contentWidth: width
                        contentHeight: mainCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        ColumnLayout {
                            id: mainCol
                            width: mainFlick.width
                            spacing: 10

                            // Adapters section
                            Text {
                                text: "Adapters"
                                color: bar.subtext
                                font.pixelSize: bar.popupSectionSize || 13
                                font.bold: true
                                font.family: bar.fontFamily
                            }

                        Repeater {
                            model: net.deviceIfaces
                            delegate: Rectangle {
                                required property string modelData
                                readonly property string iface: modelData
                                readonly property var dev: net.findDevice(iface)
                                readonly property var st: root.deviceStatus(iface)
                                Layout.fillWidth: true
                                // Size to content (top-aligned); include padding so buttons clear the border
                                readonly property int cardPad: 10
                                implicitHeight: adapterCol.implicitHeight + 2 * cardPad
                                height: implicitHeight
                                radius: bar.buttonRadius
                                color: adapterMa.containsMouse ? bar.popupButtonHoverBg : bar.surface
                                border.width: bar.controlBorderWidth
                                border.color: (dev && dev.connected) ? bar.accent : bar.dividerStrong
                                clip: false

                                ColumnLayout {
                                    id: adapterCol
                                    // Top-align so height grows cleanly with button rows
                                    x: parent.cardPad
                                    y: parent.cardPad
                                    width: parent.width - 2 * parent.cardPad
                                    spacing: 8

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        Text {
                                            text: (dev && dev.connected) ? "●" : "○"
                                            color: (dev && dev.connected) ? "#10B981" : bar.muted
                                            font.pixelSize: 12
                                        }
                                        Text {
                                            text: iface
                                            color: bar.text
                                            font.pixelSize: 12
                                            font.bold: true
                                            font.family: bar.fontFamily
                                        }
                                        Text {
                                            text: net.deviceTypeLabel(dev) + " · " + (st && st.state ? st.state : net.stateLabel(dev))
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            visible: st && st.speed_mbps > 0
                                            text: st ? (st.speed_mbps + " Mb/s") : ""
                                            color: bar.muted
                                            font.pixelSize: 10
                                            font.family: bar.fontFamily
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        visible: !!(st && (st.connection || (st.ip4 && st.ip4.length)))
                                        text: {
                                            var parts = []
                                            if (st && st.connection) parts.push(st.connection)
                                            if (st && st.ip4 && st.ip4.length) parts.push(st.ip4[0])
                                            return parts.join(" · ")
                                        }
                                        color: bar.subtext
                                        font.pixelSize: 11
                                        font.family: bar.fontFamily
                                        elide: Text.ElideRight
                                    }

                                    // Explicit button row height — avoids Flow under-reporting height
                                    // so the card border no longer clips the controls
                                    Flow {
                                        id: adapterBtns
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Math.max(22, adapterBtns.childrenRect.height)
                                        spacing: 6

                                        Rectangle {
                                            visible: !!(dev && dev.connected)
                                            width: dBtn.implicitWidth + 12
                                            height: 22
                                            radius: bar.buttonRadius
                                            color: dBtnMa.containsMouse ? Qt.rgba(0.55, 0.14, 0.14, 0.5) : bar.bg
                                            border.width: 1
                                            border.color: bar.dividerStrong
                                            Text {
                                                id: dBtn
                                                anchors.centerIn: parent
                                                text: "Disconnect"
                                                color: bar.text
                                                font.pixelSize: 10
                                                font.bold: true
                                                font.family: bar.fontFamily
                                            }
                                            MouseArea {
                                                id: dBtnMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: net.disconnectDevice(iface)
                                            }
                                        }

                                        Rectangle {
                                            visible: !(dev && dev.connected)
                                            width: aBtn.implicitWidth + 12
                                            height: 22
                                            radius: bar.buttonRadius
                                            color: aBtnMa.containsMouse ? bar.accent : bar.bg
                                            border.width: 1
                                            border.color: bar.dividerStrong
                                            Text {
                                                id: aBtn
                                                anchors.centerIn: parent
                                                text: "Enable"
                                                color: aBtnMa.containsMouse ? bar.bg : bar.text
                                                font.pixelSize: 10
                                                font.bold: true
                                                font.family: bar.fontFamily
                                            }
                                            MouseArea {
                                                id: aBtnMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                BarToolTip {
                                                    bar: root.bar
                                                    preferSide: "above"
                                                    visible: aBtnMa.containsMouse
                                                    text: "Bring this adapter up (undo disconnect)"
                                                    anchorItem: aBtnMa
                                                }
                                                onClicked: net.enableDevice(iface)
                                            }
                                        }

                                        Rectangle {
                                            visible: !!(dev && net.isWifiDevice(dev))
                                            width: wifiAdpLbl.implicitWidth + 12
                                            height: 22
                                            radius: bar.buttonRadius
                                            color: wifiAdpMa.containsMouse
                                                   ? (net.wifiEnabled ? Qt.rgba(0.55, 0.14, 0.14, 0.5) : bar.accent)
                                                   : bar.bg
                                            border.width: 1
                                            border.color: net.wifiEnabled ? bar.accent : bar.dividerStrong
                                            opacity: net.wifiHardwareEnabled ? 1.0 : 0.45
                                            Text {
                                                id: wifiAdpLbl
                                                anchors.centerIn: parent
                                                text: net.wifiEnabled ? "WiFi on" : "WiFi off"
                                                color: wifiAdpMa.containsMouse && !net.wifiEnabled ? bar.bg : bar.text
                                                font.pixelSize: 10
                                                font.bold: true
                                                font.family: bar.fontFamily
                                            }
                                            MouseArea {
                                                id: wifiAdpMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                enabled: net.wifiHardwareEnabled
                                                BarToolTip {
                                                    bar: root.bar
                                                    preferSide: "above"
                                                    visible: wifiAdpMa.containsMouse
                                                    text: net.wifiHardwareEnabled
                                                          ? (net.wifiEnabled ? "Disable WiFi radio" : "Enable WiFi radio")
                                                          : "WiFi hardware blocked (rfkill)"
                                                    anchorItem: wifiAdpMa
                                                }
                                                onClicked: net.toggleWifi()
                                            }
                                        }

                                        Rectangle {
                                            visible: !!(dev && net.isWiredDevice(dev))
                                            width: wiredAdpLbl.implicitWidth + 12
                                            height: 22
                                            radius: bar.buttonRadius
                                            color: wiredAdpMa.containsMouse
                                                   ? ((dev && dev.connected) ? Qt.rgba(0.55, 0.14, 0.14, 0.5) : bar.accent)
                                                   : bar.bg
                                            border.width: 1
                                            border.color: (dev && dev.connected) ? bar.accent : bar.dividerStrong
                                            Text {
                                                id: wiredAdpLbl
                                                anchors.centerIn: parent
                                                text: (dev && dev.connected) ? "Wired on" : "Wired off"
                                                color: wiredAdpMa.containsMouse && !(dev && dev.connected) ? bar.bg : bar.text
                                                font.pixelSize: 10
                                                font.bold: true
                                                font.family: bar.fontFamily
                                            }
                                            MouseArea {
                                                id: wiredAdpMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                BarToolTip {
                                                    bar: root.bar
                                                    preferSide: "above"
                                                    visible: wiredAdpMa.containsMouse
                                                    text: (dev && dev.connected)
                                                          ? "Turn this wired adapter off"
                                                          : "Turn this wired adapter on"
                                                    anchorItem: wiredAdpMa
                                                }
                                                onClicked: net.setAdapterEnabled(iface, !(dev && dev.connected))
                                            }
                                        }

                                        Rectangle {
                                            width: detBtn.implicitWidth + 12
                                            height: 22
                                            radius: bar.buttonRadius
                                            color: detBtnMa.containsMouse ? bar.popupButtonHoverBg : bar.bg
                                            border.width: 1
                                            border.color: bar.dividerStrong
                                            Text {
                                                id: detBtn
                                                anchors.centerIn: parent
                                                text: "Details"
                                                color: bar.text
                                                font.pixelSize: 10
                                                font.bold: true
                                                font.family: bar.fontFamily
                                            }
                                            MouseArea {
                                                id: detBtnMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.detailIface = iface
                                            }
                                        }

                                        Rectangle {
                                            width: editAdpLbl.implicitWidth + 12
                                            height: 22
                                            radius: bar.buttonRadius
                                            color: editAdpMa.containsMouse ? bar.popupButtonHoverBg : bar.bg
                                            border.width: 1
                                            border.color: bar.dividerStrong
                                            Text {
                                                id: editAdpLbl
                                                anchors.centerIn: parent
                                                text: "Edit"
                                                color: bar.text
                                                font.pixelSize: 10
                                                font.bold: true
                                                font.family: bar.fontFamily
                                            }
                                            MouseArea {
                                                id: editAdpMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                BarToolTip {
                            bar: root.bar
                            preferSide: "above"
                            visible: parent.containsMouse
                            text: "Open nm-connection-editor for this connection"
                            anchorItem: parent
                        }
                                                onClicked: {
                                                    var s = st || {}
                                                    root.openEditor(s.uuid || s.connection || "")
                                                }
                                            }
                                        }

                                        // Autoconnect chip
                                        Rectangle {
                                            visible: !!dev
                                            width: acLbl.implicitWidth + 12
                                            height: 22
                                            radius: bar.buttonRadius
                                            color: bar.bg
                                            border.width: 1
                                            border.color: (dev && dev.autoconnect) ? bar.accent : bar.dividerStrong
                                            Text {
                                                id: acLbl
                                                anchors.centerIn: parent
                                                text: (dev && dev.autoconnect) ? "Auto ✓" : "Auto"
                                                color: bar.subtext
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (dev)
                                                        net.setAutoconnect(iface, !dev.autoconnect)
                                                }
                                            }
                                        }
                                    }
                                }

                                MouseArea {
                                    id: adapterMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.NoButton
                                    z: -1
                                }
                            }
                        }

                        // Connections dropdown + editor
                        Text {
                            text: "Connections"
                            color: bar.subtext
                            font.pixelSize: bar.popupSectionSize || 13
                            font.bold: true
                            font.family: bar.fontFamily
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            ComboBox {
                                id: connectionCombo
                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                model: root.connectionModel
                                textRole: "text"
                                currentIndex: root.connectionIndex
                                enabled: root.connectionModel.length > 0
                                font.pixelSize: 11
                                font.family: bar.fontFamily

                                onActivated: (index) => {
                                    root.connectionIndex = index
                                    root.activateConnectionAt(index)
                                }

                                background: Rectangle {
                                    implicitHeight: 30
                                    radius: bar.buttonRadius
                                    color: bar.surface
                                    border.width: bar.controlBorderWidth
                                    border.color: (connectionCombo.hovered || connectionCombo.pressed)
                                                  ? bar.accent : bar.dividerStrong
                                }
                                contentItem: Text {
                                    leftPadding: 10
                                    rightPadding: 28
                                    text: connectionCombo.displayText.length
                                          ? connectionCombo.displayText
                                          : (root.connectionModel.length ? "Select connection" : "No connections")
                                    color: bar.text
                                    font.pixelSize: 11
                                    font.family: bar.fontFamily
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }
                                popup: Popup {
                                    y: connectionCombo.height + 2
                                    width: connectionCombo.width
                                    implicitHeight: Math.min(contentItem.implicitHeight + 4, 280)
                                    padding: 4
                                    background: Rectangle {
                                        radius: bar.buttonRadius
                                        color: bar.glassPopupBg
                                        border.width: bar.controlBorderWidth
                                        border.color: bar.glassPopupBorder
                                    }
                                    contentItem: ListView {
                                        clip: true
                                        implicitHeight: contentHeight
                                        model: connectionCombo.popup.visible
                                               ? connectionCombo.delegateModel : null
                                        currentIndex: connectionCombo.highlightedIndex
                                        ScrollIndicator.vertical: ScrollIndicator {}
                                    }
                                }
                                delegate: ItemDelegate {
                                    width: connectionCombo.width
                                    height: 28
                                    highlighted: connectionCombo.highlightedIndex === index
                                    contentItem: Text {
                                        text: modelData.text || modelData
                                        color: bar.text
                                        font.pixelSize: 11
                                        font.family: bar.fontFamily
                                        elide: Text.ElideRight
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        color: parent.highlighted ? bar.popupButtonHoverBg : "transparent"
                                        radius: 4
                                    }
                                }
                            }

                            Rectangle {
                                Layout.preferredHeight: 30
                                width: editorBtnLbl.implicitWidth + 14
                                radius: bar.buttonRadius
                                color: editorMa.containsMouse ? bar.popupButtonHoverBg : bar.surface
                                border.width: bar.controlBorderWidth
                                border.color: bar.dividerStrong
                                Text {
                                    id: editorBtnLbl
                                    anchors.centerIn: parent
                                    text: "Editor"
                                    color: bar.text
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                MouseArea {
                                    id: editorMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    BarToolTip {
                            bar: root.bar
                            preferSide: "above"
                            visible: parent.containsMouse
                            text: "Open nm-connection-editor for the selected connection"
                            anchorItem: parent
                        }
                                    onClicked: {
                                        var uuid = root.selectedConnectionUuid()
                                        root.openEditor(uuid)
                                    }
                                }
                            }
                        }

                        Text {
                            visible: root.connectionModel.length === 0
                            Layout.fillWidth: true
                            text: "No saved connections"
                            color: bar.muted
                            font.pixelSize: 11
                            font.family: bar.fontFamily
                        }

                        Text {
                            visible: root.statusMessage.length > 0
                            Layout.fillWidth: true
                            text: root.statusMessage
                            color: bar.accent
                            font.pixelSize: bar.fontTiny || 10
                            font.family: bar.fontFamily
                            wrapMode: Text.WordWrap
                        }
                        } // mainCol
                    } // mainFlick

                    // Vertical divider between columns
                    Rectangle {
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        color: bar.dividerStrong
                    }

                    // ---- Right column: WiFi only ----
                    ColumnLayout {
                        id: wifiColumn
                        Layout.preferredWidth: root.networkWifiWidth
                        Layout.fillHeight: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text {
                                text: "WiFi"
                                color: bar.subtext
                                font.pixelSize: bar.popupSectionSize || 13
                                font.bold: true
                                font.family: bar.fontFamily
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            Rectangle {
                                visible: net.wifiEnabled
                                width: scanLbl.implicitWidth + 14
                                height: 22
                                radius: bar.buttonRadius
                                color: scanMa.containsMouse ? bar.popupButtonHoverBg : bar.surface
                                border.width: 1
                                border.color: bar.dividerStrong
                                Text {
                                    id: scanLbl
                                    anchors.centerIn: parent
                                    text: "Rescan"
                                    color: bar.text
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                MouseArea {
                                    id: scanMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: net.rescanWifi()
                                }
                            }
                        }

                        Text {
                            visible: !net.wifiEnabled
                            Layout.fillWidth: true
                            text: net.wifiHardwareEnabled
                                  ? "WiFi radio is off — enable it above to scan and connect."
                                  : "WiFi hardware is blocked (rfkill)."
                            color: bar.muted
                            font.pixelSize: 11
                            font.family: bar.fontFamily
                            wrapMode: Text.WordWrap
                        }

                        Text {
                            visible: net.wifiEnabled && net.wifiConnected
                            Layout.fillWidth: true
                            text: net.connectedWifiSsid.length
                                  ? ("Connected to “" + net.connectedWifiSsid + "”")
                                  : "Connected"
                            color: bar.subtext
                            font.pixelSize: 11
                            font.family: bar.fontFamily
                            elide: Text.ElideRight
                        }

                        // PSK prompt (in the WiFi column)
                        Rectangle {
                            visible: root.pskSsid.length > 0 && net.wifiEnabled
                            Layout.fillWidth: true
                            height: pskCol.implicitHeight + 12
                            radius: bar.buttonRadius
                            color: bar.surface
                            border.width: bar.controlBorderWidth
                            border.color: bar.accent

                            ColumnLayout {
                                id: pskCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: 8
                                spacing: 6
                                Text {
                                    text: "Password for \"" + root.pskSsid + "\""
                                    color: bar.text
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.family: bar.fontFamily
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                                TextField {
                                    id: pskField
                                    Layout.fillWidth: true
                                    text: root.pskDraft
                                    echoMode: TextInput.Password
                                    placeholderText: "WiFi password"
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.family: bar.fontFamily
                                    background: Rectangle {
                                        radius: 4
                                        color: bar.bg
                                        border.width: 1
                                        border.color: bar.dividerStrong
                                    }
                                    onTextChanged: root.pskDraft = text
                                    Keys.onReturnPressed: root._submitPsk()
                                    Keys.onEnterPressed: root._submitPsk()
                                    Keys.onEscapePressed: root.clearPsk()
                                }
                                RowLayout {
                                    spacing: 6
                                    Rectangle {
                                        width: goLbl.implicitWidth + 14
                                        height: 24
                                        radius: bar.buttonRadius
                                        color: goMa.containsMouse ? bar.accent : bar.bg
                                        border.width: 1
                                        border.color: bar.dividerStrong
                                        Text {
                                            id: goLbl
                                            anchors.centerIn: parent
                                            text: "Connect"
                                            color: goMa.containsMouse ? bar.bg : bar.text
                                            font.pixelSize: 11
                                            font.bold: true
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: goMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root._submitPsk()
                                        }
                                    }
                                    Rectangle {
                                        width: canLbl.implicitWidth + 14
                                        height: 24
                                        radius: bar.buttonRadius
                                        color: canMa.containsMouse ? bar.popupButtonHoverBg : bar.bg
                                        border.width: 1
                                        border.color: bar.dividerStrong
                                        Text {
                                            id: canLbl
                                            anchors.centerIn: parent
                                            text: "Cancel"
                                            color: bar.text
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: canMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.clearPsk()
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                }
                            }
                        }

                        Text {
                            visible: net.wifiEnabled && net.wifiSsids.length === 0 && root.pskSsid.length === 0
                            Layout.fillWidth: true
                            text: "Scanning for networks…"
                            color: bar.muted
                            font.pixelSize: 11
                            font.family: bar.fontFamily
                        }

                        Flickable {
                            id: wifiFlick
                            visible: net.wifiEnabled
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            contentWidth: width
                            contentHeight: wifiListCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                            ColumnLayout {
                                id: wifiListCol
                                width: wifiFlick.width
                                spacing: 6

                                Repeater {
                                    // SSIDs pre-sorted in net.snapshot (connected → known → signal)
                                    model: net.wifiEnabled ? net.wifiSsids : []
                                    delegate: Rectangle {
                                        required property string modelData
                                        readonly property string ssid: modelData
                                        readonly property var network: net.findWifiNetwork(ssid)
                                        Layout.fillWidth: true
                                        implicitHeight: wifiCol.implicitHeight + 12
                                        height: implicitHeight
                                        radius: bar.buttonRadius
                                        color: wifiRowMa.containsMouse ? bar.popupButtonHoverBg : bar.surface
                                        border.width: (network && network.connected) ? 1 : 0
                                        border.color: bar.accent

                                        ColumnLayout {
                                            id: wifiCol
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.margins: 6
                                            spacing: 6

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 6
                                                Text {
                                                    text: net.signalBars(network ? network.signalStrength : 0)
                                                    color: bar.subtext
                                                    font.pixelSize: 10
                                                    font.family: bar.fontFamily
                                                    Layout.preferredWidth: 36
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    Layout.minimumWidth: 40
                                                    spacing: 1
                                                    Text {
                                                        text: ssid
                                                        color: bar.text
                                                        font.pixelSize: 12
                                                        font.bold: !!(network && network.connected)
                                                        font.family: bar.fontFamily
                                                        Layout.fillWidth: true
                                                        elide: Text.ElideRight
                                                    }
                                                    Text {
                                                        text: {
                                                            var bits = []
                                                            if (network)
                                                                bits.push(net.securityLabel(network.security))
                                                            if (network && network.known) bits.push("saved")
                                                            if (network && network.connected) bits.push("connected")
                                                            return bits.join(" · ")
                                                        }
                                                        color: bar.muted
                                                        font.pixelSize: 10
                                                        font.family: bar.fontFamily
                                                        Layout.fillWidth: true
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }

                                            Flow {
                                                Layout.fillWidth: true
                                                spacing: 6
                                                Rectangle {
                                                    visible: !!(network && network.known)
                                                    width: forgetLbl.implicitWidth + 12
                                                    height: 22
                                                    radius: bar.buttonRadius
                                                    color: forgetMa.containsMouse
                                                           ? Qt.rgba(0.55, 0.14, 0.14, 0.5)
                                                           : bar.bg
                                                    border.width: 1
                                                    border.color: bar.dividerStrong
                                                    Text {
                                                        id: forgetLbl
                                                        anchors.centerIn: parent
                                                        text: root.confirmForgetSsid === ssid ? "Confirm?" : "Forget"
                                                        color: bar.text
                                                        font.pixelSize: 10
                                                        font.family: bar.fontFamily
                                                    }
                                                    MouseArea {
                                                        id: forgetMa
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (root.confirmForgetSsid === ssid)
                                                                net.forgetNetwork(ssid)
                                                            else
                                                                root.confirmForgetSsid = ssid
                                                        }
                                                    }
                                                }
                                                Rectangle {
                                                    width: connLbl.implicitWidth + 12
                                                    height: 22
                                                    radius: bar.buttonRadius
                                                    color: {
                                                        if (network && network.connected)
                                                            return connMa.containsMouse
                                                                   ? Qt.rgba(0.55, 0.14, 0.14, 0.5) : bar.bg
                                                        return connMa.containsMouse ? bar.accent : bar.bg
                                                    }
                                                    border.width: 1
                                                    border.color: bar.dividerStrong
                                                    Text {
                                                        id: connLbl
                                                        anchors.centerIn: parent
                                                        text: (network && network.connected) ? "Disconnect" : "Connect"
                                                        color: (connMa.containsMouse && !(network && network.connected))
                                                               ? bar.bg : bar.text
                                                        font.pixelSize: 10
                                                        font.bold: true
                                                        font.family: bar.fontFamily
                                                    }
                                                    MouseArea {
                                                        id: connMa
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (!network) return
                                                            if (network.connected) {
                                                                try { network.disconnect() } catch (e) {}
                                                                net.setScanner(true)
                                                                net.deviceEpoch++
                                                                root.refreshStatusSoon()
                                                                return
                                                            }
                                                            if (network.known || net.isOpenSecurity(network.security)) {
                                                                net.connectNetwork(ssid)
                                                                return
                                                            }
                                                            if (net.needsPsk(network.security)) {
                                                                root.beginPsk(ssid)
                                                                return
                                                            }
                                                            net.connectNetwork(ssid)
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: wifiRowMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            acceptedButtons: Qt.NoButton
                                            z: -1
                                        }
                                    }
                                }
                            }
                        }
                    } // wifiColumn
                } // mainBody

                // ---- Footer: IP / DNS / all adapters off ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Rectangle {
                        Layout.fillWidth: true
                        height: 26
                        radius: bar.buttonRadius
                        color: ripMa.containsMouse ? bar.popupButtonHoverBg : bar.surface
                        border.width: bar.controlBorderWidth
                        border.color: bar.dividerStrong
                        Text {
                            id: ripLbl
                            anchors.centerIn: parent
                            text: "↻ IP"
                            color: bar.text
                            font.pixelSize: 11
                            font.bold: true
                            font.family: bar.fontFamily
                        }
                        MouseArea {
                            id: ripMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            BarToolTip {
                                bar: root.bar
                                preferSide: "above"
                                visible: ripMa.containsMouse
                                anchorItem: ripMa
                                text: "Reapply / renew IP (nmcli device reapply)"
                            }
                            onClicked: root.refreshIp(root.detailIface)
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 26
                        radius: bar.buttonRadius
                        color: rdnsMa.containsMouse ? bar.popupButtonHoverBg : bar.surface
                        border.width: bar.controlBorderWidth
                        border.color: bar.dividerStrong
                        Text {
                            id: rdnsLbl
                            anchors.centerIn: parent
                            text: "↻ DNS"
                            color: bar.text
                            font.pixelSize: 11
                            font.bold: true
                            font.family: bar.fontFamily
                        }
                        MouseArea {
                            id: rdnsMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            BarToolTip {
                                bar: root.bar
                                preferSide: "above"
                                visible: rdnsMa.containsMouse
                                anchorItem: rdnsMa
                                text: "Flush DNS caches and reapply resolver config"
                            }
                            onClicked: root.refreshDns(root.detailIface)
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 26
                        radius: bar.buttonRadius
                        color: allOffMa.containsMouse ? Qt.rgba(0.55, 0.14, 0.14, 0.55) : bar.surface
                        border.width: bar.controlBorderWidth
                        border.color: bar.dividerStrong
                        Text {
                            anchors.centerIn: parent
                            text: "All off"
                            color: bar.text
                            font.pixelSize: 11
                            font.bold: true
                            font.family: bar.fontFamily
                        }
                        MouseArea {
                            id: allOffMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            BarToolTip {
                                bar: root.bar
                                preferSide: "above"
                                visible: allOffMa.containsMouse
                                anchorItem: allOffMa
                                text: "Disconnect every adapter and turn WiFi radio off"
                            }
                            onClicked: net.disableAllAdapters()
                        }
                    }
                }
            }
        }
    }

    function _submitPsk() {
        if (!pskSsid.length) return
        var p = String(pskDraft || "")
        if (!p.length) {
            flashStatus("Enter a password")
            return
        }
        var ssid = pskSsid
        clearPsk()
        net.connectNetwork(ssid, p)
    }

    function repositionPopup() {
        if (!netPopup.visible && !netPopup.implicitWidth)
            return
        var popupWidth = root.networkPopupWidth
        if (typeof bar.placePopup === "function") {
            bar.placePopup(netPopup, root, popupWidth, netPopup.implicitHeight, 2, root.width / 2)
        } else {
            var pos = root.mapToItem(barBg, root.width / 2, root.height)
            var targetX = bar.sideMargin + pos.x - (popupWidth / 2)
            var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920
            var minX = 12
            var maxX = Math.max(minX, screenW - popupWidth - 12)
            netPopup.anchor.rect.x = Math.max(minX, Math.min(targetX, maxX))
            netPopup.anchor.rect.y = bar.popupAnchorY(netPopup.implicitHeight, 2)
        }
    }

    function showPopup() {
        detailIface = ""
        clearPsk()
        confirmForgetSsid = ""
        _connectionFingerprint = ""   // force connection dropdown rebuild
        netPopup.visible = true
        repositionPopup()
        refreshStatus(true)
        net.deviceEpoch++

        // Always two columns; scan APs when WiFi radio is on
        if (net.wifiEnabled)
            net.setScanner(true)
        else
            net.setScanner(false)
    }

    function closePopup() {
        netPopup.visible = false
        detailIface = ""
        clearPsk()
        confirmForgetSsid = ""
        statusMessage = ""
        net.setScanner(false)
        // Drop fail-handler binding so destroyed NM objects cannot fire into a closed UI
        if (_failBoundNetwork) {
            try { _failBoundNetwork.connectionFailed.disconnect(root._onConnectionFailed) } catch (e) {}
            _failBoundNetwork = null
        }
        // Trim history arrays while closed (rates still update lastRx/lastTx on poll)
        if (rxHistory.length || txHistory.length)
            clearRateHistory()
    }

    // =========================================================================
    // Public API — shell.qml Io.IpcHandler target "networkPill"
    // =========================================================================
    function hidePopup() { closePopup() }

    function togglePopup() {
        if (netPopup.visible) closePopup()
        else showPopup()
    }

    function setWifi(enabled) { net.setWifiEnabled(!!enabled) }
    function toggleWifi() { net.toggleWifi() }
    function enableWifi() { net.setWifiEnabled(true) }
    function disableWifi() { net.setWifiEnabled(false) }

    function setNetworking(enabled) { net.setNetworking(!!enabled) }
    function toggleNetworking() { net.toggleNetworking() }

    function startScan() { net.setScanner(true) }
    function stopScan() { net.setScanner(false) }

    function connectSsid(ssid, psk) {
        if (psk !== undefined && psk !== null && String(psk).length)
            net.connectNetwork(ssid, psk)
        else
            net.connectNetwork(ssid)
    }

    function disconnectDevice(iface) { net.disconnectDevice(iface) }
    function enableDevice(iface) { net.enableDevice(iface) }
    function disableAllAdapters() { net.disableAllAdapters() }
    function forgetSsid(ssid) { net.forgetNetwork(ssid) }

    function openConnectionEditor() { openEditor("") }

    function activateConnection(id) {
        if (!id || !String(id).length) return
        runControl(["connection", "up", String(id)])
        flashStatus("Activating " + id + "…")
        refreshStatusSoon()
    }
    function deactivateConnection(id) {
        if (!id || !String(id).length) return
        runControl(["connection", "down", String(id)])
        flashStatus("Deactivating " + id + "…")
        refreshStatusSoon()
    }
}
