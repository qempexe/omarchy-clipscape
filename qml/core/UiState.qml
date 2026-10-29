import QtQuick
import "../js/Schema.js" as Schema

// Colors, spacing and what is showing, for the panel, the pop-out window and the
// picker (`ui.*`). Its own item, so none of these names can clash with the shell's types.
Item {
    id: root

    visible: false

    property var store: null
    property var cfg: null           // resolved settings (Schema.resolve)

    property bool popped: false      // the panel lives in its own window
    property string tabName: "clips" // clips | settings
    property int settingsGroup: 0

    signal popOutRequested()
    signal dockRequested()
    signal closeRequested()
    signal pickerRequested()
    signal tabRequested(string name, bool toggle)   // from ipc, one bar button answers
    property var host: null                         // the bar button used last

    readonly property var cfgSafe: cfg ? cfg : Schema.defaults

    // small separate values, so a delegate only updates when its own one changes
    readonly property real densityF: cfgSafe.density === "compact" ? 0.85 : (cfgSafe.density === "spacious" ? 1.2 : 1.0)
    readonly property real fontPct: cfgSafe.fontScale
    readonly property real tintPct: cfgSafe.surfaceTint
    readonly property bool frameOn: cfgSafe.frame === true
    readonly property real opacityF: Math.max(0.5, Math.min(1, cfgSafe.opacity / 100))
    readonly property string cardStyle: cfgSafe.cardStyle
    readonly property real radius: cfgSafe.cornerRadius

    // from the shell theme
    property color barFg: "white"
    property color barBg: "#121217"
    property color themeAccent: "transparent"
    property string fontName: ""
    // the theme's window border: its colors (#rrggbb) and angle, read by the service
    property var borderColors: []
    property real borderAngle: 0

    function lumOf(c) { return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b }
    // black or white, whichever reads better on c
    function contrast(c) {
        return lumOf(c) > 0.5 ? Qt.rgba(0.08, 0.08, 0.08, 1) : Qt.rgba(0.96, 0.96, 0.96, 1)
    }
    function grey(l) { return Qt.rgba(l, l, l, 1) }
    function hexOr(v, fallback) { return Qt.color(Schema.validHex(v) ? v : fallback) }
    // text has to read against the surface: too close to it, and it turns black or white
    function readable(c, on) { return Math.abs(lumOf(c) - lumOf(on)) >= 0.35 ? c : contrast(on) }

    // ---- the color scheme (Settings > Colors) ---------------------------------------
    //   theme       the bar's own colors and the theme's accent
    //   borders     the same, with the accent from the window border
    //   custom      your background, text and accent, exactly as picked
    //   monochrome  no hue at all: greys at the bar's brightness
    readonly property string colorMode: cfgSafe.colorMode
    readonly property bool mono: colorMode === "monochrome"
    readonly property bool custom: colorMode === "custom"

    // the bar's real background, so the panel and the pop-out window show the same color
    readonly property color barSurface: Qt.rgba(barBg.r, barBg.g, barBg.b, 1)
    readonly property color surface: custom ? hexOr(cfgSafe.customBg, "#141414")
        : (mono ? grey(lumOf(barSurface)) : barSurface)
    readonly property bool lightSurface: lumOf(surface) > 0.5
    readonly property color customFg: hexOr(cfgSafe.customFg, "#e0e0e0")
    readonly property color fg: custom ? customFg
        : (mono ? contrast(surface)
        : (cfgSafe.textColor === "custom" ? readable(customFg, surface)
        : (cfgSafe.textColor === "theme" ? barFg : readable(barFg, surface))))
    readonly property bool hasThemeAccent: themeAccent.a > 0
    readonly property color themeAc: hasThemeAccent ? Qt.rgba(themeAccent.r, themeAccent.g, themeAccent.b, 1) : barFg
    readonly property color accent: custom ? hexOr(cfgSafe.accentColor, "#d4a35a")
        : (mono ? fg
        : (colorMode === "borders" && borderColors.length > 0 ? Qt.color(borderColors[0]) : themeAc))

    // the window outline: the window border's gradient, one color from it, or the accent
    readonly property bool frameGradientOn: frameOn && cfgSafe.frameGradient !== false && borderColors.length > 1
    readonly property color frameColor: {
        const n = borderColors.length
        const pick = cfgSafe.frameColor
        if (n === 0 || pick === "accent" || !pick) return accent
        if (pick === "first") return Qt.color(borderColors[0])
        if (pick === "last") return Qt.color(borderColors[n - 1])
        return Qt.color(borderColors[Math.floor((n - 1) / 2)])
    }

    // the colors of a scheme, for its tile in Settings: background, text, accent(s)
    function schemeColors(name) {
        if (name === "custom")
            return { bg: hexOr(cfgSafe.customBg, "#141414"), fg: customFg, ac: hexOr(cfgSafe.accentColor, "#d4a35a") }
        if (name === "monochrome") {
            const g = grey(lumOf(barSurface))
            return { bg: g, fg: contrast(g), ac: contrast(g) }
        }
        if (name === "borders" && borderColors.length > 0) {
            const n = borderColors.length
            return { bg: barSurface, fg: barFg, ac: Qt.color(borderColors[0]),
                     acs: [Qt.color(borderColors[0]), Qt.color(borderColors[Math.min(n - 1, 1)]), Qt.color(borderColors[Math.min(n - 1, 2)])] }
        }
        return { bg: barSurface, fg: barFg, ac: themeAc }
    }

    // text on a filled accent: black or white; in Custom whichever of your background and
    // text color reads better on it, so only your own colors show
    readonly property color accentText: custom
        ? (Math.abs(lumOf(surface) - lumOf(accent)) >= Math.abs(lumOf(fg) - lumOf(accent)) ? surface : fg)
        : contrast(accent)
    readonly property color good: mono ? fg
        : (lightSurface ? Qt.rgba(0.14, 0.50, 0.26, 1) : Qt.rgba(0.48, 0.85, 0.56, 1))
    readonly property color warn: mono ? fg
        : (lightSurface ? Qt.rgba(0.62, 0.40, 0.02, 1) : Qt.rgba(0.94, 0.71, 0.30, 1))
    readonly property color bad: mono ? fg
        : (lightSurface ? Qt.rgba(0.74, 0.16, 0.26, 1) : Qt.rgba(0.97, 0.46, 0.56, 1))

    readonly property bool animations: true

    function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a) }
    function accentTint(a) { return Qt.rgba(accent.r, accent.g, accent.b, a) }
    // rows, by Row style: soft (filled), outline, flat
    function cardFill(hover) {
        if (cardStyle === "soft") return tint(hover ? 0.10 : 0.05)
        return hover ? tint(0.05) : "transparent"
    }
    readonly property int cardBorder: cardStyle === "outline" ? 1 : 0
    // text on an "on" chip (c at 22% over the surface)
    function onFill(c) {
        return Qt.rgba(surface.r * 0.78 + c.r * 0.22, surface.g * 0.78 + c.g * 0.22,
                       surface.b * 0.78 + c.b * 0.22, 1)
    }
    function onText(c) { return custom ? fg : contrast(onFill(c)) }
    // the window background, as solid as Window opacity says
    readonly property color panelColor: Qt.rgba(surface.r, surface.g, surface.b, opacityF)

    // corner radius as a multiple of Roundness (1.5 buttons, 2 rows, 2.5 cards, 3 windows)
    function r(k) { return Math.min(24, Math.round(radius * k)) }
    readonly property real baseScale: 0.82
    function fs(n) { return Math.max(7, Math.round(n * fontPct / 100 * baseScale)) }
    function px(n) { return Math.round(n * densityF) }
}
