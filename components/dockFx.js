.pragma library

function magOn(bar) {
    if (!bar)
        return false
    const e = String(bar.dockEffect || "off")
    return e === "magnify" || e === "both"
}

function jumpOn(bar) {
    if (!bar)
        return false
    const e = String(bar.dockEffect || "off")
    return e === "jump" || e === "both"
}

function allIcons(bar) {
    if (!bar)
        return false
    return String(bar.dockScope || "icons") !== "quicklaunch"
}

function maxScale(bar) {
    const m = Number(bar && bar.dockMaxScale)
    return Math.max(1.05, Math.min(1.8, m > 0 ? m : 1.28))
}

function selfMag(bar, hovered) {
    if (!hovered || !magOn(bar) || !allIcons(bar))
        return 1
    return maxScale(bar)
}

function growUp(bar, item) {
    try {
        if (bar && bar.isDualLayout && bar.isDualLayout())
            return bar.edgeForItem(item) === "bottom"
    } catch (e) {}
    return !!(bar && bar.barPosition === "bottom")
}

function jumpPx(bar) {
    return Math.max(4, Math.min(20, Math.round((bar && bar.dockJumpPx) ? bar.dockJumpPx : 8)))
}

function radiusPx(bar) {
    return Math.max(32, Math.min(160, Math.round((bar && bar.dockRadius) ? bar.dockRadius : 72)))
}

// Cosine falloff from hover X along a row. pillHovered must be the unscaled
// pill HoverHandler — transformed cell hit-boxes can stay "hovered" after leave.
function neighborMag(bar, hoverX, cell, pillHovered, requireAllIcons) {
    if (!bar || !pillHovered || hoverX < 0 || !cell)
        return 1
    if (!magOn(bar))
        return 1
    if (requireAllIcons && !allIcons(bar))
        return 1
    const cx = cell.x + cell.width / 2
    const dist = Math.abs(hoverX - cx)
    const r = radiusPx(bar)
    if (dist >= r)
        return 1
    const t = Math.cos((dist / r) * Math.PI / 2)
    return 1 + (maxScale(bar) - 1) * t
}
