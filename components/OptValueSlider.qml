import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Left / slider / right / typed field. Parent binds `value` and handles
// valueEdited (live) + valueCommitted (release, nudge, or typed enter).
RowLayout {
    id: root
    spacing: 6
    Layout.fillWidth: true
    implicitHeight: 26

    property var bar: null
    property real from: 0
    property real to: 100
    property real stepSize: 1
    property real value: 0
    property string suffix: ""
    property bool showField: true
    property int fieldWidth: 44
    property bool enabled: true

    property color accent: (bar && bar.accent !== undefined) ? bar.accent : "#00F0E0"
    property color textColor: (bar && bar.text !== undefined) ? bar.text : "#f0f4fc"
    property color subtextColor: (bar && bar.subtext !== undefined) ? bar.subtext : "#a8b4c8"
    property color fieldBg: Qt.rgba(0.12, 0.14, 0.18, 0.85)
    property color fieldBgFocus: Qt.rgba(0.16, 0.18, 0.24, 1)
    property string fontFamily: (bar && bar.fontFamily) ? bar.fontFamily : "sans-serif"
    property string fontMono: (bar && bar.fontMono) ? bar.fontMono : fontFamily

    signal valueEdited(real v)
    signal valueCommitted(real v)

    function snap(v) {
        const lo = Number(root.from)
        const hi = Number(root.to)
        const s = Number(root.stepSize) > 0 ? Number(root.stepSize) : 1
        let n = Number(v)
        if (!(n === n))
            n = lo
        n = Math.round(n / s) * s
        if (n < lo)
            n = lo
        if (n > hi)
            n = hi
        if (s >= 1)
            n = Math.round(n)
        return n
    }

    function format(v) {
        const n = root.snap(v)
        if (Number(root.stepSize) < 1 && Number(root.stepSize) > 0)
            return String(Math.round(n * 100) / 100)
        return String(Math.round(n))
    }

    function emit(v, commit) {
        const n = root.snap(v)
        root.valueEdited(n)
        if (commit)
            root.valueCommitted(n)
    }

    function nudge(dir) {
        root.emit(Number(root.value) + dir * Number(root.stepSize), true)
    }

    Rectangle {
        Layout.preferredWidth: 22
        Layout.preferredHeight: 22
        radius: 4
        enabled: root.enabled
        opacity: enabled ? 1 : 0.4
        color: leftMa.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.16)
        Text {
            anchors.centerIn: parent
            text: "‹"
            color: root.textColor
            font.pixelSize: 14
            font.bold: true
        }
        MouseArea {
            id: leftMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.nudge(-1)
        }
    }

    Slider {
        id: sl
        Layout.fillWidth: true
        Layout.preferredHeight: 22
        from: root.from
        to: root.to
        stepSize: root.stepSize
        snapMode: Slider.SnapAlways
        live: true
        enabled: root.enabled
        value: root.value
        onMoved: root.emit(value, false)
        onPressedChanged: {
            if (!pressed)
                root.emit(value, true)
        }
        background: Rectangle {
            x: sl.leftPadding
            y: sl.topPadding + sl.availableHeight / 2 - height / 2
            implicitWidth: 160
            implicitHeight: 5
            width: sl.availableWidth
            height: 5
            radius: 3
            color: Qt.rgba(1, 1, 1, 0.12)
            Rectangle {
                width: sl.visualPosition * parent.width
                height: parent.height
                radius: 3
                color: root.accent
            }
        }
        handle: Rectangle {
            x: sl.leftPadding + sl.visualPosition * (sl.availableWidth - width)
            y: sl.topPadding + sl.availableHeight / 2 - height / 2
            implicitWidth: 12
            implicitHeight: 12
            radius: 3
            color: sl.pressed ? root.accent : root.textColor
            border.width: 1
            border.color: root.accent
        }
    }

    Rectangle {
        Layout.preferredWidth: 22
        Layout.preferredHeight: 22
        radius: 4
        enabled: root.enabled
        opacity: enabled ? 1 : 0.4
        color: rightMa.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.16)
        Text {
            anchors.centerIn: parent
            text: "›"
            color: root.textColor
            font.pixelSize: 14
            font.bold: true
        }
        MouseArea {
            id: rightMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.nudge(1)
        }
    }

    TextField {
        id: field
        visible: root.showField
        enabled: root.enabled
        Layout.preferredWidth: root.fieldWidth
        Layout.preferredHeight: 22
        horizontalAlignment: Text.AlignHCenter
        color: root.textColor
        font.pixelSize: 11
        font.family: root.fontMono
        selectByMouse: true
        text: root.format(root.value)
        background: Rectangle {
            radius: 4
            color: field.activeFocus ? root.fieldBgFocus : root.fieldBg
            border.width: 1
            border.color: field.activeFocus ? root.accent : Qt.rgba(1, 1, 1, 0.14)
        }
        onActiveFocusChanged: {
            if (!activeFocus)
                root.commitField()
        }
        onAccepted: root.commitField()
        Keys.onEscapePressed: {
            text = root.format(root.value)
            focus = false
        }
    }

    Text {
        visible: root.showField && root.suffix.length > 0
        text: root.suffix
        color: root.subtextColor
        font.pixelSize: 11
        font.family: root.fontFamily
        Layout.preferredWidth: implicitWidth
    }

    onValueChanged: {
        if (!field.activeFocus)
            field.text = root.format(root.value)
    }

    function commitField() {
        const n = parseFloat(field.text)
        if (isNaN(n)) {
            field.text = root.format(root.value)
            return
        }
        const snapped = root.snap(n)
        field.text = root.format(snapped)
        root.emit(snapped, true)
    }
}
