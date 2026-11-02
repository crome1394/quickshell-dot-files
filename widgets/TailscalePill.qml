import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io as Io
import "../components"

// =============================================================================
// TailscalePill.qml — Tailscale status pill
// =============================================================================
//
// Left click opens the panel. Right click runs `tailscale up` or `down`.
// Machines come from `tailscale status --json`. Local switches come from
// `tailscale debug prefs` and are changed with `tailscale set`.
// Copy uses wl-copy. Taildrop send uses zenity and `tailscale file cp`.
// Incoming files are left to `tailscale file get` — this pill does not run a receive loop.
// =============================================================================

Rectangle {
    id: root

    required property var bar
    required property Item barBg

    readonly property real _ws: (bar.widgetScale ? bar.widgetScale("tailscale") : 1.0)
    Layout.preferredWidth: Math.round(42 * _ws)
    Layout.preferredHeight: bar.pillHeight
    Layout.alignment: Qt.AlignVCenter
    clip: false

    property string backendState: ""
    property bool running: false
    property bool needsLogin: false
    property bool cliMissing: false
    property bool fileSharing: false
    property string tailnetName: ""
    property string healthMessage: ""
    property string authUrl: ""
    property string selfName: ""
    property string selfDns: ""
    property string selfIp: ""
    property string selfUserId: ""
    property bool acceptRoutes: false
    property bool acceptDns: false
    property bool shieldsUp: false
    property bool advertiseExit: false
    property bool exitAllowLan: false
    property bool statefulFiltering: false
    property string routesText: ""
    property string _routesSaved: ""
    property bool _routesEditing: false
    property string _prefsFp: ""
    property var listRows: []
    property var accounts: []
    property int selectedIndex: 0
    property int uiTick: 0
    property string flashText: ""
    property string pendingSendTarget: ""
    property string _fp: ""

    readonly property bool showSlash: !running && !needsLogin && backendState !== "Starting"

    onVisibleChanged: {
        if (!visible && tsPopup)
            tsPopup.visible = false
    }

    function stateLabel() {
        if (cliMissing)
            return "Not installed"
        if (needsLogin)
            return "Needs login"
        if (running)
            return "Connected"
        if (backendState === "Starting")
            return "Starting"
        if (backendState === "Stopped" || !backendState.length)
            return "Off"
        return backendState
    }

    function toggleLabel() {
        if (cliMissing)
            return "Unavailable"
        if (running)
            return "Turn off"
        if (needsLogin)
            return "Log in"
        return "Turn on"
    }

    function cleanDns(name) {
        var value = String(name || "")
        if (value.length && value.charAt(value.length - 1) === ".")
            return value.slice(0, value.length - 1)
        return value
    }

    function displayName(host, dns) {
        var h = String(host || "")
        if (h.length && h.toLowerCase() !== "localhost")
            return h
        var clean = cleanDns(dns)
        if (!clean.length)
            return h.length ? h : "Unknown"
        var dot = clean.indexOf(".")
        return dot > 0 ? clean.substring(0, dot) : clean
    }

    function firstIp(ips) {
        var v4 = ""
        var v6 = ""
        var any = ""
        if (!ips || !ips.length)
            return ""
        for (var i = 0; i < ips.length; i++) {
            var ip = String(ips[i] || "")
            if (!ip.length)
                continue
            if (!any.length)
                any = ip
            if (ip.indexOf(":") < 0) {
                if (!v4.length)
                    v4 = ip
                if (ip.indexOf("100.") === 0)
                    return ip
            } else if (!v6.length && ip.toLowerCase().indexOf("fd7a:115c:a1e0:") === 0) {
                v6 = ip
            }
        }
        if (v4.length)
            return v4
        if (v6.length)
            return v6
        return any
    }

    function isMullvad(peer) {
        var suf = ".mullvad.ts.net"
        var dns = cleanDns(peer && peer.DNSName).toLowerCase()
        var host = String((peer && peer.HostName) || "").toLowerCase()
        if (dns.length > suf.length && dns.lastIndexOf(suf) === dns.length - suf.length)
            return true
        return host.length > suf.length && host.lastIndexOf(suf) === host.length - suf.length
    }

    function fileShareOn(self) {
        var cap = "https://tailscale.com/cap/file-sharing"
        var map = self && self.CapMap
        if (map && map[cap] !== undefined)
            return true
        var caps = (self && self.Capabilities) || []
        for (var i = 0; i < caps.length; i++) {
            if (String(caps[i]) === cap)
                return true
        }
        return false
    }

    function taildropOk(peer, userId) {
        if (peer && typeof peer.TaildropTarget === "number")
            return peer.TaildropTarget === 1
        var owner = String((peer && peer.UserID) || "")
        return owner.length > 0 && owner === String(userId || "")
    }

    function byName(a, b) {
        var ao = a.online ? 0 : 1
        var bo = b.online ? 0 : 1
        if (ao !== bo)
            return ao - bo
        var an = String(a.name || "").toLowerCase()
        var bn = String(b.name || "").toLowerCase()
        if (an < bn)
            return -1
        if (an > bn)
            return 1
        return 0
    }

    function peerRecord(id, peer, kind, userId) {
        return {
            kind: kind,
            id: String(id || ""),
            name: displayName(peer.HostName, peer.DNSName),
            dns: cleanDns(peer.DNSName),
            ip: firstIp(peer.TailscaleIPs || []),
            online: peer.Online === true,
            exitNode: peer.ExitNode === true,
            exitOption: peer.ExitNodeOption === true,
            taildrop: taildropOk(peer, userId)
        }
    }

    function rowCount() {
        return 1 + (listRows ? listRows.length : 0)
    }

    function rowAt(i) {
        if (i <= 0) {
            return {
                kind: "self",
                name: selfName.length ? selfName : "This machine",
                dns: selfDns,
                ip: selfIp,
                online: running,
                exitNode: false,
                exitOption: false,
                taildrop: false
            }
        }
        if (!listRows || i - 1 >= listRows.length)
            return null
        return listRows[i - 1]
    }

    function hasActiveExit() {
        void uiTick
        var rows = listRows || []
        for (var i = 0; i < rows.length; i++) {
            if (rows[i] && rows[i].exitNode)
                return true
        }
        return false
    }

    function canSend(row) {
        return !!(row && row.kind === "peer" && row.online && row.taildrop && fileSharing && row.ip && row.ip.length)
    }

    function actionButtons() {
        void uiTick
        var row = rowAt(selectedIndex)
        var out = [
            { id: "ip", label: "Copy IP" },
            { id: "name", label: "Copy name" },
            { id: "dns", label: "Copy DNS" }
        ]
        if (canSend(row))
            out.push({ id: "send", label: "Send" })
        if (row && row.exitOption && !row.exitNode && row.kind !== "self" && row.kind !== "header")
            out.push({ id: "exit", label: "Use as exit" })
        if (hasActiveExit())
            out.push({ id: "clearExit", label: "Clear exit" })
        return out
    }

    function flash(msg) {
        flashText = String(msg || "")
        if (flashText.length)
            flashTimer.restart()
        else
            flashTimer.stop()
    }

    function applyStatus(raw) {
        var data = null
        try {
            data = JSON.parse(raw)
        } catch (e) {
            return
        }
        var state = String(data.BackendState || "")
        var self = data.Self || {}
        var userId = String(self.UserID || "")
        var nextName = displayName(self.HostName, self.DNSName)
        var nextDns = cleanDns(self.DNSName)
        var nextIp = firstIp(self.TailscaleIPs || data.TailscaleIPs || [])
        var share = fileShareOn(self)
        var tailnet = ""
        var ct = data.CurrentTailnet
        if (ct && ct.Name)
            tailnet = String(ct.Name)
        else if (data.MagicDNSSuffix)
            tailnet = String(data.MagicDNSSuffix)
        var health = ""
        if (data.Health && data.Health.length)
            health = String(data.Health[0] || "")
        var auth = String(data.AuthURL || "")
        var peers = []
        var exits = []
        var rawPeers = data.Peer || {}
        for (var id in rawPeers) {
            var peer = rawPeers[id] || {}
            if (isMullvad(peer)) {
                if (peer.ExitNodeOption === true || peer.ExitNode === true)
                    exits.push(peerRecord(id, peer, "exit", userId))
                continue
            }
            peers.push(peerRecord(id, peer, "peer", userId))
        }
        peers.sort(byName)
        exits.sort(byName)
        var next = []
        if (peers.length) {
            next.push({ kind: "header", name: "Machines" })
            for (var i = 0; i < peers.length; i++)
                next.push(peers[i])
        }
        if (exits.length) {
            next.push({ kind: "header", name: "Exit nodes" })
            for (var j = 0; j < exits.length; j++)
                next.push(exits[j])
        }
        var parts = [state, nextName, nextIp, nextDns, share ? "1" : "0", tailnet, health, auth]
        for (var k = 0; k < next.length; k++) {
            var r = next[k]
            parts.push([r.kind, r.name, r.ip, r.dns, r.online ? "1" : "0", r.exitNode ? "e" : "", r.exitOption ? "o" : "", r.taildrop ? "t" : ""].join(":"))
        }
        var fp = parts.join("|")
        if (fp === _fp)
            return
        _fp = fp
        backendState = state
        running = state === "Running"
        needsLogin = state === "NeedsLogin"
        cliMissing = false
        fileSharing = share
        tailnetName = tailnet
        healthMessage = health
        authUrl = auth
        selfName = nextName
        selfDns = nextDns
        selfIp = nextIp
        selfUserId = userId
        listRows = next
        if (selectedIndex >= rowCount())
            selectedIndex = Math.max(0, rowCount() - 1)
        uiTick++
    }

    function applyAccounts(raw) {
        var parsed = null
        try {
            parsed = JSON.parse(raw)
        } catch (e) {
            return
        }
        var src = parsed
        if (parsed && parsed.accounts)
            src = parsed.accounts
        if (!src || src.length === undefined)
            return
        var next = []
        for (var i = 0; i < src.length; i++) {
            var rawAccount = src[i] || {}
            var id = String(rawAccount.id || rawAccount.ID || "")
            if (!id.length)
                continue
            var label = String(rawAccount.nickname || rawAccount.Nickname || rawAccount.name || rawAccount.Name || "")
            if (!label.length)
                label = String(rawAccount.tailnet || rawAccount.Tailnet || rawAccount.account || rawAccount.Account || id)
            next.push({
                id: id,
                label: label,
                selected: rawAccount.selected === true || rawAccount.Selected === true
            })
        }
        var fp = ""
        for (var j = 0; j < next.length; j++)
            fp += next[j].id + (next[j].selected ? "*" : "") + ";"
        var old = ""
        for (var k = 0; k < accounts.length; k++)
            old += accounts[k].id + (accounts[k].selected ? "*" : "") + ";"
        if (fp === old)
            return
        accounts = next
        uiTick++
    }

    function refreshStatus(force) {
        if (statusProcess.running) {
            if (!force)
                return
            statusProcess.running = false
        }
        statusProcess.command = ["tailscale", "status", "--json"]
        statusProcess.running = true
    }

    function refreshAccounts() {
        if (accountsProcess.running)
            return
        accountsProcess.command = ["tailscale", "switch", "--list", "--json"]
        accountsProcess.running = true
    }

    function refreshPrefs() {
        if (prefsProcess.running)
            return
        prefsProcess.command = ["tailscale", "debug", "prefs"]
        prefsProcess.running = true
    }

    function refreshAll(force) {
        refreshStatus(!!force)
        refreshAccounts()
        refreshPrefs()
    }

    function formatRouteList(routes) {
        if (!routes || routes.length === undefined)
            return ""
        var parts = []
        for (var i = 0; i < routes.length; i++) {
            var bit = String(routes[i] || "").trim()
            if (bit.length)
                parts.push(bit)
        }
        return parts.join(", ")
    }

    function applyPrefs(raw) {
        var data = null
        try {
            data = JSON.parse(raw)
        } catch (e) {
            return
        }
        var nextRoutes = formatRouteList(data.AdvertiseRoutes)
        var nextRoutesOn = data.RouteAll === true
        var nextDns = data.CorpDNS === true
        var nextShields = data.ShieldsUp === true
        var nextExit = data.AdvertiseExitNode === true
        var nextLan = data.ExitNodeAllowLANAccess === true
        var nextFilter = data.NoStatefulFiltering !== true
        var fp = [nextRoutesOn, nextDns, nextShields, nextExit, nextLan, nextFilter, nextRoutes].join("|")
        if (fp === _prefsFp)
            return
        _prefsFp = fp
        acceptRoutes = nextRoutesOn
        acceptDns = nextDns
        shieldsUp = nextShields
        advertiseExit = nextExit
        exitAllowLan = nextLan
        statefulFiltering = nextFilter
        _routesSaved = nextRoutes
        if (!_routesEditing) {
            routesText = nextRoutes
            if (routesInput)
                routesInput.text = nextRoutes
        }
        uiTick++
    }

    function prefSwitches() {
        void uiTick
        return [
            {
                id: "routes",
                label: "Accept Routes",
                on: acceptRoutes,
                hint: "Install subnet routes advertised by other machines. They apply while Tailscale is running."
            },
            {
                id: "dns",
                label: "Accept DNS",
                on: acceptDns,
                hint: "Use this tailnet's MagicDNS and split DNS on this machine."
            },
            {
                id: "shields",
                label: "Shields Up",
                on: shieldsUp,
                hint: "Block incoming connections, including Taildrop sends to this machine."
            },
            {
                id: "lan",
                label: "Allow LAN access",
                on: exitAllowLan,
                hint: "Reach the local network while an exit node is selected."
            },
            {
                id: "exit",
                label: "Advertise as Exit Node",
                on: advertiseExit,
                hint: "Offer this machine as an exit node. Others can use it after you approve it in the admin console."
            },
            {
                id: "filter",
                label: "Stateful filtering",
                on: statefulFiltering,
                hint: "Filter packets forwarded for advertised routes and exit-node traffic."
            }
        ]
    }

    function togglePref(id) {
        var flag = ""
        var next = false
        if (id === "routes") {
            flag = "--accept-routes"
            next = !acceptRoutes
        } else if (id === "dns") {
            flag = "--accept-dns"
            next = !acceptDns
        } else if (id === "shields") {
            flag = "--shields-up"
            next = !shieldsUp
        } else if (id === "lan") {
            flag = "--exit-node-allow-lan-access"
            next = !exitAllowLan
        } else if (id === "exit") {
            flag = "--advertise-exit-node"
            next = !advertiseExit
        } else if (id === "filter") {
            flag = "--stateful-filtering"
            next = !statefulFiltering
        } else {
            return
        }
        var arg = next ? flag : (flag + "=false")
        if (!runActionCommand(["tailscale", "set", arg]))
            return
        if (id === "routes")
            acceptRoutes = next
        else if (id === "dns")
            acceptDns = next
        else if (id === "shields")
            shieldsUp = next
        else if (id === "lan")
            exitAllowLan = next
        else if (id === "exit")
            advertiseExit = next
        else if (id === "filter")
            statefulFiltering = next
        uiTick++
        flash(next ? "Turning on…" : "Turning off…")
    }

    function normalizeRoutes(raw) {
        var parts = String(raw || "").split(",")
        var out = []
        for (var i = 0; i < parts.length; i++) {
            var bit = parts[i].trim()
            if (!bit.length)
                continue
            if (bit.indexOf("/") < 1 || bit.indexOf(" ") >= 0)
                return null
            out.push(bit)
        }
        return out.join(",")
    }

    function applyRoutes() {
        var norm = normalizeRoutes(routesText)
        if (norm === null) {
            flash("Use subnets such as 192.168.1.0/24")
            return
        }
        if (!runActionCommand(["tailscale", "set", "--advertise-routes=" + norm]))
            return
        _routesEditing = false
        flash(norm.length ? "Offering routes…" : "Clearing routes…")
    }

    function clearRoutes() {
        routesText = ""
        if (routesInput)
            routesInput.text = ""
        applyRoutes()
    }

    function runActionCommand(cmd) {
        if (actionProcess.running) {
            flash("Still working…")
            return false
        }
        actionProcess.command = cmd
        actionProcess.running = true
        return true
    }

    function toggleUp() {
        if (cliMissing) {
            flash("tailscale is not installed")
            return
        }
        if (running) {
            if (runActionCommand(["tailscale", "down"]))
                flash("Turning off…")
            return
        }
        if (authUrl.length)
            Quickshell.execDetached(["xdg-open", authUrl])
        if (runActionCommand(["tailscale", "up"]))
            flash(needsLogin ? "Opening login…" : "Turning on…")
    }

    function copyText(text, label) {
        var t = String(text || "")
        if (!t.length) {
            flash("No " + label + " to copy")
            return
        }
        Quickshell.execDetached([
            "sh", "-c",
            'printf "%s" "$1" | wl-copy',
            "wl-copy",
            t
        ])
        flash("Copied " + label)
    }

    function copySelected(which) {
        var row = rowAt(selectedIndex)
        if (!row || row.kind === "header")
            return
        if (which === "name")
            copyText(row.name, "name")
        else if (which === "dns")
            copyText(row.dns, "DNS name")
        else
            copyText(row.ip, "IP")
    }

    function sendToSelected() {
        var row = rowAt(selectedIndex)
        if (!canSend(row)) {
            flash(fileSharing ? "That machine can't receive files" : "File sharing is off for this tailnet")
            return
        }
        if (pickProcess.running || actionProcess.running)
            return
        pendingSendTarget = row.ip
        pickProcess.command = ["zenity", "--file-selection", "--multiple", "--separator=\n", "--title=Send with Taildrop"]
        pickProcess.running = true
    }

    function useSelectedExit() {
        var row = rowAt(selectedIndex)
        if (!row || !(row.ip && row.ip.length) && !(row.name && row.name.length))
            return
        var target = (row.ip && row.ip.length) ? row.ip : row.name
        if (runActionCommand(["tailscale", "set", "--exit-node=" + target]))
            flash("Setting exit node…")
    }

    function clearExit() {
        if (runActionCommand(["tailscale", "set", "--exit-node="]))
            flash("Clearing exit node…")
    }

    function runButton(id) {
        if (id === "ip")
            copySelected("ip")
        else if (id === "name")
            copySelected("name")
        else if (id === "dns")
            copySelected("dns")
        else if (id === "send")
            sendToSelected()
        else if (id === "exit")
            useSelectedExit()
        else if (id === "clearExit")
            clearExit()
    }

    function switchAccount(id) {
        var accountId = String(id || "")
        if (!accountId.length)
            return
        if (runActionCommand(["tailscale", "switch", accountId]))
            flash("Switching account…")
    }

    function setSelected(i) {
        var max = Math.max(0, rowCount() - 1)
        if (i < 0)
            i = 0
        if (i > max)
            i = max
        var row = rowAt(i)
        if (row && row.kind === "header")
            return
        if (selectedIndex === i)
            return
        selectedIndex = i
        uiTick++
        Qt.callLater(revealSelection)
    }

    function moveSel(delta) {
        var n = selectedIndex
        var guard = 0
        while (guard < 40) {
            n += delta
            if (n < 0 || n >= rowCount())
                return
            var row = rowAt(n)
            guard++
            if (!row || row.kind === "header")
                continue
            setSelected(n)
            return
        }
    }

    function revealSelection() {
        if (selectedIndex <= 0 || !listRepeater)
            return
        var item = listRepeater.itemAt(selectedIndex - 1)
        if (!item)
            return
        var y = item.y
        var h = item.height
        if (y < listFlick.contentY)
            listFlick.contentY = Math.max(0, y - 4)
        else if (y + h > listFlick.contentY + listFlick.height)
            listFlick.contentY = Math.max(0, y + h - listFlick.height + 4)
    }

    function handleKey(event) {
        var t = event.text || ""
        if (event.key === Qt.Key_Escape) {
            hidePanel()
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Up || t === "k" || t === "K") {
            moveSel(-1)
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Down || t === "j" || t === "J") {
            moveSel(1)
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space || t === " ") {
            copySelected("ip")
            event.accepted = true
            return
        }
        if (t === "c" || t === "C") {
            copySelected("ip")
            event.accepted = true
            return
        }
        if (t === "n" || t === "N") {
            copySelected("name")
            event.accepted = true
            return
        }
        if (t === "d" || t === "D") {
            copySelected("dns")
            event.accepted = true
            return
        }
        if (t === "s" || t === "S") {
            sendToSelected()
            event.accepted = true
            return
        }
        if (t === "t" || t === "T") {
            toggleUp()
            event.accepted = true
            return
        }
        if (t === "r" || t === "R") {
            refreshAll(true)
            flash("Refreshing…")
            event.accepted = true
            return
        }
    }

    function showPanel() {
        if (tsPopup.visible) {
            hidePanel()
            return
        }
        var popupW = tsPopup.implicitWidth
        var popupH = tsPopup.implicitHeight
        if (typeof bar.placePopup === "function") {
            bar.placePopup(tsPopup, root, popupW, popupH, 6, root.width / 2)
        } else if (barBg) {
            var pos = root.mapToItem(barBg, root.width / 2, 0)
            var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920
            var targetX = bar.sideMargin + pos.x - (popupW / 2)
            tsPopup.anchor.rect.x = Math.max(12, Math.min(targetX, screenW - popupW - 12))
            tsPopup.anchor.rect.y = bar.popupAnchorY(popupH, 6, root)
        }
        tsPopup.visible = true
    }

    function hidePanel() {
        tsPopup.visible = false
    }

    DockFace {
        id: dockFx
        bar: root.bar
        host: root
        hovered: tsMouse.containsMouse
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
    color: tsMouse.containsMouse || tsPopup.visible ? bar.glassHover : bar.pillBg
    border.width: bar.controlBorderWidth
    border.color: tsMouse.containsMouse || tsPopup.visible
                  ? bar.accent
                  : (running ? Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.7) : bar.pillBorder)

    Item {
        id: mark
        anchors.centerIn: parent
        width: Math.max(14, Math.round((bar.iconSizePillLarge || 18) * _ws * 0.92))
        height: width
        readonly property color markColor: {
            if (root.needsLogin)
                return "#f0d060"
            if (root.running)
                return (tsMouse.containsMouse || tsPopup.visible)
                        ? bar.accent
                        : (bar.iconColor !== undefined ? bar.iconColor : bar.text)
            return bar.subtext
        }
        readonly property real dot: Math.max(2, width * 0.22)
        readonly property real mid: (width - dot) / 2
        readonly property real end: width - dot

        Repeater {
            model: 9
            delegate: Rectangle {
                required property int index
                readonly property int col: index % 3
                readonly property int rowi: Math.floor(index / 3)
                x: col === 0 ? 0 : (col === 1 ? mark.mid : mark.end)
                y: rowi === 0 ? 0 : (rowi === 1 ? mark.mid : mark.end)
                width: mark.dot
                height: mark.dot
                radius: width / 2
                color: mark.markColor
                opacity: (rowi === 1 || (rowi === 2 && col === 1)) ? 1 : 0.24
            }
        }

        Rectangle {
            visible: root.showSlash
            anchors.centerIn: parent
            width: parent.width * 1.15
            height: Math.max(2, parent.height * 0.12)
            radius: height / 2
            color: mark.markColor
            rotation: -45
        }

        Rectangle {
            visible: root.needsLogin
            width: Math.max(7, parent.width * 0.42)
            height: width
            radius: width / 2
            color: "#f0d060"
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            Text {
                anchors.centerIn: parent
                text: "!"
                color: "#1a1408"
                font.pixelSize: Math.max(6, parent.height * 0.72)
                font.bold: true
                font.family: bar.fontFamily
            }
        }
    }

    MouseArea {
        id: tsMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
            dockFx.jump()
            if (mouse.button === Qt.RightButton)
                root.toggleUp()
            else
                root.showPanel()
        }
        BarToolTip {
            bar: root.bar
            widgetId: "tailscale"
            visible: tsMouse.containsMouse && !tsPopup.visible
            text: "Tailscale · " + root.stateLabel() + " · Left: panel · Right: toggle"
            anchorItem: tsMouse
        }
    }

    Timer {
        interval: tsPopup.visible ? 3000 : 8000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: {
            root.refreshStatus(false)
            if (tsPopup.visible)
                root.refreshPrefs()
        }
    }

    Timer {
        id: flashTimer
        interval: 2600
        onTriggered: root.flashText = ""
    }

    Timer {
        id: refreshSoon
        interval: 700
        onTriggered: root.refreshAll(true)
    }

    Io.Process {
        id: statusProcess
        running: false
        stdout: Io.StdioCollector { id: statusOut }
        stderr: Io.StdioCollector { id: statusErr }
        onExited: (code) => {
            var text = (statusOut.text || "").trim()
            if (text.length && text.charAt(0) === "{") {
                root.applyStatus(text)
                return
            }
            var err = (statusErr.text || "").trim()
            if (code !== 0 && (err.indexOf("not found") >= 0 || err.indexOf("No such file") >= 0)) {
                root.cliMissing = true
                root.running = false
                root.needsLogin = false
                root.backendState = ""
                root._fp = ""
                root.uiTick++
            }
        }
    }

    Io.Process {
        id: prefsProcess
        running: false
        stdout: Io.StdioCollector { id: prefsOut }
        onExited: (code) => {
            var text = (prefsOut.text || "").trim()
            if (code !== 0 || !text.length || text.charAt(0) !== "{")
                return
            root.applyPrefs(text)
        }
    }

    Io.Process {
        id: accountsProcess
        running: false
        stdout: Io.StdioCollector { id: accountsOut }
        onExited: (code) => {
            var text = (accountsOut.text || "").trim()
            if (!text.length || (text.charAt(0) !== "[" && text.charAt(0) !== "{"))
                return
            root.applyAccounts(text)
        }
    }

    Io.Process {
        id: actionProcess
        running: false
        stdout: Io.StdioCollector { id: actionOut }
        stderr: Io.StdioCollector { id: actionErr }
        onExited: (code) => {
            if (code !== 0) {
                var err = (actionErr.text || actionOut.text || "").trim()
                if (err.length > 180)
                    err = err.substring(0, 180)
                root.flash(err.length ? err : ("Command failed (" + code + ")"))
            } else if (root.flashText.indexOf("…") >= 0) {
                root.flash("Done")
            }
            refreshSoon.restart()
            if (tsPopup.visible)
                keyGrab.forceActiveFocus()
        }
    }

    Io.Process {
        id: pickProcess
        running: false
        stdout: Io.StdioCollector { id: pickOut }
        onExited: (code) => {
            if (code !== 0) {
                root.flash("Cancelled")
                if (tsPopup.visible)
                    keyGrab.forceActiveFocus()
                return
            }
            var text = (pickOut.text || "").trim()
            if (!text.length) {
                root.flash("Cancelled")
                return
            }
            var paths = text.split("\n")
            var files = []
            for (var i = 0; i < paths.length; i++) {
                var p = String(paths[i] || "").trim()
                if (p.length)
                    files.push(p)
            }
            if (!files.length || !root.pendingSendTarget.length)
                return
            var cmd = ["tailscale", "file", "cp"].concat(files)
            cmd.push(root.pendingSendTarget + ":")
            if (root.runActionCommand(cmd))
                root.flash("Sending " + files.length + (files.length === 1 ? " file…" : " files…"))
            if (tsPopup.visible)
                keyGrab.forceActiveFocus()
        }
    }

    PopupWindow {
        id: tsPopup
        anchor.window: bar
        implicitWidth: bar.popupTailscaleWidth
        implicitHeight: bar.popupTailscaleHeight
        visible: false
        grabFocus: true
        color: "transparent"
        onVisibleChanged: {
            if (visible) {
                keyGrab.forceActiveFocus()
                root.refreshAll(true)
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: bar.popupRadiusLarge
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
                id: panelCol
                anchors.fill: parent
                anchors.margins: bar.popupSpacingTight
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                            text: "Tailscale"
                            color: bar.text
                            font.pixelSize: bar.popupTitleSize
                            font.bold: true
                            font.family: bar.fontFamily
                        }
                        Text {
                            Layout.fillWidth: true
                            text: {
                                var bits = [root.stateLabel()]
                                if (root.tailnetName.length)
                                    bits.push(root.tailnetName)
                                return bits.join(" · ")
                            }
                            color: root.needsLogin ? "#f0d060" : bar.subtext
                            font.pixelSize: bar.popupHintSize
                            font.family: bar.fontFamily
                            elide: Text.ElideRight
                        }
                    }
                    Rectangle {
                        Layout.preferredWidth: toggleLabel.implicitWidth + 18
                        Layout.preferredHeight: 28
                        radius: bar.buttonRadius
                        color: toggleMa.containsMouse ? bar.popupButtonHoverBg : Qt.rgba(0.10, 0.10, 0.12, 0.6)
                        border.width: bar.controlBorderWidth
                        border.color: root.running ? bar.accent : bar.dividerStrong
                        Text {
                            id: toggleLabel
                            anchors.centerIn: parent
                            text: root.toggleLabel()
                            color: bar.text
                            font.pixelSize: 12
                            font.family: bar.fontFamily
                        }
                        MouseArea {
                            id: toggleMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleUp()
                        }
                    }
                    Rectangle {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        radius: bar.buttonRadius
                        color: refreshMa.containsMouse ? bar.glassHover : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "↻"
                            color: bar.subtext
                            font.pixelSize: 14
                            font.family: bar.fontFamily
                        }
                        MouseArea {
                            id: refreshMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.refreshAll(true)
                                root.flash("Refreshing…")
                            }
                        }
                    }
                    Rectangle {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        radius: bar.buttonRadius
                        color: closeMa.containsMouse ? bar.glassHover : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: bar.subtext
                            font.pixelSize: 13
                            font.family: bar.fontFamily
                        }
                        MouseArea {
                            id: closeMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.hidePanel()
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.healthMessage.length > 0
                    text: root.healthMessage
                    color: "#f0d060"
                    font.pixelSize: bar.popupHintSize
                    font.family: bar.fontFamily
                    wrapMode: Text.WordWrap
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: selfCol.implicitHeight + 12
                    radius: bar.buttonRadius
                    color: root.selectedIndex === 0 ? bar.popupButtonHoverBg : Qt.rgba(0.08, 0.10, 0.14, 0.55)
                    border.width: 1
                    border.color: root.selectedIndex === 0 ? bar.accent : bar.dividerStrong
                    ColumnLayout {
                        id: selfCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 2
                        Text {
                            text: "This machine"
                            color: bar.subtext
                            font.pixelSize: bar.popupHintSize
                            font.family: bar.fontFamily
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.selfName.length ? root.selfName : "This machine"
                            color: bar.text
                            font.pixelSize: bar.popupSectionSize
                            font.bold: true
                            font.family: bar.fontFamily
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.selfIp.length ? root.selfIp : (root.running ? "No Tailscale IP" : "Off")
                            color: bar.text
                            font.pixelSize: 12
                            font.family: bar.fontMono
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: root.selfDns.length > 0
                            text: root.selfDns
                            color: bar.subtext
                            font.pixelSize: bar.popupHintSize
                            font.family: bar.fontFamily
                            elide: Text.ElideRight
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.setSelected(0)
                    }
                }

                ColumnLayout {
                    visible: !root.cliMissing
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "This node"
                        color: bar.text
                        font.pixelSize: 13
                        font.bold: true
                        font.family: bar.fontFamily
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: 14

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.minimumWidth: 0
                            Layout.alignment: Qt.AlignTop
                            spacing: 2
                            Repeater {
                                model: root.prefSwitches().slice(0, 3)
                                delegate: Item {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 26
                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 8
                                        Rectangle {
                                            Layout.preferredWidth: 16
                                            Layout.preferredHeight: 16
                                            Layout.alignment: Qt.AlignVCenter
                                            radius: 4
                                            color: modelData.on ? bar.accent : "transparent"
                                            border.width: 1
                                            border.color: modelData.on ? bar.accent : bar.dividerStrong
                                            Text {
                                                anchors.centerIn: parent
                                                visible: modelData.on
                                                text: "✓"
                                                color: bar.bg || "#111418"
                                                font.pixelSize: 11
                                                font.bold: true
                                                font.family: bar.fontFamily
                                            }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.label
                                            color: bar.text
                                            font.pixelSize: 12
                                            font.family: bar.fontFamily
                                            elide: Text.ElideRight
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }
                                    MouseArea {
                                        id: prefMaLeft
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.togglePref(modelData.id)
                                        BarToolTip {
                                            bar: root.bar
                                            widgetId: "tailscale"
                                            preferSide: "above"
                                            visible: prefMaLeft.containsMouse
                                            text: modelData.hint
                                            anchorItem: prefMaLeft
                                        }
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.minimumWidth: 0
                            Layout.alignment: Qt.AlignTop
                            spacing: 2
                            Repeater {
                                model: root.prefSwitches().slice(3)
                                delegate: Item {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 26
                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 8
                                        Rectangle {
                                            Layout.preferredWidth: 16
                                            Layout.preferredHeight: 16
                                            Layout.alignment: Qt.AlignVCenter
                                            radius: 4
                                            color: modelData.on ? bar.accent : "transparent"
                                            border.width: 1
                                            border.color: modelData.on ? bar.accent : bar.dividerStrong
                                            Text {
                                                anchors.centerIn: parent
                                                visible: modelData.on
                                                text: "✓"
                                                color: bar.bg || "#111418"
                                                font.pixelSize: 11
                                                font.bold: true
                                                font.family: bar.fontFamily
                                            }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.label
                                            color: bar.text
                                            font.pixelSize: 12
                                            font.family: bar.fontFamily
                                            elide: Text.ElideRight
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }
                                    MouseArea {
                                        id: prefMaRight
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.togglePref(modelData.id)
                                        BarToolTip {
                                            bar: root.bar
                                            widgetId: "tailscale"
                                            preferSide: "above"
                                            visible: prefMaRight.containsMouse
                                            text: modelData.hint
                                            anchorItem: prefMaRight
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Advertise routes"
                        color: bar.text
                        font.pixelSize: 12
                        font.bold: true
                        font.family: bar.fontFamily
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 30
                            radius: bar.buttonRadius
                            color: Qt.rgba(0, 0, 0, 0.22)
                            border.width: 1
                            border.color: routesInput.activeFocus ? bar.accent : bar.dividerStrong
                            TextInput {
                                id: routesInput
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                verticalAlignment: TextInput.AlignVCenter
                                color: bar.text
                                font.pixelSize: 12
                                font.family: bar.fontMono
                                clip: true
                                selectByMouse: true
                                selectedTextColor: bar.bg || "#111418"
                                selectionColor: bar.accent
                                onTextEdited: root.routesText = text
                                onActiveFocusChanged: root._routesEditing = activeFocus
                                onAccepted: root.applyRoutes()
                                Keys.onEscapePressed: (event) => {
                                    focus = false
                                    event.accepted = true
                                }
                            }
                            Text {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                verticalAlignment: Text.AlignVCenter
                                visible: !routesInput.text.length && !routesInput.activeFocus
                                text: "192.168.1.0/24, 10.0.0.0/24"
                                color: bar.subtext
                                font.pixelSize: 12
                                font.family: bar.fontMono
                            }
                        }
                        Rectangle {
                            Layout.preferredWidth: routesApplyLabel.implicitWidth + 16
                            Layout.preferredHeight: 30
                            radius: bar.buttonRadius
                            color: routesApplyMa.containsMouse ? bar.popupButtonHoverBg : Qt.rgba(0.10, 0.10, 0.12, 0.6)
                            border.width: 1
                            border.color: bar.dividerStrong
                            Text {
                                id: routesApplyLabel
                                anchors.centerIn: parent
                                text: "Apply"
                                color: bar.text
                                font.pixelSize: 11
                                font.family: bar.fontFamily
                            }
                            MouseArea {
                                id: routesApplyMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.applyRoutes()
                            }
                        }
                        Rectangle {
                            Layout.preferredWidth: routesClearLabel.implicitWidth + 16
                            Layout.preferredHeight: 30
                            radius: bar.buttonRadius
                            color: routesClearMa.containsMouse ? bar.popupButtonHoverBg : Qt.rgba(0.10, 0.10, 0.12, 0.6)
                            border.width: 1
                            border.color: bar.dividerStrong
                            Text {
                                id: routesClearLabel
                                anchors.centerIn: parent
                                text: "Clear"
                                color: bar.text
                                font.pixelSize: 11
                                font.family: bar.fontFamily
                            }
                            MouseArea {
                                id: routesClearMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.clearRoutes()
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Comma-separated subnets. Approve them in the admin console before other machines can use them."
                        color: bar.subtext
                        font.pixelSize: 10
                        font.family: bar.fontFamily
                        wrapMode: Text.WordWrap
                    }
                }

                Flickable {
                    id: listFlick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 96
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick
                    contentWidth: width
                    contentHeight: listCol.implicitHeight
                    interactive: contentHeight > height + 4

                    ColumnLayout {
                        id: listCol
                        width: listFlick.width
                        spacing: 4

                        Text {
                            visible: root.listRows.length === 0
                            Layout.fillWidth: true
                            text: root.cliMissing
                                  ? "Install tailscale to use this pill."
                                  : (root.running ? "No other machines online." : "Turn Tailscale on to see machines.")
                            color: bar.subtext
                            font.pixelSize: bar.popupHintSize
                            font.family: bar.fontFamily
                            wrapMode: Text.WordWrap
                        }

                        Repeater {
                            id: listRepeater
                            model: root.listRows
                            delegate: ColumnLayout {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                spacing: 0

                                Text {
                                    visible: modelData.kind === "header"
                                    Layout.fillWidth: true
                                    Layout.topMargin: index === 0 ? 0 : 6
                                    text: modelData.name
                                    color: bar.subtext
                                    font.pixelSize: bar.popupHintSize
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }

                                Rectangle {
                                    visible: modelData.kind !== "header"
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 36
                                    radius: bar.buttonRadius
                                    color: {
                                        var on = root.selectedIndex === index + 1
                                        if (on)
                                            return bar.popupButtonHoverBg
                                        if (rowMa.containsMouse)
                                            return Qt.rgba(1, 1, 1, 0.05)
                                        return "transparent"
                                    }
                                    border.width: 1
                                    border.color: root.selectedIndex === index + 1 ? bar.accent : "transparent"
                                    opacity: modelData.online ? 1 : 0.5

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 8
                                        Rectangle {
                                            Layout.preferredWidth: 8
                                            Layout.preferredHeight: 8
                                            radius: 4
                                            color: modelData.online ? "#2ee59a" : bar.subtext
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.name + (modelData.exitNode ? "  · exit" : "")
                                            color: bar.text
                                            font.pixelSize: 12
                                            font.family: bar.fontFamily
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: modelData.ip || ""
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontMono
                                            elide: Text.ElideRight
                                        }
                                    }

                                    MouseArea {
                                        id: rowMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.setSelected(index + 1)
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: actionFlow.implicitHeight
                    visible: actionFlow.implicitHeight > 0
                    Flow {
                        id: actionFlow
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: root.actionButtons()
                            delegate: Rectangle {
                                required property var modelData
                                width: actionLabel.implicitWidth + 16
                                height: 28
                                radius: bar.buttonRadius
                                color: actionMa.containsMouse ? bar.popupButtonHoverBg : Qt.rgba(0.10, 0.10, 0.12, 0.6)
                                border.width: bar.controlBorderWidth
                                border.color: bar.dividerStrong
                                Text {
                                    id: actionLabel
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: bar.text
                                    font.pixelSize: 11
                                    font.family: bar.fontFamily
                                }
                                MouseArea {
                                    id: actionMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.runButton(modelData.id)
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    visible: root.accounts.length > 1
                    implicitHeight: accountFlow.implicitHeight
                    Flow {
                        id: accountFlow
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: root.accounts
                            delegate: Rectangle {
                                required property var modelData
                                width: accountLabel.implicitWidth + 16
                                height: 26
                                radius: bar.buttonRadius
                                color: modelData.selected ? bar.popupButtonHoverBg : Qt.rgba(0.10, 0.10, 0.12, 0.45)
                                border.width: 1
                                border.color: modelData.selected ? bar.accent : bar.dividerStrong
                                Text {
                                    id: accountLabel
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: bar.text
                                    font.pixelSize: 11
                                    font.family: bar.fontFamily
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: !modelData.selected
                                    cursorShape: modelData.selected ? Qt.ArrowCursor : Qt.PointingHandCursor
                                    onClicked: root.switchAccount(modelData.id)
                                }
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.flashText.length > 0
                    text: root.flashText
                    color: bar.text
                    font.pixelSize: bar.popupHintSize
                    font.family: bar.fontFamily
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "j/k move · enter copy IP · c IP · n name · d DNS · s send · t toggle · r refresh · esc close"
                    color: bar.subtext
                    font.pixelSize: 10
                    font.family: bar.fontFamily
                }
            }
        }

        Item {
            id: keyGrab
            anchors.fill: parent
            focus: true
            Keys.onPressed: (event) => root.handleKey(event)
        }
    }
}
