// Config.qml — theme, fonts, sizes, visibility defaults (single source of truth).
// shell.qml instantiates Config once and aliases every property on `bar`.
// Widgets take `required property var bar` and read bar.xxx.
// Day-to-day colors/fonts: control strip → Themes (state/theme-colors.json).
// Search section headers below (e.g. FONTS, WIDGET VISIBILITY, NOTIFICATION BELL).
//   - Animation & Interaction (durations, easings, tooltip delays)
//   - Enums (menu button types)
//
// Keep this file extremely well commented. Every property must explain:
//   - What it controls
//   - Typical/used values
//   - Which widgets/components consume it
// =============================================================================

import QtQuick

QtObject {
    id: theme

    // =========================================================================
    // BASE PALETTE (liquid glass — cool dark-blue slate + vivid teal accent)
    // =========================================================================
    // Pulled from the CachyOS / Ventoy desktop wallpaper: deep magenta→pink field,
    // cool blue ribbons, and the installer logo's teal→cyan gradient (pushed
    // brighter/more saturated). Glass chrome is cool blue-slate (not purple, not
    // washed mid-grey) so teal accents and wallpaper blues stay cohesive.
    //
    // Hierarchy:
    //   bg/surface  → solid blue-slate fallbacks (elevated UI, tracks)
    //   glass*      → translucent dark-blue glass (bar / pills / popups)
    //   accent      → bright teal-cyan (active, hover border, highlights)
    //   muted       → vivid magenta-pink (secondary accent + warnings / mute / DND)

    // Writable so the control-bar Colors panel can edit live and persist.
    // Factory defaults live in themeFactoryDefaults() / themeReset().
    property color bg:        "#0a0e16"   // Deep blue-charcoal (solid fallback)
    property color surface:   "#141a24"   // Elevated blue-slate panels / tracks
    property color text:      "#f0f4fc"   // Main text — menu headers / titles only
    property color subtext:   "#a8b4c8"   // Secondary text — menu body, hints, labels
    property color barText:   "#f0f4fc"   // Widget face text on the main bar (clock, stats, IP, …)
    property color overlay:   "#6e7a90"   // Muted blue-grey (not flat mid-grey)

    // Accent = interactive chrome only: focus rings, selected outlines, hover rims,
    // selection highlights. NOT section titles, status text, or monochrome icons
    // (use text / buttonTextActive / iconColor for those).
    property color accent:    "#00F0E0"   // Vivid teal-cyan (interactive highlight)
    property color muted:     "#FF3D8A"   // Magenta-pink secondary + warning / mute / DND

    // Semantic / status colors
    property color todayBg:   "#00FFE8"   // Calendar "today" (extra-bright cyan)
    property color weekday:   "#FF5C9A"   // Calendar weekday headers (pink secondary)
    property color clock:     "#ffffff"   // Clock text (max contrast)

    // =========================================================================
    // GLASSMORPHIC TOKENS (liquid glass — frosted dark-blue slate + teal edges)
    // =========================================================================
    // Semi-transparent fills so the wallpaper tint shows through. Soft teal rim
    // glow + white top-edge sheen sell the glossy glass look. Opacity order:
    //   glassBg (bar) < glassPill < glassPopup  (popups most opaque for readability)
    // Writable for Colors panel live editing.

    // Main bar — cool dark-blue glass, wallpaper peeks through
    property color glassBg:          Qt.rgba(0.04, 0.06, 0.10, 0.58)
    // Soft cool rim (desaturated — not a vivid teal neon edge)
    property color glassBorder:      Qt.rgba(0.55, 0.72, 0.82, 0.16)
    // Top-edge light catch — transparent so the bar has no thin highlight strip
    property color glassHighlight:   "transparent"

    // Pills — slightly denser glass so content stays sharp
    property color glassPillBg:      Qt.rgba(0.05, 0.07, 0.12, 0.72)
    property color glassHover:       Qt.rgba(0.0, 0.85, 0.80, 0.22)  // Teal glow on hover

    // Popups — more opaque for readability, still blue-slate glass
    property color glassPopupBg:         Qt.rgba(0.04, 0.06, 0.10, 0.90)
    property color glassPopupBorder:     Qt.rgba(0.55, 0.72, 0.82, 0.18)
    property color glassPopupHighlight:  Qt.rgba(1, 1, 1, 0.18)

    // Convenience aliases used by many pills (same Theme slot — no separate Colors row).
    // pillBg always tracks glassPillBg; pillHover / controlHoverBg track glassHover.
    // setThemeColor keeps these in sync; they are NOT independent editable keys.
    property color pillBg:     glassPillBg
    property color pillBorder: Qt.rgba(1, 1, 1, 0.10)  // Soft glass rim; hover uses accent
    property color pillHover:  glassHover

    // =========================================================================
    // STATE COLORS (hover, pressed, active, focus — single source of truth)
    // =========================================================================
    // These provide consistent interactive feedback across pills, buttons, and popups.
    // Use these instead of ad-hoc Qt.rgba or hex values for hover/pressed states.
    // Isolation rule: each Colors-panel key writes ONLY its own property (plus the
    // intentional aliases listed above). No cascading into unrelated keys.

    // Pill-level hover border (tracks accent by default; not a separate Colors row)
    property color pillHoverBorder: accent

    // Per-item hover chips — translucent teal glow (QuickLaunch, tray, workspaces, …)
    property color iconHoverBg: Qt.rgba(0.0, 0.85, 0.82, 0.28)

    // General control states (used inside popups and complex widgets)
    property color controlHoverBg:   glassHover
    property color controlActiveBg:  Qt.rgba(0.0, 0.70, 0.75, 0.35)  // Pressed / toggled teal

    // Specific popup button hover
    property color popupButtonHoverBg: Qt.rgba(0.08, 0.10, 0.16, 0.65)

    // Control-bar toolbar / chip button fill (inactive). Isolated from pill/widget bg
    // so editing "Widget background" does not recolor Position / Colors / Audio tabs.
    // Default matches historical pillBg so the look is unchanged until edited.
    property color buttonBg:         Qt.rgba(0.05, 0.07, 0.12, 0.72)

    // Control-bar menu tab labels (Position / Colors / …) — independent of accent/subtext
    property color buttonText:       "#a8b4c8"   // Inactive menu button label
    property color buttonTextActive: "#00F0E0"   // Active / hovered menu button label

    // =========================================================================
    // THEME EDITOR API (control-bar Colors panel — non-coder friendly)
    // =========================================================================
    // Keys exposed in the UI map 1:1 to properties above. Derived tokens
    // (sliderFill, wsActiveBorder, …) stay bound to accent/muted/etc.
    //
    // Isolation: setThemeColor(key) mutates only that key (+ documented aliases).
    // Shared visual roles (button tabs 1/6/11 → buttonBg; bar pills → glassPillBg)
    // use the same Theme property on purpose — never accidental cross-talk.

    readonly property var themeEditableKeys: [
        "glassBg", "glassPillBg", "glassPopupBg",
        "glassBorder", "glassPopupBorder", "pillBorder",
        "glassHighlight", "glassPopupHighlight",
        "glassHover", "iconHoverBg",
        "accent", "muted",
        "text", "subtext", "barText", "overlay",
        "bg", "surface", "clock",
        "buttonBg", "controlActiveBg", "popupButtonHoverBg",
        "buttonText", "buttonTextActive",
        "wsActiveBg", "wsActiveText", "wsInactiveText",
        "audioSpeakerTier1", "audioSpeakerTier2", "audioSpeakerTier3", "audioSpeakerTier4",
        "audioMicTier1", "audioMicTier2", "audioMicTier3", "audioMicTier4",
        "iconColor", "audioSpeakerIcon", "audioMicIcon",
        "statUtilTier1", "statUtilTier2", "statUtilTier3", "statUtilTier4",
        "statCpuTier1", "statCpuTier2", "statCpuTier3", "statCpuTier4",
        "statMemTier1", "statMemTier2", "statMemTier3", "statMemTier4",
        "statGpuTier1", "statGpuTier2", "statGpuTier3", "statGpuTier4",
        "statTempCool", "statTempWarm", "statTempHot",
        "qlRunningDot"
    ]

    // Numeric theme keys (thresholds) — exported/imported with colors JSON.
    readonly property var themeEditableNumbers: [
        "audioUtilThreshold1", "audioUtilThreshold2", "audioUtilThreshold3",
        "audioMicUtilThreshold1", "audioMicUtilThreshold2", "audioMicUtilThreshold3",
        "statUtilThreshold1", "statUtilThreshold2", "statUtilThreshold3",
        "statTempWarmAt", "statTempHotAt"
    ]

    // Friendly rows shown in the Colors → Theming tab.
    // section: "colors" | "text" | "effects"
    // opacity: true → also appears in the Opacity section as an alpha slider.
    readonly property var themeUiRows: [
        // ── Colors (solid fills / accents) ──
        { key: "buttonBg",    label: "Button background", opacity: true,  section: "colors" },
        { key: "glassBg",     label: "Bar background",    opacity: true,  section: "colors" },
        { key: "glassBorder", label: "Border",            opacity: true,  section: "colors" },
        { key: "glassPillBg", label: "Widget / pill fill", opacity: true, section: "colors" },
        { key: "pillBorder",  label: "Pill border",       opacity: true,  section: "colors" },
        { key: "glassPopupBg",label: "Menu background",   opacity: true,  section: "colors" },
        { key: "glassPopupBorder", label: "Menu border",  opacity: true,  section: "colors" },
        { key: "accent",      label: "Accent (highlights)", opacity: false, section: "colors" },
        { key: "muted",       label: "Warning / pink",    opacity: false, section: "colors" },
        { key: "controlActiveBg", label: "Active button", opacity: true,  section: "colors" },
        { key: "wsActiveBg",  label: "Active workspace",  opacity: true,  section: "colors" },
        { key: "iconColor", label: "Icon color",   opacity: false, section: "colors" },
        { key: "qlRunningDot", label: "Running app dot", opacity: false, section: "colors" },
        // ── Text ──
        { key: "text",        label: "Main text (menu headers)", opacity: false, section: "text" },
        { key: "subtext",     label: "Secondary text (menu body)", opacity: false, section: "text" },
        { key: "barText",     label: "Bar widget text", opacity: false, section: "text" },
        { key: "buttonText",  label: "Button text",       opacity: false, section: "text" },
        { key: "buttonTextActive", label: "Active button text", opacity: false, section: "text" },
        { key: "wsActiveText", label: "Active workspace text", opacity: false, section: "text" },
        { key: "wsInactiveText", label: "Workspace text", opacity: false, section: "text" },
        // ── Special / Effects ──
        { key: "glassHover",  label: "Hover glow",        opacity: true,  section: "effects" },
        { key: "glassHighlight", label: "Top edge shine", opacity: true,  section: "effects" },
        { key: "iconHoverBg", label: "Icon hover glow",   opacity: true,  section: "effects" },
        { key: "glassPopupHighlight", label: "Menu top shine", opacity: true, section: "effects" }
    ]

    // Output (speaker) volume tiers — Themes → Thresholds.
    readonly property var themeVolumeTierUiRows: [
        { key: "audioSpeakerTier1", label: "Out low",    opacity: false },
        { key: "audioSpeakerTier2", label: "Out mid",    opacity: false },
        { key: "audioSpeakerTier3", label: "Out high",   opacity: false },
        { key: "audioSpeakerTier4", label: "Out peak",   opacity: false }
    ]

    // Input (mic) volume tiers — independent from output.
    readonly property var themeMicVolumeTierUiRows: [
        { key: "audioMicTier1", label: "In low",    opacity: false },
        { key: "audioMicTier2", label: "In mid",    opacity: false },
        { key: "audioMicTier3", label: "In high",   opacity: false },
        { key: "audioMicTier4", label: "In peak",   opacity: false }
    ]

    // Shared fallback (older themes). Thresholds UI uses the per-metric rows.
    readonly property var themeStatUtilTierUiRows: [
        { key: "statUtilTier1", label: "Load low",    opacity: false },
        { key: "statUtilTier2", label: "Load mid",    opacity: false },
        { key: "statUtilTier3", label: "Load high",   opacity: false },
        { key: "statUtilTier4", label: "Load peak",   opacity: false }
    ]

    readonly property var themeStatCpuTierUiRows: [
        { key: "statCpuTier1", label: "CPU low",    opacity: false },
        { key: "statCpuTier2", label: "CPU mid",    opacity: false },
        { key: "statCpuTier3", label: "CPU high",   opacity: false },
        { key: "statCpuTier4", label: "CPU peak",   opacity: false }
    ]
    readonly property var themeStatMemTierUiRows: [
        { key: "statMemTier1", label: "Mem low",    opacity: false },
        { key: "statMemTier2", label: "Mem mid",    opacity: false },
        { key: "statMemTier3", label: "Mem high",   opacity: false },
        { key: "statMemTier4", label: "Mem peak",   opacity: false }
    ]
    readonly property var themeStatGpuTierUiRows: [
        { key: "statGpuTier1", label: "GPU low",    opacity: false },
        { key: "statGpuTier2", label: "GPU mid",    opacity: false },
        { key: "statGpuTier3", label: "GPU high",   opacity: false },
        { key: "statGpuTier4", label: "GPU peak",   opacity: false }
    ]

    // SysStats temperature label colors (CPU / GPU).
    readonly property var themeStatTempUiRows: [
        { key: "statTempCool", label: "Temp cool", opacity: false },
        { key: "statTempWarm", label: "Temp warm", opacity: false },
        { key: "statTempHot",  label: "Temp hot",  opacity: false }
    ]

    function _clamp01(n) {
        var x = Number(n)
        if (!(x >= 0)) x = 0
        if (x > 1) x = 1
        return x
    }

    function _byteHex(n) {
        var v = Math.round(_clamp01(n) * 255)
        if (v < 0) v = 0
        if (v > 255) v = 255
        var s = v.toString(16)
        return s.length < 2 ? ("0" + s) : s
    }

    function colorToHex(c) {
        if (!c) return "#000000"
        return "#" + _byteHex(c.r) + _byteHex(c.g) + _byteHex(c.b)
    }

    function parseHex(hex) {
        if (!hex) return null
        var s = ("" + hex).trim()
        if (s.charAt(0) === "#") s = s.substring(1)
        if (s.length === 3) {
            s = s.charAt(0) + s.charAt(0) + s.charAt(1) + s.charAt(1) + s.charAt(2) + s.charAt(2)
        }
        if (s.length !== 6) return null
        var r = parseInt(s.substring(0, 2), 16)
        var g = parseInt(s.substring(2, 4), 16)
        var b = parseInt(s.substring(4, 6), 16)
        if (isNaN(r) || isNaN(g) || isNaN(b)) return null
        return { r: r / 255, g: g / 255, b: b / 255 }
    }

    function colorWithAlpha(c, a) {
        if (!c) return Qt.rgba(0, 0, 0, _clamp01(a))
        return Qt.rgba(c.r, c.g, c.b, _clamp01(a))
    }

    function colorFromHexAlpha(hex, a) {
        var p = parseHex(hex)
        if (!p) return null
        return Qt.rgba(p.r, p.g, p.b, _clamp01(a === undefined ? 1 : a))
    }

    function colorToThemeEntry(c) {
        return { hex: colorToHex(c), alpha: c ? _clamp01(c.a) : 1 }
    }

    function themeEntryToColor(entry) {
        if (!entry) return null
        if (typeof entry === "string")
            return colorFromHexAlpha(entry, 1)
        var hex = entry.hex !== undefined ? entry.hex : entry.color
        var a = entry.alpha !== undefined ? entry.alpha : 1
        return colorFromHexAlpha(hex, a)
    }

    function getThemeColor(key) {
        switch (key) {
        case "bg": return bg
        case "surface": return surface
        case "text": return text
        case "subtext": return subtext
        case "barText": return barText
        case "overlay": return overlay
        case "accent": return accent
        case "muted": return muted
        case "todayBg": return todayBg
        case "weekday": return weekday
        case "clock": return clock
        case "glassBg": return glassBg
        case "glassBorder": return glassBorder
        case "glassHighlight": return glassHighlight
        case "glassPillBg": return glassPillBg
        case "glassHover": return glassHover
        case "glassPopupBg": return glassPopupBg
        case "glassPopupBorder": return glassPopupBorder
        case "glassPopupHighlight": return glassPopupHighlight
        case "pillBorder": return pillBorder
        case "iconHoverBg": return iconHoverBg
        case "buttonBg": return buttonBg
        case "controlActiveBg": return controlActiveBg
        case "popupButtonHoverBg": return popupButtonHoverBg
        case "buttonText": return buttonText
        case "buttonTextActive": return buttonTextActive
        case "wsActiveBg": return wsActiveBg
        case "wsActiveText": return wsActiveText
        case "wsInactiveText": return wsInactiveText
        case "audioSpeakerTier1": return audioSpeakerTier1
        case "audioSpeakerTier2": return audioSpeakerTier2
        case "audioSpeakerTier3": return audioSpeakerTier3
        case "audioSpeakerTier4": return audioSpeakerTier4
        case "audioMicTier1": return audioMicTier1
        case "audioMicTier2": return audioMicTier2
        case "audioMicTier3": return audioMicTier3
        case "audioMicTier4": return audioMicTier4
        case "iconColor": return iconColor
        case "audioSpeakerIcon": return audioSpeakerIcon
        case "audioMicIcon": return audioMicIcon
        case "statUtilTier1": return statUtilTier1
        case "statUtilTier2": return statUtilTier2
        case "statUtilTier3": return statUtilTier3
        case "statUtilTier4": return statUtilTier4
        case "statCpuTier1": return statCpuTier1
        case "statCpuTier2": return statCpuTier2
        case "statCpuTier3": return statCpuTier3
        case "statCpuTier4": return statCpuTier4
        case "statMemTier1": return statMemTier1
        case "statMemTier2": return statMemTier2
        case "statMemTier3": return statMemTier3
        case "statMemTier4": return statMemTier4
        case "statGpuTier1": return statGpuTier1
        case "statGpuTier2": return statGpuTier2
        case "statGpuTier3": return statGpuTier3
        case "statGpuTier4": return statGpuTier4
        case "statTempCool": return statTempCool
        case "statTempWarm": return statTempWarm
        case "statTempHot": return statTempHot
        case "qlRunningDot": return qlRunningDot
        default: return null
        }
    }

    // Strict isolation: each key writes only itself, except documented aliases
    // (glassPillBg→pillBg, glassHover→pillHover+controlHoverBg, accent→pillHoverBorder,
    //  volume speaker tiers mirror mic tiers when set via speaker keys).
    function setThemeColor(key, c) {
        if (!c) return false
        switch (key) {
        case "bg": bg = c; break
        case "surface": surface = c; break
        case "text": text = c; break
        case "subtext": subtext = c; break
        case "barText": barText = c; break
        case "overlay": overlay = c; break
        case "accent":
            accent = c
            pillHoverBorder = c   // hover rim tracks accent (not a separate Colors key)
            break
        case "muted": muted = c; break
        case "todayBg": todayBg = c; break
        case "weekday": weekday = c; break
        case "clock": clock = c; break
        case "glassBg": glassBg = c; break
        case "glassBorder": glassBorder = c; break
        case "glassHighlight": glassHighlight = c; break
        case "glassPillBg": glassPillBg = c; pillBg = c; break
        case "glassHover":
            glassHover = c
            pillHover = c
            controlHoverBg = c
            break
        case "glassPopupBg": glassPopupBg = c; break
        case "glassPopupBorder": glassPopupBorder = c; break
        case "glassPopupHighlight": glassPopupHighlight = c; break
        case "pillBorder": pillBorder = c; break
        case "iconHoverBg": iconHoverBg = c; break
        case "buttonBg": buttonBg = c; break
        case "controlActiveBg": controlActiveBg = c; break
        case "popupButtonHoverBg": popupButtonHoverBg = c; break
        case "buttonText": buttonText = c; break
        case "buttonTextActive": buttonTextActive = c; break
        case "wsActiveBg": wsActiveBg = c; break
        case "wsActiveText": wsActiveText = c; break
        case "wsInactiveText": wsInactiveText = c; break
        case "audioSpeakerTier1": audioSpeakerTier1 = c; break
        case "audioSpeakerTier2": audioSpeakerTier2 = c; break
        case "audioSpeakerTier3": audioSpeakerTier3 = c; break
        case "audioSpeakerTier4": audioSpeakerTier4 = c; break
        case "audioMicTier1": audioMicTier1 = c; break
        case "audioMicTier2": audioMicTier2 = c; break
        case "audioMicTier3": audioMicTier3 = c; break
        case "audioMicTier4": audioMicTier4 = c; break
        case "iconColor":
            iconColor = c
            // Keep speaker/mic glyphs in sync with the shared icon color control
            audioSpeakerIcon = c
            audioMicIcon = c
            break
        case "audioSpeakerIcon":
            audioSpeakerIcon = c
            iconColor = c
            audioMicIcon = c
            break
        case "audioMicIcon": audioMicIcon = c; break
        case "statUtilTier1": statUtilTier1 = c; break
        case "statUtilTier2": statUtilTier2 = c; break
        case "statUtilTier3": statUtilTier3 = c; break
        case "statUtilTier4": statUtilTier4 = c; break
        case "statCpuTier1": statCpuTier1 = c; break
        case "statCpuTier2": statCpuTier2 = c; break
        case "statCpuTier3": statCpuTier3 = c; break
        case "statCpuTier4": statCpuTier4 = c; break
        case "statMemTier1": statMemTier1 = c; break
        case "statMemTier2": statMemTier2 = c; break
        case "statMemTier3": statMemTier3 = c; break
        case "statMemTier4": statMemTier4 = c; break
        case "statGpuTier1": statGpuTier1 = c; break
        case "statGpuTier2": statGpuTier2 = c; break
        case "statGpuTier3": statGpuTier3 = c; break
        case "statGpuTier4": statGpuTier4 = c; break
        case "statTempCool": statTempCool = c; break
        case "statTempWarm": statTempWarm = c; break
        case "statTempHot": statTempHot = c; break
        case "qlRunningDot": qlRunningDot = c; break
        default: return false
        }
        return true
    }

    function getThemeNumber(key) {
        switch (key) {
        case "audioUtilThreshold1": return audioUtilThreshold1
        case "audioUtilThreshold2": return audioUtilThreshold2
        case "audioUtilThreshold3": return audioUtilThreshold3
        case "audioMicUtilThreshold1": return audioMicUtilThreshold1
        case "audioMicUtilThreshold2": return audioMicUtilThreshold2
        case "audioMicUtilThreshold3": return audioMicUtilThreshold3
        case "statUtilThreshold1": return statUtilThreshold1
        case "statUtilThreshold2": return statUtilThreshold2
        case "statUtilThreshold3": return statUtilThreshold3
        case "statTempWarmAt": return statTempWarmAt
        case "statTempHotAt": return statTempHotAt
        default: return null
        }
    }

    function setThemeNumber(key, n) {
        var v = Math.round(Number(n))
        if (!(v >= 0)) v = 0
        switch (key) {
        case "audioUtilThreshold1":
            if (v > 100) v = 100
            audioUtilThreshold1 = Math.min(v, audioUtilThreshold2 - 1)
            if (audioUtilThreshold1 < 1) audioUtilThreshold1 = 1
            break
        case "audioUtilThreshold2":
            if (v > 100) v = 100
            audioUtilThreshold2 = Math.max(audioUtilThreshold1 + 1, Math.min(v, audioUtilThreshold3 - 1))
            break
        case "audioUtilThreshold3":
            if (v > 100) v = 100
            audioUtilThreshold3 = Math.max(audioUtilThreshold2 + 1, Math.min(v, 99))
            break
        case "audioMicUtilThreshold1":
            if (v > 100) v = 100
            audioMicUtilThreshold1 = Math.min(v, audioMicUtilThreshold2 - 1)
            if (audioMicUtilThreshold1 < 1) audioMicUtilThreshold1 = 1
            break
        case "audioMicUtilThreshold2":
            if (v > 100) v = 100
            audioMicUtilThreshold2 = Math.max(audioMicUtilThreshold1 + 1, Math.min(v, audioMicUtilThreshold3 - 1))
            break
        case "audioMicUtilThreshold3":
            if (v > 100) v = 100
            audioMicUtilThreshold3 = Math.max(audioMicUtilThreshold2 + 1, Math.min(v, 99))
            break
        case "statUtilThreshold1":
            if (v > 100) v = 100
            statUtilThreshold1 = Math.min(v, statUtilThreshold2 - 1)
            if (statUtilThreshold1 < 1) statUtilThreshold1 = 1
            break
        case "statUtilThreshold2":
            if (v > 100) v = 100
            statUtilThreshold2 = Math.max(statUtilThreshold1 + 1, Math.min(v, statUtilThreshold3 - 1))
            break
        case "statUtilThreshold3":
            if (v > 100) v = 100
            statUtilThreshold3 = Math.max(statUtilThreshold2 + 1, Math.min(v, 99))
            break
        case "statTempWarmAt":
            // °C cutoffs — allow up to 150
            if (v > 150) v = 150
            if (v < 1) v = 1
            statTempWarmAt = Math.min(v, statTempHotAt - 1)
            break
        case "statTempHotAt":
            if (v > 150) v = 150
            if (v < 2) v = 2
            statTempHotAt = Math.max(statTempWarmAt + 1, v)
            break
        default: return false
        }
        return true
    }

    function setThemeAlpha(key, a) {
        var cur = getThemeColor(key)
        if (!cur) return false
        // Top-edge shine defaults to transparent black — use white when turning on
        if ((key === "glassHighlight" || key === "glassPopupHighlight")
                && cur.a < 0.01 && a > 0.01
                && cur.r < 0.02 && cur.g < 0.02 && cur.b < 0.02) {
            return setThemeColor(key, Qt.rgba(1, 1, 1, _clamp01(a)))
        }
        return setThemeColor(key, colorWithAlpha(cur, a))
    }

    function themeExport(name) {
        var colors = {}
        var keys = themeEditableKeys
        for (var i = 0; i < keys.length; i++) {
            var k = keys[i]
            var c = getThemeColor(k)
            if (c)
                colors[k] = colorToThemeEntry(c)
        }
        var numbers = {}
        var nkeys = themeEditableNumbers
        for (var j = 0; j < nkeys.length; j++) {
            var nk = nkeys[j]
            var nv = getThemeNumber(nk)
            if (nv !== null && nv !== undefined)
                numbers[nk] = nv
        }
        return {
            name: name && ("" + name).length ? ("" + name) : "Custom",
            version: 1,
            colors: colors,
            numbers: numbers,
            fonts: {
                fontFamily: fontFamily,
                fontMono: fontMono,
                fontScale: fontScale,
                fontMonoScale: fontMonoScale,
                fontMain: fontMain,
                fontSecondary: fontSecondary,
                fontBar: fontBar,
                fontMainScale: fontMainScale,
                fontSecondaryScale: fontSecondaryScale,
                fontBarScale: fontBarScale
            }
        }
    }

    function themeApply(obj) {
        if (!obj) return false
        var colors = obj.colors !== undefined ? obj.colors : obj
        if (!colors || typeof colors !== "object") return false
        var keys = themeEditableKeys
        var any = false
        for (var i = 0; i < keys.length; i++) {
            var k = keys[i]
            if (colors[k] === undefined) continue
            var c = themeEntryToColor(colors[k])
            if (c && setThemeColor(k, c))
                any = true
        }
        // Optional numeric thresholds (volume tiers)
        var numbers = obj.numbers
        if (numbers && typeof numbers === "object") {
            var nkeys = themeEditableNumbers
            for (var j = 0; j < nkeys.length; j++) {
                var nk = nkeys[j]
                if (numbers[nk] === undefined) continue
                if (setThemeNumber(nk, numbers[nk]))
                    any = true
            }
        }
        // Optional font families + scale + per-role faces/sizes
        if (obj.fonts && typeof obj.fonts === "object") {
            if (obj.fonts.fontFamily !== undefined && ("" + obj.fonts.fontFamily).length) {
                fontFamily = "" + obj.fonts.fontFamily
                any = true
            }
            if (obj.fonts.fontMono !== undefined && ("" + obj.fonts.fontMono).length) {
                fontMono = "" + obj.fonts.fontMono
                any = true
            }
            if (obj.fonts.fontScale !== undefined) {
                if (setThemeFontScale(obj.fonts.fontScale))
                    any = true
            }
            if (obj.fonts.fontMonoScale !== undefined) {
                if (setThemeFontRoleScale("mono", obj.fonts.fontMonoScale))
                    any = true
            }
            if (obj.fonts.fontMain !== undefined) {
                fontMain = ("" + obj.fonts.fontMain).trim()
                any = true
            }
            if (obj.fonts.fontSecondary !== undefined) {
                fontSecondary = ("" + obj.fonts.fontSecondary).trim()
                any = true
            }
            if (obj.fonts.fontBar !== undefined) {
                fontBar = ("" + obj.fonts.fontBar).trim()
                any = true
            }
            if (obj.fonts.fontMainScale !== undefined) {
                if (setThemeFontRoleScale("main", obj.fonts.fontMainScale))
                    any = true
            }
            if (obj.fonts.fontSecondaryScale !== undefined) {
                if (setThemeFontRoleScale("secondary", obj.fonts.fontSecondaryScale))
                    any = true
            }
            if (obj.fonts.fontBarScale !== undefined) {
                if (setThemeFontRoleScale("bar", obj.fonts.fontBarScale))
                    any = true
            }
        }
        // Re-sync alias-style props after bulk apply (only true aliases)
        pillBg = glassPillBg
        pillHover = glassHover
        controlHoverBg = glassHover
        pillHoverBorder = accent
        return any
    }

    function setThemeFont(key, value) {
        var s = (value === undefined || value === null) ? "" : ("" + value).trim()
        // Role fonts may be cleared (empty = inherit UI font)
        if (key === "fontMain") {
            fontMain = s
            return true
        }
        if (key === "fontSecondary") {
            fontSecondary = s
            return true
        }
        if (key === "fontBar") {
            fontBar = s
            return true
        }
        if (!s.length)
            return false
        if (key === "fontFamily") {
            fontFamily = s
            return true
        }
        if (key === "fontMono") {
            fontMono = s
            return true
        }
        return false
    }

    function setThemeFontScale(s) {
        var x = Number(s)
        if (!(x > 0) || isNaN(x))
            return false
        if (x < 0.70) x = 0.70
        if (x > 1.50) x = 1.50
        // Snap to 0.01 so the slider feels stable
        fontScale = Math.round(x * 100) / 100
        return true
    }

    // role: "main" | "secondary" | "bar" | "mono" | "ui" (ui → fontScale)
    function setThemeFontRoleScale(role, s) {
        var x = _clampFontRoleScale(s)
        if (role === "main") {
            fontMainScale = x
            return true
        }
        if (role === "secondary") {
            fontSecondaryScale = x
            return true
        }
        if (role === "bar") {
            fontBarScale = x
            return true
        }
        if (role === "mono") {
            fontMonoScale = x
            return true
        }
        if (role === "ui") {
            fontScale = x
            return true
        }
        return false
    }

    // Apply a plain text face for Main / Secondary / Bar (no Nerd Font prefix — text only).
    function setRoleFontFamily(role, family) {
        var name = (family === undefined || family === null) ? "" : ("" + family).trim()
        var stack = name.length ? (name + ", sans-serif") : ""
        if (role === "main") {
            fontMain = stack
            return true
        }
        if (role === "secondary") {
            fontSecondary = stack
            return true
        }
        if (role === "bar") {
            fontBar = stack
            return true
        }
        return false
    }

    function primaryRoleFontFamily(role) {
        var stack = ""
        if (role === "main")
            stack = fontMain
        else if (role === "secondary")
            stack = fontSecondary
        else if (role === "bar")
            stack = fontBar
        if (!stack || !("" + stack).trim().length)
            return primaryUiFontFamily()
        return primaryFontFamily(stack)
    }

    // First family in a CSS-style stack (for dropdown selection display).
    function primaryFontFamily(stack) {
        if (!stack)
            return ""
        var parts = ("" + stack).split(",")
        for (var i = 0; i < parts.length; i++) {
            var p = ("" + parts[i]).trim()
            if (!p.length)
                continue
            // Skip generic fallbacks
            var low = p.toLowerCase()
            if (low === "monospace" || low === "sans-serif" || low === "serif"
                    || low === "cursive" || low === "fantasy" || low === "system-ui")
                continue
            return p
        }
        return ("" + parts[0]).trim()
    }

    // Preferred UI text face (skips leading icon/nerd font so dropdown matches text face).
    function primaryUiFontFamily() {
        if (!fontFamily)
            return ""
        var parts = ("" + fontFamily).split(",")
        var iconHints = ["symbols nerd font", "nerd font", "font awesome", "material design icons"]
        for (var i = 0; i < parts.length; i++) {
            var p = ("" + parts[i]).trim()
            if (!p.length)
                continue
            var low = p.toLowerCase()
            if (low === "monospace" || low === "sans-serif" || low === "serif"
                    || low === "cursive" || low === "fantasy" || low === "system-ui")
                continue
            var isIcon = false
            for (var j = 0; j < iconHints.length; j++) {
                if (low.indexOf(iconHints[j]) >= 0) {
                    isIcon = true
                    break
                }
            }
            if (!isIcon)
                return p
        }
        return primaryFontFamily(fontFamily)
    }

    // Apply a single UI face while keeping a Nerd Font first for bar glyphs.
    function setUiFontFamily(family) {
        var name = (family === undefined || family === null) ? "" : ("" + family).trim()
        if (!name.length)
            return false
        var icon = "Symbols Nerd Font"
        if (name.toLowerCase() === icon.toLowerCase())
            fontFamily = icon + ", sans-serif"
        else
            fontFamily = icon + ", " + name + ", sans-serif"
        return true
    }

    function setMonoFontFamily(family) {
        var name = (family === undefined || family === null) ? "" : ("" + family).trim()
        if (!name.length)
            return false
        fontMono = name + ", monospace"
        return true
    }

    // Keep role scales sane when loading older themes without them
    function ensureFontRoleDefaults() {
        fontScale = _clampFontRoleScale(fontScale)
        fontMonoScale = _clampFontRoleScale(fontMonoScale)
        fontMainScale = _clampFontRoleScale(fontMainScale)
        fontSecondaryScale = _clampFontRoleScale(fontSecondaryScale)
        fontBarScale = _clampFontRoleScale(fontBarScale)
    }

    function themeFactoryDefaults() {
        return {
            name: "Liquid glass",
            version: 1,
            colors: {
                bg: { hex: "#0a0e16", alpha: 1 },
                surface: { hex: "#141a24", alpha: 1 },
                text: { hex: "#f0f4fc", alpha: 1 },
                subtext: { hex: "#a8b4c8", alpha: 1 },
                barText: { hex: "#f0f4fc", alpha: 1 },
                overlay: { hex: "#6e7a90", alpha: 1 },
                accent: { hex: "#00F0E0", alpha: 1 },
                muted: { hex: "#FF3D8A", alpha: 1 },
                todayBg: { hex: "#00FFE8", alpha: 1 },
                weekday: { hex: "#FF5C9A", alpha: 1 },
                clock: { hex: "#ffffff", alpha: 1 },
                glassBg: { hex: "#0a0f1a", alpha: 0.58 },
                glassBorder: { hex: "#8cb8d1", alpha: 0.16 },
                glassHighlight: { hex: "#000000", alpha: 0 },
                glassPillBg: { hex: "#0d121e", alpha: 0.72 },
                glassHover: { hex: "#00d9cc", alpha: 0.22 },
                glassPopupBg: { hex: "#0a0f1a", alpha: 0.90 },
                glassPopupBorder: { hex: "#8cb8d1", alpha: 0.18 },
                glassPopupHighlight: { hex: "#ffffff", alpha: 0.18 },
                pillBorder: { hex: "#ffffff", alpha: 0.10 },
                iconHoverBg: { hex: "#00d9d1", alpha: 0.28 },
                buttonBg: { hex: "#0d121e", alpha: 0.72 },
                controlActiveBg: { hex: "#00b3bf", alpha: 0.35 },
                popupButtonHoverBg: { hex: "#141a29", alpha: 0.65 },
                buttonText: { hex: "#a8b4c8", alpha: 1 },
                buttonTextActive: { hex: "#00F0E0", alpha: 1 },
                wsActiveBg: { hex: "#00d9cc", alpha: 0.28 },
                wsActiveText: { hex: "#e6fffc", alpha: 1 },
                wsInactiveText: { hex: "#ffffff", alpha: 1 },
                audioSpeakerTier1: { hex: "#10B981", alpha: 1 },
                audioSpeakerTier2: { hex: "#F59E0B", alpha: 1 },
                audioSpeakerTier3: { hex: "#F97316", alpha: 1 },
                audioSpeakerTier4: { hex: "#EF4444", alpha: 1 },
                audioMicTier1: { hex: "#10B981", alpha: 1 },
                audioMicTier2: { hex: "#F59E0B", alpha: 1 },
                audioMicTier3: { hex: "#F97316", alpha: 1 },
                audioMicTier4: { hex: "#EF4444", alpha: 1 },
                iconColor: { hex: "#ffffff", alpha: 1 },
                audioSpeakerIcon: { hex: "#ffffff", alpha: 1 },
                audioMicIcon: { hex: "#ffffff", alpha: 1 },
                statUtilTier1: { hex: "#10B981", alpha: 1 },
                statUtilTier2: { hex: "#F59E0B", alpha: 1 },
                statUtilTier3: { hex: "#F97316", alpha: 1 },
                statUtilTier4: { hex: "#EF4444", alpha: 1 },
                statCpuTier1: { hex: "#E8A0A4", alpha: 1 },
                statCpuTier2: { hex: "#ED1C24", alpha: 1 },
                statCpuTier3: { hex: "#C4161C", alpha: 1 },
                statCpuTier4: { hex: "#FF4500", alpha: 1 },
                statMemTier1: { hex: "#5EEAD4", alpha: 1 },
                statMemTier2: { hex: "#22D3EE", alpha: 1 },
                statMemTier3: { hex: "#06B6D4", alpha: 1 },
                statMemTier4: { hex: "#0284C7", alpha: 1 },
                statGpuTier1: { hex: "#76B900", alpha: 1 },
                statGpuTier2: { hex: "#C4D600", alpha: 1 },
                statGpuTier3: { hex: "#FFC800", alpha: 1 },
                statGpuTier4: { hex: "#FF5A00", alpha: 1 },
                statTempCool: { hex: "#f0f4fc", alpha: 1 },
                statTempWarm: { hex: "#f0d060", alpha: 1 },
                statTempHot: { hex: "#FF3D8A", alpha: 1 },
                qlRunningDot: { hex: "#00F5FF", alpha: 1 }
            },
            numbers: {
                audioUtilThreshold1: 25,
                audioUtilThreshold2: 50,
                audioUtilThreshold3: 75,
                audioMicUtilThreshold1: 25,
                audioMicUtilThreshold2: 50,
                audioMicUtilThreshold3: 75,
                statUtilThreshold1: 25,
                statUtilThreshold2: 50,
                statUtilThreshold3: 75,
                statTempWarmAt: 70,
                statTempHotAt: 85
            },
            fonts: {
                fontFamily: "Symbols Nerd Font, JetBrains Mono Nerd Font, monospace",
                fontMono: "JetBrains Mono Nerd Font, monospace",
                fontScale: 1.0,
                fontMonoScale: 1.0,
                fontMain: "",
                fontSecondary: "",
                fontBar: "",
                fontMainScale: 1.0,
                fontSecondaryScale: 1.0,
                fontBarScale: 1.0
            }
        }
    }

    function themePresetSolidDark() {
        return {
            name: "Solid dark",
            version: 1,
            colors: {
                bg: { hex: "#000000", alpha: 1 },
                surface: { hex: "#121416", alpha: 1 },
                text: { hex: "#ececee", alpha: 1 },
                subtext: { hex: "#b0b0b2", alpha: 1 },
                barText: { hex: "#ececee", alpha: 1 },
                overlay: { hex: "#5c5c60", alpha: 1 },
                accent: { hex: "#00c4f5", alpha: 1 },
                muted: { hex: "#e85d6f", alpha: 1 },
                todayBg: { hex: "#00d4ff", alpha: 1 },
                weekday: { hex: "#e85d6f", alpha: 1 },
                clock: { hex: "#ffffff", alpha: 1 },
                glassBg: { hex: "#000000", alpha: 1 },
                glassBorder: { hex: "#1e2024", alpha: 1 },
                glassHighlight: { hex: "#000000", alpha: 0 },
                glassPillBg: { hex: "#0a0c0e", alpha: 1 },
                glassHover: { hex: "#16181c", alpha: 1 },
                glassPopupBg: { hex: "#000000", alpha: 1 },
                glassPopupBorder: { hex: "#121416", alpha: 1 },
                glassPopupHighlight: { hex: "#000000", alpha: 0 },
                pillBorder: { hex: "#0a0c0e", alpha: 1 },
                iconHoverBg: { hex: "#0a3a48", alpha: 1 },
                buttonBg: { hex: "#0a0c0e", alpha: 1 },
                controlActiveBg: { hex: "#16181c", alpha: 1 },
                popupButtonHoverBg: { hex: "#121416", alpha: 1 },
                buttonText: { hex: "#b0b0b2", alpha: 1 },
                buttonTextActive: { hex: "#00c4f5", alpha: 1 },
                wsActiveBg: { hex: "#16181c", alpha: 1 },
                wsActiveText: { hex: "#ececee", alpha: 1 },
                wsInactiveText: { hex: "#ffffff", alpha: 1 },
                audioSpeakerTier1: { hex: "#10B981", alpha: 1 },
                audioSpeakerTier2: { hex: "#F59E0B", alpha: 1 },
                audioSpeakerTier3: { hex: "#F97316", alpha: 1 },
                audioSpeakerTier4: { hex: "#EF4444", alpha: 1 },
                audioMicTier1: { hex: "#10B981", alpha: 1 },
                audioMicTier2: { hex: "#F59E0B", alpha: 1 },
                audioMicTier3: { hex: "#F97316", alpha: 1 },
                audioMicTier4: { hex: "#EF4444", alpha: 1 },
                iconColor: { hex: "#ffffff", alpha: 1 },
                audioSpeakerIcon: { hex: "#ffffff", alpha: 1 },
                audioMicIcon: { hex: "#ffffff", alpha: 1 },
                statUtilTier1: { hex: "#10B981", alpha: 1 },
                statUtilTier2: { hex: "#F59E0B", alpha: 1 },
                statUtilTier3: { hex: "#F97316", alpha: 1 },
                statUtilTier4: { hex: "#EF4444", alpha: 1 },
                statTempCool: { hex: "#ececee", alpha: 1 },
                statTempWarm: { hex: "#f0d060", alpha: 1 },
                statTempHot: { hex: "#e85d6f", alpha: 1 }
            },
            numbers: {
                audioUtilThreshold1: 25,
                audioUtilThreshold2: 50,
                audioUtilThreshold3: 75,
                audioMicUtilThreshold1: 25,
                audioMicUtilThreshold2: 50,
                audioMicUtilThreshold3: 75,
                statUtilThreshold1: 25,
                statUtilThreshold2: 50,
                statUtilThreshold3: 75,
                statTempWarmAt: 70,
                statTempHotAt: 85
            },
            fonts: {
                fontFamily: "Symbols Nerd Font, JetBrains Mono Nerd Font, monospace",
                fontMono: "JetBrains Mono Nerd Font, monospace",
                fontScale: 1.0,
                fontMonoScale: 1.0,
                fontMain: "",
                fontSecondary: "",
                fontBar: "",
                fontMainScale: 1.0,
                fontSecondaryScale: 1.0,
                fontBarScale: 1.0
            }
        }
    }

    function themePresetSoftGrey() {
        return {
            name: "Soft grey",
            version: 1,
            colors: {
                bg: { hex: "#1a1b1e", alpha: 1 },
                surface: { hex: "#25262b", alpha: 1 },
                text: { hex: "#e8e8ec", alpha: 1 },
                subtext: { hex: "#a0a4b0", alpha: 1 },
                barText: { hex: "#e8e8ec", alpha: 1 },
                overlay: { hex: "#6c7080", alpha: 1 },
                accent: { hex: "#7ec8e3", alpha: 1 },
                muted: { hex: "#e88a9a", alpha: 1 },
                todayBg: { hex: "#8ad4f0", alpha: 1 },
                weekday: { hex: "#e88a9a", alpha: 1 },
                clock: { hex: "#ffffff", alpha: 1 },
                glassBg: { hex: "#1a1b1e", alpha: 0.72 },
                glassBorder: { hex: "#ffffff", alpha: 0.10 },
                glassHighlight: { hex: "#ffffff", alpha: 0.12 },
                glassPillBg: { hex: "#22242a", alpha: 0.80 },
                glassHover: { hex: "#7ec8e3", alpha: 0.18 },
                glassPopupBg: { hex: "#1a1b1e", alpha: 0.92 },
                glassPopupBorder: { hex: "#ffffff", alpha: 0.12 },
                glassPopupHighlight: { hex: "#ffffff", alpha: 0.14 },
                pillBorder: { hex: "#ffffff", alpha: 0.08 },
                iconHoverBg: { hex: "#7ec8e3", alpha: 0.22 },
                buttonBg: { hex: "#22242a", alpha: 0.80 },
                controlActiveBg: { hex: "#7ec8e3", alpha: 0.28 },
                popupButtonHoverBg: { hex: "#2a2c32", alpha: 0.70 },
                buttonText: { hex: "#a0a4b0", alpha: 1 },
                buttonTextActive: { hex: "#7ec8e3", alpha: 1 },
                wsActiveBg: { hex: "#7ec8e3", alpha: 0.28 },
                wsActiveText: { hex: "#e8f7fc", alpha: 1 },
                wsInactiveText: { hex: "#ffffff", alpha: 1 },
                audioSpeakerTier1: { hex: "#10B981", alpha: 1 },
                audioSpeakerTier2: { hex: "#F59E0B", alpha: 1 },
                audioSpeakerTier3: { hex: "#F97316", alpha: 1 },
                audioSpeakerTier4: { hex: "#EF4444", alpha: 1 },
                audioMicTier1: { hex: "#10B981", alpha: 1 },
                audioMicTier2: { hex: "#F59E0B", alpha: 1 },
                audioMicTier3: { hex: "#F97316", alpha: 1 },
                audioMicTier4: { hex: "#EF4444", alpha: 1 },
                iconColor: { hex: "#ffffff", alpha: 1 },
                audioSpeakerIcon: { hex: "#ffffff", alpha: 1 },
                audioMicIcon: { hex: "#ffffff", alpha: 1 },
                statUtilTier1: { hex: "#10B981", alpha: 1 },
                statUtilTier2: { hex: "#F59E0B", alpha: 1 },
                statUtilTier3: { hex: "#F97316", alpha: 1 },
                statUtilTier4: { hex: "#EF4444", alpha: 1 },
                statTempCool: { hex: "#e8e8ec", alpha: 1 },
                statTempWarm: { hex: "#f0d060", alpha: 1 },
                statTempHot: { hex: "#e88a9a", alpha: 1 }
            },
            numbers: {
                audioUtilThreshold1: 25,
                audioUtilThreshold2: 50,
                audioUtilThreshold3: 75,
                audioMicUtilThreshold1: 25,
                audioMicUtilThreshold2: 50,
                audioMicUtilThreshold3: 75,
                statUtilThreshold1: 25,
                statUtilThreshold2: 50,
                statUtilThreshold3: 75,
                statTempWarmAt: 70,
                statTempHotAt: 85
            },
            fonts: {
                fontFamily: "Symbols Nerd Font, JetBrains Mono Nerd Font, monospace",
                fontMono: "JetBrains Mono Nerd Font, monospace",
                fontScale: 1.0,
                fontMonoScale: 1.0,
                fontMain: "",
                fontSecondary: "",
                fontBar: "",
                fontMainScale: 1.0,
                fontSecondaryScale: 1.0,
                fontBarScale: 1.0
            }
        }
    }

    // ── Additional polished built-in presets (easy on the eyes) ──────────
    function themePresetNordicFrost() {
        return {
            name: "Nordic frost",
            version: 1,
            colors: {
                bg: { hex: "#1a1e26", alpha: 1 },
                surface: { hex: "#222831", alpha: 1 },
                text: { hex: "#e8eef7", alpha: 1 },
                subtext: { hex: "#9aa8bc", alpha: 1 },
                barText: { hex: "#e8eef7", alpha: 1 },
                overlay: { hex: "#6b788c", alpha: 1 },
                accent: { hex: "#88c0d0", alpha: 1 },
                muted: { hex: "#bf616a", alpha: 1 },
                todayBg: { hex: "#8fbcbb", alpha: 1 },
                weekday: { hex: "#b48ead", alpha: 1 },
                clock: { hex: "#eceff4", alpha: 1 },
                glassBg: { hex: "#1a1e26", alpha: 0.62 },
                glassBorder: { hex: "#88c0d0", alpha: 0.14 },
                glassHighlight: { hex: "#ffffff", alpha: 0.06 },
                glassPillBg: { hex: "#1e2430", alpha: 0.78 },
                glassHover: { hex: "#88c0d0", alpha: 0.18 },
                glassPopupBg: { hex: "#171b22", alpha: 0.92 },
                glassPopupBorder: { hex: "#88c0d0", alpha: 0.16 },
                glassPopupHighlight: { hex: "#ffffff", alpha: 0.10 },
                pillBorder: { hex: "#ffffff", alpha: 0.08 },
                iconHoverBg: { hex: "#88c0d0", alpha: 0.22 },
                buttonBg: { hex: "#1e2430", alpha: 0.78 },
                controlActiveBg: { hex: "#88c0d0", alpha: 0.28 },
                popupButtonHoverBg: { hex: "#252b36", alpha: 0.70 },
                buttonText: { hex: "#9aa8bc", alpha: 1 },
                buttonTextActive: { hex: "#88c0d0", alpha: 1 },
                wsActiveBg: { hex: "#88c0d0", alpha: 0.26 },
                wsActiveText: { hex: "#e8f4f8", alpha: 1 },
                wsInactiveText: { hex: "#d8dee9", alpha: 1 },
                audioSpeakerTier1: { hex: "#a3be8c", alpha: 1 },
                audioSpeakerTier2: { hex: "#ebcb8b", alpha: 1 },
                audioSpeakerTier3: { hex: "#d08770", alpha: 1 },
                audioSpeakerTier4: { hex: "#bf616a", alpha: 1 },
                audioMicTier1: { hex: "#a3be8c", alpha: 1 },
                audioMicTier2: { hex: "#ebcb8b", alpha: 1 },
                audioMicTier3: { hex: "#d08770", alpha: 1 },
                audioMicTier4: { hex: "#bf616a", alpha: 1 },
                iconColor: { hex: "#d8dee9", alpha: 1 },
                audioSpeakerIcon: { hex: "#d8dee9", alpha: 1 },
                audioMicIcon: { hex: "#d8dee9", alpha: 1 },
                statUtilTier1: { hex: "#a3be8c", alpha: 1 },
                statUtilTier2: { hex: "#ebcb8b", alpha: 1 },
                statUtilTier3: { hex: "#d08770", alpha: 1 },
                statUtilTier4: { hex: "#bf616a", alpha: 1 },
                statTempCool: { hex: "#e8eef7", alpha: 1 },
                statTempWarm: { hex: "#ebcb8b", alpha: 1 },
                statTempHot: { hex: "#bf616a", alpha: 1 }
            },
            numbers: {
                audioUtilThreshold1: 25, audioUtilThreshold2: 50, audioUtilThreshold3: 75,
                audioMicUtilThreshold1: 25, audioMicUtilThreshold2: 50, audioMicUtilThreshold3: 75,
                statUtilThreshold1: 25, statUtilThreshold2: 50, statUtilThreshold3: 75,
                statTempWarmAt: 70, statTempHotAt: 85
            },
            fonts: {
                fontFamily: "Symbols Nerd Font, JetBrains Mono Nerd Font, monospace",
                fontMono: "JetBrains Mono Nerd Font, monospace",
                fontScale: 1.0,
                fontMonoScale: 1.0,
                fontMain: "",
                fontSecondary: "",
                fontBar: "",
                fontMainScale: 1.0,
                fontSecondaryScale: 1.0,
                fontBarScale: 1.0
            }
        }
    }

    function themePresetWarmEmber() {
        return {
            name: "Warm ember",
            version: 1,
            colors: {
                bg: { hex: "#16120f", alpha: 1 },
                surface: { hex: "#221c18", alpha: 1 },
                text: { hex: "#f3ebe3", alpha: 1 },
                subtext: { hex: "#b5a497", alpha: 1 },
                barText: { hex: "#f3ebe3", alpha: 1 },
                overlay: { hex: "#7a6c60", alpha: 1 },
                accent: { hex: "#e0a36a", alpha: 1 },
                muted: { hex: "#d4756a", alpha: 1 },
                todayBg: { hex: "#e8b07a", alpha: 1 },
                weekday: { hex: "#c98b7a", alpha: 1 },
                clock: { hex: "#fff8f0", alpha: 1 },
                glassBg: { hex: "#16120f", alpha: 0.64 },
                glassBorder: { hex: "#e0a36a", alpha: 0.14 },
                glassHighlight: { hex: "#ffffff", alpha: 0.05 },
                glassPillBg: { hex: "#1c1713", alpha: 0.80 },
                glassHover: { hex: "#e0a36a", alpha: 0.18 },
                glassPopupBg: { hex: "#14100d", alpha: 0.93 },
                glassPopupBorder: { hex: "#e0a36a", alpha: 0.16 },
                glassPopupHighlight: { hex: "#ffffff", alpha: 0.08 },
                pillBorder: { hex: "#ffffff", alpha: 0.07 },
                iconHoverBg: { hex: "#e0a36a", alpha: 0.22 },
                buttonBg: { hex: "#1c1713", alpha: 0.80 },
                controlActiveBg: { hex: "#e0a36a", alpha: 0.28 },
                popupButtonHoverBg: { hex: "#2a221c", alpha: 0.70 },
                buttonText: { hex: "#b5a497", alpha: 1 },
                buttonTextActive: { hex: "#e0a36a", alpha: 1 },
                wsActiveBg: { hex: "#e0a36a", alpha: 0.24 },
                wsActiveText: { hex: "#fff4e8", alpha: 1 },
                wsInactiveText: { hex: "#e8ddd2", alpha: 1 },
                audioSpeakerTier1: { hex: "#7cb88a", alpha: 1 },
                audioSpeakerTier2: { hex: "#d4a84b", alpha: 1 },
                audioSpeakerTier3: { hex: "#d4844a", alpha: 1 },
                audioSpeakerTier4: { hex: "#d4756a", alpha: 1 },
                audioMicTier1: { hex: "#7cb88a", alpha: 1 },
                audioMicTier2: { hex: "#d4a84b", alpha: 1 },
                audioMicTier3: { hex: "#d4844a", alpha: 1 },
                audioMicTier4: { hex: "#d4756a", alpha: 1 },
                iconColor: { hex: "#e8ddd2", alpha: 1 },
                audioSpeakerIcon: { hex: "#e8ddd2", alpha: 1 },
                audioMicIcon: { hex: "#e8ddd2", alpha: 1 },
                statUtilTier1: { hex: "#7cb88a", alpha: 1 },
                statUtilTier2: { hex: "#d4a84b", alpha: 1 },
                statUtilTier3: { hex: "#d4844a", alpha: 1 },
                statUtilTier4: { hex: "#d4756a", alpha: 1 },
                statTempCool: { hex: "#f3ebe3", alpha: 1 },
                statTempWarm: { hex: "#d4a84b", alpha: 1 },
                statTempHot: { hex: "#d4756a", alpha: 1 }
            },
            numbers: {
                audioUtilThreshold1: 25, audioUtilThreshold2: 50, audioUtilThreshold3: 75,
                audioMicUtilThreshold1: 25, audioMicUtilThreshold2: 50, audioMicUtilThreshold3: 75,
                statUtilThreshold1: 25, statUtilThreshold2: 50, statUtilThreshold3: 75,
                statTempWarmAt: 70, statTempHotAt: 85
            },
            fonts: {
                fontFamily: "Symbols Nerd Font, JetBrains Mono Nerd Font, monospace",
                fontMono: "JetBrains Mono Nerd Font, monospace",
                fontScale: 1.0,
                fontMonoScale: 1.0,
                fontMain: "",
                fontSecondary: "",
                fontBar: "",
                fontMainScale: 1.0,
                fontSecondaryScale: 1.0,
                fontBarScale: 1.0
            }
        }
    }

    function themePresetDeepOcean() {
        return {
            name: "Deep ocean",
            version: 1,
            colors: {
                bg: { hex: "#0b1219", alpha: 1 },
                surface: { hex: "#121c28", alpha: 1 },
                text: { hex: "#e6f0fa", alpha: 1 },
                subtext: { hex: "#8fa3b8", alpha: 1 },
                barText: { hex: "#e6f0fa", alpha: 1 },
                overlay: { hex: "#5c7188", alpha: 1 },
                accent: { hex: "#3db8c9", alpha: 1 },
                muted: { hex: "#e06c75", alpha: 1 },
                todayBg: { hex: "#56c8d8", alpha: 1 },
                weekday: { hex: "#7aa2f7", alpha: 1 },
                clock: { hex: "#f0f7ff", alpha: 1 },
                glassBg: { hex: "#0b1219", alpha: 0.60 },
                glassBorder: { hex: "#3db8c9", alpha: 0.15 },
                glassHighlight: { hex: "#ffffff", alpha: 0.06 },
                glassPillBg: { hex: "#0f1722", alpha: 0.78 },
                glassHover: { hex: "#3db8c9", alpha: 0.20 },
                glassPopupBg: { hex: "#0a1018", alpha: 0.93 },
                glassPopupBorder: { hex: "#3db8c9", alpha: 0.16 },
                glassPopupHighlight: { hex: "#ffffff", alpha: 0.10 },
                pillBorder: { hex: "#ffffff", alpha: 0.08 },
                iconHoverBg: { hex: "#3db8c9", alpha: 0.24 },
                buttonBg: { hex: "#0f1722", alpha: 0.78 },
                controlActiveBg: { hex: "#3db8c9", alpha: 0.30 },
                popupButtonHoverBg: { hex: "#162232", alpha: 0.70 },
                buttonText: { hex: "#8fa3b8", alpha: 1 },
                buttonTextActive: { hex: "#3db8c9", alpha: 1 },
                wsActiveBg: { hex: "#3db8c9", alpha: 0.26 },
                wsActiveText: { hex: "#e8fbff", alpha: 1 },
                wsInactiveText: { hex: "#c8d8e8", alpha: 1 },
                audioSpeakerTier1: { hex: "#2ee59a", alpha: 1 },
                audioSpeakerTier2: { hex: "#f0c060", alpha: 1 },
                audioSpeakerTier3: { hex: "#f08a50", alpha: 1 },
                audioSpeakerTier4: { hex: "#e06c75", alpha: 1 },
                audioMicTier1: { hex: "#2ee59a", alpha: 1 },
                audioMicTier2: { hex: "#f0c060", alpha: 1 },
                audioMicTier3: { hex: "#f08a50", alpha: 1 },
                audioMicTier4: { hex: "#e06c75", alpha: 1 },
                iconColor: { hex: "#c8d8e8", alpha: 1 },
                audioSpeakerIcon: { hex: "#c8d8e8", alpha: 1 },
                audioMicIcon: { hex: "#c8d8e8", alpha: 1 },
                statUtilTier1: { hex: "#2ee59a", alpha: 1 },
                statUtilTier2: { hex: "#f0c060", alpha: 1 },
                statUtilTier3: { hex: "#f08a50", alpha: 1 },
                statUtilTier4: { hex: "#e06c75", alpha: 1 },
                statTempCool: { hex: "#e6f0fa", alpha: 1 },
                statTempWarm: { hex: "#f0c060", alpha: 1 },
                statTempHot: { hex: "#e06c75", alpha: 1 }
            },
            numbers: {
                audioUtilThreshold1: 25, audioUtilThreshold2: 50, audioUtilThreshold3: 75,
                audioMicUtilThreshold1: 25, audioMicUtilThreshold2: 50, audioMicUtilThreshold3: 75,
                statUtilThreshold1: 25, statUtilThreshold2: 50, statUtilThreshold3: 75,
                statTempWarmAt: 70, statTempHotAt: 85
            },
            fonts: {
                fontFamily: "Symbols Nerd Font, JetBrains Mono Nerd Font, monospace",
                fontMono: "JetBrains Mono Nerd Font, monospace",
                fontScale: 1.0,
                fontMonoScale: 1.0,
                fontMain: "",
                fontSecondary: "",
                fontBar: "",
                fontMainScale: 1.0,
                fontSecondaryScale: 1.0,
                fontBarScale: 1.0
            }
        }
    }

    function themePresetLavenderDusk() {
        return {
            name: "Lavender dusk",
            version: 1,
            colors: {
                bg: { hex: "#14121a", alpha: 1 },
                surface: { hex: "#1e1a28", alpha: 1 },
                text: { hex: "#f0eaf8", alpha: 1 },
                subtext: { hex: "#a89bb8", alpha: 1 },
                barText: { hex: "#f0eaf8", alpha: 1 },
                overlay: { hex: "#6e6480", alpha: 1 },
                accent: { hex: "#b39ddb", alpha: 1 },
                muted: { hex: "#e5738a", alpha: 1 },
                todayBg: { hex: "#c4b0e8", alpha: 1 },
                weekday: { hex: "#ce93d8", alpha: 1 },
                clock: { hex: "#faf5ff", alpha: 1 },
                glassBg: { hex: "#14121a", alpha: 0.62 },
                glassBorder: { hex: "#b39ddb", alpha: 0.14 },
                glassHighlight: { hex: "#ffffff", alpha: 0.06 },
                glassPillBg: { hex: "#1a1622", alpha: 0.80 },
                glassHover: { hex: "#b39ddb", alpha: 0.18 },
                glassPopupBg: { hex: "#120f18", alpha: 0.93 },
                glassPopupBorder: { hex: "#b39ddb", alpha: 0.16 },
                glassPopupHighlight: { hex: "#ffffff", alpha: 0.09 },
                pillBorder: { hex: "#ffffff", alpha: 0.08 },
                iconHoverBg: { hex: "#b39ddb", alpha: 0.22 },
                buttonBg: { hex: "#1a1622", alpha: 0.80 },
                controlActiveBg: { hex: "#b39ddb", alpha: 0.28 },
                popupButtonHoverBg: { hex: "#262032", alpha: 0.70 },
                buttonText: { hex: "#a89bb8", alpha: 1 },
                buttonTextActive: { hex: "#b39ddb", alpha: 1 },
                wsActiveBg: { hex: "#b39ddb", alpha: 0.26 },
                wsActiveText: { hex: "#f8f0ff", alpha: 1 },
                wsInactiveText: { hex: "#e0d6f0", alpha: 1 },
                audioSpeakerTier1: { hex: "#81c784", alpha: 1 },
                audioSpeakerTier2: { hex: "#ffd54f", alpha: 1 },
                audioSpeakerTier3: { hex: "#ff8a65", alpha: 1 },
                audioSpeakerTier4: { hex: "#e5738a", alpha: 1 },
                audioMicTier1: { hex: "#81c784", alpha: 1 },
                audioMicTier2: { hex: "#ffd54f", alpha: 1 },
                audioMicTier3: { hex: "#ff8a65", alpha: 1 },
                audioMicTier4: { hex: "#e5738a", alpha: 1 },
                iconColor: { hex: "#e0d6f0", alpha: 1 },
                audioSpeakerIcon: { hex: "#e0d6f0", alpha: 1 },
                audioMicIcon: { hex: "#e0d6f0", alpha: 1 },
                statUtilTier1: { hex: "#81c784", alpha: 1 },
                statUtilTier2: { hex: "#ffd54f", alpha: 1 },
                statUtilTier3: { hex: "#ff8a65", alpha: 1 },
                statUtilTier4: { hex: "#e5738a", alpha: 1 },
                statTempCool: { hex: "#f0eaf8", alpha: 1 },
                statTempWarm: { hex: "#ffd54f", alpha: 1 },
                statTempHot: { hex: "#e5738a", alpha: 1 }
            },
            numbers: {
                audioUtilThreshold1: 25, audioUtilThreshold2: 50, audioUtilThreshold3: 75,
                audioMicUtilThreshold1: 25, audioMicUtilThreshold2: 50, audioMicUtilThreshold3: 75,
                statUtilThreshold1: 25, statUtilThreshold2: 50, statUtilThreshold3: 75,
                statTempWarmAt: 70, statTempHotAt: 85
            },
            fonts: {
                fontFamily: "Symbols Nerd Font, JetBrains Mono Nerd Font, monospace",
                fontMono: "JetBrains Mono Nerd Font, monospace",
                fontScale: 1.0,
                fontMonoScale: 1.0,
                fontMain: "",
                fontSecondary: "",
                fontBar: "",
                fontMainScale: 1.0,
                fontSecondaryScale: 1.0,
                fontBarScale: 1.0
            }
        }
    }

    function themePresetForestMoss() {
        return {
            name: "Forest moss",
            version: 1,
            colors: {
                bg: { hex: "#101612", alpha: 1 },
                surface: { hex: "#18201a", alpha: 1 },
                text: { hex: "#e8f0e9", alpha: 1 },
                subtext: { hex: "#9aafa0", alpha: 1 },
                barText: { hex: "#e8f0e9", alpha: 1 },
                overlay: { hex: "#64786c", alpha: 1 },
                accent: { hex: "#7cb87c", alpha: 1 },
                muted: { hex: "#d08070", alpha: 1 },
                todayBg: { hex: "#8fca8f", alpha: 1 },
                weekday: { hex: "#a8c878", alpha: 1 },
                clock: { hex: "#f4faf4", alpha: 1 },
                glassBg: { hex: "#101612", alpha: 0.62 },
                glassBorder: { hex: "#7cb87c", alpha: 0.14 },
                glassHighlight: { hex: "#ffffff", alpha: 0.05 },
                glassPillBg: { hex: "#141c16", alpha: 0.80 },
                glassHover: { hex: "#7cb87c", alpha: 0.18 },
                glassPopupBg: { hex: "#0d120e", alpha: 0.93 },
                glassPopupBorder: { hex: "#7cb87c", alpha: 0.16 },
                glassPopupHighlight: { hex: "#ffffff", alpha: 0.08 },
                pillBorder: { hex: "#ffffff", alpha: 0.07 },
                iconHoverBg: { hex: "#7cb87c", alpha: 0.22 },
                buttonBg: { hex: "#141c16", alpha: 0.80 },
                controlActiveBg: { hex: "#7cb87c", alpha: 0.28 },
                popupButtonHoverBg: { hex: "#1e2a20", alpha: 0.70 },
                buttonText: { hex: "#9aafa0", alpha: 1 },
                buttonTextActive: { hex: "#7cb87c", alpha: 1 },
                wsActiveBg: { hex: "#7cb87c", alpha: 0.24 },
                wsActiveText: { hex: "#f0fff0", alpha: 1 },
                wsInactiveText: { hex: "#d4e4d6", alpha: 1 },
                audioSpeakerTier1: { hex: "#6bcf8e", alpha: 1 },
                audioSpeakerTier2: { hex: "#d4c05a", alpha: 1 },
                audioSpeakerTier3: { hex: "#d4925a", alpha: 1 },
                audioSpeakerTier4: { hex: "#d08070", alpha: 1 },
                audioMicTier1: { hex: "#6bcf8e", alpha: 1 },
                audioMicTier2: { hex: "#d4c05a", alpha: 1 },
                audioMicTier3: { hex: "#d4925a", alpha: 1 },
                audioMicTier4: { hex: "#d08070", alpha: 1 },
                iconColor: { hex: "#d4e4d6", alpha: 1 },
                audioSpeakerIcon: { hex: "#d4e4d6", alpha: 1 },
                audioMicIcon: { hex: "#d4e4d6", alpha: 1 },
                statUtilTier1: { hex: "#6bcf8e", alpha: 1 },
                statUtilTier2: { hex: "#d4c05a", alpha: 1 },
                statUtilTier3: { hex: "#d4925a", alpha: 1 },
                statUtilTier4: { hex: "#d08070", alpha: 1 },
                statTempCool: { hex: "#e8f0e9", alpha: 1 },
                statTempWarm: { hex: "#d4c05a", alpha: 1 },
                statTempHot: { hex: "#d08070", alpha: 1 }
            },
            numbers: {
                audioUtilThreshold1: 25, audioUtilThreshold2: 50, audioUtilThreshold3: 75,
                audioMicUtilThreshold1: 25, audioMicUtilThreshold2: 50, audioMicUtilThreshold3: 75,
                statUtilThreshold1: 25, statUtilThreshold2: 50, statUtilThreshold3: 75,
                statTempWarmAt: 70, statTempHotAt: 85
            },
            fonts: {
                fontFamily: "Symbols Nerd Font, JetBrains Mono Nerd Font, monospace",
                fontMono: "JetBrains Mono Nerd Font, monospace",
                fontScale: 1.0,
                fontMonoScale: 1.0,
                fontMain: "",
                fontSecondary: "",
                fontBar: "",
                fontMainScale: 1.0,
                fontSecondaryScale: 1.0,
                fontBarScale: 1.0
            }
        }
    }

    // Shared translucent glass skeleton for liquid-style presets (accent/muted vary).
    function _hex2(n) {
        var v = Math.max(0, Math.min(255, Math.round(n)))
        var h = v.toString(16)
        return h.length < 2 ? ("0" + h) : h
    }
    function _rgbHex(r, g, b) {
        return "#" + _hex2(r * 255) + _hex2(g * 255) + _hex2(b * 255)
    }
    function _liquidPreset(name, accentHex, mutedHex, tintR, tintG, tintB) {
        var a = accentHex
        var m = mutedHex
        var tr = tintR !== undefined ? tintR : 0.04
        var tg = tintG !== undefined ? tintG : 0.06
        var tb = tintB !== undefined ? tintB : 0.10
        function glass(alpha) {
            return { hex: _rgbHex(tr, tg, tb), alpha: alpha }
        }
        return {
            name: name,
            version: 1,
            colors: {
                bg: { hex: _rgbHex(tr, tg, tb), alpha: 1 },
                surface: { hex: _rgbHex(Math.min(1, tr + 0.04), Math.min(1, tg + 0.05), Math.min(1, tb + 0.06)), alpha: 1 },
                text: { hex: "#f0f4fc", alpha: 1 },
                subtext: { hex: "#a8b4c8", alpha: 1 },
                barText: { hex: "#f0f4fc", alpha: 1 },
                overlay: { hex: "#6e7a90", alpha: 1 },
                accent: { hex: a, alpha: 1 },
                muted: { hex: m, alpha: 1 },
                todayBg: { hex: a, alpha: 1 },
                weekday: { hex: m, alpha: 1 },
                clock: { hex: "#ffffff", alpha: 1 },
                glassBg: glass(0.56),
                glassBorder: { hex: a, alpha: 0.14 },
                glassHighlight: { hex: "#ffffff", alpha: 0.08 },
                glassPillBg: glass(0.72),
                glassHover: { hex: a, alpha: 0.20 },
                glassPopupBg: glass(0.90),
                glassPopupBorder: { hex: a, alpha: 0.16 },
                glassPopupHighlight: { hex: "#ffffff", alpha: 0.14 },
                pillBorder: { hex: "#ffffff", alpha: 0.10 },
                iconHoverBg: { hex: a, alpha: 0.26 },
                buttonBg: glass(0.72),
                controlActiveBg: { hex: a, alpha: 0.32 },
                popupButtonHoverBg: glass(0.65),
                buttonText: { hex: "#a8b4c8", alpha: 1 },
                buttonTextActive: { hex: a, alpha: 1 },
                wsActiveBg: { hex: a, alpha: 0.26 },
                wsActiveText: { hex: "#e6fffc", alpha: 1 },
                wsInactiveText: { hex: "#ffffff", alpha: 1 },
                audioSpeakerTier1: { hex: "#10B981", alpha: 1 },
                audioSpeakerTier2: { hex: "#F59E0B", alpha: 1 },
                audioSpeakerTier3: { hex: "#F97316", alpha: 1 },
                audioSpeakerTier4: { hex: "#EF4444", alpha: 1 },
                audioMicTier1: { hex: "#10B981", alpha: 1 },
                audioMicTier2: { hex: "#F59E0B", alpha: 1 },
                audioMicTier3: { hex: "#F97316", alpha: 1 },
                audioMicTier4: { hex: "#EF4444", alpha: 1 },
                iconColor: { hex: "#ffffff", alpha: 1 },
                audioSpeakerIcon: { hex: "#ffffff", alpha: 1 },
                audioMicIcon: { hex: "#ffffff", alpha: 1 },
                statUtilTier1: { hex: "#10B981", alpha: 1 },
                statUtilTier2: { hex: "#F59E0B", alpha: 1 },
                statUtilTier3: { hex: "#F97316", alpha: 1 },
                statUtilTier4: { hex: "#EF4444", alpha: 1 },
                statCpuTier1: { hex: "#E8A0A4", alpha: 1 },
                statCpuTier2: { hex: "#ED1C24", alpha: 1 },
                statCpuTier3: { hex: "#C4161C", alpha: 1 },
                statCpuTier4: { hex: "#FF4500", alpha: 1 },
                statMemTier1: { hex: "#5EEAD4", alpha: 1 },
                statMemTier2: { hex: "#22D3EE", alpha: 1 },
                statMemTier3: { hex: "#06B6D4", alpha: 1 },
                statMemTier4: { hex: "#0284C7", alpha: 1 },
                statGpuTier1: { hex: "#76B900", alpha: 1 },
                statGpuTier2: { hex: "#C4D600", alpha: 1 },
                statGpuTier3: { hex: "#FFC800", alpha: 1 },
                statGpuTier4: { hex: "#FF5A00", alpha: 1 },
                statTempCool: { hex: "#f0f4fc", alpha: 1 },
                statTempWarm: { hex: "#f0d060", alpha: 1 },
                statTempHot: { hex: m, alpha: 1 },
                qlRunningDot: { hex: "#00F5FF", alpha: 1 }
            },
            numbers: {
                audioUtilThreshold1: 25, audioUtilThreshold2: 50, audioUtilThreshold3: 75,
                audioMicUtilThreshold1: 25, audioMicUtilThreshold2: 50, audioMicUtilThreshold3: 75,
                statUtilThreshold1: 25, statUtilThreshold2: 50, statUtilThreshold3: 75,
                statTempWarmAt: 70, statTempHotAt: 85
            },
            fonts: {
                fontFamily: "Symbols Nerd Font, JetBrains Mono Nerd Font, monospace",
                fontMono: "JetBrains Mono Nerd Font, monospace",
                fontScale: 1.0,
                fontMonoScale: 1.0,
                fontMain: "",
                fontSecondary: "",
                fontBar: "",
                fontMainScale: 1.0,
                fontSecondaryScale: 1.0,
                fontBarScale: 1.0
            }
        }
    }

    function themePresetLiquidMint() {
        return _liquidPreset("Liquid mint", "#5eead4", "#f472b6", 0.04, 0.08, 0.08)
    }
    function themePresetLiquidViolet() {
        return _liquidPreset("Liquid violet", "#c4b5fd", "#f9a8d4", 0.07, 0.05, 0.12)
    }
    function themePresetLiquidRose() {
        return _liquidPreset("Liquid rose", "#f9a8d4", "#fb7185", 0.10, 0.05, 0.08)
    }
    function themePresetLiquidAmber() {
        return _liquidPreset("Liquid amber", "#fbbf24", "#fb7185", 0.09, 0.07, 0.04)
    }
    function themePresetLiquidIce() {
        return _liquidPreset("Liquid ice", "#7dd3fc", "#a5b4fc", 0.04, 0.07, 0.12)
    }
    function themePresetLiquidAurora() {
        return _liquidPreset("Liquid aurora", "#34d399", "#818cf8", 0.03, 0.08, 0.09)
    }

    function themeReset() {
        return themeApply(themeFactoryDefaults())
    }

    function themeBuiltinPresets() {
        return [
            themeFactoryDefaults(),
            themePresetLiquidMint(),
            themePresetLiquidViolet(),
            themePresetLiquidRose(),
            themePresetLiquidAmber(),
            themePresetLiquidIce(),
            themePresetLiquidAurora(),
            themePresetSolidDark(),
            themePresetSoftGrey(),
            themePresetNordicFrost(),
            themePresetWarmEmber(),
            themePresetDeepOcean(),
            themePresetLavenderDusk(),
            themePresetForestMoss()
        ]
    }

    // =========================================================================
    // UI SCALE (auto from screen width + optional manual override)
    // =========================================================================
    // Base sizes below were designed around a wide desktop (~2560+ logical px).
    // shell.qml sets uiScale / screenWidth / screenHeight at runtime:
    //   • uiScaleManual == 0  → auto: clamp(screenWidth / uiDesignWidth, min, max)
    //   • uiScaleManual  > 0  → force that scale (e.g. 0.8), still clamped
    //
    // sp(n)     — scale a bar/pill pixel size
    // popupW/H  — scale a popup size and clamp to the current screen
    //
    // IPC: qs ipc call shell setUiScale 0.8 | setUiScaleManual 0 | setUiScaleAuto
    // =========================================================================

    // Runtime (written by shell.qml). Keep defaults sane before first apply.
    property real uiScale: 1.0
    property int screenWidth: 2560
    property int screenHeight: 1440

    // Full-size bar at this logical width and above; narrower screens scale down.
    readonly property int  uiDesignWidth: 2560
    readonly property real uiScaleMin:    0.65
    readonly property real uiScaleMax:    1.0
    // 0 = automatic from screen width; set e.g. 0.85 to force a scale on this machine.
    // Writable so shell IPC / state file can override without editing this file.
    property real uiScaleManual: 0

    function sp(base) {
        var b = Number(base)
        if (!(b > 0))
            return 0
        return Math.max(1, Math.round(b * uiScale))
    }

    function popupW(base) {
        var want = sp(base)
        var maxW = Math.max(160, screenWidth - 24)
        return Math.min(want, maxW)
    }

    function popupH(base) {
        var want = sp(base)
        var maxH = Math.max(120, screenHeight - sp(58) - 32)
        return Math.min(want, maxH)
    }

    function computeUiScale(widthPx) {
        var w = Number(widthPx)
        if (!(w > 0))
            w = uiDesignWidth
        var manual = Number(uiScaleManual)
        var s
        if (manual > 0)
            s = manual
        else
            s = w / uiDesignWidth
        if (s < uiScaleMin) s = uiScaleMin
        if (s > uiScaleMax) s = uiScaleMax
        return s
    }

    // =========================================================================
    // UI DENSITY / PRIORITY (what to hide on narrow screens)
    // =========================================================================
    // Priority (always kept if Config show* is true):
    //   workspaces · system tray · audio · clock/calendar · notifications · power
    //
    // Deprioritized (auto-hidden below width thresholds, widest first):
    //   1) Quick Launch
    //   2) Sys stats (CPU / Memory / GPU)
    //   3) Secondary: FreshRSS, media, kill-target
    //   4) Connectivity: Network + Bluetooth capsule
    //
    // Thresholds are logical screen width (px). Tune if a machine feels too aggressive.

    readonly property int uiDensityHideQuickLaunchBelow:   2300
    readonly property int uiDensityHideStatsBelow:         2000
    readonly property int uiDensityHideSecondaryBelow:     1680
    readonly property int uiDensityHideConnectivityBelow:  1480

    // Runtime flags written by shell.qml applyDensity()
    property bool densityHideQuickLaunch:   false
    property bool densityHideStats:         false
    property bool densityHideSecondary:     false
    property bool densityHideConnectivity:  false

    function computeDensity(widthPx) {
        var w = Number(widthPx)
        if (!(w > 0))
            w = screenWidth > 0 ? screenWidth : uiDesignWidth
        return {
            hideQuickLaunch:   w < uiDensityHideQuickLaunchBelow,
            hideStats:         w < uiDensityHideStatsBelow,
            hideSecondary:     w < uiDensityHideSecondaryBelow,
            hideConnectivity:  w < uiDensityHideConnectivityBelow
        }
    }

    // =========================================================================
    // RADII (corner rounding) — consistency is king  (scaled)
    // =========================================================================
    readonly property int barRadius:       sp(14)   // Main bar background rectangle
    readonly property int pillRadius:      sp(10)   // All pill containers (most common)
    readonly property int popupRadius:     sp(14)   // Default for most popups (audio, calendar, tray, media)
    readonly property int popupRadiusLarge:sp(16)   // Power menu, Help overlay
    readonly property int buttonRadius:       sp(6)   // Small buttons inside popups (mute, nav, close)
    readonly property int smallButtonRadius:  sp(4)   // Very tight buttons (some audio controls)
    readonly property int sliderRadius:       0   // 0 = auto (height/2). Set >0 to force specific rounding on volume bars
    readonly property int workspaceRadius:    sp(8)   // Individual workspace buttons

    // Border widths (not scaled — keep 1px crisp outlines)
    readonly property int controlBorderWidth: 1   // Default border for pills, buttons, popup cards

    // =========================================================================
    // SPACING & PADDING (scaled)
    // =========================================================================
    readonly property int sideMargin:           sp(10)   // Left/right margin of the whole bar (outside the glass rect)
    readonly property int barContentHMargin:    sp(20)   // Inner left/right padding inside the main bar row
    readonly property int barContentVMargin:     sp(4)   // Inward (desktop-side) padding only; screen-edge gap is barEdgeMargin
    readonly property int pillHPadding:         sp(18)   // Typical horizontal inner padding for pill content (AudioPill etc use this indirectly)
    readonly property int popupPadding:         sp(16)   // Generic content margin inside most popups (prefer popupSpacing for new code)
    readonly property int popupPaddingSmall:    sp(10)   // Tighter popups (device lists, tray menus) (prefer popupSpacingTight)
    readonly property int widgetSpacing:         sp(8)   // Spacing between major widgets in the bar row
    // Total vertical inset of inner hover chips vs pillHeight (workspaces use ~4).
    readonly property int pillChipInset:         4
    // Legacy token (was a top inset for nerd-font glyphs). Bar faces now
    // use anchors.centerIn like WorkspacesPill so pills share one vertical center.
    readonly property int pillFaceTopPad:        0
    readonly property int iconTextGap:           sp(6)   // Gap between icon and volume bar or label inside audio pill
    readonly property int dualAudioSidePadding:  sp(3)   // Extra tight padding used only in AudioPill dual view

    // =========================================================================
    // SIZING — BAR, PILLS, POPUPS, ICONS (scaled; popups also screen-clamped)
    // =========================================================================
    // Bar position & size (consumed by shell.qml PanelWindow anchors)
    readonly property string barPosition:  "top"       // "top" | "bottom" — which screen edge the bar sits on
    // "classic" = one full-width bar with L/C/R zones (barPosition).
    // "dual" = top + bottom centered bars (zones "top" | "bottom").
    readonly property string barLayoutMode: "classic"
    // Gap between the bar and the screen edge (top and/or bottom). 0 = flush.
    // Writable: Options / Position sliders + bar-layout.json (0–48 px).
    property int barEdgeMargin: 0
    // When true, shrink the exclusive zone by Hyprland gaps_out so tiled windows
    // sit against the bar instead of leaving a wallpaper strip. Position / Options.
    property bool flushWindowsToBar: false
    readonly property int popupBarGap:        sp(4)     // Space between bar and pill popups (flips with barPosition)
    // Extra thickness for the bar chrome + pills on top of uiScale. 1.0 = design default.
    // Writable: Options / Position sliders + bar-layout.json (0.80–1.40).
    property real barSizeScale: 1.0
    readonly property int barHeight: Math.max(36, Math.round(sp(58) * barSizeScale))
    readonly property int barTopMargin:  barEdgeMargin   // Legacy alias — prefer barEdgeMargin

    // Pills (uniform height gives the clean segmented look)
    readonly property int pillHeight: Math.max(22, Math.round(sp(36) * barSizeScale))

    // Audio widget (very sensitive — changing these requires testing dual view alignment)
    // Audio pill content width. Dual view (default) needs room for:
    //   speaker icon + bar + vol% [+ bat%] | mic icon + bar + vol% [+ bat%]
    readonly property int audioViewContentWidth: sp(330)   // Inner width for dual-first layout (+ BT battery)
    readonly property int audioViewSidePadding:    sp(6)   // Dual view left/right micro-padding
    readonly property int audioDualBarWidth:      sp(68)   // Mini volume bar width in dual view
    readonly property int audioDualPercentWidth:  sp(34)   // "100%" label slot in dual view

    // Icon sizes (nerd font glyphs and tray icons)
    readonly property int iconSizeTray:        sp(18)   // System tray — reference size for bar icons
    readonly property int iconSizePill:        iconSizeTray   // Audio, bell, media glyphs in pills
    readonly property int iconSizePillLarge:   iconSizeTray   // Power / inspector / control-bar glyphs
    // Launcher pill glyph only. Wider than iconSizePillLarge so it matches Quick
    // Launch artwork; pill chrome width stays sp(42) (shell.qml launcherPill).
    readonly property int iconSizeLauncher:    sp(26)
    readonly property int iconSizePopup:       sp(17)   // Icons inside popups (audio controls row)
    readonly property int iconSizePower:       sp(32)   // Big icons in the power menu grid
    readonly property int iconSizeMediaArt:    sp(42)   // Placeholder music note when no album art
    readonly property int quickLaunchIcon:     sp(20)   // Quick launch row icon size
    readonly property int quickLaunchSpacing:  sp(10)   // Gap between quick-launch icons
    readonly property int quickLaunchPaddingH: sp(10)   // Left/right padding inside the pill

    // =========================================================================
    // QUICK LAUNCH DOCK HOVER (runtime: shell.qml / Options → Dock)
    // =========================================================================
    // dockEffect: "off" | "magnify" | "jump" | "both"
    // dockScope: "icons" (default, all icon widgets) | "quicklaunch"
    // dockMaxScale: 1.05–1.8  (hovered icon)
    // dockRadius: px influence for neighbor magnification (QL / tray / workspaces)
    // dockJumpPx: bounce height on click
    // Stats gauges and the volume meter stay still.
    readonly property string dockEffectDefault: "both"
    readonly property real   dockMaxScaleDefault: 1.28
    readonly property int    dockRadiusDefault: 72
    readonly property int    dockJumpPxDefault: 8

    // =========================================================================
    // QUICK LAUNCH (widgets/QuickLaunchPill.qml — pinned app icon row)
    // =========================================================================
    // Add, remove, or reorder entries in quickLaunchApps. Each entry is one icon.
    //
    //   icon       — path to a PNG/SVG image file shown on the bar
    //   glyph      — optional nerd-font character instead of icon (leave icon "" to use)
    //   command    — how to start the app when clicked:
    //                  • list (recommended): ["gtk-launch", "firefox"] or ["/path/to/AppImage"]
    //                  • string: "gtk-launch firefox" (runs through the shell)
    //                Note: Config list commands are QML lists, not JavaScript arrays.
    //   tooltip    — hover label (optional)
    //   matchClass — optional WM class / app-id override when the running-dash
    //                heuristic (gtk-launch id or binary name) does not match.
    //                String or list; persisted through bar-layout.json.
    //
    // Running windows light a small accent dash under the icon (any workspace,
    // including magic). The focused window also uses wsActiveBg on the cell.

    readonly property var quickLaunchApps: [
        {
            icon: "/home/crome/icons/vscodium.svg",
            glyph: "",
            command: ["gtk-launch", "vscodium"],
            tooltip: "VSCodium"
        },
        {
            icon: "/home/crome/icons/firefox.svg",
            glyph: "",
            command: ["env", "MOZ_ENABLE_WAYLAND=0", "firefox"],
            tooltip: "Firefox"
        },
        {
            icon: "/home/crome/icons/brave.svg",
            glyph: "",
            command: ["/usr/bin/brave-origin"],
            tooltip: "Brave Origin"
        },
        {
            icon: "/home/crome/icons/google-chrome.svg",
            glyph: "",
            command: ["/usr/bin/google-chrome-stable"],
            tooltip: "Google Chrome"
        },
        {
            icon: "/home/crome/icons/logseq-a.svg",
            glyph: "",
            command: ["gtk-launch", "logseq"],
            tooltip: "Logseq"
        },
        {
            icon: "/home/crome/icons/lmstudio-dark.png",
            glyph: "",
            command: ["/home/crome/applications/LM-Studio-0.4.13-1-x64.AppImage"],
            tooltip: "LM Studio"
        },
        {
            icon: "/home/crome/icons/steam.svg",
            glyph: "",
            command: ["/usr/bin/steam"],
            tooltip: "Steam"
        },   
        {
            icon: "/home/crome/icons/com.system76.CosmicFiles.svg",
            glyph: "",
            command: ["/usr/bin/cosmic-files"],
            tooltip: "Cosmic Files"
        },    
        {
            icon: "/home/crome/icons/kitty.svg",
            glyph: "",
            command: ["/usr/bin/kitty"],
            tooltip: "Kitty"
        },        
    ]

    // Popup window sizes (scaled + clamped to screen). Increase base if content feels cramped.
    // AudioPill: streams summary, device + profile, volume, L/R, VU, echo cancel, tools.
    readonly property int popupAudioWidth:     popupW(520)   // AudioPill device/volume popup
    readonly property int popupAudioHeight:    popupH(620)
    readonly property int popupMediaWidth:     popupW(520)   // MediaPill player controls popup
    readonly property int popupMediaHeight:    popupH(470)
    readonly property int popupPowerWidth:     popupW(560)   // PowerMenu full grid (left-click)
    readonly property int popupPowerHeight:    popupH(192)
    readonly property int popupContextMenuWidth:  popupW(220)   // Compact right-click menus (bell, power)
    readonly property int popupContextMenuRowHeight: sp(34)  // Height of one row in those menus
    readonly property int popupCalendarWidth:  popupW(310)   // ClockPill calendar popup
    readonly property int popupCalendarHeight: popupH(280)
    // --- BluetoothPill (adapter power, devices, profiles)
    readonly property int popupBluetoothWidth:  popupW(380)
    readonly property int popupBluetoothHeight: popupH(480)
    readonly property int bluetoothScanSeconds: 45   // Auto-stop discovery after this many seconds
    // --- NetworkPill (nm-applet replacement: wired/WiFi, radios, connection info)
    // Main column width; WiFi AP list opens as a second column of popupNetworkWifiWidth
    readonly property int popupNetworkWidth:      popupW(520)
    readonly property int popupNetworkWifiWidth:  popupW(340)   // right column when scanning / changing network
    readonly property int popupNetworkHeight:     popupH(580)
    // --- SysStatsPill metrics popups (left-click CPU / Memory / GPU on the bar pill)
    // These are the large dropdown panels with charts and process lists — not the
    // compact numbers shown on the pill itself. Each section has its own size.
    readonly property int popupStatsCpuWidth:  popupW(598)   // CPU popup width in pixels
    readonly property int popupStatsCpuHeight: popupH(850)   // CPU popup height in pixels
    readonly property int popupStatsMemWidth:  popupW(598)   // Memory popup width in pixels
    readonly property int popupStatsMemHeight: popupH(850)   // Memory popup height in pixels
    readonly property int popupStatsGpuWidth:  popupW(598)   // GPU popup width in pixels
    readonly property int popupStatsGpuHeight: popupH(850)   // GPU popup height in pixels

    // --- Where each metrics popup appears on screen (widgets/SysStatsPill.qml)
    // Right-click CPU, Memory, or GPU to open its popup. Position is tuned per section
    // so popups do not overlap each other or fall off the screen edge.
    //
    // Shared terms (same meaning for Cpu / Mem / Gpu):
    //   anchorX          — which part of the pill section to line up under:
    //                      0 = left edge, 0.5 = middle, 1 = right edge
    //   anchorWholePill  — false = anchor under that section only (CPU, Memory, or GPU)
    //                      true  = anchor under the entire stats pill as one block
    //   offsetX          — slide popup left (negative) or right (positive) in pixels
    //   offsetY          — slide popup up (negative) or down (positive) in pixels
    //   barGap           — space between the bar and the popup (larger = farther away)

    // CPU section (left third of the pill)
    readonly property real popupStatsCpuAnchorX: 0.5
    readonly property bool popupStatsCpuAnchorWholePill: false
    readonly property int popupStatsCpuOffsetX: sp(200)
    readonly property int popupStatsCpuOffsetY: sp(7)
    readonly property int popupStatsCpuBarGap: sp(2)

    // Memory section (middle third)
    readonly property real popupStatsMemAnchorX: 0.5
    readonly property bool popupStatsMemAnchorWholePill: false
    readonly property int popupStatsMemOffsetX: 0
    readonly property int popupStatsMemOffsetY: sp(7)
    readonly property int popupStatsMemBarGap: sp(2)

    // GPU section (right third)
    readonly property real popupStatsGpuAnchorX: 0.5
    readonly property bool popupStatsGpuAnchorWholePill: false
    readonly property int popupStatsGpuOffsetX: -sp(200)
    readonly property int popupStatsGpuOffsetY: sp(7)
    readonly property int popupStatsGpuBarGap: sp(2)

    // When you right-click and open a metrics popup, should charts update live?
    // true  = live graphs and numbers (uses a bit more CPU while open)
    // false = frozen snapshot until you close and reopen
    readonly property bool popupStatsLiveUpdates: true

    // Remember your Pause / Resume choice across reboots?
    // false = always use popupStatsLiveUpdates when you open a popup
    // true  = save per-section pause state to state/popup-stats.json
    readonly property bool popupStatsPersistPause: false
    readonly property int popupHelpWidth:     popupW(1060)  // Hypr Config Inspector default width
    readonly property int popupHelpHeight:    popupH(720)   // Hypr Config Inspector default height
    readonly property int popupTrayMaxHeight:  popupH(520)   // SystemTrayPill menu max height before scroll

    // Popup internal layout tokens (standardizes the repeated glass card patterns)
    readonly property real popupHeaderHighlightHeight: 1.5   // Top light edge on popup glass cards
    // Title sizes track Main text scale; hints track Secondary text scale
    readonly property int popupTitleSize:             fspRole(16, fontMainScale)   // "Audio Controls", "Power Menu", etc.
    readonly property int popupSectionSize:           fspRole(13, fontMainScale)   // "Playback", "Recording", section headers
    readonly property int popupHintSize:              fspRole(11, fontSecondaryScale)   // body hints / secondary
    readonly property int popupSpacing:               sp(16)    // Main content margin inside popups
    readonly property int popupSpacingTight:          sp(10)    // Tighter popups (device lists, tray menus)
    readonly property int popupSectionSpacing:         sp(6)    // Spacing between sections inside popups
    readonly property int popupGridSpacing:            sp(4)    // Calendar / dense grid cell gap (ClockPill)

    // =========================================================================
    // WIDGET VISIBILITY (bar pill defaults — IPC can override until qs restart)
    // =========================================================================
    // Consumed by shell.qml on startup; toggled at runtime via qs ipc call shell …
    // Magic pill visibility is separate (wsShowSpecialPill + setShowMagicWorkspacePill).

    readonly property bool showLauncherPill:        true   // Inline app launcher (shell.qml)
    // Shell command run when the launcher pill is clicked (shell.qml passes this to sh -c).
    readonly property string launcherCommand: "~/.local/bin/rofi-app-drawer"
    readonly property string launcherTooltip: "App Launcher"
    readonly property bool showQuickLaunchPill:     true   // QuickLaunchPill.qml
    readonly property bool showMediaPill:           false  // MediaPill.qml (hidden by default)
    readonly property bool showWorkspacesPill:      true   // WorkspacesPill.qml (numbered pills)
    readonly property bool showStatsPill:           true   // SysStatsPill.qml
    readonly property bool showTrayPill:             true   // SystemTrayPill.qml
    readonly property bool showNetworkPill:          true   // NetworkPill.qml (nm-applet replacement)
    readonly property bool showBluetoothPill:        true   // BluetoothPill.qml
    readonly property bool showAudioPill:           true   // AudioPill.qml
    readonly property bool showClockPill:           true   // ClockPill.qml
    readonly property bool showNotificationPill:     true   // NotificationBell.qml
    readonly property bool showPowerPill:           true   // PowerMenu.qml
    readonly property bool showKillTargetPill:    false  // KillTargetPill.qml (click-to-kill picker)
    readonly property bool showFreshRssPill:       true   // FreshRssPill.qml (FreshRSS reader)
    readonly property bool showRadarPill:          false  // RadarPill.qml (removed from bar; set true + re-add in shell.qml to restore)
    readonly property bool showHyprInspPill:       false  // Opens HyprConfigInsp from the bar (shell.qml)
    readonly property bool showControlBarPill:     true   // Opens BarControlBar (config strip) from the bar

    // Glyphs for bar position toggle in BarControlBar (right-click empty bar chrome)
    readonly property string barPositionIconTop:    "󰁝"  // shown when bar is on bottom (click → move to top)
    readonly property string barPositionIconBottom: "󰁅"  // shown when bar is on top (click → move to bottom)
    readonly property string iconHyprInsp:          "󰓙"  // Hyprland Config Inspector (spotlight, not cog)
    readonly property string iconControlBar:        "󰢻"  // Bar control / config menu pill

    // Display (BarControlBar → Display panel; hyprctl modes + bitdepth)
    // CLI/rofi: hypr-resolution (on PATH). Script: list/status/apply for the control strip.
    readonly property string hyprResolutionBin: "hypr-resolution"
    readonly property string monitorModeScript: "/home/crome/.config/quickshell/scripts/monitor-mode.sh"
    readonly property string monitorName: "DP-1"

    // Wallpaper (BarControlBar → Wallpaper panel; hyprpaper apply)
    readonly property string wallpaperDir: "/home/crome/Pictures/wallpapers"
    readonly property string wallpaperMonitor: "DP-1"
    readonly property string wallpaperFitMode: "cover"
    readonly property int wallpaperTileSize: 148  // preferred thumb width; grid stretches to fill
    readonly property string wallpaperListScript:  "/home/crome/.config/quickshell/scripts/wallpaper-list-json.sh"
    readonly property string wallpaperApplyScript: "/home/crome/.config/quickshell/scripts/wallpaper-apply.sh"
    readonly property string wallpaperAddScript:   "/home/crome/.config/quickshell/scripts/wallpaper-add.sh"
    readonly property string wallpaperRenameScript: "/home/crome/.config/quickshell/scripts/wallpaper-rename.sh"
    readonly property string wallpaperDeleteScript: "/home/crome/.config/quickshell/scripts/wallpaper-delete.sh"
    readonly property string wallpaperPickDirScript: "/home/crome/.config/quickshell/scripts/wallpaper-pick-dir.sh"

    // XDG Autostart (BarControlBar → Autostart panel; ~/.config/autostart)
    readonly property string autostartListScript: "/home/crome/.config/quickshell/scripts/autostart-list-json.sh"
    readonly property string autostartSetScript:  "/home/crome/.config/quickshell/scripts/autostart-set.sh"
    readonly property string autostartAddScript:  "/home/crome/.config/quickshell/scripts/autostart-add.sh"
    readonly property string autostartRunScript:  "/home/crome/.config/quickshell/scripts/autostart-run.sh"

    // Clock format (Qt.formatDateTime) — editable from BarControlBar; persisted in bar-layout.json.
    // Region/timezone map: scripts/timezone-control.sh (timedatectl) + assets/world-land.json.
    readonly property string clockFormat: "dddd, MM·dd·yyyy | HH:mm:ss"
    // Clock face family (empty = inherit bar widget text). Scale is independent of fontBarScale.
    property string clockFont: ""
    property real clockFontScale: 1.0
    readonly property string clockFontResolved: {
        var s = (clockFont !== undefined && clockFont !== null) ? ("" + clockFont).trim() : ""
        return s.length ? s : fontBarResolved
    }
    readonly property int clockFontFace: fspRole(13, clockFontScale)
    readonly property string timezoneControlScript: "/home/crome/.config/quickshell/scripts/timezone-control.sh"
    // Presets shown in the control-bar Clock menu: { label, format, tip }
    readonly property var clockFormatPresets: [
        { label: "Full",   format: "dddd, MM·dd·yyyy | HH:mm:ss", tip: "Weekday, date, 24h with seconds" },
        { label: "Date",   format: "ddd MM·dd·yyyy  HH:mm",       tip: "Short weekday + date + time" },
        { label: "Time",   format: "HH:mm:ss",                    tip: "24-hour time with seconds" },
        { label: "Short",  format: "HH:mm",                       tip: "24-hour time only" },
        { label: "12h",    format: "h:mm AP",                     tip: "12-hour with AM/PM" },
        { label: "US",     format: "ddd M/d/yyyy  h:mm AP",       tip: "US-style date + 12h" }
    ]

    // Default widget order + zone for BarControlBar layout editor / runtime reparent.
    // Classic zone: "left" | "center" | "right". Connectivity is Network+Bluetooth+Audio as one unit.
    readonly property var defaultWidgetLayout: [
        { id: "launcher",      zone: "left" },
        { id: "quickLaunch",   zone: "left" },
        { id: "freshRss",      zone: "left" },
        { id: "media",         zone: "left" },
        { id: "workspaces",    zone: "center" },
        { id: "stats",         zone: "right" },
        { id: "tray",          zone: "right" },
        { id: "connectivity",  zone: "right" },
        { id: "clock",         zone: "right" },
        { id: "notifications", zone: "right" },
        { id: "killTarget",    zone: "right" },
        { id: "hyprInsp",      zone: "right" },
        { id: "controlBar",    zone: "right" },
        { id: "power",         zone: "right" }
    ]

    // Dual layout (two centered bars). zone: "top" | "bottom".
    // Hidden-by-default pills (media, killTarget, hyprInsp) stay in the catalog so
    // the Widgets panel can show them on either bar.
    readonly property var defaultDualWidgetLayout: [
        { id: "clock",         zone: "top" },
        { id: "workspaces",    zone: "top" },
        { id: "tray",          zone: "top" },
        { id: "notifications", zone: "top" },
        { id: "power",         zone: "top" },
        { id: "killTarget",    zone: "top" },
        { id: "hyprInsp",      zone: "top" },
        { id: "media",         zone: "top" },
        { id: "stats",         zone: "bottom" },
        { id: "launcher",      zone: "bottom" },
        { id: "quickLaunch",   zone: "bottom" },
        { id: "freshRss",      zone: "bottom" },
        { id: "controlBar",    zone: "bottom" },
        { id: "connectivity",  zone: "bottom" }
    ]

    // =========================================================================
    // NWS RADAR (widgets/RadarPill.qml + scripts/radar-fetch.sh)
    // =========================================================================
    // Native map window (not a browser). Radar from NOAA OpenGeo WMS; basemap
    // from Esri World Street Map. No background polling of new frames.
    //
    // Defaults match a radar.weather.gov bookmark centered on Ohio:
    //   center [-83.201, 40.326], zoom ~7.086, local mosaic view
    //
    // radarOverscan: each fetch loads this many viewport-widths of area so you
    // can pan a long distance before a reload. Scale is isotropic (same X/Y) so
    // the buffer matches the window aspect and does not stretch the map.
    // Auto-refresh runs after pan/zoom settles only when the view leaves that
    // buffer (or zoom changes a lot).
    //
    // IPC:
    //   qs ipc call radar toggle | refresh | show | hide
    //
    // product: "cref" (composite reflectivity) or "bref" (base reflectivity)

    readonly property real   radarDefaultLon:     -83.201
    readonly property real   radarDefaultLat:      40.326
    readonly property real   radarDefaultZoom:     7.086
    readonly property string radarDefaultProduct:  "cref"
    readonly property real   radarOverscan:        3.0    // 3× viewport coverage per fetch
    readonly property int    radarSettleMs:        420    // debounce before edge auto-reload
    readonly property int    radarWidth:           popupW(980)
    readonly property int    radarHeight:          popupH(680)
    readonly property int    radarMinWidth:        sp(560)
    readonly property int    radarMinHeight:       sp(400)

    // =========================================================================
    // FRESHRSS READER (widgets/FreshRssPill.qml + scripts/freshrss-api.sh)
    // =========================================================================
    // Server + credentials (outside git):
    //   ~/.config/freshrss-quickshell/freshrss.env
    //   FRESHRSS_BASE_URL / FRESHRSS_USER / FRESHRSS_API_PASSWORD
    // Without API password the client uses public RSS (anonymous, read-only).
    // API password = Profile → API password (not web form login).
    // Edit via control bar Options → FreshRSS, or the env file by hand.
    //
    // Reader defaults (in FreshRssPill.qml):
    //   readScope = "all", dateFilter = "all", categories start collapsed.
    //
    // IPC:
    //   qs ipc call freshRss toggle
    //   qs ipc call freshRss refresh

    readonly property int freshRssPollIntervalMs:  60000  // badge poll while bar is up
    readonly property int freshRssItemLimit:       80     // max unread/starred ids (when maxDays=0)
    // For All/Read scopes: recent articles pulled from *each* feed so quiet channels
    // still appear, not only high-volume feeds.
    // Ignored when freshRssMaxDays > 0 (day window is the primary limit).
    readonly property int freshRssPerFeedLimit:    12
    // Primary history window: only articles newer than this many days.
    // When > 0, overrides per-feed and item-count caps.
    // 0 = unlimited (use per-feed / item limits only).
    readonly property int freshRssMaxDays:         30
    // Filters panel (search / max days / per feed) open on reader start
    readonly property bool freshRssFiltersExpandedDefault: true
    readonly property int freshRssWidth:           popupW(980)
    readonly property int freshRssHeight:          popupH(640)
    readonly property int freshRssMinWidth:        sp(640)
    readonly property int freshRssMinHeight:       sp(420)
    readonly property int freshRssListWidth:       sp(320)   // default list pane width (SplitView)
    readonly property int freshRssListMinWidth:    sp(180)   // drag limit — list pane
    readonly property int freshRssListMaxWidth:    sp(720)
    readonly property int freshRssDetailMinWidth:  sp(260)   // drag limit — article pane
    // Scripts for Options panel credentials UI
    readonly property string freshRssSecretsReadScript:  "/home/crome/.config/quickshell/scripts/freshrss-secrets-read.sh"
    readonly property string freshRssSecretsWriteScript: "/home/crome/.config/quickshell/scripts/freshrss-secrets-write.sh"
    readonly property string freshRssConnectionTestScript: "/home/crome/.config/quickshell/scripts/freshrss-connection-test.sh"

    // =========================================================================
    // NOTIFICATION BELL (widgets/NotificationBell.qml)
    // =========================================================================
    // CLI commands for your notification daemon. Defaults below are for SwayNC.
    // To use a different daemon, replace these lists with that client's commands
    // (same argv-list style as Quick Launch). Leave [] to disable an action.
    //
    // History (every Notify, survives reboot) is scripts/notification-history.py →
    // ~/.local/state/quickshell/notification-history.json. Left-click the bell opens
    // that panel. Right-click toggles DND. SwayNC's control center is not used in the UI.
    //
    //   notificationSubscribe    — live badge/DND updates (SwayNC: swaync-client -s)
    //   notificationTogglePanel  — unused in UI (SwayNC control center); kept for IPC/scripts
    //   notificationToggleDnd    — DND on the history panel + right-click the bell
    //   notificationClearAll     — also run from the history panel "Clear list"
    //   notificationSync         — backup poll script; prints one JSON line per run:
    //                              {"count":N,"dnd":true|false}
    //   notificationDndAccent    — border/bell color when Do Not Disturb is on

    readonly property var notificationSubscribe:    ["swaync-client", "-s", "-sw"]  // Live JSON stream (optional)
    readonly property var notificationTogglePanel: ["swaync-client", "-t", "-sw"]   // Unused in UI
    readonly property var notificationToggleDnd:   ["swaync-client", "-d", "-sw"]   // History panel + right-click
    readonly property var notificationClearAll:    ["swaync-client", "-C", "-sw"]   // History "Clear list"
    // Timer poller — reliable badge/DND backup; script must print {"count":N,"dnd":true|false}
    readonly property var notificationSync: [
        "/home/crome/.config/quickshell/scripts/notification-sync.sh"
    ]
    readonly property int notificationSyncIntervalMs: 2500  // Ms between sync script runs
    readonly property color notificationDndAccent: muted  // Warning red pill border + bell when DND is on

    // =========================================================================
    // KILL TARGET PILL (widgets/KillTargetPill.qml — xkill-style window picker)
    // =========================================================================
    // Click the pill to arm pick mode, then click any window to close its app.
    // Sends SIGTERM to the window's process (same safety rules as the inspector
    // Processes tab). Escape, right-click, or clicking empty desktop cancels.

    readonly property string killTargetIcon: "🎯"   // 󰍣Crosshair / target icon on the bar pill
    readonly property string killTargetTooltip: "Click to pick a window and kill its app · Esc cancels"
    // Darkening applied to each monitor while pick mode is active (0 = invisible overlay).
    readonly property real killTargetOverlayDim: 0.12

    // =========================================================================
    // POWER MENU (widgets/PowerMenu.qml — session actions)
    // =========================================================================
    // Commands for lock, logout, reboot, shutdown, and Enter BIOS. Each is a list
    // (preferred): ["hyprlock"] or ["sh", "-c", "your shell pipeline"] — or a shell
    // string (runs via sh -c). Use [] to hide an action from both power menus.
    //
    // powerMenuActions — labels and icons shown in the grid + right-click menu.
    // Reorder or rename entries here; command lists below must match action ids.

    readonly property var powerLockCommand: ["hyprlock"]  // Lock screen (left-click grid + right-click menu)
    readonly property var powerLogoutCommand: [           // End Hyprland session; edit app list in the shell pipeline
        "sh", "-c",
        "systemctl --user stop psd.service & pkill -f 'steam|discord|flameshot|espanso|google-chrome-stable|brave|brave-origin' & sleep 1 & command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"
    ]
    readonly property var powerRebootCommand: [         // Reboot the machine
        "sh", "-c",
        "systemctl --user stop psd.service & pkill -f \"steam|discord|flameshot|espanso|google-chrome-stable|brave|brave-origin\" & sleep 1 & reboot"
    ]
    readonly property var powerShutdownCommand: [         // Power off the machine
        "sh", "-c",
        "systemctl --user stop psd.service & pkill -f \"steam|discord|flameshot|espanso|google-chrome-stable|brave|brave-origin\" & sleep 1 & shutdown now"
    ]
    readonly property var powerBiosCommand: ["systemctl", "reboot", "--firmware-setup"]  // UEFI/BIOS on next boot

    // =========================================================================
    // FONTS (writable — Themes → Fonts tab; persisted in theme-colors.json)
    // =========================================================================
    property string fontFamily: "Symbols Nerd Font, JetBrains Mono Nerd Font, monospace"
    property string fontMono:   "JetBrains Mono Nerd Font, monospace"
    // UI type scale on top of uiScale (Themes → Fonts → UI font size). 1.0 = design default.
    property real fontScale: 1.0
    // Monospace size multiplier (Themes → Fonts → Monospace size). Stacks with fontScale.
    property real fontMonoScale: 1.0

    // Per-role faces (empty = inherit). Main/Secondary = menus; Bar = face text on the bar.
    // Stored as primary family name (or full stack); resolved via font*Resolved below.
    property string fontMain: ""
    property string fontSecondary: ""
    property string fontBar: ""
    // Per-role size multipliers on top of fontScale (Themes → Fonts). 1.0 = match UI scale.
    property real fontMainScale: 1.0
    property real fontSecondaryScale: 1.0
    property real fontBarScale: 1.0

    // Font-aware size helper (uiScale × fontScale, min for readability)
    function fsp(base) {
        var b = Number(base)
        if (!(b > 0))
            return 0
        var sc = Number(fontScale)
        if (!(sc > 0))
            sc = 1
        return Math.max(8, Math.round(b * uiScale * sc))
    }

    // Role-scaled size: base × uiScale × fontScale × roleScale
    function fspRole(base, roleScale) {
        var b = Number(base)
        if (!(b > 0))
            return 0
        var sc = Number(fontScale)
        if (!(sc > 0))
            sc = 1
        var rs = Number(roleScale)
        if (!(rs > 0))
            rs = 1
        return Math.max(8, Math.round(b * uiScale * sc * rs))
    }

    function _clampFontRoleScale(s) {
        var x = Number(s)
        if (!(x > 0) || isNaN(x))
            return 1.0
        if (x < 0.70) x = 0.70
        if (x > 1.50) x = 1.50
        return Math.round(x * 100) / 100
    }

    // Resolved stacks for QML Text.font.family (empty role → UI fontFamily)
    readonly property string fontMainResolved: {
        var s = (fontMain !== undefined && fontMain !== null) ? ("" + fontMain).trim() : ""
        return s.length ? s : fontFamily
    }
    readonly property string fontSecondaryResolved: {
        var s = (fontSecondary !== undefined && fontSecondary !== null) ? ("" + fontSecondary).trim() : ""
        return s.length ? s : fontFamily
    }
    readonly property string fontBarResolved: {
        var s = (fontBar !== undefined && fontBar !== null) ? ("" + fontBar).trim() : ""
        return s.length ? s : fontFamily
    }

    // Sizes (base designed for ~58px bar; scaled via uiScale + fontScale [+ role])
    // Main text → menu titles / section headers
    readonly property int fontClock:      fspRole(15, fontBarScale)   // Clock face (bar widget text)
    readonly property int fontPillLabel:  fsp(12)   // Volume % etc. (tier colors; global scale only)
    readonly property int fontPillLabelBold: fsp(12)
    readonly property int fontPopupTitle: fspRole(16, fontMainScale)   // Menu main titles
    readonly property int fontSection:    fspRole(13, fontMainScale)   // Menu section headers
    readonly property int fontBody:       fspRole(12, fontSecondaryScale)   // Menu body / secondary
    readonly property int fontSmall:      fspRole(11, fontSecondaryScale)
    readonly property int fontTiny:       fspRole(10, fontSecondaryScale)
    readonly property int fontPowerLabel: fspRole(12, fontSecondaryScale)
    // Explicit bar-face size (~sysstats / clock / IP) — Themes → Bar widget text size
    readonly property int fontBarFace:    fspRole(13, fontBarScale)
    // Mono sample / mono-labeled UI (Themes → Monospace size)
    readonly property int fontMonoFace:   fspRole(12, fontMonoScale)

    // =========================================================================
    // ICON GLYPHS (single place to change the entire icon language)
    // =========================================================================
    // Speaker / volume (MDI — matches mic/tray visual weight; FA glyphs render smaller at same px)
    readonly property string iconSpeaker:       "󰕾"
    readonly property string iconSpeakerMuted:  "󰖁"
    // Microphone
    readonly property string iconMic:           "󰍬"
    readonly property string iconMicMuted:      "󰍭"
    // Audio device transport / form (AudioPill device picker)
    readonly property string iconAudioBluetooth: "󰂯"   // Bluetooth headset/speakers
    readonly property string iconAudioUsb:       "󰕓"   // USB audio (DAC, webcam mic, etc.)
    readonly property string iconAudioHdmi:      "󰡁"   // HDMI / DisplayPort audio
    readonly property string iconAudioInternal:  "󰓃"   // Built-in / PCI analog
    readonly property string iconAudioHeadset:   "󰋋"   // Headset form factor
    readonly property string iconAudioBattery:   "󰁹"   // BT battery (generic full)
    // Bluetooth pill (adapter / connection state glyphs)
    readonly property string iconBluetooth:          "󰂯"   // Powered on, idle
    readonly property string iconBluetoothOff:       "󰂲"   // Powered off / no adapter
    readonly property string iconBluetoothConnected: "󰂱"   // At least one device connected
    readonly property string iconBluetoothScanning:  "󰂰"   // Discovery active
    // Network pill (wired / WiFi / radios)
    readonly property string iconNetworkWired:          "󰈀"   // Ethernet connected
    readonly property string iconNetworkWifi:           "󰤨"   // Strong WiFi signal
    readonly property string iconNetworkWifiFair:       "󰤥"   // Medium WiFi
    readonly property string iconNetworkWifiWeak:       "󰤢"   // Weak WiFi
    readonly property string iconNetworkWifiNone:       "󰤟"   // Very weak / no bars
    readonly property string iconNetworkWifiOff:        "󰤭"   // WiFi radio off
    readonly property string iconNetworkDisconnected:   "󰤮"   // No active connection
    readonly property string iconNetworkOff:            "󰲛"   // Networking disabled
    readonly property string iconNetworkPortal:         "󰖟"   // Captive portal
    // Power menu
    readonly property string iconPower:         "󰐥"
    readonly property string iconLock:          "󰌾"
    readonly property string iconLogout:        "󰍃"
    readonly property string iconReboot:        "󰑓"
    readonly property string iconShutdown:      "󰐥"
    readonly property string iconBios:          "󰛳"

    // Menu rows for PowerMenu.qml (grid + right-click). Reorder or rename freely.
    readonly property var powerMenuActions: [
        { icon: iconLock,     label: "Lock",       action: "lock" },
        { icon: iconLogout,   label: "Logout",     action: "logout" },
        { icon: iconReboot,   label: "Reboot",     action: "reboot" },
        { icon: iconShutdown, label: "Shutdown",   action: "shutdown" },
        { icon: iconBios,     label: "Enter BIOS", action: "bios" },
    ]

    // Misc common
    readonly property string iconLauncher:      "󰀻"   // Unused on the bar (launcher is a drawn 3×3 in shell.qml)
    readonly property string iconBell:          "󱅫"
    readonly property string iconBellDnd:       "󰂠"
    readonly property string iconBellEmpty:     "󰂜"

    // =========================================================================
    // SLIDERS & VOLUME BARS (the key user request)
    // =========================================================================
    // These are consumed by VolumeBar.qml and MiniVolumeBar.qml.
    // The components now read these as defaults when you pass `bar` (via the
    // aliases in shell.qml) or when they import the singleton directly.

    // Normal (full) volume bar — used in speaker/mic single views + audio popup
    readonly property int  sliderBarHeight: sp(6)     // Track thickness (VolumeBar default)
    readonly property int  sliderPopupHeight: sp(8)   // Taller version used in the audio popup row

    // Compact dual-view bars (inside AudioPill when both speaker+mic shown)
    readonly property int  sliderMiniHeight: sp(5)

    // Volume bar fallback fill (AudioPill overrides per-level via audioSpeaker/MicUtilColor)
    readonly property color sliderFill:       accent   // Vivid teal-cyan (#00F0E0)
    readonly property color sliderFillMuted:  muted     // Fill when device is muted (magenta)
    readonly property color sliderTrack:      surface  // Background track (blue-slate)

    // Output (speaker) volume color ramps — Themes → Thresholds.
    property int audioUtilThreshold1: 25
    property int audioUtilThreshold2: 50
    property int audioUtilThreshold3: 75

    property color audioSpeakerTier1: "#10B981"   // 0–audioUtilThreshold1%
    property color audioSpeakerTier2: "#F59E0B"
    property color audioSpeakerTier3: "#F97316"
    property color audioSpeakerTier4: "#EF4444"

    // Input (mic) volume color ramps — independent thresholds + colors.
    property int audioMicUtilThreshold1: 25
    property int audioMicUtilThreshold2: 50
    property int audioMicUtilThreshold3: 75

    property color audioMicTier1: "#10B981"
    property color audioMicTier2: "#F59E0B"
    property color audioMicTier3: "#F97316"
    property color audioMicTier4: "#EF4444"

    // Shared monochrome glyph color (launcher, power, kill, media idle, net/bt idle, …)
    // Themes → Icon color also keeps speaker/mic unmuted glyphs in sync.
    property color iconColor: "#ffffff"
    property color audioSpeakerIcon: "#ffffff"   // Unmuted speaker icon (pill + popup)
    property color audioMicIcon:     "#ffffff"   // Unmuted mic icon (pill + popup)
    readonly property color audioSpeakerIconMuted: sliderFillMuted
    readonly property color audioMicIconMuted:     sliderFillMuted

    function audioSpeakerUtilColor(percent) {
        var p = Math.max(0, Math.min(100, percent))
        if (p <= audioUtilThreshold1) return audioSpeakerTier1
        if (p <= audioUtilThreshold2) return audioSpeakerTier2
        if (p <= audioUtilThreshold3) return audioSpeakerTier3
        return audioSpeakerTier4
    }

    function audioMicUtilColor(percent) {
        var p = Math.max(0, Math.min(100, percent))
        if (p <= audioMicUtilThreshold1) return audioMicTier1
        if (p <= audioMicUtilThreshold2) return audioMicTier2
        if (p <= audioMicUtilThreshold3) return audioMicTier3
        return audioMicTier4
    }

    // (sliderRadius is defined in the Radii section above for consistency)

    // =========================================================================
    // WORKSPACES (Hyprland filtered active/occupied pills)
    // =========================================================================
    // Consumed by WorkspacesPill.qml + shell.qml startup via bar.* aliases.
    //
    // Pill display:
    //   wsShowOnlyActive false → always show numbered pills 1..wsMinimumShown
    //   wsShowOnlyActive true  → only occupied/active numbered pills (+ extras)
    //   wsShowSpecialPill      → config default for magic pill (IPC can override at runtime)
    //
    // qs startup (shell.qml) — runs on every qs start AND reload (qs has no session vs reload distinction):
    //   wsStartupWorkspace 0 → do not change Hyprland workspace (recommended; preserves focus on qs reload)
    //   wsStartupWorkspace N → focus workspace N (after optional magic close). Prefer Hyprland exec-once
    //                          for true login-only focus instead of forcing from the bar.

    readonly property bool wsShowSpecialPill: true    // Magic pill default (toggle via qs ipc call shell setShowMagicWorkspacePill)
    readonly property int  wsMinimumShown: 3           // Default pills 1..N (IPC: qs ipc call shell setWsMinimumShown)
    readonly property bool wsShowOnlyActive: false    // IPC: qs ipc call shell setWsShowOnlyActive
    readonly property int  wsStartupWorkspace: 0       // 0 = preserve focus on start/reload. IPC: setWsStartupWorkspace
    readonly property bool wsStartupCloseMagic: false  // Close magic on qs start (only if wsStartupWorkspace > 0). IPC: setWsStartupCloseMagic

    // Legacy workspace hover (unused by WorkspacesPill — uses iconHoverBg now).
    readonly property color wsHoverYellow: "#b8fff8"           // Soft teal hover reference
    // Writable so Colors panel can edit live (also in themeEditableKeys).
    property color wsActiveBg:    Qt.rgba(0.0, 0.85, 0.80, 0.28)  // Active workspace — teal glass
    readonly property color wsActiveBorder: accent     // Vivid teal-cyan (tracks accent)
    property color wsActiveText:  "#e6fffc"
    property color wsInactiveText: "#ffffff"           // Inactive workspace number / icon

    // Legacy names some older code paths may still reference
    readonly property color wsText:        "#8a92b0"
    readonly property color wsActiveTextLegacy: wsActiveText   // (the alias in shell.qml maps wsActiveText → this)

    readonly property int  wsButtonWidth:   sp(42)   // Width of each workspace pill button
    readonly property int  wsButtonHeight:  sp(32)   // Height of each workspace pill button
    readonly property int  wsIconSize:      iconSizeTray  // Glyph size inside workspace pills
    readonly property int  wsNumberSize:    Math.max(9, sp(15))   // Font size for workspace numbers (when no icon)
    readonly property int  wsSpacing:        sp(4)   // Gap between workspace buttons

    // --- Per-workspace pill icons (edit here to remap without touching widget logic)
    // Nerd Font glyphs for most slots; Unicode emoji where noted for color/readability.
    readonly property string wsIcon1:        ""     // Code / dev
    readonly property string wsIcon2:        ""     // Browser
    readonly property string wsIcon3:        "🕹"     // Game (color emoji)
    readonly property string wsIcon4:        ""     // Misc
    readonly property string wsIcon5:        ""     // Misc
    readonly property string wsIcon6:        ""     // Misc
    readonly property string wsIcon7:        ""     // Misc
    readonly property string wsIcon8:        "󰈸"     // Misc
    readonly property string wsIcon9:        "󰈸"     // Misc
    readonly property string wsIcon10:       "󰈸"     // Misc
    readonly property string wsIconDefault:  "󰈸"     // Fallback for unmapped workspace ids

    // Icon picker reference — copy any glyph into wsIcon1…wsIcon10 or wsIconSpecial:
    //   Coding / dev:     💻 🖥️ ⌨️ 🧑‍💻 📟 🛠️ ⚙️ 🔧 🐛 🧪
    //   Browsers:         🌐 🦁 🔍 🦊 🌍 📡
    //   Editors / IDE:   󰨞 📝 ✏️ 📋 📄 🗒️ 💾
    //   Terminal:         ⌨️ 📟
    //   Chat / social:    💬 📱 📧 🗨️
    //   Media:           🎵 🎧 🎬 📺 🎮 🕹
    //   Files / misc:    📁 🗂️  󰈹 󰈸 🔥 ⭐ ✨ 🪄

    // --- Hyprland special workspace (negative id; toggled via Super+S in keybindings.lua)
    // wsSpecialName must match hl.dsp.workspace.toggle_special('<name>') and special:<name> moves.
    readonly property string wsSpecialName:  "magic"
    readonly property string wsIconSpecial:  "🪄"     // Magic space — colorful emoji, icon-only pill

    // Resolve the icon glyph/emoji for a numbered Hyprland workspace id.
    function wsIconForId(id) {
        switch (id) {
            case 1:  return wsIcon1;
            case 2:  return wsIcon2;
            case 3:  return wsIcon3;
            case 4:  return wsIcon4;
            case 5:  return wsIcon5;
            case 6:  return wsIcon6;
            case 7:  return wsIcon7;
            case 8:  return wsIcon8;
            case 9:  return wsIcon9;
            case 10: return wsIcon10;
            default: return wsIconDefault;
        }
    }

    // True when a Hyprland workspace name refers to the configured special workspace.
    function wsIsSpecialName(name) {
        if (!name || name.length === 0) return false;
        return name === wsSpecialName || name === ("special:" + wsSpecialName);
    }

    // =========================================================================
    // SYS STATS PILL (widgets/SysStatsPill.qml — CPU | Memory | GPU)
    // =========================================================================
    // The centered bar pill that shows live CPU, Memory, and GPU stats.
    // Left-click a section opens its metrics popup; right-click CPU/Memory launches
    // btop, right-click GPU launches nvtop (see popupStats* above for popup size).
    //
    // Layout notes (SysStatsPill.qml) — snug by default, still readable:
    //   - Sections hug label + gauge + values (Memory wider than CPU/GPU).
    //   - Pill width fits content + padding (no empty side ballast).
    //   - statPillWidth / statPillSectionWidth only expand if you raise them above 0.
    // If text ever clips, raise statPillPaddingH or statPillSpacing slightly.

    // Optional preferred pill width. 0 = fit content (default, no wasted side space).
    // Set e.g. sp(640) only if you want intentional extra width with centered content.
    readonly property int  statPillWidth: 0

    // Optional minimum column width. 0 = hug content (default). Raise to force equal
    // wider columns (e.g. sp(200)) if you prefer uniform section hit-targets.
    readonly property int  statPillSectionWidth: 0

    // Gap between columns (divider is centered in this slot — not double-spaced).
    readonly property int  statPillSpacing: sp(8)

    // Left and right padding inside the pill border so text is not flush to the edge.
    readonly property int  statPillPaddingH: sp(10)

    // Small horizontal utilization bars (the colored fill behind the % numbers).
    readonly property int  statGaugeWidth:   sp(56)
    readonly property int  statGaugeHeight:   sp(7)
    readonly property int  statGaugeRadius:   sp(3)
    readonly property color statTrack:       Qt.rgba(1, 1, 1, 0.10)  // Bar background track on glass

    // Shared fallback util ramp (older themes / unknown metric).
    property color statUtilTier1: "#10B981"
    property color statUtilTier2: "#F59E0B"
    property color statUtilTier3: "#F97316"
    property color statUtilTier4: "#EF4444"

    // Per-metric util ramps (Themes → Thresholds). Defaults: AMD red / cyan / NVIDIA green.
    property color statCpuTier1: "#E8A0A4"
    property color statCpuTier2: "#ED1C24"
    property color statCpuTier3: "#C4161C"
    property color statCpuTier4: "#FF4500"
    property color statMemTier1: "#5EEAD4"
    property color statMemTier2: "#22D3EE"
    property color statMemTier3: "#06B6D4"
    property color statMemTier4: "#0284C7"
    property color statGpuTier1: "#76B900"
    property color statGpuTier2: "#C4D600"
    property color statGpuTier3: "#FFC800"
    property color statGpuTier4: "#FF5A00"

    // Quick Launch running-app dot (Themes → Theming / Options → Dock).
    property color qlRunningDot: "#00F5FF"

    // At what utilization % each color tier starts (must be in ascending order).
    property int statUtilThreshold1: 25
    property int statUtilThreshold2: 50
    property int statUtilThreshold3: 75

    // CPU/GPU temperature text colors (writable — Memory uses subtext for GiB).
    property color statTempCool: "#f0f4fc"   // Normal temperature (matches default main text)
    property color statTempWarm: "#f0d060"   // Getting warm (bright gold)
    property color statTempHot:  "#FF3D8A"   // Hot (matches default muted / warning pink)

    // Temperatures in °C where the label switches cool → warm → hot.
    property int statTempWarmAt: 70
    property int statTempHotAt:  85

    // Color of the "|" between utilization % and temperature (or used GiB for Memory).
    readonly property color statValueSeparator: overlay

    function statUtilColor(util, metric) {
        var u = Math.max(0, Math.min(100, util))
        var m = String(metric || "")
        var t1 = statUtilTier1
        var t2 = statUtilTier2
        var t3 = statUtilTier3
        var t4 = statUtilTier4
        if (m === "cpu") {
            t1 = statCpuTier1; t2 = statCpuTier2; t3 = statCpuTier3; t4 = statCpuTier4
        } else if (m === "mem" || m === "memory") {
            t1 = statMemTier1; t2 = statMemTier2; t3 = statMemTier3; t4 = statMemTier4
        } else if (m === "gpu") {
            t1 = statGpuTier1; t2 = statGpuTier2; t3 = statGpuTier3; t4 = statGpuTier4
        }
        if (u <= statUtilThreshold1) return t1
        if (u <= statUtilThreshold2) return t2
        if (u <= statUtilThreshold3) return t3
        return t4
    }

    function statTempColor(temp) {
        var t = Math.round(temp)
        if (t > statTempHotAt)  return statTempHot
        if (t > statTempWarmAt) return statTempWarm
        return statTempCool
    }

    // =========================================================================
    // CAVA VISUALIZER (MediaPill background waveform)
    // =========================================================================
    // Animated bars behind the media pill when music is playing.
    readonly property int  cavaBarCount:     40   // Number of vertical bars
    readonly property int  cavaBarGap:        1   // Pixels between bars
    readonly property color cavaInactive:    Qt.rgba(1, 1, 1, 0.18)  // Bar color when silent
    readonly property color cavaActive:      Qt.rgba(0.0, 0.94, 0.88, 0.42)  // Vivid teal when audio plays
    readonly property int  cavaAnimFast:     95   // Animation speed (ms) when media is playing
    readonly property int  cavaAnimSlow:    420   // Animation speed (ms) when idle (saves CPU)

    // =========================================================================
    // SYSTEM MONITORING (SysMonService + HyprConfigInsp sysmon tabs)
    // =========================================================================
    // Shared tokens for live metrics in HyprConfigInsp (CPU/GPU/Memory/Temperature tabs)
    // and reusable gauge/sparkline components.
    //
    // Consumed by:
    //   - widgets/SysMonService.qml (pollInterval default kept in sync by convention)
    //   - widgets/HyprConfigInsp.qml + components/*MonitorView.qml
    //   - components/CircularGauge.qml, Sparkline.qml
    //
    // Notes:
    //   - pollInterval is owned by SysMonService at runtime (default 1500 ms).
    //   - panelTabActive* is reused by HyprConfigInsp tab chips (inspTabActive* aliases).
    // =========================================================================

    // Poll rate default (ms). SysMonService hardcodes 1500 to match; change both if tuning.
    readonly property int sysmonDefaultPollInterval: 1500

    // Shared active-tab chip style (HyprConfigInsp tab bar)
    readonly property color panelTabActiveBg:   Qt.rgba(0.0, 0.85, 0.80, 0.25)  // teal glass chip
    readonly property color panelTabActiveBorder: accent

    // Gauge color ramp for CircularGauge (CPU/GPU/memory/temp). <65% / 65–85% / >85%
    readonly property color gaugeLow:  "#2ee59a"
    readonly property color gaugeMid:  "#f0d060"
    readonly property color gaugeHigh: muted

    // =========================================================================
    // HYPR CONFIG INSPECTOR (HyprConfigInsp.qml floating overlay)
    // =========================================================================
    // Visual tokens for the tabbed Hyprland config / sysmon inspector window.
    // Reuses popupHelpWidth/Height for default size; panelTabActive* for tab chips.
    //
    // Consumed by:
    //   - widgets/HyprConfigInsp.qml (primary)
    //
    // How to extend:
    //   - Add a property here, alias it in HyprConfigInsp via `th.xxx`, use in UI.
    //   - Semantic color helpers (envValueColor) live in config so other tools can reuse.
    // =========================================================================

    // --- Window geometry (FloatingWindow defaults + resize limits)
    // popupHelpWidth/Height are the default inspector size (1060×720).
    readonly property int inspMinWidth:  sp(560)
    readonly property int inspMinHeight: sp(400)
    readonly property int inspContentPadding: sp(18)      // inner margin around the whole layout
    readonly property int inspSectionSpacing: sp(12)      // vertical gap between header/tabs/content/footer

    // --- Window background (inspector-only — does NOT affect audio/power/calendar popups)
    // Defaults mirror glassPopup* so the out-of-box look is unchanged.
    //
    // Solid mode (default):
    //   inspUseGradient = false  →  contentPanel uses inspWindowBg
    //
    // Gradient mode:
    //   inspUseGradient = true   →  vertical fade inspGradientTop → inspGradientBottom
    //   (inspWindowBg is ignored while gradient is active)
    //
    // Example — subtle dark vertical fade:
    //   inspUseGradient: true
    //   inspGradientTop: Qt.rgba(0.10, 0.10, 0.14, 0.93)
    //   inspGradientBottom: Qt.rgba(0.05, 0.05, 0.08, 0.96)
    readonly property color inspWindowBg:         glassPopupBg
    readonly property color inspWindowBorder:     glassPopupBorder
    readonly property color inspWindowHighlight:  glassPopupHighlight
    readonly property bool  inspUseGradient:      false
    readonly property color inspGradientTop:      glassPopupBg
    readonly property color inspGradientBottom:   Qt.rgba(0.03, 0.04, 0.08, 0.96)  // deep blue-slate glass fade

    // --- Tab bar (wrapping Flow of chips + vertical scrollbar when many tabs)
    readonly property int inspTabBarMaxHeight:       sp(102)
    readonly property int inspTabHeight:       sp(30)
    readonly property int inspTabRadius:       sp(7)
    readonly property int inspTabHPadding:       sp(28)    // added to label width for chip width
    readonly property int inspTabSpacing:       sp(6)
    readonly property int inspTabFontSize:     Math.max(9, sp(13))
    // Active tab reuses panelTabActive* tokens (shared tab-chip style)
    readonly property color inspTabActiveBg:      panelTabActiveBg
    readonly property color inspTabActiveBorder:  panelTabActiveBorder
    readonly property color inspTabHoverBg:       surface

    // --- Global search field (right of tab bar)
    readonly property int inspSearchWidth:       sp(220)
    readonly property int inspSearchHeight:       sp(28)        
    readonly property int inspSearchRadius:       sp(6)
    readonly property int inspSearchPadding:       sp(4)
    readonly property int inspSearchFontSize:     Math.max(9, sp(12))          //14
    readonly property color inspSearchSelectionBg: Qt.rgba(0.0, 0.90, 0.85, 0.35)  // teal glass selection

    // --- Header (title row, version/distro, keyboard hints)
    readonly property int inspTitleFontSize:     Math.max(9, sp(18))
    readonly property int inspSubtitleFontSize:     Math.max(9, sp(13))
    readonly property int inspHeaderButtonHeight:       sp(28)
    readonly property int inspRefreshButtonWidth:       sp(78)
    readonly property int inspCloseButtonSize:       sp(28)
    readonly property color inspHeaderDivider: divider

    // --- Footer (status line + action chips: Copy, Refresh, Edit)
    readonly property int inspStatusFontSize:     Math.max(9, sp(12))
    readonly property int inspFooterButtonHeight:       sp(22)
    readonly property int inspFooterButtonRadius:       sp(5)
    readonly property int inspFooterButtonSpacing:       sp(6)

    // --- Scrollbars (tab bar + content Flickables)
    readonly property int inspScrollBarWidth:       sp(6)
    readonly property int inspScrollBarRadius:       sp(3)
    readonly property color inspScrollBarIdle: Qt.rgba(1, 1, 1, 0.2)

    // --- List/table row interaction (binds, env, system info rows)
    readonly property color inspRowHoverBg:       Qt.rgba(1, 1, 1, 0.03)
    readonly property color inspRowHoverBgStrong: Qt.rgba(1, 1, 1, 0.06)  // system info values
    readonly property int inspRowRadius:       sp(4)
    readonly property int inspBindRowHeight:       sp(26)
    readonly property int inspEnvRowHeight:       sp(28)
    readonly property int inspEnvHeaderHeight:       sp(28)

    // --- Environment variable table layout
    readonly property int inspEnvTableSideMargin:       sp(10)
    readonly property int inspEnvTableColSpacing:       sp(12)
    readonly property int inspEnvVarColMinWidth:       sp(180)
    readonly property int inspEnvVarColMaxWidth:       sp(260)
    readonly property real inspEnvVarColRatio:    0.22   // fraction of usable width for Variable column
    readonly property int inspEnvValueColMinWidth:       sp(180)
    readonly property int inspEnvValueColMaxWidth:       sp(340)
    readonly property real inspEnvValueColRatio:   0.28   // fraction of usable width for Value column
    readonly property int inspEnvDescColMinWidth:       sp(320)    // minimum width for Description column

    // --- Key binding modifier pills (liquid glass semantic colors)
    readonly property color inspKeyPillSuper:   "#00F0E0"  // Vivid teal-cyan
    readonly property color inspKeyPillShift:   "#f0a86a"
    readonly property color inspKeyPillCtrl:    "#c084fc"  // Soft violet (contrast against teal)
    readonly property color inspKeyPillAlt:     "#00D4C8"  // Teal sibling of brand accent
    readonly property color inspKeyPillDefault: overlay
    readonly property color inspKeyPillTextOnDark:  "#ffffff"
    readonly property color inspKeyPillTextOnLight: "#000000"
    readonly property int inspKeyPillHeight:       sp(20)
    readonly property int inspKeyPillRadius:       sp(5)
    readonly property int inspKeyPillHPadding:       sp(12)
    readonly property int inspKeyPillFontSize:     Math.max(9, sp(11))

    // --- Environment variable semantic colors (keys + values)
    readonly property color inspEnvKeyHighlight: "#00E8D0"   // graphics/wayland-related keys
    readonly property color inspEnvValueTrue:      "#2ee59a"   // 1, true, enabled
    readonly property color inspEnvValueFalse:     "#f0a86a"   // 0, false, disabled
    readonly property color inspEnvValueTech:      "#00F0E0"   // nvidia, wayland, opengl, direct
    readonly property color inspEnvValuePath:      subtext      // filesystem paths
    readonly property color inspEnvValueTheme:     "#c084fc"   // theme/platform strings (violet)
    readonly property color inspEnvValueTerminal:  "#60D0FF"   // TERMINAL, hyprland refs

    // Prefixes that mark an env *key* as graphics/wayland-related (highlighted in Variable column)
    readonly property var inspEnvHighlightPrefixes: [
        "__GL", "__NV", "__VK", "GBM_", "NVD_", "LIBVA_", "AQ_", "GDK_", "QT_",
        "SDL_", "XDG_", "MOZ_", "ELECTRON_", "CLUTTER_", "HYPRCURSOR", "XCURSOR"
    ]

    function inspKeyPillColor(key) {
        var k = (key || "").toUpperCase().trim()
        if (k.indexOf("SUPER") !== -1 || k.indexOf("WIN") !== -1 || k.indexOf("META") !== -1) return inspKeyPillSuper
        if (k.indexOf("SHIFT") !== -1) return inspKeyPillShift
        if (k.indexOf("CTRL") !== -1 || k.indexOf("CONTROL") !== -1) return inspKeyPillCtrl
        if (k.indexOf("ALT") !== -1) return inspKeyPillAlt
        return inspKeyPillDefault
    }

    function inspKeyPillTextColor(key) {
        return inspKeyPillColor(key) === inspKeyPillDefault ? inspKeyPillTextOnDark : inspKeyPillTextOnLight
    }

    function inspEnvKeyIsHighlight(key) {
        var k = (key || "").toUpperCase()
        if (!k) return false
        for (var i = 0; i < inspEnvHighlightPrefixes.length; i++) {
            if (k.indexOf(inspEnvHighlightPrefixes[i]) === 0) return true
        }
        return k.indexOf("WAYLAND") !== -1
    }

    function inspEnvKeyColor(key) {
        return inspEnvKeyIsHighlight(key) ? inspEnvKeyHighlight : accent
    }

    function inspEnvValueColor(key, value) {
        var v = (value || "").trim()
        var lower = v.toLowerCase()
        var k = (key || "").toUpperCase()

        if (lower === "1" || lower === "true" || lower === "enabled") return inspEnvValueTrue
        if (lower === "0" || lower === "false" || lower === "disabled") return inspEnvValueFalse

        if (inspEnvKeyIsHighlight(key) || lower.indexOf("nvidia") !== -1 || lower.indexOf("wayland") !== -1
                || lower.indexOf("opengl") !== -1 || lower === "direct" || lower.indexOf("nvidia_only") !== -1) {
            return inspEnvValueTech
        }

        if (v.indexOf("/") === 0 || v.indexOf("~") === 0 || v.indexOf("/dev/") !== -1) {
            return inspEnvValuePath
        }

        if (k.indexOf("THEME") !== -1 || k.indexOf("PLATFORMTHEME") !== -1
                || lower.indexOf("bibata") !== -1 || lower === "qt6ct" || lower === "auto"
                || lower === "arch-") {
            return inspEnvValueTheme
        }

        if (k === "TERMINAL" || lower.indexOf("hyprland") !== -1) return inspEnvValueTerminal

        return text
    }

    // =========================================================================
    // DIVIDERS & SUBTLE LINES
    // =========================================================================
    readonly property color divider:         Qt.rgba(1, 1, 1, 0.12)   // Soft glass divider
    readonly property color dividerSubtle:   Qt.rgba(1, 1, 1, 0.07)   // Fainter glass hairline
    readonly property color dividerStrong:   Qt.rgba(0.55, 0.72, 0.82, 0.14)  // Soft cool section lines
    readonly property int  dividerThickness: 1

    // =========================================================================
    // TRAY MENU (SystemTrayPill check/radio rows)
    // =========================================================================
    readonly property color menuCheckMark:     text    // ✓ / ● glyphs (not accent — avoids purple GTK clash)
    readonly property color menuUncheckedMark: overlay // ○ / empty radio ring
    readonly property color menuCheckedRow:  Qt.rgba(0.0, 0.90, 0.85, 0.18)  // teal glass highlight on checked items

    // =========================================================================
    // TRAY MENU BUTTON TYPE ENUMS (mirror of QsMenuButtonType for safety)
    // =========================================================================
    readonly property int menuBtnNone:  0
    readonly property int menuBtnCheck: 1
    readonly property int menuBtnRadio: 2

    // =========================================================================
    // ANIMATION & INTERACTION TOKENS
    // =========================================================================
    // Centralized durations and delays for consistent feel across the bar.
    // Recommended easing for most UI motion: Easing.OutQuad (used in existing Behaviors).

    readonly property int animFast:   90    // Quick feedback (Cava bars, small state changes)
    readonly property int animMedium: 140   // Standard hover / color transitions (WorkspacesPill)
    readonly property int animSlow:   220   // Slower, more noticeable motion

    // Interaction delays
    // Writable: Options → Tooltips delay + bar-layout.json (200–3000 ms).
    property int tooltipDelay: 1550

    // =========================================================================
    // Z-LAYERS (only the global ones that matter across components)
    // =========================================================================
    readonly property int zMediaPill:  5
    readonly property int zSysStats:   5
    // Most other z usage is local (z: -1 for click-eaters)

    // =========================================================================
    // CONVENIENCE / DERIVED (rarely need editing)
    // =========================================================================
    readonly property int popupY: barHeight + 2   // Legacy Y offset under the bar (prefer popupBarGap + popupAnchorY)

    // --- NotificationBell command resolver (used by shell.qml + NotificationBell.qml)
    function notificationCommand(action) {
        if (action === "subscribe") return notificationSubscribe
        if (action === "togglePanel") return notificationTogglePanel
        if (action === "toggleDnd") return notificationToggleDnd
        if (action === "clearAll") return notificationClearAll
        if (action === "sync") return notificationSync
        return []
    }

    function notificationCmdLength(cmd) {
        return cmd && cmd.length !== undefined && cmd.length > 0
    }

    function notificationUsesLiveSubscribe() {
        return notificationCmdLength(notificationSubscribe)
    }

    function notificationSyncEnabled() {
        return notificationCmdLength(notificationSync)
    }

    function notificationSupportsPanel() {
        var cmd = notificationCommand("togglePanel")
        return cmd && cmd.length !== undefined && cmd.length > 0
    }

    function notificationSupportsDnd() {
        var cmd = notificationCommand("toggleDnd")
        return cmd && cmd.length !== undefined && cmd.length > 0
    }

    function notificationSupportsClearAll() {
        var cmd = notificationCommand("clearAll")
        return cmd && cmd.length !== undefined && cmd.length > 0
    }

    // --- PowerMenu command resolver (used by shell.qml + PowerMenu.qml)
    function powerCommand(action) {
        if (action === "lock") return powerLockCommand
        if (action === "logout") return powerLogoutCommand
        if (action === "reboot") return powerRebootCommand
        if (action === "shutdown") return powerShutdownCommand
        if (action === "bios") return powerBiosCommand
        return []
    }

    function powerActionEnabled(action) {
        var cmd = powerCommand(action)
        if (typeof cmd === "string")
            return cmd.length > 0
        return cmd && cmd.length !== undefined && cmd.length > 0
    }

    function powerMenuItems() {
        var out = []
        var actions = powerMenuActions
        if (!actions || actions.length === undefined)
            return out
        for (var i = 0; i < actions.length; i++) {
            var entry = actions[i]
            if (entry && powerActionEnabled(entry.action))
                out.push(entry)
        }
        return out
    }

}
