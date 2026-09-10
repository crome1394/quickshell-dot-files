import QtQuick
import QtQuick.Layouts
import Quickshell

// ClockPill — live clock + calendar popup.
// Face text: bar.barText / bar.fontBarResolved / bar.fontBarFace (Themes → Bar widget text).

Rectangle {
    id: root

    // === Required Properties ===
    required property var bar
    required property Item barBg   // needed for accurate popup positioning

    // Format string for Qt.formatDateTime — from bar.clockFormat (Config + control bar).
    readonly property string clockFormat: {
        if (bar && bar.clockFormat && String(bar.clockFormat).length)
            return String(bar.clockFormat)
        return "dddd, MM·dd·yyyy | HH:mm:ss"
    }

    // === Layout (for RowLayout participation in the bar) ===
    readonly property real _ws: (bar.widgetScale ? bar.widgetScale("clock") : 1.0)
    Layout.preferredWidth: Math.round((clockLabel.implicitWidth + 28) * _ws)
    Layout.preferredHeight: bar.pillHeight
    Layout.alignment: Qt.AlignVCenter

    // === Appearance via Theme ===
    // Outer chrome is stable; the clock chip highlights on hover (content, not whole pill rim).
    radius: bar.pillRadius
    color: bar.pillBg
    border.width: bar.controlBorderWidth
    border.color: bar.pillBorder

    // Content chip: per-item hover (same token as QuickLaunch / SysStats)
    Rectangle {
        id: clockChip
        anchors.centerIn: parent
        width: Math.round((clockLabel.implicitWidth + 16) * root._ws)
        height: parent.height - 8
        radius: bar.workspaceRadius
        color: clockArea.containsMouse ? bar.iconHoverBg : "transparent"
        border.width: clockArea.containsMouse ? bar.controlBorderWidth : 0
        border.color: clockArea.containsMouse ? bar.accent : "transparent"

        Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }
        Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }

        Text {
            id: clockLabel
            anchors.centerIn: parent
            text: Qt.formatDateTime(new Date(), root.clockFormat)
            // Bar widget text (Themes → Bar widget text font/size)
            color: (bar.barText !== undefined) ? bar.barText : bar.text
            font.pixelSize: {
                var base = (bar.fontBarFace !== undefined) ? bar.fontBarFace : 13
                return Math.max(9, Math.round(base * root._ws))
            }
            font.family: (bar.fontBarResolved !== undefined && String(bar.fontBarResolved).length)
                         ? bar.fontBarResolved
                         : (bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily)
            font.bold: true
        }

        MouseArea {
            id: clockArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (calendarPopup.visible) {
                    calendarPopup.visible = false
                } else {
                    showCalendarPopup()
                }
            }
        }
    }

    // Live updating clock (re-reads bar.clockFormat every tick so presets apply live)
    Timer {
        interval: 1000              //1000 = 1 Second
        running: true
        repeat: true
        onTriggered: {
            clockLabel.text = Qt.formatDateTime(new Date(), root.clockFormat)
        }
    }

    Connections {
        target: bar
        function onClockFormatChanged() {
            clockLabel.text = Qt.formatDateTime(new Date(), root.clockFormat)
        }
    }

    // ===== Calendar Logic (tightly coupled to this widget) =====
    QtObject {
        id: calendar
        property int viewedMonth: new Date().getMonth()
        property int viewedYear: new Date().getFullYear()

        function goToToday() {
            var now = new Date()
            viewedMonth = now.getMonth()
            viewedYear = now.getFullYear()
        }

        function changeMonth(delta) {
            viewedMonth += delta
            while (viewedMonth < 0) {
                viewedMonth += 12
                viewedYear -= 1
            }
            while (viewedMonth > 11) {
                viewedMonth -= 12
                viewedYear += 1
            }
        }
    }

    // ===== CALENDAR POPUP (owned by the clock) =====
    PopupWindow {
        id: calendarPopup
        anchor.window: bar
        implicitWidth: bar.popupCalendarWidth
        implicitHeight: bar.popupCalendarHeight
        visible: false
        color: "transparent"

        // Glassmorphic popup background
        Rectangle {
            anchors.fill: parent
            radius: bar.popupRadius
            color: bar.glassPopupBg
            border.width: bar.controlBorderWidth
            border.color: bar.glassPopupBorder

            // Top highlight for glass effect
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: bar.popupHeaderHighlightHeight
                color: bar.glassPopupHighlight
                radius: parent.radius
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: bar.popupSpacing
                spacing: bar.popupSectionSpacing + 4

                // Header: Month + Year + Navigation
                RowLayout {
                    Layout.fillWidth: true
                    spacing: bar.popupSectionSpacing

                    Text {
                        Layout.fillWidth: true
                        text: Qt.formatDateTime(new Date(calendar.viewedYear, calendar.viewedMonth, 1), "MMMM yyyy")
                        color: bar.text
                        font.pixelSize: bar.popupTitleSize
                        font.bold: true
                        font.family: bar.fontFamily
                        horizontalAlignment: Text.AlignLeft
                    }

                    // Nav buttons
                    Repeater {
                        model: [
                            { sym: "«", delta: -12, tip: "Previous year" },
                            { sym: "‹", delta: -1,  tip: "Previous month" },
                            { sym: "›", delta:  1,  tip: "Next month" },
                            { sym: "»", delta: 12,  tip: "Next year" }
                        ]
                        delegate: Rectangle {
                            width: 26
                            height: 26
                            radius: bar.buttonRadius
                            color: navMa.containsMouse ? bar.surface : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: modelData.sym
                                color: bar.text
                                font.pixelSize: 15
                                font.bold: true
                                font.family: bar.fontFamily
                            }

                            MouseArea {
                                id: navMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: calendar.changeMonth(modelData.delta)
                            }
                        }
                    }

                    // Today button
                    Rectangle {
                        width: 52
                        height: 24
                        radius: bar.buttonRadius
                        color: todayBtnMa.containsMouse ? bar.accent : bar.surface

                        Text {
                            anchors.centerIn: parent
                            text: "Today"
                            color: todayBtnMa.containsMouse ? bar.bg : bar.text
                            font.pixelSize: bar.popupHintSize
                            font.bold: true
                            font.family: bar.fontFamily
                        }

                        MouseArea {
                            id: todayBtnMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: calendar.goToToday()
                        }
                    }
                }

                // Weekday headers
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Repeater {
                        model: ["M", "T", "W", "T", "F", "S", "S"]
                        delegate: Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData
                            color: bar.weekday
                            font.pixelSize: bar.popupHintSize
                            font.bold: true
                            font.family: bar.fontFamily
                        }
                    }
                }

                // Calendar grid (42 cells)
                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: 7
                    rowSpacing: (bar.popupGridSpacing !== undefined) ? bar.popupGridSpacing : 4
                    columnSpacing: (bar.popupGridSpacing !== undefined) ? bar.popupGridSpacing : 4

                    Repeater {
                        model: 42
                        delegate: Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 22

                            // Day calculation
                            property int firstDay: new Date(calendar.viewedYear, calendar.viewedMonth, 1).getDay()
                            property int leadingEmpty: (firstDay === 0) ? 6 : (firstDay - 1)
                            property int daysInMonth: new Date(calendar.viewedYear, calendar.viewedMonth + 1, 0).getDate()
                            property int dayNum: index - leadingEmpty + 1

                            property bool isCurrentMonth: dayNum >= 1 && dayNum <= daysInMonth
                            property int displayNum: {
                                if (isCurrentMonth) return dayNum
                                if (dayNum < 1) {
                                    var prevDays = new Date(calendar.viewedYear, calendar.viewedMonth, 0).getDate()
                                    return prevDays + dayNum
                                }
                                return dayNum - daysInMonth
                            }

                            property bool isToday: {
                                var now = new Date()
                                return isCurrentMonth &&
                                       calendar.viewedYear === now.getFullYear() &&
                                       calendar.viewedMonth === now.getMonth() &&
                                       dayNum === now.getDate()
                            }

                            // Today highlight
                            Rectangle {
                                anchors.centerIn: parent
                                width: 26
                                height: 26
                                radius: 13
                                color: bar.todayBg
                                visible: isToday
                            }

                            // Day number
                            Text {
                                anchors.centerIn: parent
                                text: displayNum > 0 ? displayNum : ""
                                color: isToday ? bar.bg :
                                       (isCurrentMonth ? bar.text : bar.overlay)
                                font.pixelSize: isToday ? 13 : 12
                                font.bold: isToday || isCurrentMonth
                            }
                        }
                    }
                }

                // Footer
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: bar.popupSectionSpacing

                    Text {
                        Layout.fillWidth: true
                        text: "Current day is highlighted"
                        color: bar.subtext
                        font.pixelSize: bar.fontTiny
                        font.family: bar.fontFamily
                    }

                    Text {
                        text: "click clock to close"
                        color: bar.subtext
                        font.pixelSize: bar.fontTiny
                        font.family: bar.fontFamily
                    }
                }
            }
        }
    }

    // === Public API (show from shell IPC: qs ipc call clockPill showCalendar) ===
    function showCalendar() {
        showCalendarPopup()
    }

    // Helper to position + show the calendar popup
    function showCalendarPopup() {
        var popupWidth = calendarPopup.implicitWidth
        if (typeof bar.placePopup === "function") {
            bar.placePopup(calendarPopup, root, popupWidth, calendarPopup.implicitHeight, 2, root.width / 2)
        } else {
            var pos = root.mapToItem(barBg, root.width / 2, root.height)
            var targetX = bar.sideMargin + pos.x - (popupWidth / 2)
            var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920
            var minX = 12
            var maxX = screenW - popupWidth - 12
            calendarPopup.anchor.rect.x = Math.max(minX, Math.min(targetX, maxX))
            calendarPopup.anchor.rect.y = bar.popupAnchorY(calendarPopup.implicitHeight, 2)
        }

        calendarPopup.visible = true
    }
}
