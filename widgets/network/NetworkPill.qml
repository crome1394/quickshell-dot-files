import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../components"

// =============================================================================
// NetworkPill.qml — bar pill for the new network panel
// =============================================================================
//
// Where it is imported:
//   shell.qml already does `import "widgets/network"` and places
//   NetworkPill { id: networkPanel } in the widget pool.
//   Settings → Widgets → Network shows, hides, scales, and moves it.
//
//   Left click opens the panel. Right click toggles Wi-Fi.
//   The panel stays open when you click away. Escape, the ✕, or
//   another left click on the pill closes it.
//
// Bar text follows the existing Options → Network switches:
//   showNetworkFullIp, showNetworkLastOctet, showNetworkDeviceName.
// =============================================================================

Rectangle {
    id: root

    required property var bar
    required property Item barBg

    property real pillScale: 1.0
    readonly property real _s: (pillScale > 0 ? pillScale : 1)
    readonly property real _h: bar.pillHeight

    readonly property int _padW: 14
    readonly property int _naturalW: netContent.implicitWidth + _padW
    implicitWidth: Math.round(_naturalW * _s)
    implicitHeight: _h
    width: implicitWidth
    height: implicitHeight
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight
    Layout.alignment: Qt.AlignVCenter
    clip: false

    DockFace {
        id: dockFx
        bar: root.bar
        host: root
        hovered: root.netHovered
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

    HoverHandler { id: netHoverVis }
    readonly property bool netHovered: netHoverVis.hovered || netMouse.containsMouse

    radius: bar.pillRadius
    color: bar.pillBg
    border.width: bar.controlBorderWidth
    border.color: (netHovered || netPopup.visible) ? bar.accent : bar.pillBorder

    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }
    Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }

    function iconNamed(name, fallback) {
        try {
            var v = bar[name]
            if (v !== undefined && v !== null && String(v).length)
                return String(v)
        } catch (e) {}
        return fallback
    }

    function faceGlyph() {
        var st = NetworkService.linkState
        var sig = NetworkService.primarySignal
        if (st === "off")
            return iconNamed("iconNetworkOff", "󰲛")
        if (st === "airplane")
            return iconNamed("iconNetworkAirplane", "󰀝")
        if (st === "portal")
            return iconNamed("iconNetworkPortal", "󰖟")
        if (st === "vpn")
            return iconNamed("iconNetworkVpn", "󰖂")
        if (st === "wired")
            return iconNamed("iconNetworkWired", "󰈀")
        if (st === "wifi") {
            if (sig >= 75) return iconNamed("iconNetworkWifi", "󰤨")
            if (sig >= 50) return iconNamed("iconNetworkWifiFair", "󰤥")
            if (sig >= 25) return iconNamed("iconNetworkWifiWeak", "󰤢")
            if (sig >= 0) return iconNamed("iconNetworkWifiNone", "󰤟")
            return iconNamed("iconNetworkWifi", "󰤨")
        }
        if (st === "wifioff")
            return iconNamed("iconNetworkWifiOff", "󰤭")
        return iconNamed("iconNetworkDisconnected", "󰤮")
    }

    // Full IP wins, then the last octet, then the device name.
    function faceText() {
        void (bar ? bar.showNetworkFullIp : false)
        void (bar ? bar.showNetworkLastOctet : true)
        void (bar ? bar.showNetworkDeviceName : false)
        if (!NetworkService.anyConnected)
            return ""
        var ip = NetworkService.bareIp(NetworkService.primaryIp)
        var ipText = ""
        if (bar && bar.showNetworkFullIp)
            ipText = ip
        else if (bar && bar.showNetworkLastOctet !== false) {
            var parts = ip.split(".")
            if (parts.length === 4)
                ipText = parts[3]
        }
        var nameText = (bar && bar.showNetworkDeviceName) ? String(NetworkService.primaryIface || "") : ""
        if (nameText.length && ipText.length)
            return nameText + " " + ipText
        if (nameText.length)
            return nameText
        return ipText
    }

    function tooltipText() {
        if (!NetworkService.networkingEnabled)
            return "Networking off\nLeft click opens the panel"
        var lines = []
        if (NetworkService.primaryLabel.length)
            lines.push(NetworkService.primaryLabel)
        if (NetworkService.primaryIp.length)
            lines.push(NetworkService.primaryIp)
        if (NetworkService.primaryKind === "wifi" && NetworkService.primarySignal >= 0)
            lines.push("Signal " + NetworkService.primarySignal + "%")
        if (NetworkService.primarySpeed.length)
            lines.push(NetworkService.primarySpeed)
        if (NetworkService.vpnActive && NetworkService.vpnName.length)
            lines.push("VPN · " + NetworkService.vpnName)
        if (NetworkService.airplaneOn)
            lines.push("Airplane mode")
        lines.push("↓ " + NetworkService.formatRate(NetworkService.primaryRx)
                   + "   ↑ " + NetworkService.formatRate(NetworkService.primaryTx))
        return lines.join("\n")
    }

    function reposition() {
        if (!netPopup.visible)
            return
        var w = netPopup.implicitWidth
        var h = netPopup.implicitHeight
        // Dual bars sit `barEdgeMargin` in from the screen edge. placePopup
        // measures the bar window only, so a 2px gap leaves the footer under
        // the bar. Clear the margin, then leave a small gap above the strip.
        var gap = 10
        try {
            if (bar.isDualLayout && bar.isDualLayout() && bar.edgeForItem) {
                var edge = bar.edgeForItem(root)
                if (edge === "bottom" || edge === "top")
                    gap = (bar.barEdgeMargin || 0) + 14
            }
        } catch (e) {}
        if (typeof bar.placePopup === "function")
            bar.placePopup(netPopup, root, w, h, gap, root.width / 2)
    }

    function showPopup() {
        netPopup.visible = true
        netPopup.reveal = 0
        reposition()
        Qt.callLater(function () { netPopup.reveal = 1 })
        NetworkService.popupOpen = true
    }

    function closePopup() {
        if (!netPopup.visible)
            return
        netPopup.reveal = 0
        netPopup.clearPsk()
        closeTimer.restart()
    }

    function togglePopup() {
        if (netPopup.visible)
            closePopup()
        else
            showPopup()
    }

    function hidePopup() { closePopup() }
    function toggleWifi() { NetworkService.toggleWifi() }
    function setWifi(enabled) { NetworkService.setWifi(!!enabled) }

    Timer {
        id: closeTimer
        interval: 170
        repeat: false
        onTriggered: {
            netPopup.visible = false
            NetworkService.popupOpen = false
        }
    }

    Rectangle {
        id: netChip
        anchors.centerIn: parent
        width: Math.max(18, netContent.implicitWidth + 10)
        height: Math.max(18, parent.height - (bar.pillChipInset !== undefined ? bar.pillChipInset : 4))
        radius: bar.workspaceRadius
        color: root.netHovered || netPopup.visible ? bar.iconHoverBg : "transparent"
        border.width: (root.netHovered || netPopup.visible) ? bar.controlBorderWidth : 0
        border.color: (root.netHovered || netPopup.visible) ? bar.accent : "transparent"
        Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }

        Item {
            id: netContent
            anchors.centerIn: parent
            implicitWidth: pillRow.implicitWidth
            implicitHeight: pillRow.implicitHeight
            width: implicitWidth
            height: implicitHeight

            Row {
                id: pillRow
                spacing: Math.max(3, Math.round(6 * root._s))
                anchors.centerIn: parent

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.faceGlyph()
                    font.pixelSize: Math.max(12, Math.round(bar.iconSizeTray * root._s))
                    font.family: bar.fontFamily
                    color: {
                        if (!NetworkService.networkingEnabled)
                            return bar.muted
                        if (NetworkService.isPortal)
                            return "#F59E0B"
                        return (bar.iconColor !== undefined) ? bar.iconColor : bar.subtext
                    }
                }

                Text {
                    visible: root.faceText().length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.faceText()
                    color: (bar.barText !== undefined) ? bar.barText : bar.text
                    font.pixelSize: {
                        var base = (bar.fontBarFace !== undefined) ? bar.fontBarFace : 13
                        return Math.max(9, Math.round(base * root._s))
                    }
                    font.bold: true
                    font.family: (bar.fontBarResolved !== undefined && String(bar.fontBarResolved).length)
                                 ? bar.fontBarResolved : bar.fontFamily
                }
            }
        }
    }

    MouseArea {
        id: netMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: (mouse) => {
            dockFx.jump()
            if (mouse.button === Qt.RightButton) {
                if (!NetworkService.hasWifi) {
                    NetworkService.toast("No Wi-Fi adapter", false)
                    if (!netPopup.visible)
                        root.showPopup()
                    return
                }
                NetworkService.toggleWifi()
                return
            }
            root.togglePopup()
        }

        BarToolTip {
            bar: root.bar
            widgetId: "networkPanel"
            visible: netMouse.containsMouse && !netPopup.visible
            anchorItem: netMouse
            text: root.tooltipText()
        }
    }

    NetworkPopup {
        id: netPopup
        bar: root.bar
        anchorItem: root
        onDismissed: root.closePopup()
        onImplicitHeightChanged: {
            if (visible)
                root.reposition()
        }
        onVisibleChanged: {
            if (visible)
                Qt.callLater(root.reposition)
        }
    }
}
