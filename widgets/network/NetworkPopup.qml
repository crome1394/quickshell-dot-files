import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland

// =============================================================================
// NetworkPopup.qml — compact network panel anchored to NetworkButton
// =============================================================================
//
// Layout (top to bottom):
//   header card for the active connection, then Wi-Fi / airplane / VPN toggles,
//   Wired, then Wi-Fi (only while the radio is on), then VPN (only while a
//   VPN is on or the VPN toggle is open), then the editor and DNS buttons.
// The list scrolls when the content is taller than the screen.
// Clicking elsewhere does not close this panel. The pill, ✕, and Escape do.
// Colors, radius, and type sizes come from `bar` (Config.qml).
// =============================================================================

PopupWindow {
    id: root

    required property var bar
    required property Item anchorItem

    // placePopup() on the button moves this. Anchoring to `bar` up front
    // keeps the window valid before the first open.
    anchor.window: bar
    visible: false

    property real reveal: 0
    property bool activeOpen: false
    // True after the VPN toggle is opened so the profile list can show
    // before NetworkManager reports a connection. Cleared when the toggle
    // goes off or the panel closes. A live VPN shows the list on its own.
    property bool vpnOpen: false
    // Same idea for Ethernet. A connected cable shows the wired list on its own.
    property bool wiredPanel: false
    property bool savedOpen: false
    property bool hiddenOpen: false
    property var wiredOpen: ({})
    property var wifiOpen: ({})
    property string wifiPick: ""
    property string pskSsid: ""
    property string pskDraft: ""
    property bool pskSecret: false
    property string hiddenSsid: ""
    property string hiddenDraft: ""
    property bool hiddenSecret: false
    property string confirmForget: ""

    signal dismissed()

    color: "transparent"
    // Left false on purpose. A focus grab closed the panel on any outside
    // click and fought the password field. The pill, ✕, and Escape close it.
    grabFocus: false
    implicitWidth: (bar.popupNetworkPanelWidth > 0) ? bar.popupNetworkPanelWidth : 525
    // shellCol is inset by panelMargin. Count that padding or the footer
    // paints past the window and under the bar.
    implicitHeight: Math.min(maxPanelH, shellCol.implicitHeight + panelMargin * 2)

    readonly property int panelMargin: (bar.popupSpacingTight > 0) ? bar.popupSpacingTight : 10
    readonly property int maxPanelH: {
        var cap = (bar.popupNetworkPanelMaxHeight > 0) ? bar.popupNetworkPanelMaxHeight : 680
        var sh = 1080
        try {
            if (bar.screen && bar.screen.height)
                sh = bar.screen.height
        } catch (e) {}
        return Math.max(320, Math.min(cap, sh - 72))
    }
    // Keep the title, footer, toast, and padding inside maxPanelH.
    // The scrolling list gives up whatever those take.
    readonly property int scrollCap: {
        var toastH = (NetworkService.toastText && String(NetworkService.toastText).length > 0) ? 36 : 0
        var chrome = panelMargin * 2 + 36 + 8 + 34 + 8 + toastH
        return Math.max(160, maxPanelH - chrome)
    }

    onVisibleChanged: {
        if (!visible) {
            vpnOpen = false
            wiredPanel = false
            wifiPick = ""
            releaseKeys()
        }
    }

    // Any wired device currently connected. Reading wiredRows keeps this live.
    readonly property bool wiredActive: {
        var rows = NetworkService.wiredRows || []
        for (var i = 0; i < rows.length; i++) {
            if (rows[i] && rows[i].state === "connected")
                return true
        }
        return false
    }

    // Layer popups do not get a keyboard unless Hyprland has a focus grab.
    // This one is only for the password fields. An outside click releases
    // the keys and leaves the panel open.
    HyprlandFocusGrab {
        id: keyGrab
        windows: [root, bar]
        active: false
        onCleared: {
            // Outside click drops the keyboard grab. The panel stays open.
        }
    }

    function armKeys() {
        keyGrab.active = true
    }

    function releaseKeys() {
        keyGrab.active = false
    }

    function toggleVpnSwitch() {
        var rows = NetworkService.vpnRows || []
        if (!rows.length) {
            NetworkService.toast("No VPN or WireGuard profiles", false)
            return
        }
        if (NetworkService.vpnActive || vpnOpen) {
            vpnOpen = false
            NetworkService.disconnectActiveVpns()
            return
        }
        vpnOpen = true
        if (rows.length === 1)
            NetworkService.toggleVpn(rows[0].uuid, !!rows[0].active)
    }
    readonly property string textFont: bar.fontFamily
    readonly property string fieldFont: {
        if (bar.primaryUiFontFamily)
            return bar.primaryUiFontFamily() || bar.fontFamily
        return bar.fontFamily
    }

    Behavior on reveal {
        NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
    }

    function wifiGlyph(pct) {
        var s = Number(pct)
        if (s >= 75) return bar.iconNetworkWifi
        if (s >= 50) return bar.iconNetworkWifiFair
        if (s >= 25) return bar.iconNetworkWifiWeak
        return bar.iconNetworkWifiNone
    }

    function toggleWired(iface) {
        var next = {}
        var src = wiredOpen || {}
        for (var k in src)
            next[k] = src[k]
        next[iface] = !next[iface]
        wiredOpen = next
    }

    function toggleWifiDetails(ssid) {
        var name = String(ssid || "")
        if (!name.length)
            return
        var next = {}
        var src = wifiOpen || {}
        for (var k in src)
            next[k] = src[k]
        next[name] = !next[name]
        wifiOpen = next
    }

    function clearPsk() {
        pskSsid = ""
        pskDraft = ""
        pskSecret = false
        NetworkService.lastError = ""
        NetworkService.holdLists = false
        if (!hiddenOpen)
            releaseKeys()
    }

    function pickWifi(ssid) {
        var name = String(ssid || "")
        if (!name.length)
            return
        if (wifiPick === name) {
            wifiPick = ""
            if (pskSsid === name)
                clearPsk()
            return
        }
        if (pskSsid.length && pskSsid !== name)
            clearPsk()
        wifiPick = name
    }

    function wifiIsJoined(ssid) {
        if (!ssid)
            return false
        if (NetworkService.wifiJoinedSsid === ssid)
            return true
        var rows = NetworkService.wifiRows || []
        for (var i = 0; i < rows.length; i++) {
            if (rows[i] && rows[i].ssid === ssid && rows[i].connected)
                return true
        }
        return false
    }

    // True while any SSID is joined. Other networks stay without a Connect
    // button until that one is disconnected.
    function wifiHasActive() {
        if (String(NetworkService.wifiJoinedSsid || "").length)
            return true
        var rows = NetworkService.wifiRows || []
        for (var i = 0; i < rows.length; i++) {
            if (rows[i] && rows[i].connected)
                return true
        }
        return false
    }

    function beginPsk(ssid) {
        pskSsid = ssid
        pskDraft = ""
        pskSecret = false
        NetworkService.lastError = ""
        // Freeze the Wi-Fi model so a scan tick does not destroy the field.
        NetworkService.holdLists = true
        // Arm the compositor grab before the field takes focus, or keystrokes
        // land in the window behind the panel.
        armKeys()
    }

    function toggleWiredSwitch() {
        var rows = NetworkService.wiredRows || []
        if (!rows.length) {
            NetworkService.toast("No Ethernet devices", false)
            return
        }
        if (wiredActive || wiredPanel) {
            wiredPanel = false
            NetworkService.setWiredEnabled(false)
            return
        }
        wiredPanel = true
        if (rows.length === 1 && rows[0].state !== "connected")
            NetworkService.setDeviceUp(rows[0].iface, true)
    }

    function submitPsk() {
        if (!pskSsid.length)
            return
        if (!pskDraft.length) {
            NetworkService.toast("Enter a password", false)
            return
        }
        var ssid = pskSsid
        var pass = pskDraft
        // Leave the prompt open. A bad password fills lastError under the field.
        // A successful join clears it from onWifiRowsChanged below.
        NetworkService.holdLists = true
        NetworkService.connectSsid(ssid, pass)
    }

    function submitHidden() {
        NetworkService.connectHidden(hiddenSsid, hiddenDraft)
    }

    // Same wl-copy path the original network pill uses. No sudo.
    function copyDetail(text) {
        var t = String(text || "")
        if (!t.length)
            return
        Quickshell.execDetached([
            "sh", "-c",
            'printf "%s" "$1" | wl-copy',
            "wl-copy",
            t
        ])
        var shown = t.length > 42 ? t.substring(0, 42) + "…" : t
        NetworkService.toast("Copied " + shown, true)
    }

    Shortcut {
        sequences: ["Escape"]
        enabled: root.visible
        context: Qt.ApplicationShortcut
        onActivated: {
            if (root.pskSsid.length)
                root.clearPsk()
            else if (root.hiddenOpen && (root.hiddenSsid.length || root.hiddenDraft.length)) {
                root.hiddenSsid = ""
                root.hiddenDraft = ""
            } else
                root.dismissed()
        }
    }

    // The password row lives inside the Wi-Fi repeater, so its TextInput id
    // is not visible here. The list is frozen while the field is open, so
    // watch the joined SSID (updated even when Ethernet is the main link).
    Connections {
        target: NetworkService
        function onWifiJoinedSsidChanged() {
            if (root.pskSsid.length && NetworkService.wifiJoinedSsid === root.pskSsid)
                root.clearPsk()
        }
        function onWifiRowsChanged() {
            if (!root.pskSsid.length)
                return
            if (root.wifiIsJoined(root.pskSsid))
                root.clearPsk()
        }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: bar.popupRadius
        color: bar.glassPopupBg
        border.width: bar.controlBorderWidth
        border.color: bar.glassPopupBorder
        clip: true
        opacity: root.reveal
        scale: 0.97 + 0.03 * root.reveal
        transformOrigin: Item.Top

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: bar.popupHeaderHighlightHeight
            color: bar.glassPopupHighlight
            radius: parent.radius
        }

        ColumnLayout {
            id: shellCol
            anchors.fill: parent
            anchors.margins: bar.popupSpacingTight
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: "Network"
                    color: bar.text
                    font.pixelSize: bar.popupTitleSize
                    font.bold: true
                    font.family: root.textFont
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    width: 26
                    height: 26
                    radius: bar.buttonRadius
                    color: closeMa.containsMouse ? Qt.rgba(1, 0.24, 0.54, 0.22) : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: closeMa.containsMouse ? "#FF3D8A" : bar.subtext
                        font.pixelSize: 12
                        font.bold: true
                    }
                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.dismissed()
                    }
                }
            }

            Flickable {
                id: flick
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(body.implicitHeight, root.scrollCap)
                Layout.maximumHeight: root.scrollCap
                contentWidth: width
                contentHeight: body.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick

                // The bar lives in this gutter. The rows stop short of it,
                // so the handle does not sit on the pills.
                readonly property int scrollGutter: 14

                ScrollBar.vertical: ScrollBar {
                    id: vbar
                    policy: ScrollBar.AsNeeded
                    width: 8
                    padding: 0
                    leftPadding: 2
                    rightPadding: 2
                    contentItem: Rectangle {
                        implicitWidth: 4
                        radius: 2
                        color: vbar.pressed ? bar.accent : Qt.rgba(1, 1, 1, 0.35)
                    }
                }

                ColumnLayout {
                    id: body
                    width: flick.width - flick.scrollGutter
                    spacing: 12

                    // ----- Active connection -----
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: headCol.implicitHeight + 20
                        radius: bar.popupRadius
                        color: Qt.rgba(1, 1, 1, 0.04)
                        border.width: 1
                        border.color: bar.dividerStrong

                        ColumnLayout {
                            id: headCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 12
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                Text {
                                    text: {
                                        var st = NetworkService.linkState
                                        if (st === "wired") return bar.iconNetworkWired
                                        if (st === "wifi") return root.wifiGlyph(NetworkService.primarySignal)
                                        if (st === "vpn") return (bar.iconNetworkVpn !== undefined && String(bar.iconNetworkVpn).length) ? bar.iconNetworkVpn : "󰖂"
                                        if (st === "airplane") return (bar.iconNetworkAirplane !== undefined && String(bar.iconNetworkAirplane).length) ? bar.iconNetworkAirplane : "󰀝"
                                        if (st === "portal") return bar.iconNetworkPortal
                                        if (st === "off" || st === "wifioff") return bar.iconNetworkWifiOff
                                        return bar.iconNetworkDisconnected
                                    }
                                    color: bar.accent
                                    font.pixelSize: 28
                                    font.family: bar.fontFamily
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text {
                                        text: NetworkService.primaryLabel.length ? NetworkService.primaryLabel : "Not connected"
                                        color: bar.text
                                        font.pixelSize: 16
                                        font.bold: true
                                        font.family: root.textFont
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        visible: NetworkService.primaryIp.length > 0
                                        text: NetworkService.primaryIp
                                        color: bar.subtext
                                        font.pixelSize: 13
                                        font.family: root.fieldFont
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        visible: NetworkService.primarySpeed.length > 0 || NetworkService.primarySignal >= 0
                                        text: {
                                            var bits = []
                                            if (NetworkService.primarySpeed.length)
                                                bits.push(NetworkService.primarySpeed)
                                            if (NetworkService.primarySignal >= 0)
                                                bits.push(NetworkService.primarySignal + "%")
                                            return bits.join("  ·  ")
                                        }
                                        color: bar.subtext
                                        font.pixelSize: 11
                                        font.family: root.textFont
                                        Layout.fillWidth: true
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                spacing: 16
                                Text {
                                    text: "↓  " + NetworkService.formatRate(NetworkService.primaryRx)
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.family: root.fieldFont
                                }
                                Text {
                                    text: "↑  " + NetworkService.formatRate(NetworkService.primaryTx)
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.family: root.fieldFont
                                }
                                Item { Layout.fillWidth: true }
                            }

                            Text {
                                visible: NetworkService.vpnActive
                                text: "VPN  ·  " + NetworkService.vpnName
                                color: bar.accent
                                font.pixelSize: 11
                                font.bold: true
                                font.family: root.textFont
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 2
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: root.activeOpen ? "Details  ▴" : "Details  ▾"
                                    color: detailMa.containsMouse ? bar.accent : bar.subtext
                                    font.pixelSize: 11
                                    font.family: root.textFont
                                    MouseArea {
                                        id: detailMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.activeOpen = !root.activeOpen
                                    }
                                }
                            }

                            ColumnLayout {
                                visible: root.activeOpen
                                Layout.fillWidth: true
                                spacing: 3
                                DetailLine { label: "IPv4"; value: NetworkService.primaryIp }
                                DetailLine { label: "IPv6"; value: NetworkService.primaryIp6 }
                                DetailLine { label: "Gateway"; value: NetworkService.primaryGateway }
                                DetailLine { label: "Gateway v6"; value: NetworkService.primaryGateway6 }
                                DetailLine { label: "DNS"; value: NetworkService.primaryDns }
                                DetailLine { label: "MAC"; value: NetworkService.primaryMac }
                                DetailLine { label: "SSID"; value: NetworkService.primarySsid }
                                DetailLine { label: "Band"; value: NetworkService.primaryBand }
                                DetailLine { label: "Link"; value: NetworkService.primarySpeed }
                                DetailLine { label: "Security"; value: NetworkService.primarySecurity }
                                DetailLine { label: "Addressing"; value: NetworkService.primaryMethod }
                                DetailLine { label: "MTU"; value: NetworkService.primaryMtu > 0 ? String(NetworkService.primaryMtu) : "" }
                                DetailLine { label: "Device"; value: NetworkService.primaryIface }
                            }
                        }
                    }

                    // ----- Quick toggles, one row. Each list below stays hidden
                    // while its switch is off.
                    RowLayout {
                        visible: NetworkService.wiredRows.length > 0
                                 || NetworkService.hasWifi
                                 || NetworkService.vpnRows.length > 0
                        Layout.fillWidth: true
                        spacing: 6

                        QuickToggle {
                            visible: NetworkService.wiredRows.length > 0
                            label: "Wired"
                            icon: bar.iconNetworkWired
                            on: root.wiredActive || root.wiredPanel
                            available: NetworkService.wiredRows.length > 0
                            onToggled: root.toggleWiredSwitch()
                        }
                        QuickToggle {
                            visible: NetworkService.hasWifi
                            label: "Wi-Fi"
                            icon: NetworkService.wifiEnabled ? bar.iconNetworkWifi : bar.iconNetworkWifiOff
                            on: NetworkService.wifiEnabled
                            available: NetworkService.wifiHardwareEnabled
                            onToggled: {
                                if (!NetworkService.wifiHardwareEnabled) {
                                    NetworkService.toast("Wi-Fi hardware is blocked", false)
                                    return
                                }
                                NetworkService.toggleWifi()
                            }
                        }
                        QuickToggle {
                            visible: NetworkService.hasWifi
                            label: "Airplane"
                            icon: (bar.iconNetworkAirplane !== undefined && String(bar.iconNetworkAirplane).length)
                                  ? bar.iconNetworkAirplane : "󰀝"
                            on: NetworkService.airplaneOn
                            available: true
                            onToggled: NetworkService.toggleAirplane()
                        }
                        QuickToggle {
                            label: "VPN"
                            icon: (bar.iconNetworkVpn !== undefined && String(bar.iconNetworkVpn).length)
                                  ? bar.iconNetworkVpn : "󰖂"
                            on: NetworkService.vpnActive || root.vpnOpen
                            available: NetworkService.vpnRows.length > 0
                            onToggled: root.toggleVpnSwitch()
                        }
                    }

                    // ----- Wired. Hidden while the wired switch is off.
                    ColumnLayout {
                        visible: NetworkService.wiredRows.length > 0
                                 && (root.wiredActive || root.wiredPanel)
                        Layout.fillWidth: true
                        spacing: 6
                        SectionHead { title: "Wired" }
                        Text {
                            visible: wiredRep.count === 0
                            text: "No Ethernet devices"
                            color: bar.subtext
                            font.pixelSize: 12
                            font.family: root.textFont
                        }
                        Repeater {
                            id: wiredRep
                            model: NetworkService.wiredRows
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: wiredCol.implicitHeight + 16
                                radius: bar.buttonRadius
                                color: wiredMa.containsMouse ? bar.popupButtonHoverBg : Qt.rgba(0.10, 0.10, 0.12, 0.45)
                                border.width: 1
                                border.color: (modelData.state === "connected") ? bar.accent : bar.dividerStrong

                                ColumnLayout {
                                    id: wiredCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 10
                                    spacing: 3

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text {
                                            text: modelData.carrier ? bar.iconNetworkWired : bar.iconNetworkDisconnected
                                            color: modelData.state === "connected" ? bar.accent : bar.subtext
                                            font.pixelSize: 16
                                            font.family: bar.fontFamily
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            Text {
                                                text: modelData.iface
                                                color: bar.text
                                                font.pixelSize: 13
                                                font.bold: true
                                                font.family: root.textFont
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: {
                                                    var bits = []
                                                    if (!modelData.carrier)
                                                        bits.push("Cable unplugged")
                                                    else
                                                        bits.push(modelData.state.charAt(0).toUpperCase() + modelData.state.slice(1))
                                                    if (modelData.connection.length)
                                                        bits.push(modelData.connection)
                                                    if (modelData.method && String(modelData.method).length)
                                                        bits.push(modelData.method)
                                                    return bits.join("  ·  ")
                                                }
                                                color: bar.subtext
                                                font.pixelSize: 11
                                                font.family: root.textFont
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                    }

                                    Text {
                                        visible: modelData.speedMbps > 0 || String(modelData.duplex || "").length > 0
                                        text: {
                                            var bits = []
                                            if (modelData.speedMbps > 0)
                                                bits.push(modelData.speedMbps + " Mb/s")
                                            if (modelData.duplex && modelData.duplex !== "unknown")
                                                bits.push(modelData.duplex + " duplex")
                                            return bits.join("  ·  ")
                                        }
                                        color: bar.subtext
                                        font.pixelSize: 11
                                        font.family: root.textFont
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 14
                                        Text {
                                            text: {
                                                var _ = NetworkService.ifaceRates
                                                var r = NetworkService.rateFor(modelData.iface)
                                                return "↓  " + NetworkService.formatRate(r.rx)
                                            }
                                            color: bar.text
                                            font.pixelSize: 11
                                            font.family: root.fieldFont
                                        }
                                        Text {
                                            text: {
                                                var _ = NetworkService.ifaceRates
                                                var r = NetworkService.rateFor(modelData.iface)
                                                return "↑  " + NetworkService.formatRate(r.tx)
                                            }
                                            color: bar.text
                                            font.pixelSize: 11
                                            font.family: root.fieldFont
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.topMargin: 4
                                        spacing: 6
                                        SmallButton {
                                            text: (modelData.state === "connected") ? "Disconnect" : "Connect"
                                            accent: modelData.state !== "connected"
                                            onClicked: NetworkService.setDeviceUp(modelData.iface, modelData.state !== "connected")
                                        }
                                        SmallButton {
                                            text: "Edit"
                                            onClicked: NetworkService.openEditor(modelData.uuid)
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: (root.wiredOpen && root.wiredOpen[modelData.iface]) ? "Details ▴" : "Details ▾"
                                            color: wiredMa.containsMouse ? bar.accent : bar.subtext
                                            font.pixelSize: 11
                                            font.family: root.textFont
                                        }
                                    }

                                    ColumnLayout {
                                        visible: !!(root.wiredOpen && root.wiredOpen[modelData.iface])
                                        Layout.fillWidth: true
                                        Layout.topMargin: 4
                                        spacing: 3
                                        DetailLine { label: "IPv4"; value: modelData.ip4 }
                                        DetailLine { label: "IPv6"; value: modelData.ip6 }
                                        DetailLine { label: "Gateway"; value: modelData.gateway4 }
                                        DetailLine { label: "Gateway v6"; value: modelData.gateway6 }
                                        DetailLine { label: "DNS"; value: modelData.dns }
                                        DetailLine { label: "MAC"; value: modelData.mac }
                                        DetailLine { label: "MTU"; value: modelData.mtu > 0 ? String(modelData.mtu) : "" }
                                        DetailLine { label: "Addressing"; value: modelData.method }
                                    }
                                }

                                MouseArea {
                                    id: wiredMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    z: -1
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleWired(modelData.iface)
                                }
                            }
                        }
                    }

                    // ----- Wi-Fi. Hidden while the radio is off. The toggle above
                    // the wired section is what turns it back on.
                    ColumnLayout {
                        visible: NetworkService.hasWifi && NetworkService.wifiEnabled
                        Layout.fillWidth: true
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            SectionHead { title: "Wi-Fi"; Layout.fillWidth: true }
                            Rectangle {
                                visible: NetworkService.wifiEnabled
                                width: 26
                                height: 26
                                radius: bar.buttonRadius
                                color: scanMa.containsMouse ? bar.popupButtonHoverBg : "transparent"
                                border.width: 1
                                border.color: scanMa.containsMouse ? bar.accent : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: bar.iconReboot || "󰑓"
                                    color: scanMa.containsMouse ? bar.accent : bar.subtext
                                    font.pixelSize: 14
                                    font.family: bar.fontFamily
                                }
                                MouseArea {
                                    id: scanMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: NetworkService.rescan()
                                }
                            }
                        }

                        Text {
                            visible: NetworkService.wifiEnabled && wifiRep.count === 0 && root.pskSsid.length === 0
                            text: "Scanning for networks…"
                            color: bar.subtext
                            font.pixelSize: 12
                            font.family: root.textFont
                        }

                        Repeater {
                            id: wifiRep
                            model: NetworkService.wifiEnabled ? NetworkService.wifiRows : []
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: wifiCol.implicitHeight + 16
                                radius: bar.buttonRadius
                                color: wifiMa.containsMouse ? bar.popupButtonHoverBg : Qt.rgba(0.10, 0.10, 0.12, 0.45)
                                border.width: 1
                                border.color: root.wifiIsJoined(modelData.ssid) ? bar.accent : bar.dividerStrong

                                readonly property var link: {
                                    var _ = NetworkService.statusEpoch
                                    return NetworkService.wifiFacts(modelData.ssid)
                                }
                                readonly property bool detailsOpen: !!(root.wifiOpen && root.wifiOpen[modelData.ssid])

                                ColumnLayout {
                                    id: wifiCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 10
                                    spacing: 3

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text {
                                            text: root.wifiGlyph(modelData.signal)
                                            color: root.wifiIsJoined(modelData.ssid) ? bar.accent : bar.subtext
                                            font.pixelSize: 16
                                            font.family: bar.fontFamily
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            Text {
                                                text: modelData.ssid
                                                color: bar.text
                                                font.pixelSize: 13
                                                font.bold: true
                                                font.family: root.textFont
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: {
                                                    var bits = []
                                                    if (modelData.security && modelData.security !== "Open")
                                                        bits.push(modelData.security)
                                                    if (modelData.known)
                                                        bits.push("Saved")
                                                    if (root.wifiIsJoined(modelData.ssid))
                                                        bits.push("Connected")
                                                    bits.push(modelData.signal + "%")
                                                    return bits.join("  ·  ")
                                                }
                                                color: bar.subtext
                                                font.pixelSize: 11
                                                font.family: root.textFont
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                    }

                                    Rectangle {
                                    visible: root.pskSsid === modelData.ssid && !root.wifiHasActive()
                                    Layout.fillWidth: true
                                    implicitHeight: pskCol.implicitHeight + 16
                                    radius: bar.buttonRadius
                                    color: bar.surface
                                    border.width: 1
                                    border.color: NetworkService.lastError.length ? bar.muted : bar.accent
                                    // pskField only exists in this delegate. Focus it when the row opens.
                                    onVisibleChanged: {
                                        if (visible) {
                                            root.armKeys()
                                            pskFocusTimer.restart()
                                        }
                                    }
                                    Timer {
                                        id: pskFocusTimer
                                        interval: 40
                                        repeat: false
                                        onTriggered: {
                                            if (root.pskSsid === modelData.ssid)
                                                pskField.forceActiveFocus()
                                        }
                                    }

                                    ColumnLayout {
                                        id: pskCol
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.margins: 8
                                        spacing: 6
                                        Text {
                                            text: "Password for " + modelData.ssid
                                            color: bar.text
                                            font.pixelSize: 12
                                            font.bold: true
                                            font.family: root.textFont
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 32
                                                radius: bar.buttonRadius
                                                color: bar.bg
                                                border.width: 1
                                                border.color: pskField.activeFocus ? bar.accent : bar.dividerStrong
                                                TextInput {
                                                    id: pskField
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 8
                                                    anchors.rightMargin: 8
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    color: bar.text
                                                    echoMode: root.pskSecret ? TextInput.Normal : TextInput.Password
                                                    font.pixelSize: 13
                                                    font.family: root.fieldFont
                                                    selectByMouse: true
                                                    clip: true
                                                    activeFocusOnPress: true
                                                    inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                                                    passwordCharacter: "•"
                                                    // Clicking the field after an outside click clears the
                                                    // grab. Taking focus again asks Hyprland for the keys.
                                                    onActiveFocusChanged: {
                                                        if (activeFocus)
                                                            root.armKeys()
                                                    }
                                                    onTextEdited: root.pskDraft = text
                                                    onAccepted: root.submitPsk()
                                                    Keys.onEscapePressed: (event) => {
                                                        root.clearPsk()
                                                        event.accepted = true
                                                    }
                                                }
                                            }
                                            Rectangle {
                                                width: 32
                                                height: 32
                                                radius: bar.buttonRadius
                                                color: eyeMa.containsMouse ? bar.popupButtonHoverBg : bar.bg
                                                border.width: 1
                                                border.color: bar.dividerStrong
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: root.pskSecret ? "󰈉" : "󰈈"
                                                    color: bar.subtext
                                                    font.pixelSize: 14
                                                    font.family: bar.fontFamily
                                                }
                                                MouseArea {
                                                    id: eyeMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.pskSecret = !root.pskSecret
                                                }
                                            }
                                        }
                                        Text {
                                            visible: NetworkService.lastError.length > 0
                                            text: NetworkService.lastError
                                            color: bar.muted
                                            font.pixelSize: 11
                                            font.family: root.textFont
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                        RowLayout {
                                            spacing: 6
                                            SmallButton { text: "Connect"; accent: true; onClicked: root.submitPsk() }
                                            SmallButton { text: "Cancel"; onClicked: root.clearPsk() }
                                        }
                                    }
                                }

                                    RowLayout {
                                        // Joined network: Disconnect and Details.
                                        // Others: Connect only after nothing is joined.
                                        visible: root.wifiIsJoined(modelData.ssid)
                                                 || (!root.wifiHasActive() && root.pskSsid !== modelData.ssid)
                                        Layout.fillWidth: true
                                        Layout.topMargin: 4
                                        spacing: 6
                                        SmallButton {
                                            visible: root.pskSsid !== modelData.ssid
                                            text: root.wifiIsJoined(modelData.ssid) ? "Disconnect" : "Connect"
                                            accent: !root.wifiIsJoined(modelData.ssid)
                                            onClicked: {
                                                if (root.wifiIsJoined(modelData.ssid)) {
                                                    NetworkService.disconnectSsid(modelData.ssid)
                                                    return
                                                }
                                                var need = NetworkService.connectSsid(modelData.ssid, "")
                                                if (need === "password")
                                                    root.beginPsk(modelData.ssid)
                                            }
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            visible: root.wifiIsJoined(modelData.ssid)
                                            text: detailsOpen ? "Details ▴" : "Details ▾"
                                            color: wifiMa.containsMouse ? bar.accent : bar.subtext
                                            font.pixelSize: 11
                                            font.family: root.textFont
                                        }
                                    }

                                    ColumnLayout {
                                        visible: detailsOpen && root.wifiIsJoined(modelData.ssid)
                                        Layout.fillWidth: true
                                        Layout.topMargin: 4
                                        spacing: 3
                                        DetailLine { label: "IPv4"; value: link.ip4 }
                                        DetailLine { label: "IPv6"; value: link.ip6 }
                                        DetailLine { label: "Gateway"; value: link.gateway4 }
                                        DetailLine { label: "Gateway v6"; value: link.gateway6 }
                                        DetailLine { label: "DNS"; value: link.dns }
                                        DetailLine { label: "MAC"; value: link.mac }
                                        DetailLine { label: "MTU"; value: link.mtu }
                                        DetailLine { label: "Addressing"; value: link.method }
                                        DetailLine { label: "Security"; value: modelData.security || "" }
                                        DetailLine { label: "Signal"; value: modelData.signal >= 0 ? (modelData.signal + "%") : "" }
                                        DetailLine { label: "Saved"; value: modelData.known ? "Yes" : "" }
                                        DetailLine { label: "Band"; value: link.band }
                                        DetailLine { label: "Link"; value: link.link }
                                        DetailLine { label: "Device"; value: link.iface }
                                    }
                                }

                                MouseArea {
                                    id: wifiMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    z: -1
                                    cursorShape: root.wifiIsJoined(modelData.ssid) ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        if (root.wifiIsJoined(modelData.ssid))
                                            root.toggleWifiDetails(modelData.ssid)
                                    }
                                }
                            }
                        }

                        // Saved profiles, collapsed until asked.
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Text {
                                text: root.savedOpen ? "Saved networks  ▴" : "Saved networks  ▾"
                                color: savedMa.containsMouse ? bar.accent : bar.subtext
                                font.pixelSize: 12
                                font.bold: true
                                font.family: root.textFont
                                MouseArea {
                                    id: savedMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.savedOpen = !root.savedOpen
                                }
                            }
                            ColumnLayout {
                                visible: root.savedOpen
                                Layout.fillWidth: true
                                spacing: 4
                                Text {
                                    visible: savedRep.count === 0
                                    text: "No saved Wi-Fi networks"
                                    color: bar.subtext
                                    font.pixelSize: 12
                                    font.family: root.textFont
                                }
                                Repeater {
                                    id: savedRep
                                    model: NetworkService.savedRows
                                    delegate: NetworkListItem {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        bar: root.bar
                                        icon: bar.iconNetworkWifi
                                        title: modelData.name
                                        subtitle: modelData.active ? "Connected" : "Saved"
                                        active: !!modelData.active
                                        sideText: root.confirmForget === modelData.uuid ? "Confirm" : "Forget"
                                        onClicked: {
                                            if (root.confirmForget === modelData.uuid) {
                                                root.confirmForget = ""
                                                NetworkService.forgetSsid(modelData.name, modelData.uuid)
                                            } else {
                                                root.confirmForget = modelData.uuid
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Text {
                                text: root.hiddenOpen ? "Hidden network  ▴" : "Hidden network  ▾"
                                color: hiddenMa.containsMouse ? bar.accent : bar.subtext
                                font.pixelSize: 12
                                font.bold: true
                                font.family: root.textFont
                                MouseArea {
                                    id: hiddenMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.hiddenOpen = !root.hiddenOpen
                                }
                            }
                            ColumnLayout {
                                visible: root.hiddenOpen
                                Layout.fillWidth: true
                                spacing: 6
                                FieldBox {
                                    placeholder: "Network name"
                                    secret: false
                                    text: root.hiddenSsid
                                    onEdited: (t) => { root.hiddenSsid = t }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    FieldBox {
                                        Layout.fillWidth: true
                                        placeholder: "Password"
                                        secret: !root.hiddenSecret
                                        text: root.hiddenDraft
                                        onEdited: (t) => { root.hiddenDraft = t }
                                        onSubmit: root.submitHidden()
                                    }
                                    Rectangle {
                                        width: 32
                                        height: 32
                                        radius: bar.buttonRadius
                                        color: hiddenEye.containsMouse ? bar.popupButtonHoverBg : bar.bg
                                        border.width: 1
                                        border.color: bar.dividerStrong
                                        Text {
                                            anchors.centerIn: parent
                                            text: root.hiddenSecret ? "󰈉" : "󰈈"
                                            color: bar.subtext
                                            font.pixelSize: 14
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: hiddenEye
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.hiddenSecret = !root.hiddenSecret
                                        }
                                    }
                                }
                                Text {
                                    visible: NetworkService.lastError.length > 0 && root.pskSsid.length === 0
                                    text: NetworkService.lastError
                                    color: bar.muted
                                    font.pixelSize: 11
                                    font.family: root.textFont
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }
                                SmallButton { text: "Connect"; accent: true; onClicked: root.submitHidden() }
                            }
                        }
                    }

                    // ----- VPN / WireGuard. Hidden while every VPN is off.
                    // The toggle above is what brings this list back.
                    ColumnLayout {
                        visible: NetworkService.vpnRows.length > 0
                                 && (NetworkService.vpnActive || root.vpnOpen)
                        Layout.fillWidth: true
                        spacing: 6
                        SectionHead { title: "VPN" }
                        Text {
                            visible: vpnRep.count === 0
                            text: "No VPN or WireGuard profiles"
                            color: bar.subtext
                            font.pixelSize: 12
                            font.family: root.textFont
                        }
                        Repeater {
                            id: vpnRep
                            model: NetworkService.vpnRows
                            delegate: NetworkListItem {
                                required property var modelData
                                Layout.fillWidth: true
                                bar: root.bar
                                icon: (bar.iconNetworkVpn !== undefined && String(bar.iconNetworkVpn).length) ? bar.iconNetworkVpn : "󰖂"
                                title: modelData.name
                                subtitle: (modelData.type === "wireguard" ? "WireGuard" : "VPN")
                                          + (modelData.active ? "  ·  Connected" : "")
                                active: !!modelData.active
                                checkable: true
                                checked: !!modelData.active
                                onClicked: NetworkService.toggleVpn(modelData.uuid, !!modelData.active)
                                onBadgeClicked: NetworkService.toggleVpn(modelData.uuid, !!modelData.active)
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                SmallButton {
                    text: "Connection editor"
                    fill: true
                    onClicked: NetworkService.openEditor("")
                }
                SmallButton {
                    text: "Refresh IP"
                    fill: true
                    onClicked: NetworkService.refreshIp(NetworkService.primaryIface)
                }
                SmallButton {
                    text: "Flush DNS"
                    fill: true
                    onClicked: NetworkService.flushDns()
                }
            }

            Text {
                visible: NetworkService.toastText.length > 0
                Layout.fillWidth: true
                text: NetworkService.toastText
                color: NetworkService.toastOk ? bar.text : bar.muted
                font.pixelSize: 11
                font.family: root.textFont
                wrapMode: Text.WordWrap
            }
        }
    }

    component SectionHead: Text {
        property string title: ""
        text: title.toUpperCase()
        color: root.bar.subtext
        font.pixelSize: 11
        font.bold: true
        font.letterSpacing: 0.8
        font.family: root.textFont
    }

    component DetailLine: RowLayout {
        property string label: ""
        property string value: ""
        visible: value !== undefined && String(value).length > 0
        Layout.fillWidth: true
        spacing: 8
        Text {
            text: label
            color: root.bar.subtext
            font.pixelSize: 11
            font.family: root.textFont
            Layout.preferredWidth: 78
        }
        Text {
            text: value
            color: root.bar.text
            font.pixelSize: 11
            font.family: root.fieldFont
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        Rectangle {
            Layout.preferredWidth: 22
            Layout.preferredHeight: 22
            Layout.alignment: Qt.AlignVCenter
            radius: 4
            color: copyMa.containsMouse ? root.bar.popupButtonHoverBg : "transparent"
            Text {
                anchors.centerIn: parent
                text: "󰆏"
                color: copyMa.containsMouse ? root.bar.accent : root.bar.subtext
                font.pixelSize: 13
                font.family: root.bar.fontFamily
            }
            MouseArea {
                id: copyMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.copyDetail(value)
            }
        }
    }

    component SmallButton: Rectangle {
        property string text: ""
        property bool accent: false
        property bool fill: false
        signal clicked()
        Layout.fillWidth: fill
        implicitWidth: fill ? 0 : (lbl.implicitWidth + 18)
        Layout.preferredHeight: 30
        radius: root.bar.buttonRadius
        color: btnMa.containsMouse
               ? (accent ? root.bar.accent : root.bar.popupButtonHoverBg)
               : (accent ? root.bar.controlActiveBg : Qt.rgba(0.10, 0.10, 0.12, 0.55))
        border.width: 1
        border.color: accent || btnMa.containsMouse ? root.bar.accent : root.bar.dividerStrong
        Text {
            id: lbl
            anchors.centerIn: parent
            width: parent.width - 10
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: parent.text
            color: (accent && btnMa.containsMouse) ? root.bar.bg : root.bar.text
            font.pixelSize: 12
            font.bold: true
            font.family: root.textFont
        }
        MouseArea {
            id: btnMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    component QuickToggle: Rectangle {
        property string label: ""
        property string icon: ""
        property bool on: false
        property bool available: true
        signal toggled()
        Layout.fillWidth: true
        Layout.preferredHeight: 42
        radius: root.bar.buttonRadius
        opacity: available ? 1 : 0.45
        color: togMa.containsMouse ? root.bar.popupButtonHoverBg
                                    : (on ? root.bar.controlActiveBg : Qt.rgba(0.10, 0.10, 0.12, 0.45))
        border.width: 1
        border.color: (on || togMa.containsMouse) ? root.bar.accent : root.bar.dividerStrong
        Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }
        Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 4
            Text {
                text: icon
                color: on ? root.bar.accent : root.bar.subtext
                font.pixelSize: 15
                font.family: root.bar.fontFamily
            }
            Text {
                text: label
                color: root.bar.text
                font.pixelSize: 12
                font.bold: true
                font.family: root.textFont
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                text: on ? "On" : "Off"
                color: on ? root.bar.accent : root.bar.subtext
                font.pixelSize: 11
                font.bold: true
                font.family: root.textFont
            }
        }
        MouseArea {
            id: togMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: available ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: toggled()
        }
    }

    component FieldBox: Rectangle {
        property string placeholder: ""
        property bool secret: false
        property string text: ""
        signal edited(string value)
        signal submit()
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        radius: root.bar.buttonRadius
        color: root.bar.bg
        border.width: 1
        border.color: input.activeFocus ? root.bar.accent : root.bar.dividerStrong
        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            verticalAlignment: TextInput.AlignVCenter
            color: root.bar.text
            font.pixelSize: 13
            font.family: root.fieldFont
            clip: true
            selectByMouse: true
            activeFocusOnPress: true
            echoMode: secret ? TextInput.Password : TextInput.Normal
            passwordCharacter: "•"
            inputMethodHints: secret
                    ? (Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase)
                    : Qt.ImhNone
            text: parent.text
            onTextEdited: edited(text)
            onAccepted: submit()
            onActiveFocusChanged: {
                if (activeFocus)
                    root.armKeys()
            }
        }
        Text {
            anchors.fill: parent
            anchors.leftMargin: 8
            verticalAlignment: Text.AlignVCenter
            visible: !input.text.length && !input.activeFocus
            text: placeholder
            color: root.bar.overlay
            font.pixelSize: 12
            font.family: root.fieldFont
        }
    }
}
