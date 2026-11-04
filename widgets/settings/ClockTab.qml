import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../../components"

// Settings → Region & Clock. Timezone map and clock format.
ColumnLayout {
    id: root

    required property var bar
    required property bool popupOpen
    required property int menuTick
    required property var systemFontFamilies
    required property int chipR
    required property int chipH
    required property color optFieldBg
    required property color optFieldBgFocus
    required property color onGreen
    required property color offRed
    required property string entryMonoFont
    required property int fontChipWidth
    required property bool clockWidgetOn
    required property color activeLabel
    required property var refreshFonts
    required property var fontIndexFor

    // Parent owns menuTick. Emitting keeps the same write the page used to do.
    signal menuBumped()
    // Parent calls ensureControlFocusGrab(). The map and the format field use it.
    signal focusRequested()
    // Parent calls hide() before the timezone apply timer, so a password prompt is uncovered.
    signal closeRequested()

    property string clockFormatDraft: ""
    // "region" | "clock". Region is the default.
    property string clockTab: "region"

    function reposition() {
    }

    function resetInnerScroll() {
        try {
            if (clockBodyFlick)
                clockBodyFlick.contentY = 0
        } catch (e) {}
    }

    function prepareOpen() {
        root.clockTab = "region"
        root.clockFormatDraft = root.currentClockFormat()
    }

    function coerceTab() {
        if (root.clockTab === "clock" && !root.clockWidgetOn)
            root.clockTab = "region"
    }

    function currentClockFormat() {
        void root.menuTick
        return (bar.clockFormat && String(bar.clockFormat).length)
            ? String(bar.clockFormat)
            : "dddd, MM·dd·yyyy | HH:mm:ss"
    }

    function setClockFormat(fmt) {
        if (typeof bar.setClockFormat === "function")
            bar.setClockFormat(fmt)
        root.clockFormatDraft = String(fmt || "")
        root.menuBumped()
        Qt.callLater(reposition)
    }

    function clockFormatIsPreset(fmt) {
        const want = String(fmt || "")
        const presets = root.clockPresets()
        for (let i = 0; i < presets.length; i++) {
            if (presets[i] && presets[i].format === want)
                return true
        }
        return false
    }

    function applyClockFormatDraft() {
        const fmt = String(root.clockFormatDraft || "").trim()
        if (!fmt.length)
            return
        root.setClockFormat(fmt)
    }

    function currentClockFontName() {
        void root.menuTick
        return (bar && bar.clockFont) ? String(bar.clockFont).trim() : ""
    }

    function clockFontComboModel() {
        void root.menuTick
        const list = root.systemFontFamilies || []
        return ["Bar default"].concat(list)
    }

    function clockFontComboIndex() {
        void root.menuTick
        void root.systemFontFamilies
        const s = root.currentClockFontName()
        if (!s.length)
            return 0
        const i = root.fontIndexFor(s)
        return i < 0 ? 0 : i + 1
    }

    function applyClockFontFromCombo(index) {
        if (!(index > 0)) {
            if (typeof bar.setClockFont === "function")
                bar.setClockFont("")
            root.menuBumped()
            return
        }
        const list = root.systemFontFamilies || []
        const name = list[index - 1]
        if (name && typeof bar.setClockFont === "function")
            bar.setClockFont(name)
        root.menuBumped()
    }

    function currentClockFontScalePct() {
        void root.menuTick
        const s = (bar && bar.clockFontScale !== undefined) ? Number(bar.clockFontScale) : 1
        if (!(s > 0))
            return 100
        return Math.round(Math.max(0.70, Math.min(1.50, s)) * 100)
    }

    function clockPresets() {
        return bar.clockFormatPresets || []
    }

    function presetRows() {
        void root.menuTick
        const presets = root.clockPresets()
        const out = []
        const activeBorder = root.activeLabel
        const idleBorder = root.bar.dividerStrong
        const text = root.bar.text
        const sub = root.bar.subtext
        const font = root.bar.fontFamily
        const hover = root.bar.popupButtonHoverBg
        const idle = Qt.rgba(0.10, 0.10, 0.12, 0.55)
        for (let i = 0; i < presets.length; i++) {
            const p = presets[i]
            const active = root.currentClockFormat() === p.format
            out.push({
                label: (p.label || "") + (active ? "  · active" : ""),
                tip: p.tip || p.format || "",
                format: p.format,
                active: active,
                radius: root.chipR,
                hoverBg: hover,
                idleBg: idle,
                borderWidth: root.bar.controlBorderWidth,
                activeBorder: activeBorder,
                idleBorder: idleBorder,
                titleColor: active ? activeBorder : text,
                tipColor: sub,
                font: font,
                pick: function (fmt) { root.setClockFormat(fmt) }
            })
        }
        return out
    }

    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: 8

    Text {
        text: "Region & Clock"
        color: root.bar.text
        font.pixelSize: root.bar.popupTitleSize
        font.bold: true
        font.family: root.bar.fontFamily
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Rectangle {
            id: regionChip
            readonly property bool on: root.clockTab === "region"
            Layout.preferredHeight: root.chipH
            Layout.preferredWidth: regionTabLbl.implicitWidth + 16
            radius: 6
            color: regionChip.on ? Qt.rgba(root.bar.accent.r, root.bar.accent.g, root.bar.accent.b, 0.22)
                      : (regionTabMa.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
            border.width: 1
            border.color: regionChip.on ? root.bar.accent : root.bar.pillBorder
            Text {
                id: regionTabLbl
                anchors.centerIn: parent
                text: "Region"
                color: regionChip.on ? root.bar.accent : root.bar.subtext
                font.pixelSize: 11
                font.bold: regionChip.on
                font.family: root.bar.fontFamily
            }
            MouseArea {
                id: regionTabMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.clockTab = "region"
                    root.menuBumped()
                    Qt.callLater(root.reposition)
                }
            }
        }
        Rectangle {
            id: clockChip
            visible: root.clockWidgetOn
            readonly property bool on: root.clockTab === "clock"
            Layout.preferredHeight: root.chipH
            Layout.preferredWidth: clockFaceTabLbl.implicitWidth + 16
            radius: 6
            color: clockChip.on ? Qt.rgba(root.bar.accent.r, root.bar.accent.g, root.bar.accent.b, 0.22)
                      : (clockFaceTabMa.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
            border.width: 1
            border.color: clockChip.on ? root.bar.accent : root.bar.pillBorder
            Text {
                id: clockFaceTabLbl
                anchors.centerIn: parent
                text: "Clock"
                color: clockChip.on ? root.bar.accent : root.bar.subtext
                font.pixelSize: 11
                font.bold: clockChip.on
                font.family: root.bar.fontFamily
            }
            MouseArea {
                id: clockFaceTabMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.clockTab = "clock"
                    root.refreshFonts()
                    root.menuBumped()
                    Qt.callLater(root.reposition)
                }
            }
        }
        Item { Layout.fillWidth: true }
    }

    TimezoneMapView {
        id: clockTzMap
        visible: root.clockTab === "region"
        Layout.fillWidth: true
        Layout.fillHeight: visible
        Layout.minimumHeight: visible ? 200 : 0
        active: visible && root.visible && root.popupOpen
        keyboardGrab: function() { root.focusRequested() }
        beforeApply: function() { root.closeRequested() }
        textColor: root.bar.text
        subtextColor: root.bar.subtext
        accentColor: root.bar.accent
        surfaceColor: root.bar.surface !== undefined ? root.bar.surface : Qt.rgba(0.10, 0.12, 0.18, 0.9)
        oceanColor: "#8aa0b5"
        landColor: "#e7e2d6"
        highlightColor: "#6fbf3a"
        gridColor: Qt.rgba(1, 1, 1, 0.16)
        fieldBg: root.optFieldBg
        fieldBgFocus: root.optFieldBgFocus
        pillBorder: root.bar.pillBorder
        okColor: root.onGreen
        errorColor: root.offRed
        fontFamily: root.bar.fontFamily
        fontMono: root.bar.fontMono !== undefined ? root.bar.fontMono : root.bar.fontFamily
        chipR: root.chipR
    }

    Flickable {
        id: clockBodyFlick
        visible: root.clockTab === "clock"
        Layout.fillWidth: true
        Layout.fillHeight: visible
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        contentWidth: width
        contentHeight: clockBodyCol.implicitHeight
        interactive: contentHeight > height + 4
        ScrollBar.vertical: ScrollBar {
            policy: clockBodyFlick.contentHeight > clockBodyFlick.height + 4
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
            id: clockBodyCol
            width: clockBodyFlick.width
            spacing: 8

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Clock face font"
                color: root.bar.text
                font.pixelSize: 12
                font.bold: true
                font.family: root.bar.fontFamily
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                ComboBox {
                    id: clockFaceFontCombo
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    Layout.minimumWidth: 120
                    model: root.clockFontComboModel()
                    currentIndex: root.clockFontComboIndex()
                    onActivated: function(index) { root.applyClockFontFromCombo(index) }
                    contentItem: Text {
                        leftPadding: 10
                        rightPadding: clockFaceFontCombo.indicator.width + 12
                        text: clockFaceFontCombo.displayText
                        color: (root.bar.barText !== undefined) ? root.bar.barText : root.bar.text
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        font.family: root.currentClockFontName().length
                                     ? root.currentClockFontName()
                                     : ((root.bar.fontBarResolved !== undefined) ? root.bar.fontBarResolved : root.bar.fontFamily)
                    }
                    background: Rectangle {
                        radius: 6
                        color: root.optFieldBg
                        border.width: 1
                        border.color: clockFaceFontCombo.popup.visible ? root.bar.accent : root.bar.pillBorder
                    }
                    indicator: Text {
                        x: clockFaceFontCombo.width - width - 10
                        y: (clockFaceFontCombo.height - height) / 2
                        text: clockFaceFontCombo.popup.visible ? "▴" : "▾"
                        color: root.bar.subtext
                        font.pixelSize: 11
                    }
                    popup: Popup {
                        y: clockFaceFontCombo.height + 2
                        width: clockFaceFontCombo.width
                        implicitHeight: Math.min(260, contentItem.implicitHeight + 4)
                        padding: 2
                        contentItem: ListView {
                            clip: true
                            implicitHeight: contentHeight
                            property int rowWidth: clockFaceFontCombo.width
                            property color rowText: (root.bar.barText !== undefined) ? root.bar.barText : root.bar.text
                            property string defaultFont: root.bar.fontFamily
                            property color rowActive: root.bar.controlActiveBg !== undefined ? root.bar.controlActiveBg : Qt.rgba(0, 0.7, 0.75, 0.35)
                            model: clockFaceFontCombo.popup.visible ? clockFaceFontCombo.delegateModel : null
                            currentIndex: clockFaceFontCombo.highlightedIndex
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        }
                        background: Rectangle {
                            radius: 8
                            color: root.bar.glassPopupBg !== undefined ? root.bar.glassPopupBg : Qt.rgba(0.06, 0.08, 0.12, 0.96)
                            border.width: 1
                            border.color: root.bar.glassPopupBorder !== undefined ? root.bar.glassPopupBorder : root.bar.pillBorder
                        }
                    }
                    delegate: Component {
                        ClockFontRow {}
                    }
                }
                Rectangle {
                    Layout.preferredWidth: root.fontChipWidth
                    Layout.maximumWidth: root.fontChipWidth
                    Layout.preferredHeight: 34
                    radius: root.chipR
                    color: Qt.rgba(0.08, 0.10, 0.14, 0.55)
                    border.width: 1
                    border.color: root.bar.dividerStrong
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 4
                        OptValueSlider {
                            bar: root.bar
                            fieldBg: root.optFieldBg
                            fieldBgFocus: root.optFieldBgFocus
                            from: 70
                            to: 150
                            stepSize: 1
                            suffix: "%"
                            value: root.currentClockFontScalePct()
                            onValueEdited: (v) => {
                                if (typeof root.bar.setClockFontScale === "function")
                                    root.bar.setClockFontScale(Math.round(v) / 100)
                                root.menuBumped()
                            }
                            onValueCommitted: (v) => {
                                if (typeof root.bar.setClockFontScale === "function")
                                    root.bar.setClockFontScale(Math.round(v) / 100)
                            }
                        }
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Presets stay as they are. Custom uses Qt format tokens (HH:mm:ss, dddd, MMM d yyyy, AP)."
                color: root.bar.subtext
                font.pixelSize: 11
                font.family: root.bar.fontFamily
            }

            Repeater {
                model: root.presetRows()
                delegate: ClockPresetRow {}
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: customFmtCol.implicitHeight + 14
                radius: root.chipR
                color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                border.width: root.bar.controlBorderWidth
                border.color: root.clockFormatIsPreset(root.currentClockFormat())
                              ? root.bar.dividerStrong
                              : root.activeLabel
                ColumnLayout {
                    id: customFmtCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 8
                    spacing: 6
                    Text {
                        text: "Custom" + (root.clockFormatIsPreset(root.currentClockFormat()) ? "" : "  · active")
                        color: root.clockFormatIsPreset(root.currentClockFormat())
                               ? root.bar.text
                               : root.activeLabel
                        font.pixelSize: 12
                        font.bold: !root.clockFormatIsPreset(root.currentClockFormat())
                        font.family: root.bar.fontFamily
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        TextField {
                            topPadding: 1
                            bottomPadding: 1
                            verticalAlignment: Text.AlignVCenter
                            id: clockFmtField
                            Layout.fillWidth: true
                            Layout.preferredHeight: 30
                            text: root.clockFormatDraft
                            placeholderText: "e.g. ddd HH:mm"
                            color: root.bar.text
                            placeholderTextColor: root.bar.subtext
                            font.pixelSize: 14
                            font.family: root.entryMonoFont
                            background: Rectangle {
                                radius: root.chipR
                                color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
                                border.width: 1
                                border.color: clockFmtField.activeFocus ? root.bar.accent : root.bar.pillBorder
                            }
                            onPressed: root.focusRequested()
                            onActiveFocusChanged: if (activeFocus) root.focusRequested()
                            onTextChanged: root.clockFormatDraft = text
                            Keys.onReturnPressed: root.applyClockFormatDraft()
                            Keys.onEnterPressed: root.applyClockFormatDraft()
                        }
                        Rectangle {
                            Layout.preferredHeight: 30
                            Layout.preferredWidth: setFmtLbl.implicitWidth + 14
                            radius: root.chipR
                            color: setFmtMa.containsMouse ? root.bar.glassHover : (root.bar.buttonBg !== undefined ? root.bar.buttonBg : root.bar.pillBg)
                            border.width: 1
                            border.color: setFmtMa.containsMouse ? root.bar.accent : root.bar.pillBorder
                            Text {
                                id: setFmtLbl
                                anchors.centerIn: parent
                                text: "Set"
                                color: root.bar.text
                                font.pixelSize: 12
                                font.family: root.bar.fontFamily
                            }
                            MouseArea {
                                id: setFmtMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.applyClockFormatDraft()
                            }
                        }
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: clockPreviewCol.implicitHeight + 20
                radius: root.chipR
                color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                border.width: 1
                border.color: root.bar.accent
                ColumnLayout {
                    id: clockPreviewCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 4
                    Text {
                        text: "Preview"
                        color: root.bar.subtext
                        font.pixelSize: 11
                        font.family: root.bar.fontFamily
                    }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: Qt.formatDateTime(new Date(), String(root.clockFormatDraft || root.currentClockFormat() || "ddd HH:mm"))
                        color: root.bar.text
                        font.pixelSize: 28
                        font.bold: true
                        font.family: root.bar.fontFamily
                    }
                }
            }
    }
    }
}
