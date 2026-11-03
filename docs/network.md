<!-- Extracted from README for reference. See ../README.md for overview. -->

# Network panel (`widgets/network/`)

Bar pill for NetworkManager. Left click opens the panel. Right click toggles Wi-Fi. Escape, the ✕, or another left click on the pill closes it. A click elsewhere leaves it open.

The face shows the connection icon. Options → **Network** chooses the address text:

| Switch | Key | Effect |
|--------|-----|--------|
| **Full IP on bar** | `showNetworkFullIp` | Complete IPv4 address |
| **Last octet on bar** | `showNetworkLastOctet` | Last IPv4 octet when full IP is off |
| **Device name on bar** | `showNetworkDeviceName` | Adapter name (`enp10s0`, `wlan0`) beside the address |

## Panel

Wired, Wi-Fi, Airplane, and VPN sit on one row.

| Section | Contents |
|---------|----------|
| **Header** | Active connection name, address, and speed. **Details** expands IPv4, IPv6, gateway, DNS, MAC, MTU, and addressing. Each value copies to the clipboard. |
| **Wired** | One card per Ethernet device. Link state includes cable unplugged. Connect, disconnect, and Edit (`nm-connection-editor`). The Wired switch disconnects the ports and hides the list. |
| **Wi-Fi** | Networks sorted by signal, with a lock on secured ones. The joined network has Disconnect and Details (the same address lines as wired, plus security, signal, band, and link). Connect appears on the other rows only after that network is disconnected. A new secured network asks for the password inline. Saved networks can be forgotten. Hidden network connect is at the bottom of the section. The list hides while Wi-Fi is off. |
| **VPN** | Saved VPN and WireGuard profiles. The section hides while VPN is off. |
| **Footer** | Connection editor, flush DNS, refresh IP. |

Config tokens: `showNetworkPanel`, `popupNetworkPanelWidth`, `popupNetworkPanelMaxHeight`, `iconNetwork*`.

## Implementation

- **Files:** `NetworkButton.qml` (bar pill), `NetworkPopup.qml` (panel), `NetworkService.qml` (singleton).
- **Backend:** `Quickshell.Networking` for devices, the Wi-Fi scan, connect, and forget. `scripts/network-control.sh` for addresses, gateways, DNS, link facts, VPN, hidden networks, refresh IP, and flush DNS.
- **Visibility:** Settings → Widgets → **Network**, or `setShowNetworkPanel` / `toggleShowNetworkPanel`.

```bash
qs ipc call shell toggleShowNetworkPanel
qs ipc call networkPanel togglePopup
qs ipc call networkPanel toggleWifi
qs ipc call networkPanel setWifi false
```
