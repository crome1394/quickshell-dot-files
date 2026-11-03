// Workspace overview for Hyprland. Original Quickshell implementation of a
// Mission Control / expo: live toplevel captures, a workspace strip, and
// keyboard, wheel, and drag controls. Not derived from another project's code.
//
// Super+Tab toggles it (Hyprland bind → `qs ipc call overview toggle`).
// While it is open the surface takes the keyboard on the focused monitor:
//   Esc close · Tab / Shift+Tab workspace · arrows select · Enter focus
//   D close window · A all workspaces · Shift (alone) desktop layout
//   1–9, 0 pick a strip card · wheel steps workspaces · click empty space closes
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

Variants {
    id: root

    required property var hostBar
    model: Quickshell.screens

    property bool open: false
    property real reveal: 0
    property string viewMode: "workspace" // workspace | desktop | all
    property int switchDir: 1
    property bool skipCommit: false
    property double lastToggleMs: 0
    property double suppressUntil: 0
    property int openSerial: 0
    property int refreshSerial: 0
    property int commitSerial: 0
    property int stepSerial: 0
    property int stepDir: 1

    Behavior on reveal {
        NumberAnimation {
            duration: Math.max(0, root.hostBar.ovDuration)
            easing.type: Easing.OutCubic
        }
    }

    function nowMs() {
        return Date.now()
    }

    function quote(text) {
        return "'" + String(text || "").replace(/\\/g, "\\\\").replace(/'/g, "\\'") + "'"
    }

    function addressOf(addr) {
        // Quickshell toplevel addresses omit the 0x prefix Hyprland's
        // address: selector requires. hyprctl prints 0x55.., the model has 55..
        let raw = String(addr || "")
        if (raw.indexOf("address:") === 0)
            raw = raw.slice("address:".length)
        if (raw.indexOf("0x") !== 0 && raw.indexOf("0X") !== 0)
            raw = "0x" + raw
        return "address:" + raw
    }

    function armSuppress() {
        root.suppressUntil = root.nowMs() + 700
    }

    function dispatch(expr) {
        root.armSuppress()
        Hyprland.dispatch(expr)
    }

    function toggle() {
        const now = root.nowMs()
        if (now - root.lastToggleMs < 280)
            return
        root.lastToggleMs = now
        if (root.open)
            root.closeOverview()
        else
            root.openOverview(root.hostBar.ovShowAll ? "all" : "workspace")
    }

    function openMode(mode) {
        const now = root.nowMs()
        if (now - root.lastToggleMs < 280)
            return
        root.lastToggleMs = now
        const next = mode === "desktop" || mode === "all" ? mode : "workspace"
        if (root.open && root.viewMode === next) {
            root.closeOverview()
            return
        }
        root.openOverview(next)
    }

    function openOverview(mode) {
        Hyprland.refreshMonitors()
        Hyprland.refreshWorkspaces()
        Hyprland.refreshToplevels()
        root.viewMode = mode === "desktop" || mode === "all" ? mode : "workspace"
        root.open = true
        root.reveal = 1
        root.openSerial++
    }

    function closeOverview() {
        if (!root.open && root.reveal <= 0)
            return
        if (!root.skipCommit)
            root.commitSerial++
        root.skipCommit = false
        root.open = false
        root.reveal = 0
    }

    function step(dir) {
        root.stepDir = dir >= 0 ? 1 : -1
        if (root.open) {
            root.stepSerial++
            return
        }
        const mon = Hyprland.focusedMonitor
        if (!mon)
            return
        const cards = root.cardsFor(mon.name).filter(function (card) { return !card.all })
        if (!cards.length)
            return
        const key = root.activeKey(mon.name)
        let idx = 0
        for (let i = 0; i < cards.length; i++) {
            if (cards[i].key === key)
                idx = i
        }
        let next = idx + root.stepDir
        if (next < 0)
            next = cards.length - 1
        if (next >= cards.length)
            next = 0
        root.followCard(cards[next], mon.name, true)
    }

    function monitorByName(name) {
        const model = Hyprland.monitors
        const vals = model && model.values ? model.values : []
        for (let i = 0; i < vals.length; i++) {
            if (vals[i].name === name)
                return vals[i]
        }
        return null
    }

    function activeKey(monName) {
        const mon = root.monitorByName(monName)
        const ws = mon ? mon.activeWorkspace : null
        if (!ws)
            return ""
        const name = String(ws.name || "")
        if (name.indexOf("special:") === 0)
            return "s:" + name
        const id = Number(ws.id) || 0
        if (id > 0)
            return "w:" + id
        return ""
    }

    function listOf(model) {
        return model && model.values ? model.values : []
    }

    function windowRecord(tl, monName) {
        if (!tl)
            return null
        const ipc = tl.lastIpcObject || {}
        const mon = tl.monitor
        let owner = mon && mon.name ? String(mon.name) : ""
        if (!owner && tl.workspace && tl.workspace.monitor && tl.workspace.monitor.name)
            owner = String(tl.workspace.monitor.name)
        if (owner !== monName)
            return null
        if (ipc.mapped === false || ipc.hidden)
            return null
        const at = ipc.at || [0, 0]
        const size = ipc.size || [0, 0]
        const w = Number(size[0]) || 0
        const h = Number(size[1]) || 0
        if (w < 2 || h < 2)
            return null
        const ws = tl.workspace
        const wsIpc = ipc.workspace || {}
        const wsName = String((ws && ws.name) || wsIpc.name || "")
        const wsId = (ws && Number(ws.id) > 0) ? Number(ws.id) : (Number(wsIpc.id) || 0)
        const app = (tl.wayland && tl.wayland.appId) ? String(tl.wayland.appId) : String(ipc["class"] || "")
        return {
            addr: String(tl.address || ""),
            title: String(tl.title || ipc.title || app || "Window"),
            appId: app,
            x: Number(at[0]) || 0,
            y: Number(at[1]) || 0,
            w: w,
            h: h,
            wsId: wsId,
            wsName: wsName,
            special: wsName.indexOf("special:") === 0,
            pinned: !!ipc.pinned
        }
    }

    function windowsOn(monName) {
        const vals = root.listOf(Hyprland.toplevels)
        const out = []
        for (let i = 0; i < vals.length; i++) {
            const rec = root.windowRecord(vals[i], monName)
            if (rec && rec.addr)
                out.push(rec)
        }
        out.sort(function (a, b) {
            if (a.y !== b.y)
                return a.y - b.y
            return a.x - b.x
        })
        return out
    }

    function countOn(monName, key) {
        const wins = root.windowsOn(monName)
        let n = 0
        for (let i = 0; i < wins.length; i++) {
            if (root.windowMatches(wins[i], key))
                n++
        }
        return n
    }

    function windowMatches(win, key) {
        if (!key)
            return false
        if (win.pinned)
            return true
        if (key.indexOf("s:") === 0)
            return win.wsName === key.slice(2)
        if (key.indexOf("w:") === 0)
            return win.wsId === Number(key.slice(2))
        return false
    }

    function phantomCard(id, numbered) {
        return {
            key: "w:" + id,
            id: id,
            wsId: id,
            name: numbered ? String(id) : "+",
            symbol: "",
            word: "",
            font: "",
            bold: true,
            italic: false,
            color: "",
            special: "",
            phantom: true,
            all: false,
            count: 0
        }
    }

    function decorateCard(card) {
        if (!card)
            return card
        const bar = root.hostBar
        if (card.all) {
            card.symbol = ""
            card.word = "All"
            return card
        }
        if (card.special) {
            card.symbol = (bar && bar.wsSpecialIcon) ? String(bar.wsSpecialIcon() || "") : ""
            card.word = String((bar && bar.wsSpecialText) || card.name || "")
            card.font = String((bar && bar.wsSpecialFont) || "")
            card.bold = !bar || bar.wsSpecialBold !== false
            card.italic = !!(bar && bar.wsSpecialItalic)
            card.color = String((bar && bar.wsSpecialColor) || "")
            return card
        }
        const id = Number(card.wsId || card.id) || 0
        card.wsId = id
        card.symbol = (bar && bar.wsLabelForId) ? String(bar.wsLabelForId(id) || "") : ""
        card.word = (bar && bar.wsTextForId) ? String(bar.wsTextForId(id) || "") : ""
        card.font = (bar && bar.wsFontForId) ? String(bar.wsFontForId(id) || "") : ""
        card.bold = !bar || !bar.wsBoldForId || bar.wsBoldForId(id)
        card.italic = !!(bar && bar.wsItalicForId && bar.wsItalicForId(id))
        card.color = (bar && bar.wsColorForId) ? String(bar.wsColorForId(id) || "") : ""
        return card
    }

    function cardCaption(card) {
        if (!card)
            return ""
        if (card.all)
            return "All"
        if (root.hostBar.ovNumberLabels && !card.special) {
            if (card.phantom && !root.hostBar.ovDynamic)
                return "+"
            const key = String(card.key || "")
            if (key.indexOf("w:") === 0)
                return key.slice(2)
            if (card.wsId)
                return String(card.wsId)
            return String(card.name || "")
        }
        if (card.phantom && !root.hostBar.ovDynamic)
            return "+"
        const sym = String(card.symbol || "")
        const word = String(card.word || "")
        if (sym && word)
            return sym + "  " + word
        if (word)
            return word
        if (sym)
            return sym
        return String(card.name || card.wsId || "")
    }

    // Workspace id or special name. Read from the card key so a QML model
    // cannot drop the field the way it drops a property named id.
    function workspaceTarget(card) {
        if (!card || card.all)
            return null
        const key = String(card.key || "")
        if (key.indexOf("s:") === 0)
            return key.slice(2)
        if (card.special)
            return String(card.special)
        if (key.indexOf("w:") === 0) {
            const n = Number(key.slice(2))
            if (n > 0)
                return n
        }
        const n = Number(card.wsId)
        if (n > 0)
            return n
        return null
    }

    function nextWorkspaceId() {
        const vals = root.listOf(Hyprland.workspaces)
        let maxId = 1
        for (let i = 0; i < vals.length; i++) {
            const id = Number(vals[i].id) || 0
            if (id > maxId)
                maxId = id
        }
        return maxId + 1
    }

    // Hyprland keeps every special it has ever toggled. The bar has one,
    // wsSpecialName (Hidden). magic and scratchpad are not part of the strip.
    function isConfiguredSpecial(name) {
        const n = String(name || "")
        if (!n.length)
            return false
        if (root.hostBar && typeof root.hostBar.wsIsSpecialName === "function")
            return root.hostBar.wsIsSpecialName(n)
        const want = String((root.hostBar && root.hostBar.wsSpecialName) || "")
        return want.length > 0 && (n === want || n === ("special:" + want))
    }

    function cardsFor(monName) {
        const vals = root.listOf(Hyprland.workspaces)
        const byId = {}
        const specials = []
        for (let i = 0; i < vals.length; i++) {
            const ws = vals[i]
            if (!ws.monitor || ws.monitor.name !== monName)
                continue
            const name = String(ws.name || "")
            const id = Number(ws.id) || 0
            if (name.indexOf("special:") === 0) {
                if (root.hostBar.ovShowSpecial && root.isConfiguredSpecial(name)) {
                    const key = "s:" + name
                    const count = root.countOn(monName, key)
                    if (root.hostBar.wsShowOnlyActive && count <= 0)
                        continue
                    specials.push(root.decorateCard({
                        key: key,
                        id: id,
                        wsId: id,
                        name: name.replace(/^special:/, ""),
                        special: name,
                        phantom: false,
                        all: false,
                        count: count
                    }))
                }
                continue
            }
            if (id <= 0)
                continue
            const key = "w:" + id
            byId[id] = {
                key: key,
                id: id,
                wsId: id,
                name: name,
                special: "",
                phantom: false,
                all: false,
                count: root.countOn(monName, key)
            }
        }
        const slots = (root.hostBar.wsSlotsEffective ? root.hostBar.wsSlotsEffective() : []) || []
        const seen = {}
        let body = []
        for (let i = 0; i < slots.length; i++) {
            const id = Math.round(Number(slots[i] && slots[i].id))
            if (!(id >= 1) || seen[id])
                continue
            seen[id] = true
            let card = byId[id]
            if (!card) {
                card = {
                    key: "w:" + id,
                    id: id,
                    wsId: id,
                    name: String(id),
                    special: "",
                    phantom: false,
                    all: false,
                    count: root.countOn(monName, "w:" + id)
                }
            }
            body.push(root.decorateCard(card))
        }
        const extraIds = []
        const idKeys = Object.keys(byId)
        for (let i = 0; i < idKeys.length; i++) {
            const id = Number(idKeys[i])
            if (!seen[id])
                extraIds.push(id)
        }
        extraIds.sort(function (a, b) { return a - b })
        const dynamic = !!root.hostBar.ovDynamic
        const onlyActive = !!root.hostBar.wsShowOnlyActive
        const active = root.activeKey(monName)
        for (let i = 0; i < extraIds.length; i++) {
            const card = byId[extraIds[i]]
            if (onlyActive) {
                if (card.count > 0)
                    body.push(root.decorateCard(card))
                continue
            }
            if (card.count > 0 || card.key === active || root.hostBar.ovShowEmpty || dynamic)
                body.push(root.decorateCard(card))
        }
        if (onlyActive) {
            // Occupied cards, plus the next empty slot so there is one drop target.
            let maxOcc = 0
            const occupied = []
            for (let i = 0; i < body.length; i++) {
                if (body[i].count > 0) {
                    occupied.push(body[i])
                    if (body[i].id > maxOcc)
                        maxOcc = body[i].id
                }
            }
            let blank = null
            for (let i = 0; i < body.length; i++) {
                if (body[i].count === 0 && body[i].id > maxOcc) {
                    blank = body[i]
                    break
                }
            }
            if (!blank) {
                for (let i = 0; i < body.length; i++) {
                    if (body[i].count === 0) {
                        blank = body[i]
                        break
                    }
                }
            }
            if (!blank) {
                let next = root.nextWorkspaceId()
                const used = {}
                for (let i = 0; i < body.length; i++)
                    used[body[i].id] = true
                while (used[next])
                    next++
                blank = root.decorateCard(root.phantomCard(next, true))
            }
            const merged = []
            let placed = false
            for (let i = 0; i < occupied.length; i++) {
                if (!placed && blank.id < occupied[i].id) {
                    merged.push(blank)
                    placed = true
                }
                merged.push(occupied[i])
            }
            if (!placed)
                merged.push(blank)
            body = merged
        } else {
            const tail = body.length ? body[body.length - 1] : null
            if (dynamic && (!tail || tail.count > 0)) {
                let next = root.nextWorkspaceId()
                const used = {}
                for (let i = 0; i < body.length; i++)
                    used[body[i].id] = true
                while (used[next])
                    next++
                body.push(root.decorateCard(root.phantomCard(next, true)))
            }
        }
        const out = []
        if (root.hostBar.ovStripAllCard) {
            out.push(root.decorateCard({
                key: "all",
                id: 0,
                name: "All",
                special: "",
                phantom: false,
                all: true,
                count: root.windowsOn(monName).length
            }))
        }
        for (let i = 0; i < body.length; i++)
            out.push(body[i])
        for (let i = 0; i < specials.length; i++)
            out.push(specials[i])
        return out
    }

    function visibleWindows(monName, key, mode) {
        const wins = root.windowsOn(monName)
        if (mode === "all") {
            const out = []
            for (let i = 0; i < wins.length; i++) {
                if (wins[i].special && !root.hostBar.ovShowSpecial)
                    continue
                out.push(wins[i])
            }
            return out
        }
        const out = []
        for (let i = 0; i < wins.length; i++) {
            if (root.windowMatches(wins[i], key))
                out.push(wins[i])
        }
        return out
    }

    function effectiveLayout() {
        if (root.viewMode === "desktop")
            return "natural"
        if (root.viewMode === "all" && root.hostBar.ovLayout === "natural")
            return "rows"
        const layout = String(root.hostBar.ovLayout || "rows")
        if (layout === "grid" || layout === "natural")
            return layout
        return "rows"
    }

    function unitFor(mon, screenW) {
        const hw = Number(mon && mon.width) || 0
        const sw = Number(screenW) || 0
        if (hw <= 0 || sw <= 0)
            return 1
        const unit = sw / hw
        if (unit < 0.2 || unit > 5)
            return 1
        return unit
    }

    function place(wins, mon, areaW, areaH, screenW) {
        const width = Math.max(0, areaW)
        const height = Math.max(0, areaH)
        if (!wins.length || width < 8 || height < 8)
            return []
        const unit = root.unitFor(mon, screenW)
        const maxScale = Math.max(0.05, Number(root.hostBar.ovMaxScale) || 1)
        const gap = Math.max(0, Number(root.hostBar.ovGap) || 0)
        const items = []
        for (let i = 0; i < wins.length; i++) {
            items.push({
                addr: wins[i].addr,
                title: wins[i].title,
                appId: wins[i].appId,
                realW: Math.max(1, wins[i].w * unit),
                realH: Math.max(1, wins[i].h * unit),
                gx: wins[i].x,
                gy: wins[i].y
            })
        }
        const mode = root.effectiveLayout()
        if (mode === "natural")
            return root.placeNatural(items, mon, width, height, unit, maxScale)
        if (mode === "grid")
            return root.placeGrid(items, width, height, gap, maxScale)
        return root.placeRows(items, width, height, gap, maxScale)
    }

    function placeNatural(items, mon, areaW, areaH, unit, maxScale) {
        const monW = Math.max(1, (Number(mon.width) || areaW) * unit)
        const monH = Math.max(1, (Number(mon.height) || areaH) * unit)
        const monX = (Number(mon.x) || 0) * unit
        const monY = (Number(mon.y) || 0) * unit
        const fit = Math.min(areaW / monW, areaH / monH)
        const scale = Math.min(Math.max(0.01, fit), maxScale)
        const ox = (areaW - monW * scale) / 2
        const oy = (areaH - monH * scale) / 2
        const out = []
        for (let i = 0; i < items.length; i++) {
            const it = items[i]
            out.push({
                addr: it.addr,
                title: it.title,
                appId: it.appId,
                x: ox + (it.gx * unit - monX) * scale,
                y: oy + (it.gy * unit - monY) * scale,
                w: Math.max(8, it.realW * scale),
                h: Math.max(8, it.realH * scale)
            })
        }
        return out
    }

    function placeGrid(items, areaW, areaH, gap, maxScale) {
        const n = items.length
        let best = null
        let bestScore = -1
        for (let cols = 1; cols <= n; cols++) {
            const rows = Math.ceil(n / cols)
            const cellW = (areaW - gap * (cols - 1)) / cols
            const cellH = (areaH - gap * (rows - 1)) / rows
            if (cellW < 8 || cellH < 8)
                continue
            const score = Math.min(cellW, cellH)
            if (score > bestScore) {
                bestScore = score
                best = { cols: cols, rows: rows, cellW: cellW, cellH: cellH }
            }
        }
        if (!best)
            return []
        const gridW = best.cols * best.cellW + gap * (best.cols - 1)
        const gridH = best.rows * best.cellH + gap * (best.rows - 1)
        const ox = (areaW - gridW) / 2
        const oy = (areaH - gridH) / 2
        const out = []
        for (let i = 0; i < n; i++) {
            const col = i % best.cols
            const row = Math.floor(i / best.cols)
            const it = items[i]
            const fit = Math.min(best.cellW / it.realW, best.cellH / it.realH, maxScale)
            const w = Math.max(8, it.realW * fit)
            const h = Math.max(8, it.realH * fit)
            const cx = ox + col * (best.cellW + gap)
            const cy = oy + row * (best.cellH + gap)
            out.push({
                addr: it.addr,
                title: it.title,
                appId: it.appId,
                x: cx + (best.cellW - w) / 2,
                y: cy + (best.cellH - h) / 2,
                w: w,
                h: h
            })
        }
        return out
    }

    function placeRows(items, areaW, areaH, gap, maxScale) {
        const n = items.length
        let bestScale = -1
        let bestCounts = null
        for (let rows = 1; rows <= n; rows++) {
            const base = Math.floor(n / rows)
            const extra = n % rows
            const counts = []
            for (let r = 0; r < rows; r++)
                counts.push(base + (r < extra ? 1 : 0))
            let lo = 0
            let hi = maxScale
            for (let step = 0; step < 22; step++) {
                const mid = (lo + hi) / 2
                if (root.rowsFit(items, counts, areaW, areaH, gap, mid))
                    lo = mid
                else
                    hi = mid
            }
            if (lo > bestScale) {
                bestScale = lo
                bestCounts = counts
            }
        }
        if (!bestCounts || bestScale <= 0)
            return root.placeGrid(items, areaW, areaH, gap, maxScale)
        const scale = bestScale
        const rowH = []
        const rowW = []
        let idx = 0
        for (let r = 0; r < bestCounts.length; r++) {
            let rh = 0
            let rw = 0
            const count = bestCounts[r]
            for (let c = 0; c < count; c++) {
                const it = items[idx++]
                rh = Math.max(rh, it.realH * scale)
                rw += it.realW * scale
            }
            if (count > 1)
                rw += gap * (count - 1)
            rowH.push(rh)
            rowW.push(rw)
        }
        let totalH = 0
        for (let r = 0; r < rowH.length; r++)
            totalH += rowH[r]
        if (rowH.length > 1)
            totalH += gap * (rowH.length - 1)
        let y = Math.max(0, (areaH - totalH) / 2)
        idx = 0
        const out = []
        for (let r = 0; r < bestCounts.length; r++) {
            let x = Math.max(0, (areaW - rowW[r]) / 2)
            const count = bestCounts[r]
            for (let c = 0; c < count; c++) {
                const it = items[idx++]
                const w = Math.max(8, it.realW * scale)
                const h = Math.max(8, it.realH * scale)
                out.push({
                    addr: it.addr,
                    title: it.title,
                    appId: it.appId,
                    x: x,
                    y: y + (rowH[r] - h) / 2,
                    w: w,
                    h: h
                })
                x += w + gap
            }
            y += rowH[r] + gap
        }
        return out
    }

    function rowsFit(items, counts, areaW, areaH, gap, scale) {
        let idx = 0
        let usedH = 0
        for (let r = 0; r < counts.length; r++) {
            let rowW = 0
            let rowH = 0
            const count = counts[r]
            for (let c = 0; c < count; c++) {
                const it = items[idx++]
                rowW += it.realW * scale
                rowH = Math.max(rowH, it.realH * scale)
            }
            if (count > 1)
                rowW += gap * (count - 1)
            if (rowW > areaW + 0.5)
                return false
            usedH += rowH
            if (r < counts.length - 1)
                usedH += gap
            if (usedH > areaH + 0.5)
                return false
        }
        return true
    }

    function followCard(card, monName, createPhantom) {
        if (!card)
            return
        if (card.all) {
            root.viewMode = root.viewMode === "all" ? "workspace" : "all"
            return
        }
        root.viewMode = "workspace"
        if (card.phantom && createPhantom)
            root.dispatchFocusWorkspace(card.id, monName)
        else if (!card.phantom && card.special)
            root.dispatchFocusWorkspace(card.special, monName)
        else if (!card.phantom)
            root.dispatchFocusWorkspace(card.id, monName)
    }

    function dispatchFocusWorkspace(ws, monName) {
        if (monName)
            root.dispatch("hl.dsp.focus({ monitor = " + root.quote(monName) + " })")
        const numeric = typeof ws === "number" || (String(ws).length && String(Number(ws)) === String(ws) && String(ws).indexOf("special:") !== 0)
        if (numeric)
            root.dispatch("hl.dsp.focus({ workspace = " + Number(ws) + " })")
        else
            root.dispatch("hl.dsp.focus({ workspace = " + root.quote(ws) + " })")
    }

    function focusWindow(addr) {
        root.dispatch("hl.dsp.focus({ window = " + root.quote(root.addressOf(addr)) + " })")
    }

    function closeWindow(addr) {
        root.dispatch("hl.dsp.window.close({ window = " + root.quote(root.addressOf(addr)) + " })")
    }

    function moveWindow(addr, workspace, follow) {
        if (workspace === null || workspace === undefined || workspace === "")
            return
        const numeric = typeof workspace === "number" || (String(workspace).length > 0 && String(Number(workspace)) === String(workspace))
        const ws = numeric ? String(Number(workspace)) : root.quote(String(workspace))
        const window = root.quote(root.addressOf(addr))
        root.dispatch("hl.dsp.window.move({ window = " + window
            + ", workspace = " + ws
            + ", follow = " + (follow ? "true" : "false") + " })")
    }

    function swapWindow(fromAddr, toAddr) {
        root.focusWindow(fromAddr)
        root.dispatch("hl.dsp.window.swap({ target = " + root.quote(root.addressOf(toAddr)) + " })")
    }

    function toplevelFor(addr) {
        const vals = root.listOf(Hyprland.toplevels)
        const want = String(addr || "")
        for (let i = 0; i < vals.length; i++) {
            if (String(vals[i].address || "") === want)
                return vals[i]
        }
        return null
    }

    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            if (!root.open || !root.hostBar.ovExitOnSwitch)
                return
            if (root.nowMs() < root.suppressUntil)
                return
            root.closeOverview()
        }
        function onRawEvent(event) {
            if (!root.open)
                return
            const name = event.name
            if (name === "openwindow" || name === "closewindow" || name === "movewindow"
                    || name === "windowtitle" || name === "changefloatingmode"
                    || name === "fullscreen" || name === "workspace" || name === "createworkspace"
                    || name === "destroyworkspace" || name === "focusedmon")
                root.refreshSerial++
        }
    }

    PanelWindow {
        id: panel
        required property var modelData
        screen: modelData

        property var cards: []
        property var placements: []
        property string displayedKey: ""
        property string selectedAddr: ""
        property string layoutSig: ""
        property bool shiftChord: false
        property real slideX: 0
        property bool flying: false
        property real flyT: 0
        property real flyX: 0
        property real flyY: 0
        property real flyW: 0
        property real flyH: 0
        property real flyTx: 0
        property real flyTy: 0
        property real flyTw: 0
        property real flyTh: 0
        property string flyTitle: ""
        property var drag: null
        property string dropKey: ""

        readonly property var hyprMonitor: Hyprland.monitorFor(modelData)
        readonly property string monName: hyprMonitor ? String(hyprMonitor.name || "") : ""
        readonly property bool takesKeys: {
            if (!root.open || !panel.hyprMonitor)
                return false
            const focused = Hyprland.focusedMonitor
            return !!focused && focused.name === panel.monName
        }
        readonly property string anchor: {
            const a = String(root.hostBar.ovAnchor || "top")
            if (a === "bottom" || a === "left" || a === "right")
                return a
            return "top"
        }
        readonly property bool stripHorizontal: anchor === "top" || anchor === "bottom"
        readonly property real thickness: panel.stripHorizontal
                                             ? Math.max(72, root.hostBar.ovStripHeight)
                                             : Math.max(72, root.hostBar.ovStripWidth || root.hostBar.ovStripHeight)
        readonly property real stripOffset: Math.max(0, root.hostBar.ovStripOffset)
        readonly property color backdrop: {
            const dim = Math.max(0, Math.min(1, root.hostBar.ovBlur))
            const alpha = root.hostBar.ovBackdropBlur ? (0.10 + 0.25 * dim) : (0.28 + 0.50 * dim)
            return Qt.rgba(0.027, 0.04, 0.063, alpha)
        }
        readonly property color accent: root.hostBar.accent !== undefined ? root.hostBar.accent : "#7ec8ff"
        readonly property int hoverBorder: Math.max(0, root.hostBar.ovHoverBorder)
        readonly property int selectBorder: Math.max(0, root.hostBar.ovSelectBorder)
        readonly property bool desktopMode: root.viewMode === "desktop"
        readonly property string watchKey: [
            root.refreshSerial, root.viewMode, anchor,
            root.hostBar.ovLayout, root.hostBar.ovGap, root.hostBar.ovPadding,
            root.hostBar.ovPaddingTop, root.hostBar.ovPaddingBottom, root.hostBar.ovMaxScale,
            root.hostBar.ovDynamic, root.hostBar.ovShowEmpty, root.hostBar.ovAutodelete,
            root.hostBar.ovShowSpecial, root.hostBar.ovStripAllCard, root.hostBar.ovShowWsLabels,
            root.hostBar.ovStripPreviews, root.hostBar.ovNumberLabels, root.hostBar.ovLivePreviews,
            root.hostBar.ovStripHeight, root.hostBar.ovStripWidth, root.hostBar.ovStripCardMax,
            root.hostBar.ovStripMargin, root.hostBar.ovStripGap, root.hostBar.ovStripOffset,
            root.hostBar.wsShowOnlyActive,
            root.hostBar.wsSpecialName, root.hostBar.wsSpecialText, root.hostBar.wsIconSpecialCustom,
            JSON.stringify(root.hostBar.wsSlots || [])
        ].join("|")

        function pad(edge) {
            // paddingTop is the gap between the strip and the previews.
            // paddingBottom is the margin on the opposite outer edge.
            const side = Math.max(0, root.hostBar.ovPadding)
            const near = Math.max(0, root.hostBar.ovPaddingTop)
            const far = Math.max(0, root.hostBar.ovPaddingBottom)
            if (edge === "left")
                return panel.anchor === "left" ? near : (panel.anchor === "right" ? far : side)
            if (edge === "right")
                return panel.anchor === "right" ? near : (panel.anchor === "left" ? far : side)
            if (edge === "top")
                return panel.anchor === "top" ? near : (panel.anchor === "bottom" ? far : side)
            return panel.anchor === "bottom" ? near : (panel.anchor === "top" ? far : side)
        }

        function captureOpen() {
            panel.displayedKey = root.activeKey(panel.monName)
            panel.selectedAddr = ""
            panel.slideX = 0
            panel.drag = null
            panel.rebuild(true)
            if (panel.takesKeys)
                keyItem.forceActiveFocus()
        }

        function commitDisplayed() {
            if (!panel.takesKeys || root.viewMode === "all")
                return
            const key = panel.displayedKey
            const live = root.activeKey(panel.monName)
            if (!key || key === live || key === "all")
                return
            if (key.indexOf("s:") === 0)
                root.dispatchFocusWorkspace(key.slice(2), panel.monName)
            else if (key.indexOf("w:") === 0)
                root.dispatchFocusWorkspace(Number(key.slice(2)), panel.monName)
        }

        function rebuild(force) {
            if (!panel.monName || !area)
                return
            const nextCards = root.cardsFor(panel.monName)
            let shown = false
            for (let i = 0; i < nextCards.length; i++) {
                if (nextCards[i].key === panel.displayedKey)
                    shown = true
            }
            if (!panel.displayedKey || !shown) {
                const key = root.activeKey(panel.monName)
                let use = ""
                for (let i = 0; i < nextCards.length; i++) {
                    if (nextCards[i].key === key)
                        use = key
                }
                if (!use) {
                    for (let i = 0; i < nextCards.length; i++) {
                        if (!nextCards[i].all) {
                            use = nextCards[i].key
                            break
                        }
                    }
                }
                if (use)
                    panel.displayedKey = use
            }
            const wins = root.visibleWindows(panel.monName, panel.displayedKey, root.viewMode)
            const mon = panel.hyprMonitor || root.monitorByName(panel.monName)
            const placed = root.place(wins, mon, area.width, area.height, panel.width)
            const allWins = root.windowsOn(panel.monName)
            let sig = root.viewMode + "|" + panel.displayedKey + "|" + area.width + "x" + area.height
            for (let i = 0; i < allWins.length; i++)
                sig += "/" + allWins[i].addr + ":" + allWins[i].x + "," + allWins[i].y + "," + allWins[i].w + "x" + allWins[i].h
            for (let i = 0; i < nextCards.length; i++) {
                const card = nextCards[i]
                card.minis = (card.all || card.phantom || !root.hostBar.ovStripPreviews)
                              ? [] : panel.miniWindows(card.key)
                sig += ";" + card.key + ":" + card.count + (card.phantom ? "?" : "")
            }
            for (let i = 0; i < placed.length; i++) {
                const p = placed[i]
                sig += "|" + p.addr + "@" + Math.round(p.x) + "," + Math.round(p.y) + "," + Math.round(p.w) + "," + Math.round(p.h)
            }
            if (!force && sig === panel.layoutSig)
                return
            panel.layoutSig = sig
            panel.cards = nextCards
            panel.placements = placed
            if (panel.selectedAddr) {
                let still = false
                for (let i = 0; i < placed.length; i++) {
                    if (placed[i].addr === panel.selectedAddr)
                        still = true
                }
                if (!still)
                    panel.selectedAddr = placed.length ? placed[0].addr : ""
            } else if (placed.length) {
                panel.selectedAddr = placed[0].addr
            }
        }

        function stepDisplayed(dir) {
            const cards = []
            for (let i = 0; i < panel.cards.length; i++) {
                if (!panel.cards[i].all)
                    cards.push(panel.cards[i])
            }
            if (!cards.length)
                return
            let idx = 0
            for (let i = 0; i < cards.length; i++) {
                if (cards[i].key === panel.displayedKey)
                    idx = i
            }
            const prevId = cards[idx] ? cards[idx].id : 0
            let next = idx + dir
            if (next < 0)
                next = cards.length - 1
            if (next >= cards.length)
                next = 0
            root.switchDir = cards[next].id >= prevId ? 1 : -1
            panel.chooseCard(cards[next], true)
        }

        function chooseCard(card, fromKey) {
            if (!card)
                return
            if (card.all) {
                root.viewMode = root.viewMode === "all" ? "workspace" : "all"
                panel.rebuild(true)
                return
            }
            root.viewMode = "workspace"
            const prev = panel.displayedKey
            if (card.phantom && (fromKey || root.hostBar.ovSwitchOnNew))
                root.dispatchFocusWorkspace(card.id, panel.monName)
            panel.displayedKey = card.key
            if (prev !== card.key && root.hostBar.ovSwitchAnimation) {
                panel.slideX = root.switchDir * Math.min(160, area.width * 0.18)
                slideAnim.restart()
            }
            panel.selectedAddr = ""
            panel.rebuild(true)
        }

        function chooseIndex(index) {
            if (index < 0 || index >= panel.cards.length)
                return
            const card = panel.cards[index]
            root.switchDir = 1
            panel.chooseCard(card, false)
        }

        function moveSelection(dx, dy) {
            const items = panel.placements
            if (!items.length)
                return
            let cur = null
            for (let i = 0; i < items.length; i++) {
                if (items[i].addr === panel.selectedAddr)
                    cur = items[i]
            }
            if (!cur)
                cur = items[0]
            const cx = cur.x + cur.w / 2
            const cy = cur.y + cur.h / 2
            let best = null
            let bestScore = 1e12
            for (let i = 0; i < items.length; i++) {
                const it = items[i]
                if (it.addr === cur.addr)
                    continue
                const vx = (it.x + it.w / 2) - cx
                const vy = (it.y + it.h / 2) - cy
                if (dx !== 0 && (vx === 0 || (vx > 0) !== (dx > 0)))
                    continue
                if (dy !== 0 && (vy === 0 || (vy > 0) !== (dy > 0)))
                    continue
                const primary = dx !== 0 ? Math.abs(vx) : Math.abs(vy)
                const secondary = dx !== 0 ? Math.abs(vy) : Math.abs(vx)
                const score = primary + secondary * 2
                if (score < bestScore) {
                    bestScore = score
                    best = it
                }
            }
            if (best)
                panel.selectedAddr = best.addr
        }

        function activateSelected() {
            if (!panel.selectedAddr)
                return
            root.skipCommit = true
            root.focusWindow(panel.selectedAddr)
            root.closeOverview()
        }

        function closeSelected() {
            if (!panel.selectedAddr)
                return
            root.closeWindow(panel.selectedAddr)
        }

        function toggleDesktop() {
            root.viewMode = root.viewMode === "desktop" ? "workspace" : "desktop"
            panel.rebuild(true)
        }

        function setDrag(item, mouse) {
            const local = stage.mapFromGlobal(mouse.x, mouse.y)
            // MouseEvent global position is on the event in Qt 6 as mouse.x relative
            // to the mouse area. Callers pass a point already mapped.
            panel.drag = {
                addr: item.addr,
                title: item.title,
                x: local.x - item.w / 2,
                y: local.y - item.h / 2,
                w: item.w,
                h: item.h
            }
        }

        function clearDrag() {
            panel.drag = null
            panel.dropKey = ""
        }

        function cardAtStage(sx, sy) {
            let best = null
            let bestD = 1e12
            for (let i = 0; i < cardRepeater.count; i++) {
                const it = cardRepeater.itemAt(i)
                if (!it || !it.card)
                    continue
                const local = it.mapFromItem(stage, sx, sy)
                if (local.x < -16 || local.y < -16 || local.x > it.width + 16 || local.y > it.height + 16)
                    continue
                const d = Math.abs(local.x - it.width / 2) + Math.abs(local.y - it.height / 2)
                if (d < bestD) {
                    bestD = d
                    best = it
                }
            }
            return best
        }

        function previewAtStage(sx, sy) {
            for (let i = 0; i < previewRepeater.count; i++) {
                const it = previewRepeater.itemAt(i)
                if (!it)
                    continue
                const local = it.mapFromItem(stage, sx, sy)
                if (local.x >= 0 && local.y >= 0 && local.x < it.width && local.y < it.height)
                    return it
            }
            return null
        }

        function finishDrag(item, sx, sy) {
            const card = panel.cardAtStage(sx, sy)
            if (card && card.card) {
                const target = card.card
                const ws = root.workspaceTarget(target)
                if (ws !== null && target.key !== panel.displayedKey) {
                    root.moveWindow(item.addr, ws, !!root.hostBar.ovSwitchOnDrop)
                    panel.startFlight(item, card)
                    if (root.hostBar.ovSwitchOnDrop) {
                        root.viewMode = "workspace"
                        panel.displayedKey = target.key
                    }
                    panel.clearDrag()
                    panel.rebuild(true)
                    return
                }
            }
            if (root.hostBar.ovDragToSwap && root.effectiveLayout() === "grid") {
                const hit = panel.previewAtStage(sx, sy)
                if (hit && hit.previewAddr && hit.previewAddr !== item.addr) {
                    panel.startFlight(item, hit)
                    root.swapWindow(item.addr, hit.previewAddr)
                }
            }
            panel.clearDrag()
        }

        function itemAtGlobal(rep, gx, gy) {
            if (!rep)
                return null
            for (let i = 0; i < rep.count; i++) {
                const it = rep.itemAt(i)
                if (!it)
                    continue
                const p = it.mapFromGlobal(gx, gy)
                if (p.x >= 0 && p.y >= 0 && p.x < it.width && p.y < it.height)
                    return it
            }
            return null
        }

        function startFlight(item, target) {
            if (!root.hostBar.ovMoveAnimation || !target)
                return
            const drag = panel.drag
            const center = stage.mapFromItem(target, target.width / 2, target.height / 2)
            panel.flyX = drag ? drag.x : item.x
            panel.flyY = drag ? drag.y : item.y
            panel.flyW = drag ? drag.w : item.w
            panel.flyH = drag ? drag.h : item.h
            panel.flyTw = Math.max(36, target.width * 0.42)
            panel.flyTh = Math.max(24, target.height * 0.34)
            panel.flyTx = center.x - panel.flyTw / 2
            panel.flyTy = center.y - panel.flyTh / 2
            panel.flyTitle = (drag && drag.title) || item.title || ""
            panel.flying = true
            panel.flyT = 0
            flyAnim.restart()
            flyDone.restart()
        }

        function hue(text) {
            let h = 0
            const s = String(text || "")
            for (let i = 0; i < s.length; i++)
                h = (h * 33 + s.charCodeAt(i)) >>> 0
            return (h % 360) / 360
        }

        anchors.left: true
        anchors.right: true
        anchors.top: true
        anchors.bottom: true
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-overview"
        WlrLayershell.keyboardFocus: panel.takesKeys ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"
        visible: panel.monName !== "" && (root.open || root.reveal > 0.02)

        onWatchKeyChanged: panel.rebuild(false)
        onTakesKeysChanged: {
            if (panel.takesKeys && root.open)
                keyItem.forceActiveFocus()
        }
        onVisibleChanged: {
            if (visible && panel.takesKeys && root.open)
                keyItem.forceActiveFocus()
        }
        onWidthChanged: panel.rebuild(false)
        onHeightChanged: panel.rebuild(false)

        Behavior on slideX {
            enabled: false
        }
        NumberAnimation {
            id: slideAnim
            target: panel
            property: "slideX"
            to: 0
            duration: Math.max(1, root.hostBar.ovSwitchDuration)
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            id: flyAnim
            target: panel
            property: "flyT"
            from: 0
            to: 1
            duration: Math.max(1, root.hostBar.ovMoveDuration)
            easing.type: Easing.InOutCubic
            onFinished: panel.flying = false
        }
        Timer {
            id: flyDone
            interval: Math.max(32, root.hostBar.ovMoveDuration + 50)
            onTriggered: panel.flying = false
        }

        Rectangle {
            id: scrim
            anchors.fill: parent
            color: panel.backdrop
            opacity: root.reveal
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onClicked: {
                if (root.hostBar.ovExitOnClick)
                    root.closeOverview()
            }
        }

        Connections {
            target: root
            function onOpenSerialChanged() {
                if (root.open)
                    panel.captureOpen()
            }
            function onCommitSerialChanged() {
                panel.commitDisplayed()
            }
            function onStepSerialChanged() {
                if (panel.takesKeys)
                    panel.stepDisplayed(root.stepDir)
            }
        }

        Item {
            id: keyItem
            anchors.fill: parent
            focus: panel.takesKeys && root.open
            Keys.onPressed: function (event) {
                panel.shiftChord = panel.shiftChord || !!(event.modifiers & Qt.ShiftModifier)
                if (event.key === Qt.Key_Shift) {
                    panel.shiftChord = false
                    event.accepted = true
                    return
                }
                const mods = event.modifiers
                const superDown = !!(mods & Qt.MetaModifier)
                if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) && superDown) {
                    root.toggle()
                    event.accepted = true
                    return
                }
                if (event.key === Qt.Key_Escape) {
                    root.closeOverview()
                    event.accepted = true
                    return
                }
                if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (mods & Qt.ShiftModifier))) {
                    panel.stepDisplayed(-1)
                    event.accepted = true
                    return
                }
                if (event.key === Qt.Key_Tab) {
                    panel.stepDisplayed(1)
                    event.accepted = true
                    return
                }
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    panel.activateSelected()
                    event.accepted = true
                    return
                }
                if (event.key === Qt.Key_Left) {
                    panel.moveSelection(-1, 0)
                    event.accepted = true
                    return
                }
                if (event.key === Qt.Key_Right) {
                    panel.moveSelection(1, 0)
                    event.accepted = true
                    return
                }
                if (event.key === Qt.Key_Up) {
                    panel.moveSelection(0, -1)
                    event.accepted = true
                    return
                }
                if (event.key === Qt.Key_Down) {
                    panel.moveSelection(0, 1)
                    event.accepted = true
                    return
                }
                if ((event.key === Qt.Key_D || event.text === "d" || event.text === "D") && !(mods & (Qt.ControlModifier | Qt.MetaModifier | Qt.AltModifier))) {
                    panel.closeSelected()
                    event.accepted = true
                    return
                }
                if ((event.text === "a" || event.text === "A") && !(mods & (Qt.ControlModifier | Qt.MetaModifier | Qt.AltModifier))) {
                    root.viewMode = root.viewMode === "all" ? "workspace" : "all"
                    panel.rebuild(true)
                    event.accepted = true
                    return
                }
                if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9 && !(mods & (Qt.ControlModifier | Qt.MetaModifier | Qt.AltModifier))) {
                    const digit = event.key === Qt.Key_0 ? 9 : (event.key - Qt.Key_1)
                    panel.chooseIndex(digit)
                    event.accepted = true
                    return
                }
                event.accepted = true
            }
            Keys.onReleased: function (event) {
                if (event.key === Qt.Key_Shift && !panel.shiftChord)
                    panel.toggleDesktop()
                if (event.key === Qt.Key_Shift)
                    panel.shiftChord = false
            }
        }

        Item {
            id: stage
            anchors.fill: parent
            opacity: root.reveal

            WheelHandler {
                onWheel: function (event) {
                    if (!root.open || !root.hostBar.ovScrollSwitches || !panel.takesKeys)
                        return
                    if (event.angleDelta.y > 0)
                        panel.stepDisplayed(-1)
                    else if (event.angleDelta.y < 0)
                        panel.stepDisplayed(1)
                }
            }

            Item {
                id: stripHost
                x: panel.anchor === "right" ? parent.width - width - panel.stripOffset : (panel.anchor === "left" ? panel.stripOffset : 0)
                y: panel.anchor === "bottom" ? parent.height - height - panel.stripOffset : (panel.anchor === "top" ? panel.stripOffset : 0)
                width: panel.stripHorizontal ? parent.width : panel.thickness
                height: panel.stripHorizontal ? panel.thickness : parent.height

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(1, 1, 1, 0.06)
                }

                Flickable {
                    id: stripFlick
                    anchors.fill: parent
                    anchors.margins: Math.max(6, root.hostBar.ovStripMargin)
                    clip: true
                    contentWidth: cardBox.width
                    contentHeight: cardBox.height
                    flickableDirection: panel.stripHorizontal ? Flickable.HorizontalFlick : Flickable.VerticalFlick
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: panel.drag === null

                    Item {
                        id: cardBox
                        width: panel.stripHorizontal
                               ? Math.max(stripFlick.width, panel.cards.length * panel.cardPitch().w)
                               : stripFlick.width
                        height: panel.stripHorizontal
                                ? stripFlick.height
                                : Math.max(stripFlick.height, panel.cards.length * panel.cardPitch().h)

                        Repeater {
                            id: cardRepeater
                            model: panel.cards
                            delegate: Item {
                                id: cardItem
                                required property var modelData
                                required property int index
                                property var card: modelData
                                property bool cardActive: {
                                    if (modelData.all)
                                        return root.viewMode === "all"
                                    return root.viewMode !== "all" && modelData.key === panel.displayedKey
                                }
                                readonly property real pitchW: panel.cardPitch().w
                                readonly property real pitchH: panel.cardPitch().h
                                x: panel.stripHorizontal ? index * pitchW : 0
                                y: panel.stripHorizontal ? 0 : index * pitchH
                                width: pitchW
                                height: pitchH

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Text {
                                        readonly property bool numbers: root.hostBar.ovNumberLabels && !modelData.all && !modelData.special
                                        visible: root.hostBar.ovShowWsLabels
                                        width: panel.cardSize().w
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        text: root.cardCaption(modelData)
                                        color: (!numbers && modelData.color && String(modelData.color).length)
                                               ? modelData.color
                                               : (cardItem.cardActive ? "white" : Qt.rgba(1, 1, 1, 0.86))
                                        font.pixelSize: 12
                                        font.bold: numbers ? true : modelData.bold !== false
                                        font.italic: numbers ? false : !!modelData.italic
                                        font.family: (numbers || !(modelData.font && String(modelData.font).length))
                                                      ? root.hostBar.fontFamily
                                                      : modelData.font
                                    }
                                    Rectangle {
                                        id: cardFace
                                        width: panel.cardSize().w
                                        height: panel.cardSize().h
                                        radius: root.hostBar.ovStripCardRound
                                        color: modelData.phantom ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0.05, 0.07, 0.11, 0.92)
                                        border.width: panel.dropKey === modelData.key ? 3 : (cardItem.cardActive || cardMa.containsMouse ? 2 : 1)
                                        border.color: (panel.dropKey === modelData.key || cardItem.cardActive)
                                                       ? panel.accent
                                                       : (cardMa.containsMouse ? Qt.rgba(1, 1, 1, 0.7) : Qt.rgba(1, 1, 1, 0.16))
                                        clip: true

                                        Repeater {
                                            model: modelData.minis || []
                                            delegate: Item {
                                                id: mini
                                                required property var modelData
                                                x: modelData.x
                                                y: modelData.y
                                                width: Math.max(4, modelData.w)
                                                height: Math.max(4, modelData.h)
                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: 1
                                                    visible: !miniCap.hasContent
                                                    color: Qt.hsla(panel.hue(modelData.appId || modelData.title), 0.45, 0.62, 0.95)
                                                }
                                                ScreencopyView {
                                                    id: miniCap
                                                    anchors.fill: parent
                                                    captureSource: {
                                                        if (!root.open || !root.hostBar.ovStripPreviews)
                                                            return null
                                                        const tl = root.toplevelFor(modelData.addr)
                                                        return tl ? tl.wayland : null
                                                    }
                                                    live: root.open && !!root.hostBar.ovStripPreviews && !!root.hostBar.ovLivePreviews
                                                    function grabStill() {
                                                        if (!root.open || live || !captureSource)
                                                            return
                                                        Qt.callLater(function () {
                                                            if (!root.open || live || !captureSource)
                                                                return
                                                            captureFrame()
                                                        })
                                                    }
                                                    onCaptureSourceChanged: grabStill()
                                                    onLiveChanged: grabStill()
                                                }
                                            }
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            visible: modelData.all || (modelData.phantom && !root.hostBar.ovDynamic)
                                            text: modelData.all ? "All" : "+"
                                            color: Qt.rgba(0.88, 0.94, 1, 0.9)
                                            font.pixelSize: 18
                                            font.family: root.hostBar.fontFamily
                                        }
                                        MouseArea {
                                            id: cardMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: panel.chooseCard(cardItem.card, false)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item {
                id: canvas
                x: panel.anchor === "left" ? panel.thickness + panel.stripOffset : 0
                y: panel.anchor === "top" ? panel.thickness + panel.stripOffset : 0
                width: parent.width - (panel.stripHorizontal ? 0 : panel.thickness + panel.stripOffset)
                height: parent.height - (panel.stripHorizontal ? panel.thickness + panel.stripOffset : 0)

                Item {
                    id: area
                    anchors.fill: parent
                    anchors.leftMargin: panel.pad("left")
                    anchors.rightMargin: panel.pad("right")
                    anchors.topMargin: panel.pad("top")
                    anchors.bottomMargin: panel.pad("bottom")
                    onWidthChanged: panel.rebuild(false)
                    onHeightChanged: panel.rebuild(false)

                    Item {
                        id: slideHost
                        x: panel.slideX
                        width: parent.width
                        height: parent.height

                        Text {
                            anchors.centerIn: parent
                            visible: panel.placements.length === 0 && root.open
                            text: root.viewMode === "all" ? "No windows on this monitor" : "Empty workspace"
                            color: Qt.rgba(1, 1, 1, 0.72)
                            font.pixelSize: 18
                            font.family: root.hostBar.fontFamily
                        }

                        Repeater {
                            id: previewRepeater
                            model: panel.placements
                            delegate: Item {
                                id: preview
                                required property var modelData
                                property string previewAddr: modelData.addr
                                x: modelData.x
                                y: modelData.y
                                width: modelData.w
                                height: modelData.h
                                z: previewMa.pressed ? 20 : (panel.selectedAddr === modelData.addr ? 2 : 1)

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    radius: root.hostBar.ovPreviewRound + 4
                                    color: "#000000"
                                    opacity: 0.38
                                    z: -1
                                }

                                Rectangle {
                                    id: frame
                                    anchors.fill: parent
                                    radius: root.hostBar.ovPreviewRound
                                    color: "#14181f"
                                    clip: true
                                    border.width: panel.selectedAddr === modelData.addr ? panel.selectBorder : (previewMa.containsMouse ? panel.hoverBorder : 0)
                                    border.color: panel.selectedAddr === modelData.addr ? panel.accent : Qt.rgba(1, 1, 1, 0.85)

                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: frame.border.width
                                        visible: !capture.hasContent
                                        color: Qt.hsla(panel.hue(modelData.appId || modelData.title), 0.35, 0.28, 1)
                                        Text {
                                            anchors.centerIn: parent
                                            width: parent.width - 12
                                            horizontalAlignment: Text.AlignHCenter
                                            elide: Text.ElideRight
                                            text: modelData.appId || modelData.title
                                            color: "white"
                                            font.pixelSize: Math.max(11, Math.min(22, preview.height * 0.12))
                                            font.family: root.hostBar.fontFamily
                                        }
                                    }
                                    ScreencopyView {
                                        id: capture
                                        anchors.fill: parent
                                        anchors.margins: frame.border.width
                                        captureSource: {
                                            if (!root.open)
                                                return null
                                            const tl = root.toplevelFor(modelData.addr)
                                            return tl ? tl.wayland : null
                                        }
                                        live: root.open && !!root.hostBar.ovLivePreviews
                                        // A still is only needed when live previews are off.
                                        // Grabbing before the toplevel export exists logs a warning and draws nothing.
                                        function grabStill() {
                                            if (!root.open || live || !captureSource)
                                                return
                                            Qt.callLater(function () {
                                                if (!root.open || live || !captureSource)
                                                    return
                                                captureFrame()
                                            })
                                        }
                                        onCaptureSourceChanged: grabStill()
                                        onLiveChanged: grabStill()
                                    }
                                }

                                Rectangle {
                                    visible: panel.desktopMode
                                    z: 30
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 8
                                    width: 22
                                    height: 22
                                    radius: 11
                                    color: closeMa.containsMouse ? "#ff5a5a" : "#e23b3b"
                                    Text {
                                        anchors.centerIn: parent
                                        text: "✕"
                                        color: "white"
                                        font.pixelSize: 12
                                        font.bold: true
                                    }
                                    MouseArea {
                                        id: closeMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.closeWindow(modelData.addr)
                                    }
                                }

                                Rectangle {
                                    visible: root.hostBar.ovShowWindowLabels && (previewMa.containsMouse || panel.selectedAddr === modelData.addr)
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.top: parent.bottom
                                    anchors.topMargin: 6
                                    width: Math.min(parent.width, label.implicitWidth + 16)
                                    height: 22
                                    radius: 11
                                    color: Qt.rgba(0.05, 0.06, 0.08, 0.88)
                                    Text {
                                        id: label
                                        anchors.centerIn: parent
                                        text: modelData.title
                                        color: "white"
                                        font.pixelSize: 11
                                        font.family: root.hostBar.fontFamily
                                        elide: Text.ElideRight
                                        width: Math.min(preview.width - 8, 280)
                                    }
                                }

                                MouseArea {
                                    id: previewMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    preventStealing: true
                                    property real pressGX
                                    property real pressGY
                                    property bool moved
                                    onContainsMouseChanged: {
                                        if (containsMouse && root.hostBar.ovFocusFollowsMouse)
                                            panel.selectedAddr = modelData.addr
                                    }
                                    onPressed: function (mouse) {
                                        const p = stage.mapFromItem(preview, mouse.x, mouse.y)
                                        pressGX = p.x
                                        pressGY = p.y
                                        moved = false
                                        panel.selectedAddr = modelData.addr
                                    }
                                    onPositionChanged: function (mouse) {
                                        if (!(mouse.buttons & Qt.LeftButton))
                                            return
                                        const p = stage.mapFromItem(preview, mouse.x, mouse.y)
                                        if (Math.abs(p.x - pressGX) + Math.abs(p.y - pressGY) > 8)
                                            moved = true
                                        if (!moved)
                                            return
                                        panel.drag = {
                                            addr: modelData.addr,
                                            title: modelData.title,
                                            x: p.x - width / 2,
                                            y: p.y - height / 2,
                                            w: width,
                                            h: height
                                        }
                                        const hit = panel.cardAtStage(p.x, p.y)
                                        panel.dropKey = (hit && hit.card) ? hit.card.key : ""
                                    }
                                    onReleased: function (mouse) {
                                        const p = stage.mapFromItem(preview, mouse.x, mouse.y)
                                        try {
                                            if (moved)
                                                panel.finishDrag(modelData, p.x, p.y)
                                            else
                                                panel.activateSelected()
                                        } finally {
                                            panel.clearDrag()
                                        }
                                    }
                                    onCanceled: panel.clearDrag()
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                visible: panel.drag !== null
                x: panel.drag ? panel.drag.x : 0
                y: panel.drag ? panel.drag.y : 0
                width: panel.drag ? panel.drag.w : 0
                height: panel.drag ? panel.drag.h : 0
                radius: root.hostBar.ovPreviewRound
                color: Qt.rgba(0.1, 0.14, 0.2, 0.85)
                border.width: 2
                border.color: "white"
                z: 40
                Text {
                    anchors.centerIn: parent
                    width: parent.width - 8
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: panel.drag ? panel.drag.title : ""
                    color: "white"
                    font.pixelSize: 12
                    font.family: root.hostBar.fontFamily
                }
            }

            Rectangle {
                visible: panel.flying
                x: panel.flyX + (panel.flyTx - panel.flyX) * panel.flyT
                y: panel.flyY + (panel.flyTy - panel.flyY) * panel.flyT
                width: panel.flyW + (panel.flyTw - panel.flyW) * panel.flyT
                height: panel.flyH + (panel.flyTh - panel.flyH) * panel.flyT
                radius: root.hostBar.ovPreviewRound
                color: Qt.rgba(0.12, 0.16, 0.22, 0.9)
                border.width: 2
                border.color: panel.accent
                z: 41
            }
        }

        function cardPitch() {
            const size = panel.cardSize()
            const gap = Math.max(0, root.hostBar.ovStripGap)
            const label = root.hostBar.ovShowWsLabels ? 22 : 0
            if (panel.stripHorizontal)
                return { w: size.w + gap, h: Math.max(1, stripFlick.height) }
            return { w: Math.max(1, stripFlick.width), h: size.h + label + gap }
        }

        function cardSize() {
            const margin = Math.max(6, root.hostBar.ovStripMargin)
            const labelH = root.hostBar.ovShowWsLabels ? 18 : 0
            const mon = panel.hyprMonitor
            const aspect = (mon && mon.width > 0 && mon.height > 0) ? (mon.width / mon.height) : (16 / 9)
            let cardH = 0
            let cardW = 0
            if (panel.stripHorizontal) {
                const inner = Math.max(36, panel.thickness - margin * 2 - labelH - 8)
                cardH = inner
                cardW = cardH * aspect
                const cap = Math.max(160, root.hostBar.ovStripCardMax || 300)
                if (cardW > cap) {
                    cardW = cap
                    cardH = cardW / aspect
                }
            } else {
                const inner = Math.max(36, panel.thickness - margin * 2)
                cardW = inner
                cardH = cardW / aspect
                const cap = Math.max(160, root.hostBar.ovStripCardMax || 300)
                if (cardH > cap) {
                    cardH = cap
                    cardW = cardH * aspect
                }
            }
            return { w: Math.max(48, cardW), h: Math.max(32, cardH) }
        }

        function miniWindows(key) {
            const wins = root.visibleWindows(panel.monName, key, "workspace")
            const mon = panel.hyprMonitor || root.monitorByName(panel.monName)
            if (!mon)
                return []
            const size = panel.cardSize()
            const inset = 4
            const aw = Math.max(8, size.w - inset * 2)
            const ah = Math.max(8, size.h - inset * 2)
            const placed = root.placeNatural(wins.map(function (win) {
                return {
                    addr: win.addr,
                    title: win.title,
                    appId: win.appId,
                    realW: win.w,
                    realH: win.h,
                    gx: win.x,
                    gy: win.y
                }
            }), mon, aw, ah, 1, 1)
            // placeNatural already scales into the card. Offset by the inset.
            const out = []
            for (let i = 0; i < placed.length; i++) {
                out.push({
                    x: placed[i].x + inset,
                    y: placed[i].y + inset,
                    w: placed[i].w,
                    h: placed[i].h,
                    addr: placed[i].addr,
                    appId: placed[i].appId,
                    title: placed[i].title
                })
            }
            return out
        }
    }
}
