<!-- Extracted from README for reference. See ../README.md for overview. -->

# Audio pill (`AudioPill.qml`)

Bar pill for speaker + mic control (default view is **dual**: both bars with percent labels).

| Input | Action |
|-------|--------|
| **Left-click** | Open / close the full **Audio Controls** popup |
| **Right-click** | Cycle pill layout: speaker only → mic only → dual |
| **Middle-click** | Mute (speaker in dual/speaker view; mic in mic-only view) |
| **Scroll on a bar** | Step that device’s volume (swayosd-style feedback via `audio-osd.sh`) |

Pill volume bars are display + wheel only (no click-drag). Volume % and mute state are **cached** and refreshed on a short timer so the bar never holds a live binding into a dying PipeWire node.

## Popup controls

| Area | Controls |
|------|----------|
| **Header** | Active app streams summary |
| **Footer** | **pw-top**, **Restart audio** |
| **Playback** | Device picker (transport icon + optional BT battery), card **Profile**, master **Volume** + mute, collapsible **L/R**, **Level** VU meter |
| **Recording** | Same pattern; headset **Profile** when the input device exposes card profiles; collapsible **Echo cancel** |

- **Device** — selecting a device makes it the **live system default** (PipeWire preferred default + routing). Device and profile flyouts anchor to the row you clicked (over Playback / Recording), not the bottom of the screen.
- **Profile** — PipeWire/Pulse card profiles via `audio-control.sh list-card-profiles` / `set-card-profile`. Playback profiles show for cards with sinks; recording profiles show for headset-style inputs. Hidden when no card/profiles exist.
- **Volume / Level** — slightly extra vertical gap under Device/Profile so the bars don’t feel cramped. Level uses `PwNodePeakMonitor` + `components/AudioLevelMeter.qml`; sampling runs only while the popup is open and the section Level switch is On.
- **L/R** — stereo balance only (`PwNodeAudio.volumes` + `pactl` multi-channel write). **Collapsed by default**; click `▸ L/R` (summary shows `L% / R%`) to expand dual sliders, or `▾` to collapse again. Hidden for mono devices.
- **Echo cancel** — **Collapsed by default**; header shows On/Off status. Expand for the toggle + sticky-preference hint.
- **BT battery** — polled via `audio-control.sh bt-battery` (BlueZ Battery1), shown on the pill and in the popup when available. Name/MAC based — no live BlueZ property bindings in the UI path.
- Popup size: `popupAudioWidth` / `popupAudioHeight` in `Config.qml`.
Popup content scrolls in a `Flickable` when tall (expanded L/R or Echo cancel) so chrome borders stay intact.

## Stability (Bluetooth disconnect)

BT headsets (e.g. OpenRun Pro 2) destroy their PipeWire nodes and the default sink on disconnect. A live QML binding to `Pipewire.defaultAudioSink` during that teardown used to segfault Quickshell (`Default configured sink destroyed`).

Hardening approach:

| Practice | Detail |
|----------|--------|
| **Name-based selection** | Popup selection is stored as sink/source **names**, re-resolved from the current device list |
| **No live default bindings** | Bar `speaker` / `mic` are plain properties assigned only after a debounced device refresh from the safe list — never a continuous binding to `Pipewire.defaultAudio*` |
| **Immediate drop on default change** | On default sink/source change, clear held `PwNode` refs and device arrays, then resync after settle (`deviceRefreshDebounce` + `pwResyncTimer`) |
| **Volume cache** | Pill % / mute / popup master volume read from cache, not from a dying node mid-notification |
| **Peak monitors gated** | `PwNodePeakMonitor.node` is null unless the popup is open, Level is On, and a resolved node exists |
| **Battery by name** | BT battery display uses node **names** / MACs only (process-isolated `bt-battery`), not live D-Bus bindings on the node |

If `qs` ever crashes on disconnect again, check `~/.cache/quickshell/crashes/*/report.txt` and the log tail for `Default configured sink destroyed`.

## Echo cancel (system AEC)

Optional **WebRTC acoustic echo cancellation** for speaker bleed into the mic (e.g. YouTube on speakers while the mic is open). Uses PipeWire `module-echo-cancel` and temporary virtual devices:

| Node | Role |
|------|------|
| `qs_ec_source` | Cleaned default microphone |
| `qs_ec_sink` | Default playback path used as the AEC reference |

Meet, Telegram, and Discord follow system defaults, so they pick up `qs_ec_*` while echo cancel is **On**, and hardware again when **Off**. App-built-in AEC is left alone; if a call sounds odd, turn Off.

| Mechanism | Purpose |
|-----------|---------|
| `echo-cancel.pref` | Sticky preference `{"preferred":true\|false}` under this config dir (not committed; per-machine) |
| `scripts/audio-control.sh` | `echo-cancel-status` / `on` / `off` / `force-off` / `apply` |
| `quickshell-echo-cancel.service` | User systemd unit (under `~/.config/systemd/user/`) runs `echo-cancel-apply` after PipeWire at login |
| AudioPill + IPC | Collapsible UI toggle and `qs ipc call audioPill …` (same sticky on/off) |

**Enable / disable**

```bash
# UI: left-click audio pill → expand Echo cancel → On/Off

# IPC (sticky across reboot when On)
qs ipc call audioPill enableEchoCancel
qs ipc call audioPill disableEchoCancel
qs ipc call audioPill setEchoCancel true
qs ipc call audioPill toggleEchoCancel

# CLI
~/.config/quickshell/scripts/audio-control.sh echo-cancel-on
~/.config/quickshell/scripts/audio-control.sh echo-cancel-off
~/.config/quickshell/scripts/audio-control.sh echo-cancel-force-off   # hard cleanup
~/.config/quickshell/scripts/audio-control.sh echo-cancel-status      # JSON
```

**Login autostart** (already used if you enabled permanence):

```bash
systemctl --user enable --now quickshell-echo-cancel.service
systemctl --user disable --now quickshell-echo-cancel.service   # stop autostart
```

**Back-out ladder**

1. UI / IPC / `echo-cancel-off` — unload module, restore previous hardware defaults, `preferred=false`
2. `echo-cancel-force-off` — same even if state is missing/corrupt
3. Disable the user unit (and optionally delete `echo-cancel.pref`)

No permanent PipeWire `conf.d` is written; everything is reversible.

## Control-bar Audio panel

The bar **Config** strip has an **Audio** toolbar button that opens a sound-manager panel (same pattern as Services). Full layout and Options table: [control-bar.md](control-bar.md#audio-panel).

| Block | Contents |
|-------|----------|
| **Overview** (single pill) | Summary → Active streams → Levels |
| **Devices** | Output / Input columns: volume, mute, set default, ports, **Profile** under each |
| **Echo cancel** | Sticky On/Off at bottom (Options only shows/hides the section) |

- Shared view: `components/AudioMonitorView.qml` (also Inspector **Audio** tab)
- Tools: Refresh at top; `pw-top` and Restart audio at the bottom
- Active streams list hides internal peak-detect monitors (`Quickshell Peak Detect`)
- **No sampling when closed**: peak monitors, soft-poll, and profile processes tear down with `active: false`
- Pill stays the glance + wheel volume control; this panel is multi-device management

### Options (control strip → Options → Audio)

Persisted in `state/bar-layout.json`: show AEC section, show Summary / device profiles / Level meters, keep Summary / Active streams expanded on open. AEC **on/off** is only in the Audio panel (and pill), not Options.

## Related files

| Path | Role |
|------|------|
| `widgets/AudioPill.qml` | Bar pill + popup + IPC |
| `widgets/BarControlBar.qml` | Control-bar **Audio** panel host |
| `components/AudioMonitorView.qml` | Multi-device manager (Inspector + control bar) |
| `components/AudioLevelMeter.qml` | VU / peak meter visuals |
| `components/VolumeBar.qml` / `MiniVolumeBar.qml` | Volume sliders |
| `scripts/audio-control.sh` | Profiles, channel volume, echo cancel, BT battery, restart |
| `scripts/audio-poller.sh` | pactl JSON for sinks/sources/streams |
| `scripts/audio-osd.sh` | Volume OSD helper for wheel steps |
| `Config.qml` | `popupAudioWidth`, `popupAudioHeight`, volume color tiers |
