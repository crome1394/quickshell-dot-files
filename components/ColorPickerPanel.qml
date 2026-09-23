import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell

// =============================================================================
// ColorPickerPanel.qml — simple mouse-driven color picker for non-coders
// =============================================================================
// SV square + hue strip + opacity + hex + R/G/B. Emits colorEdited live.
// =============================================================================

Item {
    id: root

    property color color: "#00F0E0"
    property real alpha: 1.0
    property bool showOpacity: true
    property string title: "Pick a color"
    property color panelBg: Qt.rgba(0.06, 0.08, 0.12, 0.96)
    property color panelBorder: Qt.rgba(0.55, 0.72, 0.82, 0.22)
    property color labelColor: "#f0f4fc"
    property color fieldBg: Qt.rgba(0.10, 0.12, 0.18, 0.92)
    property color accentColor: "#00F0E0"
    property string fontFamily: "sans-serif"

    signal colorEdited(color c)
    signal accepted()
    signal cancelled()
    signal hexCopied(string hex)

    // Internal HSV (h 0–360, s/v 0–1)
    property real h: 180
    property real s: 1
    property real v: 1
    property bool _syncing: false

    // Default compact size; when the parent assigns a taller height (Layout.preferredHeight
    // / fillHeight), the SV square grows between the header and the bottom chrome.
    // Bottom controls (hue / opacity / hex / RGB / Done) are always reserved — never
    // truncated when the host is short or the SV expands.
    // Keep drag preventStealing so a parent Flickable does not steal the SV/hue drag.
    implicitWidth: 280
    // header + svMin + hue + optional opacity + hex + done + margins/spacing
    implicitHeight: 12 + 22 + svMinHeight + 5 + 16 + (showOpacity ? 30 : 0) + 30 + 30 + 12
    property int svMinHeight: 96
    property bool _hexCopied: false
    // Space reserved under the SV square so chrome never collapses
    readonly property int chromeReserveH: {
        // hue 16 + spacing + (opacity row) + hex row 28 + done 28 + spacings + margins
        var h = 16 + 5 + 28 + 5 + 28 + 8
        if (root.showOpacity)
            h += 28 + 5
        return h
    }

    function copyHexToClipboard() {
        var hex = toHex(root.previewColor)
        try {
            Quickshell.execDetached([
                "sh", "-c",
                'printf "%s" "$1" | wl-copy 2>/dev/null || printf "%s" "$1" | xclip -selection clipboard 2>/dev/null || true',
                "copy-hex",
                hex
            ])
        } catch (e) {
            // Fallback without Quickshell binding
            try {
                // Some hosts expose clipboard on Qt.application
            } catch (e2) {}
        }
        root._hexCopied = true
        copyHexReset.restart()
    }

    Timer {
        id: copyHexReset
        interval: 1200
        repeat: false
        onTriggered: root._hexCopied = false
    }

    function clamp01(n) {
        var x = Number(n)
        if (!(x >= 0)) x = 0
        if (x > 1) x = 1
        return x
    }

    function hsvToRgb(hh, ss, vv) {
        var h1 = ((hh % 360) + 360) % 360
        var c = vv * ss
        var x = c * (1 - Math.abs(((h1 / 60) % 2) - 1))
        var m = vv - c
        var r = 0, g = 0, b = 0
        if (h1 < 60) { r = c; g = x; b = 0 }
        else if (h1 < 120) { r = x; g = c; b = 0 }
        else if (h1 < 180) { r = 0; g = c; b = x }
        else if (h1 < 240) { r = 0; g = x; b = c }
        else if (h1 < 300) { r = x; g = 0; b = c }
        else { r = c; g = 0; b = x }
        return { r: r + m, g: g + m, b: b + m }
    }

    function rgbToHsv(r, g, b) {
        var max = Math.max(r, g, b)
        var min = Math.min(r, g, b)
        var d = max - min
        var hh = 0
        if (d > 1e-6) {
            if (max === r) hh = 60 * (((g - b) / d) % 6)
            else if (max === g) hh = 60 * (((b - r) / d) + 2)
            else hh = 60 * (((r - g) / d) + 4)
        }
        if (hh < 0) hh += 360
        var ss = max <= 1e-6 ? 0 : d / max
        return { h: hh, s: ss, v: max }
    }

    readonly property color previewColor: {
        var rgb = hsvToRgb(root.h, root.s, root.v)
        return Qt.rgba(rgb.r, rgb.g, rgb.b, clamp01(root.alpha))
    }

    function currentColor() {
        return root.previewColor
    }

    function emitColor() {
        if (root._syncing) return
        var c = currentColor()
        root._syncing = true
        root.color = c
        root._syncing = false
        root.colorEdited(c)
        syncFieldsFromColor(c)
    }

    function loadFromColor(c) {
        if (!c) return
        root._syncing = true
        var hsv = rgbToHsv(c.r, c.g, c.b)
        root.h = hsv.h
        root.s = hsv.s
        root.v = hsv.v
        root.alpha = clamp01(c.a)
        root.color = c
        syncFieldsFromColor(c)
        root._syncing = false
    }

    function byteHex(n) {
        var v = Math.round(clamp01(n) * 255)
        var s = v.toString(16)
        return s.length < 2 ? ("0" + s) : s
    }

    function toHex(c) {
        return "#" + byteHex(c.r) + byteHex(c.g) + byteHex(c.b)
    }

    function parseHex(hex) {
        if (!hex) return null
        var s = ("" + hex).trim()
        if (s.charAt(0) === "#") s = s.substring(1)
        if (s.length === 3)
            s = s.charAt(0) + s.charAt(0) + s.charAt(1) + s.charAt(1) + s.charAt(2) + s.charAt(2)
        if (s.length !== 6) return null
        var r = parseInt(s.substring(0, 2), 16)
        var g = parseInt(s.substring(2, 4), 16)
        var b = parseInt(s.substring(4, 6), 16)
        if (isNaN(r) || isNaN(g) || isNaN(b)) return null
        return { r: r / 255, g: g / 255, b: b / 255 }
    }

    function syncFieldsFromColor(c) {
        if (!hexField.activeFocus)
            hexField.text = toHex(c)
        if (!rField.activeFocus)
            rField.text = "" + Math.round(clamp01(c.r) * 255)
        if (!gField.activeFocus)
            gField.text = "" + Math.round(clamp01(c.g) * 255)
        if (!bField.activeFocus)
            bField.text = "" + Math.round(clamp01(c.b) * 255)
    }

    function applyHexText() {
        var p = parseHex(hexField.text)
        if (!p) return
        root._syncing = true
        var hsv = rgbToHsv(p.r, p.g, p.b)
        root.h = hsv.h
        root.s = hsv.s
        root.v = hsv.v
        root._syncing = false
        emitColor()
    }

    function applyRgbFields() {
        var r = parseInt(rField.text, 10)
        var g = parseInt(gField.text, 10)
        var b = parseInt(bField.text, 10)
        if (isNaN(r) || isNaN(g) || isNaN(b)) return
        r = Math.max(0, Math.min(255, r)) / 255
        g = Math.max(0, Math.min(255, g)) / 255
        b = Math.max(0, Math.min(255, b)) / 255
        root._syncing = true
        var hsv = rgbToHsv(r, g, b)
        root.h = hsv.h
        root.s = hsv.s
        root.v = hsv.v
        root._syncing = false
        emitColor()
    }

    readonly property color pureHueColor: {
        var rgb = hsvToRgb(root.h, 1, 1)
        return Qt.rgba(rgb.r, rgb.g, rgb.b, 1)
    }

    Component.onCompleted: loadFromColor(root.color)
    onColorChanged: {
        if (root._syncing) return
        // External set — reload HSV without re-emitting
        var c = root.color
        var hsv = rgbToHsv(c.r, c.g, c.b)
        root._syncing = true
        root.h = hsv.h
        root.s = hsv.s
        root.v = hsv.v
        if (root.alpha !== c.a)
            root.alpha = clamp01(c.a)
        syncFieldsFromColor(c)
        root._syncing = false
    }

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: root.panelBg
        border.width: 1
        border.color: root.panelBorder
        // Clip only the SV square; chrome is outside it so controls never paint under the edge
        clip: false

        // ── Header (fixed top) ──
        RowLayout {
            id: headerRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            anchors.topMargin: 6
            height: 20
            spacing: 6
            Text {
                Layout.fillWidth: true
                text: root.title
                color: root.labelColor
                font.pixelSize: 12
                font.bold: true
                font.family: root.fontFamily
                elide: Text.ElideRight
            }
            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 18
                radius: 4
                color: root.previewColor
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.25)
            }
        }

        // ── Bottom chrome (fixed — never truncated) ──
        ColumnLayout {
            id: chromeCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            anchors.bottomMargin: 6
            spacing: 5

            // Hue strip
            Item {
                id: hueBox
                Layout.fillWidth: true
                Layout.preferredHeight: 14

                Rectangle {
                    anchors.fill: parent
                    radius: 4
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#ff0000" }
                        GradientStop { position: 0.17; color: "#ffff00" }
                        GradientStop { position: 0.33; color: "#00ff00" }
                        GradientStop { position: 0.50; color: "#00ffff" }
                        GradientStop { position: 0.67; color: "#0000ff" }
                        GradientStop { position: 0.83; color: "#ff00ff" }
                        GradientStop { position: 1.0; color: "#ff0000" }
                    }
                }

                Rectangle {
                    width: 4
                    height: parent.height + 4
                    radius: 2
                    color: "#ffffff"
                    border.width: 1
                    border.color: "#000000"
                    anchors.verticalCenter: parent.verticalCenter
                    x: (root.h / 360) * hueBox.width - width / 2
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    preventStealing: true
                    function pick(mx) {
                        root.h = Math.max(0, Math.min(359.999, (mx / Math.max(1, hueBox.width)) * 360))
                        root.emitColor()
                    }
                    onPressed: (mouse) => pick(mouse.x)
                    onPositionChanged: (mouse) => {
                        if (pressed) pick(mouse.x)
                    }
                }
            }

            // Opacity row
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                visible: root.showOpacity
                spacing: 6
                Text {
                    text: "Op"
                    color: root.labelColor
                    font.pixelSize: 11
                    font.family: root.fontFamily
                }
                OptValueSlider {
                    Layout.fillWidth: true
                    accent: root.accentColor
                    textColor: root.labelColor
                    subtextColor: root.labelColor
                    fontFamily: root.fontFamily
                    from: 0
                    to: 100
                    stepSize: 1
                    suffix: "%"
                    value: Math.round(root.alpha * 100)
                    onValueEdited: (v) => {
                        root.alpha = v / 100
                        root.emitColor()
                    }
                    onValueCommitted: (v) => {
                        root.alpha = v / 100
                        root.emitColor()
                    }
                }
            }

            // Hex + RGB
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                spacing: 4
                Text {
                    text: "Hex"
                    color: root.labelColor
                    font.pixelSize: 11
                    font.family: root.fontFamily
                }
                TextField {
                    id: hexField
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24
                    Layout.minimumWidth: 72
                    font.pixelSize: 11
                    font.family: "monospace"
                    color: root.labelColor
                    selectedTextColor: "#000000"
                    selectionColor: root.accentColor
                    // Clear on click so typing a new hex is immediate
                    property bool _clearOnFocus: true
                    background: Rectangle {
                        radius: 4
                        color: root.fieldBg
                        border.width: 1
                        border.color: hexField.activeFocus ? root.accentColor : Qt.rgba(1, 1, 1, 0.12)
                    }
                    onActiveFocusChanged: {
                        if (activeFocus && _clearOnFocus) {
                            text = ""
                            selectAll()
                        } else if (!activeFocus) {
                            // Restore display if left empty without commit
                            if (!(text && text.length))
                                syncFieldsFromColor(root.previewColor)
                        }
                    }
                    onEditingFinished: root.applyHexText()
                    Keys.onReturnPressed: root.applyHexText()
                    Keys.onEnterPressed: root.applyHexText()
                }
                Text {
                    text: "R"
                    color: root.labelColor
                    font.pixelSize: 10
                    font.family: root.fontFamily
                }
                TextField {
                    id: rField
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 24
                    font.pixelSize: 11
                    font.family: "monospace"
                    color: root.labelColor
                    horizontalAlignment: Text.AlignHCenter
                    selectedTextColor: "#000000"
                    selectionColor: root.accentColor
                    validator: IntValidator { bottom: 0; top: 255 }
                    background: Rectangle {
                        radius: 4
                        color: root.fieldBg
                        border.width: 1
                        border.color: rField.activeFocus ? root.accentColor : Qt.rgba(1, 1, 1, 0.12)
                    }
                    onEditingFinished: root.applyRgbFields()
                    Keys.onReturnPressed: root.applyRgbFields()
                    Keys.onEnterPressed: root.applyRgbFields()
                }
                Text {
                    text: "G"
                    color: root.labelColor
                    font.pixelSize: 10
                    font.family: root.fontFamily
                }
                TextField {
                    id: gField
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 24
                    font.pixelSize: 11
                    font.family: "monospace"
                    color: root.labelColor
                    horizontalAlignment: Text.AlignHCenter
                    selectedTextColor: "#000000"
                    selectionColor: root.accentColor
                    validator: IntValidator { bottom: 0; top: 255 }
                    background: Rectangle {
                        radius: 4
                        color: root.fieldBg
                        border.width: 1
                        border.color: gField.activeFocus ? root.accentColor : Qt.rgba(1, 1, 1, 0.12)
                    }
                    onEditingFinished: root.applyRgbFields()
                    Keys.onReturnPressed: root.applyRgbFields()
                    Keys.onEnterPressed: root.applyRgbFields()
                }
                Text {
                    text: "B"
                    color: root.labelColor
                    font.pixelSize: 10
                    font.family: root.fontFamily
                }
                TextField {
                    id: bField
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 24
                    font.pixelSize: 11
                    font.family: "monospace"
                    color: root.labelColor
                    horizontalAlignment: Text.AlignHCenter
                    selectedTextColor: "#000000"
                    selectionColor: root.accentColor
                    validator: IntValidator { bottom: 0; top: 255 }
                    background: Rectangle {
                        radius: 4
                        color: root.fieldBg
                        border.width: 1
                        border.color: bField.activeFocus ? root.accentColor : Qt.rgba(1, 1, 1, 0.12)
                    }
                    onEditingFinished: root.applyRgbFields()
                    Keys.onReturnPressed: root.applyRgbFields()
                    Keys.onEnterPressed: root.applyRgbFields()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                spacing: 6
                Item { Layout.fillWidth: true }
                Rectangle {
                    Layout.preferredHeight: 24
                    Layout.preferredWidth: copyHexLbl.implicitWidth + 14
                    radius: 5
                    color: copyHexMa.containsMouse ? Qt.rgba(0, 0.85, 0.80, 0.22) : root.fieldBg
                    border.width: 1
                    border.color: root.panelBorder
                    Text {
                        id: copyHexLbl
                        anchors.centerIn: parent
                        text: root._hexCopied ? "Copied" : "Copy hex"
                        color: root.labelColor
                        font.pixelSize: 11
                        font.family: root.fontFamily
                    }
                    MouseArea {
                        id: copyHexMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.copyHexToClipboard()
                    }
                }
                Rectangle {
                    Layout.preferredHeight: 24
                    Layout.preferredWidth: closeLbl.implicitWidth + 14
                    radius: 5
                    color: closeMa.containsMouse ? Qt.rgba(0, 0.85, 0.80, 0.22) : root.fieldBg
                    border.width: 1
                    border.color: root.panelBorder
                    Text {
                        id: closeLbl
                        anchors.centerIn: parent
                        text: "Done"
                        color: root.labelColor
                        font.pixelSize: 11
                        font.family: root.fontFamily
                    }
                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.accepted()
                    }
                }
            }
        }

        // ── SV square fills space between header and chrome ──
        Item {
            id: svBox
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: headerRow.bottom
            anchors.bottom: chromeCol.top
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            anchors.topMargin: 5
            anchors.bottomMargin: 5
            clip: true

            // Hue base
            Rectangle {
                anchors.fill: parent
                radius: 6
                color: root.pureHueColor
            }
            // White → transparent (saturation)
            Rectangle {
                anchors.fill: parent
                radius: 6
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#ffffffff" }
                    GradientStop { position: 1.0; color: "#00ffffff" }
                }
            }
            // Transparent → black (value)
            Rectangle {
                anchors.fill: parent
                radius: 6
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: "#00000000" }
                    GradientStop { position: 1.0; color: "#ff000000" }
                }
            }

            // Cursor
            Rectangle {
                width: 12
                height: 12
                radius: 6
                color: "transparent"
                border.width: 2
                border.color: "#ffffff"
                x: root.s * svBox.width - width / 2
                y: (1 - root.v) * svBox.height - height / 2
                Rectangle {
                    anchors.centerIn: parent
                    width: 8
                    height: 8
                    radius: 4
                    color: "transparent"
                    border.width: 1
                    border.color: "#000000"
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.CrossCursor
                preventStealing: true
                function pick(mx, my) {
                    root.s = Math.max(0, Math.min(1, mx / Math.max(1, svBox.width)))
                    root.v = Math.max(0, Math.min(1, 1 - (my / Math.max(1, svBox.height))))
                    root.emitColor()
                }
                onPressed: (mouse) => pick(mouse.x, mouse.y)
                onPositionChanged: (mouse) => {
                    if (pressed) pick(mouse.x, mouse.y)
                }
            }
        }
    }
}
