import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io as Io
import "../../components"

// Settings → Display. Resolution, refresh, bit depth, and GPU readout.
ColumnLayout {
    id: root

    required property var bar
    // Settings window. The stats timer reads controlPopup.visible.
    required property var controlPopup
    required property string activeMenu
    required property int chipR
    required property color onGreen
    required property color offRed
    required property color optFieldBg
    required property color optFieldBgFocus
    required property color activeLabel

    // Parent owns menuTick. Emitting keeps the same write the page used to do.
    signal menuBumped()
    // Parent runs scheduleReposition after a full mode list load.
    signal repositionRequested()

    // Display panel (monitor resolution / refresh / bit depth)
    property bool displayLoading: false
    property bool displayApplying: false
    property string displayStatus: ""
    property string displayError: ""
    property var displayInfo: ({})
    property var displayResolutions: []     // full catalog from hyprctl
    property var displayFilteredList: []    // cached: res that support displaySelectedRate
    property int displayResIndex: 0         // index into displayFilteredList
    property real displaySelectedRate: 0    // selected refresh (Hz)
    property int displayBitdepth: 10
    property bool displayRateMenuOpen: false
    property bool displayBitdepthMenuOpen: false
    property bool displaySliderPressed: false
    property int displayTick: 0             // UI selection / catalog changes
    property int displayGpuTick: 0          // soft GPU/status poll only (cheap)
    // true while a full list+status load is in flight (not GPU-only poll)
    property bool displayFullFetch: false

    function resetInnerScroll() {
        try {
            if (displayBodyFlick)
                displayBodyFlick.contentY = 0
        } catch (e) {}
    }

    function refresh() {
        root.refreshDisplay()
    }

    // ── Display (monitor modes via scripts/monitor-mode.sh) ──────────────
    function monitorModeScriptPath() {
        // Resolve relative to this widget so worktrees and ~/.config/quickshell both work.
        try {
            const local = Qt.resolvedUrl("../../scripts/monitor-mode.sh").toString().replace("file://", "")
            if (local && local.length)
                return local
        } catch (e) {}
        if (bar.monitorModeScript && String(bar.monitorModeScript).length)
            return String(bar.monitorModeScript)
        return Quickshell.shellPath("scripts/monitor-mode.sh")
    }

    // Exact match (for applied-vs-pending and EDID labels)
    function displayRateNear(a, b) {
        return Math.abs(Number(a) - Number(b)) < 0.05
    }

    // Family match — EDID reports 239.76 / 239.90 / 239.97 as different values;
    // a 0.05Hz epsilon left only *one* res at "240Hz", which disabled the slider.
    function displayRateBucket(r) {
        const n = Number(r) || 0
        if (n <= 0)
            return 0
        if (n >= 200)
            return 240
        if (n >= 140)
            return 144
        if (n >= 100)
            return 120
        if (n >= 70)
            return 75
        if (n >= 55)
            return 60
        return Math.round(n)
    }

    function displayRateSameFamily(a, b) {
        const ba = root.displayRateBucket(a)
        const bb = root.displayRateBucket(b)
        return ba > 0 && ba === bb
    }

    function displayEntryHasRate(e, rate) {
        if (!e || !e.rates || !(rate > 0))
            return false
        for (let i = 0; i < e.rates.length; i++) {
            if (root.displayRateSameFamily(e.rates[i], rate))
                return true
        }
        return false
    }

    // Rebuild cached filtered list once when catalog or selected rate changes.
    function displayRebuildFilter() {
        const all = root.displayResolutions || []
        const rate = Number(root.displaySelectedRate) || 0
        let out = all
        if (all.length && rate > 0) {
            const filtered = []
            for (let i = 0; i < all.length; i++) {
                if (root.displayEntryHasRate(all[i], rate))
                    filtered.push(all[i])
            }
            if (filtered.length)
                out = filtered
        }
        root.displayFilteredList = out
        if (root.displayResIndex >= out.length)
            root.displayResIndex = Math.max(0, out.length - 1)
        return out
    }

    // Every resolution × each of its EDID refresh rates (not filtered by the dropdown).
    function displayAllModeChips() {
        void root.displayTick
        const all = root.displayResolutions || []
        const out = []
        for (let i = 0; i < all.length; i++) {
            const e = all[i]
            if (!e || !e.res)
                continue
            const rates = e.rates || []
            if (!rates.length) {
                out.push({ res: String(e.res), rate: 0, label: String(e.res).replace("x", "×") })
                continue
            }
            for (let j = 0; j < rates.length; j++) {
                const r = Number(rates[j])
                out.push({
                    res: String(e.res),
                    rate: r,
                    label: String(e.res).replace("x", "×") + " · " + root.displayFormatRate(r) + " Hz"
                })
            }
        }
        return out
    }

    // Chip list grouped by refresh rate, highest Hz first.
    function displayModeGroups() {
        void root.displayTick
        const chips = root.displayAllModeChips()
        const map = ({})
        const order = []
        for (let i = 0; i < chips.length; i++) {
            const chip = chips[i]
            const bucket = root.displayRateBucket(chip.rate) || 0
            const key = String(bucket)
            if (!map[key]) {
                map[key] = {
                    rate: Number(chip.rate) || 0,
                    title: bucket > 0 ? (root.displayFormatRate(bucket) + " Hz") : "Other",
                    modes: []
                }
                order.push(key)
            }
            map[key].modes.push({
                res: chip.res,
                rate: chip.rate,
                label: String(chip.res || "").replace("x", "×")
            })
        }
        order.sort(function(a, b) { return Number(b) - Number(a) })
        const groups = []
        for (let i = 0; i < order.length; i++)
            groups.push(map[order[i]])
        return groups
    }

    // Row models for the menus. The delegates only read these objects.
    function displayRateRows() {
        const rates = root.displayPendingRates()
        const out = []
        const activeBg = root.bar.controlActiveBg || Qt.rgba(0, 0.77, 0.96, 0.22)
        const hoverBg = root.bar.glassHover
        const idleBg = Qt.rgba(0.10, 0.10, 0.12, 0.55)
        const font = root.bar.fontFamily
        for (let i = 0; i < rates.length; i++) {
            const rate = rates[i]
            const on = root.displayRateNear(rate, root.displaySelectedRate)
            out.push({
                value: rate,
                label: root.displayFormatRate(rate) + " Hz",
                active: on,
                centered: false,
                radius: root.chipR,
                activeBg: activeBg,
                hoverBg: hoverBg,
                idleBg: idleBg,
                border: on ? root.activeLabel : root.bar.dividerStrong,
                fg: on ? root.activeLabel : root.bar.text,
                font: font,
                pick: function (v) { root.displaySelectRate(v) }
            })
        }
        return out
    }

    function displayBitRows() {
        const choices = [8, 10]
        const out = []
        const activeBg = root.bar.controlActiveBg || Qt.rgba(0, 0.77, 0.96, 0.22)
        const hoverBg = root.bar.glassHover
        const idleBg = Qt.rgba(0.10, 0.10, 0.12, 0.55)
        const font = root.bar.fontFamily
        for (let i = 0; i < choices.length; i++) {
            const bd = choices[i]
            const on = root.displayBitdepth === bd
            out.push({
                value: bd,
                label: bd + "-bit",
                active: on,
                centered: true,
                radius: root.chipR,
                activeBg: activeBg,
                hoverBg: hoverBg,
                idleBg: idleBg,
                border: on ? root.activeLabel : root.bar.dividerStrong,
                fg: on ? root.activeLabel : root.bar.text,
                font: font,
                pick: function (v) { root.displaySelectBitdepth(v) }
            })
        }
        return out
    }

    function displayGroupRows() {
        const groups = root.displayModeGroups()
        const out = []
        const activeBg = root.bar.controlActiveBg || Qt.rgba(0, 0.77, 0.96, 0.22)
        const hoverBg = root.bar.glassHover
        const idleBg = Qt.rgba(1, 1, 1, 0.04)
        const font = root.bar.fontMono !== undefined ? root.bar.fontMono : root.bar.fontFamily
        for (let i = 0; i < groups.length; i++) {
            const g = groups[i]
            const modes = g.modes || []
            const chips = []
            for (let j = 0; j < modes.length; j++) {
                const m = modes[j]
                const on = root.displayModeChipSelected(m.res, m.rate)
                chips.push({
                    res: m.res,
                    rate: m.rate,
                    label: m.label || "",
                    selected: on,
                    radius: root.chipR,
                    activeBg: activeBg,
                    hoverBg: hoverBg,
                    idleBg: idleBg,
                    border: on ? root.activeLabel : root.bar.pillBorder,
                    fg: on ? root.activeLabel : root.bar.text,
                    font: font,
                    pick: function (res, rate) { root.displaySelectMode(res, rate) }
                })
            }
            out.push({
                title: g.title || "",
                titleColor: root.bar.subtext,
                titleFont: root.bar.fontFamily,
                chips: chips
            })
        }
        return out
    }

    function displaySelectMode(res, rate) {
        const r = Number(rate) || 0
        if (r > 0)
            root.displaySelectedRate = r
        root.displayRebuildFilter()
        root.displayResIndex = root.displayFindResIndex(root.displayFilteredList, String(res || ""))
        root.displayNotifyUi()
    }

    function displayModeChipSelected(res, rate) {
        void root.displayTick
        if (String(root.displayPendingRes()) !== String(res || ""))
            return false
        const a = Number(root.displayPendingRate()) || 0
        const b = Number(rate) || 0
        if (b <= 0)
            return true
        return root.displayRateNear(a, b)
    }

    function displayResEntry() {
        void root.displayTick
        const list = root.displayFilteredList || []
        if (!list.length)
            return null
        const i = Math.max(0, Math.min(root.displayResIndex, list.length - 1))
        return list[i] || null
    }

    // Exact rates for the selected resolution only (from hyprctl).
    function displayPendingRates() {
        void root.displayTick
        const e = root.displayResEntry()
        if (!e || !e.rates)
            return []
        return e.rates
    }

    function displayPendingRes() {
        void root.displayTick
        const e = root.displayResEntry()
        return e && e.res ? String(e.res) : ""
    }

    function displayPendingRate() {
        void root.displayTick
        const r = Number(root.displaySelectedRate) || 0
        if (r > 0)
            return r
        const rates = root.displayPendingRates()
        return rates.length ? Number(rates[0]) : 0
    }

    // Prefer exact EDID mode for this entry in the same rate family as `rate`.
    function displayModeForEntryRate(e, rate) {
        if (!e)
            return ""
        if (e.modes && e.rates) {
            let bestIdx = -1
            let bestDiff = 1e9
            for (let i = 0; i < e.rates.length; i++) {
                if (!root.displayRateSameFamily(e.rates[i], rate))
                    continue
                const d = Math.abs(Number(e.rates[i]) - Number(rate))
                if (d < bestDiff) {
                    bestDiff = d
                    bestIdx = i
                }
            }
            if (bestIdx >= 0 && e.modes[bestIdx])
                return String(e.modes[bestIdx])
            // Fallback: any mode on this entry
            if (e.modes[0])
                return String(e.modes[0])
        }
        if (e.res && rate > 0)
            return String(e.res) + "@" + rate
        return ""
    }

    function displayPendingMode() {
        void root.displayTick
        return root.displayModeForEntryRate(root.displayResEntry(), root.displayPendingRate())
    }

    function displayFormatRate(r) {
        const all = root.displayResolutions || []
        for (let i = 0; i < all.length; i++) {
            const e = all[i]
            if (!e || !e.rateLabels || !e.rates)
                continue
            for (let j = 0; j < e.rates.length; j++) {
                if (root.displayRateNear(e.rates[j], r) && e.rateLabels[j])
                    return String(e.rateLabels[j])
            }
        }
        const n = Number(r)
        if (!(n > 0))
            return "—"
        if (Math.abs(n - Math.round(n)) < 0.005)
            return String(Math.round(n))
        return n.toFixed(2)
    }

    function displayCloseMenus() {
        root.displayRateMenuOpen = false
        root.displayBitdepthMenuOpen = false
    }

    function openNvidiaPanel() {
        Quickshell.execDetached(["nvidia-settings"])
    }

    function displayNotifyUi() {
        // Selection-only refresh — do NOT bump menuTick (avoids layout thrash / slider cancel)
        root.displayTick++
    }

    function displayCurrentLabel() {
        void root.displayTick
        void root.displayGpuTick
        void root.displayInfo
        const info = root.displayInfo || {}
        const w = info.width || 0
        const h = info.height || 0
        const rate = info.refreshRate || 0
        const bd = info.bitdepth || 0
        if (!(w > 0 && h > 0))
            return root.displayLoading ? "Loading…" : "No monitor data"
        return w + "×" + h + " @ " + root.displayFormatRate(rate) + " Hz · " + bd + "-bit"
    }

    function displayIdentityLabel() {
        void root.displayTick
        void root.displayInfo
        const info = root.displayInfo || {}
        const parts = []
        if (info.make)
            parts.push(String(info.make))
        if (info.model)
            parts.push(String(info.model))
        if (info.serial)
            parts.push(String(info.serial))
        return parts.length ? parts.join(" · ") : (info.description || "—")
    }

    function displayConnectorLabel() {
        void root.displayTick
        void root.displayInfo
        const info = root.displayInfo || {}
        const name = info.name || ""
        const fmt = info.format || ""
        const scale = info.scale !== undefined ? Number(info.scale) : 0
        const parts = []
        if (name)
            parts.push(String(name))
        if (fmt)
            parts.push(String(fmt))
        if (scale > 0)
            parts.push("scale " + scale.toFixed(2))
        if (info.vrr)
            parts.push("VRR on")
        return parts.join(" · ")
    }

    function displayMetaLabel() {
        void root.displayTick
        void root.displayInfo
        const info = root.displayInfo || {}
        const parts = []
        const pw = Number(info.physicalWidth) || 0
        const ph = Number(info.physicalHeight) || 0
        if (pw > 0 && ph > 0) {
            const inch = Math.sqrt(pw * pw + ph * ph) / 25.4
            parts.push(pw + "×" + ph + " mm · ~" + inch.toFixed(1) + "\"")
        }
        if (info.x !== undefined && info.y !== undefined)
            parts.push("pos " + info.x + "," + info.y)
        if (info.colorManagementPreset)
            parts.push(String(info.colorManagementPreset))
        if (info.dpmsStatus === false)
            parts.push("DPMS off")
        return parts.join(" · ")
    }

    function displayAdapterLabel() {
        void root.displayGpuTick
        void root.displayInfo
        const info = root.displayInfo || {}
        const a = info.adapter || {}
        const g = info.gpu || {}
        const gpuName = (g && g.name) ? String(g.name)
                        : (a && a.pciName) ? String(a.pciName) : ""
        const driver = (g && g.driver) ? ("driver " + g.driver)
                       : (a && a.driver) ? ("drm " + a.driver) : ""
        const conn = (a && a.connector) ? String(a.connector) : ""
        const pci = (a && a.pci) ? String(a.pci) : ((g && g.pciBus) ? String(g.pciBus) : "")
        const parts = []
        if (gpuName)
            parts.push(gpuName)
        if (driver)
            parts.push(driver)
        if (conn)
            parts.push(conn)
        if (pci)
            parts.push(pci)
        return parts.length ? parts.join(" · ") : "Adapter unknown"
    }

    function displayGpuStatsLine1() {
        void root.displayGpuTick
        void root.displayInfo
        const g = (root.displayInfo && root.displayInfo.gpu) ? root.displayInfo.gpu : null
        if (!g || !g.available)
            return "GPU stats unavailable (nvidia-smi)"
        const util = (g.utilGpu !== undefined) ? Math.round(Number(g.utilGpu)) : 0
        const temp = (g.tempC !== undefined) ? Math.round(Number(g.tempC)) : 0
        const pstate = g.pstate || "—"
        const power = (g.powerW !== undefined) ? Number(g.powerW).toFixed(0) : "—"
        const plim = (g.powerLimitW !== undefined) ? Number(g.powerLimitW).toFixed(0) : "—"
        return "GPU " + util + "% · " + temp + "°C · " + pstate
               + " · " + power + "/" + plim + " W"
    }

    function displayGpuStatsLine2() {
        void root.displayGpuTick
        void root.displayInfo
        const g = (root.displayInfo && root.displayInfo.gpu) ? root.displayInfo.gpu : null
        if (!g || !g.available)
            return ""
        const used = (g.memUsedMiB !== undefined) ? Math.round(Number(g.memUsedMiB)) : 0
        const total = (g.memTotalMiB !== undefined) ? Math.round(Number(g.memTotalMiB)) : 0
        const memUtil = (g.utilMem !== undefined) ? Math.round(Number(g.utilMem)) : 0
        const gfx = (g.clockGfxMHz !== undefined) ? Math.round(Number(g.clockGfxMHz)) : 0
        const memClk = (g.clockMemMHz !== undefined) ? Math.round(Number(g.clockMemMHz)) : 0
        const usedGi = (used / 1024).toFixed(1)
        const totalGi = (total / 1024).toFixed(1)
        return "VRAM " + usedGi + "/" + totalGi + " GiB (" + memUtil + "%)"
               + " · " + gfx + " / " + memClk + " MHz"
    }

    function displayGpuMemFrac() {
        void root.displayGpuTick
        void root.displayInfo
        const g = (root.displayInfo && root.displayInfo.gpu) ? root.displayInfo.gpu : null
        if (!g || !g.available)
            return 0
        const used = Number(g.memUsedMiB) || 0
        const total = Number(g.memTotalMiB) || 0
        if (total <= 0)
            return 0
        return Math.max(0, Math.min(1, used / total))
    }

    function displayGpuUtilFrac() {
        void root.displayGpuTick
        void root.displayInfo
        const g = (root.displayInfo && root.displayInfo.gpu) ? root.displayInfo.gpu : null
        if (!g || !g.available)
            return 0
        return Math.max(0, Math.min(1, (Number(g.utilGpu) || 0) / 100))
    }

    function displayHasPendingChange() {
        void root.displayTick
        const info = root.displayInfo || {}
        const pendRes = root.displayPendingRes()
        const pendRate = root.displayPendingRate()
        const pendBd = root.displayBitdepth
        if (!pendRes.length || !(pendRate > 0))
            return false
        const curRes = (info.width && info.height) ? (info.width + "x" + info.height) : ""
        const curRate = Number(info.refreshRate) || 0
        const curBd = Number(info.bitdepth) || 0
        const rateMatch = root.displayRateNear(curRate, pendRate)
        return pendRes !== curRes || !rateMatch || pendBd !== curBd
    }

    function displayFindResIndex(list, res) {
        if (!list || !res)
            return 0
        for (let i = 0; i < list.length; i++) {
            if (list[i] && list[i].res === res)
                return i
        }
        return 0
    }

    // Closest catalog rate on entry in the same family as preferred (else highest).
    function displayPickRateOnEntry(e, preferred) {
        if (!e || !e.rates || !e.rates.length)
            return 0
        if (preferred > 0) {
            let best = -1
            let bestDiff = 1e9
            for (let i = 0; i < e.rates.length; i++) {
                if (!root.displayRateSameFamily(e.rates[i], preferred))
                    continue
                const d = Math.abs(Number(e.rates[i]) - Number(preferred))
                if (d < bestDiff) {
                    bestDiff = d
                    best = i
                }
            }
            if (best >= 0)
                return Number(e.rates[best])
        }
        return Number(e.rates[0]) || 0
    }

    function displaySyncPendingFromInfo() {
        const info = root.displayInfo || {}
        const all = root.displayResolutions || []
        if (!all.length)
            return
        const curRes = (info.width && info.height) ? (String(info.width) + "x" + String(info.height)) : ""
        const curRate = Number(info.refreshRate) || 0
        const curBd = Number(info.bitdepth) || 10

        let matchedRate = curRate
        for (let i = 0; i < all.length; i++) {
            if (all[i] && all[i].res === curRes && all[i].rates) {
                matchedRate = root.displayPickRateOnEntry(all[i], curRate)
                break
            }
        }
        root.displaySelectedRate = matchedRate
        root.displayBitdepth = (curBd === 8) ? 8 : 10
        root.displayRebuildFilter()
        root.displayResIndex = root.displayFindResIndex(root.displayFilteredList, curRes)
        root.displayCloseMenus()
        root.displayNotifyUi()
    }

    // Slider step within rate-family-filtered list. Snap selected rate to this
    // entry's exact EDID value in the same family (no refilter — list stays stable).
    function displayOnResIndexChanged(newIndex) {
        const list = root.displayFilteredList || []
        if (!list.length)
            return
        const i = Math.max(0, Math.min(Math.round(newIndex), list.length - 1))
        const e = list[i]
        if (!e)
            return
        if (i === root.displayResIndex) {
            // Still snap rate if needed (exact EDID for Apply)
            const snapped = root.displayPickRateOnEntry(e, root.displaySelectedRate)
            if (snapped > 0 && !root.displayRateNear(snapped, root.displaySelectedRate)) {
                root.displaySelectedRate = snapped
                root.displayNotifyUi()
            }
            return
        }
        root.displayResIndex = i
        // Keep family; use this panel's exact Hz so Apply gets a real mode string
        const snapped = root.displayPickRateOnEntry(e, root.displaySelectedRate)
        if (snapped > 0)
            root.displaySelectedRate = snapped
        root.displayNotifyUi()
    }

    // Rate chosen: refilter resolutions to the same Hz *family* (e.g. all ~240).
    function displaySelectRate(rate) {
        const r = Number(rate) || 0
        if (!(r > 0))
            return
        if (root.displayRateNear(r, root.displaySelectedRate)) {
            root.displayCloseMenus()
            return
        }
        const prevRes = root.displayPendingRes()
        root.displaySelectedRate = r
        root.displayRebuildFilter()
        root.displayResIndex = root.displayFindResIndex(root.displayFilteredList, prevRes)
        // Snap to exact rate on the chosen res in this family
        const e = root.displayResEntry()
        if (e) {
            const snapped = root.displayPickRateOnEntry(e, r)
            if (snapped > 0)
                root.displaySelectedRate = snapped
        }
        root.displayCloseMenus()
        root.displayNotifyUi()
    }

    function displaySelectBitdepth(bd) {
        const v = (Number(bd) === 8) ? 8 : 10
        if (v === root.displayBitdepth) {
            root.displayCloseMenus()
            return
        }
        root.displayBitdepth = v
        root.displayCloseMenus()
        root.displayNotifyUi()
    }

    function refreshDisplay() {
        if (displayStatusProcess.running || displayListProcess.running)
            return
        root.displayFullFetch = true
        root.displayLoading = true
        root.displayError = ""
        root.displayStatus = "Loading…"
        root.displayCloseMenus()
        const script = root.monitorModeScriptPath()
        if (!script.length) {
            root.displayLoading = false
            root.displayFullFetch = false
            root.displayError = "monitor-mode script missing"
            root.displayStatus = ""
            return
        }
        displayStatusProcess.exec([script, "status-json"])
        displayListProcess.exec([script, "list-json"])
    }

    // Soft GPU/monitor status — Display panel only; never while dragging the slider
    function refreshDisplayStatusOnly() {
        if (!controlPopup.visible || root.activeMenu !== "display")
            return
        if (root.displaySliderPressed || root.displayApplying || root.displayLoading)
            return
        if (displayStatusProcess.running || displayListProcess.running)
            return
        const script = root.monitorModeScriptPath()
        if (!script.length)
            return
        root.displayFullFetch = false
        displayStatusProcess.exec([script, "status-json"])
    }

    function applyDisplayMode() {
        if (root.displayApplying || displayApplyProcess.running)
            return
        const mode = root.displayPendingMode()
        if (!mode.length) {
            root.displayError = "Select a resolution and refresh rate"
            return
        }
        const script = root.monitorModeScriptPath()
        if (!script.length) {
            root.displayError = "monitor-mode script missing"
            return
        }
        root.displayApplying = true
        root.displayError = ""
        root.displayStatus = "Applying " + mode + " · " + root.displayBitdepth + "-bit…"
        root.displayCloseMenus()
        displayApplyProcess.exec([script, "apply", mode, String(root.displayBitdepth)])
        root.displayTick++
        root.menuBumped()
    }

    function _displayMaybeFinishFetch() {
        if (displayStatusProcess.running || displayListProcess.running)
            return
        const full = root.displayFullFetch
        root.displayLoading = false
        if (full) {
            root.displayFullFetch = false
            if (!root.displayError.length && !root.displayApplying)
                root.displayStatus = root.displayResolutions.length
                    ? (root.displayResolutions.length + " resolution(s)")
                    : "No modes"
            if ((root.displayResolutions || []).length)
                root.displaySyncPendingFromInfo()
            root.displayGpuTick++
            root.menuBumped()
            if (controlPopup.visible)
                root.repositionRequested()
        } else {
            // Soft poll: update GPU/indicator bindings only — never touch selection or layout
            root.displayGpuTick++
        }
    }

    // Live GPU stats — ONLY while Display is open; paused during slider drag / apply / load
    Timer {
        id: displayStatsTimer
        interval: 3000
        repeat: true
        running: root.controlPopup.visible
                 && root.activeMenu === "display"
                 && !root.displayApplying
                 && !root.displayLoading
                 && !root.displaySliderPressed
        onTriggered: root.refreshDisplayStatusOnly()
    }

    Io.Process {
        id: displayStatusProcess
        running: false
        stdout: Io.StdioCollector {
            id: displayStatusStdout
            onStreamFinished: {
                const text = (displayStatusStdout.text || "").trim()
                if (text.startsWith("{")) {
                    try {
                        root.displayInfo = JSON.parse(text)
                    } catch (e) {
                        if (root.displayFullFetch)
                            root.displayError = "Status parse error"
                    }
                } else if (root.displayFullFetch && !root.displayError.length) {
                    root.displayError = "Failed to read monitor status"
                }
            }
        }
        onExited: (code) => {
            if (root.displayFullFetch && code !== 0 && !(displayStatusStdout.text || "").trim())
                root.displayError = "status-json failed (" + code + ")"
            // Always re-check; list process may still be running
            root._displayMaybeFinishFetch()
        }
    }

    Io.Process {
        id: displayListProcess
        running: false
        stdout: Io.StdioCollector {
            id: displayListStdout
            onStreamFinished: {
                const text = (displayListStdout.text || "").trim()
                if (text.startsWith("{")) {
                    try {
                        const j = JSON.parse(text)
                        root.displayResolutions = j.resolutions || []
                        root.displayRebuildFilter()
                    } catch (e) {
                        root.displayResolutions = []
                        root.displayFilteredList = []
                        root.displayError = "List parse error"
                    }
                } else {
                    root.displayResolutions = []
                    root.displayFilteredList = []
                    if (!root.displayError.length)
                        root.displayError = "Failed to list modes"
                }
            }
        }
        onExited: (code) => {
            if (code !== 0 && !(displayListStdout.text || "").trim()) {
                root.displayResolutions = []
                root.displayFilteredList = []
                root.displayError = "list-json failed (" + code + ")"
            }
            root._displayMaybeFinishFetch()
        }
    }

    Io.Process {
        id: displayApplyProcess
        running: false
        stdout: Io.StdioCollector {
            id: displayApplyStdout
            onStreamFinished: {
                const text = (displayApplyStdout.text || "").trim()
                if (text.startsWith("{")) {
                    try {
                        root.displayInfo = JSON.parse(text)
                        root.displayError = ""
                        root.displayStatus = "Applied · " + root.displayCurrentLabel()
                        root.displaySyncPendingFromInfo()
                        root.displayGpuTick++
                    } catch (e) {
                        root.displayError = "Apply parse error"
                    }
                }
                root.displayApplying = false
            }
        }
        onExited: (code) => {
            root.displayApplying = false
            if (code !== 0) {
                const t = (displayApplyStdout.text || "").trim()
                root.displayError = t.length
                    ? t.replace(/^error:\s*/i, "").slice(0, 160)
                    : ("Apply failed (" + code + ")")
                root.displayStatus = ""
                root.displayNotifyUi()
            } else if (root.activeMenu === "display") {
                // One catalog refresh after successful apply (not a poll loop)
                Qt.callLater(function () { root.refreshDisplay() })
            }
        }
    }

    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: 12

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Text {
            Layout.fillWidth: true
            text: "Display"
            color: root.bar.text
            font.pixelSize: root.bar.popupTitleSize
            font.bold: true
            font.family: root.bar.fontFamily
        }
    }

    Flickable {
        id: displayBodyFlick
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        contentWidth: width
        contentHeight: Math.max(displayBodyCol.implicitHeight, height)
        interactive: contentHeight > height + 4
        ScrollBar.vertical: ScrollBar {
            policy: displayBodyFlick.contentHeight > displayBodyFlick.height + 4
                    ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            width: 8
            contentItem: Rectangle {
                implicitWidth: 6
                radius: 3
                color: root.bar.accent
                opacity: 0.5
            }
        }
        ColumnLayout {
            id: displayBodyCol
            width: displayBodyFlick.width
            height: Math.max(implicitHeight, displayBodyFlick.height)
            spacing: 12

    // Current monitor indicator
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: dispInfoCol.implicitHeight + 16
        radius: root.chipR
        color: Qt.rgba(0.10, 0.10, 0.12, 0.65)
        border.width: 1
        border.color: root.bar.dividerStrong
        ColumnLayout {
            id: dispInfoCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 2
            Text {
                Layout.fillWidth: true
                text: root.displayCurrentLabel()
                color: root.bar.text
                font.pixelSize: 13
                font.bold: true
                font.family: root.bar.fontMono !== undefined ? root.bar.fontMono : root.bar.fontFamily
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text: root.displayIdentityLabel()
                color: root.bar.text
                font.pixelSize: 11
                font.family: root.bar.fontFamily
                elide: Text.ElideRight
                wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                visible: root.displayConnectorLabel().length > 0
                text: root.displayConnectorLabel()
                color: root.bar.subtext
                font.pixelSize: 10
                font.family: root.bar.fontMono !== undefined ? root.bar.fontMono : root.bar.fontFamily
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: root.displayMetaLabel().length > 0
                text: root.displayMetaLabel()
                color: root.bar.subtext
                font.pixelSize: 10
                font.family: root.bar.fontFamily
                elide: Text.ElideRight
            }
        }
    }

    // GPU / display adapter
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: dispGpuCol.implicitHeight + 16
        radius: root.chipR
        color: Qt.rgba(0.05, 0.07, 0.12, 0.70)
        border.width: 1
        border.color: root.bar.dividerStrong
        ColumnLayout {
            id: dispGpuCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 4
            Text {
                Layout.fillWidth: true
                text: "Adapter"
                color: root.bar.subtext
                font.pixelSize: 10
                font.bold: true
                font.family: root.bar.fontFamily
            }
            Text {
                Layout.fillWidth: true
                text: root.displayAdapterLabel()
                color: root.bar.text
                font.pixelSize: 11
                font.family: root.bar.fontFamily
                wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                text: root.displayGpuStatsLine1()
                color: root.bar.subtext
                font.pixelSize: 10
                font.family: root.bar.fontMono !== undefined ? root.bar.fontMono : root.bar.fontFamily
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: root.displayGpuStatsLine2().length > 0
                text: root.displayGpuStatsLine2()
                color: root.bar.subtext
                font.pixelSize: 10
                font.family: root.bar.fontMono !== undefined ? root.bar.fontMono : root.bar.fontFamily
                elide: Text.ElideRight
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 8
                visible: {
                    void root.displayGpuTick
                    void root.displayInfo
                    const g = root.displayInfo && root.displayInfo.gpu
                    return !!(g && g.available)
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: "GPU"
                        color: root.bar.subtext
                        font.pixelSize: 9
                        font.family: root.bar.fontFamily
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 5
                        radius: 2
                        color: Qt.rgba(1, 1, 1, 0.10)
                        Rectangle {
                            width: parent.width * root.displayGpuUtilFrac()
                            height: parent.height
                            radius: 2
                            color: root.bar.accent
                        }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: "VRAM"
                        color: root.bar.subtext
                        font.pixelSize: 9
                        font.family: root.bar.fontFamily
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 5
                        radius: 2
                        color: Qt.rgba(1, 1, 1, 0.10)
                        Rectangle {
                            width: parent.width * root.displayGpuMemFrac()
                            height: parent.height
                            radius: 2
                            color: root.onGreen
                        }
                    }
                }
            }
        }
    }

    // Resolution | Refresh rate | Bit depth  (spaced, single row)
    RowLayout {
        Layout.fillWidth: true
        spacing: 18

        // Resolution slider
        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 140
            spacing: 6
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Resolution"
                    color: root.bar.text
                    font.pixelSize: 12
                    font.family: root.bar.fontFamily
                    Layout.fillWidth: true
                }
                Text {
                    text: root.displayPendingRes().length
                          ? root.displayPendingRes().replace("x", "×")
                          : "—"
                    color: root.bar.subtext
                    font.pixelSize: 12
                    font.family: root.bar.fontMono !== undefined ? root.bar.fontMono : root.bar.fontFamily
                }
            }
            OptValueSlider {
                bar: root.bar
                fieldBg: root.optFieldBg
                fieldBgFocus: root.optFieldBgFocus
                showField: false
                from: 0
                to: Math.max(0, (root.displayFilteredList || []).length - 1)
                stepSize: 1
                enabled: (root.displayFilteredList || []).length > 1 && !root.displayApplying && !root.displayLoading
                value: root.displayResIndex
                onValueEdited: (v) => root.displayOnResIndexChanged(Math.round(v))
                onValueCommitted: (v) => root.displayOnResIndexChanged(Math.round(v))
            }
            Text {
                Layout.fillWidth: true
                text: {
                    void root.displayTick
                    const n = (root.displayFilteredList || []).length
                    const all = (root.displayResolutions || []).length
                    const fam = root.displayRateBucket(root.displaySelectedRate)
                    if (!all)
                        return root.displayLoading ? "Loading…" : "No modes"
                    if (n <= 1)
                        return "1 res near " + fam + " Hz (pick another Refresh)"
                    return (root.displayResIndex + 1) + "/" + n
                           + " res near " + fam + " Hz"
                }
                color: root.bar.subtext
                font.pixelSize: 10
                font.family: root.bar.fontFamily
            }
        }

        // Refresh rate dropdown
        ColumnLayout {
            Layout.preferredWidth: 118
            Layout.maximumWidth: 130
            Layout.alignment: Qt.AlignTop
            spacing: 6
            Text {
                text: "Refresh"
                color: root.bar.text
                font.pixelSize: 12
                font.family: root.bar.fontFamily
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                radius: root.chipR
                color: displayRateMa.containsMouse ? root.optFieldBgFocus : root.optFieldBg
                border.width: 1
                border.color: root.displayRateMenuOpen ? root.bar.accent : root.bar.pillBorder
                opacity: root.displayPendingRates().length ? 1 : 0.55
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 4
                    Text {
                        Layout.fillWidth: true
                        text: {
                            void root.displayTick
                            const r = root.displayPendingRate()
                            return r > 0 ? (root.displayFormatRate(r) + " Hz") : "—"
                        }
                        color: root.bar.text
                        font.pixelSize: 11
                        font.family: root.bar.fontMono !== undefined ? root.bar.fontMono : root.bar.fontFamily
                        elide: Text.ElideRight
                    }
                    Text {
                        text: root.displayRateMenuOpen ? "▴" : "▾"
                        color: root.bar.subtext
                        font.pixelSize: 11
                    }
                }
                MouseArea {
                    id: displayRateMa
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: root.displayPendingRates().length > 0 && !root.displayApplying
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.displayBitdepthMenuOpen = false
                        root.displayRateMenuOpen = !root.displayRateMenuOpen
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                visible: root.displayRateMenuOpen
                Repeater {
                    model: root.displayRateRows()
                    delegate: DisplayMenuRow {}
                }
            }
        }

        // Bit depth dropdown
        ColumnLayout {
            Layout.preferredWidth: 96
            Layout.maximumWidth: 104
            Layout.alignment: Qt.AlignTop
            spacing: 6
            Text {
                text: "Bit depth"
                color: root.bar.text
                font.pixelSize: 12
                font.family: root.bar.fontFamily
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                radius: root.chipR
                color: displayBdMa.containsMouse ? root.optFieldBgFocus : root.optFieldBg
                border.width: 1
                border.color: root.displayBitdepthMenuOpen ? root.bar.accent : root.bar.pillBorder
                opacity: root.displayApplying ? 0.6 : 1
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 4
                    Text {
                        Layout.fillWidth: true
                        text: root.displayBitdepth + "-bit"
                        color: root.bar.text
                        font.pixelSize: 11
                        font.family: root.bar.fontFamily
                    }
                    Text {
                        text: root.displayBitdepthMenuOpen ? "▴" : "▾"
                        color: root.bar.subtext
                        font.pixelSize: 11
                    }
                }
                MouseArea {
                    id: displayBdMa
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !root.displayApplying
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.displayRateMenuOpen = false
                        root.displayBitdepthMenuOpen = !root.displayBitdepthMenuOpen
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                visible: root.displayBitdepthMenuOpen
                Repeater {
                    model: root.displayBitRows()
                    delegate: DisplayMenuRow {}
                }
            }
        }
    }

    // Apply + status
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            radius: root.chipR
            readonly property bool canApply: root.displayHasPendingChange()
                                             && !root.displayApplying
                                             && root.displayPendingMode().length > 0
            color: canApply
                   ? (applyDispMa.containsMouse
                      ? (root.bar.controlActiveBg || Qt.rgba(0, 0.77, 0.96, 0.28))
                      : Qt.rgba(0, 0.77, 0.96, 0.18))
                   : Qt.rgba(0.12, 0.12, 0.14, 0.55)
            border.width: 1
            border.color: canApply ? root.activeLabel : root.bar.dividerStrong
            Text {
                anchors.centerIn: parent
                text: root.displayApplying
                      ? "Applying…"
                      : (parent.canApply
                         ? ("Apply  " + root.displayPendingMode()
                            + "  ·  " + root.displayBitdepth + "-bit")
                         : "No changes")
                color: parent.canApply ? root.activeLabel : root.bar.overlay
                font.pixelSize: 12
                font.bold: parent.canApply
                font.family: root.bar.fontFamily
                elide: Text.ElideRight
                width: parent.width - 16
                horizontalAlignment: Text.AlignHCenter
            }
            MouseArea {
                id: applyDispMa
                anchors.fill: parent
                hoverEnabled: true
                enabled: parent.canApply
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.applyDisplayMode()
            }
        }
    }
    Text {
        Layout.fillWidth: true
        visible: root.displayError.length > 0
        text: root.displayError
        color: root.offRed
        font.pixelSize: 11
        font.family: root.bar.fontFamily
        wrapMode: Text.WordWrap
    }
    Text {
        Layout.fillWidth: true
        visible: root.displayStatus.length > 0 && root.displayError.length === 0
        text: root.displayStatus
        color: root.onGreen
        font.pixelSize: 11
        font.family: root.bar.fontFamily
        wrapMode: Text.WordWrap
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: "Res ↔ rate linked (hyprctl). GPU stats poll every 3s only while this panel is open (paused while dragging). Apply uses scale 1.0."
        color: root.bar.subtext
        font.pixelSize: 10
        font.family: root.bar.fontFamily
    }

    Flickable {
        id: dispResFlick
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 72
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        contentWidth: width
        contentHeight: dispResCol.implicitHeight
        ScrollBar.vertical: ScrollBar {
            policy: dispResFlick.contentHeight > dispResFlick.height + 4 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            width: 6
            contentItem: Rectangle {
                implicitWidth: 4
                radius: 2
                color: root.bar.accent
                opacity: 0.5
            }
        }
        Column {
            id: dispResCol
            width: parent.width
            spacing: 10
            Repeater {
                model: root.displayGroupRows()
                delegate: DisplayModeGroup {}
            }
        }
    }

        } // displayBodyCol
    } // displayBodyFlick

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Item { Layout.fillWidth: true }
        Rectangle {
            Layout.preferredHeight: 26
            Layout.preferredWidth: Math.max(72, nvidiaPanelRow.implicitWidth + 14)
            radius: root.chipR
            color: nvidiaPanelMa.containsMouse ? root.bar.glassHover : (root.bar.buttonBg !== undefined ? root.bar.buttonBg : root.bar.pillBg)
            border.width: 1
            border.color: nvidiaPanelMa.containsMouse
                          ? "#76b900"
                          : root.bar.pillBorder
            Row {
                id: nvidiaPanelRow
                anchors.centerIn: parent
                spacing: 5
                Text {
                    text: "\uF135D"
                    color: nvidiaPanelMa.containsMouse ? "#76b900" : root.bar.subtext
                    font.pixelSize: 14
                    font.family: root.bar.fontFamily
                    verticalAlignment: Text.AlignVCenter
                }
                Text {
                    text: "NVIDIA"
                    color: nvidiaPanelMa.containsMouse ? "#76b900" : root.bar.subtext
                    font.pixelSize: 11
                    font.bold: true
                    font.family: root.bar.fontFamily
                    verticalAlignment: Text.AlignVCenter
                }
            }
            MouseArea {
                id: nvidiaPanelMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openNvidiaPanel()
            }
            ToolTip.visible: nvidiaPanelMa.containsMouse
            ToolTip.delay: root.bar.tooltipDelay !== undefined ? root.bar.tooltipDelay : 400
            ToolTip.text: "Open NVIDIA Settings"
        }
        Rectangle {
            Layout.preferredHeight: 26
            Layout.preferredWidth: Math.max(56, refreshDispTxt.implicitWidth + 16)
            radius: root.chipR
            color: refreshDispMa.containsMouse ? root.bar.glassHover : (root.bar.buttonBg !== undefined ? root.bar.buttonBg : root.bar.pillBg)
            border.width: 1
            border.color: root.bar.pillBorder
            Text {
                id: refreshDispTxt
                anchors.centerIn: parent
                text: root.displayLoading ? "…" : "Refresh"
                color: root.bar.subtext
                font.pixelSize: 11
                font.family: root.bar.fontFamily
            }
            MouseArea {
                id: refreshDispMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.refreshDisplay()
            }
        }
    }
}
