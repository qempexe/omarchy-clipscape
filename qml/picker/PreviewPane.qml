import QtQuick
import QtQuick.Layouts
import "../js/Clips.js" as Clips
import "../controls"

// The whole of the selected clip: all of its text, the picture, the color in three
// notations, the files. While editing, the text in a field you can change.
Rectangle {
    id: pane

    property var ui: null
    property var entry: null
    property bool masked: true
    property bool editing: false
    property real now: Date.now()

    readonly property string kind: entry ? Clips.kindOf(entry) : ""
    readonly property var colorInfo: kind === "color" ? Clips.colorInfo(entry.text) : null
    readonly property var files: kind === "files" ? Clips.fileUris(entry.text) : []
    readonly property bool hidden: entry !== null && entry.secret === true && masked
    property alias editor: edit

    signal editCancelled()
    signal editSaved(string text)

    function startEdit() {
        if (!entry || entry.kind !== "text") return false
        edit.text = entry.text
        editing = true
        Qt.callLater(() => { edit.forceActiveFocus(); edit.cursorPosition = edit.length })
        return true
    }

    radius: ui.r(2.5)
    color: ui.tint(0.03)
    border.width: 1
    border.color: editing ? ui.accentTint(0.6) : ui.tint(0.08)
    clip: true

    function details() {
        const c = entry
        if (!c) return []
        const out = []
        out.push(["Kind", ({ text: "Text", link: "Link", email: "Email", color: "Color", number: "Number", files: "Files", code: "Code", image: "Picture" })[kind] || "Text"])
        if (c.kind === "image") {
            if (c.w > 0) out.push(["Size", c.w + " × " + c.h])
            out.push(["File", Clips.bytesText(c.bytes) + " " + (c.mime || "").replace("image/", "").toUpperCase()])
        } else if (kind !== "files") {
            const lines = c.text.split("\n").length
            const words = c.text.trim() === "" ? 0 : c.text.trim().split(/\s+/).length
            out.push(["Length", c.text.length + " characters · " + words + (words === 1 ? " word" : " words") + (lines > 1 ? " · " + lines + " lines" : "")])
        }
        if (c.app) out.push(["From", c.app])
        out.push(["Copied", Clips.ago(c.at, now)])
        if (c.last > c.at + 1000) out.push(["Last used", Clips.ago(c.last, now)])
        if (c.uses > 1) out.push(["Used", c.uses + " times"])
        return out
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: ui.px(12)
        spacing: ui.px(10)
        visible: pane.entry !== null

        // the clip itself
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: ui.px(60)

            // text
            Flickable {
                id: textFlick
                anchors.fill: parent
                visible: !pane.editing && pane.entry !== null && pane.entry.kind === "text"
                         && pane.kind !== "color" && pane.kind !== "files"
                contentWidth: width
                contentHeight: body.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Txt {
                    id: body
                    ui: pane.ui
                    width: textFlick.width
                    text: !pane.entry || pane.entry.kind !== "text" ? ""
                        : (pane.hidden ? Clips.title(pane.entry, true) + "\n\nHidden, because it looks like a secret. Ctrl+H shows it."
                           : pane.entry.text.slice(0, 20000) + (pane.entry.text.length > 20000 ? "\n…" : ""))
                    wrapMode: Text.Wrap
                    font.pixelSize: ui.fs(pane.kind === "code" ? 11 : 12)
                    lineHeight: 1.15
                    opacity: pane.hidden ? 0.6 : 1
                }
            }

            // editing: a plain text field, no formatting
            Flickable {
                id: editFlick
                anchors.fill: parent
                visible: pane.editing
                contentWidth: width
                contentHeight: Math.max(height, edit.implicitHeight)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                function follow(r) {
                    if (r.y < contentY) contentY = r.y
                    else if (r.y + r.height > contentY + height) contentY = r.y + r.height - height
                }

                TextEdit {
                    id: edit
                    width: editFlick.width
                    textFormat: TextEdit.PlainText
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    persistentSelection: true
                    color: ui.fg
                    selectionColor: ui.accentTint(0.45)
                    selectedTextColor: ui.fg
                    font.family: ui.fontName
                    font.pixelSize: ui.fs(12)
                    onCursorRectangleChanged: editFlick.follow(cursorRectangle)
                    Keys.onPressed: function(e) {
                        if (e.key === Qt.Key_Escape) { pane.editing = false; pane.editCancelled(); e.accepted = true }
                        else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && (e.modifiers & Qt.ControlModifier)) {
                            pane.editing = false
                            pane.editSaved(edit.text)
                            e.accepted = true
                        }
                    }
                }
            }

            // a picture
            Image {
                anchors.fill: parent
                visible: pane.entry !== null && (pane.entry.kind === "image" || pane.files.length === 1 && pane.entry.thumb === true)
                source: !visible ? "" : (pane.entry.kind === "image" ? "file://" + pane.entry.path : "file://" + encodeURI(pane.files[0]))
                sourceSize.width: 1200
                sourceSize.height: 1200
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                mipmap: true
            }

            // a color
            ColumnLayout {
                anchors.fill: parent
                visible: pane.colorInfo !== null
                spacing: ui.px(10)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: ui.r(2)
                    color: pane.colorInfo ? pane.colorInfo.hex : "transparent"
                    opacity: pane.colorInfo ? Math.max(0.15, pane.colorInfo.alpha) : 1
                    border.width: 1
                    border.color: ui.tint(0.2)
                }
                Repeater {
                    model: pane.colorInfo ? [pane.colorInfo.hex, pane.colorInfo.rgb, pane.colorInfo.hsl] : []
                    delegate: Txt {
                        ui: pane.ui
                        text: modelData
                        font.pixelSize: ui.fs(12)
                    }
                }
            }

            // files
            Flickable {
                anchors.fill: parent
                visible: pane.files.length > 1 || (pane.files.length === 1 && pane.entry.thumb !== true)
                contentWidth: width
                contentHeight: fileCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: fileCol
                    width: parent.width
                    spacing: ui.px(6)
                    Repeater {
                        model: pane.files.slice(0, 200)
                        delegate: Row {
                            spacing: ui.px(8)
                            width: fileCol.width
                            Txt { ui: pane.ui; text: "󰉋"; opacity: 0.6; font.pixelSize: ui.fs(12) }
                            Txt {
                                ui: pane.ui
                                width: parent.width - ui.px(24)
                                text: modelData
                                elide: Text.ElideMiddle
                                font.pixelSize: ui.fs(11)
                            }
                        }
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: ui.tint(0.08) }

        // what it is, where it came from, when
        Column {
            Layout.fillWidth: true
            visible: !pane.editing
            spacing: ui.px(3)
            Repeater {
                model: pane.details()
                delegate: Row {
                    spacing: ui.px(10)
                    Txt { ui: pane.ui; width: ui.px(70); text: modelData[0]; opacity: 0.45; font.pixelSize: ui.fs(10) }
                    Txt { ui: pane.ui; text: modelData[1]; opacity: 0.8; font.pixelSize: ui.fs(10) }
                }
            }
        }
        Txt {
            ui: pane.ui
            Layout.fillWidth: true
            visible: pane.editing
            text: "Ctrl+Enter keeps it as a new clip and puts it on the clipboard · Esc cancels"
            wrapMode: Text.Wrap
            font.pixelSize: ui.fs(10)
            opacity: 0.55
        }
    }

    Txt {
        ui: pane.ui
        anchors.centerIn: parent
        visible: pane.entry === null
        text: "Nothing selected"
        opacity: 0.4
    }
}
