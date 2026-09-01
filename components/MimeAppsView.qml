import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io as Io

// Preferred applications / file-type defaults (control-bar MIME panel).
// Self-contained: loads only while active; no bar-level models or pollers.
Item {
    id: root

    property bool active: false
    property bool showReloadButton: true
    property var keyboardGrab: null

    property color textColor: "#f0f4fc"
    property color subtextColor: "#a8b4c8"
    property color accentColor: "#00F0E0"
    property color surfaceColor: "#141a24"
    property color overlayColor: "#6e7a90"
    property color okColor: "#2ee59a"
    property color warnColor: "#f0d060"
    property color errorColor: "#FF3D8A"
    property color fieldBg: Qt.rgba(0.18, 0.19, 0.23, 0.92)
    property color fieldBgFocus: Qt.rgba(0.22, 0.24, 0.30, 0.95)
    property color pillBorder: Qt.rgba(1, 1, 1, 0.12)
    property string fontFamily: "sans-serif"
    property string fontMono: "monospace"

    function scriptPath(name) {
        const u = Qt.resolvedUrl("../scripts/" + name).toString()
        return u.replace(/^file:\/\//, "")
    }
    readonly property string catalogScript: scriptPath("mime-catalog-json.sh")
    readonly property string appsScript: scriptPath("mime-apps-json.sh")
    readonly property string probeScript: scriptPath("mime-file-probe.sh")
    readonly property string setScript: scriptPath("mime-set-default.sh")
    readonly property string desktopAppsScript: scriptPath("desktop-apps-json.sh")

    // "types" | "apps"
    property string mode: "types"
    // "all" | "files" | "links" | "defaults"
    property string typeFilter: "defaults"

    property var types: []
    property var apps: []
    property string selectedTypeId: ""
    property string selectedAppId: ""
    property string selectedHandlerId: ""

    property string searchText: ""
    property string probePath: ""

    property bool loading: false
    property bool loadingApps: false
    property bool acting: false
    property bool probing: false
    property string lastError: ""
    property string lastStatus: ""
    property int dataVersion: 0
    property int appsVersion: 0

    property bool _catalogHandled: false
    property bool _appsHandled: false
    property bool _actionHandled: false
    property bool _probeHandled: false
    property bool _pickerAppsHandled: false

    // Associate / add picker: "associateApp" | "addTypeToApp" | ""
    property string pickerKind: ""
    property string pickerQuery: ""
    property var pickerApps: []
    property string pickerSelectedId: ""
    property bool pickerLoading: false
    property string _actionKind: ""   // "set" | "unset" | "associate"
    property string _actionAppName: ""
    property string _actionTypeName: ""

    readonly property int rowH: 40
    readonly property int handlerRowH: 28
    readonly property int chipH: 26
    readonly property bool pickerOpen: pickerKind.length > 0

    // ── helpers ──────────────────────────────────────────────

    function filterQuery() {
        return (searchText && searchText.trim()) ? searchText.toLowerCase().trim() : ""
    }

    function tokens() {
        const q = filterQuery()
        if (!q) return []
        return q.split(/\s+/).filter(function(t) { return t.length > 0 })
    }

    function matchesTokens(blob) {
        const toks = tokens()
        if (!toks.length) return true
        const hay = (blob || "").toLowerCase()
        for (let i = 0; i < toks.length; i++) {
            if (hay.indexOf(toks[i]) === -1)
                return false
        }
        return true
    }

    function pickerTokens() {
        const q = (pickerQuery && pickerQuery.trim()) ? pickerQuery.toLowerCase().trim() : ""
        if (!q) return []
        return q.split(/\s+/).filter(function(t) { return t.length > 0 })
    }

    function matchesPickerTokens(blob) {
        const toks = pickerTokens()
        if (!toks.length) return true
        const hay = (blob || "").toLowerCase()
        for (let i = 0; i < toks.length; i++) {
            if (hay.indexOf(toks[i]) === -1)
                return false
        }
        return true
    }

    function globsText(globs) {
        if (!globs || !globs.length) return ""
        const max = Math.min(globs.length, 4)
        let parts = []
        for (let i = 0; i < max; i++)
            parts.push(globs[i])
        let s = parts.join(" ")
        if (globs.length > max)
            s += " +" + (globs.length - max)
        return s
    }

    function selectedType() {
        if (!selectedTypeId) return null
        for (let i = 0; i < types.length; i++) {
            if (types[i].id === selectedTypeId)
                return types[i]
        }
        return null
    }

    function selectedApp() {
        if (!selectedAppId) return null
        for (let i = 0; i < apps.length; i++) {
            if (apps[i].id === selectedAppId)
                return apps[i]
        }
        return null
    }

    function selectedHandler() {
        const t = selectedType()
        if (!t || !selectedHandlerId) return null
        const hs = t.handlers || []
        for (let i = 0; i < hs.length; i++) {
            if (hs[i].id === selectedHandlerId)
                return hs[i]
        }
        return null
    }

    function filteredTypes() {
        void dataVersion
        void searchText
        void typeFilter
        if (!types || !types.length) return []
        const out = []
        for (let i = 0; i < types.length; i++) {
            const t = types[i]
            if (typeFilter === "files" && t.isScheme) continue
            if (typeFilter === "links" && !t.isScheme) continue
            if (typeFilter === "defaults" && !t.defaultIsExplicit) continue
            const blob = [
                t.comment || "", t.id || "", t.defaultName || "", t.defaultId || "",
                (t.globs || []).join(" ")
            ].join(" ")
            if (!matchesTokens(blob)) continue
            out.push(t)
        }
        return out
    }

    function filteredApps() {
        void appsVersion
        void searchText
        if (!apps || !apps.length) return []
        const out = []
        for (let i = 0; i < apps.length; i++) {
            const a = apps[i]
            let mimeBlob = ""
            const ms = a.mimes || []
            for (let j = 0; j < ms.length; j++) {
                mimeBlob += " " + (ms[j].comment || "") + " " + (ms[j].id || "")
                    + " " + (ms[j].globs || []).join(" ")
            }
            const blob = (a.name || "") + " " + (a.id || "") + mimeBlob
            if (!matchesTokens(blob)) continue
            out.push(a)
        }
        return out
    }

    /** Types available to add to the selected app (not already listed for it). */
    function pickerTypeRows() {
        void dataVersion
        void pickerQuery
        void selectedAppId
        const app = selectedApp()
        if (!app) return []
        const have = {}
        const ms = app.mimes || []
        for (let i = 0; i < ms.length; i++)
            have[ms[i].id] = true
        const out = []
        for (let i = 0; i < types.length; i++) {
            const t = types[i]
            if (have[t.id]) continue
            const blob = [t.comment || "", t.id || "", (t.globs || []).join(" ")].join(" ")
            if (!matchesPickerTokens(blob)) continue
            out.push(t)
        }
        // Cap for UI responsiveness
        return out.slice(0, 200)
    }

    function pickerAppRows() {
        void pickerQuery
        const rows = pickerApps || []
        if (!pickerTokens().length) return rows.slice(0, 200)
        const out = []
        for (let i = 0; i < rows.length; i++) {
            const a = rows[i]
            const blob = [a.name || "", a.id || "", a.exec || ""].join(" ")
            if (matchesPickerTokens(blob))
                out.push(a)
            if (out.length >= 200) break
        }
        return out
    }

    function ensureTypeSelection() {
        const rows = filteredTypes()
        if (!rows.length) {
            selectedTypeId = ""
            selectedHandlerId = ""
            return
        }
        if (selectedTypeId) {
            for (let i = 0; i < rows.length; i++) {
                if (rows[i].id === selectedTypeId) {
                    syncHandlerSelection(rows[i])
                    return
                }
            }
        }
        selectedTypeId = rows[0].id
        syncHandlerSelection(rows[0])
    }

    function ensureAppSelection() {
        const rows = filteredApps()
        if (!rows.length) {
            selectedAppId = ""
            return
        }
        if (selectedAppId) {
            for (let i = 0; i < rows.length; i++) {
                if (rows[i].id === selectedAppId)
                    return
            }
        }
        selectedAppId = rows[0].id
    }

    function syncHandlerSelection(t) {
        if (!t) {
            selectedHandlerId = ""
            return
        }
        const hs = t.handlers || []
        if (!hs.length) {
            selectedHandlerId = ""
            return
        }
        if (selectedHandlerId) {
            for (let i = 0; i < hs.length; i++) {
                if (hs[i].id === selectedHandlerId)
                    return
            }
        }
        for (let i = 0; i < hs.length; i++) {
            if (hs[i].isDefault) {
                selectedHandlerId = hs[i].id
                return
            }
        }
        selectedHandlerId = hs[0].id
    }

    function selectType(id) {
        selectedTypeId = id || ""
        syncHandlerSelection(selectedType())
    }

    function selectApp(id) {
        selectedAppId = id || ""
    }

    function typeIndexInFilter() {
        const rows = filteredTypes()
        for (let i = 0; i < rows.length; i++) {
            if (rows[i].id === selectedTypeId)
                return i
        }
        return -1
    }

    function appIndexInFilter() {
        const rows = filteredApps()
        for (let i = 0; i < rows.length; i++) {
            if (rows[i].id === selectedAppId)
                return i
        }
        return -1
    }

    function handlerIndex() {
        const t = selectedType()
        if (!t) return -1
        const hs = t.handlers || []
        for (let i = 0; i < hs.length; i++) {
            if (hs[i].id === selectedHandlerId)
                return i
        }
        return -1
    }

    function moveLeftSelection(delta) {
        if (mode === "types") {
            const rows = filteredTypes()
            if (!rows.length) return
            let idx = typeIndexInFilter()
            if (idx < 0) idx = 0
            else idx = Math.max(0, Math.min(rows.length - 1, idx + delta))
            selectType(rows[idx].id)
            leftList.positionViewAtIndex(idx, ListView.Contain)
        } else {
            const rows = filteredApps()
            if (!rows.length) return
            let idx = appIndexInFilter()
            if (idx < 0) idx = 0
            else idx = Math.max(0, Math.min(rows.length - 1, idx + delta))
            selectApp(rows[idx].id)
            leftList.positionViewAtIndex(idx, ListView.Contain)
        }
    }

    function moveHandlerSelection(delta) {
        const t = selectedType()
        if (!t) return
        const hs = t.handlers || []
        if (!hs.length) return
        let idx = handlerIndex()
        if (idx < 0) idx = 0
        else idx = Math.max(0, Math.min(hs.length - 1, idx + delta))
        selectedHandlerId = hs[idx].id
        handlerList.positionViewAtIndex(idx, ListView.Contain)
    }

    function jumpToType(mimeId) {
        if (!mimeId) return
        mode = "types"
        let found = null
        for (let i = 0; i < types.length; i++) {
            if (types[i].id === mimeId) {
                found = types[i]
                break
            }
        }
        if (found) {
            if (typeFilter === "defaults" && !found.defaultIsExplicit)
                typeFilter = found.isScheme ? "links" : "files"
            else if (typeFilter === "files" && found.isScheme)
                typeFilter = "links"
            else if (typeFilter === "links" && !found.isScheme)
                typeFilter = "files"
        }
        searchText = ""
        selectType(mimeId)
        dataVersion++
        Qt.callLater(function() {
            leftList.forceActiveFocus()
            const idx = root.typeIndexInFilter()
            if (idx >= 0)
                leftList.positionViewAtIndex(idx, ListView.Contain)
        })
    }

    // ── load / actions ───────────────────────────────────────

    function refresh() {
        refreshCatalog()
        if (mode === "apps" || apps.length === 0)
            refreshApps()
    }

    function refreshCatalog() {
        if (catalogProcess.running) return
        loading = true
        lastError = ""
        _catalogHandled = false
        catalogProcess.command = [root.catalogScript]
        catalogProcess.running = false
        catalogProcess.running = true
    }

    function refreshApps() {
        if (appsProcess.running) return
        loadingApps = true
        _appsHandled = false
        appsProcess.command = [root.appsScript]
        appsProcess.running = false
        appsProcess.running = true
    }

    function finishCatalog(code) {
        if (_catalogHandled) return
        _catalogHandled = true
        loading = false
        const raw = (catalogStdout.text || "").trim()
        const errOut = (catalogStderr.text || "").trim()
        if (code !== 0 && !raw) {
            lastError = errOut.length ? errOut : "Could not load file types."
            types = []
            dataVersion++
            return
        }
        if (!raw) {
            lastError = "Empty response while loading file types."
            types = []
            dataVersion++
            return
        }
        try {
            const parsed = JSON.parse(raw)
            types = parsed.types || []
            lastError = ""
            dataVersion++
            ensureTypeSelection()
        } catch (e) {
            lastError = "Could not parse file type list."
            types = []
            dataVersion++
        }
    }

    function finishApps(code) {
        if (_appsHandled) return
        _appsHandled = true
        loadingApps = false
        const raw = (appsStdout.text || "").trim()
        const errOut = (appsStderr.text || "").trim()
        if (code !== 0 && !raw) {
            if (mode === "apps")
                lastError = errOut.length ? errOut : "Could not load applications."
            apps = []
            appsVersion++
            return
        }
        if (!raw) {
            apps = []
            appsVersion++
            return
        }
        try {
            const parsed = JSON.parse(raw)
            apps = parsed.apps || []
            appsVersion++
            ensureAppSelection()
        } catch (e) {
            if (mode === "apps")
                lastError = "Could not parse applications list."
            apps = []
            appsVersion++
        }
    }

    function runProbe() {
        const p = (probePath || "").trim()
        if (!p.length) {
            lastError = "Paste a file path first."
            lastStatus = ""
            return
        }
        if (probeProcess.running) return
        probing = true
        lastError = ""
        lastStatus = "Looking up…"
        _probeHandled = false
        probeProcess.command = [root.probeScript, p]
        probeProcess.running = false
        probeProcess.running = true
    }

    function finishProbe(code) {
        if (_probeHandled) return
        _probeHandled = true
        probing = false
        const raw = (probeStdout.text || "").trim()
        if (!raw) {
            lastStatus = ""
            lastError = "Look up failed."
            return
        }
        try {
            const parsed = JSON.parse(raw)
            if (parsed.error) {
                lastStatus = ""
                lastError = parsed.error
                return
            }
            const mime = parsed.mime || ""
            const comment = parsed.comment || mime
            const defName = parsed.defaultName || ""
            if (defName)
                lastStatus = comment + " · currently opens with " + defName
            else
                lastStatus = comment + " · no default set"
            lastError = ""
            if (mime)
                jumpToType(mime)
        } catch (e) {
            lastStatus = ""
            lastError = "Could not parse look-up result."
        }
    }

    function canSetDefault() {
        const t = selectedType()
        const h = selectedHandler()
        if (!t || !h || acting || loading) return false
        if (t.defaultId && t.defaultId === h.id) return false
        return true
    }

    function canClearDefault() {
        const t = selectedType()
        if (!t || acting || loading) return false
        return !!t.defaultIsExplicit
    }

    function setDefault() {
        const t = selectedType()
        const h = selectedHandler()
        if (!t || !h || acting || setProcess.running) return
        if (t.defaultId === h.id) {
            lastStatus = "Already the default opener"
            return
        }
        runSetAction("set", t.id, h.id, h.name || h.id, t.comment || t.id)
    }

    function clearDefault() {
        const t = selectedType()
        if (!t || !t.defaultIsExplicit || acting || setProcess.running) return
        runSetAction("unset", t.id, "", "", t.comment || t.id)
    }

    function runSetAction(action, mimeId, desktopId, appName, typeName) {
        acting = true
        lastError = ""
        lastStatus = "Saving…"
        _actionHandled = false
        _actionKind = action
        _actionAppName = appName || ""
        _actionTypeName = typeName || ""
        if (action === "unset")
            setProcess.command = [root.setScript, "unset", mimeId]
        else
            setProcess.command = [root.setScript, "set", mimeId, desktopId]
        setProcess.running = false
        setProcess.running = true
    }

    function finishAction(code) {
        if (_actionHandled) return
        _actionHandled = true
        acting = false
        const raw = (setStdout.text || "").trim()
        const errOut = (setStderr.text || "").trim()
        let parsed = null
        try {
            parsed = JSON.parse(raw.length ? raw : errOut)
        } catch (e) {
            parsed = null
        }
        if (code !== 0 || (parsed && parsed.ok === false)) {
            lastStatus = ""
            if (parsed && parsed.error)
                lastError = parsed.error
            else
                lastError = errOut.length ? errOut : "Could not update association."
            return
        }
        if (parsed && parsed.action === "unset") {
            lastStatus = "Cleared default opener" + (_actionTypeName ? (" for " + _actionTypeName) : "")
        } else {
            const appName = _actionAppName || (parsed && parsed.desktopId) || "app"
            const typeName = _actionTypeName || "file type"
            lastStatus = appName + " will now open " + typeName
        }
        lastError = ""
        closePicker()
        const keepType = selectedTypeId
        const keepApp = selectedAppId
        const keepHandler = selectedHandlerId || (parsed && parsed.desktopId) || ""
        Qt.callLater(function() {
            root._pendingTypeId = keepType
            root._pendingAppId = keepApp
            root._pendingHandlerId = keepHandler
            root.refreshCatalog()
            root.refreshApps()
        })
    }

    property string _pendingTypeId: ""
    property string _pendingAppId: ""
    property string _pendingHandlerId: ""

    onDataVersionChanged: {
        if (_pendingTypeId) {
            selectedTypeId = _pendingTypeId
            selectedHandlerId = _pendingHandlerId
            _pendingTypeId = ""
            _pendingHandlerId = ""
            syncHandlerSelection(selectedType())
        }
    }
    onAppsVersionChanged: {
        if (_pendingAppId) {
            selectedAppId = _pendingAppId
            _pendingAppId = ""
        }
    }

    // ── picker ───────────────────────────────────────────────

    function openAssociateAppPicker() {
        const t = selectedType()
        if (!t) return
        pickerKind = "associateApp"
        pickerQuery = ""
        pickerSelectedId = ""
        pickerApps = []
        loadPickerApps()
    }

    function openAddTypePicker() {
        const a = selectedApp()
        if (!a) return
        if (!types.length)
            refreshCatalog()
        pickerKind = "addTypeToApp"
        pickerQuery = ""
        pickerSelectedId = ""
    }

    function closePicker() {
        pickerKind = ""
        pickerQuery = ""
        pickerSelectedId = ""
        pickerLoading = false
        if (pickerAppsProcess.running)
            pickerAppsProcess.running = false
    }

    function loadPickerApps() {
        if (pickerAppsProcess.running) return
        pickerLoading = true
        _pickerAppsHandled = false
        // No query arg → full ranked list (script caps at 250)
        pickerAppsProcess.command = [root.desktopAppsScript]
        pickerAppsProcess.running = false
        pickerAppsProcess.running = true
    }

    function finishPickerApps(code) {
        if (_pickerAppsHandled) return
        _pickerAppsHandled = true
        pickerLoading = false
        const raw = (pickerAppsStdout.text || "").trim()
        if (!raw || code !== 0) {
            pickerApps = []
            if (pickerKind === "associateApp")
                lastError = "Could not load applications list."
            return
        }
        try {
            const parsed = JSON.parse(raw)
            pickerApps = Array.isArray(parsed) ? parsed : []
            if (pickerApps.length && !pickerSelectedId)
                pickerSelectedId = pickerApps[0].id || ""
        } catch (e) {
            pickerApps = []
            lastError = "Could not parse applications list."
        }
    }

    function confirmPicker() {
        if (acting || setProcess.running) return
        if (pickerKind === "associateApp") {
            const t = selectedType()
            if (!t || !pickerSelectedId) return
            let name = pickerSelectedId
            const rows = pickerAppRows()
            for (let i = 0; i < rows.length; i++) {
                if (rows[i].id === pickerSelectedId) {
                    name = rows[i].name || name
                    break
                }
            }
            // Also try full list
            for (let i = 0; i < pickerApps.length; i++) {
                if (pickerApps[i].id === pickerSelectedId) {
                    name = pickerApps[i].name || name
                    break
                }
            }
            selectedHandlerId = pickerSelectedId
            runSetAction("associate", t.id, pickerSelectedId, name, t.comment || t.id)
            return
        }
        if (pickerKind === "addTypeToApp") {
            const a = selectedApp()
            if (!a || !pickerSelectedId) return
            let typeName = pickerSelectedId
            const rows = pickerTypeRows()
            for (let i = 0; i < rows.length; i++) {
                if (rows[i].id === pickerSelectedId) {
                    typeName = rows[i].comment || typeName
                    break
                }
            }
            selectedTypeId = pickerSelectedId
            runSetAction("associate", pickerSelectedId, a.id, a.name || a.id, typeName)
        }
    }

    function movePickerSelection(delta) {
        const rows = pickerKind === "associateApp" ? pickerAppRows() : pickerTypeRows()
        if (!rows.length) return
        let idx = 0
        for (let i = 0; i < rows.length; i++) {
            if (rows[i].id === pickerSelectedId) {
                idx = i
                break
            }
        }
        idx = Math.max(0, Math.min(rows.length - 1, idx + delta))
        pickerSelectedId = rows[idx].id
        pickerList.positionViewAtIndex(idx, ListView.Contain)
    }

    onModeChanged: {
        lastError = ""
        closePicker()
        if (mode === "apps" && !apps.length && !loadingApps)
            refreshApps()
        else if (mode === "apps")
            ensureAppSelection()
        else
            ensureTypeSelection()
        Qt.callLater(function() { leftList.forceActiveFocus() })
    }

    onTypeFilterChanged: ensureTypeSelection()
    onSearchTextChanged: {
        if (mode === "types")
            ensureTypeSelection()
        else
            ensureAppSelection()
    }

    onActiveChanged: {
        if (active) {
            refresh()
            Qt.callLater(function() { leftList.forceActiveFocus() })
        } else {
            closePicker()
            if (catalogProcess.running)
                catalogProcess.running = false
            if (appsProcess.running)
                appsProcess.running = false
            if (probeProcess.running)
                probeProcess.running = false
            if (setProcess.running)
                setProcess.running = false
            if (pickerAppsProcess.running)
                pickerAppsProcess.running = false
            loading = false
            loadingApps = false
            probing = false
            acting = false
            if (lastStatus === "Looking up…" || lastStatus === "Saving…")
                lastStatus = ""
        }
    }

    Io.Process {
        id: catalogProcess
        running: false
        stdout: Io.StdioCollector { id: catalogStdout }
        stderr: Io.StdioCollector { id: catalogStderr }
        onExited: (code) => root.finishCatalog(code)
    }
    Io.Process {
        id: appsProcess
        running: false
        stdout: Io.StdioCollector { id: appsStdout }
        stderr: Io.StdioCollector { id: appsStderr }
        onExited: (code) => root.finishApps(code)
    }
    Io.Process {
        id: probeProcess
        running: false
        stdout: Io.StdioCollector { id: probeStdout }
        stderr: Io.StdioCollector { id: probeStderr }
        onExited: (code) => root.finishProbe(code)
    }
    Io.Process {
        id: setProcess
        running: false
        stdout: Io.StdioCollector { id: setStdout }
        stderr: Io.StdioCollector { id: setStderr }
        onExited: (code) => root.finishAction(code)
    }
    Io.Process {
        id: pickerAppsProcess
        running: false
        stdout: Io.StdioCollector { id: pickerAppsStdout }
        stderr: Io.StdioCollector { id: pickerAppsStderr }
        onExited: (code) => root.finishPickerApps(code)
    }

    // ── UI ───────────────────────────────────────────────────

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        // Mode toggle
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: [
                    { id: "types", label: "File types" },
                    { id: "apps", label: "Applications" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool on: root.mode === modelData.id
                    Layout.preferredHeight: root.chipH
                    Layout.preferredWidth: modeLbl.implicitWidth + 16
                    radius: 6
                    color: on ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                              : (modeMa.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
                    border.width: 1
                    border.color: on ? root.accentColor : root.pillBorder
                    Text {
                        id: modeLbl
                        anchors.centerIn: parent
                        text: modelData.label
                        color: on ? root.accentColor : root.subtextColor
                        font.pixelSize: 11
                        font.bold: on
                        font.family: root.fontFamily
                    }
                    MouseArea {
                        id: modeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.mode = modelData.id
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Text {
                text: {
                    if (root.loading || (root.mode === "apps" && root.loadingApps))
                        return root.mode === "apps" ? "Loading applications…" : "Loading file types…"
                    if (root.mode === "types")
                        return root.filteredTypes().length + " types"
                    return root.filteredApps().length + " apps"
                }
                color: root.subtextColor
                font.pixelSize: 11
                font.family: root.fontFamily
            }

            Rectangle {
                visible: root.showReloadButton
                Layout.preferredHeight: root.chipH
                Layout.preferredWidth: reloadLbl.implicitWidth + 14
                radius: 6
                color: reloadMa.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : root.surfaceColor
                border.width: 1
                border.color: root.pillBorder
                enabled: !root.loading && !root.acting
                opacity: enabled ? 1 : 0.5
                Text {
                    id: reloadLbl
                    anchors.centerIn: parent
                    text: "Reload"
                    color: root.subtextColor
                    font.pixelSize: 11
                    font.family: root.fontFamily
                }
                MouseArea {
                    id: reloadMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.refresh()
                }
            }
        }

        // What opens this file? (types mode)
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: root.mode === "types" && !root.pickerOpen

            Text {
                text: "What opens this file?"
                color: root.subtextColor
                font.pixelSize: 11
                font.family: root.fontFamily
            }
            TextField {
                id: probeField
                Layout.fillWidth: true
                Layout.preferredHeight: 28
                placeholderText: "Paste a file path…"
                color: root.textColor
                placeholderTextColor: root.overlayColor
                font.pixelSize: 12
                font.family: root.fontMono
                text: root.probePath
                background: Rectangle {
                    radius: 6
                    color: parent.activeFocus ? root.fieldBgFocus : root.fieldBg
                    border.width: 1
                    border.color: parent.activeFocus ? root.accentColor : root.pillBorder
                }
                onTextChanged: root.probePath = text
                Keys.onReturnPressed: root.runProbe()
                Keys.onEnterPressed: root.runProbe()
                Keys.onDownPressed: leftList.forceActiveFocus()
            }
            Rectangle {
                Layout.preferredHeight: 28
                Layout.preferredWidth: lookLbl.implicitWidth + 16
                radius: 6
                color: lookMa.containsMouse
                       ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.28)
                       : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                border.width: 1
                border.color: root.accentColor
                enabled: !root.probing && !root.acting
                opacity: enabled ? 1 : 0.55
                Text {
                    id: lookLbl
                    anchors.centerIn: parent
                    text: root.probing ? "…" : "Look up"
                    color: root.accentColor
                    font.pixelSize: 11
                    font.bold: true
                    font.family: root.fontFamily
                }
                MouseArea {
                    id: lookMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runProbe()
                }
            }
        }

        // Search (main list)
        TextField {
            id: searchField
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            visible: !root.pickerOpen
            placeholderText: root.mode === "types"
                ? "Search by name, extension, or app…  (↑↓ navigate)"
                : "Search applications or file types…"
            color: root.textColor
            placeholderTextColor: root.overlayColor
            font.pixelSize: 12
            font.family: root.fontFamily
            text: root.searchText
            background: Rectangle {
                radius: 6
                color: parent.activeFocus ? root.fieldBgFocus : root.fieldBg
                border.width: 1
                border.color: parent.activeFocus ? root.accentColor : root.pillBorder
            }
            onPressed: if (typeof root.keyboardGrab === "function") root.keyboardGrab()
            onActiveFocusChanged: if (activeFocus && typeof root.keyboardGrab === "function") root.keyboardGrab()
            onTextChanged: root.searchText = text
            Keys.onDownPressed: leftList.forceActiveFocus()
            Keys.onReturnPressed: leftList.forceActiveFocus()
        }

        // Filter chips (types mode)
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: root.mode === "types" && !root.pickerOpen

            Repeater {
                model: [
                    { id: "all", label: "All" },
                    { id: "files", label: "Files" },
                    { id: "links", label: "Links" },
                    { id: "defaults", label: "Has default" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool on: root.typeFilter === modelData.id
                    Layout.preferredHeight: 22
                    Layout.preferredWidth: chipLbl.implicitWidth + 12
                    radius: 5
                    color: on ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                              : (chipMa.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
                    border.width: 1
                    border.color: on ? root.accentColor : root.pillBorder
                    Text {
                        id: chipLbl
                        anchors.centerIn: parent
                        text: modelData.label
                        color: on ? root.accentColor : root.overlayColor
                        font.pixelSize: 10
                        font.family: root.fontFamily
                    }
                    MouseArea {
                        id: chipMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.typeFilter = modelData.id
                    }
                }
            }
            Item { Layout.fillWidth: true }
            Text {
                text: "↑↓ list  ·  → apps  ·  Enter set default"
                color: root.subtextColor
                font.pixelSize: 9
                font.family: root.fontFamily
                visible: root.mode === "types"
            }
        }

        // Main body: always fills remaining height so dual panes reach the panel bottom
        Item {
            id: mainBody
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 140
            // preferredHeight 0 + fillHeight → stretch in ColumnLayout (not hug list content)
            Layout.preferredHeight: 0

            // Dual pane
            RowLayout {
                anchors.fill: parent
                spacing: 8
                visible: !root.pickerOpen

            // ── Left list ──
            Rectangle {
                Layout.preferredWidth: Math.max(200, Math.floor(mainBody.width * 0.42))
                Layout.fillWidth: false
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                Layout.preferredHeight: 0
                radius: 8
                color: root.surfaceColor
                border.width: 1
                border.color: leftList.activeFocus ? root.accentColor : root.pillBorder
                clip: true

                ListView {
                    id: leftList
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    focus: true
                    activeFocusOnTab: true
                    keyNavigationEnabled: false
                    // Never size the pane from content — parent Rectangle height is authoritative
                    interactive: true
                    model: root.mode === "types" ? root.filteredTypes() : root.filteredApps()

                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
                            root.moveLeftSelection(-1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
                            root.moveLeftSelection(1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_PageUp) {
                            root.moveLeftSelection(-8)
                            event.accepted = true
                        } else if (event.key === Qt.Key_PageDown) {
                            root.moveLeftSelection(8)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Home) {
                            const rows = root.mode === "types" ? root.filteredTypes() : root.filteredApps()
                            if (rows.length) {
                                if (root.mode === "types") root.selectType(rows[0].id)
                                else root.selectApp(rows[0].id)
                                leftList.positionViewAtBeginning()
                            }
                            event.accepted = true
                        } else if (event.key === Qt.Key_End) {
                            const rows = root.mode === "types" ? root.filteredTypes() : root.filteredApps()
                            if (rows.length) {
                                if (root.mode === "types") root.selectType(rows[rows.length - 1].id)
                                else root.selectApp(rows[rows.length - 1].id)
                                leftList.positionViewAtEnd()
                            }
                            event.accepted = true
                        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (root.mode === "types") {
                                const st = root.selectedType()
                                const hs = st ? (st.handlers || []) : []
                                if (hs.length)
                                    handlerList.forceActiveFocus()
                                else
                                    root.openAssociateAppPicker()
                            }
                            event.accepted = true
                        } else if (event.key === Qt.Key_A && root.mode === "types") {
                            root.openAssociateAppPicker()
                            event.accepted = true
                        }
                    }

                    delegate: Rectangle {
                        id: leftRow
                        required property var modelData
                        required property int index
                        width: leftList.width
                        height: root.rowH
                        radius: 6
                        readonly property bool selected: root.mode === "types"
                            ? (modelData.id === root.selectedTypeId)
                            : (modelData.id === root.selectedAppId)
                        color: selected
                               ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                               : (leftMa.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent")

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            anchors.topMargin: 4
                            anchors.bottomMargin: 4
                            spacing: 1

                            Text {
                                Layout.fillWidth: true
                                text: root.mode === "types"
                                      ? (modelData.comment || modelData.id)
                                      : (modelData.name || modelData.id)
                                color: root.textColor
                                font.pixelSize: 12
                                font.bold: leftRow.selected
                                font.family: root.fontFamily
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: {
                                    if (root.mode === "types") {
                                        const g = root.globsText(modelData.globs)
                                        const def = modelData.defaultName || ""
                                        if (g && def) return g + " · " + def
                                        if (g) return g
                                        if (def) return def
                                        return modelData.id || ""
                                    }
                                    const owned = modelData.ownedCount || 0
                                    const total = modelData.mimeCount || 0
                                    if (owned > 0)
                                        return "Default opener for " + owned + " · " + total + " listed"
                                    return total + " file types listed"
                                }
                                color: root.subtextColor
                                font.pixelSize: 10
                                font.family: root.fontFamily
                                elide: Text.ElideRight
                            }
                        }
                        MouseArea {
                            id: leftMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.mode === "types")
                                    root.selectType(modelData.id)
                                else
                                    root.selectApp(modelData.id)
                                leftList.forceActiveFocus()
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: leftList.count === 0 && !root.loading && !(root.mode === "apps" && root.loadingApps)
                        width: parent.width - 24
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: root.lastError.length
                              ? ""
                              : (root.filterQuery().length
                                 ? "No matches. Try an extension like pdf or png."
                                 : (root.mode === "types"
                                    ? (root.typeFilter === "defaults"
                                       ? "No defaults set yet. Try All or Files."
                                       : "No file types found.")
                                    : "No applications with file types found."))
                        color: root.subtextColor
                        font.pixelSize: 11
                        font.family: root.fontFamily
                    }
                }
            }

            // ── Right detail ──
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                Layout.preferredHeight: 0
                radius: 8
                color: root.surfaceColor
                border.width: 1
                border.color: (handlerList.activeFocus && root.mode === "types")
                              ? root.accentColor : root.pillBorder
                clip: true

                // Types detail
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6
                    visible: root.mode === "types"

                    readonly property var t: root.selectedType()

                    Text {
                        Layout.fillWidth: true
                        text: parent.t ? (parent.t.comment || parent.t.id) : "Select a file type"
                        color: root.textColor
                        font.pixelSize: 14
                        font.bold: true
                        font.family: root.fontFamily
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !!parent.t
                        text: {
                            const t = parent.t
                            if (!t) return ""
                            const g = root.globsText(t.globs)
                            if (g)
                                return t.id + "  ·  Extensions: " + g
                            return t.id
                        }
                        color: root.subtextColor
                        font.pixelSize: 10
                        font.family: root.fontMono
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: !!parent.t
                        wrapMode: Text.WordWrap
                        text: {
                            const t = parent.t
                            if (!t) return ""
                            if (t.defaultIsExplicit)
                                return "Which app opens this?  ★ = current default opener"
                            if (t.defaultName && t.defaultName.length)
                                return "Which app opens this?  ★ = suggested opener (not saved as your default)"
                            return "Which app opens this?  No opener set yet — associate an app below."
                        }
                        color: root.subtextColor
                        font.pixelSize: 11
                        font.bold: true
                        font.family: root.fontFamily
                        topPadding: 4
                    }

                    ListView {
                        id: handlerList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: 0
                        Layout.minimumHeight: 0
                        clip: true
                        spacing: 2
                        visible: !!parent.t
                        focus: true
                        activeFocusOnTab: true
                        keyNavigationEnabled: false
                        model: parent.t ? (parent.t.handlers || []) : []

                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
                                root.moveHandlerSelection(-1)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
                                root.moveHandlerSelection(1)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Escape) {
                                leftList.forceActiveFocus()
                                event.accepted = true
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                root.setDefault()
                                event.accepted = true
                            } else if (event.key === Qt.Key_A) {
                                root.openAssociateAppPicker()
                                event.accepted = true
                            }
                        }

                        delegate: Rectangle {
                            id: hRow
                            required property var modelData
                            width: handlerList.width
                            height: root.handlerRowH
                            radius: 5
                            readonly property bool selected: modelData.id === root.selectedHandlerId
                            color: selected
                                   ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14)
                                   : (hMa.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent")

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                spacing: 6
                                Text {
                                    text: modelData.isDefault ? "★" : " "
                                    color: root.accentColor
                                    font.pixelSize: 12
                                    Layout.preferredWidth: 14
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name || modelData.id
                                    color: root.textColor
                                    font.pixelSize: 12
                                    font.family: root.fontFamily
                                    elide: Text.ElideRight
                                }
                                Text {
                                    visible: modelData.isDefault
                                    text: "Default opener"
                                    color: root.accentColor
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.family: root.fontFamily
                                }
                            }
                            MouseArea {
                                id: hMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.selectedHandlerId = modelData.id
                                    handlerList.forceActiveFocus()
                                }
                                onDoubleClicked: {
                                    root.selectedHandlerId = modelData.id
                                    root.setDefault()
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: handlerList.count === 0 && !!parent.parent.t
                            width: parent.width - 20
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: "No apps listed yet.\nClick “Associate app…” to pick one\n(e.g. VSCodium for Markdown)."
                            color: root.subtextColor
                            font.pixelSize: 11
                            font.family: root.fontFamily
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: !!parent.t

                        Rectangle {
                            Layout.preferredHeight: 28
                            Layout.preferredWidth: assocLbl.implicitWidth + 16
                            radius: 6
                            color: assocMa.containsMouse
                                   ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.28)
                                   : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                            border.width: 1
                            border.color: root.accentColor
                            enabled: !root.acting
                            opacity: enabled ? 1 : 0.55
                            Text {
                                id: assocLbl
                                anchors.centerIn: parent
                                text: "Associate app…"
                                color: root.accentColor
                                font.pixelSize: 11
                                font.bold: true
                                font.family: root.fontFamily
                            }
                            MouseArea {
                                id: assocMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openAssociateAppPicker()
                                ToolTip.visible: containsMouse
                                ToolTip.delay: 400
                                ToolTip.text: "Pick any installed app and make it the default opener for this file type."
                            }
                        }

                        Rectangle {
                            Layout.preferredHeight: 28
                            Layout.preferredWidth: setLbl.implicitWidth + 18
                            radius: 6
                            readonly property bool ready: root.canSetDefault()
                            color: ready
                                   ? (setMa.containsMouse
                                      ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                                      : Qt.rgba(1, 1, 1, 0.06))
                                   : Qt.rgba(1, 1, 1, 0.03)
                            border.width: 1
                            border.color: ready ? root.pillBorder : root.pillBorder
                            opacity: root.acting ? 0.55 : 1
                            Text {
                                id: setLbl
                                anchors.centerIn: parent
                                text: {
                                    if (root.acting) return "Saving…"
                                    const t = root.selectedType()
                                    const h = root.selectedHandler()
                                    if (t && h && t.defaultId === h.id)
                                        return "Already default"
                                    return "Use as default"
                                }
                                color: parent.ready ? root.textColor : root.overlayColor
                                font.pixelSize: 11
                                font.bold: parent.ready
                                font.family: root.fontFamily
                            }
                            MouseArea {
                                id: setMa
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: root.canSetDefault()
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: root.setDefault()
                                ToolTip.visible: containsMouse && enabled
                                ToolTip.delay: 400
                                ToolTip.text: "Make the selected app open this file type."
                            }
                        }

                        Rectangle {
                            Layout.preferredHeight: 28
                            Layout.preferredWidth: clearLbl.implicitWidth + 16
                            radius: 6
                            readonly property bool ready: root.canClearDefault()
                            color: clearMa.containsMouse && ready
                                   ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                            border.width: 1
                            border.color: root.pillBorder
                            opacity: ready ? 1 : 0.4
                            Text {
                                id: clearLbl
                                anchors.centerIn: parent
                                text: "Clear default"
                                color: root.subtextColor
                                font.pixelSize: 11
                                font.family: root.fontFamily
                            }
                            MouseArea {
                                id: clearMa
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: root.canClearDefault()
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: root.clearDefault()
                                ToolTip.visible: containsMouse
                                ToolTip.delay: 400
                                ToolTip.text: "Remove your saved default. The system may pick another app."
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }
                }

                // Apps detail
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6
                    visible: root.mode === "apps"

                    readonly property var a: root.selectedApp()

                    Text {
                        Layout.fillWidth: true
                        text: parent.a ? (parent.a.name || parent.a.id) : "Select an application"
                        color: root.textColor
                        font.pixelSize: 14
                        font.bold: true
                        font.family: root.fontFamily
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !!parent.a
                        wrapMode: Text.WordWrap
                        text: {
                            const a = parent.a
                            if (!a) return ""
                            return "File types linked to this app. ★ = this app is the default opener for that type (double-click that kind of file and this app runs). Rows without ★ are types the app can open, but another program is currently the default."
                        }
                        color: root.subtextColor
                        font.pixelSize: 10
                        font.family: root.fontFamily
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: !!parent.a
                        spacing: 8
                        Text {
                            Layout.fillWidth: true
                            text: "Linked file types"
                            color: root.subtextColor
                            font.pixelSize: 11
                            font.bold: true
                            font.family: root.fontFamily
                        }
                        Rectangle {
                            Layout.preferredHeight: 24
                            Layout.preferredWidth: addTypeLbl.implicitWidth + 14
                            radius: 6
                            color: addTypeMa.containsMouse
                                   ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.28)
                                   : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                            border.width: 1
                            border.color: root.accentColor
                            enabled: !root.acting
                            opacity: enabled ? 1 : 0.55
                            Text {
                                id: addTypeLbl
                                anchors.centerIn: parent
                                text: "+ Add type"
                                color: root.accentColor
                                font.pixelSize: 11
                                font.bold: true
                                font.family: root.fontFamily
                            }
                            MouseArea {
                                id: addTypeMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openAddTypePicker()
                                ToolTip.visible: containsMouse
                                ToolTip.delay: 400
                                ToolTip.text: "Link another file type to this app and make it the default opener."
                            }
                        }
                    }

                    ListView {
                        id: appMimeList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: 0
                        Layout.minimumHeight: 0
                        clip: true
                        spacing: 2
                        visible: !!parent.a
                        model: parent.a ? (parent.a.mimes || []) : []

                        delegate: Rectangle {
                            id: amRow
                            required property var modelData
                            width: appMimeList.width
                            height: root.handlerRowH + 8
                            radius: 5
                            color: amMa.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                spacing: 6
                                Text {
                                    text: modelData.isDefault ? "★" : " "
                                    color: root.accentColor
                                    font.pixelSize: 12
                                    Layout.preferredWidth: 14
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.comment || modelData.id
                                        color: root.textColor
                                        font.pixelSize: 12
                                        font.family: root.fontFamily
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: {
                                            const g = root.globsText(modelData.globs)
                                            let s = g ? (modelData.id + " · " + g) : modelData.id
                                            if (modelData.userAdded)
                                                s += " · added by you"
                                            return s
                                        }
                                        color: root.subtextColor
                                        font.pixelSize: 9
                                        font.family: root.fontMono
                                        elide: Text.ElideRight
                                    }
                                }
                                Text {
                                    visible: modelData.isDefault
                                    text: "Default opener"
                                    color: root.accentColor
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.family: root.fontFamily
                                }
                            }
                            MouseArea {
                                id: amMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.jumpToType(modelData.id)
                                ToolTip.visible: containsMouse
                                ToolTip.delay: 400
                                ToolTip.text: modelData.isDefault
                                    ? "This app opens this type by default. Click to manage."
                                    : "This app can open this type, but isn’t the default. Click to change."
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: appMimeList.count === 0 && !!parent.parent.a
                            width: parent.width - 20
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: "No file types linked yet.\nUse “+ Add type” to associate one."
                            color: root.subtextColor
                            font.pixelSize: 11
                            font.family: root.fontFamily
                        }
                    }
                }
            }
        }

            // ── Picker overlay (associate app / add type) — same mainBody slot ──
            Rectangle {
                anchors.fill: parent
                visible: root.pickerOpen
                radius: 8
                color: root.surfaceColor
                border.width: 1
                border.color: root.accentColor
                clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: {
                            if (root.pickerKind === "associateApp") {
                                const t = root.selectedType()
                                const name = t ? (t.comment || t.id) : "this file type"
                                return "Associate an app with “" + name + "” — it becomes the default opener."
                            }
                            if (root.pickerKind === "addTypeToApp") {
                                const a = root.selectedApp()
                                const name = a ? (a.name || a.id) : "this app"
                                return "Add a file type for “" + name + "” — it becomes the default opener for that type."
                            }
                            return ""
                        }
                        color: root.textColor
                        font.pixelSize: 12
                        font.bold: true
                        font.family: root.fontFamily
                    }
                    Rectangle {
                        Layout.preferredHeight: 26
                        Layout.preferredWidth: cancelLbl.implicitWidth + 14
                        radius: 6
                        color: cancelMa.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                        border.width: 1
                        border.color: root.pillBorder
                        Text {
                            id: cancelLbl
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: root.subtextColor
                            font.pixelSize: 11
                            font.family: root.fontFamily
                        }
                        MouseArea {
                            id: cancelMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.closePicker()
                        }
                    }
                }

                TextField {
                    id: pickerSearch
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    placeholderText: root.pickerKind === "associateApp"
                        ? "Search installed apps… (e.g. codium)"
                        : "Search file types… (e.g. markdown or md)"
                    color: root.textColor
                    placeholderTextColor: root.overlayColor
                    font.pixelSize: 12
                    font.family: root.fontFamily
                    text: root.pickerQuery
                    background: Rectangle {
                        radius: 6
                        color: parent.activeFocus ? root.fieldBgFocus : root.fieldBg
                        border.width: 1
                        border.color: parent.activeFocus ? root.accentColor : root.pillBorder
                    }
                    onTextChanged: root.pickerQuery = text
                    Keys.onDownPressed: pickerList.forceActiveFocus()
                    Keys.onReturnPressed: root.confirmPicker()
                    Keys.onEscapePressed: root.closePicker()
                    Component.onCompleted: forceActiveFocus()
                }

                ListView {
                    id: pickerList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: 0
                    Layout.minimumHeight: 0
                    clip: true
                    spacing: 2
                    focus: true
                    model: root.pickerKind === "associateApp" ? root.pickerAppRows() : root.pickerTypeRows()

                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Up) {
                            root.movePickerSelection(-1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Down) {
                            root.movePickerSelection(1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.confirmPicker()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Escape) {
                            root.closePicker()
                            event.accepted = true
                        }
                    }

                    delegate: Rectangle {
                        required property var modelData
                        width: pickerList.width
                        height: 32
                        radius: 5
                        readonly property bool selected: modelData.id === root.pickerSelectedId
                        color: selected
                               ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                               : (pMa.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent")

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8
                            Text {
                                Layout.fillWidth: true
                                text: root.pickerKind === "associateApp"
                                      ? (modelData.name || modelData.id)
                                      : (modelData.comment || modelData.id)
                                color: root.textColor
                                font.pixelSize: 12
                                font.family: root.fontFamily
                                elide: Text.ElideRight
                            }
                            Text {
                                text: root.pickerKind === "associateApp"
                                      ? (modelData.id || "")
                                      : root.globsText(modelData.globs) || (modelData.id || "")
                                color: root.subtextColor
                                font.pixelSize: 10
                                font.family: root.fontMono
                                elide: Text.ElideRight
                                Layout.maximumWidth: parent.width * 0.45
                            }
                        }
                        MouseArea {
                            id: pMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.pickerSelectedId = modelData.id
                            onDoubleClicked: {
                                root.pickerSelectedId = modelData.id
                                root.confirmPicker()
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: pickerList.count === 0 && !root.pickerLoading
                        text: root.pickerLoading ? "" : "No matches."
                        color: root.subtextColor
                        font.pixelSize: 11
                        font.family: root.fontFamily
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: root.pickerLoading
                        text: "Loading apps…"
                        color: root.subtextColor
                        font.pixelSize: 11
                        font.family: root.fontFamily
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        Layout.fillWidth: true
                        text: "↑↓ select · Enter confirm · Esc cancel"
                        color: root.subtextColor
                        font.pixelSize: 10
                        font.family: root.fontFamily
                    }
                    Rectangle {
                        Layout.preferredHeight: 28
                        Layout.preferredWidth: confLbl.implicitWidth + 18
                        radius: 6
                        readonly property bool ready: root.pickerSelectedId.length > 0 && !root.acting && !root.pickerLoading
                        color: ready
                               ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                               : Qt.rgba(1, 1, 1, 0.04)
                        border.width: 1
                        border.color: ready ? root.accentColor : root.pillBorder
                        Text {
                            id: confLbl
                            anchors.centerIn: parent
                            text: root.acting ? "Saving…" : "Associate"
                            color: parent.ready ? root.accentColor : root.overlayColor
                            font.pixelSize: 11
                            font.bold: parent.ready
                            font.family: root.fontFamily
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: parent.ready
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.confirmPicker()
                        }
                    }
                }
            } // picker ColumnLayout
            } // picker Rectangle
        } // mainBody

        // Status line
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: (root.lastError.length > 0 || root.lastStatus.length > 0) ? 18 : 0
            spacing: 8
            visible: root.lastError.length > 0 || root.lastStatus.length > 0
            Text {
                Layout.fillWidth: true
                visible: root.lastError.length > 0
                text: root.lastError
                color: root.errorColor
                font.pixelSize: 11
                font.family: root.fontFamily
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: root.lastError.length === 0 && root.lastStatus.length > 0
                text: root.lastStatus
                color: root.okColor
                font.pixelSize: 11
                font.family: root.fontFamily
                elide: Text.ElideRight
            }
        }
    }

    // Keep picker search focused when opened
    onPickerKindChanged: {
        if (pickerKind.length)
            Qt.callLater(function() { pickerSearch.forceActiveFocus() })
        else
            Qt.callLater(function() { leftList.forceActiveFocus() })
    }
}
