import QtQuick
import "../components"
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io as Io

// =============================================================================
// KillTargetPill.qml — Click-to-kill window picker (xkill-style)
// =============================================================================
//
// Click the pill to arm pick mode: fullscreen overlay on every monitor with a
// crosshair cursor. Left-click a window to SIGTERM its PID (process-control.sh).
// Escape, right-click, or empty click cancels. Second pill click also cancels.
// =============================================================================

Item {
    id: root

    required property var bar

    readonly property real _ws: (bar.widgetScale ? bar.widgetScale("killTarget") : 1.0)
    Layout.preferredWidth: Math.round(42 * _ws)
    Layout.preferredHeight: bar.pillHeight
    Layout.alignment: Qt.AlignVCenter

    property bool pickActive: false
    property string statusMessage: ""
    property string _pendingClass: ""
    property string _pendingTitle: ""
    property int _pendingPid: 0

    readonly property string resolveScript: "/home/crome/.config/quickshell/scripts/window-at-point.sh"
    readonly property string killScript: "/home/crome/.config/quickshell/scripts/process-control.sh"

    function activatePickMode() {
        if (pickActive) {
            cancelPickMode()
            return
        }
        statusMessage = ""
        pickActive = true
    }

    function cancelPickMode() {
        pickActive = false
        resolveProcess.running = false
        killProcess.running = false
    }

    function showStatus(message) {
        statusMessage = message
        statusTimer.restart()
    }

    function killAtPoint(globalX, globalY) {
        if (!pickActive) return
        resolveProcess.running = false
        resolveProcess.command = [
            resolveScript,
            String(Math.round(globalX)),
            String(Math.round(globalY)),
            String(Quickshell.processId)
        ]
        resolveProcess.running = true
    }

    function handleResolvedClient(data) {
        if (data.error) {
            if (data.error === "no_window") {
                showStatus("No window at that point")
                cancelPickMode()
            } else {
                showStatus("Could not identify window")
                cancelPickMode()
            }
            return
        }

        const pid = Number(data.pid) || 0
        if (pid <= 0) {
            showStatus("No process for that window")
            cancelPickMode()
            return
        }

        _pendingPid = pid
        _pendingClass = data.class || "unknown"
        _pendingTitle = data.title || ""
        killProcess.running = false
        killProcess.command = [killScript, "kill", String(pid)]
        killProcess.running = true
    }

    function handleKillFinished(exitCode) {
        pickActive = false
        if (exitCode === 0) {
            const label = _pendingClass || ("PID " + _pendingPid)
            showStatus("Killed " + label + " (" + _pendingPid + ")")
        } else {
            const err = (killStderr.text || killStdout.text || "").trim()
            showStatus(err.length ? err : ("Failed to kill PID " + _pendingPid))
        }
        _pendingPid = 0
        _pendingClass = ""
        _pendingTitle = ""
    }

    Timer {
        id: statusTimer
        interval: 3200
        onTriggered: root.statusMessage = ""
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.pickActive
        onActivated: root.cancelPickMode()
    }

    Io.Process {
        id: resolveProcess
        stdout: Io.SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                const trimmed = line.trim()
                if (!trimmed.startsWith("{") || !trimmed.endsWith("}")) return
                try {
                    const data = JSON.parse(trimmed)
                    root.handleResolvedClient(data)
                } catch (e) {
                    root.showStatus("Could not parse window data")
                    root.cancelPickMode()
                }
            }
        }
        onExited: (code) => {
            if (code !== 0 && root.pickActive)
                root.showStatus("Window lookup failed")
        }
    }

    Io.Process {
        id: killProcess
        stdout: Io.StdioCollector { id: killStdout }
        stderr: Io.StdioCollector { id: killStderr }
        onExited: (code) => root.handleKillFinished(code)
    }

    Rectangle {
        id: pill
        anchors.fill: parent
        clip: false
        DockFace {
            id: dockFx
            bar: root.bar
            host: pill
            hovered: pickMouse.containsMouse
        }
        transform: [
            Scale {
                xScale: dockFx.mag
                yScale: dockFx.mag
                origin.x: pill.width / 2
                origin.y: dockFx.growUp ? pill.height : 0
            },
            Translate { y: dockFx.jumpY }
        ]
        radius: bar.pillRadius
        color: pickMouse.containsMouse || root.pickActive ? bar.glassHover : bar.pillBg
        border.width: bar.controlBorderWidth
        border.color: root.pickActive || pickMouse.containsMouse ? bar.accent : bar.pillBorder

        Text {
            anchors.centerIn: parent
            text: bar.killTargetIcon
            font.pixelSize: bar.iconSizePillLarge
            font.family: bar.fontFamily
            color: root.pickActive || pickMouse.containsMouse ? bar.accent : (bar.iconColor !== undefined ? bar.iconColor : bar.subtext)
        }

        MouseArea {
            id: pickMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                dockFx.jump()
                root.activatePickMode()
            }

            BarToolTip {
                bar: root.bar
                widgetId: "killTarget"
                visible: pickMouse.containsMouse || root.statusMessage.length > 0
                anchorItem: pickMouse
                text: root.pickActive
                      ? "Click a window to kill · Esc to cancel"
                      : (root.statusMessage.length ? root.statusMessage : bar.killTargetTooltip)
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            property var modelData

            screen: modelData
            visible: root.pickActive
            color: "transparent"
            aboveWindows: true
            focusable: true
            exclusiveZone: 0

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, bar.killTargetOverlayDim)
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.CrossCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton) {
                        root.cancelPickMode()
                        return
                    }
                    const globalX = modelData.x + mouse.x
                    const globalY = modelData.y + mouse.y
                    root.killAtPoint(globalX, globalY)
                }
            }
        }
    }
}