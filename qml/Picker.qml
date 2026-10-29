import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "picker"
import "controls"

// The picker: Super+Ctrl+V. Clipscape stands in for Omarchy's own clipboard plugin
// (clonedFrom in the manifest), so that key, and Clipboard in the Omarchy menu, open it.
//
// open(payload) is called by the shell; the payload may hold { "query": "...", "filter": "..." }.
Item {
    id: root

    property string omarchyPath: ""
    property var shell: null
    property var manifest: null
    property var service: null

    readonly property string pluginId: "io.github.qempexe.clipscape"
    readonly property var svc: service !== null ? service : lookedUp
    property var lookedUp: null
    readonly property var ui: svc ? svc.ui : null
    readonly property var cfg: svc ? svc.cfg : null

    property bool opened: false
    property var targetScreen: null
    // 0 = shown, 1 = gone
    property real t: 1
    readonly property bool shown: opened || t < 1

    // the service and the picker load in whatever order
    function lookUp() {
        if (root.service !== null || root.lookedUp !== null) return
        if (root.shell && typeof root.shell.serviceFor === "function") root.lookedUp = root.shell.serviceFor(root.pluginId)
    }
    onShellChanged: lookUp()
    Timer {
        interval: 400
        repeat: true
        running: root.svc === null && root.shell !== null
        onTriggered: root.lookUp()
    }

    function open(payload) {
        if (!root.svc) { root.lookUp(); if (!root.svc) return }
        let p = {}
        try { p = JSON.parse(String(payload || "{}")) } catch (e) { p = {} }
        if (root.opened) {
            view.forceActiveFocus()
            return
        }
        // the bar panel gives up the keyboard first
        root.ui.closeRequested()
        root.targetScreen = pickScreen()
        root.opened = true
        if (p && typeof p.query === "string") view.setQuery(p.query)
        if (p && typeof p.filter === "string" && ["all", "pinned", "text", "link", "image", "files", "color", "code"].indexOf(p.filter) >= 0)
            view.setFilter(p.filter)
        if (root.cfg.openAt === "mouse") cursorProc.running = true
        else place(-1, -1)
        anim.from = root.t
        anim.to = 0
        anim.restart()
        Qt.callLater(() => view.forceActiveFocus())
    }

    function close() {
        if (!root.opened) return
        root.opened = false
        anim.from = root.t
        anim.to = 1
        anim.restart()
    }
    function toggle() { if (root.opened) dismiss(); else open("") }

    // close, and tell the shell, so its idea of "open" matches ours
    function dismiss() {
        root.close()
        if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    }

    function pickScreen() {
        let name = ""
        try { name = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name) : "" } catch (e) { name = "" }
        let list = []
        try { list = Quickshell.screens } catch (e2) { list = [] }
        for (let i = 0; i < list.length; i++) if (list[i] && list[i].name === name) return list[i]
        return null
    }

    // where the card goes: the middle, or centered on the mouse and kept on screen
    property real cardX: 0
    property real cardY: 0
    function place(mx, my) {
        const w = card.width, h = card.height
        if (mx < 0) {
            cardX = Math.round((win.width - w) / 2)
            cardY = Math.round((win.height - h) / 2)
        } else {
            cardX = Math.round(Math.max(16, Math.min(win.width - w - 16, mx - w / 2)))
            cardY = Math.round(Math.max(16, Math.min(win.height - h - 16, my - h / 3)))
        }
    }
    Process {
        id: cursorProc
        command: ["hyprctl", "-j", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                let c = null
                try { c = JSON.parse(String(text || "")) } catch (e) { c = null }
                const sx = win.screen && win.screen.x !== undefined ? win.screen.x : 0
                const sy = win.screen && win.screen.y !== undefined ? win.screen.y : 0
                if (c && typeof c.x === "number" && typeof c.y === "number") root.place(c.x - sx, c.y - sy)
                else root.place(-1, -1)
            }
        }
    }

    NumberAnimation {
        id: anim
        target: root
        property: "t"
        duration: 120
        easing.type: Easing.OutCubic
    }

    // no input while it fades away, so the fade never eats a click
    Region { id: noInput }

    PanelWindow {
        id: win

        visible: root.shown
        screen: root.targetScreen
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "clipscape"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        mask: root.opened ? null : noInput

        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: (1 - root.t) * (root.cfg ? root.cfg.dim / 100 : 0.3)
        }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: root.dismiss()
        }

        Item {
            id: card
            visible: root.ui !== null
            x: root.cardX
            y: root.cardY + Math.round(root.t * 12)
            width: Math.min(win.width - 32, root.cfg ? root.cfg.pickerWidth : 860)
            height: Math.min(win.height - 32, root.cfg ? root.cfg.pickerHeight : 560)
            opacity: 1 - root.t
            scale: 1 - root.t * 0.03
            onWidthChanged: if (root.opened && root.cfg.openAt !== "mouse") root.place(-1, -1)
            onHeightChanged: if (root.opened && root.cfg.openAt !== "mouse") root.place(-1, -1)

            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }   // clicks on the card stay here

            Frame { anchors.fill: parent; ui: root.ui }

            ClipView {
                id: view
                anchors.fill: parent
                anchors.margins: root.ui ? root.ui.px(14) : 14
                anchors.bottomMargin: root.ui ? root.ui.px(34) : 34
                svc: root.svc
                active: root.opened
                onDone: root.dismiss()
            }

            Txt {
                ui: root.ui
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: root.ui ? root.ui.px(16) : 16
                anchors.rightMargin: root.ui ? root.ui.px(16) : 16
                height: root.ui ? root.ui.px(30) : 30
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                text: view.hints
                font.pixelSize: root.ui ? root.ui.fs(10) : 10
                opacity: 0.45
            }
        }
    }
}
