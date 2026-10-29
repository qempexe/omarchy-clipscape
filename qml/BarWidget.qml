import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "js/Clips.js" as Clips

// The bar button. Left click opens the panel, right click opens it on Settings, middle
// click opens the picker (or pauses). All state lives in the service, so the button,
// the panel and the picker never disagree.
BarWidget {
    id: root

    moduleName: "io.github.qempexe.clipscape"

    // service can show up a bit after the bar, so keep asking
    property var svc: null
    function lookup() {
        if (svc) return
        try {
            if (bar && bar.shell && typeof bar.shell.serviceFor === "function")
                svc = bar.shell.serviceFor(moduleName)
        } catch (e) { svc = null }
    }
    onBarChanged: { lookup(); injectPanel() }
    onSvcChanged: injectPanel()
    Timer {
        interval: 250
        repeat: true
        running: root.svc === null
        onTriggered: root.lookup()
    }

    readonly property var ux: svc ? svc.ui : null
    readonly property var cfg: svc ? svc.cfg : null

    // the button
    readonly property bool paused: svc ? svc.paused : false
    readonly property string icon: paused ? "󰏤" : "󰅌"
    readonly property string label: {
        const c = root.cfg
        if (!c || !root.svc) return icon
        if (c.barShows === "count") return icon + " " + root.svc.count
        if (c.barShows === "last") {
            const l = root.svc.clips.latest
            if (!l) return icon
            let t = Clips.title(l, true)
            if (l.secret) t = "••••••"
            if (t.length > 22) t = t.slice(0, 21) + "…"
            return icon + " " + t
        }
        return icon
    }
    readonly property string tooltip: {
        if (!svc) return "Clipscape"
        const n = svc.count
        return "Clipscape: " + n + (n === 1 ? " clip" : " clips") + (paused ? ", paused" : "") + " · Super+Ctrl+V"
    }

    // panel / popped out window
    property bool userPicked: false
    readonly property bool popped: ux ? ux.popped : false

    readonly property bool panelOpened: panelLoader.item ? panelLoader.item.opened === true : false
    readonly property bool windowShown: windowLoader.item ? windowLoader.item.visible === true : false
    readonly property bool opened: panelOpened

    function setPopped(v) { if (ux) ux.popped = v }

    // "open as" wins until someone uses pop out / dock in the header
    function chooseMode() {
        if (userPicked || !cfg) return
        const want = cfg.openAs === "window"
        if (want === popped) return
        if (windowShown) hideWindow()
        if (panelOpened) closePanel()
        setPopped(want)
    }

    property bool windowRequested: false
    function showWindow() {
        windowRequested = true
        if (windowLoader.item) windowLoader.item.visible = true
    }
    function hideWindow() {
        if (windowLoader.item) windowLoader.item.visible = false
        windowRequested = false
    }

    // hyprland closed it on us -> forget it so the next click makes a new one
    Connections {
        target: windowLoader.item
        ignoreUnknownSignals: true
        function onVisibleChanged() {
            if (windowLoader.item && !windowLoader.item.visible && root.windowRequested)
                root.windowRequested = false
        }
    }

    // panel failed to show? open it as a window instead of doing nothing (reason goes to the log)
    property bool wantPanel: false
    function fallbackToWindow(reason) {
        console.warn("Clipscape: " + reason + "; opening as a window instead")
        wantPanel = false
        panelCheck.stop()
        setPopped(true)
        showWindow()
    }

    function openPanel() {
        if (panelLoader.status === Loader.Error || !panelLoader.item) {
            fallbackToWindow("Panel.qml is not loaded (status " + panelLoader.status + ")")
            return
        }
        injectPanel()
        wantPanel = true
        panelLoader.item.open()
        panelCheck.restart()
    }
    function closePanel() {
        wantPanel = false
        panelCheck.stop()
        if (panelLoader.item) panelLoader.item.close()
    }

    function open() {
        if (!svc) { lookup(); if (!svc) return }
        chooseMode()
        if (popped) showWindow()
        else openPanel()
    }
    function close() {
        closePanel()
        hideWindow()
    }
    function toggle() {
        if (!svc) { lookup(); if (!svc) return }
        if (ux) ux.host = root
        chooseMode()
        if (popped) {
            if (windowShown) hideWindow()
            else showWindow()
        } else if (panelOpened) {
            closePanel()
        } else if (!(panelLoader.item && panelLoader.item.justClosedByGrab === true)) {
            openPanel()
        }
    }
    function popOut() {
        userPicked = true
        setPopped(true)
        closePanel()
        showWindow()
    }
    function dock() {
        userPicked = true
        hideWindow()
        setPopped(false)
        Qt.callLater(root.openPanel)
    }
    function showTab(name) {
        if (ux) ux.tabName = name
        if (!opened && !windowShown) open()
    }

    onPanelOpenedChanged: if (panelOpened) { wantPanel = false; panelCheck.stop() }

    Timer {
        id: panelCheck
        interval: 600
        onTriggered: if (root.wantPanel && !root.panelOpened && !root.popped)
            root.fallbackToWindow("the panel did not open")
    }

    // header buttons -> whichever bar button owns the panel
    Connections {
        target: root.ux
        ignoreUnknownSignals: true
        function onPopOutRequested() { if (root.panelOpened || root.windowShown) root.popOut() }
        function onDockRequested() { if (root.panelOpened || root.windowShown) root.dock() }
        function onCloseRequested() { root.close() }
        // first button to hear it takes it, so several bars don't all open a panel
        function onTabRequested(name, toggle) {
            if (!root.ux.host) root.ux.host = root
            if (root.ux.host !== root) return
            const shown = root.panelOpened || root.windowShown
            if (toggle && shown && root.ux.tabName === name) root.close()
            else root.showTab(name)
        }
    }

    function injectPanel() {
        if (!panelLoader.item) return
        panelLoader.item.bar = root.bar
        panelLoader.item.anchorItem = button
        panelLoader.item.hostWidget = root
        panelLoader.item.svc = root.svc
    }

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("panel/Panel.qml")
        onLoaded: {
            root.injectPanel()
            Qt.callLater(root.injectPanel)
        }
        onStatusChanged: if (status === Loader.Error)
            console.warn("Clipscape: Panel.qml failed to load; check the shell log for the QML error")
    }

    Loader {
        id: windowLoader
        active: root.windowRequested
        source: Qt.resolvedUrl("panel/PopoutWindow.qml")
        onLoaded: {
            item.svc = root.svc
            item.visible = root.windowRequested
        }
        onStatusChanged: if (status === Loader.Error)
            console.warn("Clipscape: PopoutWindow.qml failed to load; check the shell log for the QML error")
    }

    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: root.label
        tooltipText: root.tooltip
        onPressed: function(buttonCode) {
            if (buttonCode === Qt.LeftButton) root.toggle()
            else if (buttonCode === Qt.RightButton) root.showTab("settings")
            else if (buttonCode === Qt.MiddleButton && root.cfg && root.svc) {
                if (root.cfg.middleClick === "picker") root.svc.openPicker("")
                else if (root.cfg.middleClick === "pause") root.svc.togglePaused()
            }
        }
    }
}
