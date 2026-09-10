import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Io as Io

import "../components"

// =============================================================================
// AudioPill.qml — Audio control pill (speaker + mic + device menus)
// =============================================================================
//
// Purpose:
//   Multi-view audio pill (default dual: speaker + mic with % labels).
//   Left-click opens the full popup. Scroll-wheel on a bar adjusts that
//   device’s volume and shows swayosd feedback. No click-drag volume on the pill.
//
// Popup extras (left-click):
//   - L/R channel volume sliders for stereo playback and recording devices
//   - Real-time VU peak meters via PwNodePeakMonitor (enabled only while open)
//   - Card profile dropdowns (PipeWire/Pulse profiles via audio-control.sh)
//   - Active streams, pw-top, restart audio
//
// Theme Properties Consumed:
//   - bar.audioViewContentWidth, bar.audioViewSidePadding
//   - bar.pillRadius, bar.pillBg, bar.pillBorder, bar.accent
//   - bar.iconHoverBg, bar.workspaceRadius  (content hover; Config.qml)
//   - bar.audioSpeakerTier1–4, bar.audioMicTier1–4, bar.audioUtilThreshold1–3
//   - bar.audioSpeakerUtilColor(), bar.audioMicUtilColor()
//   - bar.audioSpeakerIcon, bar.audioMicIcon, bar.audioSpeakerIconMuted, bar.audioMicIconMuted
//   - bar.pillHPadding
//   - bar.iconSpeaker*, bar.iconMic*, bar.iconSizeTray, bar.iconSizePopup
//   - bar.fontFamily, bar.fontPillLabel, bar.fontPopupTitle, bar.fontSection,
//     bar.fontBody, bar.fontSmall
//   - bar.muted, bar.text, bar.subtext, bar.overlay, bar.bg, bar.surface
//   - bar.sliderPopupHeight, bar.controlBorderWidth, bar.buttonRadius,
//     bar.smallButtonRadius
//   - bar.popupRadius, bar.glassPopupBg, bar.glassPopupBorder,
//     bar.glassPopupHighlight, bar.popupHeaderHighlightHeight,
//     bar.popupSpacing, bar.popupTitleSize, bar.popupSectionSize,
//     bar.popupHintSize, bar.popupButtonHoverBg, bar.dividerStrong
//   - bar.popupAudioWidth, bar.popupAudioHeight
//   - bar.tooltipDelay
//
// Dependencies:
//   - required property var bar
//   - required property Item barBg (for popup positioning)
//   - property bool embedded — when true, omit outer chrome (grouped Net/BT/Audio pill)
//   - property real pillScale — multiplies horizontal content width (BarControlBar Sizes)
//   - Quickshell.Services.Pipewire (volume, channels, PwNodePeakMonitor)
//   - scripts/audio-control.sh (card profile list/set; L/R pactl fallback)
//
// Notes:
//   - Default viewMode is dual (2). Right-click cycles speaker / mic / dual.
//   - Pill volume bars are display-only (interactive: false); wheel still works.
//   - Peak monitors are disabled when the popup is closed (CPU / PipeWire load).
//   - L/R and profile rows hide gracefully for mono / profile-less devices.
// =============================================================================

Rectangle {
    id: root

    required property var bar
    required property Item barBg

    // When true, section inside shared connectivity/audio pill (no own border/bg).
    property bool embedded: false
    // Horizontal scale from BarControlBar Sizes panel (1.0 = default). Height stays fixed.
    property real pillScale: 1.0

    readonly property real _s: (pillScale > 0 ? pillScale : 1)
    readonly property int _sidePad: Math.max(4, Math.round((bar.audioViewSidePadding !== undefined
        ? bar.audioViewSidePadding : 6) * _s))
    readonly property int _barW: Math.max(40, Math.round(110 * _s))
    readonly property int _h: bar.pillHeight
    // Hug the active view's content (speaker / mic / dual) — no fixed 330px blank.
    readonly property int _contentW: {
        var inner = 64
        if (audio.viewMode === 0)
            inner = speakerViewRow.implicitWidth
        else if (audio.viewMode === 1)
            inner = micViewRow.implicitWidth
        else
            inner = dualViewRow.implicitWidth
        return Math.max(64, Math.ceil(inner) + _sidePad * 2)
    }
    readonly property int _outerPad: Math.max(8, Math.round(10 * _s))

    // === Layout ===
    Layout.preferredWidth: embedded
        ? (_contentW + 8)
        : (_contentW + _outerPad)
    Layout.preferredHeight: embedded ? Math.max(18, _h - 8) : _h
    Layout.alignment: Qt.AlignVCenter
    width: Layout.preferredWidth
    height: Layout.preferredHeight
    implicitWidth: Layout.preferredWidth
    implicitHeight: Layout.preferredHeight

    // === Appearance via Theme ===
    // Reliable hover for rim/glow (MouseArea is z:-1 so wheels still work)
    HoverHandler {
        id: audioHoverVis
    }
    readonly property bool audioHovered: audioHoverVis.hovered || audioHover.containsMouse

    // Standalone: stable outer chrome; content chip highlights.
    // Embedded (connectivity pill): this rect is the content chip — hover rim + glow.
    radius: embedded ? bar.workspaceRadius : bar.pillRadius
    color: {
        if (embedded)
            return root.audioHovered ? bar.iconHoverBg : "transparent"
        return bar.pillBg
    }
    border.width: embedded
        ? (root.audioHovered ? bar.controlBorderWidth : 0)
        : bar.controlBorderWidth
    border.color: embedded
        ? (root.audioHovered ? bar.accent : "transparent")
        : bar.pillBorder

    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }
    Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }

    // ===== AUDIO STATE =====
    // Track only our debounced speaker/mic refs — NEVER bind PwObjectTracker to
    // Pipewire.defaultAudioSink/Source directly. Those fire "Default configured
    // sink destroyed" mid-teardown and re-evaluating that binding segfaults qs.
    PwObjectTracker {
        id: audioTracker
        objects: [audio.speaker, audio.mic].filter(function(n){ return !!n; })
    }

    // Path to the shared pactl helper (profiles + optional channel-volume fallback).
    readonly property string audioControlScript: "/home/crome/.config/quickshell/scripts/audio-control.sh"
    readonly property string audioOsdScript: "/home/crome/.config/quickshell/scripts/audio-osd.sh"

    // Debounced swayosd feedback for wheel volume changes (same helper as AudioMonitorView).
    property var _pendingOsd: null
    Timer {
        id: volumeOsdTimer
        interval: 40
        repeat: false
        onTriggered: root.flushVolumeOsd()
    }
    function notifyVolumeOsd(kind, percent, muted) {
        root._pendingOsd = {
            kind: kind || "sink",
            percent: Math.max(0, Math.min(150, Math.round(percent))),
            muted: !!muted
        }
        volumeOsdTimer.restart()
    }
    function flushVolumeOsd() {
        if (!root._pendingOsd) return
        var osd = root._pendingOsd
        root._pendingOsd = null
        Quickshell.execDetached([
            root.audioOsdScript,
            osd.kind,
            String(osd.percent),
            osd.muted ? "1" : "0"
        ])
    }

    QtObject {
        id: audio
        property int viewMode: 2  // 0=speaker, 1=mic, 2=dual (default both)

        property var sinks: []
        property var sources: []

        // System-default nodes for the bar pill. These are PLAIN properties
        // assigned only from refreshDevices() / ensureSelection() after settle —
        // never a live binding to Pipewire.defaultAudioSink (that crashes qs on
        // BT disconnect when the default is destroyed mid-notification).
        property var speaker: null
        property var mic: null
        // Stable names of the live system defaults (updated with speaker/mic).
        property string liveSinkName: ""
        property string liveSourceName: ""

        // Popup selection by stable name only (never store long-lived PwNode
        // pointers outside the sinks/sources arrays rebuilt on refresh).
        property string selectedSinkName: ""
        property string selectedSourceName: ""

        // Bump when device set changes OR we intentionally drop all live refs
        // (disconnect) so selected*/popup* re-resolve to null immediately.
        property int deviceListEpoch: 0
        property string _lastSinkSig: ""
        property string _lastSourceSig: ""

        // Resolve selected name → live node from current list only.
        readonly property var selectedSink: {
            var _ = deviceListEpoch
            return resolveNodeByName(selectedSinkName, true)
        }
        readonly property var selectedSource: {
            var _ = deviceListEpoch
            return resolveNodeByName(selectedSourceName, false)
        }

        // Popup controls operate on the selected device (fall back to system default)
        readonly property var popupSpeaker: {
            var _ = deviceListEpoch
            return selectedSink || speaker
        }
        readonly property var popupMic: {
            var _ = deviceListEpoch
            return selectedSource || mic
        }

        // Popup is expensive; many bindings skip work when closed.
        readonly property bool popupOpen: audioPopup.visible

        // Cached volume/mute for the bar — updated on a timer / after resync, NOT via
        // live bindings to speaker.audio (those re-enter during node destroy → segfault).
        property real speakerVolume: 0.0
        property bool speakerMuted: false
        property real micVolume: 0.0
        property bool micMuted: false

        readonly property int speakerPercent: Math.round(speakerVolume * 100)
        readonly property int micPercent: Math.round(micVolume * 100)

        // Popup volume cache (selected device)
        property real popupSpeakerVolume: 0.0
        property bool popupSpeakerMuted: false
        property real popupMicVolume: 0.0
        property bool popupMicMuted: false
        readonly property int popupSpeakerPercent: Math.round(popupSpeakerVolume * 100)
        readonly property int popupMicPercent: Math.round(popupMicVolume * 100)

        // Read volume only from our held node refs (speaker/mic/popup*), never
        // from Pipewire.defaultAudio* — those can be mid-destroy when a timer fires.
        function syncVolumeCache() {
            try {
                var s = speaker;
                if (s && s.audio) {
                    speakerVolume = s.audio.volume;
                    speakerMuted = !!s.audio.muted;
                }
            } catch (e) { /* keep last known */ }
            try {
                var m = mic;
                if (m && m.audio) {
                    micVolume = m.audio.volume;
                    micMuted = !!m.audio.muted;
                }
            } catch (e2) {}
            if (popupOpen) {
                try {
                    var ps = popupSpeaker;
                    if (ps && ps.audio) {
                        popupSpeakerVolume = ps.audio.volume;
                        popupSpeakerMuted = !!ps.audio.muted;
                    }
                } catch (e3) {}
                try {
                    var pm = popupMic;
                    if (pm && pm.audio) {
                        popupMicVolume = pm.audio.volume;
                        popupMicMuted = !!pm.audio.muted;
                    }
                } catch (e4) {}
            }
        }

        property bool deviceListForSink: true

        // --- Profile list state (playback + recording card profiles) ---
        // Populated asynchronously via list-card-profiles; empty when unavailable.
        property string speakerCard: ""
        property string micCard: ""
        property string speakerProfileActive: ""
        property string micProfileActive: ""
        property var speakerProfiles: []   // [{name, description, available, sinks, sources, priority}]
        property var micProfiles: []
        property bool profileListForSink: true
        property string profileListCard: ""
        property var profileListItems: []

        // ---- Master volume (wpctl BT workaround) — all node access try/catch for disconnect ----
        function setVolume(node, v) {
            if (!node) return;
            try {
                if (node.audio)
                    node.audio.volume = Math.max(0.0, Math.min(1.0, v));
                if (node.id !== undefined) {
                    var pct = Math.round(v * 100);
                    Quickshell.execDetached(["wpctl", "set-volume", String(node.id), pct + "%"]);
                }
                volumeCacheTimer.restart();
            } catch (e) {}
        }
        // isSink: true = speaker/playback (OSD sink icons), false = mic (OSD mic icons)
        function stepVolume(node, delta, isSink) {
            if (!node) return;
            try {
                if (!node.audio) return;
                var nv = Math.max(0.0, Math.min(1.0, node.audio.volume + delta));
                node.audio.volume = nv;
                var pct = Math.round(nv * 100);
                if (node.id !== undefined)
                    Quickshell.execDetached(["wpctl", "set-volume", String(node.id), pct + "%"]);
                root.notifyVolumeOsd(isSink ? "sink" : "source", pct, !!node.audio.muted);
                // Optimistic cache update for snappy bar
                if (isSink) {
                    speakerVolume = nv;
                    if (popupOpen) popupSpeakerVolume = nv;
                } else {
                    micVolume = nv;
                    if (popupOpen) popupMicVolume = nv;
                }
            } catch (e) {}
        }
        function toggleMute(node) {
            if (!node) return;
            try {
                if (node.audio)
                    node.audio.muted = !node.audio.muted;
                volumeCacheTimer.restart();
            } catch (e) {}
        }
        function cycleView() { viewMode = (viewMode + 1) % 3; }

        // Safe property readers — destroyed PwNodes must never throw into QML bindings.
        function safeName(node) {
            if (!node) return "";
            try { return String(node.name || ""); } catch (e) { return ""; }
        }
        function safeDesc(node) {
            if (!node) return "";
            try { return String(node.description || ""); } catch (e) { return ""; }
        }
        function safeId(node) {
            if (!node) return undefined;
            try { return node.id; } catch (e) { return undefined; }
        }
        function safeHasAudio(node) {
            if (!node) return false;
            try { return !!node.audio; } catch (e) { return false; }
        }

        function refreshDevices() {
            var s = [], r = [];
            var sinkSigParts = [], sourceSigParts = [];
            try {
                var vals = (Pipewire.nodes && Pipewire.nodes.values) ? Pipewire.nodes.values : [];
                for (var i = 0; i < vals.length; i++) {
                    var n = vals[i];
                    if (!n) continue;
                    try {
                        if (!n.audio) continue;
                        if (n.isStream) continue;
                        if (isVirtualEcNode(n)) continue;
                        var rawName = safeName(n);
                        if (!rawName || rawName.indexOf(".monitor") >= 0) continue;
                        var label = safeDesc(n) || rawName || "Device";
                        try {
                            if (n.nickname) label = n.description || n.nickname || rawName;
                        } catch (e2) {}
                        if (n.isSink) {
                            s.push({ node: n, name: label, nodeName: rawName });
                            sinkSigParts.push(rawName);
                        } else {
                            r.push({ node: n, name: label, nodeName: rawName });
                            sourceSigParts.push(rawName);
                        }
                    } catch (e1) {
                        // Node vanished mid-iteration (BT disconnect) — skip
                        continue;
                    }
                }
            } catch (e) {
                // Registry churn during disconnect
            }
            var cmp = function(a, b) { return a.name.localeCompare(b.name); };
            s.sort(cmp); r.sort(cmp);
            sinkSigParts.sort();
            sourceSigParts.sort();
            var sinkSig = sinkSigParts.join("\n");
            var sourceSig = sourceSigParts.join("\n");
            var changed = (sinkSig !== _lastSinkSig) || (sourceSig !== _lastSourceSig);

            // Always refresh node object pointers when the name set is unchanged
            // but objects may have been rebound — still assign arrays.
            audio.sinks = s;
            audio.sources = r;
            if (changed) {
                audio._lastSinkSig = sinkSig;
                audio._lastSourceSig = sourceSig;
                audio.deviceListEpoch += 1;
            }

            // Assign bar speaker/mic ONLY from the rebuilt list (never store a raw
            // Pipewire.default* pointer that can be destroyed out from under us).
            var defSinkName = "";
            var defSourceName = "";
            try {
                defSinkName = safeName(Pipewire.defaultAudioSink);
            } catch (eDs) { defSinkName = ""; }
            try {
                defSourceName = safeName(Pipewire.defaultAudioSource);
            } catch (eDm) { defSourceName = ""; }
            // Prefer non-EC hardware when default is echo-cancel virtual node
            try {
                var rawDef = Pipewire.defaultAudioSink;
                if (rawDef && isVirtualEcNode(rawDef)) {
                    var prefS = Pipewire.preferredDefaultAudioSink;
                    var prefSn = safeName(prefS);
                    if (prefSn && !isVirtualEcNode(prefS))
                        defSinkName = prefSn;
                }
            } catch (eEc) {}
            try {
                var rawMic = Pipewire.defaultAudioSource;
                if (rawMic && isVirtualEcNode(rawMic)) {
                    var prefM = Pipewire.preferredDefaultAudioSource;
                    var prefMn = safeName(prefM);
                    if (prefMn && !isVirtualEcNode(prefM))
                        defSourceName = prefMn;
                }
            } catch (eEc2) {}

            liveSinkName = defSinkName;
            liveSourceName = defSourceName;
            speaker = resolveNodeByName(defSinkName, true);
            mic = resolveNodeByName(defSourceName, false);
            // If name not in list yet (registry lag), leave null — next refresh will fill.

            // After refresh: force live defaults when popup closed; soft-fix when open
            ensureSelection(!audioPopup.visible);
            // Keep epoch in lockstep with node pointer identity changes even if names match
            deviceListEpoch += 1;
        }

        // Coalesce rapid PipeWire registry events (BT disconnect floods valuesChanged).
        function scheduleRefreshDevices() {
            root._deviceRefreshPending = true;
            // restart() extends the quiet window so a flood collapses to one scan
            deviceRefreshDebounce.restart();
        }

        // Resolve a stored name to a live node from the current device list only.
        function resolveNodeByName(nodeName, isSink) {
            if (!nodeName || nodeName.length === 0) return null;
            var list = isSink ? sinks : sources;
            for (var i = 0; i < list.length; i++) {
                if (list[i].nodeName === nodeName)
                    return list[i].node;
            }
            return null;
        }

        // Cached names only — do not touch Pipewire.default* (unsafe mid-disconnect).
        function liveDefaultName(isSink) {
            return isSink ? (liveSinkName || "") : (liveSourceName || "");
        }

        // True if a node is one of our virtual echo-cancel devices (not real hardware).
        function isVirtualEcNode(node) {
            var n = safeName(node);
            if (!n) return false;
            return n === "qs_ec_sink" || n === "qs_ec_source"
                || n.indexOf("echo-cancel") >= 0 || n.indexOf("Echo Cancel") >= 0
                || n.indexOf("echo_cancel") >= 0;
        }

        // Transport kind for icons: bluetooth | usb | hdmi | internal
        function deviceTransport(node) {
            if (!node) return "internal";
            try {
                var nm = safeName(node).toLowerCase();
                if (!nm) return "internal";
                var p = {};
                try { p = node.properties || {}; } catch (e) { p = {}; }
                var api = String(p["device.api"] || "").toLowerCase();
                var bus = String(p["device.bus"] || "").toLowerCase();
                if (nm.indexOf("bluez") === 0 || api.indexOf("bluez") >= 0 || bus === "bluetooth")
                    return "bluetooth";
                if (nm.indexOf("hdmi") >= 0 || nm.indexOf("displayport") >= 0 || nm.indexOf("dp-") >= 0)
                    return "hdmi";
                if (bus === "usb" || nm.indexOf("usb-") >= 0 || nm.indexOf(".usb-") >= 0)
                    return "usb";
                if (bus === "pci" || nm.indexOf("pci-") >= 0)
                    return "internal";
            } catch (e) {}
            return "internal";
        }

        function deviceKindIcon(node) {
            var t = deviceTransport(node);
            if (t === "bluetooth")
                return (bar && bar.iconAudioBluetooth) ? bar.iconAudioBluetooth : "󰂯";
            if (t === "usb")
                return (bar && bar.iconAudioUsb) ? bar.iconAudioUsb : "󰕓";
            if (t === "hdmi")
                return (bar && bar.iconAudioHdmi) ? bar.iconAudioHdmi : "󰡁";
            return (bar && bar.iconAudioInternal) ? bar.iconAudioInternal : "󰓃";
        }

        // ---- Bluetooth battery (Quickshell.Bluetooth → BlueZ Battery1) ----
        // Extract MAC from PipeWire bluez node names so we can match BluetoothDevice.address.
        function btMacFromNode(node) {
            var nm = safeName(node);
            if (!nm) return "";
            try {
                if (nm.indexOf("bluez_output.") === 0) {
                    var bout = nm.substring("bluez_output.".length);
                    bout = bout.replace(/\.[0-9]+$/, ""); // strip profile index
                    return bout.replace(/_/g, ":").toUpperCase();
                }
                if (nm.indexOf("bluez_input.") === 0) {
                    var bin = nm.substring("bluez_input.".length);
                    return bin.replace(/_/g, ":").toUpperCase();
                }
            } catch (e) {}
            return "";
        }

        function normalizeMac(addr) {
            return String(addr || "").replace(/[^0-9A-Fa-f]/g, "").toUpperCase();
        }

        // BT battery is polled out-of-process (bluetoothctl) into this map.
        // NEVER bind live to Quickshell.Bluetooth during disconnect — that crashed qs
        // when BlueZ removed Battery1 mid-signal (crash n15x2touit).
        property var btBatteryByMac: ({})

        function batteryPercentForMac(mac) {
            var m = normalizeMac(mac);
            if (!m) return -1;
            var map = btBatteryByMac;
            if (map && map[m] !== undefined && map[m] !== null)
                return Number(map[m]);
            // Also try colon form keys from script
            if (map) {
                for (var k in map) {
                    if (normalizeMac(k) === m)
                        return Number(map[k]);
                }
            }
            return -1;
        }

        // Returns 0–100, or -1 if unknown / not BT / no battery report.
        function batteryPercentForNode(node) {
            return batteryPercentForMac(btMacFromNode(node));
        }

        function batteryColor(pct) {
            if (pct < 0) return bar ? bar.subtext : "#a8b4c8";
            if (pct <= 15) return "#EF4444";
            if (pct <= 30) return "#F59E0B";
            return "#10B981";
        }

        // Polled integers (updated by btBatteryProcess) — not live D-Bus bindings.
        property int speakerBtBattery: -1
        property int micBtBattery: -1
        property int popupSpeakerBtBattery: -1
        property int popupMicBtBattery: -1

        function recomputeBtBatteryDisplay() {
            try {
                // Name-only lookup — never touch speaker/mic PwNode here (disconnect race).
                var sMac = normalizeMac(
                    btMacFromNodeName(selectedSinkName)
                    || btMacFromNodeName(liveSinkName)
                );
                var mMac = normalizeMac(
                    btMacFromNodeName(selectedSourceName)
                    || btMacFromNodeName(liveSourceName)
                );
                speakerBtBattery = batteryPercentForMac(sMac);
                micBtBattery = batteryPercentForMac(mMac);
                if (popupOpen) {
                    popupSpeakerBtBattery = batteryPercentForMac(
                        normalizeMac(btMacFromNodeName(selectedSinkName) || sMac)
                    );
                    popupMicBtBattery = batteryPercentForMac(
                        normalizeMac(btMacFromNodeName(selectedSourceName) || mMac)
                    );
                } else {
                    popupSpeakerBtBattery = -1;
                    popupMicBtBattery = -1;
                }
            } catch (e) {
                speakerBtBattery = -1;
                micBtBattery = -1;
                popupSpeakerBtBattery = -1;
                popupMicBtBattery = -1;
            }
        }

        function btMacFromNodeName(nm) {
            nm = String(nm || "");
            if (nm.indexOf("bluez_output.") === 0) {
                var bout = nm.substring("bluez_output.".length).replace(/\.[0-9]+$/, "");
                return bout.replace(/_/g, ":").toUpperCase();
            }
            if (nm.indexOf("bluez_input.") === 0) {
                return nm.substring("bluez_input.".length).replace(/_/g, ":").toUpperCase();
            }
            return "";
        }

        // True if any current audio path looks like Bluetooth (by name only).
        function anyBluezSelected() {
            try {
                if (selectedSinkName.indexOf("bluez_") === 0) return true;
                if (selectedSourceName.indexOf("bluez_") === 0) return true;
            } catch (e) {}
            return false;
        }

        // Headset-like (Bluetooth or form-factor) — used for recording profile visibility.
        function isHeadsetNode(node) {
            if (!node) return false;
            try {
                if (deviceTransport(node) === "bluetooth") return true;
                var p = {};
                try { p = node.properties || {}; } catch (e) { return false; }
                var form = String(p["device.form_factor"] || p["bluez5.form-factor"] || "").toLowerCase();
                var icon = String(p["device.icon-name"] || "").toLowerCase();
                return form.indexOf("headset") >= 0 || form.indexOf("headphone") >= 0
                    || icon.indexOf("headset") >= 0 || icon.indexOf("headphone") >= 0;
            } catch (e) {
                return false;
            }
        }

        // Recording profile row: only for headsets that expose input-capable card profiles.
        // Skip evaluation when popup is closed.
        readonly property bool showRecordingHeadsetProfile: {
            if (!popupOpen) return false;
            var n = popupMic;
            var _ = micCard;
            var __ = micProfiles;
            var ___ = deviceListEpoch;
            if (!n || !isHeadsetNode(n)) return false;
            if (!micCard || micCard.length === 0) return false;
            var list = filteredProfiles(false);
            return list && list.length > 0;
        }

        function nodesMatch(a, b) {
            if (!a || !b) return false;
            try {
                if (a === b) return true;
                var aid = safeId(a), bid = safeId(b);
                if (aid !== undefined && bid !== undefined && aid === bid) return true;
                var an = safeName(a), bn = safeName(b);
                if (an && bn && an === bn) return true;
                var ad = safeDesc(a), bd = safeDesc(b);
                if (ad && bd && ad === bd) return true;
            } catch (e) {}
            return false;
        }

        // Live system default device (what PipeWire is actually using right now).
        // Prefer defaultAudioSink/Source over preferredDefault* — preferred can be
        // stale across qs restarts while the session default has moved (e.g. BT headset).
        // When echo-cancel is active, default may be qs_ec_*; fall back to preferred.
        function hardwareDefault(isSink) {
            var def = null;
            var pref = null;
            try {
                def = isSink ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource;
            } catch (e) { def = null; }
            try {
                pref = isSink ? Pipewire.preferredDefaultAudioSink : Pipewire.preferredDefaultAudioSource;
            } catch (e2) { pref = null; }

            if (def && !isVirtualEcNode(def) && safeName(def)) return def;
            if (pref && !isVirtualEcNode(pref) && safeName(pref)) return pref;
            // Fall back to first listed hardware device
            var list = isSink ? sinks : sources;
            if (list && list.length > 0 && list[0].node) return list[0].node;
            return null;
        }

        function nameStillListed(nodeName, isSink) {
            if (!nodeName || nodeName.length === 0) return false;
            var list = isSink ? sinks : sources;
            for (var i = 0; i < list.length; i++) {
                if (list[i].nodeName === nodeName) return true;
            }
            return false;
        }

        // Ensure selected*Name track listed hardware.
        // forceLive=true: always snap to the current system defaults (startup / reopen / disconnect).
        // forceLive=false: only fix empty or vanished selections (preserve in-popup picks).
        function ensureSelection(forceLive) {
            var liveSink = hardwareDefault(true);
            var liveSource = hardwareDefault(false);
            var liveSinkName = safeName(liveSink);
            var liveSourceName = safeName(liveSource);

            if (forceLive || !selectedSinkName || !nameStillListed(selectedSinkName, true))
                selectedSinkName = liveSinkName;
            if (forceLive || !selectedSourceName || !nameStillListed(selectedSourceName, false))
                selectedSourceName = liveSourceName;
        }

        // Called when PipeWire defaults change (BT connect/disconnect, etc.).
        // MUST NOT read Pipewire/Bluetooth objects here — only drop local refs and
        // arm delayed timers. Crash ct11cwpuit: "Default configured sink destroyed"
        // + live defaultAudioSink bindings → segfault in QML binding update.
        // Also: root.pwResyncTimer was undefined (Timer ids are not root props), so
        // the settle path never ran after disconnect.
        function onSystemDefaultChanged() {
            // Immediately drop every live PwNode we hold so peak monitors / tracker
            // / volume cache cannot touch a dying OpenRun (or any BT) node.
            try {
                speaker = null;
                mic = null;
                sinks = [];
                sources = [];
                liveSinkName = "";
                liveSourceName = "";
                deviceListEpoch += 1;
            } catch (e) {}
            root._deviceRefreshPending = true;
            deviceRefreshDebounce.restart();
            // Longer settle window after default destroy before force-select.
            pwResyncTimer.restart();
        }

        // Name of the device currently selected in the popup (not necessarily default).
        // Never call hardwareDefault() here — that reads Pipewire.default* and can
        // race a BT disconnect from a binding.
        function getSelectedDeviceName(isSink) {
            var node = isSink ? (selectedSink || speaker) : (selectedSource || mic);
            if (node) {
                var label = safeDesc(node) || safeName(node);
                if (label) return label;
            }
            var nm = isSink ? (selectedSinkName || liveSinkName)
                            : (selectedSourceName || liveSourceName);
            if (nm && nm.length) return nm;
            return "No device";
        }

        function isSelectedSystemDefault(isSink) {
            var selName = isSink ? selectedSinkName : selectedSourceName;
            var liveName = liveDefaultName(isSink);
            if (selName && liveName)
                return selName === liveName;
            // Fallback: compare held node pointers from our safe list only
            return nodesMatch(
                isSink ? selectedSink : selectedSource,
                isSink ? speaker : mic
            );
        }

        // Select a device for popup controls AND make it the live system default.
        function selectDevice(node, forSink) {
            if (!node) return;
            root.setDefaultAudioDevice(node, forSink);
        }

        // ---- L/R channel helpers (stereo devices only) ----
        //
        // Uses PwNodeAudio.channels + .volumes (native Quickshell PipeWire API).
        // Indices prefer FrontLeft/FrontRight; fall back to 0/1 for plain stereo.
        // Mono / missing channel data → hasStereoChannels() is false and UI hides.

        function _channels(node) {
            return (node && node.audio && node.audio.channels) ? node.audio.channels : [];
        }
        function _volumes(node) {
            return (node && node.audio && node.audio.volumes) ? node.audio.volumes : [];
        }

        function hasStereoChannels(node) {
            return _channels(node).length >= 2 && _volumes(node).length >= 2;
        }

        function _findChannelIndex(node, preferEnum, fallbackIndex) {
            var chs = _channels(node);
            for (var i = 0; i < chs.length; i++) {
                if (chs[i] === preferEnum)
                    return i;
            }
            return fallbackIndex;
        }

        function leftChannelIndex(node) {
            return _findChannelIndex(node, PwAudioChannel.FrontLeft, 0);
        }
        function rightChannelIndex(node) {
            return _findChannelIndex(node, PwAudioChannel.FrontRight, 1);
        }

        function channelVolume(node, isLeft) {
            if (!node || !node.audio) return 0.0;
            var vols = _volumes(node);
            if (vols.length === 0) return 0.0;
            var idx = isLeft ? leftChannelIndex(node) : rightChannelIndex(node);
            if (idx < 0 || idx >= vols.length) return vols[0] || 0.0;
            return vols[idx] || 0.0;
        }

        // Popup L/R + stereo — only evaluate while popup is open (bar dual view
        // does not use per-channel bars, so skip that work when closed).
        readonly property real popupSpeakerLeftVolume: {
            if (!popupOpen) return 0
            var n = popupSpeaker
            try {
                var _ = n && n.audio ? n.audio.volumes : null
                var __ = n && n.audio ? n.audio.channels : null
                return channelVolume(n, true)
            } catch (e) { return 0 }
        }
        readonly property real popupSpeakerRightVolume: {
            if (!popupOpen) return 0
            var n = popupSpeaker
            try {
                var _ = n && n.audio ? n.audio.volumes : null
                var __ = n && n.audio ? n.audio.channels : null
                return channelVolume(n, false)
            } catch (e) { return 0 }
        }
        readonly property real popupMicLeftVolume: {
            if (!popupOpen) return 0
            var n = popupMic
            try {
                var _ = n && n.audio ? n.audio.volumes : null
                var __ = n && n.audio ? n.audio.channels : null
                return channelVolume(n, true)
            } catch (e) { return 0 }
        }
        readonly property real popupMicRightVolume: {
            if (!popupOpen) return 0
            var n = popupMic
            try {
                var _ = n && n.audio ? n.audio.volumes : null
                var __ = n && n.audio ? n.audio.channels : null
                return channelVolume(n, false)
            } catch (e) { return 0 }
        }
        readonly property bool popupSpeakerHasStereo: {
            if (!popupOpen) return false
            var n = popupSpeaker
            try {
                var _ = n && n.audio ? n.audio.volumes : null
                var __ = n && n.audio ? n.audio.channels : null
                return hasStereoChannels(n)
            } catch (e) { return false }
        }
        readonly property bool popupMicHasStereo: {
            if (!popupOpen) return false
            var n = popupMic
            try {
                var _ = n && n.audio ? n.audio.volumes : null
                var __ = n && n.audio ? n.audio.channels : null
                return hasStereoChannels(n)
            } catch (e) { return false }
        }

        // Set one channel (L or R) while preserving the other.
        // Writes native volumes + pactl multi-channel set for backend reliability
        // (same class of issue as the master-volume wpctl workaround).
        function setChannelVolume(node, isLeft, v, isSink) {
            if (!node) return;
            try {
                if (!node.audio) return;
                if (!hasStereoChannels(node)) return;

                var clamped = Math.max(0.0, Math.min(1.0, v));
                var li = leftChannelIndex(node);
                var ri = rightChannelIndex(node);
                var leftVol = isLeft ? clamped : channelVolume(node, true);
                var rightVol = isLeft ? channelVolume(node, false) : clamped;

                var vols = _volumes(node);
                var next = [];
                for (var i = 0; i < vols.length; i++)
                    next.push(vols[i]);
                if (li >= 0 && li < next.length) next[li] = leftVol;
                if (ri >= 0 && ri < next.length) next[ri] = rightVol;

                try {
                    node.audio.volumes = next;
                } catch (e) {
                    // Some nodes reject partial channel writes; fall through to pactl.
                }

                var nm = safeName(node);
                if (nm) {
                    var lPct = Math.round(leftVol * 100);
                    var rPct = Math.round(rightVol * 100);
                    var kind = isSink ? "sink" : "source";
                    Quickshell.execDetached([
                        root.audioControlScript, "set-channel-volume",
                        kind, String(nm), String(lPct), String(rPct)
                    ]);
                }
            } catch (e2) {}
        }

        // ---- Card / profile helpers ----
        //
        // PipeWire nodes expose the owning card as properties["device.name"]
        // (e.g. "alsa_card.usb-..."). Bluetooth / virtual devices may omit it;
        // the profile row simply stays hidden in that case.

        function cardNameForNode(node) {
            if (!node) return "";
            try {
                var p = {};
                try { p = node.properties || {}; } catch (e) { p = {}; }
                // Prefer an explicit card id when present (Pulse-compat props).
                if (p["device.name"]) {
                    var dn = String(p["device.name"]);
                    if (dn.indexOf("alsa_card.") === 0 || dn.indexOf("bluez_card.") === 0)
                        return dn;
                }

                var nm = safeName(node);
                if (!nm) return "";

                // ALSA: alsa_output.<card-id>.<profile> → alsa_card.<card-id>
                if (nm.indexOf("alsa_output.") === 0 || nm.indexOf("alsa_input.") === 0) {
                    var rest = nm.replace(/^alsa_(output|input)\./, "");
                    var lastDot = rest.lastIndexOf(".");
                    if (lastDot > 0)
                        return "alsa_card." + rest.substring(0, lastDot);
                }

                // Bluetooth: bluez_output.AA_BB_….N → bluez_card.AA_BB_…
                //            bluez_input.AA:BB:…   → bluez_card.AA_BB_…  (normalize : to _)
                if (nm.indexOf("bluez_output.") === 0) {
                    var bout = nm.substring("bluez_output.".length);
                    bout = bout.replace(/\.[0-9]+$/, "");
                    return "bluez_card." + bout.replace(/:/g, "_");
                }
                if (nm.indexOf("bluez_input.") === 0) {
                    var bin = nm.substring("bluez_input.".length);
                    return "bluez_card." + bin.replace(/:/g, "_");
                }
            } catch (e2) {}
            return "";
        }

        function getProfileLabel(isSink) {
            var active = isSink ? speakerProfileActive : micProfileActive;
            var list = isSink ? speakerProfiles : micProfiles;
            if (!active || active.length === 0)
                return "No profile";
            for (var i = 0; i < list.length; i++) {
                if (list[i].name === active)
                    return list[i].description || active;
            }
            return active;
        }

        // Profiles relevant to a section: playback wants sinks>0, recording sources>0.
        // Always keep the currently active profile visible (even if filtered).
        function filteredProfiles(isSink) {
            var list = isSink ? speakerProfiles : micProfiles;
            var active = isSink ? speakerProfileActive : micProfileActive;
            var out = [];
            for (var i = 0; i < list.length; i++) {
                var p = list[i];
                if (!p || !p.name) continue;
                // Hide the "Off" profile unless it is already active (avoids accidents).
                if (p.name === "off" && p.name !== active)
                    continue;
                var isActive = (p.name === active);
                var hasRole = isSink
                    ? (p.sinks === undefined || Number(p.sinks) > 0)
                    : (p.sources === undefined || Number(p.sources) > 0);
                if (isActive || hasRole)
                    out.push(p);
            }
            return out;
        }

        function applyProfilePayload(isSink, data) {
            if (!data) return;
            var profiles = data.profiles || [];
            if (isSink) {
                speakerCard = data.card || "";
                speakerProfileActive = data.active || "";
                speakerProfiles = profiles;
            } else {
                micCard = data.card || "";
                micProfileActive = data.active || "";
                micProfiles = profiles;
            }
        }
    }

    // Per-section Level meter switches (popup UI). Default on; Off stops sampling
    // for that path so peak monitors stay cheap when the user does not need them.
    property bool speakerLevelMeterOn: true
    property bool micLevelMeterOn: true

    // Collapsible secondary controls in the left-click popup (default collapsed).
    property bool speakerLrExpanded: false
    property bool micLrExpanded: false
    property bool echoCancelExpanded: false

    // Peak meters: bind node only when actively sampling so we never hold a
    // destroyed BT node, and avoid PipeWire peak work when Level is Off / popup closed.
    // Also require a non-empty live/selected name so a mid-disconnect nulling of
    // speaker/mic forces node:null before the dying PwNode is unbound.
    PwNodePeakMonitor {
        id: speakerPeakMon
        node: (audioPopup.visible && root.speakerLevelMeterOn && audio.popupSpeaker)
              ? audio.popupSpeaker : null
        enabled: audioPopup.visible && root.speakerLevelMeterOn && !!audio.popupSpeaker
    }
    PwNodePeakMonitor {
        id: micPeakMon
        node: (audioPopup.visible && root.micLevelMeterOn && audio.popupMic)
              ? audio.popupMic : null
        enabled: audioPopup.visible && root.micLevelMeterOn && !!audio.popupMic
    }

    // Debounce device list rebuilds under PipeWire registry floods (BT disconnect).
    property bool _deviceRefreshPending: false
    Timer {
        id: deviceRefreshDebounce
        interval: 220
        repeat: false
        onTriggered: {
            if (!root._deviceRefreshPending) return;
            root._deviceRefreshPending = false;
            try {
                audio.refreshDevices();
                audio.syncVolumeCache();
            } catch (e) {}
        }
    }

    // After default sink/source destruction, wait longer before force-syncing
    // selection — registry + defaults must fully settle.
    Timer {
        id: pwResyncTimer
        interval: 450
        repeat: false
        onTriggered: {
            try {
                audio.refreshDevices();
                audio.ensureSelection(true);
                audio.syncVolumeCache();
                // Refresh battery after BT drop (map may be empty now)
                root.pollBtBatteries();
            } catch (e) {}
        }
    }

    // Periodic volume cache refresh for the bar (replaces live speaker.audio bindings).
    Timer {
        id: volumeCacheTimer
        interval: 350
        repeat: true
        running: true
        onTriggered: {
            try { audio.syncVolumeCache(); } catch (e) {}
        }
    }

    // ---- Bluetooth battery poll (process-isolated; no live BlueZ QML bindings) ----
    function pollBtBatteries() {
        // Skip work when no bluez path is involved (USB-only sessions).
        if (!audio.anyBluezSelected() && !audioPopup.visible) {
            // Clear stale levels when nothing BT is active
            if (audio.speakerBtBattery >= 0 || audio.micBtBattery >= 0) {
                audio.btBatteryByMac = ({});
                audio.recomputeBtBatteryDisplay();
            }
            return;
        }
        if (btBatteryProcess.running)
            return;
        btBatteryProcess.command = [root.audioControlScript, "bt-battery", "all"];
        btBatteryProcess.running = true;
    }

    Io.Process {
        id: btBatteryProcess
        running: false
        stdout: Io.StdioCollector { id: btBatteryStdout }
        onExited: (code) => {
            if (code !== 0) return;
            try {
                var data = root._parseProfileJson(btBatteryStdout.text);
                if (data && data.devices)
                    audio.btBatteryByMac = data.devices;
                else
                    audio.btBatteryByMac = ({});
                audio.recomputeBtBatteryDisplay();
            } catch (e) {
                audio.btBatteryByMac = ({});
                audio.recomputeBtBatteryDisplay();
            }
        }
    }

    // Poll BT battery slowly; also when popup opens. Never reactive on BlueZ signals.
    Timer {
        id: btBatteryPollTimer
        interval: 8000
        repeat: true
        running: true
        onTriggered: root.pollBtBatteries()
    }

    // Async profile fetch — separate processes for sink/source so stdout never
    // interleaves and either side can refresh independently.
    // Parse JSON from process stdout. Handles both compact one-liners and
    // pretty-printed multi-line objects (list-streams used to fail on the latter
    // when only the last line "}" was parsed).
    function _parseProfileJson(text) {
        var t = (text || "").trim();
        if (!t.length) return null;

        // 1) Whole buffer (pretty multi-line or single object)
        try {
            return JSON.parse(t);
        } catch (e1) {
            // fall through
        }

        // 2) Last non-empty line (compact JSON; also last object if collector accumulated)
        var lines = t.split("\n");
        var last = "";
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();
            if (line.length)
                last = line;
        }
        if (last.length) {
            try {
                return JSON.parse(last);
            } catch (e2) {
                // fall through
            }
        }

        // 3) Last balanced {...} slice in the buffer (robust against prefix junk)
        var start = t.lastIndexOf("{");
        if (start >= 0) {
            var slice = t.substring(start);
            try {
                return JSON.parse(slice);
            } catch (e3) {
                return null;
            }
        }
        return null;
    }

    Io.Process {
        id: speakerProfileProcess
        running: false
        stdout: Io.StdioCollector { id: speakerProfileStdout }
        onExited: (code) => {
            if (code !== 0) return;
            var data = root._parseProfileJson(speakerProfileStdout.text);
            if (data)
                audio.applyProfilePayload(true, data);
        }
    }

    Io.Process {
        id: micProfileProcess
        running: false
        stdout: Io.StdioCollector { id: micProfileStdout }
        onExited: (code) => {
            if (code !== 0) return;
            var data = root._parseProfileJson(micProfileStdout.text);
            if (data)
                audio.applyProfilePayload(false, data);
        }
    }

    Io.Process {
        id: profileSetProcess
        running: false
        // Fire-and-forget; refresh profiles after exit so the label updates.
        onExited: (code) => {
            if (code === 0)
                root.refreshProfiles();
        }
    }

    function _startProfileFetch(isSink) {
        // Profiles follow the device selected in the popup
        var node = isSink ? audio.popupSpeaker : audio.popupMic;
        var card = audio.cardNameForNode(node);
        if (!card || card.length === 0) {
            audio.applyProfilePayload(isSink, { card: "", active: "", profiles: [] });
            return;
        }
        var proc = isSink ? speakerProfileProcess : micProfileProcess;
        if (proc.running)
            proc.running = false;
        proc.command = [root.audioControlScript, "list-card-profiles", card];
        proc.running = true;
    }

    // Refresh both profile lists. Safe to call often (popup open / after set).
    function refreshProfiles() {
        root._startProfileFetch(true);
        root._startProfileFetch(false);
    }

    function setCardProfile(card, profileName) {
        if (!card || !profileName) return;
        if (profileSetProcess.running)
            profileSetProcess.running = false;
        profileSetProcess.command = [
            root.audioControlScript, "set-card-profile", card, profileName
        ];
        profileSetProcess.running = true;
    }

    // =========================================================================
    // Echo cancel (sticky system AEC — permanent preference, reversible Off)
    // =========================================================================
    // Preference: ~/.config/quickshell/echo-cancel.pref  (preferred true/false)
    // Login: systemd user unit quickshell-echo-cancel.service → echo-cancel-apply
    // Backup: Component.onCompleted also runs apply (covers service races).
    //
    // On  → qs_ec_* defaults + preferred=true  (survives reboot)
    // Off → hardware restored + preferred=false (stays off until turned On)
    // Nuclear: audio-control.sh echo-cancel-force-off
    //          systemctl --user disable --now quickshell-echo-cancel.service
    // =========================================================================
    property bool echoCancelEnabled: false
    property bool echoCancelPreferred: false
    property bool echoCancelBusy: false
    property string echoCancelError: ""
    property string echoCancelHint: ""
    property bool echoCancelApplyTried: false

    function applyEchoCancelStatus(data) {
        if (!data) return;
        echoCancelEnabled = !!data.enabled;
        echoCancelPreferred = !!data.preferred;
        echoCancelError = data.error || "";
        if (echoCancelEnabled) {
            echoCancelHint = "On (permanent) · cleaned mic/speakers · Off undoes until you re-enable";
        } else if (echoCancelPreferred && !echoCancelEnabled) {
            echoCancelHint = "Preferred on · applying… (or run echo-cancel-apply if stuck)";
        } else if (echoCancelError.length) {
            echoCancelHint = echoCancelError;
        } else {
            echoCancelHint = "Off · hardware path · turn On to make permanent again";
        }
    }

    function refreshEchoCancelStatus() {
        if (echoCancelStatusProcess.running)
            echoCancelStatusProcess.running = false;
        echoCancelStatusProcess.command = [root.audioControlScript, "echo-cancel-status"];
        echoCancelStatusProcess.running = true;
    }

    // Apply sticky preference at shell start (idempotent; no-op if preferred=false).
    function applyEchoCancelPreference() {
        if (echoCancelBusy) return;
        if (echoCancelApplyProcess.running)
            echoCancelApplyProcess.running = false;
        echoCancelApplyProcess.command = [root.audioControlScript, "echo-cancel-apply"];
        echoCancelApplyProcess.running = true;
    }

    function setEchoCancel(wantOn) {
        if (echoCancelBusy) return;
        echoCancelBusy = true;
        echoCancelError = "";
        if (echoCancelToggleProcess.running)
            echoCancelToggleProcess.running = false;
        // On → preferred=true; Off → preferred=false + restore hardware.
        echoCancelToggleProcess.command = [
            root.audioControlScript,
            wantOn ? "echo-cancel-on" : "echo-cancel-off"
        ];
        echoCancelToggleProcess.running = true;
    }

    // --- Public API (popup toggle + qs ipc call audioPill …) ---
    function setEchoCancelEnabled(enabled) {
        root.setEchoCancel(!!enabled);
    }
    function enableEchoCancel() {
        root.setEchoCancel(true);
    }
    function disableEchoCancel() {
        root.setEchoCancel(false);
    }
    function toggleEchoCancel() {
        root.setEchoCancel(!root.echoCancelEnabled);
    }

    Io.Process {
        id: echoCancelStatusProcess
        running: false
        stdout: Io.StdioCollector { id: echoCancelStatusStdout }
        onExited: (code) => {
            var data = root._parseProfileJson(echoCancelStatusStdout.text);
            if (data)
                root.applyEchoCancelStatus(data);
        }
    }

    Io.Process {
        id: echoCancelToggleProcess
        running: false
        stdout: Io.StdioCollector { id: echoCancelToggleStdout }
        onExited: (code) => {
            root.echoCancelBusy = false;
            var data = root._parseProfileJson(echoCancelToggleStdout.text);
            if (data) {
                root.applyEchoCancelStatus(data);
            } else {
                root.echoCancelError = code === 0 ? "" : "Echo cancel command failed";
                root.refreshEchoCancelStatus();
            }
            // Virtual devices appeared/disappeared — refresh lists + profiles.
            audio.refreshDevices();
            root.refreshProfiles();
        }
    }

    Io.Process {
        id: echoCancelApplyProcess
        running: false
        stdout: Io.StdioCollector { id: echoCancelApplyStdout }
        onExited: (code) => {
            var data = root._parseProfileJson(echoCancelApplyStdout.text);
            if (data)
                root.applyEchoCancelStatus(data);
            else
                root.refreshEchoCancelStatus();
            if (root.echoCancelEnabled)
                audio.refreshDevices();
        }
    }

    // After the bar is up, apply sticky preference once (covers late PipeWire).
    Timer {
        id: echoCancelApplyTimer
        interval: 2500
        repeat: false
        onTriggered: {
            if (!root.echoCancelApplyTried) {
                root.echoCancelApplyTried = true;
                root.applyEchoCancelPreference();
            }
        }
    }

    Component.onCompleted: {
        echoCancelApplyTimer.start();
        // First battery poll after a short settle (avoid race with PW/BT bring-up)
        Qt.callLater(function() { root.pollBtBatteries(); });
    }

    // =========================================================================
    // Active streams summary + audio tools (popup header)
    // =========================================================================
    property var streamPlayback: []
    property var streamRecording: []
    property bool audioRestartBusy: false
    property string audioToolsStatus: ""

    function openPwTop() {
        // Same pattern as SysStatsPill btop/nvtop — dedicated kitty window.
        Quickshell.execDetached(["kitty", "-e", "pw-top"]);
    }

    function restartSoundSystem() {
        if (audioRestartBusy) return;
        audioRestartBusy = true;
        audioToolsStatus = "Restarting audio…";
        if (audioRestartProcess.running)
            audioRestartProcess.running = false;
        audioRestartProcess.command = [root.audioControlScript, "restart-audio"];
        audioRestartProcess.running = true;
    }

    function refreshStreams() {
        if (!audioPopup.visible) return;
        // Don't thrash: skip if a poll is already in flight
        if (streamListProcess.running) return;
        streamListProcess.command = [root.audioControlScript, "list-streams"];
        streamListProcess.running = true;
    }

    function applyStreamsPayload(data) {
        if (!data) return;
        streamPlayback = data.playback || [];
        streamRecording = data.recording || [];
    }

    Io.Process {
        id: streamListProcess
        running: false
        stdout: Io.StdioCollector { id: streamListStdout }
        onExited: (code) => {
            if (code !== 0) return;
            var data = root._parseProfileJson(streamListStdout.text);
            if (data)
                root.applyStreamsPayload(data);
        }
    }

    Io.Process {
        id: audioRestartProcess
        running: false
        stdout: Io.StdioCollector { id: audioRestartStdout }
        onExited: (code) => {
            root.audioRestartBusy = false;
            var data = root._parseProfileJson(audioRestartStdout.text);
            if (code === 0 && data && data.ok) {
                var ecNote = data.echo_cancel_enabled ? " · echo cancel re-applied" : "";
                root.audioToolsStatus = "Audio restarted" + ecNote;
                // Refresh devices, profiles, streams, echo-cancel status after graph rebuild.
                audio.refreshDevices();
                root.refreshProfiles();
                root.refreshEchoCancelStatus();
                root.refreshStreams();
            } else {
                var err = (data && data.error) ? data.error : "Audio restart failed";
                root.audioToolsStatus = err;
            }
            audioToolsStatusClear.restart();
        }
    }

    Timer {
        id: audioToolsStatusClear
        interval: 4000
        onTriggered: root.audioToolsStatus = ""
    }

    // Poll active streams only while the popup is open (pactl parse is non-trivial).
    Timer {
        id: streamPollTimer
        interval: 2000
        repeat: true
        running: audioPopup.visible
        onTriggered: root.refreshStreams()
    }

    Connections {
        target: audioPopup
        function onVisibleChanged() {
            if (audioPopup.visible)
                root.refreshStreams();
        }
    }

    // When the default sink/source changes (BT connect/disconnect, qs start):
    // ONLY restart timers — zero PipeWire object access in the signal handler.
    // (Crash n15x2touit: lookupSingletonProperty during "Default configured sink destroyed".)
    Connections {
        target: Pipewire
        function onDefaultAudioSinkChanged() {
            audio.onSystemDefaultChanged();
        }
        function onDefaultAudioSourceChanged() {
            audio.onSystemDefaultChanged();
        }
        // Do NOT handle defaultConfigured*Changed — those fire while the configured
        // node is being destroyed and are unsafe to react to in QML.
        function onReadyChanged() {
            // Arm delayed resync only; no immediate PipeWire property reads.
            if (Pipewire.ready)
                pwResyncTimer.restart();
        }
    }

    Connections {
        target: Pipewire.nodes
        function onValuesChanged() {
            // Coalesce registry floods; no work in this stack frame.
            audio.scheduleRefreshDevices();
        }
    }

    // PipeWire nodes / defaults can arrive after the bar first loads — re-sync a few times.
    Timer {
        id: audioStartupSyncTimer
        interval: 500
        repeat: true
        property int ticks: 0
        running: true
        onTriggered: {
            ticks += 1;
            audio.scheduleRefreshDevices();
            audio.ensureSelection(true);
            // Stop after defaults look real, or after ~4s
            var sinkOk = false, sourceOk = false, selOk = false;
            try {
                sinkOk = !!(audio.speaker && audio.safeName(audio.speaker));
                sourceOk = !!(audio.mic && audio.safeName(audio.mic));
                selOk = audio.selectedSinkName.length > 0 || audio.selectedSourceName.length > 0;
            } catch (e) {}
            if ((sinkOk && sourceOk && selOk) || ticks >= 8)
                running = false;
        }
    }

    // Content chip: hover rim on contents only (outer pill border stays stable).
    // MouseArea stays on the chip so padding outside does not light the whole pill.
    // When embedded, the outer rect is already the chip (no double chrome).
    Rectangle {
        id: audioContent
        anchors.centerIn: parent
        width: root._contentW
        height: embedded ? parent.height : Math.max(18, parent.height - 8)
        radius: bar.workspaceRadius
        color: {
            if (embedded)
                return "transparent"
            return root.audioHovered ? bar.iconHoverBg : "transparent"
        }
        border.width: (!embedded && root.audioHovered) ? bar.controlBorderWidth : 0
        border.color: (!embedded && root.audioHovered) ? bar.accent : "transparent"
        implicitWidth: width
        implicitHeight: height
        clip: true

        Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }
        Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }

        MouseArea {
            id: audioHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            // Bars are non-interactive (display + wheel only). Clicks open popup / mute / cycle.
            // z below content so WheelHandlers on the bars still receive scroll.
            z: -1

            onClicked: (mouse) => {
                if (mouse.button === Qt.LeftButton) {
                    // Full audio menu (was right-click)
                    showAudioPopup();
                } else if (mouse.button === Qt.MiddleButton) {
                    if (audio.viewMode === 0) audio.toggleMute(audio.speaker);
                    else if (audio.viewMode === 1) audio.toggleMute(audio.mic);
                    else audio.toggleMute(audio.speaker);
                } else if (mouse.button === Qt.RightButton) {
                    // Cycle speaker / mic / dual views
                    audio.cycleView();
                }
            }
        }

        // SPEAKER VIEW
        Row {
            id: speakerViewRow
            visible: audio.viewMode === 0
            anchors.centerIn: parent
            spacing: 6

            Item {
                width: bar.iconSizeTray
                height: bar.iconSizeTray
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    anchors.centerIn: parent
                    text: audio.speakerMuted ? bar.iconSpeakerMuted : bar.iconSpeaker
                    font.pixelSize: bar.iconSizeTray
                    font.family: bar.fontFamily
                    color: audio.speakerMuted ? bar.audioSpeakerIconMuted : bar.audioSpeakerIcon
                }
            }

            Item {
                width: root._barW; height: 18
                anchors.verticalCenter: parent.verticalCenter

                VolumeBar {
                    id: spkBar
                    anchors.centerIn: parent
                    bar: bar
                    interactive: false
                    onSet: function(v){ audio.setVolume(audio.speaker, v); }
                }
                Binding {
                    target: spkBar
                    property: "fill"
                    value: audio.speakerMuted ? bar.sliderFillMuted : bar.audioSpeakerUtilColor(audio.speakerPercent)
                }
                Binding {
                    target: spkBar
                    property: "value"
                    value: audio.speakerVolume
                }

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (e) => {
                        const d = (e.angleDelta.y > 0) ? 0.05 : -0.05;
                        audio.stepVolume(audio.speaker, d, true);
                    }
                }
            }

            Text {
                text: audio.speakerPercent + "%"
                font.pixelSize: bar.fontPillLabel
                font.bold: true
                color: audio.speakerMuted ? bar.muted : bar.audioSpeakerUtilColor(audio.speakerPercent)
                anchors.verticalCenter: parent.verticalCenter
            }
            // vol% | 󰂯 bat%
            Row {
                visible: audio.speakerBtBattery >= 0
                spacing: 4
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    text: "|"
                    font.pixelSize: 11
                    color: bar.subtext
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: (bar && bar.iconAudioBluetooth) ? bar.iconAudioBluetooth : "󰂯"
                    font.pixelSize: 12
                    font.family: bar.fontFamily
                    color: audio.batteryColor(audio.speakerBtBattery)
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: audio.speakerBtBattery + "%"
                    font.pixelSize: 11
                    font.bold: true
                    font.family: bar.fontFamily
                    color: audio.batteryColor(audio.speakerBtBattery)
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // MIC VIEW
        Row {
            id: micViewRow
            visible: audio.viewMode === 1
            anchors.centerIn: parent
            spacing: 6

            Item {
                width: bar.iconSizeTray
                height: bar.iconSizeTray
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    anchors.centerIn: parent
                    text: audio.micMuted ? bar.iconMicMuted : bar.iconMic
                    font.pixelSize: bar.iconSizeTray
                    font.family: bar.fontFamily
                    color: audio.micMuted ? bar.audioMicIconMuted : bar.audioMicIcon
                }
            }

            Item {
                width: root._barW; height: 18
                anchors.verticalCenter: parent.verticalCenter

                VolumeBar {
                    id: micBar
                    anchors.centerIn: parent
                    bar: bar
                    interactive: false
                    onSet: function(v){ audio.setVolume(audio.mic, v); }
                }
                Binding {
                    target: micBar
                    property: "fill"
                    value: audio.micMuted ? bar.sliderFillMuted : bar.audioMicUtilColor(audio.micPercent)
                }
                Binding {
                    target: micBar
                    property: "value"
                    value: audio.micVolume
                }

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (e) => {
                        const d = (e.angleDelta.y > 0) ? 0.05 : -0.05;
                        audio.stepVolume(audio.mic, d, false);
                    }
                }
            }

            Text {
                text: audio.micPercent + "%"
                font.pixelSize: bar.fontPillLabel
                font.bold: true
                color: audio.micMuted ? bar.muted : bar.audioMicUtilColor(audio.micPercent)
                anchors.verticalCenter: parent.verticalCenter
            }
            Row {
                visible: audio.micBtBattery >= 0
                spacing: 4
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    text: "|"
                    font.pixelSize: 11
                    color: bar.subtext
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: (bar && bar.iconAudioBluetooth) ? bar.iconAudioBluetooth : "󰂯"
                    font.pixelSize: 12
                    font.family: bar.fontFamily
                    color: audio.batteryColor(audio.micBtBattery)
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: audio.micBtBattery + "%"
                    font.pixelSize: 11
                    font.bold: true
                    font.family: bar.fontFamily
                    color: audio.batteryColor(audio.micBtBattery)
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // DUAL VIEW (default) — wider: icon + bar + % for speaker and mic
        Row {
            id: dualViewRow
            visible: audio.viewMode === 2
            anchors.centerIn: parent
            spacing: 10

                // --- Speaker half ---
                Row {
                    spacing: 4
                    anchors.verticalCenter: parent.verticalCenter

                    Item {
                        width: bar.iconSizeTray
                        height: bar.iconSizeTray
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: audio.speakerMuted ? bar.iconSpeakerMuted : bar.iconSpeaker
                            font.pixelSize: bar.iconSizeTray
                            font.family: bar.fontFamily
                            color: audio.speakerMuted ? bar.audioSpeakerIconMuted : bar.audioSpeakerIcon
                        }
                    }
                    Item {
                        width: Math.max(32, Math.round((bar.audioDualBarWidth || 72) * root._s))
                        height: 16
                        anchors.verticalCenter: parent.verticalCenter
                        MiniVolumeBar {
                            id: spkMiniBar
                            anchors.centerIn: parent
                            width: parent.width
                            bar: bar
                            interactive: false
                            onSet: function(v){ audio.setVolume(audio.speaker, v); }
                        }
                        Binding {
                            target: spkMiniBar
                            property: "fill"
                            value: audio.speakerMuted ? bar.sliderFillMuted : bar.audioSpeakerUtilColor(audio.speakerPercent)
                        }
                        Binding {
                            target: spkMiniBar
                            property: "value"
                            value: audio.speakerVolume
                        }
                        WheelHandler {
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: (e) => {
                                const d = (e.angleDelta.y > 0) ? 0.05 : -0.05;
                                audio.stepVolume(audio.speaker, d, true);
                            }
                        }
                    }
                    Text {
                        width: bar.audioDualPercentWidth || 34
                        text: audio.speakerPercent + "%"
                        font.pixelSize: bar.fontPillLabel
                        font.bold: true
                        font.family: bar.fontFamily
                        color: audio.speakerMuted ? bar.muted : bar.audioSpeakerUtilColor(audio.speakerPercent)
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                    }
                    // BT battery (playback): vol% | 󰂯 bat%
                    Row {
                        visible: audio.speakerBtBattery >= 0
                        spacing: 3
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            text: "|"
                            font.pixelSize: 10
                            color: bar.subtext
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: (bar && bar.iconAudioBluetooth) ? bar.iconAudioBluetooth : "󰂯"
                            font.pixelSize: 11
                            font.family: bar.fontFamily
                            color: audio.batteryColor(audio.speakerBtBattery)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: audio.speakerBtBattery + "%"
                            font.pixelSize: 10
                            font.bold: true
                            font.family: bar.fontFamily
                            color: audio.batteryColor(audio.speakerBtBattery)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                // Subtle divider between speaker and mic
                Rectangle {
                    width: 1
                    height: 14
                    anchors.verticalCenter: parent.verticalCenter
                    color: bar.dividerStrong
                    opacity: 0.7
                }

                // --- Mic half ---
                Row {
                    spacing: 4
                    anchors.verticalCenter: parent.verticalCenter

                    Item {
                        width: bar.iconSizeTray
                        height: bar.iconSizeTray
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: audio.micMuted ? bar.iconMicMuted : bar.iconMic
                            font.pixelSize: bar.iconSizeTray
                            font.family: bar.fontFamily
                            color: audio.micMuted ? bar.audioMicIconMuted : bar.audioMicIcon
                        }
                    }
                    Item {
                        width: Math.max(32, Math.round((bar.audioDualBarWidth || 72) * root._s))
                        height: 16
                        anchors.verticalCenter: parent.verticalCenter
                        MiniVolumeBar {
                            id: micMiniBar
                            anchors.centerIn: parent
                            width: parent.width
                            bar: bar
                            interactive: false
                            onSet: function(v){ audio.setVolume(audio.mic, v); }
                        }
                        Binding {
                            target: micMiniBar
                            property: "fill"
                            value: audio.micMuted ? bar.sliderFillMuted : bar.audioMicUtilColor(audio.micPercent)
                        }
                        Binding {
                            target: micMiniBar
                            property: "value"
                            value: audio.micVolume
                        }
                        WheelHandler {
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: (e) => {
                                const d = (e.angleDelta.y > 0) ? 0.05 : -0.05;
                                audio.stepVolume(audio.mic, d, false);
                            }
                        }
                    }
                    Text {
                        width: bar.audioDualPercentWidth || 34
                        text: audio.micPercent + "%"
                        font.pixelSize: bar.fontPillLabel
                        font.bold: true
                        font.family: bar.fontFamily
                        color: audio.micMuted ? bar.muted : bar.audioMicUtilColor(audio.micPercent)
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                    }
                    // BT battery (recording) — hide if same MAC already shown on speaker side
                    // (name-based MAC compare — never touch live speaker/mic PwNode in a binding)
                    Row {
                        visible: audio.micBtBattery >= 0
                                 && !(audio.speakerBtBattery >= 0
                                      && audio.btMacFromNodeName(audio.liveSinkName || audio.selectedSinkName)
                                         === audio.btMacFromNodeName(audio.liveSourceName || audio.selectedSourceName)
                                      && audio.btMacFromNodeName(audio.liveSinkName || audio.selectedSinkName).length > 0)
                        spacing: 3
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            text: "|"
                            font.pixelSize: 10
                            color: bar.subtext
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: (bar && bar.iconAudioBluetooth) ? bar.iconAudioBluetooth : "󰂯"
                            font.pixelSize: 11
                            font.family: bar.fontFamily
                            color: audio.batteryColor(audio.micBtBattery)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: audio.micBtBattery + "%"
                            font.pixelSize: 10
                            font.bold: true
                            font.family: bar.fontFamily
                            color: audio.batteryColor(audio.micBtBattery)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
        }
    }

    // ===== AUDIO POPUP (device selectors + full sliders) =====
    PopupWindow {
        id: audioPopup
        anchor.window: bar
        implicitWidth: bar.popupAudioWidth
        implicitHeight: bar.popupAudioHeight
        visible: false
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: bar.popupRadius
            color: bar.glassPopupBg
            border.width: bar.controlBorderWidth
            border.color: bar.glassPopupBorder
            // Keep content (esp. expanded Echo cancel / L/R) inside the rounded frame
            clip: true

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: bar.popupHeaderHighlightHeight
                color: bar.glassPopupHighlight
                radius: parent.radius
                z: 1
            }

            Rectangle {
                z: 20
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 8
                width: 26
                height: 26
                radius: bar.smallButtonRadius !== undefined ? bar.smallButtonRadius : bar.buttonRadius
                color: audioCloseMa.containsMouse
                       ? Qt.rgba(1, 0.24, 0.54, 0.22)
                       : bar.surface
                border.width: 1
                border.color: audioCloseMa.containsMouse ? "#FF3D8A" : bar.dividerStrong
                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: audioCloseMa.containsMouse ? "#FF3D8A" : bar.subtext
                    font.pixelSize: 12
                    font.bold: true
                    font.family: bar.fontFamily
                }
                MouseArea {
                    id: audioCloseMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        audioPopup.visible = false
                        audioDeviceListPopup.visible = false
                        audioProfileListPopup.visible = false
                    }
                }
            }

            // Scroll when content exceeds fixed popup height so Echo cancel
            // never paints over the bottom border.
            Flickable {
                id: audioPopupFlick
                anchors.fill: parent
                anchors.margins: bar.popupSpacing
                contentWidth: width
                contentHeight: audioPopupCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height + 1
                flickableDirection: Flickable.VerticalFlick

                ColumnLayout {
                    id: audioPopupCol
                    width: audioPopupFlick.width
                    spacing: 16

                // Header + tools (top-right: pw-top, restart audio)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "Audio Controls"
                        color: bar.text
                        font.pixelSize: bar.popupTitleSize
                        font.bold: true
                        font.family: bar.fontFamily
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        visible: root.audioToolsStatus.length > 0
                        text: root.audioToolsStatus
                        color: bar.subtext
                        font.pixelSize: 11
                        font.family: bar.fontFamily
                        elide: Text.ElideRight
                        Layout.maximumWidth: 180
                    }
                }

                // -------------------------------------------------------------
                // Active streams (apps currently playing / recording)
                // Between title and Playback — easy to scan at a glance.
                // -------------------------------------------------------------
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: "Active streams"
                        color: bar.text
                        font.pixelSize: bar.popupSectionSize
                        font.bold: true
                        font.family: bar.fontFamily
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(120, Math.max(52, streamCol.implicitHeight + 12))
                        radius: bar.buttonRadius
                        color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                        border.width: bar.controlBorderWidth
                        border.color: bar.dividerStrong
                        clip: true

                        Flickable {
                            anchors.fill: parent
                            anchors.margins: 6
                            contentHeight: streamCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            interactive: contentHeight > height

                            ColumnLayout {
                                id: streamCol
                                width: parent.width
                                spacing: 3

                                // Playback streams
                                Repeater {
                                    model: root.streamPlayback
                                    delegate: RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        required property var modelData

                                        Text {
                                            text: modelData.corked ? "‖" : "▶"
                                            color: modelData.mute ? bar.muted : "#10B981"
                                            font.pixelSize: 11
                                            font.bold: true
                                            Layout.preferredWidth: 14
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.label
                                                  || (modelData.app + (modelData.media ? (" · " + modelData.media) : ""))
                                            color: modelData.mute ? bar.muted : bar.text
                                            font.pixelSize: 12
                                            font.family: bar.fontFamily
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: modelData.mute ? "muted"
                                                  : ((modelData.volume_pct !== undefined ? modelData.volume_pct : 0) + "%")
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            Layout.preferredWidth: 42
                                            horizontalAlignment: Text.AlignRight
                                        }
                                    }
                                }

                                // Recording streams
                                Repeater {
                                    model: root.streamRecording
                                    delegate: RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        required property var modelData

                                        Text {
                                            text: "●"
                                            color: modelData.mute ? bar.muted : "#00F0E0"
                                            font.pixelSize: 11
                                            font.bold: true
                                            Layout.preferredWidth: 14
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: "REC · " + (modelData.label
                                                  || (modelData.app + (modelData.media ? (" · " + modelData.media) : "")))
                                            color: modelData.mute ? bar.muted : bar.text
                                            font.pixelSize: 12
                                            font.family: bar.fontFamily
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: modelData.mute ? "muted"
                                                  : ((modelData.volume_pct !== undefined ? modelData.volume_pct : 0) + "%")
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            Layout.preferredWidth: 42
                                            horizontalAlignment: Text.AlignRight
                                        }
                                    }
                                }

                                Text {
                                    visible: root.streamPlayback.length === 0
                                             && root.streamRecording.length === 0
                                    text: "No active app streams (paused & level-meters hidden)"
                                    color: bar.subtext
                                    font.pixelSize: 11
                                    font.italic: true
                                    font.family: bar.fontFamily
                                }
                            }
                        }
                    }
                }

                // OUTPUT section
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "Playback"
                        color: bar.text
                        font.pixelSize: bar.popupSectionSize
                        font.bold: true
                    }

                    // Device picker with transport icon (Bluetooth / USB / HDMI / internal)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "Device"
                            color: bar.subtext
                            font.pixelSize: 11
                            font.family: bar.fontFamily
                            Layout.preferredWidth: 48
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            radius: bar.buttonRadius
                            color: outDevMouse.containsMouse ? bar.popupButtonHoverBg : Qt.rgba(0.10, 0.10, 0.12, 0.6)
                            border.width: bar.controlBorderWidth
                            border.color: bar.dividerStrong

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 6
                                Text {
                                    text: audio.deviceKindIcon(audio.popupSpeaker)
                                    color: bar.subtext
                                    font.pixelSize: 14
                                    font.family: bar.fontFamily
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: audio.getSelectedDeviceName(true)
                                    color: bar.text
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                                // Bluetooth battery (BlueZ Battery1 via Quickshell.Bluetooth)
                                Row {
                                    visible: audio.popupSpeakerBtBattery >= 0
                                    spacing: 3
                                    Text {
                                        text: (bar && bar.iconAudioBattery) ? bar.iconAudioBattery : "󰁹"
                                        color: audio.batteryColor(audio.popupSpeakerBtBattery)
                                        font.pixelSize: 13
                                        font.family: bar.fontFamily
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: audio.popupSpeakerBtBattery + "%"
                                        color: audio.batteryColor(audio.popupSpeakerBtBattery)
                                        font.pixelSize: 11
                                        font.bold: true
                                        font.family: bar.fontFamily
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                                Text {
                                    text: "▼"
                                    color: bar.subtext
                                    font.pixelSize: 11
                                }
                            }

                            MouseArea {
                                id: outDevMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: openAudioDeviceList(true, outDevMouse)
                            }
                        }
                    }

                    // Playback profile — label outside, matching Device / Level
                    RowLayout {
                        visible: audio.speakerCard.length > 0 && audio.speakerProfiles.length > 0
                        Layout.fillWidth: true
                        spacing: 6

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
                            color: outProfMouse.containsMouse ? bar.popupButtonHoverBg : Qt.rgba(0.10, 0.10, 0.12, 0.45)
                            border.width: bar.controlBorderWidth
                            border.color: bar.dividerStrong

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 6
                                Text {
                                    Layout.fillWidth: true
                                    text: audio.getProfileLabel(true)
                                    color: bar.text
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: "▼"
                                    color: bar.subtext
                                    font.pixelSize: 11
                                }
                            }

                            MouseArea {
                                id: outProfMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: openAudioProfileList(true, outProfMouse)
                            }
                        }
                    }

                    // Master volume — operates on selected playback device
                    // Slight extra top gap so Volume sits a bit lower than Device/Profile.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 8

                        Text {
                            text: "Volume"
                            color: bar.subtext
                            font.pixelSize: 11
                            font.family: bar.fontFamily
                            Layout.preferredWidth: 48
                        }

                        Text {
                            text: audio.popupSpeakerMuted ? bar.iconSpeakerMuted : bar.iconSpeaker
                            font.pixelSize: bar.iconSizePopup
                            font.family: bar.fontFamily
                            color: audio.popupSpeakerMuted ? bar.audioSpeakerIconMuted : bar.audioSpeakerIcon
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 18
                            VolumeBar {
                                id: popupSpkBar
                                anchors.fill: parent
                                anchors.verticalCenter: parent.verticalCenter
                                bar: bar
                                onSet: function(v){ audio.setVolume(audio.popupSpeaker, v); }
                                barHeight: bar ? bar.sliderPopupHeight : 8
                            }
                            Binding {
                                target: popupSpkBar
                                property: "fill"
                                value: audio.popupSpeakerMuted ? bar.sliderFillMuted : bar.audioSpeakerUtilColor(audio.popupSpeakerPercent)
                            }
                            Binding {
                                target: popupSpkBar
                                property: "value"
                                value: audio.popupSpeakerVolume
                            }
                            WheelHandler {
                                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                onWheel: (e) => { const d = (e.angleDelta.y > 0) ? 0.05 : -0.05; audio.stepVolume(audio.popupSpeaker, d, true); }
                            }
                        }

                        Text {
                            text: audio.popupSpeakerPercent + "%"
                            color: audio.popupSpeakerMuted ? bar.muted : bar.audioSpeakerUtilColor(audio.popupSpeakerPercent)
                            font.pixelSize: 13
                            font.bold: true
                            Layout.preferredWidth: 42
                        }

                        Rectangle {
                            width: 52; height: 22; radius: bar.smallButtonRadius
                            color: muteOutMa.containsMouse ? (audio.popupSpeakerMuted ? bar.muted : bar.accent) : bar.surface
                            border.width: bar.controlBorderWidth
                            border.color: bar.dividerStrong

                            Text {
                                anchors.centerIn: parent
                                text: audio.popupSpeakerMuted ? "Unmute" : "Mute"
                                color: muteOutMa.containsMouse ? bar.bg : bar.text
                                font.pixelSize: 11
                                font.bold: true
                            }
                            MouseArea {
                                id: muteOutMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: audio.toggleMute(audio.popupSpeaker)
                            }
                        }
                    }

                    // L / R channel volume (stereo selected playback only) — collapsible
                    // Collapsed: compact "L/R ▸  L% / R%" row. Expanded: full dual bars + ▾.
                    ColumnLayout {
                        visible: audio.popupSpeakerHasStereo
                        Layout.fillWidth: true
                        spacing: 0

                        // Collapsed summary row
                        Item {
                            visible: !root.speakerLrExpanded
                            Layout.fillWidth: true
                            Layout.preferredHeight: 18

                            RowLayout {
                                anchors.fill: parent
                                spacing: 6

                                Item { Layout.preferredWidth: 48; Layout.preferredHeight: 1 }

                                Text {
                                    text: "▸"
                                    color: bar.subtext
                                    font.pixelSize: 11
                                    Layout.preferredWidth: 12
                                }
                                Text {
                                    text: "L/R"
                                    color: bar.subtext
                                    font.pixelSize: 11
                                    font.family: bar.fontFamily
                                    font.bold: true
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: Math.round(audio.popupSpeakerLeftVolume * 100) + " / "
                                          + Math.round(audio.popupSpeakerRightVolume * 100)
                                    color: bar.subtext
                                    font.pixelSize: 11
                                    font.family: bar.fontFamily
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.speakerLrExpanded = true
                            }
                        }

                        // Expanded L/R bars (chevron collapses)
                        RowLayout {
                            visible: root.speakerLrExpanded
                            Layout.fillWidth: true
                            spacing: 8

                            // Collapse control in the label column
                            Item {
                                Layout.preferredWidth: 48
                                Layout.preferredHeight: 14
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.right: parent.right
                                    anchors.rightMargin: 4
                                    text: "▾"
                                    color: bar.subtext
                                    font.pixelSize: 11
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.speakerLrExpanded = false
                                }
                            }

                            Text {
                                text: "L"
                                color: bar.subtext
                                font.pixelSize: 11
                                font.bold: true
                                Layout.preferredWidth: 12
                            }
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 14
                                VolumeBar {
                                    id: popupSpkLBar
                                    anchors.fill: parent
                                    bar: bar
                                    barHeight: 5
                                    onSet: function(v) { audio.setChannelVolume(audio.popupSpeaker, true, v, true); }
                                }
                                Binding {
                                    target: popupSpkLBar
                                    property: "fill"
                                    value: audio.popupSpeakerMuted ? bar.sliderFillMuted : bar.audioSpeakerUtilColor(Math.round(audio.popupSpeakerLeftVolume * 100))
                                }
                                Binding {
                                    target: popupSpkLBar
                                    property: "value"
                                    value: audio.popupSpeakerLeftVolume
                                }
                            }
                            Text {
                                text: Math.round(audio.popupSpeakerLeftVolume * 100) + "%"
                                color: bar.subtext
                                font.pixelSize: 11
                                Layout.preferredWidth: 32
                            }

                            Text {
                                text: "R"
                                color: bar.subtext
                                font.pixelSize: 11
                                font.bold: true
                                Layout.preferredWidth: 12
                            }
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 14
                                VolumeBar {
                                    id: popupSpkRBar
                                    anchors.fill: parent
                                    bar: bar
                                    barHeight: 5
                                    onSet: function(v) { audio.setChannelVolume(audio.popupSpeaker, false, v, true); }
                                }
                                Binding {
                                    target: popupSpkRBar
                                    property: "fill"
                                    value: audio.popupSpeakerMuted ? bar.sliderFillMuted : bar.audioSpeakerUtilColor(Math.round(audio.popupSpeakerRightVolume * 100))
                                }
                                Binding {
                                    target: popupSpkRBar
                                    property: "value"
                                    value: audio.popupSpeakerRightVolume
                                }
                            }
                            Text {
                                text: Math.round(audio.popupSpeakerRightVolume * 100) + "%"
                                color: bar.subtext
                                font.pixelSize: 11
                                Layout.preferredWidth: 32
                            }
                        }
                    }

                    // Playback VU / peak meter + Off switch (right of "Level")
                    // Extra top gap so Level sits a bit lower (matches Volume spacing).
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 6

                        Text {
                            text: "Level"
                            color: bar.subtext
                            font.pixelSize: 11
                            font.family: bar.fontFamily
                            Layout.preferredWidth: 48
                        }

                        Rectangle {
                            width: 40
                            height: 20
                            radius: bar.smallButtonRadius
                            color: {
                                if (spkLevelOffMa.containsMouse)
                                    return root.speakerLevelMeterOn ? bar.muted : bar.accent;
                                return bar.surface;
                            }
                            border.width: bar.controlBorderWidth
                            border.color: bar.dividerStrong

                            Text {
                                anchors.centerIn: parent
                                text: root.speakerLevelMeterOn ? "Off" : "On"
                                color: spkLevelOffMa.containsMouse ? bar.bg : bar.text
                                font.pixelSize: 10
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            MouseArea {
                                id: spkLevelOffMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.speakerLevelMeterOn = !root.speakerLevelMeterOn
                            }
                        }

                        AudioLevelMeter {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 10
                            bar: bar
                            barHeight: 8
                            muted: audio.popupSpeakerMuted || !root.speakerLevelMeterOn
                            level: (audioPopup.visible && root.speakerLevelMeterOn && !audio.popupSpeakerMuted)
                                   ? speakerPeakMon.peak : 0
                            opacity: root.speakerLevelMeterOn ? 1.0 : 0.35
                        }
                    }
                }

                // INPUT section (identical pattern applied)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "Recording"
                        color: bar.text
                        font.pixelSize: bar.popupSectionSize
                        font.bold: true
                    }

                    // Device picker with transport icon (Bluetooth headset, USB mic, etc.)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "Device"
                            color: bar.subtext
                            font.pixelSize: 11
                            font.family: bar.fontFamily
                            Layout.preferredWidth: 48
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            radius: bar.buttonRadius
                            color: inDevMouse.containsMouse ? bar.popupButtonHoverBg : Qt.rgba(0.10, 0.10, 0.12, 0.6)
                            border.width: bar.controlBorderWidth
                            border.color: bar.dividerStrong

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 6
                                Text {
                                    text: audio.deviceKindIcon(audio.popupMic)
                                    color: bar.subtext
                                    font.pixelSize: 14
                                    font.family: bar.fontFamily
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: audio.getSelectedDeviceName(false)
                                    color: bar.text
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                                Row {
                                    visible: audio.popupMicBtBattery >= 0
                                    spacing: 3
                                    Text {
                                        text: (bar && bar.iconAudioBattery) ? bar.iconAudioBattery : "󰁹"
                                        color: audio.batteryColor(audio.popupMicBtBattery)
                                        font.pixelSize: 13
                                        font.family: bar.fontFamily
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: audio.popupMicBtBattery + "%"
                                        color: audio.batteryColor(audio.popupMicBtBattery)
                                        font.pixelSize: 11
                                        font.bold: true
                                        font.family: bar.fontFamily
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                                Text {
                                    text: "▼"
                                    color: bar.subtext
                                    font.pixelSize: 11
                                }
                            }

                            MouseArea {
                                id: inDevMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: openAudioDeviceList(false, inDevMouse)
                            }
                        }
                    }

                    // Headset / Bluetooth profile (HFP vs A2DP, etc.) — only when a
                    // connected headset exposes input-capable card profiles.
                    RowLayout {
                        visible: audio.showRecordingHeadsetProfile
                        Layout.fillWidth: true
                        spacing: 6

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
                            color: inProfMouse.containsMouse ? bar.popupButtonHoverBg : Qt.rgba(0.10, 0.10, 0.12, 0.45)
                            border.width: bar.controlBorderWidth
                            border.color: bar.dividerStrong

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 6
                                Text {
                                    Layout.fillWidth: true
                                    text: audio.getProfileLabel(false)
                                    color: bar.text
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: "▼"
                                    color: bar.subtext
                                    font.pixelSize: 11
                                }
                            }

                            MouseArea {
                                id: inProfMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: openAudioProfileList(false, inProfMouse)
                            }
                        }
                    }

                    // Master volume — operates on selected recording device
                    // Slight extra top gap so Volume sits a bit lower than Device/Profile.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 8

                        Text {
                            text: "Volume"
                            color: bar.subtext
                            font.pixelSize: 11
                            font.family: bar.fontFamily
                            Layout.preferredWidth: 48
                        }

                        Text {
                            text: audio.popupMicMuted ? bar.iconMicMuted : bar.iconMic
                            font.pixelSize: bar.iconSizePopup
                            font.family: bar.fontFamily
                            color: audio.popupMicMuted ? bar.audioMicIconMuted : bar.audioMicIcon
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 18
                            VolumeBar {
                                id: popupMicBar
                                anchors.fill: parent
                                anchors.verticalCenter: parent.verticalCenter
                                bar: bar
                                onSet: function(v){ audio.setVolume(audio.popupMic, v); }
                                barHeight: bar ? bar.sliderPopupHeight : 8
                            }
                            Binding {
                                target: popupMicBar
                                property: "fill"
                                value: audio.popupMicMuted ? bar.sliderFillMuted : bar.audioMicUtilColor(audio.popupMicPercent)
                            }
                            Binding {
                                target: popupMicBar
                                property: "value"
                                value: audio.popupMicVolume
                            }
                            WheelHandler {
                                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                onWheel: (e) => { const d = (e.angleDelta.y > 0) ? 0.05 : -0.05; audio.stepVolume(audio.popupMic, d, false); }
                            }
                        }

                        Text {
                            text: audio.popupMicPercent + "%"
                            color: audio.popupMicMuted ? bar.muted : bar.audioMicUtilColor(audio.popupMicPercent)
                            font.pixelSize: 13
                            font.bold: true
                            Layout.preferredWidth: 42
                        }

                        Rectangle {
                            width: 52; height: 22; radius: bar.smallButtonRadius
                            color: muteInMa.containsMouse ? (audio.popupMicMuted ? bar.muted : bar.accent) : bar.surface
                            border.width: bar.controlBorderWidth
                            border.color: bar.dividerStrong

                            Text {
                                anchors.centerIn: parent
                                text: audio.popupMicMuted ? "Unmute" : "Mute"
                                color: muteInMa.containsMouse ? bar.bg : bar.text
                                font.pixelSize: 11
                                font.bold: true
                            }
                            MouseArea {
                                id: muteInMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: audio.toggleMute(audio.popupMic)
                            }
                        }
                    }

                    // L / R channel volume (stereo selected recording only) — collapsible
                    ColumnLayout {
                        visible: audio.popupMicHasStereo
                        Layout.fillWidth: true
                        spacing: 0

                        // Collapsed summary row
                        Item {
                            visible: !root.micLrExpanded
                            Layout.fillWidth: true
                            Layout.preferredHeight: 18

                            RowLayout {
                                anchors.fill: parent
                                spacing: 6

                                Item { Layout.preferredWidth: 48; Layout.preferredHeight: 1 }

                                Text {
                                    text: "▸"
                                    color: bar.subtext
                                    font.pixelSize: 11
                                    Layout.preferredWidth: 12
                                }
                                Text {
                                    text: "L/R"
                                    color: bar.subtext
                                    font.pixelSize: 11
                                    font.family: bar.fontFamily
                                    font.bold: true
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: Math.round(audio.popupMicLeftVolume * 100) + " / "
                                          + Math.round(audio.popupMicRightVolume * 100)
                                    color: bar.subtext
                                    font.pixelSize: 11
                                    font.family: bar.fontFamily
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.micLrExpanded = true
                            }
                        }

                        // Expanded L/R bars (chevron collapses)
                        RowLayout {
                            visible: root.micLrExpanded
                            Layout.fillWidth: true
                            spacing: 8

                            Item {
                                Layout.preferredWidth: 48
                                Layout.preferredHeight: 14
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.right: parent.right
                                    anchors.rightMargin: 4
                                    text: "▾"
                                    color: bar.subtext
                                    font.pixelSize: 11
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.micLrExpanded = false
                                }
                            }

                            Text {
                                text: "L"
                                color: bar.subtext
                                font.pixelSize: 11
                                font.bold: true
                                Layout.preferredWidth: 12
                            }
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 14
                                VolumeBar {
                                    id: popupMicLBar
                                    anchors.fill: parent
                                    bar: bar
                                    barHeight: 5
                                    onSet: function(v) { audio.setChannelVolume(audio.popupMic, true, v, false); }
                                }
                                Binding {
                                    target: popupMicLBar
                                    property: "fill"
                                    value: audio.popupMicMuted ? bar.sliderFillMuted : bar.audioMicUtilColor(Math.round(audio.popupMicLeftVolume * 100))
                                }
                                Binding {
                                    target: popupMicLBar
                                    property: "value"
                                    value: audio.popupMicLeftVolume
                                }
                            }
                            Text {
                                text: Math.round(audio.popupMicLeftVolume * 100) + "%"
                                color: bar.subtext
                                font.pixelSize: 11
                                Layout.preferredWidth: 32
                            }

                            Text {
                                text: "R"
                                color: bar.subtext
                                font.pixelSize: 11
                                font.bold: true
                                Layout.preferredWidth: 12
                            }
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 14
                                VolumeBar {
                                    id: popupMicRBar
                                    anchors.fill: parent
                                    bar: bar
                                    barHeight: 5
                                    onSet: function(v) { audio.setChannelVolume(audio.popupMic, false, v, false); }
                                }
                                Binding {
                                    target: popupMicRBar
                                    property: "fill"
                                    value: audio.popupMicMuted ? bar.sliderFillMuted : bar.audioMicUtilColor(Math.round(audio.popupMicRightVolume * 100))
                                }
                                Binding {
                                    target: popupMicRBar
                                    property: "value"
                                    value: audio.popupMicRightVolume
                                }
                            }
                            Text {
                                text: Math.round(audio.popupMicRightVolume * 100) + "%"
                                color: bar.subtext
                                font.pixelSize: 11
                                Layout.preferredWidth: 32
                            }
                        }
                    }

                    // Recording VU / peak meter + Off switch (right of "Level")
                    // Extra top gap so Level sits a bit lower (matches Volume spacing).
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 6

                        Text {
                            text: "Level"
                            color: bar.subtext
                            font.pixelSize: 11
                            font.family: bar.fontFamily
                            Layout.preferredWidth: 48
                        }

                        // Compact On/Off for this meter only (does not mute audio)
                        Rectangle {
                            width: 40
                            height: 20
                            radius: bar.smallButtonRadius
                            color: {
                                if (micLevelOffMa.containsMouse)
                                    return root.micLevelMeterOn ? bar.muted : bar.accent;
                                return bar.surface;
                            }
                            border.width: bar.controlBorderWidth
                            border.color: bar.dividerStrong

                            Text {
                                anchors.centerIn: parent
                                text: root.micLevelMeterOn ? "Off" : "On"
                                color: micLevelOffMa.containsMouse ? bar.bg : bar.text
                                font.pixelSize: 10
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            MouseArea {
                                id: micLevelOffMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.micLevelMeterOn = !root.micLevelMeterOn
                            }
                        }

                        AudioLevelMeter {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 10
                            bar: bar
                            barHeight: 8
                            muted: audio.popupMicMuted || !root.micLevelMeterOn
                            level: (audioPopup.visible && root.micLevelMeterOn && !audio.popupMicMuted)
                                   ? micPeakMon.peak : 0
                            opacity: root.micLevelMeterOn ? 1.0 : 0.35
                        }
                    }

                    // ---------------------------------------------------------
                    // Echo cancel (system AEC for speaker→mic bleed) — collapsible
                    // Fully reversible: Off restores prior hardware defaults.
                    // Does not edit PipeWire conf; safe alongside Meet/Discord.
                    // Hidden entirely when Options → “Show echo cancel in audio menu” is off.
                    // ---------------------------------------------------------
                    ColumnLayout {
                        visible: bar.showEchoCancelInMenu !== false
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        spacing: 4

                        // Header always visible: chevron + title + compact state when collapsed
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 24

                            RowLayout {
                                anchors.fill: parent
                                spacing: 8

                                Text {
                                    text: root.echoCancelExpanded ? "▾" : "▸"
                                    color: bar.subtext
                                    font.pixelSize: 12
                                    Layout.preferredWidth: 12
                                }
                                Text {
                                    text: "Echo cancel"
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.family: bar.fontFamily
                                    font.bold: true
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    visible: !root.echoCancelExpanded
                                    text: root.echoCancelBusy
                                          ? "…"
                                          : (root.echoCancelEnabled ? "On" : "Off")
                                    color: root.echoCancelEnabled ? bar.accent : bar.subtext
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.echoCancelExpanded = !root.echoCancelExpanded
                            }
                        }

                        // Expanded body: toggle + hint
                        ColumnLayout {
                            visible: root.echoCancelExpanded
                            Layout.fillWidth: true
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Item { Layout.preferredWidth: 12; Layout.preferredHeight: 1 }

                                Text {
                                    text: "Enable"
                                    color: bar.subtext
                                    font.pixelSize: 11
                                    font.family: bar.fontFamily
                                }

                                Item { Layout.fillWidth: true }

                                // Toggle button — label always shows the action / state clearly
                                Rectangle {
                                    width: 72
                                    height: 24
                                    radius: bar.smallButtonRadius
                                    opacity: root.echoCancelBusy ? 0.6 : 1.0
                                    color: {
                                        if (echoCancelToggleMa.containsMouse)
                                            return root.echoCancelEnabled ? bar.muted : bar.accent;
                                        return root.echoCancelEnabled ? bar.accent : bar.surface;
                                    }
                                    border.width: bar.controlBorderWidth
                                    border.color: bar.dividerStrong

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.echoCancelBusy
                                              ? "…"
                                              : (root.echoCancelEnabled ? "On" : "Off")
                                        color: {
                                            if (echoCancelToggleMa.containsMouse)
                                                return bar.bg;
                                            return root.echoCancelEnabled ? bar.bg : bar.text;
                                        }
                                        font.pixelSize: 12
                                        font.bold: true
                                        font.family: bar.fontFamily
                                    }

                                    MouseArea {
                                        id: echoCancelToggleMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: root.echoCancelBusy ? Qt.BusyCursor : Qt.PointingHandCursor
                                        enabled: !root.echoCancelBusy
                                        onClicked: root.setEchoCancel(!root.echoCancelEnabled)
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.leftMargin: 20
                                // Keep hint inside card; avoid long lines painting past the border
                                Layout.bottomMargin: 2
                                text: root.echoCancelHint.length
                                      ? root.echoCancelHint
                                      : "Sticky preference · survives reboot when On"
                                color: root.echoCancelError.length ? bar.muted : bar.subtext
                                font.pixelSize: 10
                                font.family: bar.fontFamily
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        width: pwTopLabel.implicitWidth + 16
                        height: 24
                        radius: bar.smallButtonRadius
                        color: pwTopMa.containsMouse ? bar.popupButtonHoverBg : bar.surface
                        border.width: bar.controlBorderWidth
                        border.color: bar.dividerStrong
                        Text {
                            id: pwTopLabel
                            anchors.centerIn: parent
                            text: "pw-top"
                            color: bar.text
                            font.pixelSize: 11
                            font.bold: true
                            font.family: bar.fontFamily
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
                        width: restartLabel.implicitWidth + 16
                        height: 24
                        radius: bar.smallButtonRadius
                        opacity: root.audioRestartBusy ? 0.6 : 1.0
                        color: restartMa.containsMouse ? bar.accent : bar.surface
                        border.width: bar.controlBorderWidth
                        border.color: bar.dividerStrong
                        Text {
                            id: restartLabel
                            anchors.centerIn: parent
                            text: root.audioRestartBusy ? "Restarting…" : "Restart audio"
                            color: restartMa.containsMouse ? bar.bg : bar.text
                            font.pixelSize: 11
                            font.bold: true
                            font.family: bar.fontFamily
                        }
                        MouseArea {
                            id: restartMa
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !root.audioRestartBusy
                            cursorShape: root.audioRestartBusy ? Qt.BusyCursor : Qt.PointingHandCursor
                            onClicked: root.restartSoundSystem()
                        }
                    }
                }
                } // audioPopupCol
            } // audioPopupFlick

            MouseArea {
                anchors.fill: parent
                z: -1
                onClicked: {
                    audioPopup.visible = false
                    audioDeviceListPopup.visible = false
                    audioProfileListPopup.visible = false
                }
            }
        } // glass chrome
    }

    // Device list popup (shared) — same centralization pattern applied
    // Anchor is set at open time via positionSecondaryPopup() so the list can
    // attach to the Device row (Playback/Recording) instead of the bar bottom.
    PopupWindow {
        id: audioDeviceListPopup
        implicitWidth: 380
        implicitHeight: Math.min(420, Math.max(100, (audio.deviceListForSink ? audio.sinks.length : audio.sources.length) * 40 + 90))
        visible: false
        color: "transparent"

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
                spacing: 4

                Text {
                    text: audio.deviceListForSink ? "Select Playback Device" : "Select Recording Device"
                    color: bar.text
                    font.pixelSize: bar.popupSectionSize
                    font.bold: true
                }

                Text {
                    text: "Selecting a device makes it Active (live routing)"
                    color: bar.subtext
                    font.pixelSize: 10
                    font.family: bar.fontFamily
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Item { Layout.preferredHeight: 2 }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    Repeater {
                        model: audio.deviceListForSink ? audio.sinks : audio.sources
                        delegate: Rectangle {
                            id: devRow
                            Layout.fillWidth: true
                            Layout.preferredHeight: 30
                            radius: bar.buttonRadius
                            // Hover via either the row or the Default button
                            color: (rowDevMa.containsMouse || setDefMa.containsMouse)
                                   ? bar.surface : "transparent"

                            required property var modelData
                            // Selected for popup controls (not necessarily system default)
                            readonly property bool isSelected: root.isSelectedDevice(modelData)
                            // System fallback device
                            readonly property bool isDefault: root.isSystemDefaultDevice(modelData)

                            // Full-row click = select device for Volume/Level/etc (NOT system default)
                            MouseArea {
                                id: rowDevMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: audio.selectDevice(modelData.node, audio.deviceListForSink)
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 6
                                spacing: 8
                                z: 1

                                Text {
                                    visible: devRow.isSelected
                                    text: "›"
                                    color: bar.accent
                                    font.pixelSize: 14
                                    font.bold: true
                                }

                                Text {
                                    text: audio.deviceKindIcon(modelData.node)
                                    color: bar.subtext
                                    font.pixelSize: 13
                                    font.family: bar.fontFamily
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.bold: devRow.isSelected
                                    elide: Text.ElideRight
                                }

                                // Active indicator / switch (live system routing)
                                Rectangle {
                                    Layout.preferredWidth: devRow.isDefault ? 54 : 72
                                    Layout.preferredHeight: 22
                                    radius: bar.smallButtonRadius
                                    color: {
                                        if (devRow.isDefault)
                                            return bar.accent;
                                        if (setDefMa.containsMouse)
                                            return bar.popupButtonHoverBg;
                                        return bar.surface;
                                    }
                                    border.width: bar.controlBorderWidth
                                    border.color: bar.dividerStrong

                                    Text {
                                        anchors.centerIn: parent
                                        text: devRow.isDefault ? "Active" : "Set Active"
                                        color: devRow.isDefault ? bar.bg : bar.text
                                        font.pixelSize: 10
                                        font.bold: true
                                        font.family: bar.fontFamily
                                    }
                                    MouseArea {
                                        id: setDefMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: (mouse) => {
                                            mouse.accepted = true;
                                            root.setDefaultAudioDevice(modelData.node, audio.deviceListForSink);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        visible: (audio.deviceListForSink ? audio.sinks.length : audio.sources.length) === 0
                        text: "(no devices)"
                        color: bar.subtext
                        font.pixelSize: 11
                        font.italic: true
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: audioDeviceListPopup.visible = false
        }
    }

    // Card profile list popup (shared by Playback + Recording profile rows)
    // Anchor set at open time (same as device list — over Profile row, not bar).
    PopupWindow {
        id: audioProfileListPopup
        implicitWidth: 340
        implicitHeight: Math.min(420, Math.max(100, audio.profileListItems.length * 32 + 70))
        visible: false
        color: "transparent"

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
                spacing: 4

                Text {
                    text: audio.profileListForSink ? "Playback Profile" : "Recording Profile"
                    color: bar.text
                    font.pixelSize: bar.popupSectionSize
                    font.bold: true
                }

                Item { Layout.preferredHeight: 4 }

                // Scrollable-ish list: ColumnLayout + Repeater (same pattern as devices)
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: profileCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: profileCol
                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: audio.profileListItems
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 28
                                radius: bar.buttonRadius
                                color: rowProfMa.containsMouse ? bar.surface : "transparent"
                                opacity: (modelData.available === false) ? 0.45 : 1.0

                                required property var modelData

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 6
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.description || modelData.name
                                        color: bar.text
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        visible: modelData.name === (audio.profileListForSink
                                            ? audio.speakerProfileActive
                                            : audio.micProfileActive)
                                        text: "✓"
                                        color: bar.accent
                                        font.pixelSize: 13
                                    }
                                }

                                MouseArea {
                                    id: rowProfMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    // Allow selecting unavailable profiles only if already active
                                    // (user may need to leave a dead profile); otherwise require available.
                                    onClicked: {
                                        if (modelData.available === false
                                            && modelData.name !== (audio.profileListForSink
                                                ? audio.speakerProfileActive
                                                : audio.micProfileActive)) {
                                            return
                                        }
                                        var card = audio.profileListCard
                                        if (card && modelData.name) {
                                            root.setCardProfile(card, modelData.name)
                                        }
                                        audioProfileListPopup.visible = false
                                    }
                                }
                            }
                        }

                        Text {
                            visible: audio.profileListItems.length === 0
                            text: "(no profiles)"
                            color: bar.subtext
                            font.pixelSize: 11
                            font.italic: true
                        }
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: audioProfileListPopup.visible = false
        }
    }

    // Is this list entry the one currently selected for popup controls?
    function isSelectedDevice(dev) {
        if (!dev || !dev.nodeName) return false
        var selName = audio.deviceListForSink ? audio.selectedSinkName : audio.selectedSourceName
        return selName.length > 0 && selName === dev.nodeName
    }

    // Is this list entry the system default / fallback device?
    function isSystemDefaultDevice(dev) {
        if (!dev || !dev.nodeName) return false
        var liveName = audio.liveDefaultName(audio.deviceListForSink)
        return liveName.length > 0 && liveName === dev.nodeName
    }

    // Back-compat alias (device list Active badge)
    function isCurrentDevice(dev) {
        return root.isSystemDefaultDevice(dev)
    }

    // Select + set system default sink/source so the device is immediately live.
    // Uses Quickshell preferredDefault + pactl for reliability.
    // Stores selection by name only — never keeps a raw PwNode after return.
    function setDefaultAudioDevice(node, forSink) {
        if (!node) return

        var nm = audio.safeName(node)
        var label = audio.safeDesc(node) || nm || "device"
        if (!nm || nm.indexOf("qs_ec_") === 0)
            return

        // Update popup selection by stable name (survives node rebuilds).
        if (forSink)
            audio.selectedSinkName = nm
        else
            audio.selectedSourceName = nm

        try {
            if (forSink)
                Pipewire.preferredDefaultAudioSink = node
            else
                Pipewire.preferredDefaultAudioSource = node
        } catch (e) {
            // fall through to pactl
        }

        Quickshell.execDetached([
            root.audioControlScript,
            "set-default",
            forSink ? "sink" : "source",
            String(nm)
        ])

        audioDeviceListPopup.visible = false
        root.audioToolsStatus = "Live: " + label
        audioToolsStatusClear.restart()

        // Defer profile fetch — node registry may still be settling.
        Qt.callLater(function() {
            try {
                root._startProfileFetch(forSink)
                if (root.echoCancelPreferred || root.echoCancelEnabled)
                    deviceChangeEcTimer.restart()
                else if (audioPopup.visible)
                    root.refreshStreams()
            } catch (e2) {}
        })
    }

    // Brief delay so pactl/preferred settle, then re-apply echo cancel on new masters.
    Timer {
        id: deviceChangeEcTimer
        interval: 350
        repeat: false
        onTriggered: {
            // apply path rebuilds qs_ec_* from the new defaults
            root.applyEchoCancelPreference()
            if (audioPopup.visible) {
                root.refreshProfiles()
                root.refreshStreams()
            }
        }
    }

    // Position a secondary flyout next to the row that opened it (Device / Profile),
    // instead of re-anchoring to the bottom bar. Falls back to bar-bottom placement
    // if no target item is available.
    function positionSecondaryPopup(popup, targetItem) {
        if (targetItem) {
            // Attach to the clicked Device/Profile control so the list sits over
            // Playback or Recording rather than gravitating to the bar edge.
            popup.anchor.item = targetItem
            // Anchor to the top-left of the control; expand down/right so the menu
            // hovers over that section of the main audio popup.
            popup.anchor.edges = Edges.Top | Edges.Left
            popup.anchor.gravity = Edges.Bottom | Edges.Right
            popup.anchor.margins.top = 0
            popup.anchor.margins.left = 0
            popup.anchor.adjustment = PopupAdjustment.All
            // Point-anchor at the control's top-left so the menu lines up with the row.
            popup.anchor.rect.x = 0
            popup.anchor.rect.y = 0
            popup.anchor.rect.width = 1
            popup.anchor.rect.height = Math.max(1, targetItem.height)
        } else {
            var popupW = popup.implicitWidth
            var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920
            if (typeof bar.placePopup === "function") {
                bar.placePopup(popup, root, popupW, popup.implicitHeight, 46, 0, popupW / 2)
            } else {
                var p = root.mapToItem(barBg, 0, root.height)
                var baseX = bar.sideMargin + p.x
                popup.anchor.window = bar
                popup.anchor.rect.x = Math.min(baseX, screenW - popupW - 12)
                popup.anchor.rect.y = bar.popupAnchorY(popup.implicitHeight, 46)
            }
        }
    }

    function openAudioDeviceList(forSink, targetItem) {
        audio.deviceListForSink = forSink
        // Close sibling flyouts so only one secondary popup is open.
        audioProfileListPopup.visible = false
        positionSecondaryPopup(audioDeviceListPopup, targetItem)
        audioDeviceListPopup.visible = true
        // Item may have moved since last open (popup layout); refresh anchor.
        if (targetItem && audioDeviceListPopup.anchor)
            audioDeviceListPopup.anchor.updateAnchor()
    }

    function openAudioProfileList(forSink, targetItem) {
        audio.profileListForSink = forSink
        audio.profileListCard = forSink ? audio.speakerCard : audio.micCard
        audio.profileListItems = audio.filteredProfiles(forSink)
        audioDeviceListPopup.visible = false

        if (!audio.profileListCard || audio.profileListItems.length === 0)
            return

        positionSecondaryPopup(audioProfileListPopup, targetItem)
        audioProfileListPopup.visible = true
        if (targetItem && audioProfileListPopup.anchor)
            audioProfileListPopup.anchor.updateAnchor()
    }

    function showAudioPopup() {
        if (audioPopup.visible) {
            audioPopup.visible = false
            audioDeviceListPopup.visible = false
            audioProfileListPopup.visible = false
            return
        }

        var popupW = audioPopup.implicitWidth
        if (typeof bar.placePopup === "function") {
            bar.placePopup(audioPopup, root, popupW, audioPopup.implicitHeight, undefined, root.width / 2, 60)
        } else {
            var pos = root.mapToItem(barBg, root.width / 2, root.height)
            var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920
            var targetX = bar.sideMargin + pos.x - (popupW / 2) + 60
            var minX = 12
            var maxX = screenW - popupW - 12
            audioPopup.anchor.rect.x = Math.max(minX, Math.min(targetX, maxX))
            audioPopup.anchor.rect.y = bar.popupAnchorY(audioPopup.implicitHeight)
        }

        // Always open on the live system defaults (forceLive).
        audio.refreshDevices()
        audio.ensureSelection(true)
        root.refreshProfiles()
        root.refreshEchoCancelStatus()
        // One immediate stream snapshot; timer keeps it fresh while open
        root.refreshStreams()
        root.pollBtBatteries()
        audioPopup.visible = true
    }
}
