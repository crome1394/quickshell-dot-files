import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../../components"

// Settings → Widgets. Visibility, zone, order, and width scale.
ColumnLayout {
    id: root

    required property var bar
    required property int menuTick
    required property int chipR
    required property int bodyScrollBarW
    required property int bodyScrollGutter
    required property color onGreen
    required property color offRed
    required property color optFieldBg
    required property color optFieldBgFocus
    required property color activeLabel

    // Parent owns menuTick. Emitting keeps the same write the page used to do.
    signal menuBumped()
    // Parent restarts sizeRepositionTimer. Dragging must not bump menuTick.
    signal scaleNudged()

    function reposition() {
    }

    function resetInnerScroll() {
        try {
            if (widgetsBodyFlick)
                widgetsBodyFlick.contentY = 0
        } catch (e) {}
    }

    function isWidgetOn(id) {
        void root.menuTick
        if (typeof bar.getWidgetVisible === "function")
            return !!bar.getWidgetVisible(id)
        return false
    }

    function toggleWidget(id) {
        if (typeof bar.toggleWidgetVisible === "function")
            bar.toggleWidgetVisible(id)
        root.menuBumped()
        // Keep panel open; only refresh list state
        Qt.callLater(reposition)
    }

    function activeWindowCorner() {
        void root.menuTick
        if (bar && bar.activeWindowPillCorner !== undefined) {
            const c = String(bar.activeWindowPillCorner || "")
            if (c === "topRight" || c === "bottomLeft" || c === "bottomRight")
                return c
        }
        return "topLeft"
    }

    function activeWindowCornerChoices() {
        return [
            { id: "topLeft",     label: "Top left",     tip: "Place the active-window pill in the top-left corner" },
            { id: "topRight",    label: "Top right",    tip: "Place the active-window pill in the top-right corner" },
            { id: "bottomLeft",  label: "Bottom left",  tip: "Place the active-window pill in the bottom-left corner" },
            { id: "bottomRight", label: "Bottom right", tip: "Place the active-window pill in the bottom-right corner" }
        ]
    }

    function setActiveWindowCorner(corner) {
        if (typeof bar.setActiveWindowCorner === "function")
            bar.setActiveWindowCorner(corner)
        root.menuBumped()
        Qt.callLater(reposition)
    }

    // Widget list for the combined Widgets panel (layout + visibility + scale).
    function widgetEntries() {
        void root.menuTick
        void bar.widgetScales
        const layout = bar.widgetLayout
        const cat = bar.widgetCatalog || []
        const labels = {}
        for (let i = 0; i < cat.length; i++)
            labels[cat[i].id] = cat[i].label
        const out = []
        if (layout && layout.length) {
            for (let i = 0; i < layout.length; i++) {
                const e = layout[i]
                const div = !!(bar && typeof bar.isDividerId === "function" && bar.isDividerId(e.id))
                out.push({
                    id: e.id,
                    zone: e.zone,
                    index: i,
                    label: div ? ("|  Divider " + String(e.id).replace("divider", "")) : (labels[e.id] || e.id),
                    on: root.isWidgetOn(e.id),
                    divider: div
                })
            }
        } else {
            for (let i = 0; i < cat.length; i++) {
                out.push({
                    id: cat[i].id,
                    zone: (bar.barLayoutMode === "dual") ? "bottom" : "right",
                    index: i,
                    label: cat[i].label,
                    on: root.isWidgetOn(cat[i].id)
                })
            }
        }
        // Zone groups (T→B or L→C→R), then live bar order inside the zone
        // (same sequence as applyWidgetLayout — not A–Z).
        out.sort(function (a, b) {
            const dual = bar.barLayoutMode === "dual"
            const zoneOrder = dual
                ? { top: 0, bottom: 1, left: 2, right: 3 }
                : { left: 0, center: 1, right: 2 }
            const za = zoneOrder[a.zone] !== undefined ? zoneOrder[a.zone] : 9
            const zb = zoneOrder[b.zone] !== undefined ? zoneOrder[b.zone] : 9
            if (za !== zb)
                return za - zb
            const ia = (a.index !== undefined) ? a.index : 0
            const ib = (b.index !== undefined) ? b.index : 0
            return ia - ib
        })
        return out
    }

    function widgetZoneSections() {
        void root.menuTick
        if (bar && bar.barLayoutMode === "dual")
            return [
                { id: "top", title: "Top bar", hint: "Upper strip, left to right" },
                { id: "bottom", title: "Bottom bar", hint: "Lower strip, left to right" },
                { id: "left", title: "Left bar", hint: "Left edge, top to bottom" },
                { id: "right", title: "Right bar", hint: "Right edge, top to bottom" }
            ]
        return [
            { id: "left", title: "Left", hint: "Left side of the bar, left to right" },
            { id: "center", title: "Center", hint: "Middle of the bar, left to right" },
            { id: "right", title: "Right", hint: "Right side of the bar, left to right" }
        ]
    }

    function widgetEntriesInZone(zone) {
        const all = root.widgetEntries()
        const out = []
        for (let i = 0; i < all.length; i++) {
            if (all[i].zone === zone)
                out.push(all[i])
        }
        return out
    }

    function zoneChoices() {
        void root.menuTick
        if (bar && bar.barLayoutMode === "dual")
            return [
                { id: "top", label: "T" },
                { id: "bottom", label: "B" },
                { id: "left", label: "L" },
                { id: "right", label: "R" }
            ]
        return [
            { id: "left", label: "L" },
            { id: "center", label: "C" },
            { id: "right", label: "R" }
        ]
    }

    function scalePercentOf(id) {
        // Depend on widgetScales so bindings refresh without menuTick thrash
        void bar.widgetScales
        if (typeof bar.widgetScale === "function")
            return Math.round(bar.widgetScale(id) * 100)
        return 100
    }

    function setScalePercent(id, percent) {
        let p = Number(percent)
        if (!(p > 0))
            return
        if (p < 80)
            p = 80
        if (p > 180)
            p = 180
        if (typeof bar.setWidgetScale === "function")
            bar.setWidgetScale(id, p / 100)
        // Do not bump menuTick / full panel rebuild while dragging — bar.widgetScales notifies
        root.scaleNudged()
    }

    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: 7

    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: "Widgets"
            color: bar.text
            font.pixelSize: bar.popupTitleSize
            font.bold: true
            font.family: bar.fontFamily
        }
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: (bar.barLayoutMode === "dual")
              ? "Grouped by bar. ✓/✕ · name · T/B/L/R · ↑↓ · width % (80–180)"
              : "Grouped by side. ✓/✕ · name · L/C/R · ↑↓ · width % (80–180)"
        color: bar.subtext
        font.pixelSize: bar.popupHintSize
        font.family: bar.fontFamily
    }

    Flickable {
        id: widgetsBodyFlick
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        contentWidth: width
        contentHeight: widgetsBodyCol.implicitHeight
        interactive: contentHeight > height + 4
        ScrollBar.vertical: ScrollBar {
            policy: widgetsBodyFlick.contentHeight > widgetsBodyFlick.height + 4
                    ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            width: root.bodyScrollBarW
            padding: 2
            contentItem: Rectangle {
                implicitWidth: 6
                radius: 3
                color: bar.accent
                opacity: 0.5
            }
            background: Rectangle {
                implicitWidth: root.bodyScrollBarW
                radius: 4
                color: Qt.rgba(1, 1, 1, 0.06)
            }
        }
        ColumnLayout {
            id: widgetsBodyCol
            width: Math.max(1, widgetsBodyFlick.width - root.bodyScrollGutter)
            spacing: 14

    Component {
        id: widgetRowCard
        Rectangle {
            id: widgetRow
            required property var modelData
            readonly property string widgetId: modelData.id
            readonly property string widgetZone: modelData.zone
            readonly property string widgetLabel: modelData.label
            readonly property bool widgetOn: modelData.on
            readonly property bool widgetDivider: !!modelData.divider
            readonly property int livePct: root.scalePercentOf(widgetId)
            property int localPct: livePct
            property bool editing: false

            Layout.fillWidth: true
            Layout.preferredHeight: widgetRow.widgetDivider ? 40 : 58
            radius: root.chipR
            color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
            border.width: bar.controlBorderWidth
            border.color: bar.dividerStrong
            opacity: widgetRow.widgetOn ? 1.0 : 0.78

            onLivePctChanged: {
                if (!widgetRow.editing)
                    widgetRow.localPct = livePct
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 6
                anchors.topMargin: 5
                anchors.bottomMargin: 5
                spacing: 4

                // Row 1 — three columns: [✓ name] | [L C R] | [↑ ↓]
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    // Column 1: toggle + full name
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 120
                        spacing: 6

                        Rectangle {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 24
                            Layout.alignment: Qt.AlignVCenter
                            radius: 4
                            color: visMa.containsMouse
                                   ? (widgetRow.widgetOn
                                      ? Qt.rgba(0.29, 0.87, 0.50, 0.18)
                                      : Qt.rgba(0.97, 0.44, 0.44, 0.18))
                                   : "transparent"
                            border.width: 1
                            border.color: widgetRow.widgetOn ? root.onGreen : root.offRed
                            Text {
                                anchors.centerIn: parent
                                text: widgetRow.widgetOn ? "✓" : "✕"
                                color: widgetRow.widgetOn ? root.onGreen : root.offRed
                                font.pixelSize: 14
                                font.bold: true
                                font.family: bar.fontFamily
                            }
                            MouseArea {
                                id: visMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleWidget(widgetRow.widgetId)
                                ToolTip.visible: containsMouse
                                ToolTip.delay: bar.tooltipDelay
                                ToolTip.text: widgetRow.widgetOn ? "Hide from bar" : "Show on bar"
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 72
                            // Prefer full labels; elide only if panel is extremely narrow
                            elide: Text.ElideRight
                            text: widgetRow.widgetLabel
                            color: bar.text
                            font.pixelSize: 12
                            font.family: bar.fontFamily
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    // Column 2: zone L C R (classic) or T B L R (dual)
                    RowLayout {
                        readonly property int zoneBtnCount: root.zoneChoices().length
                        Layout.preferredWidth: zoneBtnCount * 22 + (zoneBtnCount - 1) * 4
                        Layout.maximumWidth: zoneBtnCount * 22 + (zoneBtnCount - 1) * 4
                        Layout.minimumWidth: zoneBtnCount * 22 + (zoneBtnCount - 1) * 4
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 4

                        Repeater {
                            model: root.zoneChoices()
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool zoneOn: widgetRow.widgetZone === modelData.id
                                Layout.preferredWidth: 22
                                Layout.preferredHeight: 22
                                radius: 4
                                color: zoneOn ? bar.controlActiveBg : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                border.width: 1
                                border.color: zoneOn ? root.activeLabel : bar.pillBorder
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    font.pixelSize: 10
                                    font.family: bar.fontFamily
                                    color: zoneOn ? root.activeLabel : bar.subtext
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (typeof bar.setWidgetZone === "function")
                                            bar.setWidgetZone(widgetRow.widgetId, modelData.id)
                                        root.menuBumped()
                                        Qt.callLater(root.reposition)
                                    }
                                }
                            }
                        }
                    }

                    // Column 3: reorder ↑ ↓
                    RowLayout {
                        Layout.preferredWidth: 52
                        Layout.maximumWidth: 52
                        Layout.minimumWidth: 52
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 4

                        Rectangle {
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            radius: 4
                            color: upMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                            border.width: 1
                            border.color: bar.pillBorder
                            Text {
                                anchors.centerIn: parent
                                text: "↑"
                                color: bar.subtext
                                font.pixelSize: 12
                            }
                            MouseArea {
                                id: upMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (typeof bar.moveWidget === "function")
                                        bar.moveWidget(widgetRow.widgetId, -1)
                                    root.menuBumped()
                                    Qt.callLater(root.reposition)
                                }
                            }
                        }
                        Rectangle {
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            radius: 4
                            color: dnMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                            border.width: 1
                            border.color: bar.pillBorder
                            Text {
                                anchors.centerIn: parent
                                text: "↓"
                                color: bar.subtext
                                font.pixelSize: 12
                            }
                            MouseArea {
                                id: dnMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (typeof bar.moveWidget === "function")
                                        bar.moveWidget(widgetRow.widgetId, 1)
                                    root.menuBumped()
                                    Qt.callLater(root.reposition)
                                }
                            }
                        }
                    }
                }

                // Row 2: horizontal width scale
                RowLayout {
                    visible: !widgetRow.widgetDivider
                    Layout.fillWidth: true
                    spacing: 6

                    OptValueSlider {
                        bar: bar
                        fieldBg: root.optFieldBg
                        fieldBgFocus: root.optFieldBgFocus
                        from: 80
                        to: 180
                        stepSize: 5
                        suffix: "%"
                        value: widgetRow.localPct
                        onValueEdited: (v) => {
                            widgetRow.localPct = Math.round(v)
                            root.setScalePercent(widgetRow.widgetId, widgetRow.localPct)
                        }
                        onValueCommitted: (v) => {
                            widgetRow.localPct = Math.round(v)
                            root.setScalePercent(widgetRow.widgetId, widgetRow.localPct)
                        }
                    }
                }
            }
        }
    } // widgetRowCard

    Component {
        id: zoneSection
        ColumnLayout {
                required property var modelData
                required property int index
                readonly property var zoneWidgets: {
                    void root.menuTick
                    return root.widgetEntriesInZone(modelData.id)
                }
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignTop
                spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 3
                    Layout.preferredHeight: 28
                    radius: 2
                    color: bar.accent
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                        text: modelData.title
                        color: bar.text
                        font.pixelSize: 13
                        font.bold: true
                        font.family: bar.fontFamily
                    }
                    Text {
                        Layout.fillWidth: true
                        text: modelData.hint
                        color: bar.subtext
                        font.pixelSize: 10
                        font.family: bar.fontFamily
                        wrapMode: Text.WordWrap
                    }
                }

                Rectangle {
                    Layout.preferredHeight: 22
                    Layout.preferredWidth: Math.max(28, zoneCountLbl.implicitWidth + 12)
                    radius: 11
                    color: Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.14)
                    border.width: 1
                    border.color: Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.28)
                    Text {
                        id: zoneCountLbl
                        anchors.centerIn: parent
                        text: String(zoneWidgets.length)
                        color: bar.accent
                        font.pixelSize: 11
                        font.bold: true
                        font.family: bar.fontFamily
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: zoneInner.implicitHeight + 16
                radius: 10
                color: Qt.rgba(1, 1, 1, 0.035)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)

                ColumnLayout {
                    id: zoneInner
                    x: 8
                    y: 8
                    width: parent.width - 16
                    spacing: 6

                    Repeater {
                        model: zoneWidgets
                        delegate: widgetRowCard
                    }

                    Text {
                        visible: zoneWidgets.length === 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: (bar.barLayoutMode === "dual")
                              ? "Nothing here yet — use T/B/L/R on a widget to move it."
                              : "Nothing here yet — use L/C/R on a widget to move it."
                        color: bar.subtext
                        font.pixelSize: 11
                        font.family: bar.fontFamily
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 16
        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.minimumWidth: 0
            Layout.alignment: Qt.AlignTop
            spacing: 16
            Repeater {
                model: {
                    void root.menuTick
                    const all = root.widgetZoneSections()
                    if (bar && bar.barLayoutMode === "dual")
                        return all.slice(0, 2)
                    return all
                }
                delegate: zoneSection
            }
        }
        ColumnLayout {
            visible: bar && bar.barLayoutMode === "dual"
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.minimumWidth: 0
            Layout.alignment: Qt.AlignTop
            spacing: 16
            Repeater {
                model: {
                    void root.menuTick
                    const all = root.widgetZoneSections()
                    if (!(bar && bar.barLayoutMode === "dual"))
                        return []
                    return all.slice(2)
                }
                delegate: zoneSection
            }
        }
    }

    // ===== OTHER (screen-corner overlays) =====
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 3
                Layout.preferredHeight: 28
                radius: 2
                color: bar.accent
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    text: "Other"
                    color: bar.text
                    font.pixelSize: 13
                    font.bold: true
                    font.family: bar.fontFamily
                }
                Text {
                    Layout.fillWidth: true
                    text: "Overlays placed in a screen corner, outside the bar."
                    color: bar.subtext
                    font.pixelSize: 10
                    font.family: bar.fontFamily
                    wrapMode: Text.WordWrap
                }
            }

            Rectangle {
                Layout.preferredHeight: 22
                Layout.preferredWidth: Math.max(28, otherCountLbl.implicitWidth + 12)
                radius: 11
                color: Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.14)
                border.width: 1
                border.color: Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.28)
                Text {
                    id: otherCountLbl
                    anchors.centerIn: parent
                    text: "1"
                    color: bar.accent
                    font.pixelSize: 11
                    font.bold: true
                    font.family: bar.fontFamily
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: otherInner.implicitHeight + 16
            radius: 10
            color: Qt.rgba(1, 1, 1, 0.035)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            ColumnLayout {
                id: otherInner
                x: 8
                y: 8
                width: parent.width - 16
                spacing: 6

                Rectangle {
                    id: activeWindowRow
                    readonly property bool activeWindowOn: root.isWidgetOn("activeWindow")
                    readonly property string activeCorner: root.activeWindowCorner()

                    Layout.fillWidth: true
                    Layout.preferredHeight: 58
                    radius: root.chipR
                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                    border.width: bar.controlBorderWidth
                    border.color: bar.dividerStrong
                    opacity: activeWindowOn ? 1.0 : 0.78

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 6
                        anchors.topMargin: 5
                        anchors.bottomMargin: 5
                        spacing: 10

                        // Toggle + name
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 120
                            spacing: 6

                            Rectangle {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 24
                                Layout.alignment: Qt.AlignVCenter
                                radius: 4
                                color: awVisMa.containsMouse
                                       ? (activeWindowRow.activeWindowOn
                                          ? Qt.rgba(0.29, 0.87, 0.50, 0.18)
                                          : Qt.rgba(0.97, 0.44, 0.44, 0.18))
                                       : "transparent"
                                border.width: 1
                                border.color: activeWindowRow.activeWindowOn ? root.onGreen : root.offRed
                                Text {
                                    anchors.centerIn: parent
                                    text: activeWindowRow.activeWindowOn ? "✓" : "✕"
                                    color: activeWindowRow.activeWindowOn ? root.onGreen : root.offRed
                                    font.pixelSize: 14
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                MouseArea {
                                    id: awVisMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleWidget("activeWindow")
                                    ToolTip.visible: containsMouse
                                    ToolTip.delay: bar.tooltipDelay
                                    ToolTip.text: activeWindowRow.activeWindowOn
                                                  ? "Hide the active-window pill"
                                                  : "Show the active-window pill"
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 72
                                elide: Text.ElideRight
                                text: "Active Window"
                                color: bar.text
                                font.pixelSize: 12
                                font.family: bar.fontFamily
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        // Screen corner
                        RowLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 4

                            Repeater {
                                model: root.activeWindowCornerChoices()
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool cornerOn: activeWindowRow.activeCorner === modelData.id

                                    Layout.preferredWidth: cornerLbl.implicitWidth + 18
                                    Layout.preferredHeight: 24
                                    radius: 4
                                    color: cornerOn
                                           ? bar.controlActiveBg
                                           : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                    border.width: 1
                                    border.color: cornerOn ? root.activeLabel : bar.pillBorder

                                    Text {
                                        id: cornerLbl
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        font.pixelSize: 10
                                        font.family: bar.fontFamily
                                        color: cornerOn ? root.activeLabel : bar.subtext
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.setActiveWindowCorner(modelData.id)
                                        ToolTip.visible: containsMouse
                                        ToolTip.delay: bar.tooltipDelay
                                        ToolTip.text: modelData.tip
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

        } // widgetsBodyCol
    } // widgetsBodyFlick

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Item { Layout.fillWidth: true }
        Rectangle {
            Layout.preferredHeight: 24
            Layout.preferredWidth: addDivLbl.implicitWidth + 12
            radius: root.chipR
            color: addDivMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
            border.width: bar.controlBorderWidth
            border.color: bar.pillBorder
            Text {
                id: addDivLbl
                anchors.centerIn: parent
                text: "Add  |"
                color: bar.subtext
                font.pixelSize: 11
                font.family: bar.fontFamily
            }
            MouseArea {
                id: addDivMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (typeof bar.addWidgetDivider === "function")
                        bar.addWidgetDivider()
                    root.menuBumped()
                    Qt.callLater(root.reposition)
                }
            }
        }
        Rectangle {
            Layout.preferredHeight: 24
            Layout.preferredWidth: resetLbl.implicitWidth + 12
            radius: root.chipR
            color: resetMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
            border.width: bar.controlBorderWidth
            border.color: bar.pillBorder
            Text {
                id: resetLbl
                anchors.centerIn: parent
                text: "Reset layout"
                color: bar.subtext
                font.pixelSize: 11
                font.family: bar.fontFamily
            }
            MouseArea {
                id: resetMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (typeof bar.resetWidgetLayout === "function")
                        bar.resetWidgetLayout()
                    root.menuBumped()
                    Qt.callLater(root.reposition)
                }
            }
        }
        Rectangle {
            Layout.preferredHeight: 24
            Layout.preferredWidth: resetSizesLbl.implicitWidth + 12
            radius: root.chipR
            color: resetSizesMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
            border.width: 1
            border.color: bar.pillBorder
            Text {
                id: resetSizesLbl
                anchors.centerIn: parent
                text: "Reset sizes"
                color: bar.subtext
                font.pixelSize: 11
                font.family: bar.fontFamily
            }
            MouseArea {
                id: resetSizesMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (typeof bar.resetWidgetScales === "function")
                        bar.resetWidgetScales()
                    root.menuBumped()
                    Qt.callLater(root.reposition)
                }
            }
        }
    }
}
