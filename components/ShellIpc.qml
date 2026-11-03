import Quickshell
import QtQuick
import Quickshell.Io as Io

// Shell and overview IPC. The calls match the old inline handlers.
// Properties stand in for shell.qml ids, which this file cannot see.
Scope {
    id: ipcRoot
    required property var hostBar
    required property var controlBar
    required property var overview
    required property var shell

    Io.IpcHandler {
        target: "overview"
        function toggle(): void { ipcRoot.overview.toggle() }
        function open(): void { ipcRoot.overview.openOverview("workspace") }
        function close(): void { ipcRoot.overview.closeOverview() }
        function desktop(): void { ipcRoot.overview.openMode("desktop") }
        function all(): void { ipcRoot.overview.openMode("all") }
        function next(): void { ipcRoot.overview.step(1) }
        function prev(): void { ipcRoot.overview.step(-1) }
    }

    // IPC handlers must use explicit types (bool, string, etc.) — `var` is not supported
    Io.IpcHandler {
        id: shellHandler
        target: "shell"
        function setShowLauncherPill(enabled: bool): void {
            ipcRoot.hostBar.setWidgetVisible("launcher", enabled)
        }
        function toggleShowLauncherPill(): void {
            ipcRoot.hostBar.toggleWidgetVisible("launcher")
        }
        function setShowQuickLaunchPill(enabled: bool): void {
            ipcRoot.hostBar.setWidgetVisible("quickLaunch", enabled)
        }
        function toggleShowQuickLaunchPill(): void {
            ipcRoot.hostBar.toggleWidgetVisible("quickLaunch")
        }
        function setShowWorkspacesPill(enabled: bool): void {
            ipcRoot.hostBar.setWidgetVisible("workspaces", enabled)
        }
        function toggleShowWorkspacesPill(): void {
            ipcRoot.hostBar.toggleWidgetVisible("workspaces")
        }
        function setShowStatsWidget(enabled: bool): void {
            ipcRoot.hostBar.setWidgetVisible("stats", enabled)
        }
        function toggleShowStatsWidget(): void {
            ipcRoot.hostBar.toggleWidgetVisible("stats")
        }
        function setShowTrayPill(enabled: bool): void {
            ipcRoot.hostBar.setWidgetVisible("tray", enabled)
        }
        function toggleShowTrayPill(): void {
            ipcRoot.hostBar.toggleWidgetVisible("tray")
        }
        function setShowNetworkPanel(enabled: bool): void {
            ipcRoot.hostBar.setWidgetVisible("networkPanel", enabled)
        }
        function toggleShowNetworkPanel(): void {
            ipcRoot.hostBar.toggleWidgetVisible("networkPanel")
        }
        function setShowBluetoothPill(enabled: bool): void {
            ipcRoot.hostBar.setWidgetVisible("bluetooth", enabled)
        }
        function toggleShowBluetoothPill(): void {
            ipcRoot.hostBar.toggleWidgetVisible("bluetooth")
        }
        function setShowAudioPill(enabled: bool): void {
            ipcRoot.hostBar.setWidgetVisible("audio", enabled)
        }
        function toggleShowAudioPill(): void {
            ipcRoot.hostBar.toggleWidgetVisible("audio")
        }
        function setShowClockPill(enabled: bool): void {
            ipcRoot.hostBar.setWidgetVisible("clock", enabled)
        }
        function toggleShowClockPill(): void {
            ipcRoot.hostBar.toggleWidgetVisible("clock")
        }
        function setShowNotificationPill(enabled: bool): void {
            ipcRoot.hostBar.setWidgetVisible("notifications", enabled)
        }
        function toggleShowNotificationPill(): void {
            ipcRoot.hostBar.toggleWidgetVisible("notifications")
        }
        function setShowPowerPill(enabled: bool): void {
            ipcRoot.hostBar.setWidgetVisible("power", enabled)
        }
        function toggleShowPowerPill(): void {
            ipcRoot.hostBar.toggleWidgetVisible("power")
        }
        function setShowOpacityPill(enabled: bool): void {
            ipcRoot.hostBar.setWidgetVisible("opacity", enabled)
        }
        function toggleShowOpacityPill(): void {
            ipcRoot.hostBar.toggleWidgetVisible("opacity")
        }
        function setShowTailscalePill(enabled: bool): void {
            ipcRoot.hostBar.setWidgetVisible("tailscale", enabled)
        }
        function toggleShowTailscalePill(): void {
            ipcRoot.hostBar.toggleWidgetVisible("tailscale")
        }
        function setClockFormat(format: string): void {
            ipcRoot.hostBar.setClockFormat(format)
        }
        function setClockFont(name: string): void {
            ipcRoot.hostBar.setClockFont(name)
        }
        function setClockFontScale(scale: string): void {
            ipcRoot.hostBar.setClockFontScale(scale)
        }
        function setWidgetZone(widgetId: string, zone: string): void {
            ipcRoot.hostBar.setWidgetZone(widgetId, zone)
        }
        function moveWidget(widgetId: string, delta: string): void {
            ipcRoot.hostBar.moveWidget(widgetId, Number(delta) || 0)
        }
        function resetWidgetLayout(): void {
            ipcRoot.hostBar.resetWidgetLayout()
        }
        function setBarPosition(position: string): void {
            ipcRoot.hostBar.setBarPosition(position)
        }
        function toggleBarPosition(): void {
            ipcRoot.hostBar.toggleBarPosition()
        }
        function setBarLayoutMode(mode: string): void {
            ipcRoot.hostBar.setBarLayoutMode(mode)
        }
        function toggleBarLayoutMode(): void {
            ipcRoot.hostBar.toggleBarLayoutMode()
        }
        function toggleBarControlBar(): void {
            ipcRoot.controlBar.toggle()
        }
        function showBarControlBar(): void {
            ipcRoot.controlBar.show()
        }
        function hideBarControlBar(): void {
            ipcRoot.controlBar.hide()
        }
        function setUiScale(scale: string): void {
            ipcRoot.hostBar.setUiScale(scale)
        }
        function setUiScaleManual(scale: string): void {
            ipcRoot.hostBar.setUiScaleManual(scale)
        }
        function setUiScaleAuto(): void {
            ipcRoot.hostBar.setUiScaleAuto()
        }
        function setBarEdgeMargin(px: string): void {
            ipcRoot.hostBar.setBarEdgeMargin(px)
        }
        function setBarSizeScale(scale: string): void {
            ipcRoot.hostBar.setBarSizeScale(scale)
        }
        function setFlushWindowsToBar(enabled: bool): void {
            ipcRoot.hostBar.setFlushWindowsToBar(enabled)
        }
        function setTooltipDelay(ms: string): void {
            ipcRoot.hostBar.setTooltipDelay(ms)
        }
        function setShowFreshRssPill(enabled: bool): void {
            ipcRoot.hostBar.setWidgetVisible("freshRss", enabled)
        }
        function toggleShowFreshRssPill(): void {
            ipcRoot.hostBar.toggleWidgetVisible("freshRss")
        }
        function setShowHyprInspPill(enabled: bool): void {
            ipcRoot.hostBar.setWidgetVisible("hyprInsp", enabled)
        }
        function toggleShowHyprInspPill(): void {
            ipcRoot.hostBar.toggleWidgetVisible("hyprInsp")
        }
        function setShowControlBarPill(enabled: bool): void {
            ipcRoot.hostBar.setWidgetVisible("controlBar", enabled)
        }
        function toggleShowControlBarPill(): void {
            ipcRoot.hostBar.toggleWidgetVisible("controlBar")
        }
        function setShowActiveWindowPill(enabled: bool): void {
            ipcRoot.hostBar.setWidgetVisible("activeWindow", enabled)
        }
        function toggleShowActiveWindowPill(): void {
            ipcRoot.hostBar.toggleWidgetVisible("activeWindow")
        }
        function setActiveWindowCorner(corner: string): void {
            ipcRoot.hostBar.setActiveWindowCorner(corner)
        }
        function setNotificationCorner(corner: string): void {
            if (ipcRoot.hostBar && ipcRoot.hostBar.setNotificationCorner)
                ipcRoot.hostBar.setNotificationCorner(corner)
        }
        function setNotificationTimeout(seconds: string): void {
            if (ipcRoot.hostBar && ipcRoot.hostBar.setNotificationTimeout)
                ipcRoot.hostBar.setNotificationTimeout(seconds)
        }
        function addActiveWindowExclude(pattern: string): void {
            if (ipcRoot.hostBar && ipcRoot.hostBar.addActiveWindowExclude)
                ipcRoot.hostBar.addActiveWindowExclude(pattern)
        }
        function removeActiveWindowExclude(pattern: string): void {
            if (ipcRoot.hostBar && ipcRoot.hostBar.removeActiveWindowExclude)
                ipcRoot.hostBar.removeActiveWindowExclude(pattern)
        }
        function setShowMagicWorkspacePill(enabled: bool): void {
            if (ipcRoot.hostBar && ipcRoot.hostBar.setShowMagicWorkspacePill)
                ipcRoot.hostBar.setShowMagicWorkspacePill(enabled)
            else
                ipcRoot.shell.showMagicWorkspacePill = enabled
        }
        function toggleShowMagicWorkspacePill(): void {
            shellHandler.setShowMagicWorkspacePill(!ipcRoot.shell.showMagicWorkspacePill)
        }
        function setWsMinimumShown(count: int): void {
            if (ipcRoot.hostBar && ipcRoot.hostBar.setWsMinimumShown)
                ipcRoot.hostBar.setWsMinimumShown(count)
            else
                ipcRoot.shell.wsMinimumShown = Math.max(1, Math.min(10, count))
        }
        function setWsShowOnlyActive(enabled: bool): void {
            if (ipcRoot.hostBar && ipcRoot.hostBar.setWsShowOnlyActive)
                ipcRoot.hostBar.setWsShowOnlyActive(enabled)
            else
                ipcRoot.shell.wsShowOnlyActive = enabled
        }
        function setWsShowNumbers(enabled: bool): void {
            if (ipcRoot.hostBar && ipcRoot.hostBar.setWsShowNumbers)
                ipcRoot.hostBar.setWsShowNumbers(enabled)
            else
                ipcRoot.shell.wsShowNumbers = !!enabled
        }
        function setWsStartupWorkspace(workspace: int): void {
            if (ipcRoot.hostBar && ipcRoot.hostBar.setWsStartupWorkspace)
                ipcRoot.hostBar.setWsStartupWorkspace(workspace)
            else
                ipcRoot.shell.wsStartupWorkspace = Math.max(0, Math.min(10, workspace))
        }
        function setWsStartupCloseMagic(enabled: bool): void {
            if (ipcRoot.hostBar && ipcRoot.hostBar.setWsStartupCloseMagic)
                ipcRoot.hostBar.setWsStartupCloseMagic(enabled)
            else
                ipcRoot.shell.wsStartupCloseMagic = enabled
        }
        function addWsSlot(): void {
            if (ipcRoot.hostBar && ipcRoot.hostBar.addWsSlot)
                ipcRoot.hostBar.addWsSlot()
        }
        function removeWsSlot(index: int): void {
            if (ipcRoot.hostBar && ipcRoot.hostBar.removeWsSlot)
                ipcRoot.hostBar.removeWsSlot(index)
        }
        function moveWsSlot(index: int, delta: int): void {
            if (ipcRoot.hostBar && ipcRoot.hostBar.moveWsSlot)
                ipcRoot.hostBar.moveWsSlot(index, delta)
        }
        function setWsSlotLabel(index: int, label: string): void {
            if (ipcRoot.hostBar && ipcRoot.hostBar.setWsSlotLabel)
                ipcRoot.hostBar.setWsSlotLabel(index, label)
        }
        function setWsSlotFont(index: int, font: string): void {
            if (ipcRoot.hostBar && ipcRoot.hostBar.setWsSlotFont)
                ipcRoot.hostBar.setWsSlotFont(index, font)
        }
    }
}
