import QtQuick
import QtQuick.Controls

// Workspace font box. The closed control shows the chosen face. The popup
// searches the installed list so the full catalog does not have to be scrolled.
ComboBox {
    id: combo

    required property var bar
    required property var host
    property string fontName: ""
    signal fontPicked(string name)
    property string query: ""
    property int hi: 0
    property var shownFonts: []

    function rebuild() {
        const q = String(query || "").trim().toLowerCase()
        const all = (host && typeof host.wsFontChoices === "function") ? host.wsFontChoices() : []
        const out = []
        for (let i = 0; i < all.length; i++) {
            const face = String(all[i])
            if (!q.length || face.toLowerCase().indexOf(q) !== -1)
                out.push(face)
        }
        shownFonts = out
        if (hi >= out.length)
            hi = Math.max(0, out.length - 1)
    }
    function pick(name) {
        const n = String(name || "")
        fontPicked(n === "Bar font" ? "" : n)
        popup.close()
    }
    function acceptHi() {
        const list = shownFonts || []
        if (!list.length)
            return
        const i = Math.max(0, Math.min(list.length - 1, hi))
        pick(list[i])
    }
    onQueryChanged: {
        hi = 0
        rebuild()
    }

    // The closed box must not size itself to the longest installed face.
    // That width was squeezing the label field down to a few pixels, so the
    // tail of the label (for example "ng" from Coding) painted outside the card.
    implicitWidth: 160
    implicitHeight: 28
    model: (host && typeof host.wsFontChoices === "function") ? host.wsFontChoices() : []
    currentIndex: (host && typeof host.wsFontComboIndex === "function") ? host.wsFontComboIndex(fontName) : 0
    contentItem: Text {
        leftPadding: 8
        rightPadding: combo.indicator ? combo.indicator.width + 10 : 18
        text: combo.fontName.length ? combo.fontName : "Bar font"
        font.pixelSize: 12
        font.family: combo.fontName.length ? combo.fontName : combo.bar.fontFamily
        color: combo.bar.text
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: Rectangle {
        radius: combo.host && combo.host.chipR !== undefined ? combo.host.chipR : 8
        color: combo.host ? combo.host.optFieldBg : Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        border.color: combo.popup.visible ? combo.bar.accent : combo.bar.pillBorder
    }
    indicator: Text {
        x: combo.width - width - 8
        y: (combo.height - height) / 2
        text: combo.popup.visible ? "▴" : "▾"
        color: combo.bar.subtext
        font.pixelSize: 11
    }
    popup: Popup {
        id: fontPopup
        y: combo.height + 2
        width: Math.max(combo.width, 240)
        padding: 6
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        height: combo.shownFonts.length ? 272 : 76
        onOpened: {
            searchField.text = ""
            combo.query = ""
            combo.rebuild()
            const current = combo.fontName.length ? combo.fontName : "Bar font"
            const list = combo.shownFonts || []
            let idx = 0
            for (let i = 0; i < list.length; i++) {
                if (list[i] === current) {
                    idx = i
                    break
                }
            }
            combo.hi = idx
            Qt.callLater(function() {
                searchField.forceActiveFocus()
                if ((combo.shownFonts || []).length)
                    fontList.positionViewAtIndex(Math.max(0, combo.hi), ListView.Contain)
            })
        }
        contentItem: Column {
            spacing: 4
            width: fontPopup.availableWidth
            TextField {
                id: searchField
                width: parent.width
                height: 28
                selectByMouse: true
                placeholderText: "Search fonts"
                color: combo.bar.text
                placeholderTextColor: combo.bar.subtext
                font.pixelSize: 12
                font.family: combo.bar.fontFamily
                background: Rectangle {
                    radius: combo.host && combo.host.chipR !== undefined ? combo.host.chipR : 6
                    color: searchField.activeFocus
                           ? (combo.host ? combo.host.optFieldBgFocus : Qt.rgba(1, 1, 1, 0.1))
                           : (combo.host ? combo.host.optFieldBg : Qt.rgba(1, 1, 1, 0.06))
                    border.width: 1
                    border.color: searchField.activeFocus ? combo.bar.accent : combo.bar.pillBorder
                }
                onTextChanged: combo.query = text
                Keys.onUpPressed: (event) => {
                    combo.hi = Math.max(0, combo.hi - 1)
                    fontList.positionViewAtIndex(combo.hi, ListView.Contain)
                    event.accepted = true
                }
                Keys.onDownPressed: (event) => {
                    const n = (combo.shownFonts || []).length
                    combo.hi = Math.min(Math.max(0, n - 1), combo.hi + 1)
                    fontList.positionViewAtIndex(Math.max(0, combo.hi), ListView.Contain)
                    event.accepted = true
                }
                Keys.onReturnPressed: (event) => {
                    combo.acceptHi()
                    event.accepted = true
                }
                Keys.onEnterPressed: (event) => {
                    combo.acceptHi()
                    event.accepted = true
                }
                Keys.onEscapePressed: (event) => {
                    fontPopup.close()
                    event.accepted = true
                }
            }
            Text {
                width: parent.width
                visible: combo.shownFonts.length === 0
                text: "No matching fonts"
                color: combo.bar.subtext
                font.pixelSize: 12
                font.family: combo.bar.fontFamily
                leftPadding: 8
            }
            ListView {
                id: fontList
                width: parent.width
                height: combo.shownFonts.length ? 220 : 0
                clip: true
                model: combo.shownFonts
                currentIndex: combo.hi
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Rectangle {
                    required property int index
                    required property string modelData
                    width: fontList.width
                    height: 30
                    radius: 4
                    color: (index === combo.hi || fontRowMa.containsMouse)
                           ? (combo.bar.controlActiveBg !== undefined
                              ? combo.bar.controlActiveBg
                              : Qt.rgba(0, 0.7, 0.75, 0.35))
                           : "transparent"
                    Text {
                        anchors.fill: parent
                        leftPadding: 8
                        text: modelData
                        color: combo.bar.text
                        font.family: modelData === "Bar font" ? combo.bar.fontFamily : modelData
                        font.pixelSize: 13
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                    MouseArea {
                        id: fontRowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onContainsMouseChanged: {
                            if (containsMouse)
                                combo.hi = index
                        }
                        onClicked: combo.pick(modelData)
                    }
                }
            }
        }
        background: Rectangle {
            radius: 8
            color: combo.bar.glassPopupBg !== undefined ? combo.bar.glassPopupBg : Qt.rgba(0.06, 0.08, 0.12, 0.96)
            border.width: 1
            border.color: combo.bar.glassPopupBorder !== undefined ? combo.bar.glassPopupBorder : combo.bar.pillBorder
        }
    }
}
