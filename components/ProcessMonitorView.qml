import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io as Io

// Processes tab — mirrors ServicesView architecture:
//   - Summary from live sysmon poll (load + process_stats)
//   - Full process list loaded on-demand via own poller (tab open + Refresh only)
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

    readonly property string pollerScript: Quickshell.shellPath("scripts/run-process-poller.sh")
    readonly property string controlScript: Quickshell.shellPath("scripts/process-control.sh")

    readonly property int cardRadius: 6
    readonly property int cardMargin: 10
    readonly property int rowHeight: 22
    readonly property int headerHeight: 20
    readonly property int sectionSpacing: 8
    readonly property int tblSpacing: 6
    readonly property int tblRowPad: 6
    readonly property int tblCellPad: 10

    readonly property var colMinW: ({
        pid: 40, user: 36, cpu: 38, mem: 38, time: 42, start: 46,
        threads: 26, rss: 38, vsz: 42, pri: 24, nice: 28, shr: 36, stat: 28, cmd: 120
    })
    readonly property var colMaxW: ({
        user: 92, time: 68, start: 60, cmd: 420
    })
    property var colLayout: ({
        pid: 40, user: 36, cpu: 38, mem: 38, time: 42, start: 46,
        threads: 26, rss: 38, vsz: 42, pri: 24, nice: 28, shr: 36, stat: 28, cmd: 120,
        fixed: 0, total: 640
    })
    property int colLayoutVersion: 0

    property var processes: []
    property int dataVersion: 0
    property bool loading: false
    property string sortKey: "cpu"
    property bool highUsageOnly: false
    property var selectedPids: []
    property int selectionVersion: 0
    property int anchorIndex: -1
    property bool acting: false
    readonly property bool hasSelection: selectedPids.length > 0
    readonly property int selectedCount: selectedPids.length
    // Back-compat for status bar bindings
    readonly property int selectedPid: selectedPids.length === 1 ? selectedPids[0] : 0
    property string lastError: ""
    property string lastAction: ""
    property bool _loadHandled: false
    property bool _actionHandled: false
    property int _lastActionExitCode: 0
    property var _actionQueue: []
    property int _actionIndex: 0
    property string _pendingAction: ""
    property bool killConfirmVisible: false
    property string lastUpdatedLabel: ""
    property int lastUpdatedVersion: 0
    property var expandedGroups: ({})
    property int groupStateVersion: 0
    property bool groupedView: true
    property int viewModeVersion: 0

    readonly property int summaryHeight: Math.max(68, Math.min(94, Math.round(height * 0.12)))
    readonly property int groupIndent: 14

    function cloneProcessRow(p) {
        return {
            pid: p.pid,
            user: p.user || "",
            name: p.name || "",
            cmd: p.cmd || p.name || "",
            state: p.state || "",
            nice: p.nice,
            pri: p.pri,
            cpu: Number(p.cpu || 0),
            mem: Number(p.mem || 0),
            rss: p.rss,
            vsz: p.vsz,
            shr: p.shr,
            time: p.time || "",
            start: p.start || "",
            threads: p.threads
        }
    }

    function filterQuery() {
        return (globalFilter && globalFilter.trim()) ? globalFilter.toLowerCase().trim() : ""
    }

    function commandGroupKey(p) {
        const cmd = (p.cmd || p.name || "").toLowerCase().trim()
        if (!cmd) return ""
        let base = cmd.split(/\s+/)[0]
        const slash = base.lastIndexOf("/")
        if (slash >= 0) base = base.substring(slash + 1)
        return base
    }

    function filteredProcesses() {
        const tick = dataVersion + "|" + sortKey + "|" + (highUsageOnly ? "1" : "0") + "|" + globalFilter + "|" + processes.length
        void tick

        if (!processes || !processes.length) return []

        const q = filterQuery()
        const rows = []
        for (let i = 0; i < processes.length; i++) {
            const p = processes[i]
            if (!p) continue
            if (highUsageOnly && p.cpu < 1 && p.mem < 1)
                continue
            if (q) {
                const hay = [
                    String(p.pid || ""),
                    p.user, p.name, p.cmd,
                    formatState(p.state),
                    p.start || ""
                ].join(" ").toLowerCase()
                if (hay.indexOf(q) === -1)
                    continue
            }
            rows.push(p)
        }

        const metric = sortKey === "mem" ? "mem" : "cpu"
        rows.sort(function(a, b) { return b[metric] - a[metric] })
        return rows
    }

    function isGroupExpanded(key) {
        const tick = groupStateVersion
        void tick
        return !!expandedGroups[key]
    }

    function toggleGroup(key) {
        if (!key || !groupedView) return
        const next = Object.assign({}, expandedGroups)
        if (next[key])
            delete next[key]
        else
            next[key] = true
        expandedGroups = next
        groupStateVersion++
        Qt.callLater(function() { root.refreshColumnLayout(procFlickable.width) })
    }

    function toggleGroupedView() {
        groupedView = !groupedView
        viewModeVersion++
        Qt.callLater(function() { root.refreshColumnLayout(procFlickable.width) })
    }

    function processDisplayRow(p, rowType, indent) {
        return {
            rowType: rowType,
            groupKey: commandGroupKey(p),
            indent: indent || 0,
            pid: p.pid,
            user: p.user,
            name: p.name,
            cmd: p.cmd,
            state: p.state,
            nice: p.nice,
            pri: p.pri,
            cpu: p.cpu,
            mem: p.mem,
            rss: p.rss,
            vsz: p.vsz,
            shr: p.shr,
            time: p.time,
            start: p.start,
            threads: p.threads,
            memberPids: []
        }
    }

    function buildGroupRow(key, members, expanded) {
        let cpu = 0
        let mem = 0
        let rss = 0
        let vsz = 0
        let shr = 0
        let threads = 0
        const pids = []
        let user = members[0].user || ""
        let mixedUser = false
        for (let i = 0; i < members.length; i++) {
            const p = members[i]
            pids.push(p.pid)
            cpu += p.cpu
            mem += p.mem
            rss += Number(p.rss) || 0
            vsz += Number(p.vsz) || 0
            shr += Number(p.shr) || 0
            threads += Number(p.threads) || 0
            if ((p.user || "") !== user)
                mixedUser = true
        }
        return {
            rowType: "group",
            groupKey: key,
            label: key,
            count: members.length,
            expanded: expanded,
            memberPids: pids,
            indent: 0,
            pid: 0,
            user: mixedUser ? "…" : user,
            name: key,
            cmd: key + " (" + members.length + ")",
            state: "",
            nice: undefined,
            pri: undefined,
            cpu: cpu,
            mem: mem,
            rss: rss,
            vsz: vsz,
            shr: shr,
            time: "",
            start: "",
            threads: threads
        }
    }

    function displayRows() {
        const tick = dataVersion + "|" + sortKey + "|" + (highUsageOnly ? "1" : "0")
            + "|" + globalFilter + "|" + groupStateVersion + "|" + viewModeVersion
            + "|" + (groupedView ? "1" : "0")
        void tick

        const procs = filteredProcesses()
        if (!procs.length)
            return []

        if (!groupedView) {
            const flat = []
            for (let f = 0; f < procs.length; f++)
                flat.push(processDisplayRow(procs[f], "process", 0))
            return flat
        }

        const metric = sortKey === "mem" ? "mem" : "cpu"
        const groups = {}
        const order = []
        for (let i = 0; i < procs.length; i++) {
            const p = procs[i]
            const key = commandGroupKey(p)
            if (!groups[key]) {
                groups[key] = []
                order.push(key)
            }
            groups[key].push(p)
        }

        for (let g = 0; g < order.length; g++)
            groups[order[g]].sort(function(a, b) { return b[metric] - a[metric] })

        order.sort(function(a, b) {
            const ma = groups[a]
            const mb = groups[b]
            let sumA = 0
            let sumB = 0
            for (let i = 0; i < ma.length; i++)
                sumA += ma[i][metric]
            for (let j = 0; j < mb.length; j++)
                sumB += mb[j][metric]
            if (sumB !== sumA)
                return sumB - sumA
            return a < b ? -1 : 1
        })

        const out = []
        for (let o = 0; o < order.length; o++) {
            const key = order[o]
            const members = groups[key]
            if (members.length === 1) {
                out.push(processDisplayRow(members[0], "process", 0))
            } else {
                const expanded = isGroupExpanded(key)
                out.push(buildGroupRow(key, members, expanded))
                if (expanded) {
                    for (let c = 0; c < members.length; c++)
                        out.push(processDisplayRow(members[c], "child", 1))
                }
            }
        }
        return out
    }

    function rowSelectionPids(row) {
        if (!row)
            return []
        if (row.rowType === "group")
            return row.memberPids ? row.memberPids.slice() : []
        return row.pid ? [row.pid] : []
    }

    function isDisplayRowSelected(row) {
        const tick = selectionVersion
        void tick
        if (!row)
            return false
        if (row.rowType === "group") {
            const pids = row.memberPids || []
            if (!pids.length)
                return false
            for (let i = 0; i < pids.length; i++) {
                if (!isPidSelected(pids[i]))
                    return false
            }
            return true
        }
        return isPidSelected(row.pid)
    }

    function displayRowCmdText(row) {
        if (!row)
            return "--"
        return row.cmd || row.name || "--"
    }

    function groupedAppCount() {
        const tick = dataVersion + "|" + globalFilter + "|" + sortKey
        void tick
        const procs = filteredProcesses()
        const counts = {}
        let multi = 0
        for (let i = 0; i < procs.length; i++) {
            const k = commandGroupKey(procs[i])
            counts[k] = (counts[k] || 0) + 1
        }
        for (const key in counts) {
            if (counts[key] > 1)
                multi++
        }
        return multi
    }

    function pruneExpandedGroups() {
        const procs = filteredProcesses()
        const valid = {}
        for (let i = 0; i < procs.length; i++)
            valid[commandGroupKey(procs[i])] = true
        const next = {}
        let changed = false
        for (const key in expandedGroups) {
            if (valid[key] && expandedGroups[key])
                next[key] = true
            else
                changed = true
        }
        if (changed) {
            expandedGroups = next
            groupStateVersion++
        }
    }

    function copyToClipboard(text) {
        if (!text) return
        Quickshell.execDetached([
            "sh", "-c",
            'printf "%s" "$1" | wl-copy',
            "wl-copy",
            text
        ])
        lastAction = "Copied to clipboard"
        Qt.callLater(function() {
            if (root.lastAction === "Copied to clipboard") root.lastAction = ""
        }, 1200)
    }

    function isPidSelected(pid) {
        const tick = selectionVersion
        void tick
        return selectedPids.indexOf(pid) !== -1
    }

    function setSelectedPids(pids) {
        const unique = []
        for (let i = 0; i < pids.length; i++) {
            const pid = pids[i]
            if (pid && unique.indexOf(pid) === -1)
                unique.push(pid)
        }
        selectedPids = unique
        selectionVersion++
    }

    function clearSelection() {
        selectedPids = []
        anchorIndex = -1
        selectionVersion++
    }

    function selectionLabel() {
        const n = selectedCount
        if (!n) return ""
        if (n === 1) return "PID " + selectedPids[0]
        return n + " selected"
    }

    function mergePids(target, pids) {
        const next = target.slice()
        for (let i = 0; i < pids.length; i++) {
            if (next.indexOf(pids[i]) === -1)
                next.push(pids[i])
        }
        return next
    }

    function togglePidsInSelection(pids) {
        const next = selectedPids.slice()
        let allPresent = pids.length > 0
        for (let i = 0; i < pids.length; i++) {
            if (next.indexOf(pids[i]) === -1) {
                allPresent = false
                break
            }
        }
        if (allPresent) {
            for (let j = 0; j < pids.length; j++) {
                const pos = next.indexOf(pids[j])
                if (pos !== -1)
                    next.splice(pos, 1)
            }
        } else {
            for (let k = 0; k < pids.length; k++) {
                if (next.indexOf(pids[k]) === -1)
                    next.push(pids[k])
            }
        }
        setSelectedPids(next)
    }

    function handleDisplayRowClick(row, rowIndex, mouse) {
        const mods = mouse.modifiers || 0
        const ctrl = (mods & Qt.ControlModifier) || (mods & Qt.MetaModifier)
        const shift = mods & Qt.ShiftModifier
        const rows = displayRows()
        const pids = rowSelectionPids(row)

        if (!pids.length)
            return

        if (shift && anchorIndex >= 0 && anchorIndex < rows.length) {
            const lo = Math.min(anchorIndex, rowIndex)
            const hi = Math.max(anchorIndex, rowIndex)
            let next = ctrl ? selectedPids.slice() : []
            for (let i = lo; i <= hi; i++)
                next = mergePids(next, rowSelectionPids(rows[i]))
            setSelectedPids(next)
        } else if (ctrl) {
            togglePidsInSelection(pids)
            anchorIndex = rowIndex
        } else {
            setSelectedPids(pids)
            anchorIndex = rowIndex
        }
    }

    function copySelectedPid() {
        if (!hasSelection) return
        if (selectedCount === 1)
            copyToClipboard(String(selectedPids[0]))
        else
            copyToClipboard(selectedPids.join("\n"))
    }

    function copySelectedCommand() {
        const procs = selectedProcesses()
        if (!procs.length) return
        const lines = []
        for (let i = 0; i < procs.length; i++)
            lines.push(procs[i].cmd || procs[i].name || "")
        copyToClipboard(lines.join("\n"))
    }

    function exportText() {
        const rows = filteredProcesses()
        if (!rows.length) return ""
        const lines = ["PID\tUser\tCPU%\tMem%\tTime\tStart\tThr\tRSS\tVSZ\tPR\tNI\tSHR\tCommand\tStat"]
        for (let i = 0; i < rows.length; i++) {
            const p = rows[i]
            lines.push([
                String(p.pid),
                p.user || "",
                p.cpu.toFixed(1),
                p.mem.toFixed(1),
                formatTime(p.time),
                formatStart(p.start),
                p.threads !== undefined ? String(p.threads) : "--",
                formatKiB(p.rss),
                formatKiB(p.vsz),
                p.pri !== undefined ? String(p.pri) : "--",
                formatNice(p.nice),
                formatKiB(p.shr),
                p.cmd || p.name || "",
                formatState(p.state)
            ].join("\t"))
        }
        return lines.join("\n")
    }

    function copyAll() {
        const text = exportText()
        if (text) copyToClipboard(text)
    }

    function measureCell(text, bold) {
        colMetrics.font.pixelSize = 10
        colMetrics.font.family = "monospace"
        colMetrics.font.bold = !!bold
        colMetrics.text = text ? String(text) : ""
        return Math.ceil(colMetrics.advanceWidth) + root.tblCellPad
    }

    function fitCol(key, value, bold) {
        const min = colMinW[key] || 32
        const max = colMaxW[key] || 9999
        return Math.min(max, Math.max(min, measureCell(value, bold)))
    }

    function colW(name) {
        const tick = colLayoutVersion
        void tick
        return colLayout[name] || colMinW[name] || 36
    }

    function refreshColumnLayout(viewportWidth) {
        const vw = Math.max(0, Math.round(viewportWidth || 0))
        const fixedKeys = ["pid", "user", "cpu", "mem", "time", "start", "threads", "rss", "vsz", "pri", "nice", "shr", "stat"]
        const w = {}

        for (let i = 0; i < fixedKeys.length; i++)
            w[fixedKeys[i]] = colMinW[fixedKeys[i]] || 32

        w.pid = Math.max(w.pid, fitCol("pid", "PID", true))
        w.user = Math.max(w.user, fitCol("user", "User", true))
        w.cpu = Math.max(w.cpu, fitCol("cpu", "CPU%", true))
        w.mem = Math.max(w.mem, fitCol("mem", "Mem%", true))
        w.time = Math.max(w.time, fitCol("time", "Time", true))
        w.start = Math.max(w.start, fitCol("start", "Start", true))
        w.threads = Math.max(w.threads, fitCol("threads", "Thr", true))
        w.rss = Math.max(w.rss, fitCol("rss", "RSS", true))
        w.vsz = Math.max(w.vsz, fitCol("vsz", "VSZ", true))
        w.pri = Math.max(w.pri, fitCol("pri", "PR", true))
        w.nice = Math.max(w.nice, fitCol("nice", "NI", true))
        w.shr = Math.max(w.shr, fitCol("shr", "SHR", true))
        w.stat = Math.max(w.stat, fitCol("stat", "Stat", true))

        w.pid = Math.max(w.pid, fitCol("pid", ">", false))

        let cmdContentMin = colMinW.cmd
        const rows = displayRows()
        for (let r = 0; r < rows.length; r++) {
            const p = rows[r]
            if (p.rowType === "group") {
                w.cpu = Math.max(w.cpu, fitCol("cpu", p.cpu.toFixed(1), true))
                w.mem = Math.max(w.mem, fitCol("mem", p.mem.toFixed(1), true))
                w.threads = Math.max(w.threads, fitCol("threads", p.threads !== undefined ? String(p.threads) : "--", true))
                w.rss = Math.max(w.rss, fitCol("rss", formatKiB(p.rss), true))
                w.vsz = Math.max(w.vsz, fitCol("vsz", formatKiB(p.vsz), true))
                w.shr = Math.max(w.shr, fitCol("shr", formatKiB(p.shr), true))
                w.user = Math.max(w.user, fitCol("user", p.user || "…", true))
                cmdContentMin = Math.max(cmdContentMin, fitCol("cmd", p.cmd || p.label || "--", true))
                continue
            }
            w.pid = Math.max(w.pid, fitCol("pid", String(p.pid), false))
            w.user = Math.max(w.user, fitCol("user", p.user || "--", false))
            w.cpu = Math.max(w.cpu, fitCol("cpu", p.cpu.toFixed(1), false))
            w.mem = Math.max(w.mem, fitCol("mem", p.mem.toFixed(1), false))
            w.time = Math.max(w.time, fitCol("time", formatTime(p.time), false))
            w.start = Math.max(w.start, fitCol("start", formatStart(p.start), false))
            w.threads = Math.max(w.threads, fitCol("threads", p.threads !== undefined ? String(p.threads) : "--", false))
            w.rss = Math.max(w.rss, fitCol("rss", formatKiB(p.rss), false))
            w.vsz = Math.max(w.vsz, fitCol("vsz", formatKiB(p.vsz), false))
            w.pri = Math.max(w.pri, fitCol("pri", p.pri !== undefined ? String(p.pri) : "--", false))
            w.nice = Math.max(w.nice, fitCol("nice", formatNice(p.nice), false))
            w.shr = Math.max(w.shr, fitCol("shr", formatKiB(p.shr), false))
            w.stat = Math.max(w.stat, fitCol("stat", formatState(p.state), false))
            const cmd = displayRowCmdText(p)
            const cmdPad = p.rowType === "child" ? groupIndent : 0
            cmdContentMin = Math.max(cmdContentMin, fitCol("cmd", cmd, false) + cmdPad)
        }

        let fixed = tblRowPad * 2
        for (let f = 0; f < fixedKeys.length; f++)
            fixed += w[fixedKeys[f]]
        fixed += tblSpacing * fixedKeys.length

        const minTotal = fixed + colMinW.cmd
        const neededTotal = fixed + cmdContentMin
        let total = Math.max(neededTotal, minTotal)
        if (vw > 0)
            total = Math.max(total, vw)
        w.cmd = Math.max(colMinW.cmd, total - fixed)
        w.fixed = fixed
        w.total = fixed + w.cmd
        colLayout = w
        colLayoutVersion++
    }

    function tableContentWidth(viewportWidth) {
        const tick = colLayoutVersion
        void tick
        return colLayout.total || Math.max(viewportWidth || 0, 640)
    }

    function formatLoad(load) {
        if (!load || !load.length) return "-- / -- / --"
        const a = Number(load[0] || 0).toFixed(2)
        const b = load.length > 1 ? Number(load[1] || 0).toFixed(2) : "--"
        const c = load.length > 2 ? Number(load[2] || 0).toFixed(2) : "--"
        return a + " / " + b + " / " + c
    }

    function formatState(state) {
        if (!state) return "--"
        return String(state).charAt(0).toUpperCase()
    }

    function formatNice(value) {
        if (value === undefined || value === null) return "--"
        return String(value)
    }

    function stateColor(state) {
        const s = formatState(state)
        if (s === "R") return root.accentColor
        if (s === "D") return root.errorColor
        if (s === "Z") return root.warnColor
        return root.subtextColor
    }

    function formatKiB(kb) {
        const v = Number(kb) || 0
        if (!v) return "--"
        if (v >= 1024) return (v / 1024).toFixed(1) + "M"
        return Math.round(v) + "K"
    }

    function formatTime(value) {
        if (!value) return "--"
        return String(value)
    }

    function formatStart(value) {
        if (!value) return "--"
        return String(value)
    }

    function stampLastUpdated() {
        lastUpdatedLabel = Qt.formatDateTime(new Date(), "MMM d yyyy, h:mm:ss ap")
        lastUpdatedVersion++
    }

    function summaryStats() {
        const data = service && service.data ? service.data : {}
        const stats = data.process_stats || {}
        return {
            running: stats.running || 0,
            total: stats.total || 0,
            load: data.load || []
        }
    }

    function selectedProcesses() {
        const tick = selectionVersion
        void tick
        if (!hasSelection) return []
        const wanted = {}
        for (let i = 0; i < selectedPids.length; i++)
            wanted[selectedPids[i]] = true
        const out = []
        for (let j = 0; j < processes.length; j++) {
            const p = processes[j]
            if (p && wanted[p.pid])
                out.push(p)
        }
        return out
    }

    function pruneSelection() {
        if (!hasSelection) return
        const rows = filteredProcesses()
        const visible = {}
        for (let i = 0; i < rows.length; i++)
            visible[rows[i].pid] = true
        const next = []
        for (let j = 0; j < selectedPids.length; j++) {
            if (visible[selectedPids[j]])
                next.push(selectedPids[j])
        }
        if (next.length !== selectedPids.length)
            setSelectedPids(next)
        const display = displayRows()
        if (anchorIndex >= display.length)
            anchorIndex = display.length > 0 ? Math.min(anchorIndex, display.length - 1) : -1
    }

    function refresh() {
        if (pollProcess.running || acting) return
        stampLastUpdated()
        loading = true
        lastError = ""
        _loadHandled = false
        pollProcess.running = false
        pollProcess.running = true
    }

    function finishPoll() {
        if (_loadHandled) return

        const raw = (pollStdout.text || "").trim()
        if (!raw)
            return

        _loadHandled = true
        loading = false

        try {
            const parsed = JSON.parse(raw)
            const source = parsed.processes || []
            const copy = []
            for (let i = 0; i < source.length; i++) {
                if (source[i]) copy.push(cloneProcessRow(source[i]))
            }
            processes = copy
            dataVersion++
            stampLastUpdated()
            pruneSelection()
            pruneExpandedGroups()
            lastError = ""
            Qt.callLater(function() { root.refreshColumnLayout(procFlickable.width) })
        } catch (e) {
            lastError = "Failed to parse process JSON"
        }
    }

    function requestAction(action) {
        if (!hasSelection || acting || loading) return
        if (action === "kill" && selectedCount > 1) {
            killConfirmVisible = true
            return
        }
        startAction(action)
    }

    function confirmKill() {
        killConfirmVisible = false
        startAction("kill")
    }

    function cancelKill() {
        killConfirmVisible = false
    }

    function startAction(action) {
        if (!hasSelection || acting) return
        _pendingAction = action
        _actionQueue = selectedPids.slice()
        _actionIndex = 0
        acting = true
        lastAction = ""
        lastError = ""
        runNextAction()
    }

    function runNextAction() {
        if (_actionIndex >= _actionQueue.length) {
            finishAllActions()
            return
        }
        _actionHandled = false
        actionProcess.running = false
        actionProcess.command = [root.controlScript, _pendingAction, String(_actionQueue[_actionIndex])]
        actionProcess.running = true
    }

    function finishAction(exitCode) {
        if (_actionHandled) return
        _actionHandled = true
        const code = exitCode !== undefined ? exitCode : _lastActionExitCode
        if (code !== 0) {
            const err = (actionStderr.text || actionStdout.text || "").trim()
            const pid = _actionQueue[_actionIndex]
            lastError = err.length ? err
                : (_pendingAction + " failed for PID " + pid + " (exit " + code + ")")
            acting = false
            _actionQueue = []
            _pendingAction = ""
            return
        }
        _actionIndex++
        if (_actionIndex < _actionQueue.length)
            Qt.callLater(function() { root.runNextAction() })
        else
            finishAllActions()
    }

    function finishAllActions() {
        const count = _actionIndex
        acting = false
        _actionQueue = []
        _pendingAction = ""
        lastAction = count > 1 ? ("Action completed (" + count + " processes)") : "Action completed"
        Qt.callLater(function() { root.refresh() })
    }

    function resetScroll() {
        procFlickable.contentY = 0
    }

    function focusScroll() {
        procFlickable.forceActiveFocus()
    }

    function pageScroll(direction) {
        const maxY = Math.max(0, procFlickable.contentHeight - procFlickable.height)
        if (maxY <= 0) return
        const page = Math.max(80, procFlickable.height * 0.85)
        procFlickable.contentY = Math.max(0, Math.min(maxY, procFlickable.contentY + direction * page))
    }

    function lineScroll(direction) {
        const maxY = Math.max(0, procFlickable.contentHeight - procFlickable.height)
        if (maxY <= 0) return
        const step = Math.max(root.rowHeight * 2, 24)
        procFlickable.contentY = Math.max(0, Math.min(maxY, procFlickable.contentY + direction * step))
    }

    onActiveChanged: {
        if (active) {
            refresh()
        } else {
            if (pollProcess.running)
                pollProcess.running = false
            loading = false
        }
    }

    onSortKeyChanged: {
        pruneSelection()
        Qt.callLater(function() { root.refreshColumnLayout(procFlickable.width) })
    }
    onHighUsageOnlyChanged: {
        pruneSelection()
        Qt.callLater(function() { root.refreshColumnLayout(procFlickable.width) })
    }
    onGlobalFilterChanged: {
        pruneSelection()
        Qt.callLater(function() { root.refreshColumnLayout(procFlickable.width) })
    }

    onSelectionVersionChanged: {
        if (killConfirmVisible)
            killConfirmVisible = false
    }

    onVisibleChanged: {
        if (visible && active) Qt.callLater(function() { root.focusScroll() })
    }

    Io.Process {
        id: pollProcess
        command: [root.pollerScript]
        running: false
        stdout: Io.StdioCollector {
            id: pollStdout
            onStreamFinished: root.finishPoll()
        }
        onExited: Qt.callLater(function() {
            root.finishPoll()
            if (!root._loadHandled) {
                root._loadHandled = true
                root.loading = false
                if (!(pollStdout.text || "").trim())
                    root.lastError = "Empty response from process poller"
            }
        })
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

    TextMetrics {
        id: colMetrics
        font.pixelSize: 10
        font.family: "monospace"
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: root.sectionSpacing

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.summaryHeight
            Layout.minimumHeight: 64
            radius: root.cardRadius
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: root.cardMargin
                spacing: 4

                Text {
                    text: "PROCESS SUMMARY"
                    color: root.accentColor
                    font.pixelSize: 12
                    font.bold: true
                    font.family: "monospace"
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    ColumnLayout {
                        spacing: 1
                        Text {
                            property var _bind: service && service.data ? service.data.timestamp : 0
                            text: "Total: " + root.summaryStats().total + "  ·  Running: " + root.summaryStats().running
                            color: root.subtextColor
                            font.pixelSize: 11
                            font.family: "monospace"
                        }
                        Text {
                            property var _bind: service && service.data ? service.data.timestamp : 0
                            text: "Load (1 / 5 / 15 min): " + root.formatLoad(root.summaryStats().load)
                            color: root.subtextColor
                            font.pixelSize: 11
                            font.family: "monospace"
                        }
                        Text {
                            property int _rows: root.dataVersion
                            property int _sel: root.selectionVersion
                            property int _grp: root.groupStateVersion
                            property int _view: root.viewModeVersion
                            text: root.loading ? "Loading process list…"
                                : ("Showing " + root.filteredProcesses().length + " processes"
                                    + (root.groupedView && root.groupedAppCount() > 0 ? ("  ·  " + root.groupedAppCount() + " groups") : "")
                                    + (root.hasSelection ? "  ·  " + root.selectionLabel() : ""))
                            color: root.overlayColor
                            font.pixelSize: 11
                            font.family: "monospace"
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        property var _bind: service && service.data ? service.data.timestamp : 0
                        text: root.summaryStats().load.length ? Number(root.summaryStats().load[0] || 0).toFixed(2) : "--"
                        color: root.textColor
                        font.pixelSize: 25
                        font.bold: true
                        font.family: "monospace"
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "Sort:"
                color: root.overlayColor
                font.pixelSize: 10
                font.family: "monospace"
            }

            Rectangle {
                width: sortCpuLabel.implicitWidth + 16
                height: 24
                radius: 4
                color: root.sortKey === "cpu" ? Qt.rgba(0.55, 0.70, 0.96, 0.18) : "transparent"
                border.width: root.sortKey === "cpu" ? 1 : 0
                border.color: root.accentColor
                Text {
                    id: sortCpuLabel
                    anchors.centerIn: parent
                    text: "CPU%"
                    color: root.sortKey === "cpu" ? root.accentColor : root.textColor
                    font.pixelSize: 10
                    font.family: "monospace"
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.sortKey = "cpu"
                }
            }

            Rectangle {
                width: sortMemLabel.implicitWidth + 16
                height: 24
                radius: 4
                color: root.sortKey === "mem" ? Qt.rgba(0.55, 0.70, 0.96, 0.18) : "transparent"
                border.width: root.sortKey === "mem" ? 1 : 0
                border.color: root.accentColor
                Text {
                    id: sortMemLabel
                    anchors.centerIn: parent
                    text: "Memory%"
                    color: root.sortKey === "mem" ? root.accentColor : root.textColor
                    font.pixelSize: 10
                    font.family: "monospace"
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.sortKey = "mem"
                }
            }

            Rectangle {
                width: highUsageLabel.implicitWidth + 16
                height: 24
                radius: 4
                color: root.highUsageOnly ? Qt.rgba(0.95, 0.55, 0.66, 0.16) : "transparent"
                border.width: root.highUsageOnly ? 1 : 0
                border.color: root.errorColor
                Text {
                    id: highUsageLabel
                    anchors.centerIn: parent
                    text: "High usage"
                    color: root.highUsageOnly ? root.errorColor : root.textColor
                    font.pixelSize: 10
                    font.family: "monospace"
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.highUsageOnly = !root.highUsageOnly
                }
            }

            Rectangle {
                width: groupViewLabel.implicitWidth + 16
                height: 24
                radius: 4
                color: groupViewMa.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                border.width: 1
                border.color: root.groupedView ? root.accentColor : Qt.rgba(1, 1, 1, 0.1)
                Text {
                    id: groupViewLabel
                    anchors.centerIn: parent
                    text: root.groupedView ? "Grouped" : "Ungrouped"
                    color: root.groupedView ? root.accentColor : root.textColor
                    font.pixelSize: 10
                    font.family: "monospace"
                }
                MouseArea {
                    id: groupViewMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleGroupedView()
                }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                Layout.preferredWidth: 62
                Layout.preferredHeight: 28
                radius: 6
                color: copyPidMa.containsMouse ? root.surfaceColor : "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.1)
                opacity: root.hasSelection && !root.loading ? 1 : 0.35
                Text {
                    anchors.centerIn: parent
                    text: "Copy PID"
                    color: root.accentColor
                    font.pixelSize: 10
                }
                MouseArea {
                    id: copyPidMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.hasSelection && !root.loading
                    onClicked: root.copySelectedPid()
                }
            }

            Rectangle {
                Layout.preferredWidth: 88
                Layout.preferredHeight: 28
                radius: 6
                color: copyCmdMa.containsMouse ? root.surfaceColor : "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.1)
                opacity: root.hasSelection && !root.loading ? 1 : 0.35
                Text {
                    anchors.centerIn: parent
                    text: "Copy Command"
                    color: root.accentColor
                    font.pixelSize: 10
                }
                MouseArea {
                    id: copyCmdMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.hasSelection && !root.loading
                    onClicked: root.copySelectedCommand()
                }
            }

            Rectangle {
                Layout.preferredWidth: 42
                Layout.preferredHeight: 28
                radius: 6
                color: killMa.containsMouse ? root.surfaceColor : "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.1)
                opacity: root.hasSelection && !root.acting && !root.loading ? 1 : 0.35
                Text {
                    anchors.centerIn: parent
                    text: "Kill"
                    color: root.errorColor
                    font.pixelSize: 11
                }
                MouseArea {
                    id: killMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.hasSelection && !root.acting && !root.loading
                    onClicked: root.requestAction("kill")
                }
            }

            Rectangle {
                Layout.preferredWidth: 58
                Layout.preferredHeight: 28
                radius: 6
                color: restartMa.containsMouse ? root.surfaceColor : "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.1)
                opacity: root.hasSelection && !root.acting && !root.loading ? 1 : 0.35
                Text {
                    anchors.centerIn: parent
                    text: "Restart"
                    color: root.accentColor
                    font.pixelSize: 11
                }
                MouseArea {
                    id: restartMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.hasSelection && !root.acting && !root.loading
                    onClicked: root.requestAction("restart")
                }
            }

            Text {
                visible: root.lastAction.length > 0 && root.lastError.length === 0
                text: root.lastAction
                color: root.okColor
                font.pixelSize: 10
                font.family: "monospace"
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 120
            radius: root.cardRadius
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
            clip: true

            Flickable {
                id: procFlickable
                anchors.fill: parent
                anchors.margins: 8
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: root.tableContentWidth(width)
                contentHeight: Math.max(height, procTable.implicitHeight)

                property int _dataTick: root.dataVersion
                property int _colTick: root.colLayoutVersion
                property string _filterTick: root.globalFilter + "|" + root.sortKey + "|" + (root.highUsageOnly ? "1" : "0")
                    + "|" + root.groupStateVersion + "|" + root.viewModeVersion + "|" + (root.groupedView ? "1" : "0")

                focus: true

                Component.onCompleted: root.refreshColumnLayout(width)
                onWidthChanged: Qt.callLater(function() { root.refreshColumnLayout(width) })

                WheelHandler {
                    onWheel: function(event) {
                        const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                        if (delta === 0) return
                        const maxY = Math.max(0, procFlickable.contentHeight - procFlickable.height)
                        if (maxY > 0) {
                            const ticks = delta / 120
                            procFlickable.contentY = Math.max(0, Math.min(maxY, procFlickable.contentY - ticks * 28))
                        }
                        event.accepted = true
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    policy: procFlickable.contentHeight > procFlickable.height + 1 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                    contentItem: Rectangle {
                        implicitWidth: 6
                        radius: 3
                        color: parent.pressed ? root.accentColor : Qt.rgba(1, 1, 1, 0.2)
                    }
                }

                ScrollBar.horizontal: ScrollBar {
                    policy: procFlickable.contentWidth > procFlickable.width + 1 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                    contentItem: Rectangle {
                        implicitHeight: 6
                        radius: 3
                        color: parent.pressed ? root.accentColor : Qt.rgba(1, 1, 1, 0.2)
                    }
                }

                Column {
                    id: procTable
                    width: root.tableContentWidth(procFlickable.width)
                    spacing: 0

                    Rectangle {
                        width: parent.width
                        height: root.headerHeight
                        radius: 3
                        color: Qt.rgba(0.55, 0.70, 0.96, 0.12)

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: root.tblRowPad
                            anchors.rightMargin: root.tblRowPad
                            spacing: root.tblSpacing
                            clip: true

                            Text { property int _cw: root.colLayoutVersion; width: root.colW("pid"); height: parent.height; text: "PID"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight; clip: true }
                            Text { property int _cw: root.colLayoutVersion; width: root.colW("user"); height: parent.height; text: "User"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; clip: true }
                            Text { property int _cw: root.colLayoutVersion; width: root.colW("cpu"); height: parent.height; text: "CPU%"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight; clip: true }
                            Text { property int _cw: root.colLayoutVersion; width: root.colW("mem"); height: parent.height; text: "Mem%"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight; clip: true }
                            Text { property int _cw: root.colLayoutVersion; width: root.colW("time"); height: parent.height; text: "Time"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight; clip: true }
                            Text { property int _cw: root.colLayoutVersion; width: root.colW("start"); height: parent.height; text: "Start"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight; clip: true }
                            Text { property int _cw: root.colLayoutVersion; width: root.colW("threads"); height: parent.height; text: "Thr"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight; clip: true }
                            Text { property int _cw: root.colLayoutVersion; width: root.colW("rss"); height: parent.height; text: "RSS"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight; clip: true }
                            Text { property int _cw: root.colLayoutVersion; width: root.colW("vsz"); height: parent.height; text: "VSZ"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight; clip: true }
                            Text { property int _cw: root.colLayoutVersion; width: root.colW("pri"); height: parent.height; text: "PR"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight; clip: true }
                            Text { property int _cw: root.colLayoutVersion; width: root.colW("nice"); height: parent.height; text: "NI"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight; clip: true }
                            Text { property int _cw: root.colLayoutVersion; width: root.colW("shr"); height: parent.height; text: "SHR"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight; clip: true }
                            Text { property int _cw: root.colLayoutVersion; width: root.colW("cmd"); height: parent.height; text: "Command"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; clip: true }
                            Text { property int _cw: root.colLayoutVersion; width: root.colW("stat"); height: parent.height; text: "Stat"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter; clip: true }
                        }
                    }

                    Text {
                        width: parent.width
                        visible: root.loading && root.filteredProcesses().length === 0
                        text: "Loading processes..."
                        color: root.overlayColor
                        font.pixelSize: 11
                        font.family: "monospace"
                        topPadding: 6
                    }

                    Text {
                        width: parent.width
                        visible: !root.loading && root.lastError.length > 0 && root.filteredProcesses().length === 0
                        text: root.lastError
                        color: root.errorColor
                        font.pixelSize: 11
                        font.family: "monospace"
                        wrapMode: Text.Wrap
                        topPadding: 6
                    }

                    Text {
                        width: parent.width
                        visible: !root.loading && root.filteredProcesses().length === 0 && root.lastError.length === 0
                        text: "(no matching processes)"
                        color: root.overlayColor
                        font.pixelSize: 11
                        font.family: "monospace"
                        topPadding: 6
                    }

                    Repeater {
                        property int _viewTick: root.viewModeVersion
                        model: root.displayRows()
                        delegate: Item {
                            id: rowRoot
                            width: parent.width
                            height: root.rowHeight

                            property int _selTick: root.selectionVersion
                            property int _grpTick: root.groupStateVersion
                            readonly property bool isGroup: modelData.rowType === "group"
                            readonly property bool isChild: modelData.rowType === "child"
                            readonly property bool isSelected: root.isDisplayRowSelected(modelData)
                            readonly property bool rowHover: rowMa.containsMouse

                            Rectangle {
                                anchors.top: parent.top
                                width: parent.width
                                height: 1
                                color: Qt.rgba(1, 1, 1, 0.1)
                                visible: rowRoot.isGroup && index > 0
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: 2
                                color: rowRoot.isSelected ? Qt.rgba(0.55, 0.70, 0.96, 0.18)
                                    : (rowRoot.rowHover ? Qt.rgba(1, 1, 1, 0.04)
                                        : (rowRoot.isGroup ? Qt.rgba(0.55, 0.70, 0.96, 0.08)
                                            : (rowRoot.isChild ? Qt.rgba(1, 1, 1, 0.015)
                                                : (index % 2 === 0 ? "transparent" : Qt.rgba(1, 1, 1, 0.02)))))
                            }

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: root.tblRowPad
                                anchors.rightMargin: root.tblRowPad
                                spacing: root.tblSpacing
                                clip: true

                                Item {
                                    width: root.colW("pid")
                                    height: parent.height
                                    clip: true

                                    Text {
                                        visible: rowRoot.isGroup
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        leftPadding: 2
                                        text: modelData.expanded ? "v" : ">"
                                        color: root.accentColor
                                        font.pixelSize: 11
                                        font.bold: true
                                        font.family: "monospace"
                                    }

                                    Text {
                                        visible: !rowRoot.isGroup
                                        anchors.fill: parent
                                        text: modelData.pid
                                        color: rowRoot.isSelected ? root.accentColor : root.textColor
                                        font.pixelSize: 10
                                        font.family: "monospace"
                                        font.bold: rowRoot.isSelected
                                        verticalAlignment: Text.AlignVCenter
                                        horizontalAlignment: Text.AlignRight
                                        clip: true
                                    }

                                    Text {
                                        visible: rowRoot.isGroup
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: String(modelData.count || "")
                                        color: root.overlayColor
                                        font.pixelSize: 9
                                        font.family: "monospace"
                                        clip: true
                                    }

                                    MouseArea {
                                        visible: rowRoot.isGroup
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: function(mouse) {
                                            root.toggleGroup(modelData.groupKey)
                                            mouse.accepted = true
                                        }
                                    }
                                }

                                Text {
                                    property int _cw: root.colLayoutVersion
                                    width: root.colW("user")
                                    height: parent.height
                                    text: rowRoot.isGroup ? (modelData.user || "…") : (modelData.user || "--")
                                    color: rowRoot.isGroup ? root.textColor : root.overlayColor
                                    font.pixelSize: 10
                                    font.family: "monospace"
                                    font.bold: rowRoot.isGroup
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                    clip: true
                                }
                                Text {
                                    property int _cw: root.colLayoutVersion
                                    width: root.colW("cpu")
                                    height: parent.height
                                    text: modelData.cpu.toFixed(1)
                                    color: root.accentColor
                                    font.pixelSize: 10
                                    font.family: "monospace"
                                    font.bold: rowRoot.isGroup
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    clip: true
                                }
                                Text {
                                    property int _cw: root.colLayoutVersion
                                    width: root.colW("mem")
                                    height: parent.height
                                    text: modelData.mem.toFixed(1)
                                    color: root.textColor
                                    font.pixelSize: 10
                                    font.family: "monospace"
                                    font.bold: rowRoot.isGroup
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    clip: true
                                }
                                Text {
                                    property int _cw: root.colLayoutVersion
                                    width: root.colW("time")
                                    height: parent.height
                                    text: rowRoot.isGroup ? "--" : root.formatTime(modelData.time)
                                    color: root.subtextColor
                                    font.pixelSize: 10
                                    font.family: "monospace"
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    clip: true
                                }
                                Text {
                                    property int _cw: root.colLayoutVersion
                                    width: root.colW("start")
                                    height: parent.height
                                    text: rowRoot.isGroup ? "--" : root.formatStart(modelData.start)
                                    color: root.subtextColor
                                    font.pixelSize: 10
                                    font.family: "monospace"
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideRight
                                    clip: true
                                }
                                Text {
                                    property int _cw: root.colLayoutVersion
                                    width: root.colW("threads")
                                    height: parent.height
                                    text: modelData.threads !== undefined ? String(modelData.threads) : "--"
                                    color: root.textColor
                                    font.pixelSize: 10
                                    font.family: "monospace"
                                    font.bold: rowRoot.isGroup
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    clip: true
                                }
                                Text {
                                    property int _cw: root.colLayoutVersion
                                    width: root.colW("rss")
                                    height: parent.height
                                    text: root.formatKiB(modelData.rss)
                                    color: root.textColor
                                    font.pixelSize: 10
                                    font.family: "monospace"
                                    font.bold: rowRoot.isGroup
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    clip: true
                                }
                                Text {
                                    property int _cw: root.colLayoutVersion
                                    width: root.colW("vsz")
                                    height: parent.height
                                    text: root.formatKiB(modelData.vsz)
                                    color: root.textColor
                                    font.pixelSize: 10
                                    font.family: "monospace"
                                    font.bold: rowRoot.isGroup
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    clip: true
                                }
                                Text {
                                    property int _cw: root.colLayoutVersion
                                    width: root.colW("pri")
                                    height: parent.height
                                    text: rowRoot.isGroup ? "--" : (modelData.pri !== undefined ? modelData.pri : "--")
                                    color: root.textColor
                                    font.pixelSize: 10
                                    font.family: "monospace"
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    clip: true
                                }
                                Text {
                                    property int _cw: root.colLayoutVersion
                                    width: root.colW("nice")
                                    height: parent.height
                                    text: rowRoot.isGroup ? "--" : root.formatNice(modelData.nice)
                                    color: root.textColor
                                    font.pixelSize: 10
                                    font.family: "monospace"
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    clip: true
                                }
                                Text {
                                    property int _cw: root.colLayoutVersion
                                    width: root.colW("shr")
                                    height: parent.height
                                    text: root.formatKiB(modelData.shr)
                                    color: root.textColor
                                    font.pixelSize: 10
                                    font.family: "monospace"
                                    font.bold: rowRoot.isGroup
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    clip: true
                                }
                                Item {
                                    width: root.colW("cmd")
                                    height: parent.height
                                    clip: true

                                    Text {
                                        anchors.fill: parent
                                        anchors.leftMargin: rowRoot.isChild ? root.groupIndent : 0
                                        text: root.displayRowCmdText(modelData)
                                        color: rowRoot.isSelected ? root.textColor
                                            : (rowRoot.isGroup ? root.textColor : root.subtextColor)
                                        font.pixelSize: 10
                                        font.family: "monospace"
                                        font.bold: rowRoot.isGroup
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                        clip: true
                                    }
                                }
                                Text {
                                    property int _cw: root.colLayoutVersion
                                    width: root.colW("stat")
                                    height: parent.height
                                    text: rowRoot.isGroup ? "--" : root.formatState(modelData.state)
                                    color: rowRoot.isGroup ? root.overlayColor : root.stateColor(modelData.state)
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.family: "monospace"
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    clip: true
                                }
                            }

                            MouseArea {
                                id: rowMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: function(mouse) {
                                    root.handleDisplayRowClick(modelData, index, mouse)
                                }
                            }
                        }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: 2
            horizontalAlignment: Text.AlignRight
            property int _updatedVer: root.lastUpdatedVersion
            property bool _loading: root.loading
            visible: root.lastUpdatedLabel.length > 0
            text: _loading ? "Refreshing…" : ("Last updated: " + root.lastUpdatedLabel)
            color: root.overlayColor
            font.pixelSize: 10
            font.family: "monospace"
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.killConfirmVisible
        color: Qt.rgba(0, 0, 0, 0.55)
        z: 100

        MouseArea {
            anchors.fill: parent
            onClicked: root.cancelKill()
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, 360)
            height: killConfirmColumn.implicitHeight + 28
            radius: root.cardRadius
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.12)

            MouseArea {
                anchors.fill: parent
            }

            ColumnLayout {
                id: killConfirmColumn
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12

                Text {
                    Layout.fillWidth: true
                    text: "Kill " + root.selectedCount + " processes?"
                    color: root.textColor
                    font.pixelSize: 13
                    font.bold: true
                    font.family: "monospace"
                    wrapMode: Text.Wrap
                }

                Text {
                    Layout.fillWidth: true
                    text: "This sends SIGTERM to each selected process."
                    color: root.subtextColor
                    font.pixelSize: 11
                    font.family: "monospace"
                    wrapMode: Text.Wrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredWidth: 72
                        Layout.preferredHeight: 28
                        radius: 6
                        color: cancelKillMa.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.1)
                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: root.textColor
                            font.pixelSize: 11
                        }
                        MouseArea {
                            id: cancelKillMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.cancelKill()
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 72
                        Layout.preferredHeight: 28
                        radius: 6
                        color: confirmKillMa.containsMouse ? Qt.rgba(0.95, 0.55, 0.66, 0.2) : Qt.rgba(0.95, 0.55, 0.66, 0.12)
                        border.width: 1
                        border.color: root.errorColor
                        Text {
                            anchors.centerIn: parent
                            text: "Kill"
                            color: root.errorColor
                            font.pixelSize: 11
                            font.bold: true
                        }
                        MouseArea {
                            id: confirmKillMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.confirmKill()
                        }
                    }
                }
            }
        }
    }
}