import QtQuick
import QtQuick.Layouts
import "../js/Clips.js" as Clips
import "../controls"

// The history, searchable, with the selected clip beside it (or under it when there is
// no room). The same view is the picker (Super+Ctrl+V) and the panel's Clips tab.
//
// Everything is done from the keyboard; typing goes to the search. done() asks the host
// to close: after a paste or a copy, or on Esc.
Item {
    id: view

    property var svc: null
    property bool active: false          // on screen right now
    property bool inPanel: false
    readonly property var ui: svc ? svc.ui : null
    readonly property var store: svc ? svc.clips : null
    readonly property var cfg: svc ? svc.cfg : null

    signal done()

    // ---- what is showing -----------------------------------------------------------
    property string query: ""
    property string filter: "all"
    property string selectedId: ""
    property var marks: []               // ids, in the order they were marked
    property bool revealed: false        // Ctrl+H: secrets shown while this stays open
    property bool menuOpen: false
    property bool transforms: false      // the menu shows the transforms
    property bool confirmClear: false
    property bool renaming: false
    property real now: Date.now()

    readonly property var rows: {
        const rev = store ? store.revision : 0
        return store ? Clips.search(store.clips, query, filter, cfg.pinnedFirst, revealed) : []
    }
    readonly property var counts: {
        const rev = store ? store.revision : 0
        return store ? Clips.counts(store.clips) : ({})
    }
    readonly property int selected: {
        if (rows.length === 0) return -1
        for (let i = 0; i < rows.length; i++) if (rows[i].id === selectedId) return i
        return 0
    }
    readonly property var current: selected >= 0 ? rows[selected] : null
    readonly property bool masked: !revealed

    // a fresh start every time it opens
    function reset() {
        query = ""
        const start = cfg ? cfg.startFilter : "all"
        filter = start === "last" ? svc.lastFilter : (start === "pinned" ? "pinned" : "all")
        marks = []
        menuOpen = false
        transforms = false
        confirmClear = false
        renaming = false
        revealed = false
        preview.editing = false
        now = Date.now()
        selectedId = rows.length > 0 ? rows[0].id : ""
        list.positionViewAtBeginning()
    }
    onActiveChanged: if (active) { reset(); Qt.callLater(() => view.forceActiveFocus()) }
    Timer { interval: 30000; repeat: true; running: view.active; onTriggered: view.now = Date.now() }

    // the newest copy is selected while nothing else was picked
    Connections {
        target: view.store
        ignoreUnknownSignals: true
        function onCaptured(c) { if (view.query === "" && !view.menuOpen) view.selectedId = c.id }
    }

    function select(i) {
        if (rows.length === 0) return
        const j = Math.max(0, Math.min(rows.length - 1, i))
        selectedId = rows[j].id
        list.positionViewAtIndex(j, ListView.Contain)
    }
    function step(d) { if (rows.length > 0) select(selected < 0 ? 0 : selected + d) }

    // a row is selected by the mouse only when the mouse itself moved, so a list
    // scrolling under a resting pointer never takes the keyboard's selection away
    property point lastPointer: Qt.point(-1, -1)
    function hover(i, at) {
        if (lastPointer.x < 0) { lastPointer = at; return }
        if (Math.abs(at.x - lastPointer.x) < 1 && Math.abs(at.y - lastPointer.y) < 1) return
        lastPointer = at
        if (!menuOpen && !preview.editing && i >= 0 && i < rows.length) selectedId = rows[i].id
    }

    function setQuery(q) {
        query = q.slice(0, 200)
        selectedId = rows.length > 0 ? rows[0].id : ""
        list.positionViewAtBeginning()
    }
    function setFilter(f) {
        filter = f
        svc.rememberFilter(f)
        selectedId = rows.length > 0 ? rows[0].id : ""
        list.positionViewAtBeginning()
    }
    function stepFilter(d) {
        const keys = Clips.FILTER_KEYS
        setFilter(keys[(keys.indexOf(filter) + d + keys.length) % keys.length])
    }

    function toggleMark(id) {
        const i = marks.indexOf(id)
        marks = i >= 0 ? marks.filter(x => x !== id) : marks.concat([id])
    }

    // ---- doing things -----------------------------------------------------------------
    function primaryHow(shift) {
        const paste = cfg.enterAction === "paste"
        return (paste !== shift) ? "paste" : "copy"
    }

    function use(how) {
        if (marks.length > 0) {
            if (!store.useMany(marks.filter(id => store.byId(id) !== null), how)) return
        } else if (current) {
            if (!store.use(current.id, how)) return
        } else {
            return
        }
        done()
    }

    function useRow(i, how) {
        if (i < 0 || i >= rows.length) return
        selectedId = rows[i].id
        if (store.use(rows[i].id, how)) done()
    }

    function removeSelected() {
        const ids = marks.length > 0 ? marks.slice() : (current ? [current.id] : [])
        if (ids.length === 0) return
        const next = selected
        store.remove(ids)
        marks = []
        select(Math.min(next, rows.length - 1))
    }

    function togglePin() {
        if (!current) return
        store.setPinned(current.id, !current.pinned)
    }

    function openSelected() {
        if (!current || current.kind !== "text") return
        const k = Clips.kindOf(current)
        if (k === "link") {
            const u = current.text.trim()
            if (svc.openUrl(/^www\./i.test(u) ? "https://" + u : u)) done()
        } else if (k === "files") {
            const p = Clips.fileUris(current.text)
            if (p.length > 0 && svc.showFolder(p[0])) done()
        }
    }

    function startEdit() { if (current && current.kind === "text" && !(current.secret && masked)) preview.startEdit() }
    function saveEdit(text) {
        const id = store.addText(text)
        if (id !== "") { selectedId = id; store.use(id, "copy") }
        view.forceActiveFocus()
    }

    function startRename() {
        if (!current || !current.pinned) return
        renameBox.text = current.label
        renaming = true
        Qt.callLater(() => renameBox.forceActiveFocus())
    }
    function finishRename(keep) {
        if (!renaming) return
        renaming = false
        if (keep && current) store.rename(current.id, renameBox.text)
        view.forceActiveFocus()
    }

    function applyTransform(key) {
        if (!current || current.kind !== "text") return
        const out = Clips.transform(key, current.text)
        if (out === null) return
        const id = store.addText(out)
        if (id !== "") selectedId = id
    }

    // the actions menu for the selected clip
    readonly property var menuActions: {
        const c = current
        if (!c) return []
        if (transforms) {
            return [{ key: "back", label: "‹ Back", keys: "←" }]
                .concat(Clips.TRANSFORMS.filter(t => Clips.transform(t.key, c.text) !== null)
                    .map(t => ({ key: "t:" + t.key, label: t.label, keys: "" })))
        }
        const k = Clips.kindOf(c)
        const out = [
            { key: "paste", label: marks.length > 1 ? "Paste the " + marks.length + " marked" : "Paste", keys: cfg.enterAction === "paste" ? "Enter" : "Shift+Enter" },
            { key: "copy", label: "Copy", keys: cfg.enterAction === "paste" ? "Shift+Enter" : "Enter" }
        ]
        if (c.kind === "text") out.push({ key: "type", label: "Type it out", keys: "Ctrl+T" })
        out.push({ key: "pin", label: c.pinned ? "Unpin" : "Pin", keys: "Ctrl+P" })
        if (c.pinned) {
            out.push({ key: "rename", label: c.label ? "Rename" : "Give it a name", keys: "Ctrl+R" })
            out.push({ key: "up", label: "Move up", keys: "Ctrl+↑" }, { key: "down", label: "Move down", keys: "Ctrl+↓" })
        }
        out.push({ key: "mark", label: marks.indexOf(c.id) >= 0 ? "Unmark" : "Mark", keys: "Ctrl+Space" })
        if (c.kind === "text" && k !== "files") {
            out.push({ key: "edit", label: "Edit", keys: "Ctrl+E" })
            out.push({ key: "transforms", label: "Transform ›", keys: "→" })
        }
        if (k === "link") out.push({ key: "open", label: "Open the link", keys: "Alt+Enter" })
        if (k === "files") out.push({ key: "open", label: "Show the folder", keys: "Alt+Enter" })
        if (c.secret) out.push({ key: "reveal", label: masked ? "Show secrets" : "Hide secrets", keys: "Ctrl+H" })
        out.push({ key: "delete", label: marks.length > 1 ? "Delete the " + marks.length + " marked" : "Delete", keys: "Del", danger: true })
        return out
    }

    function openMenu() {
        if (!current) return
        transforms = false
        menuOpen = true
    }
    function runAction(key) {
        if (key === "transforms") { transforms = true; return }
        if (key === "back") { transforms = false; return }
        menuOpen = false
        transforms = false
        if (key.indexOf("t:") === 0) { applyTransform(key.slice(2)); return }
        if (key === "paste") use("paste")
        else if (key === "copy") use("copy")
        else if (key === "type") use("type")
        else if (key === "pin") togglePin()
        else if (key === "rename") startRename()
        else if (key === "up" && current) store.movePin(current.id, -1)
        else if (key === "down" && current) store.movePin(current.id, 1)
        else if (key === "mark" && current) toggleMark(current.id)
        else if (key === "edit") startEdit()
        else if (key === "open") openSelected()
        else if (key === "reveal") revealed = !revealed
        else if (key === "delete") removeSelected()
    }

    // ---- the keyboard ------------------------------------------------------------------
    focus: true
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(e) {
        if (preview.editing || renaming) return
        const ctrl = (e.modifiers & Qt.ControlModifier) !== 0
        const shift = (e.modifiers & Qt.ShiftModifier) !== 0
        const alt = (e.modifiers & Qt.AltModifier) !== 0
        const k = e.key
        e.accepted = true

        if (confirmClear) {
            if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Y) { confirmClear = false; store.clearUnpinned(); marks = [] }
            else if (k === Qt.Key_Escape || k === Qt.Key_N) confirmClear = false
            return
        }
        if (menuOpen) {
            if (k === Qt.Key_Escape) { if (transforms) transforms = false; else menuOpen = false }
            else if (k === Qt.Key_Up) actionMenu.move(-1)
            else if (k === Qt.Key_Down) actionMenu.move(1)
            else if (k === Qt.Key_Left && transforms) transforms = false
            else if (k === Qt.Key_Right && !transforms && menuActions.some(a => a.key === "transforms")) transforms = true
            else if (k === Qt.Key_Return || k === Qt.Key_Enter) actionMenu.pick()
            else if ((k === Qt.Key_K && ctrl) || k === Qt.Key_Menu) menuOpen = false
            return
        }

        if (k === Qt.Key_Escape) {
            if (marks.length > 0) marks = []
            else if (query !== "") setQuery("")
            else done()
        } else if (k === Qt.Key_Up && ctrl) { if (current && current.pinned) store.movePin(current.id, -1) }
        else if (k === Qt.Key_Down && ctrl) { if (current && current.pinned) store.movePin(current.id, 1) }
        else if (k === Qt.Key_Up) step(-1)
        else if (k === Qt.Key_Down) step(1)
        else if (k === Qt.Key_PageUp) step(-8)
        else if (k === Qt.Key_PageDown) step(8)
        else if (k === Qt.Key_Home && (ctrl || query === "")) select(0)
        else if (k === Qt.Key_End && (ctrl || query === "")) select(rows.length - 1)
        else if (k === Qt.Key_Tab) stepFilter(1)
        else if (k === Qt.Key_Backtab) stepFilter(-1)
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            if (alt) openSelected()
            else use(primaryHow(shift))
        }
        else if (k === Qt.Key_Delete) { if (shift) { if (store.clips.length > store.pinnedCount) confirmClear = true } else removeSelected() }
        else if (k === Qt.Key_Menu || (ctrl && k === Qt.Key_K)) openMenu()
        else if (ctrl && k === Qt.Key_Space) { if (current) toggleMark(current.id) }
        else if (ctrl && k === Qt.Key_P) togglePin()
        else if (ctrl && k === Qt.Key_E) startEdit()
        else if (ctrl && k === Qt.Key_R) startRename()
        else if (ctrl && k === Qt.Key_T) use("type")
        else if (ctrl && k === Qt.Key_H) revealed = !revealed
        else if (ctrl && (k === Qt.Key_U || (k === Qt.Key_Backspace && query === ""))) setQuery("")
        else if (ctrl && k === Qt.Key_Backspace) setQuery(query.replace(/\S*\s*$/, ""))
        else if (alt && k >= Qt.Key_1 && k <= Qt.Key_9) { if (cfg.numbers) useRow(k - Qt.Key_1, primaryHow(shift)) }
        else if (k === Qt.Key_Backspace) setQuery(query.slice(0, -1))
        else if (!ctrl && !alt && e.text.length === 1 && e.text.charCodeAt(0) >= 32 && e.text.charCodeAt(0) !== 127) setQuery(query + e.text)
        else e.accepted = false
    }

    // ---- what it looks like ---------------------------------------------------------------
    readonly property bool wide: width >= ui.px(640)
    readonly property bool showPreview: cfg ? cfg.preview : true

    ColumnLayout {
        anchors.fill: parent
        spacing: ui.px(10)

        // search
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: ui.px(34)
            radius: ui.r(2)
            color: ui.tint(0.05)
            border.width: 1
            border.color: view.query !== "" ? ui.accentTint(0.5) : ui.tint(0.08)

            Txt { id: lens; ui: view.ui; anchors.left: parent.left; anchors.leftMargin: ui.px(12); anchors.verticalCenter: parent.verticalCenter; text: "󰍉"; opacity: 0.55; font.pixelSize: ui.fs(14) }
            Txt {
                id: queryText
                ui: view.ui
                anchors.left: lens.right
                anchors.leftMargin: ui.px(8)
                anchors.right: status.left
                anchors.rightMargin: ui.px(8)
                anchors.verticalCenter: parent.verticalCenter
                text: view.query !== "" ? view.query
                    : (view.wide ? "Type to search · is:pinned  type:link  app:firefox" : "Type to search")
                opacity: view.query !== "" ? 1 : 0.4
                elide: view.query !== "" ? Text.ElideLeft : Text.ElideRight
                font.pixelSize: ui.fs(13)
            }
            Rectangle {   // the caret, after what was typed
                visible: view.active && view.query !== "" && !preview.editing
                x: queryText.x + Math.min(queryText.width, queryText.contentWidth) + 1
                anchors.verticalCenter: parent.verticalCenter
                width: 1.5
                height: ui.fs(13) + 4
                color: ui.fg
            }
            Row {
                id: status
                anchors.right: parent.right
                anchors.rightMargin: ui.px(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: ui.px(8)
                Txt {
                    ui: view.ui
                    anchors.verticalCenter: parent.verticalCenter
                    visible: view.marks.length > 0
                    text: view.marks.length + " marked"
                    color: ui.accent
                    font.pixelSize: ui.fs(10)
                    font.weight: Font.DemiBold
                }
                Txt {
                    ui: view.ui
                    anchors.verticalCenter: parent.verticalCenter
                    text: view.rows.length + (view.rows.length === 1 ? " clip" : " clips")
                    opacity: 0.45
                    font.pixelSize: ui.fs(10)
                }
                Rectangle {   // recording or paused; click to switch
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: recText.implicitWidth + ui.px(14)
                    implicitHeight: ui.px(20)
                    radius: ui.r(1)
                    color: view.svc && view.svc.paused ? Qt.rgba(ui.warn.r, ui.warn.g, ui.warn.b, 0.18) : ui.tint(recArea.containsMouse ? 0.10 : 0.05)
                    border.width: 1
                    border.color: view.svc && view.svc.paused ? ui.warn : ui.tint(0.1)
                    Txt {
                        id: recText
                        ui: view.ui
                        anchors.centerIn: parent
                        text: view.svc && view.svc.paused ? "󰏤 Paused" : "Recording"
                        color: view.svc && view.svc.paused ? ui.warn : ui.fg
                        opacity: view.svc && view.svc.paused ? 1 : 0.6
                        font.pixelSize: ui.fs(9)
                    }
                    MouseArea { id: recArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: view.svc.togglePaused() }
                }
            }
        }

        // filters
        Flickable {
            Layout.fillWidth: true
            implicitHeight: ui.px(26)
            contentWidth: chips.implicitWidth
            contentHeight: height
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            Row {
                id: chips
                spacing: ui.px(6)
                Repeater {
                    model: Clips.FILTERS
                    delegate: Chip {
                        ui: view.ui
                        readonly property int n: view.counts[modelData.key] || 0
                        visible: n > 0 || modelData.key === "all" || modelData.key === "pinned" || view.filter === modelData.key
                        label: modelData.label + (n > 0 && modelData.key !== "all" ? "  " + n : "")
                        on: view.filter === modelData.key
                        onClicked: { view.setFilter(modelData.key); view.forceActiveFocus() }
                    }
                }
            }
        }

        // the list and the preview
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: view.wide ? 2 : 1
            columnSpacing: ui.px(12)
            rowSpacing: ui.px(10)

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: view.wide && view.showPreview ? view.width * 0.5 : view.width

                ListView {
                    id: list
                    anchors.fill: parent
                    model: view.rows.length
                    clip: true
                    spacing: ui.px(4)
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: 400
                    delegate: ClipRow {
                        ui: view.ui
                        width: list.width
                        entry: view.rows[index] || null
                        number: view.cfg.numbers && index < 9 ? index + 1 : 0
                        selected: index === view.selected
                        marked: entry !== null && view.marks.indexOf(entry.id) >= 0
                        markIndex: entry !== null ? view.marks.indexOf(entry.id) + 1 : 0
                        detailed: view.cfg.rows === "detailed"
                        showApp: view.cfg.showApp
                        masked: view.masked
                        now: view.now
                        onHovered: function(at) { view.hover(index, at) }
                        onPicked: { view.forceActiveFocus(); view.useRow(index, view.primaryHow(false)) }
                        onMenu: { view.selectedId = entry.id; view.openMenu(); view.forceActiveFocus() }
                    }
                }

                // nothing to show
                Column {
                    anchors.centerIn: parent
                    width: parent.width - ui.px(40)
                    visible: view.rows.length === 0
                    spacing: ui.px(8)
                    Txt {
                        ui: view.ui
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "󰅌"
                        opacity: 0.35
                        font.pixelSize: ui.fs(30)
                    }
                    Txt {
                        ui: view.ui
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        opacity: 0.6
                        text: !view.store || !view.store.ready ? "Reading the history…"
                            : view.store.clips.length === 0
                              ? (view.svc.paused ? "Recording is paused. Click Paused to start again." : "Nothing copied yet. Copy something and it shows up here.")
                              : (view.query !== "" ? "Nothing matches “" + view.query + "”." : "Nothing here in " + (Clips.FILTERS.find(f => f.key === view.filter) || { label: "this filter" }).label + ".")
                    }
                }
            }

            PreviewPane {
                id: preview
                ui: view.ui
                visible: view.showPreview
                Layout.fillWidth: true
                // beside the list when there is room, else a smaller pane under it
                Layout.fillHeight: view.wide
                Layout.preferredWidth: view.wide ? view.width * 0.5 : view.width
                Layout.preferredHeight: view.wide ? -1 : Math.max(ui.px(130), view.height * 0.36)
                entry: view.current
                masked: view.masked
                now: view.now
                onEditCancelled: view.forceActiveFocus()
                onEditSaved: function(text) { view.saveEdit(text) }
            }
        }
    }

    // renaming a pinned clip: a field over the top of the preview
    Rectangle {
        visible: view.renaming
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(parent.width - ui.px(40), ui.px(360))
        height: ui.px(84)
        radius: ui.r(2.5)
        color: ui.surface
        border.width: 1
        border.color: ui.accentTint(0.6)
        z: 20
        Column {
            anchors.fill: parent
            anchors.margins: ui.px(12)
            spacing: ui.px(8)
            Txt { ui: view.ui; text: "A name for this pinned clip (Enter keeps it, Esc cancels)"; font.pixelSize: ui.fs(10); opacity: 0.6; width: parent.width; elide: Text.ElideRight }
            Rectangle {
                width: parent.width
                height: ui.px(28)
                radius: ui.r(1.5)
                color: ui.tint(0.06)
                TextBox {
                    id: renameBox
                    ui: view.ui
                    anchors.fill: parent
                    anchors.leftMargin: ui.px(8)
                    anchors.rightMargin: ui.px(8)
                    maximumLength: 60
                    onEditingFinished: view.finishRename(true)
                    Keys.onEscapePressed: function(e) { view.finishRename(false); e.accepted = true }
                }
            }
        }
    }

    // clearing the history: asked once more
    Rectangle {
        visible: view.confirmClear
        anchors.centerIn: parent
        width: Math.min(parent.width - ui.px(40), ui.px(380))
        height: ui.px(110)
        radius: ui.r(2.5)
        color: ui.surface
        border.width: 1
        border.color: ui.bad
        z: 20
        Column {
            anchors.centerIn: parent
            spacing: ui.px(12)
            Txt {
                ui: view.ui
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Clear the history? Pinned clips stay."
                font.pixelSize: ui.fs(12)
                font.weight: Font.DemiBold
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: ui.px(8)
                Btn { ui: view.ui; text: "Cancel (Esc)"; onClicked: { view.confirmClear = false; view.forceActiveFocus() } }
                Btn { ui: view.ui; kind: "danger"; text: "Clear (Enter)"; onClicked: { view.confirmClear = false; view.store.clearUnpinned(); view.marks = []; view.forceActiveFocus() } }
            }
        }
    }

    // a click outside the menu closes it
    MouseArea {
        anchors.fill: parent
        visible: view.menuOpen
        z: 29
        onClicked: view.menuOpen = false
    }
    ActionMenu {
        id: actionMenu
        ui: view.ui
        visible: view.menuOpen
        z: 30
        anchors.centerIn: parent
        heading: view.current ? (view.transforms ? "Transform into a new clip" : Clips.title(view.current, view.masked)) : ""
        actions: view.menuActions
        onChosen: function(key) { view.runAction(key); view.forceActiveFocus() }
    }

    // the keys, at the bottom of the picker (the panel has them in its footer)
    readonly property string hints: preview.editing ? "Ctrl+Enter keep the edit · Esc cancel"
        : (cfg && cfg.enterAction === "paste" ? "Enter paste · Shift+Enter copy" : "Enter copy · Shift+Enter paste")
          + " · Ctrl+K actions · Ctrl+P pin · Ctrl+Space mark · Tab filter · Del delete"
    readonly property string shortHints: preview.editing ? "Ctrl+Enter keep · Esc cancel"
        : (cfg && cfg.enterAction === "paste" ? "Enter paste" : "Enter copy") + " · Ctrl+K actions · Ctrl+P pin · Tab filter"
}
