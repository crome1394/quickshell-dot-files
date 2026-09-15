import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io as Io
import ".."

// =============================================================================
// FreshRssPill.qml — FreshRSS reader (bar pill + FloatingWindow)
// =============================================================================
//
// Data: scripts/freshrss-api.sh
//   - Google Reader per-feed streams (All/Read) — parallel, auth-cached
//   - Fever unread/starred id lists
//   - Anonymous public RSS fallback without API password
//
// Perf notes:
//   - Categories start collapsed → ListView only paints ~N feed headers
//   - listRows skips date/item expansion for collapsed feeds
//   - Search scans metadata/summary only (not full HTML)
//   - API trims HTML/text before JSON hits QML
//
// IPC (shell.qml):
//   qs ipc call freshRss toggle | refresh | show | hide
//
// =============================================================================

Rectangle {
    id: root

    required property var bar

    Config { id: th }

    readonly property string apiScript: Qt.resolvedUrl("../scripts/freshrss-api.sh").toString().replace("file://", "")

    property string mode: "rss"       // rss | fever
    property bool writable: false
    property bool loading: false
    property string statusMsg: ""
    property string errorMsg: ""
    property var items: []
    property int selectedIndex: -1
    // Keyboard list cursor (index into listRows: headers, dates, and items)
    property int listCursor: 0
    property string listCursorId: ""
    // note: unreadCount / loadedCount declared with filter defaults below
    property string filterMode: "all" // all | video  (content type)
    // Defaults: All (read + unread) with all dates, categories start collapsed.
    // "Today" is available as a date chip when you want a tighter view.
    property string readScope: "all"  // unread | all | read | saved
    property string dateFilter: "all" // all | today | week
    property string searchQuery: ""

    // Filters panel (search / max days / per feed) — default from Config / bar Options
    property bool filtersExpanded: (bar.freshRssFiltersExpanded !== undefined)
                                   ? !!bar.freshRssFiltersExpanded
                                   : (th.freshRssFiltersExpandedDefault !== undefined
                                      ? !!th.freshRssFiltersExpandedDefault
                                      : true)

    // How many articles to pull (adjustable in the window UI)
    // - maxDays: primary history window (default 30). When > 0, overrides per-feed/item caps.
    // - perFeedLimit: All/Read when maxDays === 0
    // - itemLimit: Unread/Starred when maxDays === 0
    property int maxDays: th.freshRssMaxDays !== undefined ? th.freshRssMaxDays : 30
    property int perFeedLimit: th.freshRssPerFeedLimit || 12
    property int itemLimit: th.freshRssItemLimit || 80
    readonly property var perFeedChoices: [5, 8, 10, 12, 15, 20, 25, 30]
    readonly property var itemLimitChoices: [20, 40, 50, 80, 100, 150, 200]
    readonly property var maxDaysChoices: [7, 14, 30, 60, 90, 180, 0]  // 0 = unlimited

    // Resizable list pane width (SplitView).
    // Default always from Config.freshRssListWidth. listPaneUserWidth is set only when
    // the user finishes dragging the split handle (not on every width change / not while
    // the FloatingWindow is hidden). Writing preferredWidth every pixel used to thrash
    // layout and early hidden layout used to break the Config binding entirely.
    property int listPaneUserWidth: -1
    readonly property int listPaneWidth: listPaneUserWidth > 0
                                         ? listPaneUserWidth
                                         : (th.freshRssListWidth || 320)
    readonly property int listPaneMinWidth: th.freshRssListMinWidth || 180
    readonly property int listPaneMaxWidth: th.freshRssListMaxWidth || 720
    readonly property int detailPaneMinWidth: th.freshRssDetailMinWidth || 260

    // Collapsed category titles → true. Reassign whole object + bump version so listRows rebinds.
    property var collapsedCategories: ({})
    // FreshRSS folders (News, Youtube Feeds, …)
    property var collapsedGroups: ({})
    property int collapseVersion: 0
    // After each successful fetch, re-collapse categories (fresh session start behavior).
    property bool autoCollapseOnLoad: true

    // Unread badge + per-feed maps from FreshRSS (GReader unread-count)
    property int unreadCount: 0
    property int loadedCount: 0
    property var feedUnreadById: ({})    // "16" → 10
    property var feedUnreadByTitle: ({}) // "Alex Jones Live" → 10
    property int countsVersion: 0        // bump when maps change (listRows rebind)

    function serverUnreadForCategory(cat, feedId) {
        const _ = countsVersion
        const titles = feedUnreadByTitle || ({})
        if (cat && titles[cat] !== undefined && titles[cat] !== null)
            return Math.max(0, Number(titles[cat]) || 0)
        const ids = feedUnreadById || ({})
        if (feedId !== undefined && feedId !== null && feedId !== "") {
            const k = String(feedId)
            if (ids[k] !== undefined && ids[k] !== null)
                return Math.max(0, Number(ids[k]) || 0)
        }
        return -1  // unknown (not from server)
    }

    /** Unread among currently loaded+filtered items for a category (fallback / date rows). */
    function loadedUnreadInList(itemList) {
        let n = 0
        for (let i = 0; i < itemList.length; i++) {
            if (Number(itemList[i].is_read) !== 1)
                n++
        }
        return n
    }

    readonly property string viewStatusText: {
        const shown = filteredItems.length
        const loaded = loadedCount || items.length
        let loadedUnread = 0
        let loadedRead = 0
        for (let i = 0; i < filteredItems.length; i++) {
            if (Number(filteredItems[i].is_read) === 1)
                loadedRead++
            else
                loadedUnread++
        }
        const parts = []
        parts.push(readScope)
        parts.push(dateFilter === "today" ? "today" : (dateFilter === "week" ? "7d" : "all dates"))
        // FreshRSS-accurate global unread first
        parts.push(unreadCount + " unread")
        // What's visible in the current filter
        parts.push(shown + " shown")
        if (shown > 0)
            parts.push(loadedUnread + "u/" + loadedRead + "r in view")
        if (loaded !== shown)
            parts.push(loaded + " loaded")
        if (maxDays > 0)
            parts.push(maxDays + "d")
        else if (readScope === "all" || readScope === "read")
            parts.push(perFeedLimit + "/feed")
        else
            parts.push("max " + itemLimit)
        return parts.join(" · ")
    }

    readonly property var selectedItem: {
        if (selectedIndex < 0 || selectedIndex >= items.length)
            return null
        return items[selectedIndex]
    }

    // Flat article list after search / date / video filters, newest first.
    // Keep this cheap: items may be hundreds; avoid scanning full HTML bodies.
    readonly property var filteredItems: {
        const q = (searchQuery || "").trim().toLowerCase()
        const wantVideo = filterMode === "video"
        const df = dateFilter
        const now = new Date()
        const startToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime() / 1000
        const startWeek = startToday - 6 * 86400
        // Global day window (overrides / is independent of Today/7d chips)
        const maxDaysCut = (maxDays > 0)
            ? (Math.floor(Date.now() / 1000) - maxDays * 86400)
            : 0

        const src = items
        const n = src.length
        const list = []
        for (let i = 0; i < n; i++) {
            const it = src[i]
            const created = Number(it.created_on_time || 0)
            if (maxDaysCut > 0 && created > 0 && created < maxDaysCut)
                continue
            if (wantVideo) {
                // Prefer precomputed flag from the API; fall back for older payloads.
                if (Number(it.is_video) !== 1 && !itemIsVideo(it))
                    continue
            }
            if (df === "today") {
                if (created < startToday)
                    continue
            } else if (df === "week") {
                if (created < startWeek)
                    continue
            }
            if (q.length > 0) {
                // Metadata only (not full body text) — much cheaper for large lists
                const blob = (
                    String(it.title || "") + "\n" +
                    String(it.author || "") + "\n" +
                    String(it.feed_title || "") + "\n" +
                    String(it.group_title || "") + "\n" +
                    String(it.category || "") + "\n" +
                    String(it.summary || "")
                ).toLowerCase()
                if (blob.indexOf(q) < 0)
                    continue
            }
            list.push(it)
        }
        list.sort((a, b) => Number(b.created_on_time || 0) - Number(a.created_on_time || 0))
        return list
    }

    // Date sub-group collapse: key = "category\x1fYYYY-MM-DD" → true when collapsed
    property var collapsedDates: ({})

    function dateKeyForEpoch(epoch) {
        const e = Number(epoch || 0)
        if (e <= 0)
            return "unknown"
        const d = new Date(e * 1000)
        const y = d.getFullYear()
        const m = String(d.getMonth() + 1).padStart(2, "0")
        const day = String(d.getDate()).padStart(2, "0")
        return y + "-" + m + "-" + day
    }

    function dateLabelForKey(key, epoch) {
        if (!key || key === "unknown")
            return "Unknown date"
        const now = new Date()
        const todayKey = dateKeyForEpoch(Math.floor(now.getTime() / 1000))
        const yest = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1)
        const yestKey = dateKeyForEpoch(Math.floor(yest.getTime() / 1000))
        if (key === todayKey)
            return "Today"
        if (key === yestKey)
            return "Yesterday"
        const e = Number(epoch || 0)
        if (e > 0)
            return Qt.formatDateTime(new Date(e * 1000), "ddd, MMM d, yyyy")
        // parse key yyyy-MM-dd
        const parts = key.split("-")
        if (parts.length === 3) {
            const d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
            return Qt.formatDateTime(d, "ddd, MMM d, yyyy")
        }
        return key
    }

    function dateCollapseKey(cat, dateKey) {
        return String(cat) + "\x1f" + String(dateKey)
    }

    // Sectioned rows: FreshRSS folder → feed → date → articles
    readonly property var listRows: {
        const _tick = collapseVersion  // dependency for collapse toggles
        const _counts = countsVersion  // rebind when FreshRSS unread maps update
        const list = filteredItems
        const collapsed = collapsedCategories || ({})
        const collapsedGrp = collapsedGroups || ({})
        const collapsedDt = collapsedDates || ({})

        const groups = ({})
        const groupOrder = []
        function ensureFeed(group, feed, fid) {
            if (!groups[group]) {
                groups[group] = ({})
                groupOrder.push(group)
            }
            const gg = groups[group]
            if (!gg[feed])
                gg[feed] = { items: [], feed_id: fid || "" }
            else if (fid && !gg[feed].feed_id)
                gg[feed].feed_id = fid
            return gg[feed]
        }

        for (let i = 0; i < list.length; i++) {
            const it = list[i]
            const feed = (it.feed_title || it.category || "Other").toString()
            const group = (it.group_title || "Other Feeds").toString()
            ensureFeed(group, feed, it.feed_id).items.push(it)
        }

        groupOrder.sort((a, b) => a.localeCompare(b, undefined, { sensitivity: "base" }))
        const rows = []
        for (let gi = 0; gi < groupOrder.length; gi++) {
            const g = groupOrder[gi]
            const feedsMap = groups[g]
            const feedNames = Object.keys(feedsMap)
            feedNames.sort((a, b) => a.localeCompare(b, undefined, { sensitivity: "base" }))
            let groupUnread = 0
            let groupShown = 0
            for (let fi = 0; fi < feedNames.length; fi++) {
                const itemsIn = feedsMap[feedNames[fi]].items
                const sampleFid = feedsMap[feedNames[fi]].feed_id
                const srv = serverUnreadForCategory(feedNames[fi], sampleFid)
                const loadedUnread = loadedUnreadInList(itemsIn)
                groupUnread += srv >= 0 ? srv : loadedUnread
                groupShown += itemsIn.length
            }
            const gCollapsed = !!collapsedGrp[g]
            rows.push({
                kind: "group",
                group: g,
                category: g,
                unread: groupUnread,
                shown: groupShown,
                collapsed: gCollapsed,
                id: "grp:" + g
            })
            if (gCollapsed)
                continue

            for (let fi = 0; fi < feedNames.length; fi++) {
                const cat = feedNames[fi]
                const itemsIn = feedsMap[cat].items
                const isCollapsed = !!collapsed[cat]
                const sampleFid = feedsMap[cat].feed_id
                const srvUnread = serverUnreadForCategory(cat, sampleFid)
                const loadedUnread = loadedUnreadInList(itemsIn)
                const loadedRead = itemsIn.length - loadedUnread
                rows.push({
                    kind: "header",
                    category: cat,
                    group: g,
                    feed_id: sampleFid,
                    unread: srvUnread >= 0 ? srvUnread : loadedUnread,
                    read: loadedRead,
                    shown: itemsIn.length,
                    count: srvUnread >= 0 ? srvUnread : loadedUnread,
                    collapsed: isCollapsed,
                    id: "hdr:" + g + "\x1f" + cat
                })
                if (isCollapsed)
                    continue

            // Sub-group by calendar date (newest dates first)
            const byDate = ({})
            for (let j = 0; j < itemsIn.length; j++) {
                const it = itemsIn[j]
                const dk = dateKeyForEpoch(it.created_on_time)
                if (!byDate[dk])
                    byDate[dk] = []
                byDate[dk].push(it)
            }
            const dateKeys = Object.keys(byDate)
            dateKeys.sort((a, b) => {
                // unknown last; otherwise newest date first (string yyyy-MM-dd sorts lexically)
                if (a === "unknown")
                    return 1
                if (b === "unknown")
                    return -1
                return b.localeCompare(a)
            })

            for (let d = 0; d < dateKeys.length; d++) {
                const dk = dateKeys[d]
                const dayItems = byDate[dk]
                // newest articles first within the day
                dayItems.sort((a, b) => Number(b.created_on_time || 0) - Number(a.created_on_time || 0))
                const dKey = dateCollapseKey(cat, dk)
                const dateCollapsed = !!collapsedDt[dKey]
                const sampleEpoch = dayItems[0] ? dayItems[0].created_on_time : 0
                const dayUnread = loadedUnreadInList(dayItems)
                const dayRead = dayItems.length - dayUnread
                rows.push({
                    kind: "date",
                    category: cat,
                    dateKey: dk,
                    dateLabel: dateLabelForKey(dk, sampleEpoch),
                    unread: dayUnread,
                    read: dayRead,
                    shown: dayItems.length,
                    count: dayUnread,
                    collapsed: dateCollapsed,
                    id: "date:" + dKey
                })
                if (dateCollapsed)
                    continue
                for (let k = 0; k < dayItems.length; k++) {
                    const it = dayItems[k]
                    rows.push({
                        kind: "item",
                        id: it.id,
                        item: it,
                        category: cat,
                        dateKey: dk
                    })
                }
            }
            } // feeds
        } // groups
        return rows
    }

    function isCategoryCollapsed(cat) {
        return !!(collapsedCategories && collapsedCategories[cat])
    }

    function toggleCategory(cat) {
        if (!cat)
            return
        const next = ({})
        const cur = collapsedCategories || ({})
        const keys = Object.keys(cur)
        for (let i = 0; i < keys.length; i++)
            next[keys[i]] = cur[keys[i]]
        if (next[cat])
            delete next[cat]
        else
            next[cat] = true
        collapsedCategories = next
        collapseVersion++
    }

    function toggleGroup(group) {
        if (!group)
            return
        const next = ({})
        const cur = collapsedGroups || ({})
        const keys = Object.keys(cur)
        for (let i = 0; i < keys.length; i++)
            next[keys[i]] = cur[keys[i]]
        if (next[group])
            delete next[group]
        else
            next[group] = true
        collapsedGroups = next
        collapseVersion++
    }

    function toggleDateGroup(cat, dateKey) {
        if (!cat || !dateKey)
            return
        const key = dateCollapseKey(cat, dateKey)
        const next = ({})
        const cur = collapsedDates || ({})
        const keys = Object.keys(cur)
        for (let i = 0; i < keys.length; i++)
            next[keys[i]] = cur[keys[i]]
        if (next[key])
            delete next[key]
        else
            next[key] = true
        collapsedDates = next
        collapseVersion++
    }

    function expandAllCategories() {
        collapsedCategories = ({})
        collapsedGroups = ({})
        collapsedDates = ({})
        collapseVersion++
    }

    function collapseAllCategories() {
        // Collapse feeds (not folders) so News / Youtube Feeds still show CachyOS, etc.
        const list = items.length ? items : filteredItems
        const next = ({})
        for (let i = 0; i < list.length; i++) {
            const cat = (list[i].feed_title || list[i].category || "Other").toString()
            next[cat] = true
        }
        collapsedCategories = next
        collapsedGroups = ({})
        collapseVersion++
    }

    readonly property real _ws: (bar.widgetScale ? bar.widgetScale("freshRss") : 1.0)
    Layout.preferredWidth: Math.round(Math.max(42, pillInner.implicitWidth + 16) * _ws)
    Layout.preferredHeight: bar.pillHeight
    Layout.alignment: Qt.AlignVCenter

    radius: bar.pillRadius
    color: pillMouse.containsMouse || readerWindow.visible ? bar.glassHover : bar.pillBg
    border.width: bar.controlBorderWidth
    border.color: (pillMouse.containsMouse || readerWindow.visible) ? bar.accent : bar.pillBorder

    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }
    Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }

    function toggle() {
        if (readerWindow.visible)
            hide()
        else
            show()
    }

    function show() {
        readerWindow.visible = true
        refresh()
    }

    function hide() {
        readerWindow.visible = false
    }

    function refresh() {
        loadItems()
        pollStatus()
    }

    function pollStatus() {
        if (statusProcess.running)
            statusProcess.running = false
        statusProcess.command = [apiScript, "status"]
        statusProcess.running = true
    }

    function loadItems() {
        loading = true
        errorMsg = ""
        if (itemsProcess.running)
            itemsProcess.running = false
        // scope: unread | all | read | saved — see scripts/freshrss-api.sh
        // 4th arg: per-feed count for All/Read (ensures every channel is represented)
        itemsProcess.command = [
            apiScript, "items",
            String(root.itemLimit),
            root.readScope || "all",
            String(root.perFeedLimit),
            String(root.maxDays)  // primary history window; 0 = use per-feed/item caps
        ]
        itemsProcess.running = true
    }

    function setMaxDays(n) {
        const v = Math.max(0, Math.min(3650, Number(n) || 0))
        if (v === maxDays)
            return
        maxDays = v
        loadItems()
    }

    function nudgeMaxDays(delta) {
        const choices = maxDaysChoices
        let idx = choices.indexOf(maxDays)
        if (idx < 0) {
            idx = 0
            for (let i = 0; i < choices.length; i++) {
                if (choices[i] >= maxDays && choices[i] > 0) {
                    idx = i
                    break
                }
                idx = i
            }
        }
        idx = Math.max(0, Math.min(choices.length - 1, idx + delta))
        setMaxDays(choices[idx])
    }

    function setReadScope(scope) {
        if (!scope)
            return
        // "All" = every feed, read + unread. Clear a "Today" date filter so quiet
        // channels (Dark Journalist, David Bombal, …) are not hidden when they
        // have no posts today.
        if (scope === "all" && dateFilter === "today")
            dateFilter = "all"
        if (scope === readScope) {
            // Still reload if user re-clicks All after changing other filters
            if (scope === "all")
                loadItems()
            return
        }
        readScope = scope
        loadItems()
    }

    function setPerFeedLimit(n) {
        const v = Math.max(1, Math.min(40, Number(n) || 12))
        if (v === perFeedLimit)
            return
        perFeedLimit = v
        if (readScope === "all" || readScope === "read")
            loadItems()
    }

    function setItemLimit(n) {
        const v = Math.max(5, Math.min(500, Number(n) || 80))
        if (v === itemLimit)
            return
        itemLimit = v
        if (readScope === "unread" || readScope === "saved")
            loadItems()
    }

    function nudgePerFeed(delta) {
        const choices = perFeedChoices
        let idx = choices.indexOf(perFeedLimit)
        if (idx < 0) {
            // snap to nearest
            idx = 0
            for (let i = 0; i < choices.length; i++) {
                if (choices[i] >= perFeedLimit) {
                    idx = i
                    break
                }
                idx = i
            }
        }
        idx = Math.max(0, Math.min(choices.length - 1, idx + delta))
        setPerFeedLimit(choices[idx])
    }

    function nudgeItemLimit(delta) {
        const choices = itemLimitChoices
        let idx = choices.indexOf(itemLimit)
        if (idx < 0) {
            idx = 0
            for (let i = 0; i < choices.length; i++) {
                if (choices[i] >= itemLimit) {
                    idx = i
                    break
                }
                idx = i
            }
        }
        idx = Math.max(0, Math.min(choices.length - 1, idx + delta))
        setItemLimit(choices[idx])
    }

    function isVideoUrl(url) {
        if (!url)
            return false
        const u = String(url).toLowerCase()
        return u.indexOf("youtube.com") >= 0
            || u.indexOf("youtu.be") >= 0
            || u.indexOf("youtube-nocookie.com") >= 0
            || u.indexOf("/shorts/") >= 0
            || u.indexOf("vimeo.com") >= 0
            || u.indexOf("twitch.tv") >= 0
            || /\.(m4v|mp4|webm|mkv)(\?|$)/i.test(u)
    }

    function itemIsVideo(it) {
        if (!it)
            return false
        if (Number(it.is_video) === 1)
            return true
        return isVideoUrl(it.media_url) || isVideoUrl(it.url)
            || /youtube/i.test(String(it.feed_title || ""))
            || /youtube/i.test(String(it.group_title || ""))
    }

    function playableUrl(it) {
        if (!it)
            return ""
        if (it.media_url && String(it.media_url).length > 0)
            return it.media_url
        return it.url || ""
    }

    function selectItemById(id) {
        if (id === undefined || id === null) {
            selectedIndex = -1
            return
        }
        const sid = String(id)
        for (let j = 0; j < items.length; j++) {
            if (String(items[j].id) === sid) {
                selectedIndex = j
                return
            }
        }
        selectedIndex = -1
    }

    function selectIndex(i) {
        // i is index into filteredItems (article-only, not section headers)
        if (i < 0 || i >= filteredItems.length) {
            selectedIndex = -1
            return
        }
        selectItemById(filteredItems[i].id)
    }

    function selectRelative(delta) {
        if (filteredItems.length === 0)
            return
        let fi = 0
        if (selectedItem) {
            for (let i = 0; i < filteredItems.length; i++) {
                if (String(filteredItems[i].id) === String(selectedItem.id)) {
                    fi = i
                    break
                }
            }
        }
        fi = Math.max(0, Math.min(filteredItems.length - 1, fi + delta))
        selectIndex(fi)
        // Keep list cursor on the selected article when using j/k
        syncListCursorToArticleId(selectedItem ? selectedItem.id : "")
    }

    function syncListCursorToArticleId(articleId) {
        if (articleId === undefined || articleId === null || articleId === "")
            return
        const rows = listRows
        const sid = String(articleId)
        for (let i = 0; i < rows.length; i++) {
            if (rows[i].kind === "item" && rows[i].item && String(rows[i].item.id) === sid) {
                listCursor = i
                listCursorId = rows[i].id || ("item:" + sid)
                return
            }
        }
    }

    function restoreListCursor() {
        const rows = listRows
        if (!rows || rows.length === 0) {
            listCursor = 0
            listCursorId = ""
            return
        }
        if (listCursorId) {
            for (let i = 0; i < rows.length; i++) {
                if (String(rows[i].id) === String(listCursorId)) {
                    listCursor = i
                    return
                }
            }
            // After expand/collapse, id may be gone; try same category header
            if (String(listCursorId).indexOf("hdr:") === 0) {
                const cat = String(listCursorId).slice(4)
                for (let i = 0; i < rows.length; i++) {
                    if (rows[i].kind === "header" && rows[i].category === cat) {
                        listCursor = i
                        listCursorId = rows[i].id
                        return
                    }
                }
            }
        }
        listCursor = Math.max(0, Math.min(rows.length - 1, listCursor))
        listCursorId = rows[listCursor] ? (rows[listCursor].id || "") : ""
    }

    function moveListCursor(delta) {
        const rows = listRows
        if (!rows || rows.length === 0)
            return
        restoreListCursor()
        listCursor = Math.max(0, Math.min(rows.length - 1, listCursor + delta))
        const row = rows[listCursor]
        listCursorId = row ? (row.id || "") : ""
        if (typeof listView !== "undefined" && listView)
            listView.positionViewAtIndex(listCursor, ListView.Contain)
    }

    /** Space — expand/collapse feed or date under the list cursor. */
    function scheduleRestoreListCursor() {
        restoreCursorTimer.restart()
    }

    function toggleListCursorExpand() {
        const rows = listRows
        if (!rows || rows.length === 0)
            return
        restoreListCursor()
        const row = rows[listCursor]
        if (!row)
            return
        if (row.kind === "group") {
            toggleGroup(row.group || row.category || "Other Feeds")
            listCursorId = row.id
            scheduleRestoreListCursor()
        } else if (row.kind === "header") {
            toggleCategory(row.category || "Other")
            listCursorId = row.id || ("hdr:" + (row.category || "Other"))
            scheduleRestoreListCursor()
        } else if (row.kind === "date") {
            toggleDateGroup(row.category, row.dateKey)
            listCursorId = row.id
            scheduleRestoreListCursor()
        } else if (row.kind === "item") {
            // On an article: toggle its feed category (collapse/expand whole feed)
            if (row.category)
                toggleCategory(row.category)
            listCursorId = "hdr:" + (row.category || "Other")
            scheduleRestoreListCursor()
        }
    }

    /** Enter — open article in the detail pane, or expand header/date. */
    function activateListCursor() {
        const rows = listRows
        if (!rows || rows.length === 0)
            return
        restoreListCursor()
        const row = rows[listCursor]
        if (!row)
            return
        if (row.kind === "item" && row.item) {
            selectItemById(row.item.id)
            listCursorId = row.id || ("item:" + row.item.id)
        } else if (row.kind === "group") {
            toggleGroup(row.group || row.category || "Other Feeds")
            listCursorId = row.id
            scheduleRestoreListCursor()
        } else if (row.kind === "header") {
            toggleCategory(row.category || "Other")
            listCursorId = row.id || ("hdr:" + (row.category || "Other"))
            scheduleRestoreListCursor()
        } else if (row.kind === "date") {
            toggleDateGroup(row.category, row.dateKey)
            listCursorId = row.id
            scheduleRestoreListCursor()
        }
    }

    /**
     * Right arrow: load article when cursor is on an item (same as Enter).
     * On a feed/date header, keep expand/collapse (same as Space) so trees still work.
     */
    function rightArrowAction() {
        const rows = listRows
        if (!rows || rows.length === 0)
            return
        restoreListCursor()
        const row = rows[listCursor]
        if (!row)
            return
        if (row.kind === "item")
            activateListCursor()
        else
            toggleListCursorExpand()
    }

    onListRowsChanged: scheduleRestoreListCursor()

    Timer {
        id: restoreCursorTimer
        interval: 1
        repeat: false
        onTriggered: root.restoreListCursor()
    }

    function openBrowser() {
        const it = selectedItem
        if (!it || !it.url)
            return
        runAction(["open-browser", it.url])
    }

    /** Copy the selected article URL to the clipboard (wl-copy). */
    function shareArticleLink() {
        const it = selectedItem
        const url = it && it.url ? String(it.url) : ""
        if (!url.length) {
            statusMsg = "No link to share"
            return
        }
        Quickshell.execDetached([
            "sh", "-c",
            'printf "%s" "$1" | wl-copy',
            "wl-copy",
            url
        ])
        statusMsg = "Link copied"
    }

    function playMpv() {
        const it = selectedItem
        if (!it || !itemIsVideo(it))
            return
        const url = playableUrl(it)
        if (!url)
            return
        statusMsg = "Starting mpv…"
        runAction(["play-mpv", url])
    }

    function openOrPlayUrl(url) {
        if (!url)
            return
        if (isVideoUrl(url)) {
            statusMsg = "Starting mpv…"
            runAction(["play-mpv", url])
        } else {
            runAction(["open-browser", url])
        }
    }

    function activateItem(it) {
        if (!it)
            return
        selectItemById(it.id)
        if (itemIsVideo(it))
            playMpv()
        else
            openBrowser()
    }

    function markRead() {
        if (!writable || !selectedItem)
            return
        runAction(["mark-read", String(selectedItem.id)])
    }

    function starItem() {
        if (!writable || !selectedItem)
            return
        const act = Number(selectedItem.is_saved) === 1 ? "unstar" : "star"
        runAction([act, String(selectedItem.id)])
    }

    /** Resolve numeric feed id for a category title (from list rows or loaded items). */
    function feedIdForCategory(cat) {
        if (!cat)
            return ""
        const rows = listRows
        for (let i = 0; i < rows.length; i++) {
            if (rows[i].kind === "header" && rows[i].category === cat && rows[i].feed_id)
                return String(rows[i].feed_id)
        }
        for (let j = 0; j < items.length; j++) {
            const it = items[j]
            const c = (it.category || it.feed_title || "").toString()
            if (c === cat && it.feed_id !== undefined && it.feed_id !== null && it.feed_id !== "")
                return String(it.feed_id)
        }
        return ""
    }

    /** Category under list cursor, or of the selected article. */
    function activeCategoryContext() {
        const rows = listRows
        if (rows && rows.length > 0) {
            let idx = listCursor
            if (idx < 0 || idx >= rows.length)
                idx = 0
            const row = rows[idx]
            if (row && row.category)
                return {
                    category: row.category,
                    feed_id: row.feed_id || feedIdForCategory(row.category)
                }
        }
        if (selectedItem) {
            const cat = (selectedItem.category || selectedItem.feed_title || "").toString()
            return { category: cat, feed_id: String(selectedItem.feed_id || feedIdForCategory(cat) || "") }
        }
        return null
    }

    // Reactive context for feed-level actions (depends on cursor + data)
    readonly property var cursorFeedContext: {
        const _c = listCursor
        const _v = collapseVersion
        const _i = items.length
        const _s = selectedIndex
        return activeCategoryContext()
    }

    function markCategoryRead() {
        if (!writable)
            return
        const ctx = activeCategoryContext()
        if (!ctx || !ctx.feed_id) {
            statusMsg = "No feed selected (focus a category or article)"
            return
        }
        statusMsg = "Marking “" + ctx.category + "” read…"
        runAction(["mark-feed-read", String(ctx.feed_id)])
    }

    function markCategoryUnread() {
        if (!writable)
            return
        const ctx = activeCategoryContext()
        if (!ctx || !ctx.feed_id) {
            statusMsg = "No feed selected (focus a category or article)"
            return
        }
        statusMsg = "Marking “" + ctx.category + "” unread…"
        runAction(["mark-feed-unread", String(ctx.feed_id)])
    }

    function runAction(args) {
        if (actionProcess.running)
            actionProcess.running = false
        actionProcess.command = [apiScript].concat(args)
        actionProcess.running = true
    }

    function formatTime(epoch) {
        if (!epoch || epoch <= 0)
            return ""
        const d = new Date(epoch * 1000)
        return Qt.formatDateTime(d, "MMM d  HH:mm")
    }

    function bodyHtml(it) {
        if (!it)
            return ""
        // Prefer HTML; Qt RichText is limited but good enough for simple feeds
        const raw = it.html || ""
        if (raw.length > 0)
            return raw
        return (it.text || "").replace(/\n/g, "<br/>")
    }

    // ── Pill face ───────────────────────────────────────────────────────────
    Row {
        id: pillInner
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: bar.pillFaceTopPad
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "󰑫"   // RSS-ish nerd font glyph; fallback below if missing
            color: bar.iconColor !== undefined ? bar.iconColor : bar.subtext
            font.pixelSize: bar.iconSizePillLarge || 16
            font.family: bar.fontFamily
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.unreadCount > 0 ? (root.unreadCount > 99 ? "99+" : String(root.unreadCount)) : "RSS"
            // Bar widget text (Themes → Fonts → Bar widget text)
            color: (bar.barText !== undefined) ? bar.barText : bar.text
            font.pixelSize: {
                var base = (bar.fontBarFace !== undefined) ? bar.fontBarFace : 13
                return Math.max(9, Math.round(base * root._ws))
            }
            font.family: (bar.fontBarResolved !== undefined && String(bar.fontBarResolved).length)
                         ? bar.fontBarResolved
                         : (bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily)
            font.bold: root.unreadCount > 0
        }
    }

    MouseArea {
        id: pillMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggle()
    }

    // Background status poll (badge)
    Timer {
        interval: th.freshRssPollIntervalMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.pollStatus()
    }

    Io.Process {
        id: statusProcess
        stdout: Io.StdioCollector {
            onStreamFinished: {
                const line = (text || "").trim()
                if (!line.startsWith("{"))
                    return
                try {
                    const j = JSON.parse(line)
                    if (j.ok === false) {
                        root.errorMsg = j.error || "status failed"
                        return
                    }
                    // Prefer explicit unread field; never treat "items loaded" as unread
                    if (j.unread !== undefined)
                        root.unreadCount = Math.max(0, Number(j.unread) || 0)
                    else if (j.count !== undefined && j.mode)
                        root.unreadCount = Math.max(0, Number(j.count) || 0)
                    if (j.mode)
                        root.mode = j.mode
                    if (j.mode === "rss")
                        root.errorMsg = "API password missing — this is public RSS, not your feed list. Options → FreshRSS → set Profile → API password to see CachyOS, Dark Journalist, It’s FOSS, …"
                    else if (root.errorMsg && root.errorMsg.indexOf("API password missing") === 0)
                        root.errorMsg = ""
                    if (j.writable !== undefined)
                        root.writable = !!j.writable
                    // Per-feed / per-title unread (FreshRSS sidebar).
                    // Only bump countsVersion when maps actually change — every poll
                    // used to rebuild listRows even when unread totals were identical.
                    let mapsChanged = false
                    if (j.feeds && typeof j.feeds === "object") {
                        if (JSON.stringify(j.feeds) !== JSON.stringify(root.feedUnreadById || ({}))) {
                            root.feedUnreadById = j.feeds
                            mapsChanged = true
                        }
                    }
                    if (j.titles && typeof j.titles === "object") {
                        if (JSON.stringify(j.titles) !== JSON.stringify(root.feedUnreadByTitle || ({}))) {
                            root.feedUnreadByTitle = j.titles
                            mapsChanged = true
                        }
                    }
                    if (mapsChanged)
                        root.countsVersion++
                } catch (e) {}
            }
        }
    }

    Io.Process {
        id: itemsProcess
        stdout: Io.StdioCollector {
            onStreamFinished: {
                root.loading = false
                const line = (text || "").trim()
                if (!line.startsWith("{")) {
                    root.errorMsg = "invalid items response"
                    return
                }
                try {
                    const j = JSON.parse(line)
                    if (j.ok === false) {
                        root.errorMsg = j.error || "items failed"
                        return
                    }
                    root.mode = j.mode || root.mode
                    root.writable = !!j.writable
                    // Do NOT overwrite unreadCount with loaded item count.
                    // Refresh true unread from status after load.
                    const list = j.items || []
                    root.items = list
                    root.loadedCount = list.length
                    root.statusMsg = root.viewStatusText
                    root.pollStatus()
                    // Start collapsed so you open only the feeds you care about
                    if (root.autoCollapseOnLoad)
                        root.collapseAllCategories()
                    // keep selection if possible
                    if (root.selectedItem) {
                        const sid = root.selectedItem.id
                        let found = -1
                        for (let i = 0; i < list.length; i++) {
                            if (list[i].id === sid) {
                                found = i
                                break
                            }
                        }
                        root.selectedIndex = found
                    } else if (list.length > 0) {
                        root.selectedIndex = 0
                    }
                    root.errorMsg = (!root.writable || root.mode === "rss")
                        ? "API password missing — public RSS, not your feed list. Options → FreshRSS → Profile API password."
                        : ""
                } catch (e) {
                    root.errorMsg = "parse error"
                }
            }
        }
        stderr: Io.StdioCollector {
            onStreamFinished: {
                if ((text || "").trim().length > 0 && root.loading)
                    root.errorMsg = text.trim().slice(0, 200)
            }
        }
    }

    Io.Process {
        id: actionProcess
        stdout: Io.StdioCollector {
            onStreamFinished: {
                const line = (text || "").trim()
                if (!line.startsWith("{"))
                    return
                try {
                    const j = JSON.parse(line)
                    if (j.ok === false) {
                        root.statusMsg = j.error || "action failed"
                        return
                    }
                    if (j.as === "read" || j.as === "saved" || j.as === "unsaved" || j.as === "unread")
                        root.loadItems()
                    else if (j.action === "mark-feed-read" || j.action === "mark-feed-unread") {
                        root.statusMsg = j.action === "mark-feed-read"
                            ? "Feed marked read"
                            : ("Feed marked unread" + (j.items ? (" (" + j.items + " items)") : ""))
                        root.loadItems()
                        root.pollStatus()
                    } else if (j.action === "mpv")
                        root.statusMsg = "Playing in mpv…"
                    else if (j.action === "browser")
                        root.statusMsg = "Opened in browser"
                } catch (e) {}
            }
        }
    }

    // ── Reader window ───────────────────────────────────────────────────────
    FloatingWindow {
        id: readerWindow
        visible: false
        title: "FreshRSS"
        color: "transparent"
        implicitWidth: th.freshRssWidth
        implicitHeight: th.freshRssHeight
        minimumSize: Qt.size(th.freshRssMinWidth, th.freshRssMinHeight)

        onClosed: root.hide()

        Shortcut {
            sequence: "Escape"
            enabled: readerWindow.visible
            onActivated: root.hide()
        }
        Shortcut {
            sequence: "Ctrl+R"
            enabled: readerWindow.visible
            onActivated: root.refresh()
        }
        Shortcut {
            sequence: "R"
            enabled: readerWindow.visible && !searchField.activeFocus
            onActivated: root.refresh()
        }
        Shortcut {
            sequence: "Ctrl+F"
            enabled: readerWindow.visible
            onActivated: searchField.forceActiveFocus()
        }
        Shortcut {
            sequence: "/"
            enabled: readerWindow.visible && !searchField.activeFocus
            onActivated: searchField.forceActiveFocus()
        }
        // Article-only navigation (also moves list cursor onto the article)
        Shortcut {
            sequence: "J"
            enabled: readerWindow.visible && !searchField.activeFocus
            onActivated: root.selectRelative(1)
        }
        Shortcut {
            sequence: "K"
            enabled: readerWindow.visible && !searchField.activeFocus
            onActivated: root.selectRelative(-1)
        }
        // Full list cursor (headers, dates, articles): W up / S down
        Shortcut {
            sequence: "W"
            enabled: readerWindow.visible && !searchField.activeFocus
            onActivated: root.moveListCursor(-1)
        }
        Shortcut {
            sequence: "S"
            enabled: readerWindow.visible && !searchField.activeFocus
            onActivated: root.moveListCursor(1)
        }
        Shortcut {
            sequence: "Up"
            enabled: readerWindow.visible && !searchField.activeFocus
            onActivated: root.moveListCursor(-1)
        }
        Shortcut {
            sequence: "Down"
            enabled: readerWindow.visible && !searchField.activeFocus
            onActivated: root.moveListCursor(1)
        }
        Shortcut {
            sequence: "Space"
            enabled: readerWindow.visible && !searchField.activeFocus
            onActivated: root.toggleListCursorExpand()
        }
        // Right / D: open article if cursor is on one; otherwise expand/collapse feed/date
        Shortcut {
            sequence: "Right"
            enabled: readerWindow.visible && !searchField.activeFocus
            onActivated: root.rightArrowAction()
        }
        Shortcut {
            sequence: "D"
            enabled: readerWindow.visible && !searchField.activeFocus
            onActivated: root.rightArrowAction()
        }
        // Left / A: expand/collapse only
        Shortcut {
            sequence: "Left"
            enabled: readerWindow.visible && !searchField.activeFocus
            onActivated: root.toggleListCursorExpand()
        }
        Shortcut {
            sequence: "A"
            enabled: readerWindow.visible && !searchField.activeFocus
            onActivated: root.toggleListCursorExpand()
        }
        Shortcut {
            sequence: "Return"
            enabled: readerWindow.visible && !searchField.activeFocus
            onActivated: root.activateListCursor()
        }
        Shortcut {
            sequence: "Enter"
            enabled: readerWindow.visible && !searchField.activeFocus
            onActivated: root.activateListCursor()
        }
        Shortcut {
            sequence: "B"
            enabled: readerWindow.visible && !searchField.activeFocus
            onActivated: root.openBrowser()
        }
        // Copy article link (share)
        Shortcut {
            sequence: "C"
            enabled: readerWindow.visible && !searchField.activeFocus
                     && root.selectedItem && root.selectedItem.url
            onActivated: root.shareArticleLink()
        }
        Shortcut {
            sequence: "V"
            enabled: readerWindow.visible && !searchField.activeFocus
                     && root.selectedItem && root.itemIsVideo(root.selectedItem)
            onActivated: root.playMpv()
        }
        Shortcut {
            sequence: "M"
            enabled: readerWindow.visible && root.writable && !searchField.activeFocus
            onActivated: root.markRead()
        }
        // Star moved off S (S = list down); use Shift+S
        Shortcut {
            sequence: "Shift+S"
            enabled: readerWindow.visible && root.writable && !searchField.activeFocus
            onActivated: root.starItem()
        }
        // Mark whole feed/category under list cursor
        Shortcut {
            sequence: "Shift+R"
            enabled: readerWindow.visible && root.writable && !searchField.activeFocus
            onActivated: root.markCategoryRead()
        }
        Shortcut {
            sequence: "Shift+U"
            enabled: readerWindow.visible && root.writable && !searchField.activeFocus
            onActivated: root.markCategoryUnread()
        }

        Rectangle {
            id: panel
            anchors.fill: parent
            radius: th.popupRadiusLarge || 12
            color: th.inspWindowBg || bar.glassPopupBg
            border.width: 1
            border.color: th.inspWindowBorder || bar.glassPopupBorder
            focus: readerWindow.visible

            // top highlight
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: bar.popupHeaderHighlightHeight || 1
                color: th.inspWindowHighlight || bar.glassPopupHighlight
                radius: parent.radius
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        text: "FreshRSS"
                        color: bar.text
                        font.pixelSize: bar.popupTitleSize || 16
                        font.bold: true
                        font.family: bar.fontFamily
                    }

                    Rectangle {
                        radius: 6
                        color: Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.18)
                        border.width: 1
                        border.color: bar.accent
                        implicitHeight: 22
                        implicitWidth: modeLabel.implicitWidth + 14
                        Text {
                            id: modeLabel
                            anchors.centerIn: parent
                            text: root.mode === "fever"
                                  ? (root.writable ? "Fever · read/write" : "Fever")
                                  : "RSS · read-only"
                            color: bar.subtext
                            font.pixelSize: 11
                            font.family: bar.fontMono
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: root.loading
                              ? "Loading…"
                              : (root.errorMsg || root.viewStatusText)
                        color: root.errorMsg ? "#e06c75" : bar.subtext
                        font.pixelSize: 12
                        font.family: bar.fontMono
                        elide: Text.ElideRight
                        Layout.maximumWidth: 420
                    }

                    Rectangle {
                        radius: 6
                        implicitHeight: 28
                        implicitWidth: refreshTxt.implicitWidth + 18
                        color: refreshMa.containsMouse ? bar.iconHoverBg : "transparent"
                        border.width: 1
                        border.color: bar.pillBorder
                        Text {
                            id: refreshTxt
                            anchors.centerIn: parent
                            text: "Refresh"
                            color: bar.text
                            font.pixelSize: 12
                        }
                        MouseArea {
                            id: refreshMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.refresh()
                        }
                    }
                }

                // View controls (always visible)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // Date chips
                    Repeater {
                        model: [
                            { id: "all", label: "All dates" },
                            { id: "today", label: "Today" },
                            { id: "week", label: "7 days" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            radius: 6
                            implicitHeight: 28
                            implicitWidth: dateTxt.implicitWidth + 14
                            color: root.dateFilter === modelData.id
                                   ? Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.28)
                                   : (dateMa.containsMouse ? bar.iconHoverBg : "transparent")
                            border.width: 1
                            border.color: root.dateFilter === modelData.id ? bar.accent : bar.pillBorder
                            Text {
                                id: dateTxt
                                anchors.centerIn: parent
                                text: modelData.label
                                color: bar.text
                                font.pixelSize: 12
                            }
                            MouseArea {
                                id: dateMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.dateFilter = modelData.id
                            }
                        }
                    }

                    // Read state scope (server fetch)
                    Repeater {
                        model: [
                            { id: "unread", label: "Unread" },
                            { id: "all", label: "All" },
                            { id: "read", label: "Read" },
                            { id: "saved", label: "Starred" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            radius: 6
                            implicitHeight: 28
                            implicitWidth: scopeTxt.implicitWidth + 14
                            color: root.readScope === modelData.id
                                   ? Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.28)
                                   : (scopeMa.containsMouse ? bar.iconHoverBg : "transparent")
                            border.width: 1
                            border.color: root.readScope === modelData.id ? bar.accent : bar.pillBorder
                            Text {
                                id: scopeTxt
                                anchors.centerIn: parent
                                text: modelData.label
                                color: bar.text
                                font.pixelSize: 12
                            }
                            MouseArea {
                                id: scopeMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.setReadScope(modelData.id)
                            }
                        }
                    }

                    // Type chips (client filter on current list)
                    Repeater {
                        model: [
                            { id: "all", label: "Any type" },
                            { id: "video", label: "Video" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            radius: 6
                            implicitHeight: 28
                            implicitWidth: typeTxt.implicitWidth + 14
                            color: root.filterMode === modelData.id
                                   ? Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.28)
                                   : (typeMa.containsMouse ? bar.iconHoverBg : "transparent")
                            border.width: 1
                            border.color: root.filterMode === modelData.id ? bar.accent : bar.pillBorder
                            Text {
                                id: typeTxt
                                anchors.centerIn: parent
                                text: modelData.label
                                color: bar.text
                                font.pixelSize: 12
                            }
                            MouseArea {
                                id: typeMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.filterMode = modelData.id
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Expand / collapse all categories
                    Rectangle {
                        radius: 6
                        implicitHeight: 28
                        implicitWidth: foldTxt.implicitWidth + 14
                        color: foldMa.containsMouse ? bar.iconHoverBg : "transparent"
                        border.width: 1
                        border.color: bar.pillBorder
                        Text {
                            id: foldTxt
                            anchors.centerIn: parent
                            text: "Collapse all"
                            color: bar.text
                            font.pixelSize: 12
                        }
                        MouseArea {
                            id: foldMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.collapseAllCategories()
                        }
                    }
                    Rectangle {
                        radius: 6
                        implicitHeight: 28
                        implicitWidth: expandTxt.implicitWidth + 14
                        color: expandMa.containsMouse ? bar.iconHoverBg : "transparent"
                        border.width: 1
                        border.color: bar.pillBorder
                        Text {
                            id: expandTxt
                            anchors.centerIn: parent
                            text: "Expand all"
                            color: bar.text
                            font.pixelSize: 12
                        }
                        MouseArea {
                            id: expandMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.expandAllCategories()
                        }
                    }
                }

                // ===== Filters (collapsible): search, max days, per feed =====
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    // Header
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        radius: 6
                        color: filtersHdrMa.containsMouse ? bar.iconHoverBg : "transparent"
                        border.width: 1
                        border.color: bar.pillBorder
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8
                            Text {
                                text: root.filtersExpanded ? "▾" : "▸"
                                color: bar.subtext
                                font.pixelSize: 12
                                Layout.preferredWidth: 12
                            }
                            Text {
                                text: "Filters"
                                color: bar.text
                                font.pixelSize: 12
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            Text {
                                visible: !root.filtersExpanded
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: {
                                    const bits = []
                                    const q = (root.searchQuery || "").trim()
                                    if (q.length)
                                        bits.push("\"" + q + "\"")
                                    if (root.maxDays > 0)
                                        bits.push(root.maxDays + "d")
                                    else
                                        bits.push("∞ days")
                                    if (root.readScope === "all" || root.readScope === "read")
                                        bits.push(root.perFeedLimit + "/feed")
                                    else
                                        bits.push("max " + root.itemLimit)
                                    return bits.join(" · ")
                                }
                                color: bar.subtext
                                font.pixelSize: 11
                                font.family: bar.fontFamily
                            }
                            Item { Layout.fillWidth: true; visible: root.filtersExpanded }
                        }
                        MouseArea {
                            id: filtersHdrMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.filtersExpanded = !root.filtersExpanded
                        }
                    }

                    ColumnLayout {
                        visible: root.filtersExpanded
                        Layout.fillWidth: true
                        spacing: 8

                        // Search
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            radius: 8
                            color: Qt.rgba(0, 0, 0, 0.22)
                            border.width: 1
                            border.color: searchField.activeFocus ? bar.accent : (bar.pillBorder || bar.divider)

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 8
                                spacing: 6

                                Text {
                                    text: "⌕"
                                    color: bar.subtext
                                    font.pixelSize: 14
                                }
                                TextInput {
                                    id: searchField
                                    Layout.fillWidth: true
                                    color: bar.text
                                    font.pixelSize: 13
                                    font.family: bar.fontFamily
                                    clip: true
                                    selectByMouse: true
                                    selectedTextColor: bar.bg || "#111"
                                    selectionColor: bar.accent
                                    onTextChanged: root.searchQuery = text

                                    Text {
                                        anchors.fill: parent
                                        visible: !searchField.text && !searchField.activeFocus
                                        text: "Search title, feed, author…"
                                        color: bar.subtext
                                        font.pixelSize: 13
                                    }
                                }
                                Text {
                                    visible: searchField.text.length > 0
                                    text: "✕"
                                    color: bar.subtext
                                    font.pixelSize: 12
                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -4
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            searchField.text = ""
                                            root.searchQuery = ""
                                        }
                                    }
                                }
                            }
                        }

                        // Max days
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "Max days:"
                                color: bar.subtext
                                font.pixelSize: 12
                                font.bold: true
                            }

                            Rectangle {
                                radius: 6
                                implicitWidth: 28
                                implicitHeight: 28
                                color: daysMinusMa.containsMouse ? bar.iconHoverBg : "transparent"
                                border.width: 1
                                border.color: bar.pillBorder
                                Text {
                                    anchors.centerIn: parent
                                    text: "−"
                                    color: bar.text
                                    font.pixelSize: 16
                                    font.bold: true
                                }
                                MouseArea {
                                    id: daysMinusMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.nudgeMaxDays(-1)
                                }
                            }

                            Text {
                                text: root.maxDays > 0 ? String(root.maxDays) : "∞"
                                color: bar.accent
                                font.pixelSize: 13
                                font.bold: true
                                font.family: bar.fontMono
                                Layout.preferredWidth: 36
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Rectangle {
                                radius: 6
                                implicitWidth: 28
                                implicitHeight: 28
                                color: daysPlusMa.containsMouse ? bar.iconHoverBg : "transparent"
                                border.width: 1
                                border.color: bar.pillBorder
                                Text {
                                    anchors.centerIn: parent
                                    text: "+"
                                    color: bar.text
                                    font.pixelSize: 16
                                    font.bold: true
                                }
                                MouseArea {
                                    id: daysPlusMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.nudgeMaxDays(1)
                                }
                            }

                            Repeater {
                                model: root.maxDaysChoices
                                delegate: Rectangle {
                                    required property var modelData
                                    radius: 6
                                    implicitHeight: 26
                                    implicitWidth: daysPresetTxt.implicitWidth + 12
                                    readonly property bool active: root.maxDays === modelData
                                    color: active
                                           ? Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.28)
                                           : (daysPresetMa.containsMouse ? bar.iconHoverBg : "transparent")
                                    border.width: 1
                                    border.color: active ? bar.accent : bar.pillBorder
                                    Text {
                                        id: daysPresetTxt
                                        anchors.centerIn: parent
                                        text: modelData === 0 ? "∞" : String(modelData)
                                        color: bar.text
                                        font.pixelSize: 11
                                        font.family: bar.fontMono
                                    }
                                    MouseArea {
                                        id: daysPresetMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.setMaxDays(modelData)
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.maxDays > 0
                                      ? "history window (overrides per-feed / item limits)"
                                      : "unlimited history — use per-feed / item limits below"
                                color: bar.subtext
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }

                        // Per feed / max items
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            opacity: root.maxDays > 0 ? 0.45 : 1.0

                            Text {
                                text: (root.readScope === "all" || root.readScope === "read")
                                      ? "Per feed:"
                                      : "Max items:"
                                color: bar.subtext
                                font.pixelSize: 12
                            }

                            Rectangle {
                                radius: 6
                                implicitWidth: 28
                                implicitHeight: 28
                                color: minusMa.containsMouse && root.maxDays <= 0 ? bar.iconHoverBg : "transparent"
                                border.width: 1
                                border.color: bar.pillBorder
                                Text {
                                    anchors.centerIn: parent
                                    text: "−"
                                    color: bar.text
                                    font.pixelSize: 16
                                    font.bold: true
                                }
                                MouseArea {
                                    id: minusMa
                                    anchors.fill: parent
                                    enabled: root.maxDays <= 0
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.readScope === "all" || root.readScope === "read")
                                            root.nudgePerFeed(-1)
                                        else
                                            root.nudgeItemLimit(-1)
                                    }
                                }
                            }

                            Text {
                                text: (root.readScope === "all" || root.readScope === "read")
                                      ? String(root.perFeedLimit)
                                      : String(root.itemLimit)
                                color: bar.text
                                font.pixelSize: 13
                                font.bold: true
                                font.family: bar.fontMono
                                Layout.preferredWidth: 36
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Rectangle {
                                radius: 6
                                implicitWidth: 28
                                implicitHeight: 28
                                color: plusMa.containsMouse && root.maxDays <= 0 ? bar.iconHoverBg : "transparent"
                                border.width: 1
                                border.color: bar.pillBorder
                                Text {
                                    anchors.centerIn: parent
                                    text: "+"
                                    color: bar.text
                                    font.pixelSize: 16
                                    font.bold: true
                                }
                                MouseArea {
                                    id: plusMa
                                    anchors.fill: parent
                                    enabled: root.maxDays <= 0
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.readScope === "all" || root.readScope === "read")
                                            root.nudgePerFeed(1)
                                        else
                                            root.nudgeItemLimit(1)
                                    }
                                }
                            }

                            Repeater {
                                model: (root.readScope === "all" || root.readScope === "read")
                                       ? [5, 10, 12, 15, 20, 30]
                                       : [20, 50, 80, 100, 150]
                                delegate: Rectangle {
                                    required property var modelData
                                    radius: 6
                                    implicitHeight: 26
                                    implicitWidth: presetTxt.implicitWidth + 12
                                    readonly property bool active: {
                                        if (root.readScope === "all" || root.readScope === "read")
                                            return root.perFeedLimit === modelData
                                        return root.itemLimit === modelData
                                    }
                                    color: active
                                           ? Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.28)
                                           : (presetMa.containsMouse && root.maxDays <= 0 ? bar.iconHoverBg : "transparent")
                                    border.width: 1
                                    border.color: active ? bar.accent : bar.pillBorder
                                    Text {
                                        id: presetTxt
                                        anchors.centerIn: parent
                                        text: String(modelData)
                                        color: bar.text
                                        font.pixelSize: 11
                                        font.family: bar.fontMono
                                    }
                                    MouseArea {
                                        id: presetMa
                                        anchors.fill: parent
                                        enabled: root.maxDays <= 0
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.readScope === "all" || root.readScope === "read")
                                                root.setPerFeedLimit(modelData)
                                            else
                                                root.setItemLimit(modelData)
                                        }
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.maxDays > 0
                                      ? "(inactive while Max days is set)"
                                      : ((root.readScope === "all" || root.readScope === "read")
                                         ? "articles per feed"
                                         : "total for Unread / Starred")
                                color: bar.subtext
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                // Body split — drag the handle to resize list vs article panes
                SplitView {
                    id: bodySplit
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    orientation: Qt.Horizontal
                    handle: Rectangle {
                        implicitWidth: 10
                        color: "transparent"
                        // Persist width once on drag end (not per-pixel) so preferredWidth
                        // stays stable during the drag and we never clobber Config on
                        // hidden/zero-size layout.
                        readonly property bool dragging: SplitHandle.pressed
                        onDraggingChanged: {
                            if (dragging || !readerWindow.visible)
                                return
                            const w = Math.round(listPane.width)
                            if (w >= root.listPaneMinWidth && Math.abs(w - root.listPaneWidth) > 1)
                                root.listPaneUserWidth = w
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            width: SplitHandle.pressed || SplitHandle.hovered ? 4 : 2
                            height: Math.min(parent.height - 16, 80)
                            radius: 2
                            color: SplitHandle.pressed
                                   ? bar.accent
                                   : (SplitHandle.hovered
                                      ? Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.7)
                                      : (bar.divider || bar.pillBorder))
                            Behavior on width { NumberAnimation { duration: 80 } }
                        }
                    }

                    // List (grouped by feed/category title, newest sections & items on top)
                    Rectangle {
                        id: listPane
                        // preferredWidth + implicitWidth so SplitView honors Config on first show
                        SplitView.preferredWidth: root.listPaneWidth
                        implicitWidth: root.listPaneWidth
                        SplitView.minimumWidth: root.listPaneMinWidth
                        SplitView.maximumWidth: root.listPaneMaxWidth
                        radius: 8
                        color: Qt.rgba(0, 0, 0, 0.18)
                        border.width: 1
                        border.color: bar.divider || bar.pillBorder

                        ListView {
                            id: listView
                            anchors.fill: parent
                            anchors.margins: 4
                            clip: true
                            spacing: 2
                            model: root.listRows
                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                            }

                            delegate: Rectangle {
                                id: rowDelegate
                                required property var modelData
                                required property int index
                                width: listView.width
                                readonly property bool isGroup: modelData.kind === "group"
                                readonly property bool isHeader: modelData.kind === "header"
                                readonly property bool isDate: modelData.kind === "date"
                                readonly property bool isItem: modelData.kind === "item"
                                readonly property var art: isItem ? (modelData.item || null) : null
                                height: isGroup ? 30 : (isHeader ? 26 : (isDate ? 24 : (titleCol.implicitHeight + 14)))
                                radius: isGroup ? 6 : (isHeader ? 4 : (isDate ? 3 : 6))
                                readonly property bool isCursor: index === root.listCursor
                                color: {
                                    if (isCursor)
                                        return Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.28)
                                    if (isGroup)
                                        return Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.16)
                                    if (isHeader)
                                        return Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.10)
                                    if (isDate)
                                        return Qt.rgba(1, 1, 1, 0.04)
                                    const sel = root.selectedItem && art && String(root.selectedItem.id) === String(art.id)
                                    if (sel)
                                        return Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.22)
                                    return rowMa.containsMouse ? (th.inspRowHoverBg || bar.iconHoverBg) : "transparent"
                                }
                                border.width: isCursor || (isItem && root.selectedItem && art && String(root.selectedItem.id) === String(art.id)) ? 1 : 0
                                border.color: isCursor ? bar.accent : bar.accent

                                RowLayout {
                                    visible: rowDelegate.isGroup
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 6
                                    Text {
                                        text: modelData.collapsed ? "▸" : "▾"
                                        color: bar.accent
                                        font.pixelSize: 13
                                        font.bold: true
                                        Layout.preferredWidth: 14
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.group || modelData.category || "Other Feeds"
                                        color: bar.text
                                        font.pixelSize: 13
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        text: String(Number(modelData.unread || 0))
                                        color: Number(modelData.unread || 0) > 0 ? bar.accent : bar.subtext
                                        font.pixelSize: 11
                                        font.bold: Number(modelData.unread || 0) > 0
                                        font.family: bar.fontMono
                                    }
                                }

                                // Feed header (subscription name)
                                RowLayout {
                                    visible: rowDelegate.isHeader
                                    anchors.fill: parent
                                    anchors.leftMargin: 22
                                    anchors.rightMargin: 8
                                    spacing: 6
                                    Text {
                                        text: modelData.collapsed ? "▸" : "▾"
                                        color: bar.accent
                                        font.pixelSize: 13
                                        font.bold: true
                                        Layout.preferredWidth: 14
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.category || "Other"
                                        color: bar.accent
                                        font.pixelSize: 12
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    // FreshRSS sidebar style: primary number = unread on server
                                    Text {
                                        text: String(Number(modelData.unread || 0))
                                        color: Number(modelData.unread || 0) > 0 ? bar.accent : bar.subtext
                                        font.pixelSize: 11
                                        font.bold: Number(modelData.unread || 0) > 0
                                        font.family: bar.fontMono
                                    }
                                    // Optional: how many of this feed are in the current window
                                    Text {
                                        visible: Number(modelData.shown || 0) > 0
                                        text: "·" + String(modelData.shown || 0)
                                        color: bar.subtext
                                        font.pixelSize: 10
                                        font.family: bar.fontMono
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    visible: rowDelegate.isGroup
                                    enabled: rowDelegate.isGroup
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.listCursor = index
                                        root.listCursorId = modelData.id || ("grp:" + (modelData.group || ""))
                                        root.toggleGroup(modelData.group || modelData.category || "Other Feeds")
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    visible: rowDelegate.isHeader
                                    enabled: rowDelegate.isHeader
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.listCursor = index
                                        root.listCursorId = modelData.id || ("hdr:" + (modelData.category || ""))
                                        root.toggleCategory(modelData.category || "Other")
                                    }
                                }

                                // Date sub-header under an open feed (click to collapse that day)
                                RowLayout {
                                    visible: rowDelegate.isDate
                                    anchors.fill: parent
                                    anchors.leftMargin: 22
                                    anchors.rightMargin: 8
                                    spacing: 6
                                    Text {
                                        text: modelData.collapsed ? "▸" : "▾"
                                        color: bar.subtext
                                        font.pixelSize: 11
                                        Layout.preferredWidth: 12
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.dateLabel || modelData.dateKey || "Date"
                                        color: bar.subtext
                                        font.pixelSize: 11
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    // unread / total for that day (from loaded list)
                                    Text {
                                        text: {
                                            const u = Number(modelData.unread || 0)
                                            const s = Number(modelData.shown || 0)
                                            if (u > 0 && s > 0 && u !== s)
                                                return u + "/" + s
                                            if (u > 0)
                                                return String(u)
                                            return String(s)
                                        }
                                        color: Number(modelData.unread || 0) > 0 ? bar.accent : (bar.subtext)
                                        font.pixelSize: 10
                                        font.bold: Number(modelData.unread || 0) > 0
                                        font.family: bar.fontMono
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    visible: rowDelegate.isDate
                                    enabled: rowDelegate.isDate
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.listCursor = index
                                        root.listCursorId = modelData.id || ""
                                        root.toggleDateGroup(modelData.category, modelData.dateKey)
                                    }
                                }

                                // Article content (indented under date)
                                Column {
                                    id: titleCol
                                    visible: rowDelegate.isItem
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: 28
                                    anchors.rightMargin: 8
                                    spacing: 2

                                    RowLayout {
                                        width: parent.width
                                        spacing: 6
                                        Text {
                                            visible: rowDelegate.art && root.itemIsVideo(rowDelegate.art)
                                            text: "▶"
                                            color: bar.accent
                                            font.pixelSize: 11
                                            font.bold: true
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: (rowDelegate.art && rowDelegate.art.title) ? rowDelegate.art.title : "(no title)"
                                            color: bar.text
                                            font.pixelSize: 13
                                            font.bold: rowDelegate.art ? Number(rowDelegate.art.is_read) !== 1 : false
                                            elide: Text.ElideRight
                                            wrapMode: Text.NoWrap
                                            maximumLineCount: 2
                                        }
                                    }
                                    Text {
                                        width: parent.width
                                        text: {
                                            if (!rowDelegate.art)
                                                return ""
                                            const g = rowDelegate.art.group_title || ""
                                            const t = root.formatTime(rowDelegate.art.created_on_time)
                                            if (g && t)
                                                return g + " · " + t
                                            return t || g || ""
                                        }
                                        color: bar.subtext
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    id: rowMa
                                    anchors.fill: parent
                                    visible: rowDelegate.isItem
                                    hoverEnabled: rowDelegate.isItem
                                    enabled: rowDelegate.isItem
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.listCursor = index
                                        root.listCursorId = modelData.id || ""
                                        if (rowDelegate.art)
                                            root.selectItemById(rowDelegate.art.id)
                                    }
                                    onDoubleClicked: {
                                        root.listCursor = index
                                        if (rowDelegate.art)
                                            root.activateItem(rowDelegate.art)
                                    }
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: !root.loading && root.filteredItems.length === 0
                                text: root.errorMsg || "No matching items"
                                color: bar.subtext
                                font.pixelSize: 13
                            }
                        }
                    }

                    // Detail
                    Rectangle {
                        id: detailPane
                        SplitView.fillWidth: true
                        SplitView.minimumWidth: root.detailPaneMinWidth
                        radius: 8
                        color: Qt.rgba(0, 0, 0, 0.12)
                        border.width: 1
                        border.color: bar.divider || bar.pillBorder

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                text: root.selectedItem ? (root.selectedItem.title || "") : "Select an article"
                                color: bar.text
                                font.pixelSize: 16
                                font.bold: true
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: !!root.selectedItem
                                text: {
                                    const it = root.selectedItem
                                    if (!it)
                                        return ""
                                    const bits = []
                                    if (it.feed_title)
                                        bits.push(it.feed_title)
                                    if (it.author)
                                        bits.push(it.author)
                                    const t = root.formatTime(it.created_on_time)
                                    if (t)
                                        bits.push(t)
                                    return bits.join(" · ")
                                }
                                color: bar.subtext
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }

                            // Feed/category actions (when cursor is on a feed or article)
                            Flow {
                                Layout.fillWidth: true
                                spacing: 8
                                visible: root.writable && root.cursorFeedContext && root.cursorFeedContext.feed_id

                                Text {
                                    text: (root.cursorFeedContext ? root.cursorFeedContext.category : "") + ":"
                                    color: bar.subtext
                                    font.pixelSize: 12
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Repeater {
                                    model: [
                                        { id: "feed-read", label: "Mark feed read" },
                                        { id: "feed-unread", label: "Mark feed unread" }
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        radius: 6
                                        implicitHeight: 28
                                        implicitWidth: feedActTxt.implicitWidth + 18
                                        color: feedActMa.containsMouse
                                               ? Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.25)
                                               : "transparent"
                                        border.width: 1
                                        border.color: bar.pillBorder
                                        Text {
                                            id: feedActTxt
                                            anchors.centerIn: parent
                                            text: modelData.label
                                            color: bar.text
                                            font.pixelSize: 12
                                        }
                                        MouseArea {
                                            id: feedActMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (modelData.id === "feed-read")
                                                    root.markCategoryRead()
                                                else
                                                    root.markCategoryUnread()
                                            }
                                        }
                                    }
                                }
                            }

                            // Article actions
                            Flow {
                                Layout.fillWidth: true
                                spacing: 8
                                visible: !!root.selectedItem

                                Repeater {
                                    model: {
                                        const it = root.selectedItem
                                        if (!it)
                                            return []
                                        const acts = [
                                            { id: "browser", label: "Open in browser", enabled: !!(it.url) },
                                            // Share = copy article URL to clipboard
                                            { id: "share", label: "󰒲 Share", enabled: !!(it.url) },
                                        ]
                                        // Only show mpv for video articles (YouTube, .m4v, etc.)
                                        if (root.itemIsVideo(it) && root.playableUrl(it)) {
                                            acts.push({
                                                id: "mpv",
                                                label: "Play in mpv",
                                                enabled: true
                                            })
                                        }
                                        if (root.writable) {
                                            acts.push({ id: "read", label: "Mark read", enabled: true })
                                            acts.push({
                                                id: "star",
                                                label: Number(it.is_saved) === 1 ? "Unstar" : "Star",
                                                enabled: true
                                            })
                                        }
                                        return acts
                                    }
                                    delegate: Rectangle {
                                        required property var modelData
                                        radius: 6
                                        implicitHeight: 28
                                        implicitWidth: actTxt.implicitWidth + 18
                                        opacity: modelData.enabled ? 1 : 0.4
                                        color: actMa.containsMouse && modelData.enabled
                                               ? Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.25)
                                               : "transparent"
                                        border.width: 1
                                        border.color: bar.pillBorder
                                        Text {
                                            id: actTxt
                                            anchors.centerIn: parent
                                            text: modelData.label
                                            color: bar.text
                                            font.pixelSize: 12
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: actMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            enabled: modelData.enabled
                                            cursorShape: Qt.PointingHandCursor
                                            ToolTip.visible: containsMouse && modelData.id === "share"
                                            ToolTip.text: "Copy article link to clipboard"
                                            ToolTip.delay: 400
                                            onClicked: {
                                                if (modelData.id === "browser")
                                                    root.openBrowser()
                                                else if (modelData.id === "share")
                                                    root.shareArticleLink()
                                                else if (modelData.id === "mpv")
                                                    root.playMpv()
                                                else if (modelData.id === "read")
                                                    root.markRead()
                                                else if (modelData.id === "star")
                                                    root.starItem()
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: bar.divider || bar.pillBorder
                                visible: !!root.selectedItem
                            }

                            Flickable {
                                id: bodyFlick
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                contentWidth: width
                                contentHeight: bodyText.implicitHeight
                                boundsBehavior: Flickable.StopAtBounds
                                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                                Text {
                                    id: bodyText
                                    width: bodyFlick.width - 4
                                    textFormat: Text.RichText
                                    wrapMode: Text.Wrap
                                    color: bar.text
                                    font.pixelSize: 13
                                    font.family: bar.fontFamily
                                    text: root.selectedItem ? root.bodyHtml(root.selectedItem) : ""
                                    onLinkActivated: (link) => {
                                        // YouTube / video links → mpv; everything else → browser
                                        root.openOrPlayUrl(link)
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: !root.writable
                                text: "Read-only public RSS (API password is empty). Folders like News / Youtube Feeds and feeds like CachyOS won’t appear until you set FreshRSS Profile → API password in Options → FreshRSS."
                                color: bar.subtext
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                // Footer shortcuts
                Text {
                    Layout.fillWidth: true
                    text: "w/s or ↑/↓ list · a/← Space expand · d/→ Enter open · j/k articles · / search · b browser · c share · v mpv · r refresh · Esc"
                          + (root.writable ? " · m item read · Shift+S star · Shift+R feed read · Shift+U feed unread" : "")
                    color: bar.subtext
                    font.pixelSize: 11
                    font.family: bar.fontMono
                    wrapMode: Text.WordWrap
                }
            }

            // Drag region on empty header area — click title bar strip
            MouseArea {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 18
                cursorShape: Qt.SizeAllCursor
                onPressed: readerWindow.startSystemMove()
            }
        }
    }
}
