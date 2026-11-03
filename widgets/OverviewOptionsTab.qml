// Settings → Options → Overview. Writes through bar.setOverview into bar-layout.json.
import QtQuick
import QtQuick.Layouts
import "../components"

ColumnLayout {
    id: root

    required property var bar
    Layout.fillWidth: true
    spacing: 8

    function setKey(key, value, persist) {
        if (root.bar && root.bar.setOverview)
            root.bar.setOverview(key, value, persist !== false)
    }

    component SectionTitle: Text {
        required property string label
        Layout.fillWidth: true
        Layout.columnSpan: 2
        Layout.topMargin: 8
        text: label
        color: root.bar.text
        font.pixelSize: 12
        font.bold: true
        font.family: root.bar.fontFamily
    }

    component Hint: Text {
        required property string label
        Layout.fillWidth: true
        Layout.columnSpan: 2
        wrapMode: Text.WordWrap
        text: label
        color: root.bar.subtext
        font.pixelSize: 10
        font.family: root.bar.fontFamily
    }

    component ChoiceRow: RowLayout {
        required property string setting
        required property var choices
        required property string current
        Layout.fillWidth: true
        Layout.columnSpan: 2
        spacing: 6
        Repeater {
            model: parent.choices
            delegate: Rectangle {
                required property var modelData
                readonly property bool picked: modelData.id === parent.current
                Layout.preferredHeight: 26
                Layout.fillWidth: true
                radius: 4
                color: picked ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.04)
                border.width: 1
                border.color: picked ? root.bar.accent : root.bar.pillBorder
                Text {
                    anchors.centerIn: parent
                    text: modelData.label
                    color: parent.picked ? root.bar.text : root.bar.subtext
                    font.pixelSize: 11
                    font.bold: parent.picked
                    font.family: root.bar.fontFamily
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setKey(parent.parent.setting, modelData.id, true)
                }
            }
        }
    }

    component Flag: Rectangle {
        id: flag
        required property string setting
        required property string label
        required property string detail
        required property bool checked
        readonly property color markOn: "#2ee59a"
        readonly property color markOff: "#FF3D8A"
        Layout.fillWidth: true
        Layout.preferredHeight: 40
        radius: 6
        color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
        border.width: 1
        border.color: root.bar.dividerStrong !== undefined ? root.bar.dividerStrong : root.bar.pillBorder
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    text: flag.label
                    color: root.bar.text
                    font.pixelSize: 12
                    font.family: root.bar.fontFamily
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: flag.detail
                    color: root.bar.subtext
                    font.pixelSize: 10
                    font.family: root.bar.fontFamily
                    elide: Text.ElideRight
                }
            }
            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 22
                radius: 4
                color: flagMark.containsMouse
                       ? (flag.checked ? Qt.rgba(0.29, 0.87, 0.50, 0.18) : Qt.rgba(0.97, 0.44, 0.44, 0.18))
                       : "transparent"
                border.width: 1
                border.color: flag.checked ? flag.markOn : flag.markOff
                Text {
                    anchors.centerIn: parent
                    text: flag.checked ? "✓" : "✕"
                    color: flag.checked ? flag.markOn : flag.markOff
                    font.pixelSize: 14
                    font.bold: true
                }
                MouseArea {
                    id: flagMark
                    anchors.fill: parent
                    hoverEnabled: true
                }
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.setKey(flag.setting, !flag.checked, true)
        }
    }

    component SliderRow: ColumnLayout {
        required property string setting
        required property string label
        property real from: 0
        property real to: 100
        property real stepSize: 1
        property real amount: 0
        property string suffix: ""
        Layout.fillWidth: true
        spacing: 2
        Text {
            text: parent.label
            color: root.bar.subtext
            font.pixelSize: 11
            font.family: root.bar.fontFamily
        }
        OptValueSlider {
            bar: root.bar
            from: parent.from
            to: parent.to
            stepSize: parent.stepSize
            value: parent.amount
            suffix: parent.suffix
            onValueEdited: function (v) { root.setKey(parent.setting, v, false) }
            onValueCommitted: function (v) { root.setKey(parent.setting, v, true) }
        }
    }

    Text {
        text: "Overview"
        color: root.bar.text
        font.pixelSize: 12
        font.bold: true
        font.family: root.bar.fontFamily
    }
    Hint {
        label: "Super+Tab opens the workspace overview. Super+Shift+Tab opens desktop layout (windows in place, with close buttons). Super+Ctrl+Tab opens every workspace. Inside: Tab and Shift+Tab move between workspaces, arrows select, Enter focuses, D closes the selected window, A toggles all workspaces, a bare Shift flips desktop layout, 1–9 and 0 pick a strip card, the wheel steps workspaces, and a click on empty space closes. Drag a window onto a card to move it. In grid layout, drop one preview on another to swap them. The workspace you are viewing is focused when the overview closes."
    }

    SectionTitle { label: "Layout" }
    ChoiceRow {
        setting: "layout"
        current: root.bar.ovLayout
        choices: [
            { id: "rows", label: "Rows" },
            { id: "grid", label: "Grid" },
            { id: "natural", label: "Natural" }
        ]
    }
    Hint { label: "Rows packs previews at their real aspect. Grid uses equal cells. Natural keeps each window where it sits on the desktop." }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 16
        rowSpacing: 8

        SectionTitle { label: "Workspace strip" }
        ChoiceRow {
            setting: "anchor"
            current: root.bar.ovAnchor
            choices: [
                { id: "top", label: "Top" },
                { id: "bottom", label: "Bottom" },
                { id: "left", label: "Left" },
                { id: "right", label: "Right" }
            ]
        }
        SliderRow { setting: "stripHeight"; label: "Strip height (top or bottom)"; from: 72; to: 640; amount: root.bar.ovStripHeight; suffix: "px" }
        SliderRow { setting: "stripWidth"; label: "Strip width (left or right)"; from: 72; to: 640; amount: root.bar.ovStripWidth; suffix: "px" }
        SliderRow { setting: "cardMax"; label: "Card length"; from: 160; to: 960; amount: root.bar.ovStripCardMax; suffix: "px" }
        SliderRow { setting: "stripGap"; label: "Card spacing"; from: 0; to: 64; amount: root.bar.ovStripGap; suffix: "px" }
        SliderRow { setting: "stripMargin"; label: "Strip padding"; from: 0; to: 64; amount: root.bar.ovStripMargin; suffix: "px" }
        SliderRow { setting: "stripOffset"; label: "Inset from the screen edge"; from: 0; to: 120; amount: root.bar.ovStripOffset; suffix: "px" }
        SliderRow { setting: "stripRound"; label: "Card corner radius"; from: 0; to: 28; amount: root.bar.ovStripCardRound; suffix: "px" }
        Hint { label: "Height is the strip when it sits on the top or bottom. Width is the strip when it sits on the left or right. Card length is how wide each card is on a top or bottom strip, and how tall it is on a left or right strip." }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 16
        rowSpacing: 8

        SectionTitle { label: "Previews" }
        SliderRow { setting: "gap"; label: "Gap between windows"; from: 0; to: 120; amount: root.bar.ovGap; suffix: "px" }
        SliderRow { setting: "padding"; label: "Side margin"; from: 0; to: 200; amount: root.bar.ovPadding; suffix: "px" }
        SliderRow { setting: "paddingTop"; label: "Gap beside the strip"; from: 0; to: 160; amount: root.bar.ovPaddingTop; suffix: "px" }
        SliderRow { setting: "paddingBottom"; label: "Outer margin opposite the strip"; from: 0; to: 160; amount: root.bar.ovPaddingBottom; suffix: "px" }
        SliderRow { setting: "maxScale"; label: "Max scale vs real size"; from: 0.2; to: 1.5; stepSize: 0.05; amount: root.bar.ovMaxScale; suffix: "×" }
        SliderRow { setting: "round"; label: "Preview corner radius"; from: 0; to: 32; amount: root.bar.ovPreviewRound; suffix: "px" }
        SliderRow { setting: "blur"; label: "Backdrop dim"; from: 0; to: 1; stepSize: 0.05; amount: root.bar.ovBlur }
        SliderRow { setting: "hoverBorder"; label: "Hover border"; from: 0; to: 8; amount: root.bar.ovHoverBorder; suffix: "px" }
        SliderRow { setting: "selectBorder"; label: "Keyboard selection border"; from: 0; to: 8; amount: root.bar.ovSelectBorder; suffix: "px" }
        Flag {
            setting: "backdropBlur"
            label: "Blur the desktop"
            detail: "Blur what is behind the overview while it is open. The dim slider still darkens it."
            checked: root.bar.ovBackdropBlur === true
        }
        Flag {
            setting: "live"
            label: "Live window previews"
            detail: "Off grabs a still frame. On follows the window while the overview is open."
            checked: root.bar.ovLivePreviews !== false
        }
        Flag {
            setting: "stripPreviews"
            label: "Strip previews"
            detail: "Window thumbnails inside the workspace cards. Off leaves the cards empty."
            checked: root.bar.ovStripPreviews !== false
        }
        Flag {
            setting: "windowLabels"
            label: "Window titles"
            detail: "Show the title under the hovered or selected preview."
            checked: root.bar.ovShowWindowLabels !== false
        }
        Flag {
            setting: "wsLabels"
            label: "Workspace labels"
            detail: "Names above the strip cards. Off gives the cards that space."
            checked: root.bar.ovShowWsLabels !== false
        }
        Flag {
            setting: "numberLabels"
            label: "Use workspace numbers"
            detail: "Replace the emoji and name from the workspace widget with the workspace number."
            checked: root.bar.ovNumberLabels === true
        }
    }

    SectionTitle { label: "Motion" }
    SliderRow { setting: "duration"; label: "Open and close"; from: 0; to: 800; amount: root.bar.ovDuration; suffix: "ms" }
    Flag {
        setting: "switchAnim"
        label: "Slide between workspaces"
        detail: "The preview area slides when Tab, the wheel, or a card changes the workspace."
        checked: root.bar.ovSwitchAnimation !== false
    }
    SliderRow { setting: "switchDuration"; label: "Slide length"; from: 0; to: 800; amount: root.bar.ovSwitchDuration; suffix: "ms" }
    Flag {
        setting: "moveAnim"
        label: "Fly a dropped window into its card"
        detail: "The preview shrinks toward the workspace card after a drag."
        checked: root.bar.ovMoveAnimation !== false
    }
    SliderRow { setting: "moveDuration"; label: "Flight length"; from: 0; to: 800; amount: root.bar.ovMoveDuration; suffix: "ms" }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 16
        rowSpacing: 8

        SectionTitle { label: "Workspaces" }
        Hint { label: "Show only active workspace, in the workspace options, hides empty cards here and keeps the next blank one." }
    Flag {
        setting: "dynamic"
        label: "Dynamic workspaces"
        detail: "List populated workspaces and one empty card at the end. A window has to land there before another empty card appears."
        checked: root.bar.ovDynamic !== false
    }
    Flag {
        setting: "autodelete"
        label: "Hide emptied workspaces"
        detail: "With dynamic workspaces, drop emptied ones from the strip. Hyprland already removes unpinned empty workspaces. Persistent ones are left alone."
        checked: root.bar.ovAutodelete !== false
    }
    Flag {
        setting: "showEmpty"
        label: "Show empty workspaces"
        detail: "When dynamic workspaces is off, keep empty ones as cards."
        checked: root.bar.ovShowEmpty !== false
    }
    Flag {
        setting: "showSpecial"
        label: "Show the special workspace"
        detail: "Add the configured special workspace as a strip card."
        checked: root.bar.ovShowSpecial === true
    }
    Flag {
        setting: "allCard"
        label: "All-workspaces card"
        detail: "Leading strip card that shows every window on this monitor."
        checked: root.bar.ovStripAllCard === true
    }
    Flag {
        setting: "showAll"
        label: "Open into all workspaces"
        detail: "Super+Tab starts in the all-workspaces view."
        checked: root.bar.ovShowAll === true
    }
    Flag {
        setting: "switchOnNew"
        label: "Follow a new workspace"
        detail: "Clicking the empty card creates it and moves the overview there."
        checked: root.bar.ovSwitchOnNew !== false
    }
    Flag {
        setting: "switchOnDrop"
        label: "Follow a dropped window"
        detail: "Dropping a window on a card also switches to that workspace."
        checked: root.bar.ovSwitchOnDrop === true
    }
    Flag {
        setting: "dragSwap"
        label: "Drag to swap in grid layout"
        detail: "Dropping a preview onto another swaps the two windows."
        checked: root.bar.ovDragToSwap !== false
    }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 16
        rowSpacing: 8

        SectionTitle { label: "Input" }
    Flag {
        setting: "focusFollowsMouse"
        label: "Selection follows the pointer"
        detail: "Hovering a preview selects it for Enter and D."
        checked: root.bar.ovFocusFollowsMouse !== false
    }
    Flag {
        setting: "scroll"
        label: "Wheel switches workspace"
        detail: "The wheel over the overview steps to the previous or next card."
        checked: root.bar.ovScrollSwitches !== false
    }
    Flag {
        setting: "exitOnClick"
        label: "Click empty space to close"
        detail: "A click that misses windows and cards dismisses the overview."
        checked: root.bar.ovExitOnClick !== false
    }
    Flag {
        setting: "exitOnSwitch"
        label: "Close if the workspace changes"
        detail: "Dismiss when Hyprland switches workspace underneath the overview."
        checked: root.bar.ovExitOnSwitch === true
    }
        Hint { label: "Saved in state/bar-layout.json. Colors follow the bar theme. IPC: qs ipc call overview toggle | desktop | all | next | prev | close." }
    }
}
