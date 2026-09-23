import QtQuick

// Hover magnify + click jump for one bar face or icon cell.
// Host must set clip: false and apply transform from mag / jumpY / growUp.
Item {
    id: root
    width: 0
    height: 0

    required property var bar
    required property Item host
    required property bool hovered
    // Quick Launch / tray / workspaces: pass cosine falloff instead of self-scale.
    property bool useNeighbor: false
    property real neighborScale: 1
    // false = participate even when Options → Dock → Apply to is Quick Launch.
    property bool respectScope: true

    property real mag: {
        void bar.dockEffect
        void bar.dockScope
        void bar.dockMaxScale
        if (useNeighbor)
            return neighborScale
        if (!bar || typeof bar.dockSelfMag !== "function")
            return 1
        return bar.dockSelfMag(hovered)
    }
    property real jumpY: 0
    readonly property bool growUp: {
        if (!bar || !host || typeof bar.dockGrowUpFor !== "function")
            return false
        return !!bar.dockGrowUpFor(host)
    }

    Behavior on mag {
        NumberAnimation { duration: 90; easing.type: Easing.OutQuad }
    }

    SequentialAnimation {
        id: jumpAnim
        NumberAnimation {
            target: root
            property: "jumpY"
            to: {
                const px = (root.bar && typeof root.bar.dockJumpPixels === "function") ? root.bar.dockJumpPixels() : 8
                return root.growUp ? -px : px
            }
            duration: 90
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: root
            property: "jumpY"
            to: 0
            duration: 220
            easing.type: Easing.OutBounce
        }
        onStopped: root.jumpY = 0
    }

    onMagChanged: {
        if (root.mag <= 1.01 && !jumpAnim.running)
            root.jumpY = 0
    }

    function jump() {
        if (!bar || typeof bar.dockJumpOn !== "function" || !bar.dockJumpOn())
            return
        if (respectScope && typeof bar.dockScopeAll === "function" && !bar.dockScopeAll())
            return
        jumpAnim.restart()
    }
}
