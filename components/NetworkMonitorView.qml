import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io as Io

// Live network monitoring tab — fast metrics via SysMonService, detail via on-demand poller.
Item {
    id: root

    required property var service

    property bool active: false
    property string globalFilter: ""
    property color textColor: "#f0f4fc"
    property color subtextColor: "#a8b4c8"
    property color accentColor: "#00F0E0"
    property color surfaceColor: "#141a24"
    property color overlayColor: "#6e7a90"
    property color okColor: "#2ee59a"
    property color warnColor: "#f0d060"
    property color errorColor: "#FF3D8A"

    readonly property string detailPollerScript: Quickshell.shellPath("scripts/run-network-detail-poller.sh")
    readonly property string privilegedPollerScript: Quickshell.shellPath("scripts/run-network-privileged-poller.sh")
    readonly property bool narrowLayout: width < 520

    readonly property int cardRadius: 6
    readonly property int cardMargin: 6
    readonly property int panelSpacing: 2
    readonly property int panelTailPad: 3
    readonly property int rowHeight: 20
    readonly property int connRowHeight: narrowLayout ? 32 : 20
    readonly property int ifaceRowHeight: 34
    readonly property int headerHeight: 18
    readonly property int sectionSpacing: 3
    readonly property int maxTableRows: 10
    readonly property int graphsMinHeight: 44
    readonly property int wifiPanelHeight: (!!wifiInfo.iface && !!wifiInfo.connected) ? 44 : 0
    readonly property int dnsListMinHeight: 36
    readonly property int firewallScrollHeight: 28
    readonly property int fwRowHeight: root.cardMargin * 2 + 18 + 11 + root.firewallScrollHeight + root.panelTailPad
    readonly property int activeConnTileWidth: narrowLayout ? 136 : 164
    readonly property int connTableViewportHeight: maxTableRows * connRowHeight + Math.max(0, maxTableRows - 1) * 2
    readonly property int procTableViewportHeight: maxTableRows * rowHeight + Math.max(0, maxTableRows - 1) * 2
    readonly property int connPanelHeight: root.cardMargin * 2 + 18 + 10 + root.headerHeight + connTableViewportHeight + root.panelTailPad
    readonly property int procPanelHeight: root.cardMargin * 2 + 18 + 10 + root.headerHeight + procTableViewportHeight + root.panelTailPad
    readonly property int privilegedConnCount: {
        void _privilegedData.timestamp
        return filteredConnections().length
    }
    readonly property int staticColumnsMinHeight: {
        void narrowLayout
        if (narrowLayout) {
            let h = ifacePanelHeight + sectionSpacing + routePanelMinHeight
                + sectionSpacing + latencyPanelHeight + sectionSpacing + dnsPanelMinHeight
            if (wifiPanelHeight > 0)
                h += sectionSpacing + wifiPanelHeight
            return h + sectionSpacing + connPanelHeight + sectionSpacing + procPanelHeight
        }
        const left = ifacePanelHeight + sectionSpacing + routePanelMinHeight
            + sectionSpacing + procPanelHeight
        let right = latencyPanelHeight + sectionSpacing + dnsPanelMinHeight
        if (wifiPanelHeight > 0)
            right += sectionSpacing + wifiPanelHeight
        right += sectionSpacing + connPanelHeight
        return Math.max(left, right)
    }
    readonly property int staticBlockMinHeight: staticColumnsMinHeight
    readonly property int graphsSectionPreferred: Math.max(56, Math.round(height * 0.18))

    readonly property var netData: service && service.data && service.data.network ? service.data.network : ({})
    readonly property var detailData: _detailData
    readonly property var connStats: netData.conn_stats || {}
    readonly property var wifiInfo: netData.wifi || {}

    readonly property int ifacePanelHeight: {
        const tick = service && service.data ? service.data.timestamp : 0
        void tick
        const n = Math.max(1, Math.min(3, filteredInterfaces().length))
        return root.cardMargin * 2 + 18 + root.headerHeight + n * root.ifaceRowHeight + root.panelTailPad
    }
    readonly property int routePanelMinHeight: {
        void _privilegedData.timestamp
        const n = Math.max(1, Math.min(3, filteredRoutes().length))
        return root.cardMargin * 2 + 18 + n * 14 + root.panelTailPad
    }
    readonly property int dnsPanelMinHeight: {
        void detailData.timestamp
        return root.cardMargin * 2 + 18 + 12 + root.dnsListMinHeight + root.panelTailPad
    }
    readonly property int latencyPanelHeight: {
        void _privilegedData.timestamp
        return root.cardMargin * 2 + 18 + root.headerHeight
            + 3 * root.rowHeight + (privilegedLoading || privilegedError.length > 0 ? 12 : root.panelTailPad)
    }

    property var _detailData: ({})
    property bool detailLoading: false
    property string detailError: ""
    property bool _detailHandled: false

    property var _privilegedData: ({ firewall: {}, connections: [], routes: [], latency: {} })
    property bool privilegedLoading: false
    property string privilegedError: ""
    property bool _privilegedHandled: false
    property bool _privilegedFetched: false

    property string copyHint: ""

    property var _flickable: null
    property var _connFlickable: null
    property var _procFlickable: null
    property var _fwFlickable: null

    function filterQuery() {
        return (globalFilter && globalFilter.trim()) ? globalFilter.toLowerCase().trim() : ""
    }

    function formatRate(bytesPerSec) {
        const b = Number(bytesPerSec) || 0
        const kb = b / 1024
        if (kb >= 1024) return (kb / 1024).toFixed(1) + " MB/s"
        return kb.toFixed(1) + " KB/s"
    }

    function formatBytes(n) {
        const b = Number(n) || 0
        if (b >= 1073741824) return (b / 1073741824).toFixed(1) + " GB"
        if (b >= 1048576) return (b / 1048576).toFixed(1) + " MB"
        if (b >= 1024) return (b / 1024).toFixed(1) + " KB"
        return b + " B"
    }

    function formatSpeed(mbps) {
        const m = Number(mbps) || -1
        if (m <= 0) return "—"
        if (m >= 1000) return (m / 1000).toFixed(1) + " Gbps"
        return m + " Mbps"
    }

    function formatLatency(ms) {
        const v = Number(ms)
        if (isNaN(v) || v < 0) return "—"
        return v.toFixed(v >= 10 ? 0 : 1) + " ms"
    }

    function formatLoss(pct) {
        const v = Number(pct)
        if (isNaN(v) || v < 0) return "—"
        return v.toFixed(0) + "%"
    }

    function latencyColor(ms) {
        const v = Number(ms)
        if (isNaN(v) || v < 0) return root.overlayColor
        if (v < 30) return root.okColor
        if (v < 80) return root.warnColor
        return root.errorColor
    }

    function lossColor(pct) {
        const v = Number(pct)
        if (isNaN(v) || v < 0) return root.overlayColor
        if (v === 0) return root.okColor
        if (v < 10) return root.warnColor
        return root.errorColor
    }

    function connStateColor(state) {
        const s = (state || "").toUpperCase()
        if (s === "ESTABLISHED" || s === "ESTAB") return root.okColor
        if (s === "LISTEN") return root.accentColor
        if (s.indexOf("WAIT") !== -1 || s.indexOf("SYN") !== -1) return root.warnColor
        return root.subtextColor
    }

    function stateColor(state) {
        const s = (state || "").toLowerCase()
        if (s === "up" || s === "unknown") return root.okColor
        if (s === "down" || s === "lowerlayerdown") return root.errorColor
        return root.warnColor
    }

    function linkLabel(row) {
        if (!row) return "—"
        if (row.link_up === true) return "up"
        if (row.link_up === false) return "down"
        if (row.carrier === 1) return "up"
        if (row.carrier === 0) return "down"
        return row.state || "—"
    }

    function localIpLabel() {
        if (netData.local_ip) return netData.local_ip
        const iface = netData.iface
        const ifaces = netData.interfaces || []
        for (let i = 0; i < ifaces.length; i++) {
            if (ifaces[i].name === iface && ifaces[i].ipv4)
                return String(ifaces[i].ipv4).split("/")[0]
        }
        return "—"
    }

    function dnsLabel() {
        const dns = netData.dns
        if (!dns || !dns.length) return "—"
        return dns.join("  ·  ")
    }

    function publicIpLabel() {
        if (detailLoading && !detailData.public_ip) return "…"
        if (detailData.public_ip) return detailData.public_ip
        if (detailData.public_ip_error) return detailData.public_ip_error
        return "—"
    }

    function tailscaleActive() {
        const ts = netData.tailscale
        return ts && (ts.active || ts.online || (ts.ips && ts.ips.length > 0))
    }

    function showVpnBar() {
        // Always bool — `||` of loose checks can yield undefined when vpn_iface is missing
        return !!(tailscaleActive() || (netData.vpn_iface && String(netData.vpn_iface).length > 0))
    }

    function detailDns() {
        return detailData.dns || {}
    }

    function filteredInterfaces() {
        const tick = service && service.data ? service.data.timestamp : 0
        void tick
        const list = (netData.interfaces || []).slice(0, 3)
        const q = filterQuery()
        if (!q) return list
        return list.filter(function(row) {
            return (row.name && row.name.toLowerCase().indexOf(q) !== -1)
                || (row.ipv4 && row.ipv4.toLowerCase().indexOf(q) !== -1)
                || (row.ipv6 && row.ipv6.toLowerCase().indexOf(q) !== -1)
                || (row.state && row.state.toLowerCase().indexOf(q) !== -1)
                || (row.mac && row.mac.toLowerCase().indexOf(q) !== -1)
                || (row.wifi_ssid && row.wifi_ssid.toLowerCase().indexOf(q) !== -1)
        })
    }

    function filteredProcBandwidth() {
        const tick = service && service.data ? service.data.timestamp : 0
        void tick
        const list = netData.proc_bandwidth || []
        const q = filterQuery()
        if (!q) return list
        return list.filter(function(row) {
            return row.process && row.process.toLowerCase().indexOf(q) !== -1
        })
    }

    function filteredConnections() {
        void _privilegedData.timestamp
        const list = _privilegedData.connections || []
        const q = filterQuery()
        if (!q) return list
        return list.filter(function(row) {
            return (row.proto && row.proto.toLowerCase().indexOf(q) !== -1)
                || (row.state && row.state.toLowerCase().indexOf(q) !== -1)
                || (row.process && row.process.toLowerCase().indexOf(q) !== -1)
                || (row.local && row.local.toLowerCase().indexOf(q) !== -1)
                || (row.remote && row.remote.toLowerCase().indexOf(q) !== -1)
        })
    }

    function filteredRoutes() {
        void _privilegedData.timestamp
        const routes = _privilegedData.routes || []
        const q = filterQuery()
        if (!q) return routes
        return routes.filter(function(row) {
            return routeLine(row).toLowerCase().indexOf(q) !== -1
        })
    }

    function filteredDnsServers() {
        const servers = detailDns().servers || netData.dns || []
        const q = filterQuery()
        if (!q) return servers
        return servers.filter(function(s) {
            return String(s).toLowerCase().indexOf(q) !== -1
        })
    }

    function filteredFirewallRules() {
        const fw = _privilegedData.firewall || {}
        const rules = fw.rules || []
        const q = filterQuery()
        if (!q) return rules
        return rules.filter(function(line) {
            return String(line).toLowerCase().indexOf(q) !== -1
        })
    }

    function routeLine(row) {
        if (!row) return "—"
        if (typeof row === "string") return row
        let s = row.dst || "default"
        if (row.gateway) s += " via " + row.gateway
        if (row.dev) s += " dev " + row.dev
        if (row.protocol) s += " proto " + row.protocol
        if (row.metric) s += " metric " + row.metric
        if (row.scope) s += " scope " + row.scope
        return s
    }

    function latencyRows() {
        void _privilegedData.timestamp
        const lat = _privilegedData.latency || {}
        return [
            lat.gateway || { label: "Gateway", host: netData.gateway || "" },
            lat.google_dns || { label: "Google DNS", host: "8.8.8.8" },
            lat.cloudflare_dns || { label: "Cloudflare DNS", host: "1.1.1.1" }
        ]
    }

    function ifaceDetailLine(row) {
        const mtu = row.mtu ? ("MTU " + row.mtu) : ""
        const mac = row.mac || ""
        const v4 = row.ipv4 || ""
        const v6 = row.ipv6 || ""
        const addr = v4 && v6 ? v4 + " · " + v6 : (v4 || v6 || "")
        let s = [mtu, mac, addr].filter(function(x) { return x }).join("  ·  ")
        if (row.wifi_ssid) s += (s ? "  ·  " : "") + row.wifi_ssid
        return s || "—"
    }

    function connectionLine(row) {
        if (!row) return ""
        return [
            row.proto || "—",
            row.state || "—",
            row.process || "—",
            row.local || "—",
            row.remote || "—",
            formatBytes(row.bytes_received),
            formatBytes(row.bytes_sent)
        ].join("\t")
    }

    function copyToClipboard(text) {
        if (!text) return
        Quickshell.execDetached([
            "sh", "-c",
            'printf "%s" "$1" | wl-copy',
            "wl-copy",
            text
        ])
        copyHint = "Copied"
        Qt.callLater(function() {
            if (root.copyHint === "Copied") root.copyHint = ""
        }, 1200)
    }

    function openTerminal() {
        Quickshell.execDetached([
            "sh", "-c",
            'exec "${TERMINAL:-kitty}"'
        ])
    }

    function copySummaryText() {
        return [
            "Network Summary",
            "Interface: " + (netData.iface || "—"),
            "Local IP: " + localIpLabel(),
            "Gateway: " + (netData.gateway || "—"),
            "Public IP: " + publicIpLabel(),
            "Download: " + formatRate(netData.rx_rate),
            "Upload: " + formatRate(netData.tx_rate),
            "TCP established: " + (connStats.tcp_established || 0)
        ].join("\n")
    }

    function copyInterfacesText() {
        const lines = ["Interfaces"]
        const rows = filteredInterfaces()
        for (let i = 0; i < rows.length; i++) {
            const r = rows[i]
            lines.push((r.name || "—") + "  " + (r.state || "—") + "  link " + linkLabel(r)
                + "  " + formatSpeed(r.speed_mbps) + "  " + ifaceDetailLine(r))
        }
        return lines.join("\n")
    }

    function copyRoutesText() {
        return ["Routing"].concat(filteredRoutes().map(routeLine)).join("\n")
    }

    function copyDnsText() {
        const d = detailDns()
        const lines = ["DNS Resolution"]
        if (d.current) lines.push("Active: " + d.current + (d.link ? " (" + d.link + ")" : ""))
        const c = d.cache || {}
        if (c.cache_size !== undefined)
            lines.push("Cache: " + c.cache_size + " entries, " + (c.cache_hits || 0) + " hits, " + (c.cache_misses || 0) + " misses")
        filteredDnsServers().forEach(function(s) { lines.push(s) })
        return lines.join("\n")
    }

    function copyLatencyText() {
        const lines = ["Latency & Packet Loss", "Target\tLatency\tLoss"]
        latencyRows().forEach(function(r) {
            lines.push((r.label || "") + " " + (r.host || "") + "\t" + formatLatency(r.ms) + "\t" + formatLoss(r.loss_pct))
        })
        return lines.join("\n")
    }

    function copyProcBwText() {
        const lines = ["Bandwidth by Process", "Process\tDownload\tUpload"]
        filteredProcBandwidth().forEach(function(r) {
            lines.push((r.process || "—") + "\t" + formatRate(r.rx_rate) + "\t" + formatRate(r.tx_rate))
        })
        return lines.join("\n")
    }

    function copyConnectionsText() {
        const lines = ["Connections", "Proto\tState\tProcess\tLocal\tRemote\tRX\tTX"]
        filteredConnections().forEach(function(r) { lines.push(connectionLine(r)) })
        return lines.join("\n")
    }

    function copyFirewallText() {
        const fw = _privilegedData.firewall || {}
        const lines = ["Firewall", fw.summary || "—"]
        if (fw.backend && fw.backend !== "none") lines.push("Backend: " + fw.backend)
        filteredFirewallRules().forEach(function(r) { lines.push(String(r)) })
        return lines.join("\n")
    }

    function copyConnStatsText() {
        const s = connStats
        const lines = [
            "Active Connections (live)",
            "TCP established: " + (s.tcp_established || 0),
            "TCP sockets: " + (s.tcp_total || 0),
            "UDP sockets: " + (s.udp || 0),
            "Total sockets: " + (s.total || 0)
        ]
        if (_privilegedFetched)
            lines.push("Shown in table: " + privilegedConnCount)
        return lines.join("\n")
    }

    function copyVpnText() {
        const ts = netData.tailscale || {}
        const parts = []
        if (netData.vpn_iface) parts.push("Interface: " + netData.vpn_iface)
        if (ts.active) parts.push("Tailscale: active")
        else if (ts.hostname) parts.push("Tailscale: " + ts.hostname)
        if (ts.ips && ts.ips.length) parts.push("IPs: " + ts.ips.join(", "))
        if (ts.using_exit_node) parts.push("Exit: " + (ts.exit_node_name || ts.exit_node || "—"))
        return ["VPN / Tailscale"].concat(parts).join("\n")
    }

    function scrollArea(flick, direction, stepScale) {
        if (!flick || flick.contentHeight <= flick.height + 1) return false
        const maxY = flick.contentHeight - flick.height
        const step = Math.max(28, Math.round(flick.height * (stepScale || 0.85)))
        const newY = Math.max(0, Math.min(maxY, flick.contentY + direction * step))
        if (newY === flick.contentY) return false
        flick.contentY = newY
        root._flickable = flick
        return true
    }

    function refreshDetail() {
        if (detailProcess.running) return
        detailLoading = true
        detailError = ""
        _detailHandled = false
        detailProcess.running = false
        detailProcess.running = true
    }

    function refreshPrivileged() {
        if (privilegedProcess.running) return
        privilegedLoading = true
        privilegedError = ""
        _privilegedHandled = false
        privilegedProcess.running = false
        privilegedProcess.running = true
    }

    // Live metrics (detail poller) — safe for periodic / footer refresh.
    function refresh() {
        refreshDetail()
    }

    function finishDetailPoll() {
        if (_detailHandled) return
        const raw = (detailStdout.text || "").trim()
        if (!raw) return

        _detailHandled = true
        detailLoading = false

        try {
            _detailData = JSON.parse(raw)
            detailError = ""
        } catch (e) {
            detailError = "Failed to parse network detail JSON"
        }
    }

    function finishPrivilegedPoll() {
        if (_privilegedHandled) return
        const raw = (privilegedStdout.text || "").trim()
        if (!raw)
            return

        _privilegedHandled = true
        privilegedLoading = false
        _privilegedFetched = true

        try {
            const parsed = JSON.parse(raw)
            _privilegedData = {
                timestamp: parsed.timestamp || 0,
                latency: parsed.latency || {},
                routes: parsed.routes || [],
                firewall: parsed.firewall || {},
                connections: parsed.connections || []
            }
            privilegedError = ""
        } catch (e) {
            privilegedError = "Failed to parse privileged network JSON"
        }
    }

    function resetScroll() {
        if (_connFlickable) _connFlickable.contentY = 0
        if (_procFlickable) _procFlickable.contentY = 0
        if (_fwFlickable) _fwFlickable.contentY = 0
        root._flickable = _connFlickable || _fwFlickable
    }

    function pageScroll(direction) {
        if (scrollArea(_connFlickable, direction, 0.85)) return
        if (scrollArea(_procFlickable, direction, 0.85)) return
        scrollArea(_fwFlickable, direction, 0.85)
    }

    function lineScroll(direction) {
        if (scrollArea(_connFlickable, direction, 0.14)) return
        if (scrollArea(_procFlickable, direction, 0.14)) return
        scrollArea(_fwFlickable, direction, 0.14)
    }

    function suspendBackgroundWork() {
        if (detailProcess.running)
            detailProcess.running = false
        if (privilegedProcess.running)
            privilegedProcess.running = false
        detailLoading = false
        privilegedLoading = false
    }

    onActiveChanged: {
        if (active) {
            refreshDetail()
            refreshPrivileged()
        } else {
            suspendBackgroundWork()
            _privilegedFetched = false
        }
    }

    // Section title row + optional copy chip
    component SectionBar: RowLayout {
        property string title: ""
        property string copyPayload: ""
        property color titleColor: root.accentColor
        property bool showRefresh: false
        property bool refreshBusy: false
        signal refreshClicked()
        Layout.fillWidth: true
        spacing: 4

        Text {
            text: title
            color: titleColor
            font.pixelSize: 10
            font.bold: true
            font.family: "monospace"
        }
        Item { Layout.fillWidth: true }
        Rectangle {
            visible: showRefresh
            width: refreshMa.containsMouse ? 58 : 54
            height: 18
            radius: 4
            color: refreshMa.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.12)
            opacity: refreshBusy ? 0.55 : 1
            Text {
                anchors.centerIn: parent
                text: refreshBusy ? "…" : "Refresh"
                color: root.accentColor
                font.pixelSize: 9
                font.family: "monospace"
            }
            MouseArea {
                id: refreshMa
                anchors.fill: parent
                hoverEnabled: true
                enabled: !refreshBusy
                cursorShape: Qt.PointingHandCursor
                onClicked: refreshClicked()
            }
        }
        Rectangle {
            visible: copyPayload.length > 0
            width: 40
            height: 18
            radius: 4
            color: copyMa.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.12)
            Text {
                anchors.centerIn: parent
                text: "Copy"
                color: root.accentColor
                font.pixelSize: 9
                font.family: "monospace"
            }
            MouseArea {
                id: copyMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.copyToClipboard(copyPayload)
            }
        }
    }

    Io.Process {
        id: detailProcess
        command: [root.detailPollerScript]
        running: false
        stdout: Io.StdioCollector {
            id: detailStdout
            onStreamFinished: root.finishDetailPoll()
        }
        onExited: Qt.callLater(function() {
            root.finishDetailPoll()
            if (!root._detailHandled) {
                root._detailHandled = true
                root.detailLoading = false
                if (!(detailStdout.text || "").trim())
                    root.detailError = "Empty response from network detail poller"
            }
        })
    }

    Io.Process {
        id: privilegedProcess
        command: [root.privilegedPollerScript]
        running: false
        stdout: Io.StdioCollector {
            id: privilegedStdout
            onStreamFinished: root.finishPrivilegedPoll()
        }
        onExited: Qt.callLater(function() {
            root.finishPrivilegedPoll()
            if (!root._privilegedHandled) {
                root._privilegedHandled = true
                root.privilegedLoading = false
                if (!(privilegedStdout.text || "").trim())
                    root.privilegedError = "Empty response from privileged network poller"
            }
        })
    }

    ColumnLayout {
        id: contentCol
        anchors.fill: parent
        spacing: root.sectionSpacing

            property int _netTick: service ? service.netRxHistory.length : 0
            property var _dataBind: service ? service.data : ({})

            // --- Summary + Firewall (left) | Active Connections (right rail) ---
            RowLayout {
                Layout.fillWidth: true
                spacing: root.sectionSpacing

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: root.sectionSpacing

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: summaryInner.implicitHeight + root.cardMargin * 2
                        radius: root.cardRadius
                        color: root.surfaceColor
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.08)

                        ColumnLayout {
                            id: summaryInner
                            anchors.fill: parent
                            anchors.margins: root.cardMargin
                            spacing: root.panelSpacing

                            SectionBar {
                                title: "NETWORK SUMMARY"
                                copyPayload: root.copySummaryText()
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text {
                                        text: (netData.iface || "—") + "  ·  Gateway " + (netData.gateway || "—")
                                            + "  ·  " + (connStats.tcp_established || 0) + " TCP est"
                                        color: root.subtextColor
                                        font.pixelSize: 10
                                        font.family: "monospace"
                                        wrapMode: Text.Wrap
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: "Local IP: " + localIpLabel() + "  ·  Public IP: " + publicIpLabel()
                                        color: root.subtextColor
                                        font.pixelSize: 10
                                        font.family: "monospace"
                                        wrapMode: Text.Wrap
                                        Layout.fillWidth: true
                                    }
                                }

                                ColumnLayout {
                                    spacing: 1
                                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                    Text {
                                        text: "↓ " + formatRate(netData.rx_rate)
                                        color: root.okColor
                                        font.pixelSize: 12
                                        font.bold: true
                                        font.family: "monospace"
                                    }
                                    Text {
                                        text: "↑ " + formatRate(netData.tx_rate)
                                        color: root.accentColor
                                        font.pixelSize: 12
                                        font.bold: true
                                        font.family: "monospace"
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Rectangle {
                                    width: openTermMa.containsMouse ? 102 : 98
                                    height: 22
                                    radius: 4
                                    color: openTermMa.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.14)
                                    Text {
                                        anchors.centerIn: parent
                                        text: "Open Terminal"
                                        color: root.accentColor
                                        font.pixelSize: 9
                                        font.family: "monospace"
                                    }
                                    MouseArea {
                                        id: openTermMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.openTerminal()
                                    }
                                }
                                Text {
                                    visible: copyHint.length > 0
                                    text: copyHint
                                    color: root.okColor
                                    font.pixelSize: 9
                                    font.family: "monospace"
                                }
                                Item { Layout.fillWidth: true }
                            }
                        }
                    }

                    FirewallCard {}
                }

                ActiveConnCard {}
            }

            // --- VPN ---
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: vpnInner.implicitHeight + root.cardMargin * 2
                visible: showVpnBar()
                radius: root.cardRadius
                color: root.surfaceColor
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)

                ColumnLayout {
                    id: vpnInner
                    anchors.fill: parent
                    anchors.margins: root.cardMargin
                    spacing: root.panelSpacing

                    SectionBar {
                        title: "VPN / TAILSCALE"
                        copyPayload: root.copyVpnText()
                    }
                    Text {
                        text: {
                            const ts = netData.tailscale || {}
                            const parts = []
                            if (netData.vpn_iface) parts.push(netData.vpn_iface)
                            if (ts.active) parts.push("Tailscale active")
                            else if (ts.hostname) parts.push(ts.hostname)
                            if (ts.ips && ts.ips.length) parts.push(ts.ips.join(", "))
                            if (ts.using_exit_node && (ts.exit_node_name || ts.exit_node))
                                parts.push("exit " + (ts.exit_node_name || ts.exit_node))
                            return parts.length ? parts.join("  ·  ") : "—"
                        }
                        color: tailscaleActive() ? root.okColor : root.subtextColor
                        font.pixelSize: 10
                        font.family: "monospace"
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                }
            }

            // --- Main body: status strip + balanced detail grid (tables capped at 10 rows) ---
            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: root.staticBlockMinHeight
                Layout.preferredHeight: root.staticBlockMinHeight
                Layout.alignment: Qt.AlignTop
                sourceComponent: root.narrowLayout ? narrowBodyComponent : wideBodyComponent
            }

            Component {
                id: wideBodyComponent
                ColumnLayout {
                    width: contentCol.width
                    spacing: root.sectionSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: root.sectionSpacing

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: root.sectionSpacing
                            StaticLeftPanels {}
                            ProcTableCard {}
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: root.sectionSpacing
                            StaticRightPanels {}
                            ConnTableCard {}
                        }
                    }
                }
            }

            Component {
                id: narrowBodyComponent
                ColumnLayout {
                    width: contentCol.width
                    spacing: root.sectionSpacing

                    StaticLeftPanels {}
                    StaticRightPanels {}
                    ConnTableCard {}
                    ProcTableCard {}
                }
            }

            // --- Bandwidth graphs (bottom, always visible) ---
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: root.graphsSectionPreferred
                Layout.minimumHeight: root.graphsMinHeight
                spacing: root.sectionSpacing

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: root.cardRadius
                    color: root.surfaceColor
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.08)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 2
                        Text {
                            text: "↓ Download History"
                            color: root.okColor
                            font.pixelSize: 10
                            font.bold: true
                            font.family: "monospace"
                        }
                        Sparkline {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 28
                            history: service.netRxHistory
                            lineColor: root.okColor
                            fillColor: Qt.rgba(0.65, 0.90, 0.75, 0.15)
                            lineWidth: 1.1
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: root.cardRadius
                    color: root.surfaceColor
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.08)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 2
                        Text {
                            text: "↑ Upload History"
                            color: root.accentColor
                            font.pixelSize: 10
                            font.bold: true
                            font.family: "monospace"
                        }
                        Sparkline {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 28
                            history: service.netTxHistory
                            lineColor: root.accentColor
                            fillColor: Qt.rgba(0.55, 0.70, 0.96, 0.18)
                            lineWidth: 1.1
                        }
                    }
                }
            }
        }

    component ConnTableCard: Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: root.connPanelHeight
        Layout.maximumHeight: root.connPanelHeight
        radius: root.cardRadius
        color: root.surfaceColor
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.08)

        ConnectionsPanel {
            anchors.fill: parent
            anchors.margins: root.cardMargin
        }
    }

    component ProcTableCard: Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: root.procPanelHeight
        Layout.maximumHeight: root.procPanelHeight
        radius: root.cardRadius
        color: root.surfaceColor
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.08)

        ProcBandwidthPanel {
            anchors.fill: parent
            anchors.margins: root.cardMargin
        }
    }

    component FirewallCard: Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: root.fwRowHeight
        Layout.maximumHeight: root.fwRowHeight
        radius: root.cardRadius
        color: root.surfaceColor
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.08)

        FirewallPanel {
            anchors.fill: parent
            anchors.margins: root.cardMargin
        }
    }

    component ActiveConnCard: Rectangle {
        Layout.preferredWidth: root.activeConnTileWidth
        Layout.fillHeight: true
        radius: root.cardRadius
        color: root.surfaceColor
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.08)

        ActiveConnectionsTile {
            anchors.fill: parent
            anchors.margins: root.cardMargin
        }
    }

    component FirewallPanel: ColumnLayout {
        spacing: root.panelSpacing

        SectionBar {
            title: "FIREWALL"
            copyPayload: root.copyFirewallText()
            showRefresh: true
            refreshBusy: root.privilegedLoading
            onRefreshClicked: root.refreshPrivileged()
        }

        Text {
            Layout.fillWidth: true
            text: {
                const fw = _privilegedData.firewall || {}
                if (privilegedLoading && !fw.summary) return "loading…"
                let s = fw.summary || "—"
                if (fw.backend && fw.backend !== "none") s += "  ·  " + fw.backend
                return s
            }
            color: (_privilegedData.firewall && _privilegedData.firewall.active) ? root.okColor : root.subtextColor
            font.pixelSize: 9
            font.family: "monospace"
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        Flickable {
            id: fwFlickable
            Layout.fillWidth: true
            Layout.preferredHeight: root.firewallScrollHeight
            Layout.maximumHeight: root.firewallScrollHeight
            contentWidth: width
            contentHeight: fwRulesCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Component.onCompleted: root._fwFlickable = fwFlickable
            Component.onDestruction: {
                if (root._fwFlickable === fwFlickable)
                    root._fwFlickable = null
            }

            ScrollBar.vertical: ScrollBar {
                policy: fwFlickable.contentHeight > fwFlickable.height + 1 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                contentItem: Rectangle {
                    implicitWidth: 4
                    radius: 2
                    color: parent.pressed ? root.accentColor : Qt.rgba(1, 1, 1, 0.2)
                }
            }

            Column {
                id: fwRulesCol
                width: parent.width
                spacing: 1

                Repeater {
                    model: filteredFirewallRules()
                    delegate: Text {
                        width: fwRulesCol.width
                        text: modelData
                        color: root.subtextColor
                        font.pixelSize: 8
                        font.family: "monospace"
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }

                Text {
                    width: fwRulesCol.width
                    visible: !privilegedLoading && privilegedError.length > 0 && filteredFirewallRules().length === 0
                    text: privilegedError
                    color: root.errorColor
                    font.pixelSize: 9
                    font.family: "monospace"
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
                Text {
                    width: fwRulesCol.width
                    visible: !privilegedLoading && privilegedError.length === 0 && filteredFirewallRules().length === 0
                    text: "No firewall rules"
                    color: root.overlayColor
                    font.pixelSize: 9
                    font.family: "monospace"
                }
            }
        }
    }

    // Shared panel groups (used in wide + narrow layouts)
    component StaticLeftPanels: ColumnLayout {
        spacing: root.sectionSpacing
        Layout.fillWidth: true
        Layout.fillHeight: !root.narrowLayout

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.ifacePanelHeight
            radius: root.cardRadius
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: root.cardMargin
                spacing: root.panelSpacing

                SectionBar { title: "INTERFACES"; copyPayload: root.copyInterfacesText() }

                Rectangle {
                    Layout.fillWidth: true
                    height: root.headerHeight
                    radius: 4
                    color: Qt.rgba(1, 1, 1, 0.03)
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        spacing: 6
                        Text { Layout.preferredWidth: 54; text: "Name"; color: root.accentColor; font.pixelSize: 9; font.bold: true; font.family: "monospace" }
                        Text { Layout.preferredWidth: 34; text: "State"; color: root.accentColor; font.pixelSize: 9; font.bold: true; font.family: "monospace" }
                        Text { Layout.preferredWidth: 30; text: "Link"; color: root.accentColor; font.pixelSize: 9; font.bold: true; font.family: "monospace" }
                        Text { Layout.fillWidth: true; text: "Speed"; color: root.accentColor; font.pixelSize: 9; font.bold: true; font.family: "monospace"; horizontalAlignment: Text.AlignRight }
                    }
                }

                Repeater {
                    model: filteredInterfaces()
                    delegate: Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.ifaceRowHeight
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            spacing: 1
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Text {
                                    Layout.preferredWidth: 54
                                    text: modelData.name || "—"
                                    color: root.textColor
                                    font.pixelSize: 10
                                    font.family: "monospace"
                                    font.bold: modelData.name === netData.iface
                                }
                                Text {
                                    Layout.preferredWidth: 34
                                    text: modelData.state || "—"
                                    color: stateColor(modelData.state)
                                    font.pixelSize: 10
                                    font.family: "monospace"
                                }
                                Text {
                                    Layout.preferredWidth: 30
                                    text: linkLabel(modelData)
                                    color: modelData.link_up ? root.okColor : root.subtextColor
                                    font.pixelSize: 10
                                    font.family: "monospace"
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: formatSpeed(modelData.speed_mbps)
                                    color: root.subtextColor
                                    font.pixelSize: 10
                                    font.family: "monospace"
                                    horizontalAlignment: Text.AlignRight
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: ifaceDetailLine(modelData)
                                color: root.overlayColor
                                font.pixelSize: 9
                                font.family: "monospace"
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: root.routePanelMinHeight
            radius: root.cardRadius
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: root.cardMargin
                spacing: root.panelSpacing
                SectionBar {
                    title: "ROUTING"
                    copyPayload: root.copyRoutesText()
                    showRefresh: true
                    refreshBusy: root.privilegedLoading
                    onRefreshClicked: root.refreshPrivileged()
                }
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 28
                    contentWidth: width
                    contentHeight: routeCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ScrollBar.vertical: ScrollBar {
                        policy: parent.contentHeight > parent.height + 1 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                        contentItem: Rectangle {
                            implicitWidth: 4
                            radius: 2
                            color: parent.pressed ? root.accentColor : Qt.rgba(1, 1, 1, 0.2)
                        }
                    }

                    Column {
                        id: routeCol
                        width: parent.width
                        spacing: 1

                        Repeater {
                            model: filteredRoutes()
                            delegate: Text {
                                width: routeCol.width
                                text: routeLine(modelData)
                                color: (modelData && modelData.dst === "default") ? root.okColor : root.subtextColor
                                font.pixelSize: 10
                                font.family: "monospace"
                                wrapMode: Text.Wrap
                            }
                        }

                        Text {
                            width: routeCol.width
                            visible: root.privilegedLoading && filteredRoutes().length === 0
                            text: "loading…"
                            color: root.overlayColor
                            font.pixelSize: 10
                            font.family: "monospace"
                        }
                        Text {
                            width: routeCol.width
                            visible: !root.privilegedLoading && filteredRoutes().length === 0
                            text: root.privilegedError.length > 0 ? root.privilegedError : "No routes available"
                            color: root.privilegedError.length > 0 ? root.errorColor : root.overlayColor
                            font.pixelSize: 10
                            font.family: "monospace"
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }
        }

    }

    component StaticRightPanels: ColumnLayout {
        spacing: root.sectionSpacing
        Layout.fillWidth: true
        Layout.fillHeight: !root.narrowLayout

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.latencyPanelHeight
            radius: root.cardRadius
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: root.cardMargin
                spacing: root.panelSpacing
                SectionBar {
                    title: "LATENCY & PACKET LOSS"
                    copyPayload: root.copyLatencyText()
                    showRefresh: true
                    refreshBusy: root.privilegedLoading
                    onRefreshClicked: root.refreshPrivileged()
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: root.headerHeight
                    radius: 4
                    color: Qt.rgba(1, 1, 1, 0.03)
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        spacing: 8
                        Text { Layout.fillWidth: true; text: "Target"; color: root.accentColor; font.pixelSize: 9; font.bold: true; font.family: "monospace" }
                        Text { Layout.preferredWidth: 58; text: "Latency"; color: root.accentColor; font.pixelSize: 9; font.bold: true; font.family: "monospace"; horizontalAlignment: Text.AlignRight }
                        Text { Layout.preferredWidth: 40; text: "Loss"; color: root.accentColor; font.pixelSize: 9; font.bold: true; font.family: "monospace"; horizontalAlignment: Text.AlignRight }
                    }
                }
                Repeater {
                    model: latencyRows()
                    delegate: RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            Layout.fillWidth: true
                            text: (modelData.label || "—") + "  " + (modelData.host || "")
                            color: root.subtextColor
                            font.pixelSize: 10
                            font.family: "monospace"
                            wrapMode: Text.Wrap
                        }
                        Text {
                            Layout.preferredWidth: 58
                            text: formatLatency(modelData.ms)
                            color: latencyColor(modelData.ms)
                            font.pixelSize: 10
                            font.family: "monospace"
                            horizontalAlignment: Text.AlignRight
                        }
                        Text {
                            Layout.preferredWidth: 40
                            text: formatLoss(modelData.loss_pct)
                            color: lossColor(modelData.loss_pct)
                            font.pixelSize: 10
                            font.family: "monospace"
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
                Text {
                    visible: privilegedLoading
                    text: "measuring (3 pings each)…"
                    color: root.overlayColor
                    font.pixelSize: 9
                    font.family: "monospace"
                }
                Text {
                    visible: privilegedError.length > 0
                    text: privilegedError
                    color: root.errorColor
                    font.pixelSize: 9
                    font.family: "monospace"
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: root.dnsPanelMinHeight
            radius: root.cardRadius
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: root.cardMargin
                spacing: root.panelSpacing
                SectionBar { title: "DNS RESOLUTION"; copyPayload: root.copyDnsText() }
                Text {
                    Layout.fillWidth: true
                    text: {
                        const d = detailDns()
                        let s = ""
                        if (d.current) s += "Active: " + d.current
                        if (d.link) s += " (" + d.link + ")"
                        if (d.domain) s += (s ? "  ·  " : "") + "domain " + d.domain
                        const c = d.cache || {}
                        if (c.cache_size !== undefined)
                            s += (s ? "  ·  " : "") + "cache " + c.cache_size
                                + " entries · " + (c.cache_hits || 0) + " hits · "
                                + (c.cache_misses || 0) + " misses"
                        return s || (detailLoading ? "loading…" : "—")
                    }
                    color: root.subtextColor
                    font.pixelSize: 10
                    font.family: "monospace"
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: root.dnsListMinHeight
                    contentWidth: width
                    contentHeight: dnsCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ScrollBar.vertical: ScrollBar {
                        policy: parent.contentHeight > parent.height + 1 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                        contentItem: Rectangle {
                            implicitWidth: 5
                            radius: 2
                            color: parent.pressed ? root.accentColor : Qt.rgba(1, 1, 1, 0.2)
                        }
                    }

                    Column {
                        id: dnsCol
                        width: parent.width
                        spacing: 2
                        Repeater {
                            model: filteredDnsServers()
                            delegate: Text {
                                width: dnsCol.width
                                text: "• " + modelData
                                color: (modelData === detailDns().current || modelData === netData.dns_current)
                                    ? root.okColor : root.subtextColor
                                font.pixelSize: 10
                                font.family: "monospace"
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: wifiBlock.implicitHeight + root.cardMargin * 2
            visible: !!(wifiInfo.iface && wifiInfo.connected)
            radius: root.cardRadius
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            ColumnLayout {
                id: wifiBlock
                anchors.fill: parent
                anchors.margins: root.cardMargin
                spacing: root.panelSpacing
                SectionBar {
                    title: "WIFI"
                    copyPayload: {
                        const w = wifiInfo
                        return ["WiFi", w.iface, w.ssid, w.channel_mhz ? w.channel_mhz + " MHz" : "",
                            w.signal_dbm !== null ? w.signal_dbm + " dBm" : ""].filter(Boolean).join("  ·  ")
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: {
                        const w = wifiInfo
                        const parts = [w.iface, w.ssid || "connected"]
                        if (w.channel_mhz) parts.push(w.channel_mhz + " MHz")
                        if (w.signal_dbm !== null && w.signal_dbm !== undefined) parts.push(w.signal_dbm + " dBm")
                        if (w.signal_pct !== null && w.signal_pct !== undefined) parts.push(w.signal_pct + "%")
                        if (w.noise_dbm !== null && w.noise_dbm !== undefined) parts.push("noise " + w.noise_dbm + " dBm")
                        if (w.bitrate_mbps) parts.push(w.bitrate_mbps + " Mbps")
                        return parts.join("  ·  ")
                    }
                    color: root.okColor
                    font.pixelSize: 10
                    font.family: "monospace"
                    wrapMode: Text.Wrap
                }
            }
        }

    }

    component ActiveConnectionsTile: ColumnLayout {
        spacing: root.panelSpacing

        property int _liveTick: {
            if (!(service && service.data))
                return 0
            var t = Number(service.data.timestamp)
            return (t > 0 && !isNaN(t)) ? t : 0
        }

        SectionBar {
            title: "ACTIVE CONNECTIONS"
            copyPayload: root.copyConnStatsText()
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width
                spacing: root.panelSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    ColumnLayout {
                        Layout.preferredWidth: 44
                        spacing: 0

                        Text {
                            text: String(connStats.tcp_established || 0)
                            color: root.okColor
                            font.pixelSize: 18
                            font.bold: true
                            font.family: "monospace"
                        }
                        Text {
                            text: "estab"
                            color: root.overlayColor
                            font.pixelSize: 7
                            font.family: "monospace"
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 4
                        rowSpacing: 1

                        Text {
                            text: "TCP"
                            color: root.overlayColor
                            font.pixelSize: 8
                            font.family: "monospace"
                        }
                        Text {
                            text: String(connStats.tcp_total || 0)
                            color: root.subtextColor
                            font.pixelSize: 9
                            font.family: "monospace"
                            horizontalAlignment: Text.AlignRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: "UDP"
                            color: root.overlayColor
                            font.pixelSize: 8
                            font.family: "monospace"
                        }
                        Text {
                            text: String(connStats.udp || 0)
                            color: root.subtextColor
                            font.pixelSize: 9
                            font.family: "monospace"
                            horizontalAlignment: Text.AlignRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: "Total"
                            color: root.overlayColor
                            font.pixelSize: 8
                            font.family: "monospace"
                        }
                        Text {
                            text: String(connStats.total || 0)
                            color: root.textColor
                            font.pixelSize: 9
                            font.bold: true
                            font.family: "monospace"
                            horizontalAlignment: Text.AlignRight
                            Layout.fillWidth: true
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: root._privilegedFetched
                    text: "in table: " + root.privilegedConnCount
                    color: root.overlayColor
                    font.pixelSize: 8
                    font.family: "monospace"
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
        }
    }

    component ConnectionsPanel: ColumnLayout {
        spacing: root.panelSpacing

        Component.onCompleted: root._connFlickable = connFlickable
        Component.onDestruction: {
            if (root._connFlickable === connFlickable)
                root._connFlickable = null
        }

        SectionBar {
            title: "CONNECTIONS"
            copyPayload: root.copyConnectionsText()
            showRefresh: true
            refreshBusy: root.privilegedLoading
            onRefreshClicked: root.refreshPrivileged()
        }

        Text {
            Layout.fillWidth: true
            visible: filteredConnections().length > 0
            text: {
                const n = filteredConnections().length
                return n > root.maxTableRows
                    ? ("top " + root.maxTableRows + " of " + n + " · scroll for more")
                    : (n + " shown")
            }
            color: root.overlayColor
            font.pixelSize: 8
            font.family: "monospace"
        }

        Rectangle {
            Layout.fillWidth: true
            height: root.headerHeight
            radius: 4
            color: Qt.rgba(1, 1, 1, 0.03)
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 4
                anchors.rightMargin: 4
                spacing: 4
                Text { Layout.preferredWidth: 28; text: "Proto"; color: root.accentColor; font.pixelSize: 8; font.bold: true; font.family: "monospace" }
                Text { Layout.preferredWidth: root.narrowLayout ? 0 : 68; visible: !root.narrowLayout; text: "State"; color: root.accentColor; font.pixelSize: 8; font.bold: true; font.family: "monospace" }
                Text { Layout.preferredWidth: 52; text: "Process"; color: root.accentColor; font.pixelSize: 8; font.bold: true; font.family: "monospace" }
                Text { Layout.fillWidth: true; text: "Local"; color: root.accentColor; font.pixelSize: 8; font.bold: true; font.family: "monospace" }
                Text { Layout.fillWidth: true; text: "Remote"; color: root.accentColor; font.pixelSize: 8; font.bold: true; font.family: "monospace" }
                Text { Layout.preferredWidth: 48; text: "RX"; color: root.okColor; font.pixelSize: 8; font.bold: true; font.family: "monospace"; horizontalAlignment: Text.AlignRight }
                Text { Layout.preferredWidth: 48; text: "TX"; color: root.accentColor; font.pixelSize: 8; font.bold: true; font.family: "monospace"; horizontalAlignment: Text.AlignRight }
            }
        }

        Flickable {
            id: connFlickable
            Layout.fillWidth: true
            Layout.preferredHeight: root.connTableViewportHeight
            Layout.maximumHeight: root.connTableViewportHeight
            contentWidth: Math.max(width, connCol.implicitWidth)
            contentHeight: connCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
                policy: connFlickable.contentHeight > connFlickable.height + 1 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                contentItem: Rectangle {
                    implicitWidth: 5
                    radius: 2
                    color: parent.pressed ? root.accentColor : Qt.rgba(1, 1, 1, 0.2)
                }
            }

            Column {
                id: connCol
                width: Math.max(connFlickable.width, root.narrowLayout ? connFlickable.width : 520)
                spacing: 2

                Repeater {
                    model: filteredConnections()
                    delegate: Item {
                        width: connCol.width
                        height: root.connRowHeight

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 4
                            anchors.rightMargin: 4
                            spacing: 0
                            visible: root.narrowLayout

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text {
                                    text: (modelData.proto || "—").toUpperCase() + "  " + (modelData.state || "—")
                                    color: connStateColor(modelData.state)
                                    font.pixelSize: 9
                                    font.family: "monospace"
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.process || "—"
                                    color: root.textColor
                                    font.pixelSize: 9
                                    font.family: "monospace"
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: formatBytes(modelData.bytes_received)
                                    color: root.okColor
                                    font.pixelSize: 9
                                    font.family: "monospace"
                                }
                                Text {
                                    text: formatBytes(modelData.bytes_sent)
                                    color: root.accentColor
                                    font.pixelSize: 9
                                    font.family: "monospace"
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: (modelData.local || "—") + " → " + (modelData.remote || "—")
                                color: root.subtextColor
                                font.pixelSize: 8
                                font.family: "monospace"
                                elide: Text.ElideMiddle
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 4
                            anchors.rightMargin: 4
                            spacing: 4
                            visible: !root.narrowLayout

                            Text {
                                Layout.preferredWidth: 28
                                text: (modelData.proto || "—").toUpperCase()
                                color: root.subtextColor
                                font.pixelSize: 9
                                font.family: "monospace"
                            }
                            Text {
                                Layout.preferredWidth: 68
                                text: modelData.state || "—"
                                color: connStateColor(modelData.state)
                                font.pixelSize: 9
                                font.family: "monospace"
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.preferredWidth: 52
                                text: modelData.process || "—"
                                color: root.textColor
                                font.pixelSize: 9
                                font.family: "monospace"
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.local || "—"
                                color: root.subtextColor
                                font.pixelSize: 8
                                font.family: "monospace"
                                elide: Text.ElideMiddle
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.remote || "—"
                                color: root.subtextColor
                                font.pixelSize: 8
                                font.family: "monospace"
                                elide: Text.ElideMiddle
                            }
                            Text {
                                Layout.preferredWidth: 48
                                text: formatBytes(modelData.bytes_received)
                                color: root.okColor
                                font.pixelSize: 9
                                font.family: "monospace"
                                horizontalAlignment: Text.AlignRight
                            }
                            Text {
                                Layout.preferredWidth: 48
                                text: formatBytes(modelData.bytes_sent)
                                color: root.accentColor
                                font.pixelSize: 9
                                font.family: "monospace"
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                }

                Text {
                    width: connCol.width
                    visible: root.privilegedLoading && filteredConnections().length === 0
                    text: "loading…"
                    color: root.overlayColor
                    font.pixelSize: 10
                    font.family: "monospace"
                    topPadding: 4
                }
                Text {
                    width: connCol.width
                    visible: !root.privilegedLoading && filteredConnections().length === 0
                    text: root.privilegedError.length > 0 ? root.privilegedError : "No connections"
                    color: root.privilegedError.length > 0 ? root.errorColor : root.overlayColor
                    font.pixelSize: 10
                    font.family: "monospace"
                    topPadding: 4
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    component ProcBandwidthPanel: ColumnLayout {
        spacing: root.panelSpacing

        Component.onCompleted: root._procFlickable = procFlickable
        Component.onDestruction: {
            if (root._procFlickable === procFlickable)
                root._procFlickable = null
        }

        SectionBar { title: "BANDWIDTH BY PROCESS"; copyPayload: root.copyProcBwText() }

        Text {
            Layout.fillWidth: true
            visible: filteredProcBandwidth().length > 0
            text: {
                const n = filteredProcBandwidth().length
                return n > root.maxTableRows
                    ? ("top " + root.maxTableRows + " of " + n + " · scroll for more")
                    : (n + " shown")
            }
            color: root.overlayColor
            font.pixelSize: 8
            font.family: "monospace"
        }

        Rectangle {
            Layout.fillWidth: true
            height: root.headerHeight
            radius: 4
            color: Qt.rgba(1, 1, 1, 0.03)
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                spacing: 8
                Text { Layout.fillWidth: true; text: "Process"; color: root.accentColor; font.pixelSize: 9; font.bold: true; font.family: "monospace" }
                Text { Layout.minimumWidth: 72; text: "Download"; color: root.okColor; font.pixelSize: 9; font.bold: true; font.family: "monospace"; horizontalAlignment: Text.AlignRight }
                Text { Layout.minimumWidth: 72; text: "Upload"; color: root.accentColor; font.pixelSize: 9; font.bold: true; font.family: "monospace"; horizontalAlignment: Text.AlignRight }
            }
        }
        Flickable {
            id: procFlickable
            Layout.fillWidth: true
            Layout.preferredHeight: root.procTableViewportHeight
            Layout.maximumHeight: root.procTableViewportHeight
            contentWidth: width
            contentHeight: procCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
                policy: procFlickable.contentHeight > procFlickable.height + 1 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                contentItem: Rectangle {
                    implicitWidth: 5
                    radius: 2
                    color: parent.pressed ? root.accentColor : Qt.rgba(1, 1, 1, 0.2)
                }
            }

            Column {
                id: procCol
                width: parent.width
                spacing: 2

                Repeater {
                    model: filteredProcBandwidth()
                    delegate: Item {
                        width: procCol.width
                        height: root.rowHeight

                        RowLayout {
                            anchors.fill: parent
                            spacing: 8
                            Text {
                                Layout.fillWidth: true
                                text: modelData.process || "—"
                                color: root.textColor
                                font.pixelSize: 10
                                font.family: "monospace"
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.minimumWidth: 72
                                text: formatRate(modelData.rx_rate)
                                color: root.okColor
                                font.pixelSize: 10
                                font.family: "monospace"
                                horizontalAlignment: Text.AlignRight
                            }
                            Text {
                                Layout.minimumWidth: 72
                                text: formatRate(modelData.tx_rate)
                                color: root.accentColor
                                font.pixelSize: 10
                                font.family: "monospace"
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                }

                Text {
                    width: procCol.width
                    visible: filteredProcBandwidth().length === 0
                    text: "No per-process traffic yet"
                    color: root.overlayColor
                    font.pixelSize: 10
                    font.family: "monospace"
                    topPadding: 4
                }
            }
        }
    }
}