import QtQuick
import "../js/Clips.js" as Clips
import "../controls"

// The square at the start of a row: a picture's thumbnail, a color's swatch, or a
// glyph for what the clip is.
Rectangle {
    id: root

    property var ui: null
    property var entry: null
    property bool showThumb: true
    property bool masked: true

    readonly property string kind: entry ? Clips.kindOf(entry) : "text"
    readonly property var color_: kind === "color" ? Clips.colorInfo(entry.text) : null
    // a copied picture file shows itself too
    readonly property string thumb: {
        if (!entry || !showThumb) return ""
        if (entry.kind === "image") return "file://" + entry.path
        if (kind === "files" && entry.thumb === true) {
            const p = Clips.fileUris(entry.text)
            if (p.length === 1) return "file://" + encodeURI(p[0])
        }
        return ""
    }
    readonly property var glyphs: ({ text: "󰦨", link: "󰌹", email: "󰇰", color: "󰏘", number: "󰎠",
                                     files: "󰉋", code: "󰅴", image: "󰋩" })

    radius: ui.r(1.2)
    color: color_ ? color_.hex : ui.tint(0.07)
    border.width: color_ ? 1 : 0
    border.color: ui.tint(0.2)
    clip: true

    Image {
        id: pic
        anchors.fill: parent
        visible: root.thumb !== "" && status === Image.Ready
        source: root.thumb
        sourceSize.width: 128
        sourceSize.height: 128
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
    }

    Txt {
        ui: root.ui
        anchors.centerIn: parent
        visible: !root.color_ && (root.thumb === "" || pic.status !== Image.Ready)
        text: root.entry && root.entry.secret && root.masked ? "󰌋" : (root.glyphs[root.kind] || "󰦨")
        font.pixelSize: Math.round(root.height * 0.5)
        opacity: 0.75
    }
}
