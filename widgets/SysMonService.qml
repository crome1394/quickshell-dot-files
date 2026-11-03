import QtQuick
import Quickshell.Io as Io
import Quickshell

// =============================================================================
// SysMonService.qml — Source of truth for system metrics polling + history
// =============================================================================
//
// Purpose:
//   Owns all live data for system monitoring: parsed JSON from poller,
//   rolling history arrays for sparklines, pollInterval, refresh state, and
//   the Process/Timer machinery. HyprlandInspectorPanel (and future consumers like
//   SysStatsPill) read properties directly and write ONLY via explicit
//   assignments in event handlers.
//
// Root type: Item (logic-only, visible:false) — required so that child
// declarations of Quickshell.Io.Process and Timer work (they need a container
// with default property). Consumers treat the instance as a pure service.
//
// Theme Properties Consumed:
//   - None at runtime (to keep service self-contained and avoid import
//     ordering issues with non-instantiated modules). The default 1500 is
//     kept in sync with Theme.sysmonDefaultPollInterval by convention.
//
// Dependencies:
//   - scripts/sysmon-poller.sh  (the existing efficient JSON collector)
//   - Quickshell.Io for Process + SplitParser
//
// Notes:
//   - This file must remain the canonical owner. No two-way bindings across
//     the service/UI boundary.
//   - pollInterval: UI reads current value for display/selection highlight,
//     writes new value via onClicked etc:  service.pollInterval = 2000
//   - When pollInterval changes while autoPoll is on, the timer is restarted
//     so the new rate takes effect immediately.
//   - Histories are simple JS arrays; service does slice+push+assign to trigger
//     QML bindings.
//   - System Information (fastfetch) lives in HyprlandInspectorPanel (view-specific);
//     this service is focused on the periodic monitor metrics.
//   - Uses the poller.sh (evaluated: bash+ jq+ native tools is the clean reuse
//     of mature collection logic; native QML reimpl would duplicate ~450 LOC
//     of parsing/state without benefit for this iteration).
//   - Follows strict commenting: header, === sections, inline notes.
//   - Root is Item (logic container) so declarative children (Process/Timer) work.
//     Consumers do SysMonService { id: service } and treat it as the service object.
// =============================================================================

Item {
    id: root
    visible: false   // logic-only container (not a UI element). Using Item as root
                     // gives a default property so declarative Io.Process/Timer children
                     // work (QtObject does not). The panel treats the instance as a
                     // pure service object.

    // === Owned data (source of truth) ===
    // Default kept in sync with Theme.sysmonDefaultPollInterval (1500).
    property var data: ({})
    property bool autoPoll: true
    property int pollInterval: 1500
    property bool isRefreshing: false

    property string lastStatus: "Loading..."
    property string lastError: ""

    // Rolling histories (most recent at end). Length capped in updateHistory.
    // UI components bind directly, e.g. Sparkline { history: root.cpuHistory }
    property var cpuHistory: []
    property var gpuHistory: []
    property var netRxHistory: []
    property var netTxHistory: []
    property var diskReadHistory: []
    property var diskWriteHistory: []
    property var ramHistory: []
    property var cpuTempHistory: []
    property var gpuTempHistory: []

    // === Section: History management (pure function, called from parser) ===
    // Appends current sample and drops oldest when > 48 points.
    // Uses slice + reassign so QML sees the change and bindings fire.
    function updateHistory() {
        if (!data.cpu) return

        // CPU util
        let ch = cpuHistory.slice()
        ch.push(data.cpu.util || 0)
        if (ch.length > 48) ch.shift()
        cpuHistory = ch

        // GPU util
        let gh = gpuHistory.slice()
        if (data.gpu && data.gpu.available !== false && data.gpu.util !== null && data.gpu.util !== undefined)
            gh.push(data.gpu.util || 0)
        if (gh.length > 48) gh.shift()
        gpuHistory = gh

        // Network KB/s
        let nrh = netRxHistory.slice()
        nrh.push(data.network ? (data.network.rx_rate / 1024) : 0)
        if (nrh.length > 48) nrh.shift()
        netRxHistory = nrh

        let nth = netTxHistory.slice()
        nth.push(data.network ? (data.network.tx_rate / 1024) : 0)
        if (nth.length > 48) nth.shift()
        netTxHistory = nth

        // Disk KiB/s
        let drh = diskReadHistory.slice()
        drh.push(data.disk ? (data.disk.read_rate / 1024) : 0)
        if (drh.length > 48) drh.shift()
        diskReadHistory = drh

        let dwh = diskWriteHistory.slice()
        dwh.push(data.disk ? (data.disk.write_rate / 1024) : 0)
        if (dwh.length > 48) dwh.shift()
        diskWriteHistory = dwh

        // RAM %
        let rh = ramHistory.slice()
        rh.push(data.memory ? (data.memory.ram_pct || 0) : 0)
        if (rh.length > 48) rh.shift()
        ramHistory = rh

        // CPU / GPU temperature (°C)
        let cth = cpuTempHistory.slice()
        cth.push(data.cpu ? (data.cpu.temp || 0) : 0)
        if (cth.length > 48) cth.shift()
        cpuTempHistory = cth

        let gth = gpuTempHistory.slice()
        if (data.gpu && data.gpu.available !== false && data.gpu.temp !== null && data.gpu.temp !== undefined)
            gth.push(data.gpu.temp || 0)
        if (gth.length > 48) gth.shift()
        gpuTempHistory = gth
    }

    // === Section: Polling engine (Process + Timer) ===
    // We drive the external poller.sh (single-shot each time).
    // Stdout parser expects one JSON object per line.

    Io.Process {
        id: poller
        command: [Quickshell.shellPath("scripts/sysmon-poller.sh")]
        stdout: Io.SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                const trimmed = line.trim()
                if (!trimmed) return
                if (!trimmed.startsWith("{") || !trimmed.endsWith("}")) return
                try {
                    const parsed = JSON.parse(trimmed)
                    if (parsed.error) {
                        root.lastError = parsed.error
                    } else if (parsed.timestamp && parsed.cpu) {
                        root.data = parsed
                        root.updateHistory()
                        root.lastError = ""
                        root.lastStatus = "Updated " + new Date().toLocaleTimeString()
                    }
                } catch (e) {
                    root.lastError = "JSON parse error"
                }
                root.isRefreshing = false
            }
        }
        onExited: (code) => {
            root.isRefreshing = false
            if (code !== 0 && !root.lastError) {
                root.lastError = "Poller exited " + code
            }
        }
    }

    Timer {
        id: pollTimer
        interval: root.pollInterval
        running: root.autoPoll
        repeat: true
        onTriggered: root.refresh()
    }

    // Restart timer promptly when user changes poll rate via the panel control.
    onPollIntervalChanged: {
        if (autoPoll && pollTimer.running) {
            pollTimer.stop()
            pollTimer.start()
        }
    }

    onAutoPollChanged: {
        if (!autoPoll)
            root.stopPolling()
    }

    // === Public API (called by UI or on demand) ===
    function stopPolling() {
        if (poller.running)
            poller.running = false
        root.isRefreshing = false
    }

    function refresh() {
        if (!root.autoPoll || poller.running) return
        root.isRefreshing = true
        root.lastStatus = "Refreshing..."
        poller.running = true
    }

    // Start with a friendly status; first sample comes from timer or manual refresh.
    Component.onCompleted: {
        Qt.callLater(function() {
            root.lastStatus = "Ready"
            // Fire an initial sample shortly after load so sparklines have data.
            if (autoPoll) {
                Qt.callLater(function() { refresh() })
            }
        })
    }

    // Optional: allow external pause/resume (panel can bind visible etc later).
    function setAutoPoll(enabled) {
        autoPoll = enabled
    }
}
