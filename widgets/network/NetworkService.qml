pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Networking
import Quickshell.Io as Io

// =============================================================================
// NetworkService.qml — one NetworkManager backend for the network panel
// =============================================================================
//
// Singleton (see qmldir). NetworkButton and NetworkPopup both read this.
// Do not instantiate it. Import the folder and use NetworkService.
//
// Backend:
//   Quickshell.Networking  devices, Wi-Fi radio, scan, connect, forget
//   scripts/network-control.sh  IP, DNS, gateway, link facts, VPN, hidden SSID
//   nmcli monitor  pushes changes. A timer still samples byte counters so
//   the rx/tx numbers stay live (those do not emit NetworkManager events).
//
// DNS flush goes through `network-control.sh refresh-dns`. That runs
// `resolvectl flush-caches` as the session user. It does not call sudo.
// =============================================================================

Item {
    id: root

    visible: false
    width: 0
    height: 0

    readonly property string controlScript: "/home/crome/.config/quickshell/scripts/network-control.sh"

    // The button sets this while the popup is open. Scanning and the fast
    // rate sample stay off when it is closed.
    property bool popupOpen: false
    // Popup sets this while a password field is focused so a list refresh
    // does not destroy the field mid-typing.
    property bool holdLists: false

    property var statusData: ({})
    property int statusEpoch: 0
    property int deviceEpoch: 0
    property bool airplaneOn: false
    property string toastText: ""
    property bool toastOk: true
    property string lastError: ""
    property string pending: ""

    property bool hasWifi: false
    property bool anyConnected: false
    property bool vpnActive: false
    property string vpnName: ""
    property string linkState: "down"     // off | airplane | portal | vpn | wired | wifi | wifioff | down
    property string primaryLabel: ""
    property string primaryIp: ""
    property string primaryIface: ""
    property string primaryKind: "none"   // wired | wifi | none
    property string primarySpeed: ""
    property string primarySsid: ""
    // SSID the radio is actually joined to, even when Ethernet is the primary link.
    // The password row watches this so it can close after a successful join.
    property string wifiJoinedSsid: ""
    property string primaryBand: ""
    property string primarySecurity: ""
    property string primaryMethod: ""
    property string primaryMac: ""
    property string primaryGateway: ""
    property string primaryDns: ""
    property string primaryIp6: ""
    property string primaryGateway6: ""
    property int primaryMtu: 0
    property int primarySignal: -1
    property real primaryRx: 0
    property real primaryTx: 0

    property var wiredRows: []
    property var wifiRows: []
    property var savedRows: []
    property var vpnRows: []
    property var ifaceRates: ({})

    property string _wiredFp: ""
    property string _wifiFp: ""
    property string _savedFp: ""
    property string _vpnFp: ""
    property var _ratePrev: ({})
    property var _failTarget: null
    property int _monitorFails: 0
    // Last announced link snapshot. The first real status pass only stores it,
    // so opening the panel does not notify about the connection you already have.
    property bool _notesReady: false
    property var _noteSnap: ({})

    readonly property bool wifiEnabled: {
        void root.deviceEpoch
        if (airplaneOn)
            return false
        try { return !!Networking.wifiEnabled } catch (e) { return false }
    }
    readonly property bool wifiHardwareEnabled: {
        void root.deviceEpoch
        try { return !!Networking.wifiHardwareEnabled } catch (e) { return true }
    }
    readonly property bool networkingEnabled: {
        var d = statusData || {}
        if (d.networking !== undefined)
            return !!d.networking
        return true
    }
    readonly property bool isPortal: {
        try {
            return Networking.connectivity === NetworkConnectivity.Portal
                || Networking.connectivity === 2
        } catch (e) {
            var d = statusData || {}
            return String(d.connectivity || "").toLowerCase() === "portal"
        }
    }

    function toast(message, ok) {
        toastText = message || ""
        toastOk = ok !== false
        if (toastText.length)
            toastTimer.restart()
        else
            toastTimer.stop()
    }

    // Desktop notification (SwayNC and the bell history). `notify-send` is the
    // same path every other app on this session uses. The in-panel toast is
    // separate and stays for copy, validation, and "connecting…" hints.
    function desktopNotify(summary, body) {
        var title = String(summary || "Network")
        var text = String(body || "")
        var icon = "network-wired"
        if (title.indexOf("Wi-Fi") >= 0 || title.indexOf("Airplane") >= 0)
            icon = "network-wireless"
        else if (title.indexOf("VPN") >= 0)
            icon = "network-vpn"
        var args = ["notify-send", "-a", "Network", "-i", icon, title]
        if (text.length)
            args.push(text)
        Quickshell.execDetached(args)
    }

    // Compare the link we last announced with this pass. Radio, Wi-Fi join,
    // Ethernet, VPN, and airplane each produce one notification when they change.
    function noteLinkChanges(wifiOn, airplane, ssid, wired, vpn) {
        var snap = {
            wifi: !!wifiOn,
            airplane: !!airplane,
            ssid: String(ssid || ""),
            wired: {},
            vpn: {}
        }
        var list = wired || []
        for (var i = 0; i < list.length; i++) {
            var row = list[i]
            if (!row || !row.iface)
                continue
            var label = String(row.iface)
            if (row.connection && String(row.connection).length && String(row.connection) !== label)
                label += " · " + row.connection
            snap.wired[String(row.iface)] = { state: String(row.state || ""), label: label }
        }
        var vlist = vpn || []
        for (var v = 0; v < vlist.length; v++) {
            var vp = vlist[v]
            if (!vp || !vp.uuid)
                continue
            snap.vpn[String(vp.uuid)] = {
                active: !!vp.active,
                name: String(vp.name || "VPN")
            }
        }
        if (!_notesReady) {
            _noteSnap = snap
            if (statusEpoch > 0)
                _notesReady = true
            return
        }
        var prev = _noteSnap || {}
        var airplaneChanged = snap.airplane !== !!prev.airplane
        if (airplaneChanged)
            desktopNotify("Airplane mode", snap.airplane ? "On" : "Off")
        if (snap.wifi !== !!prev.wifi && !airplaneChanged)
            desktopNotify("Wi-Fi", snap.wifi ? "On" : "Off")
        var prevSsid = String(prev.ssid || "")
        if (!airplaneChanged && snap.ssid !== prevSsid) {
            if (snap.ssid.length)
                desktopNotify("Wi-Fi", "Connected to " + snap.ssid)
            else if (prevSsid.length)
                desktopNotify("Wi-Fi", "Disconnected from " + prevSsid)
        }
        var prevWired = prev.wired || {}
        var seenW = {}
        for (var iface in snap.wired) {
            seenW[iface] = true
            var now = snap.wired[iface]
            var was = prevWired[iface]
            if (!was) {
                if (now.state === "connected")
                    desktopNotify("Wired", now.label + " connected")
                continue
            }
            if (was.state === now.state)
                continue
            if (now.state === "connected")
                desktopNotify("Wired", now.label + " connected")
            else if (was.state === "connected")
                desktopNotify("Wired", now.label + (now.state === "cable unplugged" ? " unplugged" : " disconnected"))
        }
        for (var oldIface in prevWired) {
            if (seenW[oldIface])
                continue
            if (prevWired[oldIface] && prevWired[oldIface].state === "connected")
                desktopNotify("Wired", (prevWired[oldIface].label || oldIface) + " disconnected")
        }
        var prevVpn = prev.vpn || {}
        var seenV = {}
        for (var id in snap.vpn) {
            seenV[id] = true
            var cur = snap.vpn[id]
            var before = prevVpn[id]
            var wasOn = before ? !!before.active : false
            if (cur.active === wasOn)
                continue
            desktopNotify("VPN", cur.active ? ("Connected to " + cur.name) : ("Disconnected from " + cur.name))
        }
        for (var oldId in prevVpn) {
            if (seenV[oldId])
                continue
            if (prevVpn[oldId] && prevVpn[oldId].active)
                desktopNotify("VPN", "Disconnected from " + (prevVpn[oldId].name || "VPN"))
        }
        _noteSnap = snap
    }

    function formatRate(bytesPerSec) {
        var b = Number(bytesPerSec) || 0
        if (b < 0)
            b = 0
        if (b >= 1048576)
            return (b / 1048576).toFixed(1) + " MB/s"
        if (b >= 1024)
            return (b / 1024).toFixed(1) + " KB/s"
        return Math.round(b) + " B/s"
    }

    function bareIp(cidr) {
        var s = String(cidr || "")
        var i = s.indexOf("/")
        if (i > 0)
            s = s.substring(0, i)
        return s
    }

    function skipIface(name) {
        var n = String(name || "")
        if (!n.length || n === "lo")
            return true
        if (n.indexOf("p2p") === 0)
            return true
        return false
    }

    function isEthernetType(type) {
        var t = String(type || "").toLowerCase()
        return t === "ethernet" || t.indexOf("802-3") >= 0 || t.indexOf("ethernet") >= 0
    }

    function isWifiProfile(type) {
        var t = String(type || "").toLowerCase()
        return t.indexOf("wireless") >= 0 || t.indexOf("wifi") >= 0
    }

    function isVpnProfile(type) {
        var t = String(type || "").toLowerCase()
        return t === "vpn" || t === "wireguard" || t.indexOf("vpn") >= 0 || t.indexOf("wireguard") >= 0
    }

    function methodLabel(method) {
        var s = String(method || "").toLowerCase()
        if (s === "auto")
            return "DHCP"
        if (s === "manual")
            return "Static"
        if (!s.length || s === "--")
            return ""
        return s
    }

    function signalPercent(strength) {
        var s = Number(strength)
        if (isNaN(s) || s < 0)
            return 0
        if (s <= 1.01)
            return Math.round(s * 100)
        return Math.round(Math.min(100, s))
    }

    function signalBucket(pct) {
        if (pct >= 75) return 4
        if (pct >= 50) return 3
        if (pct >= 25) return 2
        if (pct > 0) return 1
        return 0
    }

    function statusIsWifi(d) {
        var t = String((d && d.type) || "").toLowerCase()
        return t === "wifi" || t === "802-11-wireless"
    }

    function packWifiFacts(d) {
        var mtuN = Number(d.mtu) || 0
        return {
            iface: String(d.iface || ""),
            ip4: joinAddrs(d.ip4, 2),
            ip6: joinAddrs(d.ip6, 2),
            gateway4: bareIp(d.gateway4),
            gateway6: bareIp(d.gateway6),
            dns: joinAddrs(d.dns, 3),
            mac: String(d.mac || ""),
            band: bandFromFreq(d.wifi_freq),
            link: speedText(d.speed_mbps, d.duplex, d.wifi_bitrate),
            method: methodLabel(d.method4),
            mtu: mtuN > 0 ? String(mtuN) : ""
        }
    }

    // Link facts for a joined Wi-Fi SSID, from the status snapshot.
    // Same address fields as a wired device. Empty when that SSID is not up.
    // Matches wifi_ssid when the status script filled it, otherwise the
    // connection name (often the SSID), otherwise the single connected radio.
    function wifiFacts(ssid) {
        var none = {
            iface: "", ip4: "", ip6: "", gateway4: "", gateway6: "",
            dns: "", mac: "", band: "", link: "", method: "", mtu: ""
        }
        var want = String(ssid || "")
        if (!want.length)
            return none
        var list = (statusData && statusData.devices) ? statusData.devices : []
        var only = null
        var connectedWifi = 0
        for (var i = 0; i < list.length; i++) {
            var d = list[i]
            if (!d || !statusIsWifi(d))
                continue
            var st = String(d.state || "").toLowerCase()
            // "disconnected" contains "connected", so require it as the prefix.
            if (st.indexOf("connected") !== 0)
                continue
            connectedWifi++
            only = d
            var devSsid = String(d.wifi_ssid || "")
            var connName = String(d.connection || "")
            if (devSsid === want)
                return packWifiFacts(d)
            if (connName.length && connName !== "--" && connName === want)
                return packWifiFacts(d)
        }
        if (connectedWifi === 1 && only && want === String(wifiJoinedSsid || ""))
            return packWifiFacts(only)
        return none
    }

    function bandFromFreq(freq) {
        var n = parseInt(String(freq || ""), 10)
        if (!(n > 0))
            return ""
        // nmcli reports MHz ("5240 MHz") or occasionally GHz.
        if (n < 20)
            n = n * 1000
        if (n < 3000)
            return "2.4 GHz"
        if (n < 5900)
            return "5 GHz"
        return "6 GHz"
    }

    function speedText(mbps, duplex, bitrate) {
        var br = String(bitrate || "")
        if (br.length && br !== "--")
            return br
        var parts = []
        var n = Number(mbps)
        if (n > 0)
            parts.push(n + " Mb/s")
        var d = String(duplex || "")
        if (d.length && d !== "unknown" && d !== "--")
            parts.push(d + " duplex")
        return parts.join(" · ")
    }

    function securityLabel(sec) {
        try {
            if (typeof WifiSecurityType !== "undefined" && WifiSecurityType.toString)
                return WifiSecurityType.toString(sec)
        } catch (e) {}
        return String(sec)
    }

    function isOpenSecurity(sec) {
        try {
            if (sec === WifiSecurityType.Open || sec === WifiSecurityType.Owe)
                return true
            if (sec === 9 || sec === 10)
                return true
        } catch (e) {}
        return false
    }

    function needsPsk(sec) {
        try {
            if (sec === WifiSecurityType.WpaPsk || sec === WifiSecurityType.Wpa2Psk
                    || sec === WifiSecurityType.Sae)
                return true
            if (sec === 1 || sec === 3 || sec === 5)
                return true
        } catch (e) {}
        return false
    }

    function isSecured(sec) {
        return !isOpenSecurity(sec)
    }

    // Enterprise networks need the connection editor, not a PSK box.
    function needsEnterprise(sec) {
        try {
            if (sec === WifiSecurityType.WpaEap || sec === WifiSecurityType.Wpa2Eap
                    || sec === WifiSecurityType.Leap || sec === WifiSecurityType.Wpa3SuiteB192)
                return true
            if (sec === 0 || sec === 2 || sec === 4 || sec === 8)
                return true
        } catch (e) {}
        return false
    }

    function statusDevice(iface) {
        var list = (statusData && statusData.devices) ? statusData.devices : []
        for (var i = 0; i < list.length; i++) {
            if (list[i] && list[i].iface === iface)
                return list[i]
        }
        return null
    }

    function findDevice(iface) {
        if (!iface)
            return null
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
        if (!ssid)
            return null
        try {
            var vals = (Networking.devices && Networking.devices.values)
                    ? Networking.devices.values : []
            for (var i = 0; i < vals.length; i++) {
                var d = vals[i]
                if (!d || !isWifiDev(d))
                    continue
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

    function isWifiDev(dev) {
        if (!dev)
            return false
        try {
            var t = dev.type
            return (t === DeviceType.Wifi || t === 1) && !skipIface(dev.name)
        } catch (e) { return false }
    }

    function isWiredDev(dev) {
        if (!dev)
            return false
        try {
            var t = dev.type
            return (t === DeviceType.Wired || t === 2) && !skipIface(dev.name)
        } catch (e) { return false }
    }

    function rateFor(iface) {
        var table = ifaceRates || {}
        var r = table[String(iface || "")] || {}
        return { rx: Number(r.rx) || 0, tx: Number(r.tx) || 0 }
    }

    function noteRates(devices) {
        var now = Date.now()
        var prev = _ratePrev || {}
        var next = {}
        var rates = {}
        var list = devices || []
        for (var i = 0; i < list.length; i++) {
            var d = list[i]
            if (!d || !d.iface)
                continue
            var iface = String(d.iface)
            var rx = Number(d.rx_bytes) || 0
            var tx = Number(d.tx_bytes) || 0
            var p = prev[iface]
            var rxRate = 0
            var txRate = 0
            if (p && p.t && now > p.t) {
                var dt = (now - p.t) / 1000
                if (dt > 0.2 && dt < 30) {
                    rxRate = Math.max(0, (rx - p.rx) / dt)
                    txRate = Math.max(0, (tx - p.tx) / dt)
                }
            }
            next[iface] = { rx: rx, tx: tx, t: now }
            rates[iface] = { rx: rxRate, tx: txRate }
        }
        _ratePrev = next
        ifaceRates = rates
    }

    function joinAddrs(list, limit) {
        var out = []
        var src = list || []
        var cap = limit || 3
        for (var i = 0; i < src.length && out.length < cap; i++) {
            var s = String(src[i] || "")
            if (s.length && s !== "--")
                out.push(s)
        }
        return out.join(", ")
    }

    // One pass over Quickshell devices + the last nmcli snapshot.
    function rebuildLists() {
        var __ = deviceEpoch
        var __s = statusEpoch
        var nmWired = ({})
        var wifiScored = []
        var seenSsid = ({})
        var wifiHw = false
        var connectedSsid = ""
        var connectedSec = ""
        var connectedSig = -1

        try {
            var vals = (Networking.devices && Networking.devices.values)
                    ? Networking.devices.values : []
            for (var i = 0; i < vals.length; i++) {
                var dev = vals[i]
                if (!dev || skipIface(dev.name))
                    continue
                if (isWifiDev(dev)) {
                    wifiHw = true
                    if (popupOpen && wifiEnabled) {
                        var nets = (dev.networks && dev.networks.values) ? dev.networks.values : []
                        for (var j = 0; j < nets.length; j++) {
                            var n = nets[j]
                            if (!n)
                                continue
                            var ssid = String(n.name || "")
                            if (!ssid.length || seenSsid[ssid])
                                continue
                            seenSsid[ssid] = true
                            var pct = signalPercent(n.signalStrength)
                            var secured = isSecured(n.security)
                            wifiScored.push({
                                ssid: ssid,
                                signal: pct,
                                bucket: signalBucket(pct),
                                secured: secured ? 1 : 0,
                                known: n.known ? 1 : 0,
                                connected: n.connected ? 1 : 0,
                                security: securityLabel(n.security)
                            })
                            if (n.connected) {
                                connectedSsid = ssid
                                connectedSec = securityLabel(n.security)
                                connectedSig = pct
                            }
                        }
                    } else {
                        // Closed popup: only need the connected SSID and signal.
                        var nets2 = (dev.networks && dev.networks.values) ? dev.networks.values : []
                        for (var k = 0; k < nets2.length; k++) {
                            var n2 = nets2[k]
                            if (n2 && n2.connected) {
                                connectedSsid = String(n2.name || "")
                                connectedSec = securityLabel(n2.security)
                                connectedSig = signalPercent(n2.signalStrength)
                                break
                            }
                        }
                    }
                } else if (isWiredDev(dev)) {
                    nmWired[String(dev.name)] = {
                        connected: !!dev.connected,
                        hasLink: true,
                        linkSpeed: 0
                    }
                    try {
                        if (dev.hasLink !== undefined)
                            nmWired[String(dev.name)].hasLink = !!dev.hasLink
                        if (dev.linkSpeed)
                            nmWired[String(dev.name)].linkSpeed = Number(dev.linkSpeed) || 0
                    } catch (eL) {}
                }
            }
        } catch (e) {}

        hasWifi = wifiHw

        var statusDevs = (statusData && statusData.devices) ? statusData.devices : []
        var wired = []
        var seenWired = ({})
        for (var s = 0; s < statusDevs.length; s++) {
            var sd = statusDevs[s]
            if (!sd || skipIface(sd.iface) || !isEthernetType(sd.type))
                continue
            seenWired[sd.iface] = true
            var nm = nmWired[sd.iface] || {}
            var carrier = (sd.carrier === undefined) ? (nm.hasLink !== false) : !!sd.carrier
            var mbps = Number(sd.speed_mbps)
            if (!(mbps > 0) && nm.linkSpeed > 0)
                mbps = nm.linkSpeed
            var state = String(sd.state || "")
            if (!carrier)
                state = "cable unplugged"
            wired.push({
                iface: String(sd.iface),
                state: state,
                connection: String(sd.connection || ""),
                uuid: String(sd.uuid || ""),
                mac: String(sd.mac || ""),
                speedMbps: mbps > 0 ? mbps : 0,
                duplex: String(sd.duplex || ""),
                carrier: carrier ? 1 : 0,
                method: methodLabel(sd.method4),
                ip4: joinAddrs(sd.ip4, 2),
                ip6: joinAddrs(sd.ip6, 2),
                gateway4: bareIp(sd.gateway4),
                gateway6: bareIp(sd.gateway6),
                dns: joinAddrs(sd.dns, 3),
                mtu: Number(sd.mtu) || 0,
                managed: sd.managed !== false
            })
        }
        // Networking knows a NIC that status has not reported yet.
        for (var key in nmWired) {
            if (seenWired[key])
                continue
            wired.push({
                iface: key,
                state: nmWired[key].connected ? "connected" : (nmWired[key].hasLink ? "disconnected" : "cable unplugged"),
                connection: "",
                uuid: "",
                mac: "",
                speedMbps: nmWired[key].linkSpeed || 0,
                duplex: "",
                carrier: nmWired[key].hasLink ? 1 : 0,
                method: "",
                ip4: "",
                ip6: "",
                gateway4: "",
                gateway6: "",
                dns: "",
                mtu: 0,
                managed: true
            })
        }

        var conns = (statusData && statusData.connections) ? statusData.connections : []
        var vpn = []
        var saved = []
        var vpnUp = ""
        for (var c = 0; c < conns.length; c++) {
            var profile = conns[c]
            if (!profile)
                continue
            if (isVpnProfile(profile.type)) {
                vpn.push({
                    name: String(profile.name || profile.uuid || "VPN"),
                    uuid: String(profile.uuid || ""),
                    type: String(profile.type || ""),
                    active: profile.active ? 1 : 0
                })
                if (profile.active && !vpnUp.length)
                    vpnUp = String(profile.name || "VPN")
            } else if (isWifiProfile(profile.type)) {
                saved.push({
                    name: String(profile.name || profile.uuid || "Saved network"),
                    uuid: String(profile.uuid || ""),
                    active: profile.active ? 1 : 0
                })
            }
        }

        // Primary link: wired beats Wi-Fi. VPN is reported beside it.
        var pLabel = ""
        var pIp = ""
        var pIface = ""
        var pKind = "none"
        var pSpeed = ""
        var pSsid = ""
        var pBand = ""
        var pMethod = ""
        var pMac = ""
        var pGw = ""
        var pDns = ""
        var pIp6 = ""
        var pGw6 = ""
        var pMtu = 0
        var connected = false
        for (var w = 0; w < wired.length; w++) {
            var row = wired[w]
            var up = row.state === "connected" || row.ip4.length > 0
            if (!up)
                continue
            connected = true
            pKind = "wired"
            pIface = row.iface
            pLabel = row.connection.length ? row.connection : row.iface
            pIp = bareIp(row.ip4)
            pSpeed = speedText(row.speedMbps, row.duplex, "")
            pMethod = row.method
            pMac = row.mac
            pGw = row.gateway4
            pDns = row.dns
            pIp6 = row.ip6
            pGw6 = row.gateway6
            pMtu = row.mtu
            break
        }
        if (!pLabel.length) {
            for (var sd2 = 0; sd2 < statusDevs.length; sd2++) {
                var wd = statusDevs[sd2]
                if (!wd || skipIface(wd.iface) || isEthernetType(wd.type))
                    continue
                var st = String(wd.state || "").toLowerCase()
                if (st.indexOf("connected") < 0)
                    continue
                if (isVpnProfile(wd.type))
                    continue
                connected = true
                pKind = "wifi"
                pIface = String(wd.iface)
                pSsid = String(wd.wifi_ssid || connectedSsid || "")
                pLabel = pSsid.length ? pSsid : (wd.connection || wd.iface)
                pIp = bareIp((wd.ip4 && wd.ip4.length) ? wd.ip4[0] : "")
                pSpeed = speedText(wd.speed_mbps, wd.duplex, wd.wifi_bitrate)
                pBand = bandFromFreq(wd.wifi_freq)
                pMethod = methodLabel(wd.method4)
                pMac = String(wd.mac || "")
                pGw = bareIp(wd.gateway4)
                pDns = joinAddrs(wd.dns, 3)
                pIp6 = joinAddrs(wd.ip6, 2)
                pGw6 = bareIp(wd.gateway6)
                pMtu = Number(wd.mtu) || 0
                break
            }
        }
        if (pKind === "wifi" && connectedSsid.length)
            pSsid = connectedSsid
        if (!connected && connectedSsid.length) {
            connected = true
            pKind = "wifi"
            pSsid = connectedSsid
            pLabel = connectedSsid
        }

        anyConnected = connected
        vpnActive = vpnUp.length > 0
        vpnName = vpnUp
        primaryLabel = pLabel
        primaryIp = pIp
        primaryIface = pIface
        primaryKind = pKind
        primarySpeed = pSpeed
        primarySsid = pSsid
        wifiJoinedSsid = connectedSsid
        primaryBand = pBand
        primarySecurity = connectedSec
        primaryMethod = pMethod
        primaryMac = pMac
        primaryGateway = pGw
        primaryDns = pDns
        primaryIp6 = pIp6
        primaryGateway6 = pGw6
        primaryMtu = pMtu
        primarySignal = (pKind === "wifi") ? connectedSig : -1

        var rates = rateFor(pIface)
        primaryRx = rates.rx
        primaryTx = rates.tx

        if (!networkingEnabled)
            linkState = "off"
        else if (airplaneOn)
            linkState = "airplane"
        else if (isPortal)
            linkState = "portal"
        else if (vpnActive)
            linkState = "vpn"
        else if (pKind === "wired")
            linkState = "wired"
        else if (pKind === "wifi")
            linkState = "wifi"
        else if (hasWifi && !wifiEnabled)
            linkState = "wifioff"
        else
            linkState = "down"

        noteLinkChanges(wifiEnabled, airplaneOn, connectedSsid, wired, vpn)

        var wfp = []
        for (var a = 0; a < wired.length; a++) {
            var wr = wired[a]
            wfp.push(wr.iface + wr.state + wr.connection + wr.ip4 + wr.carrier + wr.speedMbps + wr.method)
        }
        var wiredKey = wfp.join("|")
        if (wiredKey !== _wiredFp) {
            _wiredFp = wiredKey
            wiredRows = wired
        }

        var vfp = []
        for (var v = 0; v < vpn.length; v++)
            vfp.push(vpn[v].uuid + ":" + vpn[v].active)
        var vpnKey = vfp.join("|")
        if (vpnKey !== _vpnFp) {
            _vpnFp = vpnKey
            vpnRows = vpn
        }

        if (!popupOpen)
            return

        saved.sort(function (a, b) {
            if (b.active !== a.active)
                return b.active - a.active
            return String(a.name).localeCompare(String(b.name))
        })
        var sfp = []
        for (var sv = 0; sv < saved.length; sv++)
            sfp.push(saved[sv].uuid + ":" + saved[sv].active)
        var savedKey = sfp.join("|")
        if (savedKey !== _savedFp) {
            _savedFp = savedKey
            savedRows = saved
        }

        if (holdLists && _wifiFp.length)
            return
        wifiScored.sort(function (a, b) {
            if (b.signal !== a.signal)
                return b.signal - a.signal
            return String(a.ssid).localeCompare(String(b.ssid))
        })
        var ffp = []
        for (var f = 0; f < wifiScored.length; f++) {
            var ap = wifiScored[f]
            ffp.push(ap.ssid + ":" + ap.bucket + ":" + ap.connected + ":" + ap.known + ":" + ap.secured)
        }
        var wifiKey = ffp.join("|")
        if (wifiKey !== _wifiFp) {
            _wifiFp = wifiKey
            wifiRows = wifiScored
        }
    }

    function setScanner(on) {
        try {
            var vals = (Networking.devices && Networking.devices.values)
                    ? Networking.devices.values : []
            for (var i = 0; i < vals.length; i++) {
                var d = vals[i]
                if (!d || !isWifiDev(d))
                    continue
                try { d.scannerEnabled = !!on } catch (e1) {}
            }
        } catch (e) {}
        deviceEpoch++
    }

    function setWifi(on) {
        var enable = !!on
        if (enable && airplaneOn)
            airplaneOn = false
        try {
            Networking.wifiEnabled = enable
        } catch (e) {
            runControl(["wifi", enable ? "on" : "off"])
        }
        deviceEpoch++
        if (enable && popupOpen)
            scanAfterEnable.restart()
        refreshSoon.restart()
    }

    function toggleWifi() {
        setWifi(!wifiEnabled)
    }

    function setAirplane(on) {
        airplaneOn = !!on
        // nmcli radio all off/on is Wi-Fi + WWAN. Ethernet stays up.
        // This is the same nmcli the pill already uses for the Wi-Fi radio.
        runControl(["radio", "all", on ? "off" : "on"])
        deviceEpoch++
    }

    function toggleAirplane() {
        setAirplane(!airplaneOn)
    }

    function rescan() {
        if (!hasWifi || !wifiEnabled) {
            toast("Wi-Fi is off", false)
            return
        }
        setScanner(false)
        Qt.callLater(function () { setScanner(true) })
        pending = "scan"
        runControl(["wifi-rescan"])
        toast("Scanning for networks…", true)
    }

    function watchNetwork(n) {
        if (!n)
            return
        try {
            if (_failTarget && _failTarget !== n)
                _failTarget.connectionFailed.disconnect(onConnectionFailed)
            if (_failTarget !== n) {
                n.connectionFailed.connect(onConnectionFailed)
                _failTarget = n
            }
        } catch (e) {}
    }

    function onConnectionFailed(reason) {
        var noSecrets = false
        try {
            noSecrets = (reason === ConnectionFailReason.NoSecrets || reason === 1)
        } catch (e) {
            noSecrets = (reason === 1)
        }
        var label = ""
        try {
            if (typeof ConnectionFailReason !== "undefined" && ConnectionFailReason.toString)
                label = ConnectionFailReason.toString(reason)
        } catch (e2) {}
        if (noSecrets)
            lastError = "Wrong or missing password"
        else if (label.length)
            lastError = "Connection failed: " + label
        else
            lastError = "Connection failed"
        toast(lastError, false)
        desktopNotify("Wi-Fi", lastError)
        deviceEpoch++
        refreshSoon.restart()
    }

    // Returns "password" when the popup should ask, "enterprise" when the
    // editor is required, or "" when connect() was started.
    function connectSsid(ssid, psk) {
        var n = findWifiNetwork(ssid)
        if (!n) {
            toast("Network not found: " + ssid, false)
            return ""
        }
        try {
            if (n.connected)
                return ""
        } catch (e0) {}
        lastError = ""
        watchNetwork(n)
        var hasPsk = psk !== undefined && psk !== null && String(psk).length > 0
        try {
            if (hasPsk) {
                if (n.connectWithPsk)
                    n.connectWithPsk(String(psk))
                else
                    n.connect()
                toast("Connecting to " + ssid + "…", true)
                return ""
            }
            if (n.known || n.connected || isOpenSecurity(n.security)) {
                n.connect()
                toast("Connecting to " + ssid + "…", true)
                return ""
            }
            if (needsEnterprise(n.security)) {
                toast("This network needs the connection editor", false)
                openEditor("")
                return "enterprise"
            }
            if (needsPsk(n.security))
                return "password"
            n.connect()
            toast("Connecting to " + ssid + "…", true)
        } catch (e) {
            lastError = "Connect failed"
            toast(lastError, false)
        }
        deviceEpoch++
        refreshSoon.restart()
        return ""
    }

    function disconnectSsid(ssid) {
        var n = findWifiNetwork(ssid)
        if (n) {
            try { n.disconnect() } catch (e) {}
        }
        toast("Disconnecting " + ssid + "…", true)
        deviceEpoch++
        refreshSoon.restart()
    }

    function forgetSsid(ssid, uuid) {
        var n = findWifiNetwork(ssid)
        if (n) {
            try { n.forget() } catch (e) {}
            toast("Forgot " + ssid, true)
        } else if (uuid && String(uuid).length) {
            pending = "forget"
            runControl(["connection", "delete", String(uuid)])
            toast("Removing " + (ssid || "network") + "…", true)
        }
        deviceEpoch++
        refreshSoon.restart()
    }

    function connectHidden(ssid, psk) {
        var name = String(ssid || "").trim()
        if (!name.length) {
            toast("Enter the network name", false)
            return
        }
        lastError = ""
        pending = "hidden"
        var args = ["wifi-hidden", name]
        if (psk !== undefined && psk !== null && String(psk).length)
            args.push(String(psk))
        runControl(args)
        toast("Connecting to " + name + "…", true)
    }

    function setDeviceUp(iface, up) {
        if (!iface)
            return
        if (up) {
            runControl(["device", "connect", iface])
            toast("Connecting " + iface + "…", true)
        } else {
            var d = findDevice(iface)
            if (d) {
                try { d.disconnect() } catch (e) {
                    runControl(["device", "disconnect", iface])
                }
            } else {
                runControl(["device", "disconnect", iface])
            }
            toast("Disconnecting " + iface + "…", true)
        }
        deviceEpoch++
        refreshSoon.restart()
    }

    function toggleVpn(uuid, active) {
        if (!uuid)
            return
        runControl(["connection", active ? "down" : "up", String(uuid)])
        toast(active ? "Disconnecting VPN…" : "Connecting VPN…", true)
        refreshSoon.restart()
    }

    // Drop every VPN the panel currently shows as connected. One profile
    // goes through the control script. Several go out together so a second
    // nmcli does not cancel the first.
    function disconnectActiveVpns() {
        var rows = vpnRows || []
        var uuids = []
        for (var i = 0; i < rows.length; i++) {
            if (rows[i] && rows[i].active && rows[i].uuid)
                uuids.push(String(rows[i].uuid))
        }
        if (!uuids.length)
            return
        if (uuids.length === 1) {
            toggleVpn(uuids[0], true)
            return
        }
        var cmd = ["sh", "-c", 'for u in "$@"; do nmcli connection down "$u"; done', "vpn-down"]
        for (var u = 0; u < uuids.length; u++)
            cmd.push(uuids[u])
        Quickshell.execDetached(cmd)
        toast("Disconnecting VPN…", true)
        refreshSoon.restart()
    }

    function openEditor(uuidOrName) {
        if (uuidOrName && String(uuidOrName).length)
            Quickshell.execDetached(["nm-connection-editor", "--edit", String(uuidOrName)])
        else
            Quickshell.execDetached(["nm-connection-editor"])
    }

    // Same command the original pill's footer uses. resolvectl flush-caches
    // runs inside network-control.sh refresh-dns.
    function flushDns() {
        pending = "dns"
        toast("Flushing DNS cache…", true)
        runControl(["refresh-dns"])
    }

    // Same path the original pill uses. `refresh-ip` reapplies the connection
    // so DHCP renews without a full disconnect when NetworkManager allows it.
    function refreshIp(iface) {
        var name = String(iface || primaryIface || "")
        pending = "ip"
        if (name.length)
            runControl(["refresh-ip", name])
        else
            runControl(["refresh-ip"])
        toast("Refreshing IP…", true)
    }

    // Master switch for the wired toggle. One device goes through the control
    // script. Several are issued together so the second nmcli does not cancel
    // the first. Off disconnects connected ports. On connects the others.
    function setWiredEnabled(on) {
        var rows = wiredRows || []
        var ifaces = []
        var enable = !!on
        for (var i = 0; i < rows.length; i++) {
            if (!rows[i] || !rows[i].iface)
                continue
            var up = rows[i].state === "connected"
            if (enable && !up)
                ifaces.push(String(rows[i].iface))
            else if (!enable && up)
                ifaces.push(String(rows[i].iface))
        }
        if (!ifaces.length)
            return
        if (ifaces.length === 1) {
            setDeviceUp(ifaces[0], enable)
            return
        }
        var script = enable
                ? 'for i in "$@"; do nmcli device connect "$i"; done'
                : 'for i in "$@"; do nmcli device disconnect "$i"; done'
        var cmd = ["sh", "-c", script, "wired"]
        for (var u = 0; u < ifaces.length; u++)
            cmd.push(ifaces[u])
        Quickshell.execDetached(cmd)
        toast(enable ? "Connecting Ethernet…" : "Disconnecting Ethernet…", true)
        refreshSoon.restart()
    }

    function runControl(args) {
        var cmd = [controlScript].concat(args)
        if (controlProcess.running)
            controlProcess.running = false
        controlProcess.command = cmd
        controlProcess.running = true
    }

    function refreshStatus(force) {
        if (statusProcess.running) {
            if (force)
                statusProcess.running = false
            else
                return
        }
        statusProcess.command = [controlScript, "status"]
        statusProcess.running = true
    }

    function clearFailWatch() {
        if (_failTarget) {
            try { _failTarget.connectionFailed.disconnect(onConnectionFailed) } catch (e) {}
            _failTarget = null
        }
    }

    onPopupOpenChanged: {
        if (popupOpen) {
            if (wifiEnabled && hasWifi)
                setScanner(true)
            refreshStatus(true)
            fastTimer.start()
        } else {
            setScanner(false)
            fastTimer.stop()
            clearFailWatch()
            holdLists = false
            lastError = ""
        }
        rebuildLists()
    }

    Connections {
        target: Networking
        function onWifiEnabledChanged() {
            // A radio kill from somewhere else drops the airplane flag only
            // when Wi-Fi comes back. Turning Wi-Fi off by itself is not airplane.
            if (Networking.wifiEnabled && root.airplaneOn)
                root.airplaneOn = false
            root.deviceEpoch++
            root.rebuildLists()
        }
        function onConnectivityChanged() {
            root.deviceEpoch++
            root.rebuildLists()
        }
    }

    Io.Process {
        id: statusProcess
        running: false
        stdout: Io.StdioCollector { id: statusStdout }
        onExited: (code) => {
            if (code !== 0)
                return
            var t = (statusStdout.text || "").trim()
            if (!t.length)
                return
            try {
                var data = JSON.parse(t)
                root.statusData = data
                root.noteRates(data.devices || [])
                root.statusEpoch++
                root.rebuildLists()
            } catch (e) {}
        }
    }

    Io.Process {
        id: controlProcess
        running: false
        stdout: Io.StdioCollector { id: controlStdout }
        onExited: (code) => {
            var t = (controlStdout.text || "").trim()
            var ok = code === 0
            var err = ""
            var msg = ""
            try {
                var j = JSON.parse(t)
                if (j) {
                    if (j.ok === false)
                        ok = false
                    err = j.error || ""
                    msg = j.message || ""
                }
            } catch (e) {
                if (code !== 0 && t.length)
                    err = t
            }
            var why = root.pending
            root.pending = ""
            if (why === "dns") {
                root.toast(ok ? "DNS cache flushed" : (err || "DNS flush failed"), ok)
                root.desktopNotify("DNS", ok ? "Cache flushed" : (err || "Flush failed"))
            } else if (why === "ip") {
                root.toast(ok ? "IP refreshed" : (err || "IP refresh failed"), ok)
                root.desktopNotify("Network", ok ? "IP refreshed" : (err || "IP refresh failed"))
            } else if (why === "forget") {
                root.toast(ok ? "Network removed" : (err || "Could not forget that network"), ok)
                root.desktopNotify("Wi-Fi", ok ? "Saved network removed" : (err || "Could not forget that network"))
            } else if (why === "hidden") {
                if (!ok) {
                    root.toast(err || "Could not join that network", false)
                    root.desktopNotify("Wi-Fi", err || "Could not join that network")
                }
            } else if (why === "scan") {
                if (!ok) {
                    root.toast(err || "Rescan failed", false)
                    root.desktopNotify("Wi-Fi", err || "Rescan failed")
                }
            } else if (!ok && err.length) {
                root.toast(err, false)
                root.desktopNotify("Network", err)
            } else if (ok && msg.length && why.length) {
                root.toast(msg, true)
            }
            refreshSoon.restart()
            root.deviceEpoch++
        }
    }

    // Event stream. Any line means NetworkManager changed something.
    Io.Process {
        id: monitorProcess
        command: ["nmcli", "monitor"]
        running: true
        stdout: Io.SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                if (String(line || "").trim().length)
                    refreshSoon.restart()
            }
        }
        onExited: {
            root._monitorFails++
            if (root._monitorFails <= 4)
                monitorRestart.restart()
        }
        onStarted: root._monitorFails = 0
    }

    Timer {
        id: monitorRestart
        interval: 4000
        repeat: false
        onTriggered: {
            if (!monitorProcess.running)
                monitorProcess.running = true
        }
    }

    // Live rx/tx. Byte counters do not show up on nmcli monitor.
    Timer {
        id: fastTimer
        interval: 1000
        repeat: true
        running: false
        onTriggered: root.refreshStatus(false)
    }

    // Fallback if the monitor dies, and the bar tooltip's speed when closed.
    Timer {
        id: slowTimer
        interval: 8000
        repeat: true
        running: true
        onTriggered: {
            if (!root.popupOpen)
                root.refreshStatus(false)
        }
    }

    Timer {
        id: refreshSoon
        interval: 350
        repeat: false
        onTriggered: root.refreshStatus(false)
    }

    Timer {
        id: scanAfterEnable
        interval: 900
        repeat: false
        onTriggered: {
            if (!root.wifiEnabled)
                return
            root.setScanner(true)
            root.pending = "scan"
            root.runControl(["wifi-rescan"])
        }
    }

    Timer {
        id: toastTimer
        interval: 3600
        repeat: false
        onTriggered: root.toastText = ""
    }

    // Weak notify while the list is open. Networking does not always ping us.
    Timer {
        id: listTick
        interval: 2500
        repeat: true
        running: popupOpen
        onTriggered: {
            root.deviceEpoch++
            root.rebuildLists()
        }
    }

    Component.onCompleted: {
        refreshStatus(true)
        rebuildLists()
    }
}
