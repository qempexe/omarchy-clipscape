import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "js/Schema.js" as Schema
import "js/Clips.js" as Clips
import "js/Theme.js" as Theme
import "core"

// The always-loaded part: settings, the colors, the history and the watcher that keeps
// it, and ipc. The picker, the bar button and its panel all read from here, so they
// never disagree.
Item {
    id: root

    visible: false

    property var shell: null
    property var manifest: null      // handed in by the shell; read from manifest.json when it isn't

    readonly property string pluginId: "io.github.qempexe.clipscape"

    function readText(fv) {
        try { return String(typeof fv.text === "function" ? fv.text() : fv.text) } catch (e) { return "" }
    }

    FileView {
        id: manifestFile
        path: decodeURIComponent(Qt.resolvedUrl("../manifest.json").toString().replace(/^file:\/\//, ""))
        onLoaded: {
            if (root.manifest) return
            let m = null
            try { m = JSON.parse(root.readText(manifestFile)) } catch (e) { m = null }
            const v = m && typeof m.version === "string" && /^[0-9A-Za-z.+-]{1,32}$/.test(m.version) ? m.version : ""
            root.manifest = { version: v }
        }
    }

    // opening a link: only plain http(s) addresses, through xdg-open
    function openUrl(url) {
        const u = String(url || "").trim()
        if (!/^https?:\/\/[A-Za-z0-9.-]+(:[0-9]{1,5})?(\/[A-Za-z0-9._~%!$&'()*+,;=:@\/?#-]*)?$/.test(u) || u.length > 2000) return false
        opener.command = ["xdg-open", u]
        opener.running = true
        return true
    }
    // a copied file's folder, in the file manager (the file itself is never opened)
    function showFolder(path) {
        const p = String(path || "")
        if (p.charAt(0) !== "/" || p.indexOf("\n") >= 0 || p.length > 4096) return false
        const dir = p.replace(/\/[^\/]*$/, "") || "/"
        opener.command = ["xdg-open", dir]
        opener.running = true
        return true
    }
    Process { id: opener }

    // ---- settings ---------------------------------------------------------------------
    SettingsStore { id: settingsStore }
    property alias store: settingsStore
    readonly property var cfg: Schema.resolve(settingsStore.values)

    function setValue(key, value) {
        if (Schema.isSetting(key)) settingsStore.set(key, Schema.clean(key, value))
    }

    // pausing is kept with the settings (so it survives a restart) but isn't one of them
    readonly property bool paused: settingsStore.values.paused === true
    function setPaused(v) { settingsStore.set("paused", v === true ? true : null) }
    function togglePaused() { setPaused(!paused) }

    // the filter the picker opened with last, for Opens on: The last filter
    readonly property string lastFilter: Clips.FILTER_KEYS.indexOf(String(settingsStore.values.lastFilter)) >= 0
        ? String(settingsStore.values.lastFilter) : "all"
    function rememberFilter(f) {
        if (Clips.FILTER_KEYS.indexOf(f) >= 0 && f !== lastFilter) settingsStore.set("lastFilter", f)
    }

    UiState {
        id: ux
        store: settingsStore
        cfg: root.cfg
        barFg: Color.bar.text
        barBg: Color.bar.background
        themeAccent: Color.accent
        fontName: Style.font.family
        borderColors: root.borderColors
        borderAngle: root.borderAngle
        onPickerRequested: root.openPicker("")
    }
    property alias ui: ux

    // ---- the history -----------------------------------------------------------------------
    ClipStore {
        id: clipStore
        cfg: root.cfg
        paused: root.paused
    }
    property alias clips: clipStore

    readonly property int count: clipStore.clips.length

    // ---- the picker -------------------------------------------------------------------
    function openPicker(payload) {
        if (root.shell && typeof root.shell.summon === "function")
            return root.shell.summon(root.pluginId, String(payload || "")) === true
        return false
    }

    // ---- the theme's window border ------------------------------------------------------
    // For the Window borders scheme and the window outline: the active border's colors and
    // angle, from the theme's hyprland.lua (or .conf, or the line some themes keep in
    // colors.toml). Only #rrggbb values and an angle are taken from these files.
    property var tomlBorder: ({ colors: [], angle: 0 })
    property var luaBorder: ({ colors: [], angle: 0 })
    property var confBorder: ({ colors: [], angle: 0 })
    property bool luaMissing: false
    readonly property var borderColors: luaBorder.colors.length > 0 ? luaBorder.colors
        : (confBorder.colors.length > 0 ? confBorder.colors : tomlBorder.colors)
    readonly property real borderAngle: luaBorder.colors.length > 0 ? luaBorder.angle
        : (confBorder.colors.length > 0 ? confBorder.angle : tomlBorder.angle)
    readonly property string themeDir: {
        try { return Color.currentThemePath ? String(Color.currentThemePath) : "" } catch (e) { return "" }
    }

    FileView {
        id: paletteFile
        path: root.themeDir !== "" ? root.themeDir + "/colors.toml" : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.tomlBorder = Theme.parseBorder(root.readText(paletteFile))
        onLoadFailed: { root.tomlBorder = ({ colors: [], angle: 0 }); root.retryTheme() }
    }
    FileView {
        id: borderLua
        path: root.themeDir !== "" ? root.themeDir + "/hyprland.lua" : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { root.luaMissing = false; root.luaBorder = Theme.parseBorder(root.readText(borderLua)) }
        onLoadFailed: { root.luaBorder = ({ colors: [], angle: 0 }); root.luaMissing = true }
    }
    FileView {
        id: borderConf
        // only looked at when the theme has no hyprland.lua
        path: root.themeDir !== "" && root.luaMissing ? root.themeDir + "/hyprland.conf" : ""
        watchChanges: true
        onFileChanged: reload()
        onPathChanged: if (path === "") root.confBorder = ({ colors: [], angle: 0 })
        onLoaded: root.confBorder = Theme.parseBorder(root.readText(borderConf))
        onLoadFailed: root.confBorder = ({ colors: [], angle: 0 })
    }
    // a theme switch replaces the theme folder, so for a moment the files are gone and
    // the watch can lose track of them: read them again shortly after, a few times at most
    property int themeTries: 0
    function retryTheme() { if (themeTries < 3) { themeTries++; themeRetry.restart() } }
    Timer {
        id: themeRetry
        interval: 800
        onTriggered: { paletteFile.reload(); borderLua.reload(); borderConf.reload() }
    }
    Connections {
        target: Color
        ignoreUnknownSignals: true
        function onAccentChanged() { root.themeTries = 0; themeRetry.restart() }
        function onBackgroundChanged() { root.themeTries = 0; themeRetry.restart() }
    }

    // ---- ipc: omarchy-shell io.github.qempexe.clipscape <function> ---------------------
    IpcHandler {
        target: root.pluginId

        function picker(): string { return root.openPicker("") ? "ok" : "unavailable" }
        // the panel on a tab, again to close
        function panel(): string { root.ui.tabRequested("clips", true); return "ok" }
        function settings(): string { root.ui.tabRequested("settings", true); return "ok" }

        function pause(): string { root.setPaused(true); return "paused" }
        function resume(): string { root.setPaused(false); return "recording" }
        function togglePause(): string { root.togglePaused(); return root.paused ? "paused" : "recording" }

        // copy (or paste) the n-th clip, 1 being the newest
        function copy(n: string): string { return root.useNth(n, "copy") }
        function paste(n: string): string { return root.useNth(n, "paste") }

        function clear(): string { clipStore.clearUnpinned(); return "cleared" }

        function status(): string {
            return JSON.stringify({
                clips: root.count,
                pinned: clipStore.pinnedCount,
                recording: !root.paused,
                ready: clipStore.ready
            })
        }
    }

    function useNth(n, how) {
        const i = parseInt(String(n || "1"), 10)
        if (!(i >= 1 && i <= clipStore.clips.length)) return "no clip " + String(n).slice(0, 8)
        return clipStore.use(clipStore.clips[i - 1].id, how) ? "ok" : "failed"
    }
}
