import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io as Io
import Quickshell.Services.Pipewire
import ".."

// PulseAudio/PipeWire audio devices via pactl (sinks, sources, ports, defaults).
// Used by Inspector Audio tab and BarControlBar Audio panel.
// Optional tools strip (pw-top / restart / AEC) via showTools.
// Defaults: card profiles + VU levels (name-resolved PipeWire nodes, gated while active).
Item {
    id: root

    Config { id: theme }

    property string globalFilter: ""
    property bool active: false
    // Tools + echo cancel (control bar + inspector). Safe off for minimal embeds.
    property bool showTools: true

    // Section visibility (Options → Audio; defaults on)
    property bool showSummary: true
    property bool showDefaults: true
    property bool showLevelMeters: true
    property bool showEchoCancel: true
    // Expanded prefs (Options “keep expanded”); applied each time panel opens
    property bool summaryExpandedPref: true
    property bool defaultsExpandedPref: true
    // Session expand state (headers toggle these)
    property bool summaryExpanded: true
    property bool defaultsExpanded: true

    property color textColor: "#f0f4fc"
    property color subtextColor: "#a8b4c8"
    property color accentColor: "#00F0E0"
    property color surfaceColor: "#141a24"
    property color overlayColor: "#6e7a90"
    property color okColor: "#2ee59a"
    property color warnColor: "#f0d060"
    property color errorColor: "#FF3D8A"

    readonly property string pollerScript: "/home/crome/.config/quickshell/scripts/audio-poller.sh"
    readonly property string controlScript: "/home/crome/.config/quickshell/scripts/audio-control.sh"
    readonly property string osdScript: "/home/crome/.config/quickshell/scripts/audio-osd.sh"

    readonly property color defaultBadgeText: "#2ee59a"
    readonly property color defaultBadgeBg: Qt.rgba(0.13, 0.77, 0.37, 0.32)
    readonly property color defaultBadgeBorder: Qt.rgba(0.13, 0.77, 0.37, 0.75)

    property var audioData: ({
        timestamp: 0,
        default_sink: "",
        default_source: "",
        sinks: [],
        sources: [],
        streams: { playback: [], recording: [] }
    })
    // Default open — matches AudioPill “Active streams” glance section
    property bool streamsExpanded: true
    property string selectedSinkName: ""
    property string selectedSourceName: ""
    property bool loading: false
    property bool acting: false
    property string lastError: ""
    property string lastAction: ""
    property int dataVersion: 0

    // Echo cancel (same sticky path as AudioPill / audio-control.sh)
    property bool echoCancelEnabled: false
    property bool echoCancelPreferred: false
    property bool echoCancelBusy: false
    property string echoCancelError: ""
    property string echoCancelHint: ""
    property bool audioRestartBusy: false
    property string toolsStatus: ""

    // Default-device profiles + VU (gated while active)
    property bool speakerLevelMeterOn: true
    property bool micLevelMeterOn: true
    property var peakSpeaker: null
    property var peakMic: null
    property string speakerCard: ""
    property string micCard: ""
    property string speakerProfileActive: ""
    property string micProfileActive: ""
    property var speakerProfiles: []
    property var micProfiles: []
    property bool speakerProfileMenuOpen: false
    property bool micProfileMenuOpen: false

    property bool _loadHandled: false
    property bool _actionHandled: false
    property int _lastActionExitCode: 0
    // Last defaults we loaded profiles for — avoid re-spawning list-card-profiles every soft-poll
    property string _profilesSinkKey: ""
    property string _profilesSourceKey: ""

    readonly property int cardRadius: 6
    readonly property int cardMargin: 10
    readonly property int sectionSpacing: 8
    readonly property int deviceRowHeight: 66
    readonly property int streamsHeaderHeight: 28
    readonly property int streamsRowHeight: 22
    readonly property int streamsMaxBodyHeight: 120

    // Peak sampling ONLY while active + levels enabled. node:null tears down PipeWire
    // peak streams (avoids "Quickshell Peak Detect" and CPU when menu is closed).
    readonly property bool samplingPeaks: root.active && root.showLevelMeters
                                          && (root.speakerLevelMeterOn || root.micLevelMeterOn)

    // Track only name-resolved peak nodes — never Pipewire.defaultAudio*
    PwObjectTracker {
        objects: root.samplingPeaks
            ? [root.peakSpeaker, root.peakMic].filter(function (n) { return !!n })
            : []
    }

    PwNodePeakMonitor {
        id: speakerPeakMon
        node: (root.active && root.showLevelMeters && root.speakerLevelMeterOn && root.peakSpeaker)
              ? root.peakSpeaker : null
        enabled: root.active && root.showLevelMeters && root.speakerLevelMeterOn && !!root.peakSpeaker
    }

    PwNodePeakMonitor {
        id: micPeakMon
        node: (root.active && root.showLevelMeters && root.micLevelMeterOn && root.peakMic)
              ? root.peakMic : null
        enabled: root.active && root.showLevelMeters && root.micLevelMeterOn && !!root.peakMic
    }

    function filterQuery() {
        return (globalFilter && globalFilter.trim()) ? globalFilter.toLowerCase().trim() : ""
    }

    function matchesSearch(dev) {
        const q = filterQuery()
        if (!q) return true
        const ports = (dev.ports || []).map(function(p) {
            return (p.name || "") + " " + (p.description || "") + " " + (p.type || "")
        }).join(" ")
        const hay = [
            dev.name, dev.description, dev.state, dev.active_port, ports
        ].join(" ").toLowerCase()
        return hay.indexOf(q) !== -1
    }

    function filteredSinks() {
        const tick = dataVersion + "|" + globalFilter + "|" + (audioData.sinks ? audioData.sinks.length : 0)
        const list = audioData.sinks || []
        const out = []
        for (let i = 0; i < list.length; i++) {
            if (matchesSearch(list[i])) out.push(list[i])
        }
        return out
    }

    function filteredSources() {
        const tick = dataVersion + "|" + globalFilter + "|" + (audioData.sources ? audioData.sources.length : 0)
        const list = audioData.sources || []
        const out = []
        for (let i = 0; i < list.length; i++) {
            if (matchesSearch(list[i])) out.push(list[i])
        }
        return out
    }

    // Hide internal PipeWire peak monitors (PwNodePeakMonitor → "Quickshell Peak Detect")
    function isInternalStream(s) {
        if (!s) return true
        const app = String(s.app || s.binary || "").toLowerCase()
        const media = String(s.media || "").toLowerCase()
        const binary = String(s.binary || "").toLowerCase()
        if (app.indexOf("peak detect") >= 0 || binary.indexOf("peak detect") >= 0)
            return true
        if (media === "peak detect" || media.indexOf("peak detect") >= 0)
            return true
        if (app.indexOf("quickshell peak") >= 0 || binary.indexOf("quickshell peak") >= 0)
            return true
        return false
    }

    function streamList(kind) {
        const tick = dataVersion + "|" + globalFilter
        const streams = audioData.streams || {}
        const raw = kind === "recording" ? (streams.recording || []) : (streams.playback || [])
        const list = []
        for (let i = 0; i < raw.length; i++) {
            if (!isInternalStream(raw[i]))
                list.push(raw[i])
        }
        const q = filterQuery()
        if (!q) return list
        const out = []
        for (let i = 0; i < list.length; i++) {
            const s = list[i]
            const hay = [
                s.app, s.binary, s.media, s.device_name, kind
            ].join(" ").toLowerCase()
            if (hay.indexOf(q) !== -1) out.push(s)
        }
        return out
    }

    function activeStreamCount() {
        return streamList("playback").length + streamList("recording").length
    }

    function streamsBodyHeight() {
        const rows = streamList("playback").length + streamList("recording").length
        if (rows === 0) return 28
        return Math.min(streamsMaxBodyHeight, Math.max(56, rows * streamsRowHeight + 16))
    }

    function streamLabel(stream) {
        if (!stream) return "--"
        const app = stream.app || stream.binary || "Unknown"
        if (stream.media && stream.media !== app && stream.media !== "Playback" && stream.media !== "Recording")
            return app + " — " + stream.media
        return app
    }

    function streamStatus(stream) {
        if (!stream) return ""
        if (stream.mute) return "muted"
        if (stream.corked) return "paused"
        return "active"
    }

    function deviceLabel(dev) {
        if (!dev) return "--"
        return dev.description || dev.name || "--"
    }

    function defaultSinkDevice() {
        const name = audioData.default_sink || ""
        const sinks = audioData.sinks || []
        for (let i = 0; i < sinks.length; i++) {
            if (sinks[i].name === name) return sinks[i]
        }
        return null
    }

    function defaultSourceDevice() {
        const name = audioData.default_source || ""
        const sources = audioData.sources || []
        for (let i = 0; i < sources.length; i++) {
            if (sources[i].name === name) return sources[i]
        }
        return null
    }

    function activePortLabel(dev) {
        if (!dev || !dev.ports || !dev.ports.length) {
            return dev && dev.active_port ? dev.active_port : "--"
        }
        for (let i = 0; i < dev.ports.length; i++) {
            if (dev.ports[i].active) return dev.ports[i].description || dev.ports[i].name
        }
        return dev.active_port || "--"
    }

    function stateColor(state) {
        const s = (state || "").toLowerCase()
        if (s === "running" || s === "idle") return root.okColor
        if (s === "suspended") return root.warnColor
        return root.subtextColor
    }

    property var _pendingOsd: null

    function scheduleVolumeRefresh() {
        if (!root.active) return
        volumeRefreshTimer.restart()
    }

    function notifyVolumeOsd(kind, percent, muted) {
        if (!root.active) return
        _pendingOsd = { kind: kind, percent: percent, muted: !!muted }
        osdTimer.restart()
    }

    function flushVolumeOsd() {
        if (!_pendingOsd) return
        const osd = _pendingOsd
        _pendingOsd = null
        Quickshell.execDetached([
            root.osdScript,
            osd.kind,
            String(Math.max(0, Math.min(150, Math.round(osd.percent)))),
            osd.muted ? "1" : "0"
        ])
    }

    function setSinkVolume(name, percent, muted) {
        if (!name) return
        const pct = Math.max(0, Math.min(150, Math.round(percent)))
        Quickshell.execDetached([root.controlScript, "set-volume", "sink", name, String(pct)])
        notifyVolumeOsd("sink", pct, muted)
        scheduleVolumeRefresh()
    }

    function setSourceVolume(name, percent, muted) {
        if (!name) return
        const pct = Math.max(0, Math.min(150, Math.round(percent)))
        Quickshell.execDetached([root.controlScript, "set-volume", "source", name, String(pct)])
        notifyVolumeOsd("source", pct, muted)
        scheduleVolumeRefresh()
    }

    function toggleSinkMute(name) {
        if (!name) return
        Quickshell.execDetached([root.controlScript, "toggle-mute", "sink", name])
        scheduleVolumeRefresh()
    }

    function toggleSourceMute(name) {
        if (!name) return
        Quickshell.execDetached([root.controlScript, "toggle-mute", "source", name])
        scheduleVolumeRefresh()
    }

    function refresh() {
        // No background sampling when the panel/tab is closed
        if (!root.active) return
        if (pollProcess.running) return
        loading = true
        lastError = ""
        _loadHandled = false
        pollProcess.running = false
        pollProcess.running = true
    }

    function runControl(action, target, name, port) {
        if (!root.active) return
        if (!name || acting || pollProcess.running) return
        acting = true
        lastAction = ""
        lastError = ""
        _actionHandled = false
        const cmd = port
            ? [root.controlScript, action, target, name, port]
            : [root.controlScript, action, target, name]
        actionProcess.running = false
        actionProcess.command = cmd
        actionProcess.running = true
    }

    function setDefaultSink(name) {
        runControl("set-default", "sink", name, "")
    }

    function setDefaultSource(name) {
        runControl("set-default", "source", name, "")
    }

    function setSinkPort(name, port) {
        runControl("set-port", "sink", name, port)
    }

    function setSourcePort(name, port) {
        runControl("set-port", "source", name, port)
    }

    function finishPoll() {
        if (_loadHandled) return
        _loadHandled = true
        loading = false
        // Discard late process results after the menu/tab closed — no state thrash
        if (!root.active)
            return
        const raw = (pollStdout.text || "").trim()
        if (!raw) {
            lastError = "Empty response from audio poller"
            return
        }
        try {
            const parsed = JSON.parse(raw)
            const prevSink = audioData.default_sink || ""
            const prevSource = audioData.default_source || ""
            audioData = parsed
            dataVersion++
            const sinkNames = {}
            const sourceNames = {}
            const sinks = parsed.sinks || []
            const sources = parsed.sources || []
            for (let i = 0; i < sinks.length; i++) sinkNames[sinks[i].name] = true
            for (let i = 0; i < sources.length; i++) sourceNames[sources[i].name] = true
            if (selectedSinkName && !sinkNames[selectedSinkName]) selectedSinkName = ""
            if (selectedSourceName && !sourceNames[selectedSourceName]) selectedSourceName = ""
            root.refreshPeakNodes()
            // Profiles only when defaults change (or first fill) — not every 3s soft-poll
            const nextSink = parsed.default_sink || ""
            const nextSource = parsed.default_source || ""
            if (nextSink !== prevSink || nextSource !== prevSource
                    || nextSink !== root._profilesSinkKey || nextSource !== root._profilesSourceKey) {
                root.refreshProfiles()
            }
        } catch (e) {
            lastError = "Failed to parse audio JSON"
        }
    }

    function finishAction(exitCode) {
        if (_actionHandled) return
        _actionHandled = true
        acting = false
        if (!root.active)
            return
        const code = exitCode !== undefined ? exitCode : _lastActionExitCode
        if (code !== 0) {
            const err = (actionStderr.text || actionStdout.text || "").trim()
            lastError = err.length ? err : "Audio action failed (exit " + code + ")"
            return
        }
        lastAction = "Updated"
        Qt.callLater(function() {
            if (root.active)
                root.refresh()
        })
    }

    // Tear down all background work when the panel/tab closes.
    // Safe to call repeatedly; prevents peak sampling, poll, and profile process leaks.
    function stopAllWork() {
        volumeRefreshTimer.stop()
        osdTimer.stop()
        softPollTimer.stop()
        toolsStatusClear.stop()

        if (pollProcess.running)
            pollProcess.running = false
        if (actionProcess.running)
            actionProcess.running = false
        if (echoCancelStatusProcess.running)
            echoCancelStatusProcess.running = false
        if (speakerProfileProcess.running)
            speakerProfileProcess.running = false
        if (micProfileProcess.running)
            micProfileProcess.running = false
        // Leave echoCancelToggleProcess / audioRestartProcess / profileSetProcess if mid-flight
        // so sticky AEC / restart can finish; their handlers no-op UI when !active.

        clearPeakNodes()
        loading = false
        acting = false
        _loadHandled = true
        speakerProfileMenuOpen = false
        micProfileMenuOpen = false
        _profilesSinkKey = ""
        _profilesSourceKey = ""
        toolsStatus = ""
    }

    // Parse first JSON object from process stdout (tolerates trailing noise).
    function parseJsonPayload(text) {
        const raw = (text || "").trim()
        if (!raw.length) return null
        try {
            return JSON.parse(raw)
        } catch (e) {
            const start = raw.indexOf("{")
            const end = raw.lastIndexOf("}")
            if (start >= 0 && end > start) {
                try {
                    return JSON.parse(raw.substring(start, end + 1))
                } catch (e2) {
                    return null
                }
            }
            return null
        }
    }

    function applyEchoCancelStatus(data) {
        if (!data) return
        echoCancelEnabled = !!data.enabled
        echoCancelPreferred = !!data.preferred
        echoCancelError = data.error || ""
        if (echoCancelEnabled) {
            echoCancelHint = "On · cleaned mic/speakers (sticky)"
        } else if (echoCancelPreferred && !echoCancelEnabled) {
            echoCancelHint = "Preferred on · applying…"
        } else if (echoCancelError.length) {
            echoCancelHint = echoCancelError
        } else {
            echoCancelHint = "Off · hardware path"
        }
    }

    function refreshEchoCancelStatus() {
        if (!root.active || !root.showTools) return
        if (echoCancelStatusProcess.running)
            echoCancelStatusProcess.running = false
        echoCancelStatusProcess.command = [root.controlScript, "echo-cancel-status"]
        echoCancelStatusProcess.running = true
    }

    function setEchoCancel(wantOn) {
        if (!root.active || !root.showTools || echoCancelBusy) return
        echoCancelBusy = true
        echoCancelError = ""
        toolsStatus = wantOn ? "Enabling echo cancel…" : "Disabling echo cancel…"
        if (echoCancelToggleProcess.running)
            echoCancelToggleProcess.running = false
        echoCancelToggleProcess.command = [
            root.controlScript,
            wantOn ? "echo-cancel-on" : "echo-cancel-off"
        ]
        echoCancelToggleProcess.running = true
    }

    function openPwTop() {
        Quickshell.execDetached(["kitty", "-e", "pw-top"])
    }

    function restartSoundSystem() {
        if (!root.active || audioRestartBusy) return
        audioRestartBusy = true
        toolsStatus = "Restarting audio…"
        if (audioRestartProcess.running)
            audioRestartProcess.running = false
        audioRestartProcess.command = [root.controlScript, "restart-audio"]
        audioRestartProcess.running = true
    }

    // ---- Card / profile helpers (name-based — no live defaultAudio* binding) ----

    function cardNameFromDeviceName(nm) {
        if (!nm) return ""
        const name = String(nm)
        if (name.indexOf("alsa_output.") === 0 || name.indexOf("alsa_input.") === 0) {
            const rest = name.replace(/^alsa_(output|input)\./, "")
            const lastDot = rest.lastIndexOf(".")
            if (lastDot > 0)
                return "alsa_card." + rest.substring(0, lastDot)
        }
        if (name.indexOf("bluez_output.") === 0) {
            let bout = name.substring("bluez_output.".length)
            bout = bout.replace(/\.[0-9]+$/, "")
            return "bluez_card." + bout.replace(/:/g, "_")
        }
        if (name.indexOf("bluez_input.") === 0) {
            const bin = name.substring("bluez_input.".length)
            return "bluez_card." + bin.replace(/:/g, "_")
        }
        return ""
    }

    function safeNodeName(node) {
        if (!node) return ""
        try { return String(node.name || "") } catch (e) { return "" }
    }

    function findNodeByName(wantName) {
        if (!wantName) return null
        try {
            const vals = (Pipewire.nodes && Pipewire.nodes.values) ? Pipewire.nodes.values : []
            for (let i = 0; i < vals.length; i++) {
                const n = vals[i]
                if (!n) continue
                try {
                    if (!n.audio) continue
                    if (n.isStream) continue
                    if (safeNodeName(n) === wantName)
                        return n
                } catch (e1) {
                    continue
                }
            }
        } catch (e) {}
        return null
    }

    function clearPeakNodes() {
        peakSpeaker = null
        peakMic = null
    }

    function refreshPeakNodes() {
        if (!root.active) {
            clearPeakNodes()
            return
        }
        const sinkName = audioData.default_sink || ""
        const sourceName = audioData.default_source || ""
        // Assign from list resolution only — never store Pipewire.defaultAudio*
        peakSpeaker = sinkName ? findNodeByName(sinkName) : null
        peakMic = sourceName ? findNodeByName(sourceName) : null
    }

    function applyProfilePayload(isSink, data) {
        if (!data || !root.active) return
        const profiles = data.profiles || []
        if (isSink) {
            speakerCard = data.card || ""
            speakerProfileActive = data.active || ""
            speakerProfiles = profiles
            _profilesSinkKey = audioData.default_sink || ""
        } else {
            micCard = data.card || ""
            micProfileActive = data.active || ""
            micProfiles = profiles
            _profilesSourceKey = audioData.default_source || ""
        }
    }

    function filteredProfiles(isSink) {
        const list = isSink ? speakerProfiles : micProfiles
        const activeProf = isSink ? speakerProfileActive : micProfileActive
        const out = []
        for (let i = 0; i < list.length; i++) {
            const p = list[i]
            if (!p || !p.name) continue
            if (p.name === "off" && p.name !== activeProf)
                continue
            const isActive = (p.name === activeProf)
            const hasRole = isSink
                ? (p.sinks === undefined || Number(p.sinks) > 0)
                : (p.sources === undefined || Number(p.sources) > 0)
            if (isActive || hasRole)
                out.push(p)
        }
        return out
    }

    function getProfileLabel(isSink) {
        const activeProf = isSink ? speakerProfileActive : micProfileActive
        const list = isSink ? speakerProfiles : micProfiles
        if (!activeProf || activeProf.length === 0)
            return "No profile"
        for (let i = 0; i < list.length; i++) {
            if (list[i].name === activeProf)
                return list[i].description || activeProf
        }
        return activeProf
    }

    function startProfileFetch(isSink) {
        if (!root.active) return
        const devName = isSink
            ? (audioData.default_sink || "")
            : (audioData.default_source || "")
        const card = cardNameFromDeviceName(devName)
        if (!card || card.length === 0) {
            applyProfilePayload(isSink, { card: "", active: "", profiles: [] })
            return
        }
        const proc = isSink ? speakerProfileProcess : micProfileProcess
        if (proc.running)
            proc.running = false
        proc.command = [root.controlScript, "list-card-profiles", card]
        proc.running = true
    }

    function refreshProfiles() {
        if (!root.active) return
        startProfileFetch(true)
        startProfileFetch(false)
    }

    function setCardProfile(card, profileName) {
        if (!root.active || !card || !profileName) return
        if (profileSetProcess.running)
            profileSetProcess.running = false
        // Force profile re-fetch after set (defaults may be unchanged)
        _profilesSinkKey = ""
        _profilesSourceKey = ""
        profileSetProcess.command = [
            root.controlScript, "set-card-profile", card, profileName
        ]
        profileSetProcess.running = true
        speakerProfileMenuOpen = false
        micProfileMenuOpen = false
    }

    function defaultSinkMuted() {
        const d = defaultSinkDevice()
        return !!(d && d.mute)
    }

    function defaultSourceMuted() {
        const d = defaultSourceDevice()
        return !!(d && d.mute)
    }

    function streamAppLabel(stream) {
        if (!stream) return "--"
        const app = stream.app || stream.binary || "Unknown"
        if (stream.media && stream.media !== app && stream.media !== "Playback"
                && stream.media !== "Recording" && stream.media !== "-")
            return app + " · " + stream.media
        return app
    }

    function resetScroll() {
        sinksFlickable.contentY = 0
        sourcesFlickable.contentY = 0
    }

    function focusScroll() {
        sinksFlickable.forceActiveFocus()
    }

    function pageScroll(direction) {
        const flick = sinksFlickable.activeFocus ? sinksFlickable : sourcesFlickable
        const maxY = Math.max(0, flick.contentHeight - flick.height)
        if (maxY <= 0) return
        const page = Math.max(80, flick.height * 0.85)
        flick.contentY = Math.max(0, Math.min(maxY, flick.contentY + direction * page))
    }

    function lineScroll(direction) {
        const flick = sinksFlickable.activeFocus ? sinksFlickable : sourcesFlickable
        const maxY = Math.max(0, flick.contentHeight - flick.height)
        if (maxY <= 0) return
        const step = Math.max(root.deviceRowHeight, 28)
        flick.contentY = Math.max(0, Math.min(maxY, flick.contentY + direction * step))
    }

    onActiveChanged: {
        if (active) {
            // Restore expand prefs each open (Options → keep expanded)
            summaryExpanded = summaryExpandedPref
            // defaultsExpandedPref repurposed: keep Active streams expanded
            streamsExpanded = defaultsExpandedPref
            defaultsExpanded = true
            _profilesSinkKey = ""
            _profilesSourceKey = ""
            refresh()
            if (showTools)
                refreshEchoCancelStatus()
            softPollTimer.restart()
            if (typeof audioScroll !== "undefined" && audioScroll)
                audioScroll.contentY = 0
        } else {
            // Full teardown: no peak sampling, no poll, no profile processes
            stopAllWork()
        }
    }

    Component.onDestruction: stopAllWork()

    Timer {
        id: volumeRefreshTimer
        interval: 350
        repeat: false
        running: false
        onTriggered: {
            if (root.active)
                root.refresh()
        }
    }

    Timer {
        id: osdTimer
        interval: 120
        repeat: false
        running: false
        onTriggered: root.flushVolumeOsd()
    }

    // Soft re-poll while panel/tab is open (device hotplug, BT, volume elsewhere).
    Timer {
        id: softPollTimer
        interval: 3000
        repeat: true
        running: false
        onTriggered: {
            if (!root.active || root.loading || root.acting)
                return
            root.refresh()
        }
    }

    Timer {
        id: toolsStatusClear
        interval: 4000
        onTriggered: root.toolsStatus = ""
    }

    Io.Process {
        id: pollProcess
        command: [root.pollerScript]
        running: false
        stdout: Io.StdioCollector {
            id: pollStdout
            onStreamFinished: root.finishPoll()
        }
        onExited: root.finishPoll()
    }

    Io.Process {
        id: actionProcess
        running: false
        stdout: Io.StdioCollector { id: actionStdout }
        stderr: Io.StdioCollector { id: actionStderr }
        onExited: (code) => {
            root._lastActionExitCode = code
            root.finishAction(code)
        }
    }

    Io.Process {
        id: echoCancelStatusProcess
        running: false
        stdout: Io.StdioCollector { id: echoCancelStatusStdout }
        onExited: (code) => {
            const data = root.parseJsonPayload(echoCancelStatusStdout.text)
            if (data)
                root.applyEchoCancelStatus(data)
        }
    }

    Io.Process {
        id: echoCancelToggleProcess
        running: false
        stdout: Io.StdioCollector { id: echoCancelToggleStdout }
        onExited: (code) => {
            root.echoCancelBusy = false
            const data = root.parseJsonPayload(echoCancelToggleStdout.text)
            if (data)
                root.applyEchoCancelStatus(data)
            if (!root.active)
                return
            if (data) {
                root.toolsStatus = root.echoCancelEnabled ? "Echo cancel on" : "Echo cancel off"
            } else {
                root.echoCancelError = code === 0 ? "" : "Echo cancel command failed"
                root.toolsStatus = root.echoCancelError || "Echo cancel updated"
                root.refreshEchoCancelStatus()
            }
            toolsStatusClear.restart()
            root.refresh()
        }
    }

    Io.Process {
        id: audioRestartProcess
        running: false
        stdout: Io.StdioCollector { id: audioRestartStdout }
        onExited: (code) => {
            root.audioRestartBusy = false
            if (!root.active)
                return
            const data = root.parseJsonPayload(audioRestartStdout.text)
            if (code === 0 && data && data.ok) {
                const ecNote = data.echo_cancel_enabled ? " · echo cancel re-applied" : ""
                root.toolsStatus = "Audio restarted" + ecNote
                root.refresh()
                root.refreshEchoCancelStatus()
            } else {
                root.toolsStatus = (data && data.error) ? data.error : "Audio restart failed"
            }
            toolsStatusClear.restart()
        }
    }

    Io.Process {
        id: speakerProfileProcess
        running: false
        stdout: Io.StdioCollector { id: speakerProfileStdout }
        onExited: (code) => {
            if (!root.active) return
            const data = root.parseJsonPayload(speakerProfileStdout.text)
            if (data)
                root.applyProfilePayload(true, data)
        }
    }

    Io.Process {
        id: micProfileProcess
        running: false
        stdout: Io.StdioCollector { id: micProfileStdout }
        onExited: (code) => {
            if (!root.active) return
            const data = root.parseJsonPayload(micProfileStdout.text)
            if (data)
                root.applyProfilePayload(false, data)
        }
    }

    Io.Process {
        id: profileSetProcess
        running: false
        onExited: (code) => {
            if (!root.active) return
            if (code === 0) {
                root.refreshProfiles()
                root.refresh()
            }
        }
    }

    Flickable {
        id: audioScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: mainCol.implicitHeight + 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height + 4
        ScrollBar.vertical: ScrollBar {
            policy: audioScroll.contentHeight > audioScroll.height + 4 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            width: 8
            contentItem: Rectangle {
                implicitWidth: 6
                radius: 3
                color: root.accentColor
                opacity: 0.55
            }
        }

        ColumnLayout {
            id: mainCol
            width: audioScroll.width - (audioScroll.contentHeight > audioScroll.height + 4 ? 10 : 0)
            spacing: root.sectionSpacing

        RowLayout {
            visible: root.showTools && (root.toolsStatus.length > 0 || root.loading || (root.lastAction || "").length > 0)
            Layout.fillWidth: true
            spacing: 6
            Text {
                text: root.toolsStatus.length ? root.toolsStatus
                      : (root.loading ? "loading…" : (root.lastAction || ""))
                color: root.toolsStatus.length ? root.okColor : root.overlayColor
                font.pixelSize: 10
                font.family: "monospace"
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }


        // Combined overview card: Summary → Active streams → Levels (no dead space)
        Rectangle {
            visible: true
            Layout.fillWidth: true
            Layout.preferredHeight: overviewCol.implicitHeight + root.cardMargin * 2
            Layout.minimumHeight: 28 + root.cardMargin * 2
            radius: root.cardRadius
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
            clip: true

            ColumnLayout {
                id: overviewCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: root.cardMargin
                spacing: 8

                // --- Audio Summary ---
                ColumnLayout {
                    visible: root.showSummary
                    Layout.fillWidth: true
                    spacing: 4

                    Item {
                        id: summaryHead
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        Layout.minimumHeight: 28
                        RowLayout {
                            anchors.fill: parent
                            spacing: 8
                            Text {
                                text: root.summaryExpanded ? "▾" : "▸"
                                color: root.overlayColor
                                font.pixelSize: 11
                                Layout.preferredWidth: 14
                            }
                            Text {
                                text: "AUDIO SUMMARY"
                                color: root.textColor
                                font.pixelSize: 12
                                font.bold: true
                                font.family: "monospace"
                            }
                            Item { Layout.fillWidth: true }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.summaryExpanded = !root.summaryExpanded
                        }
                    }

                    RowLayout {
                        visible: root.summaryExpanded
                        Layout.fillWidth: true
                        spacing: 10

                        ColumnLayout {
                            spacing: 1
                            Layout.fillWidth: true
                            Text {
                                text: "Output: " + root.deviceLabel(root.defaultSinkDevice())
                                color: root.textColor
                                font.pixelSize: 11
                                font.family: "monospace"
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text: "Input: " + root.deviceLabel(root.defaultSourceDevice())
                                color: root.textColor
                                font.pixelSize: 11
                                font.family: "monospace"
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        ColumnLayout {
                            spacing: 1
                            Text {
                                text: (audioData.sinks ? audioData.sinks.length : 0) + " sinks"
                                color: root.subtextColor
                                font.pixelSize: 11
                                font.family: "monospace"
                                horizontalAlignment: Text.AlignRight
                            }
                            Text {
                                text: (audioData.sources ? audioData.sources.length : 0) + " sources"
                                color: root.subtextColor
                                font.pixelSize: 11
                                font.family: "monospace"
                                horizontalAlignment: Text.AlignRight
                            }
                            Text {
                                text: root.loading ? "loading..." : (root.lastAction || "pactl")
                                color: root.overlayColor
                                font.pixelSize: 10
                                font.family: "monospace"
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                }

                // Subtle divider when both summary and streams show
                Rectangle {
                    visible: root.showSummary
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                // --- Active streams ---
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Item {
                        id: streamHeadRow
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        Layout.minimumHeight: 28

                        RowLayout {
                            anchors.fill: parent
                            spacing: 8

                            Text {
                                text: root.streamsExpanded ? "▾" : "▸"
                                color: root.overlayColor
                                font.pixelSize: 12
                                Layout.preferredWidth: 14
                            }

                            Text {
                                text: "Active streams"
                                color: root.textColor
                                font.pixelSize: 12
                                font.bold: true
                                font.family: "monospace"
                            }

                            Text {
                                text: streamList("playback").length + " playing · "
                                      + streamList("recording").length + " recording"
                                color: root.subtextColor
                                font.pixelSize: 10
                                font.family: "monospace"
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.streamsExpanded = !root.streamsExpanded
                        }
                    }

                    Rectangle {
                        visible: root.streamsExpanded
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(140, Math.max(40, streamPillCol.implicitHeight + 12))
                        radius: 4
                        color: Qt.rgba(0, 0, 0, 0.18)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.06)
                        clip: true

                        Flickable {
                            anchors.fill: parent
                            anchors.margins: 6
                            contentHeight: streamPillCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            interactive: contentHeight > height

                            ColumnLayout {
                                id: streamPillCol
                                width: parent.width
                                spacing: 3

                                Repeater {
                                    model: streamList("playback")
                                    delegate: RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        required property var modelData

                                        Text {
                                            text: modelData.corked ? "‖" : "▶"
                                            color: modelData.mute ? root.overlayColor : "#10B981"
                                            font.pixelSize: 11
                                            font.bold: true
                                            Layout.preferredWidth: 14
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: root.streamAppLabel(modelData)
                                            color: modelData.mute ? root.overlayColor : root.textColor
                                            font.pixelSize: 11
                                            font.family: theme.fontFamily
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: modelData.mute ? "muted"
                                                  : ((modelData.volume_pct !== undefined ? modelData.volume_pct : 0) + "%")
                                            color: root.subtextColor
                                            font.pixelSize: 10
                                            Layout.preferredWidth: 42
                                            horizontalAlignment: Text.AlignRight
                                        }
                                    }
                                }

                                Repeater {
                                    model: streamList("recording")
                                    delegate: RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        required property var modelData

                                        Text {
                                            text: "●"
                                            color: modelData.mute ? root.overlayColor : "#00F0E0"
                                            font.pixelSize: 11
                                            font.bold: true
                                            Layout.preferredWidth: 14
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: "REC · " + root.streamAppLabel(modelData)
                                            color: modelData.mute ? root.overlayColor : root.textColor
                                            font.pixelSize: 11
                                            font.family: theme.fontFamily
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: modelData.mute ? "muted"
                                                  : ((modelData.volume_pct !== undefined ? modelData.volume_pct : 0) + "%")
                                            color: root.subtextColor
                                            font.pixelSize: 10
                                            Layout.preferredWidth: 42
                                            horizontalAlignment: Text.AlignRight
                                        }
                                    }
                                }

                                Text {
                                    visible: root.activeStreamCount() === 0
                                    text: "No active app streams (playback or recording)"
                                    color: root.overlayColor
                                    font.pixelSize: 10
                                    font.italic: true
                                    font.family: theme.fontFamily
                                }
                            }
                        }
                    }
                }

                // Divider before levels
                Rectangle {
                    visible: root.showLevelMeters
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                // --- Levels (attached bottom of overview pill) ---
                ColumnLayout {
                    id: levelsCol
                    visible: root.showLevelMeters
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "LEVELS"
                        color: root.textColor
                        font.pixelSize: 11
                        font.bold: true
                        font.family: "monospace"
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "Playback"
                            color: theme.audioSpeakerIcon
                            font.pixelSize: 10
                            font.family: "monospace"
                            Layout.preferredWidth: 64
                        }

                        Rectangle {
                            width: 36
                            height: 18
                            radius: 3
                            color: spkLevelMa.containsMouse
                                ? (root.speakerLevelMeterOn ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0.55, 0.70, 0.96, 0.22))
                                : Qt.rgba(1, 1, 1, 0.04)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.10)
                            Text {
                                anchors.centerIn: parent
                                text: root.speakerLevelMeterOn ? "Off" : "On"
                                color: root.subtextColor
                                font.pixelSize: 9
                                font.family: "monospace"
                            }
                            MouseArea {
                                id: spkLevelMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.speakerLevelMeterOn = !root.speakerLevelMeterOn
                            }
                        }

                        AudioLevelMeter {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 10
                            barHeight: 8
                            muted: root.defaultSinkMuted() || !root.speakerLevelMeterOn
                            level: (root.active && root.showLevelMeters && root.speakerLevelMeterOn
                                    && !root.defaultSinkMuted())
                                   ? speakerPeakMon.peak : 0
                            opacity: root.speakerLevelMeterOn ? 1.0 : 0.35
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "Recording"
                            color: theme.audioMicIcon
                            font.pixelSize: 10
                            font.family: "monospace"
                            Layout.preferredWidth: 64
                        }

                        Rectangle {
                            width: 36
                            height: 18
                            radius: 3
                            color: micLevelMa.containsMouse
                                ? (root.micLevelMeterOn ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0.55, 0.70, 0.96, 0.22))
                                : Qt.rgba(1, 1, 1, 0.04)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.10)
                            Text {
                                anchors.centerIn: parent
                                text: root.micLevelMeterOn ? "Off" : "On"
                                color: root.subtextColor
                                font.pixelSize: 9
                                font.family: "monospace"
                            }
                            MouseArea {
                                id: micLevelMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.micLevelMeterOn = !root.micLevelMeterOn
                            }
                        }

                        AudioLevelMeter {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 10
                            barHeight: 8
                            muted: root.defaultSourceMuted() || !root.micLevelMeterOn
                            level: (root.active && root.showLevelMeters && root.micLevelMeterOn
                                    && !root.defaultSourceMuted())
                                   ? micPeakMon.peak : 0
                            opacity: root.micLevelMeterOn ? 1.0 : 0.35
                        }
                    }
                }
            }
        }

        // Devices — size to content; outer view Flickable scrolls
        RowLayout {
            Layout.fillWidth: true
            spacing: root.sectionSpacing

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: sinksOuterCol.implicitHeight + root.cardMargin * 2
                Layout.minimumHeight: 120
                radius: root.cardRadius
                color: root.surfaceColor
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)
                clip: true

                ColumnLayout {
                    id: sinksOuterCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: root.cardMargin
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text {
                            text: theme.iconSpeaker
                            color: theme.audioSpeakerIcon
                            font.pixelSize: 13
                            font.family: theme.fontFamily
                        }
                        Text {
                            text: "Output Devices"
                            color: root.textColor
                            font.pixelSize: 11
                            font.bold: true
                            font.family: "monospace"
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: root.filteredSinks().length + " shown"
                            color: root.overlayColor
                            font.pixelSize: 10
                            font.family: "monospace"
                        }
                    }

                    Flickable {
                        id: sinksFlickable
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.max(80, sinksList.implicitHeight)
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        contentWidth: width
                        contentHeight: sinksList.implicitHeight
                        interactive: false
                        focus: true

                        property int _tick: root.dataVersion


                        ScrollBar.vertical: ScrollBar {
                            policy: sinksFlickable.contentHeight > sinksFlickable.height + 1 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                            contentItem: Rectangle {
                                implicitWidth: 6
                                radius: 3
                                color: parent.pressed ? root.accentColor : Qt.rgba(1, 1, 1, 0.2)
                            }
                        }

                        Column {
                            id: sinksList
                            width: parent.width
                            spacing: 6

                            Text {
                                width: parent.width
                                visible: root.loading && root.filteredSinks().length === 0
                                text: "Loading audio devices..."
                                color: root.overlayColor
                                font.pixelSize: 10
                                font.family: "monospace"
                            }

                            Text {
                                width: parent.width
                                visible: !root.loading && root.lastError.length > 0 && root.filteredSinks().length === 0
                                text: root.lastError
                                color: root.errorColor
                                font.pixelSize: 10
                                font.family: "monospace"
                                wrapMode: Text.Wrap
                            }

                            Repeater {
                                model: root.filteredSinks()
                                delegate: Rectangle {
                                    readonly property var dev: modelData

                                    width: parent.width
                                    height: root.deviceRowHeight
                                    radius: 4
                                    color: dev.name === root.selectedSinkName
                                        ? Qt.rgba(0.55, 0.70, 0.96, 0.14)
                                        : Qt.rgba(0, 0, 0, 0.12)
                                    border.width: 1
                                    border.color: dev.is_default
                                        ? Qt.rgba(0.65, 0.89, 0.63, 0.35)
                                        : Qt.rgba(1, 1, 1, 0.05)

                                    MouseArea {
                                        z: -1
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.selectedSinkName = dev.name
                                    }

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        spacing: 3

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            Text {
                                                text: dev.description || dev.name
                                                color: root.textColor
                                                font.pixelSize: 10
                                                font.bold: dev.is_default
                                                font.family: "monospace"
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }

                                            Text {
                                                text: dev.mute ? "MUTED" : (Number(dev.volume_pct || 0).toFixed(0) + "%")
                                                color: dev.mute ? root.warnColor : theme.audioSpeakerUtilColor(Number(dev.volume_pct || 0))
                                                font.pixelSize: 10
                                                font.family: "monospace"
                                            }

                                            Rectangle {
                                                visible: dev.is_default
                                                Layout.preferredWidth: 56
                                                Layout.preferredHeight: 18
                                                radius: 4
                                                color: root.defaultBadgeBg
                                                border.width: 1
                                                border.color: root.defaultBadgeBorder

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "Default"
                                                    color: root.defaultBadgeText
                                                    font.pixelSize: 9
                                                    font.bold: true
                                                    font.family: "monospace"
                                                }
                                            }

                                            Rectangle {
                                                visible: !dev.is_default
                                                Layout.preferredWidth: 72
                                                Layout.preferredHeight: 18
                                                radius: 4
                                                color: defSinkMa.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                                                border.width: 1
                                                border.color: Qt.rgba(1, 1, 1, 0.1)
                                                opacity: root.acting ? 0.4 : 1

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "Set Default"
                                                    color: root.accentColor
                                                    font.pixelSize: 8
                                                    font.family: "monospace"
                                                }

                                                MouseArea {
                                                    id: defSinkMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    enabled: !root.acting && !root.loading
                                                    onClicked: root.setDefaultSink(dev.name)
                                                }
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            Text {
                                                text: dev.mute ? theme.iconSpeakerMuted : theme.iconSpeaker
                                                color: dev.mute ? theme.audioSpeakerIconMuted : theme.audioSpeakerIcon
                                                font.pixelSize: 12
                                                font.family: theme.fontFamily
                                            }

                                            Item {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 14

                                                VolumeBar {
                                                    id: sinkVolBar
                                                    anchors.fill: parent
                                                    value: Math.min(1, Number(dev.volume_pct || 0) / 100)
                                                    onSet: function(v) {
                                                        root.setSinkVolume(dev.name, Math.round(v * 100), dev.mute)
                                                    }
                                                }

                                                Binding {
                                                    target: sinkVolBar
                                                    property: "fill"
                                                    value: dev.mute
                                                        ? theme.sliderFillMuted
                                                        : theme.audioSpeakerUtilColor(
                                                            sinkVolBar.dragging
                                                                ? Math.round(sinkVolBar.localValue * 100)
                                                                : Number(dev.volume_pct || 0))
                                                }
                                            }

                                            Rectangle {
                                                Layout.preferredWidth: 44
                                                Layout.preferredHeight: 18
                                                radius: 4
                                                color: sinkMuteMa.containsMouse
                                                    ? (dev.mute ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0.55, 0.70, 0.96, 0.22))
                                                    : Qt.rgba(1, 1, 1, 0.04)
                                                border.width: 1
                                                border.color: dev.mute
                                                    ? Qt.rgba(0.96, 0.89, 0.69, 0.35)
                                                    : Qt.rgba(1, 1, 1, 0.1)

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: dev.mute ? "Unmute" : "Mute"
                                                    color: dev.mute ? root.warnColor : root.subtextColor
                                                    font.pixelSize: 8
                                                    font.family: "monospace"
                                                }

                                                MouseArea {
                                                    id: sinkMuteMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.toggleSinkMute(dev.name)
                                                }
                                            }

                                            Text {
                                                text: dev.state || "--"
                                                color: root.stateColor(dev.state)
                                                font.pixelSize: 9
                                                font.family: "monospace"
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 4
                                            visible: dev.ports && dev.ports.length > 0

                                            Text {
                                                text: "Port:"
                                                color: root.overlayColor
                                                font.pixelSize: 9
                                                font.family: "monospace"
                                            }

                                            Repeater {
                                                model: dev.ports || []
                                                delegate: Rectangle {
                                                    readonly property var port: modelData

                                                    Layout.preferredHeight: 16
                                                    Layout.preferredWidth: Math.min(120, portLabel.implicitWidth + 10)
                                                    radius: 3
                                                    color: port.active
                                                        ? Qt.rgba(0.55, 0.70, 0.96, 0.22)
                                                        : (portMa.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.03))
                                                    border.width: 1
                                                    border.color: port.active
                                                        ? Qt.rgba(0.55, 0.70, 0.96, 0.45)
                                                        : Qt.rgba(1, 1, 1, 0.08)
                                                    opacity: root.acting ? 0.45 : 1

                                                    Text {
                                                        id: portLabel
                                                        anchors.centerIn: parent
                                                        text: port.description || port.name
                                                        color: port.active ? root.textColor : root.subtextColor
                                                        font.pixelSize: 8
                                                        font.family: "monospace"
                                                        elide: Text.ElideRight
                                                    }

                                                    MouseArea {
                                                        id: portMa
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        enabled: !port.active && !root.acting && !root.loading
                                                        onClicked: root.setSinkPort(dev.name, port.name)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Playback profile (default sink card)
                    ColumnLayout {
                        visible: root.showDefaults
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            visible: root.speakerCard.length > 0 && root.speakerProfiles.length > 0

                            Text {
                                text: "Profile"
                                color: root.subtextColor
                                font.pixelSize: 10
                                font.family: "monospace"
                                Layout.preferredWidth: 48
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 24
                                radius: 4
                                color: spkProfMa.containsMouse
                                    ? Qt.rgba(1, 1, 1, 0.10)
                                    : Qt.rgba(0, 0, 0, 0.18)
                                border.width: 1
                                border.color: root.speakerProfileMenuOpen
                                    ? root.accentColor
                                    : Qt.rgba(1, 1, 1, 0.10)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 6
                                    Text {
                                        Layout.fillWidth: true
                                        text: root.getProfileLabel(true)
                                        color: root.textColor
                                        font.pixelSize: 10
                                        font.family: "monospace"
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        text: root.speakerProfileMenuOpen ? "▴" : "▾"
                                        color: root.overlayColor
                                        font.pixelSize: 10
                                    }
                                }
                                MouseArea {
                                    id: spkProfMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.micProfileMenuOpen = false
                                        root.speakerProfileMenuOpen = !root.speakerProfileMenuOpen
                                    }
                                }
                            }
                        }

                        Column {
                            Layout.fillWidth: true
                            visible: root.speakerProfileMenuOpen
                            spacing: 2

                            Repeater {
                                model: root.filteredProfiles(true)
                                delegate: Rectangle {
                                    required property var modelData
                                    width: parent.width
                                    height: 22
                                    radius: 3
                                    color: modelData.name === root.speakerProfileActive
                                        ? Qt.rgba(0.55, 0.70, 0.96, 0.18)
                                        : (spkProfItemMa.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.12))
                                    border.width: 1
                                    border.color: modelData.name === root.speakerProfileActive
                                        ? Qt.rgba(0.55, 0.70, 0.96, 0.40)
                                        : "transparent"

                                    Text {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        text: modelData.description || modelData.name
                                        color: root.textColor
                                        font.pixelSize: 10
                                        font.family: "monospace"
                                        elide: Text.ElideRight
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    MouseArea {
                                        id: spkProfItemMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.setCardProfile(root.speakerCard, modelData.name)
                                    }
                                }
                            }
                        }

                        Text {
                            visible: !(root.speakerCard.length > 0 && root.speakerProfiles.length > 0)
                            text: "No card profiles for default output"
                            color: root.overlayColor
                            font.pixelSize: 9
                            font.family: "monospace"
                            font.italic: true
                        }
                    }

                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: sourcesOuterCol.implicitHeight + root.cardMargin * 2
                Layout.minimumHeight: 120
                radius: root.cardRadius
                color: root.surfaceColor
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)
                clip: true

                ColumnLayout {
                    id: sourcesOuterCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: root.cardMargin
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text {
                            text: theme.iconMic
                            color: theme.audioMicIcon
                            font.pixelSize: 13
                            font.family: theme.fontFamily
                        }
                        Text {
                            text: "Input Devices"
                            color: root.textColor
                            font.pixelSize: 11
                            font.bold: true
                            font.family: "monospace"
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: root.filteredSources().length + " shown"
                            color: root.overlayColor
                            font.pixelSize: 10
                            font.family: "monospace"
                        }
                    }

                    Flickable {
                        id: sourcesFlickable
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.max(80, sourcesList.implicitHeight)
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        contentWidth: width
                        contentHeight: sourcesList.implicitHeight
                        interactive: false

                        property int _tick: root.dataVersion


                        ScrollBar.vertical: ScrollBar {
                            policy: sourcesFlickable.contentHeight > sourcesFlickable.height + 1 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                            contentItem: Rectangle {
                                implicitWidth: 6
                                radius: 3
                                color: parent.pressed ? root.accentColor : Qt.rgba(1, 1, 1, 0.2)
                            }
                        }

                        Column {
                            id: sourcesList
                            width: parent.width
                            spacing: 6

                            Text {
                                width: parent.width
                                visible: root.loading && root.filteredSources().length === 0
                                text: "Loading audio devices..."
                                color: root.overlayColor
                                font.pixelSize: 10
                                font.family: "monospace"
                            }

                            Repeater {
                                model: root.filteredSources()
                                delegate: Rectangle {
                                    readonly property var dev: modelData

                                    width: parent.width
                                    height: root.deviceRowHeight
                                    radius: 4
                                    color: dev.name === root.selectedSourceName
                                        ? Qt.rgba(0.55, 0.70, 0.96, 0.14)
                                        : Qt.rgba(0, 0, 0, 0.12)
                                    border.width: 1
                                    border.color: dev.is_default
                                        ? Qt.rgba(0.65, 0.89, 0.63, 0.35)
                                        : Qt.rgba(1, 1, 1, 0.05)

                                    MouseArea {
                                        z: -1
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.selectedSourceName = dev.name
                                    }

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        spacing: 3

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            Text {
                                                text: dev.description || dev.name
                                                color: root.textColor
                                                font.pixelSize: 10
                                                font.bold: dev.is_default
                                                font.family: "monospace"
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }

                                            Text {
                                                text: dev.mute ? "MUTED" : (Number(dev.volume_pct || 0).toFixed(0) + "%")
                                                color: dev.mute ? root.warnColor : theme.audioMicUtilColor(Number(dev.volume_pct || 0))
                                                font.pixelSize: 10
                                                font.family: "monospace"
                                            }

                                            Rectangle {
                                                visible: dev.is_default
                                                Layout.preferredWidth: 56
                                                Layout.preferredHeight: 18
                                                radius: 4
                                                color: root.defaultBadgeBg
                                                border.width: 1
                                                border.color: root.defaultBadgeBorder

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "Default"
                                                    color: root.defaultBadgeText
                                                    font.pixelSize: 9
                                                    font.bold: true
                                                    font.family: "monospace"
                                                }
                                            }

                                            Rectangle {
                                                visible: !dev.is_default
                                                Layout.preferredWidth: 72
                                                Layout.preferredHeight: 18
                                                radius: 4
                                                color: defSrcMa.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                                                border.width: 1
                                                border.color: Qt.rgba(1, 1, 1, 0.1)
                                                opacity: root.acting ? 0.4 : 1

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "Set Default"
                                                    color: root.accentColor
                                                    font.pixelSize: 8
                                                    font.family: "monospace"
                                                }

                                                MouseArea {
                                                    id: defSrcMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    enabled: !root.acting && !root.loading
                                                    onClicked: root.setDefaultSource(dev.name)
                                                }
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            Text {
                                                text: dev.mute ? theme.iconMicMuted : theme.iconMic
                                                color: dev.mute ? theme.audioMicIconMuted : theme.audioMicIcon
                                                font.pixelSize: 12
                                                font.family: theme.fontFamily
                                            }

                                            Item {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 14

                                                VolumeBar {
                                                    id: srcVolBar
                                                    anchors.fill: parent
                                                    value: Math.min(1, Number(dev.volume_pct || 0) / 100)
                                                    onSet: function(v) {
                                                        root.setSourceVolume(dev.name, Math.round(v * 100), dev.mute)
                                                    }
                                                }

                                                Binding {
                                                    target: srcVolBar
                                                    property: "fill"
                                                    value: dev.mute
                                                        ? theme.sliderFillMuted
                                                        : theme.audioMicUtilColor(
                                                            srcVolBar.dragging
                                                                ? Math.round(srcVolBar.localValue * 100)
                                                                : Number(dev.volume_pct || 0))
                                                }
                                            }

                                            Rectangle {
                                                Layout.preferredWidth: 44
                                                Layout.preferredHeight: 18
                                                radius: 4
                                                color: srcMuteMa.containsMouse
                                                    ? (dev.mute ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0.55, 0.70, 0.96, 0.22))
                                                    : Qt.rgba(1, 1, 1, 0.04)
                                                border.width: 1
                                                border.color: dev.mute
                                                    ? Qt.rgba(0.96, 0.89, 0.69, 0.35)
                                                    : Qt.rgba(1, 1, 1, 0.1)

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: dev.mute ? "Unmute" : "Mute"
                                                    color: dev.mute ? root.warnColor : root.subtextColor
                                                    font.pixelSize: 8
                                                    font.family: "monospace"
                                                }

                                                MouseArea {
                                                    id: srcMuteMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.toggleSourceMute(dev.name)
                                                }
                                            }

                                            Text {
                                                text: dev.state || "--"
                                                color: root.stateColor(dev.state)
                                                font.pixelSize: 9
                                                font.family: "monospace"
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 4
                                            visible: dev.ports && dev.ports.length > 0

                                            Text {
                                                text: "Port:"
                                                color: root.overlayColor
                                                font.pixelSize: 9
                                                font.family: "monospace"
                                            }

                                            Repeater {
                                                model: dev.ports || []
                                                delegate: Rectangle {
                                                    readonly property var port: modelData

                                                    Layout.preferredHeight: 16
                                                    Layout.preferredWidth: Math.min(120, srcPortLabel.implicitWidth + 10)
                                                    radius: 3
                                                    color: port.active
                                                        ? Qt.rgba(0.55, 0.70, 0.96, 0.22)
                                                        : (srcPortMa.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.03))
                                                    border.width: 1
                                                    border.color: port.active
                                                        ? Qt.rgba(0.55, 0.70, 0.96, 0.45)
                                                        : Qt.rgba(1, 1, 1, 0.08)
                                                    opacity: root.acting ? 0.45 : 1

                                                    Text {
                                                        id: srcPortLabel
                                                        anchors.centerIn: parent
                                                        text: port.description || port.name
                                                        color: port.active ? root.textColor : root.subtextColor
                                                        font.pixelSize: 8
                                                        font.family: "monospace"
                                                        elide: Text.ElideRight
                                                    }

                                                    MouseArea {
                                                        id: srcPortMa
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        enabled: !port.active && !root.acting && !root.loading
                                                        onClicked: root.setSourcePort(dev.name, port.name)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Recording profile (default source card)
                    ColumnLayout {
                        visible: root.showDefaults
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            visible: root.micCard.length > 0 && root.micProfiles.length > 0

                            Text {
                                text: "Profile"
                                color: root.subtextColor
                                font.pixelSize: 10
                                font.family: "monospace"
                                Layout.preferredWidth: 48
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 24
                                radius: 4
                                color: micProfMa.containsMouse
                                    ? Qt.rgba(1, 1, 1, 0.10)
                                    : Qt.rgba(0, 0, 0, 0.18)
                                border.width: 1
                                border.color: root.micProfileMenuOpen
                                    ? root.accentColor
                                    : Qt.rgba(1, 1, 1, 0.10)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 6
                                    Text {
                                        Layout.fillWidth: true
                                        text: root.getProfileLabel(false)
                                        color: root.textColor
                                        font.pixelSize: 10
                                        font.family: "monospace"
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        text: root.micProfileMenuOpen ? "▴" : "▾"
                                        color: root.overlayColor
                                        font.pixelSize: 10
                                    }
                                }
                                MouseArea {
                                    id: micProfMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.speakerProfileMenuOpen = false
                                        root.micProfileMenuOpen = !root.micProfileMenuOpen
                                    }
                                }
                            }
                        }

                        Column {
                            Layout.fillWidth: true
                            visible: root.micProfileMenuOpen
                            spacing: 2

                            Repeater {
                                model: root.filteredProfiles(false)
                                delegate: Rectangle {
                                    required property var modelData
                                    width: parent.width
                                    height: 22
                                    radius: 3
                                    color: modelData.name === root.micProfileActive
                                        ? Qt.rgba(0.55, 0.70, 0.96, 0.18)
                                        : (micProfItemMa.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.12))
                                    border.width: 1
                                    border.color: modelData.name === root.micProfileActive
                                        ? Qt.rgba(0.55, 0.70, 0.96, 0.40)
                                        : "transparent"

                                    Text {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        text: modelData.description || modelData.name
                                        color: root.textColor
                                        font.pixelSize: 10
                                        font.family: "monospace"
                                        elide: Text.ElideRight
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    MouseArea {
                                        id: micProfItemMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.setCardProfile(root.micCard, modelData.name)
                                    }
                                }
                            }
                        }

                        Text {
                            visible: !(root.micCard.length > 0 && root.micProfiles.length > 0)
                            text: "No card profiles for default input"
                            color: root.overlayColor
                            font.pixelSize: 9
                            font.family: "monospace"
                            font.italic: true
                        }
                    }

                }
            }
        }


        // Echo cancel — bottom of panel
        Rectangle {
            visible: root.showTools && root.showEchoCancel
            Layout.fillWidth: true
            Layout.preferredHeight: aecCol.implicitHeight + root.cardMargin * 2
            radius: root.cardRadius
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
            clip: true

            ColumnLayout {
                id: aecCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: root.cardMargin
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "Echo cancel"
                        color: root.textColor
                        font.pixelSize: 11
                        font.bold: true
                        font.family: "monospace"
                    }

                    Rectangle {
                        Layout.preferredHeight: 18
                        Layout.preferredWidth: Math.max(36, aecStateLbl.implicitWidth + 12)
                        radius: 4
                        color: root.echoCancelEnabled
                            ? Qt.rgba(0.13, 0.77, 0.37, 0.28)
                            : Qt.rgba(1, 1, 1, 0.05)
                        border.width: 1
                        border.color: root.echoCancelEnabled
                            ? Qt.rgba(0.13, 0.77, 0.37, 0.55)
                            : Qt.rgba(1, 1, 1, 0.10)
                        Text {
                            id: aecStateLbl
                            anchors.centerIn: parent
                            text: root.echoCancelBusy ? "…" : (root.echoCancelEnabled ? "On" : "Off")
                            color: root.echoCancelEnabled ? root.okColor : root.overlayColor
                            font.pixelSize: 9
                            font.bold: true
                            font.family: "monospace"
                        }
                    }

                    Text {
                        text: root.echoCancelHint
                        color: root.overlayColor
                        font.pixelSize: 9
                        font.family: "monospace"
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        Layout.preferredHeight: 22
                        Layout.preferredWidth: Math.max(52, aecToggleLbl.implicitWidth + 14)
                        radius: 4
                        color: aecToggleMa.containsMouse
                            ? (root.echoCancelEnabled ? Qt.rgba(0.91, 0.36, 0.43, 0.18) : Qt.rgba(0.13, 0.77, 0.37, 0.18))
                            : Qt.rgba(1, 1, 1, 0.04)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.10)
                        opacity: root.echoCancelBusy ? 0.5 : 1
                        Text {
                            id: aecToggleLbl
                            anchors.centerIn: parent
                            text: root.echoCancelEnabled ? "Turn off" : "Turn on"
                            color: root.echoCancelEnabled ? root.warnColor : root.okColor
                            font.pixelSize: 9
                            font.family: "monospace"
                        }
                        MouseArea {
                            id: aecToggleMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: !root.echoCancelBusy
                            onClicked: root.setEchoCancel(!root.echoCancelEnabled)
                        }
                    }
                }
            }
        }

        RowLayout {
            visible: root.showTools
            Layout.fillWidth: true
            spacing: 6
            Item { Layout.fillWidth: true }
            Rectangle {
                Layout.preferredHeight: 22
                Layout.preferredWidth: Math.max(56, refreshLbl.implicitWidth + 14)
                radius: 4
                color: refreshMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.04)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.10)
                opacity: root.loading ? 0.5 : 1
                Text {
                    id: refreshLbl
                    anchors.centerIn: parent
                    text: "Refresh"
                    color: root.subtextColor
                    font.pixelSize: 10
                    font.family: "monospace"
                }
                MouseArea {
                    id: refreshMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: !root.loading
                    onClicked: {
                        root.refresh()
                        root.refreshEchoCancelStatus()
                    }
                }
            }
            Rectangle {
                Layout.preferredHeight: 22
                Layout.preferredWidth: Math.max(52, pwTopLbl.implicitWidth + 14)
                radius: 4
                color: pwTopMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.04)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.10)
                Text {
                    id: pwTopLbl
                    anchors.centerIn: parent
                    text: "pw-top"
                    color: root.accentColor
                    font.pixelSize: 10
                    font.family: "monospace"
                }
                MouseArea {
                    id: pwTopMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openPwTop()
                }
            }
            Rectangle {
                Layout.preferredHeight: 22
                Layout.preferredWidth: Math.max(72, restartLbl.implicitWidth + 14)
                radius: 4
                color: restartMa.containsMouse ? Qt.rgba(0.91, 0.36, 0.43, 0.18) : Qt.rgba(1, 1, 1, 0.04)
                border.width: 1
                border.color: root.audioRestartBusy
                    ? Qt.rgba(0.91, 0.36, 0.43, 0.45)
                    : Qt.rgba(1, 1, 1, 0.10)
                opacity: root.audioRestartBusy ? 0.55 : 1
                Text {
                    id: restartLbl
                    anchors.centerIn: parent
                    text: root.audioRestartBusy ? "…" : "Restart audio"
                    color: root.errorColor
                    font.pixelSize: 10
                    font.family: "monospace"
                }
                MouseArea {
                    id: restartMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: !root.audioRestartBusy
                    onClicked: root.restartSoundSystem()
                }
            }
        }

        }
    }
}
