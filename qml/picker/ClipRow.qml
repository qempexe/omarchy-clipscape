import QtQuick
import "../js/Clips.js" as Clips
import "../controls"

// One clip in the list: its icon or thumbnail, one line of it, and (Two lines) what it
// is, its size, the app and when. Pinned, marked and Alt+number show on the right.
Rectangle {
    id: row

    property var ui: null
    property var entry: null
    property int number: 0          // 1 to 9 shows Alt+n, 0 shows nothing
    property bool selected: false
    property bool marked: false
    property int markIndex: 0
    property bool detailed: true
    property bool showApp: true
    property bool masked: true
    property real now: Date.now()

    signal picked()
    signal hovered(point at)
    signal menu()

    readonly property bool hot: area.containsMouse

    height: detailed ? ui.px(50) : ui.px(34)
    radius: ui.r(2)
    color: selected ? ui.accentTint(0.16) : ui.cardFill(hot)
    border.width: selected ? 1 : ui.cardBorder
    border.color: selected ? ui.accentTint(0.55) : ui.tint(0.12)

    KindIcon {
        id: icon
        ui: row.ui
        entry: row.entry
        masked: row.masked
        anchors.left: parent.left
        anchors.leftMargin: ui.px(8)
        anchors.verticalCenter: parent.verticalCenter
        width: row.detailed ? ui.px(34) : ui.px(22)
        height: width
    }

    Column {
        anchors.left: icon.right
        anchors.leftMargin: ui.px(10)
        anchors.right: side.left
        anchors.rightMargin: ui.px(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: ui.px(2)

        Txt {
            ui: row.ui
            width: parent.width
            text: row.entry ? Clips.title(row.entry, row.masked) : ""
            elide: Text.ElideRight
            maximumLineCount: 1
            font.pixelSize: ui.fs(12)
            font.weight: row.entry && row.entry.label ? Font.DemiBold : Font.Normal
            opacity: row.entry && row.entry.secret && row.masked ? 0.7 : 1
        }
        Txt {
            ui: row.ui
            visible: row.detailed
            width: parent.width
            text: row.entry ? Clips.meta(row.entry, row.now, row.showApp) : ""
            elide: Text.ElideRight
            font.pixelSize: ui.fs(10)
            opacity: 0.5
        }
    }

    Row {
        id: side
        anchors.right: parent.right
        anchors.rightMargin: ui.px(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: ui.px(6)

        Txt {   // pinned
            ui: row.ui
            visible: row.entry !== null && row.entry.pinned
            anchors.verticalCenter: parent.verticalCenter
            text: "󰐃"
            color: ui.accent
            font.pixelSize: ui.fs(13)
        }
        Rectangle {   // marked, with its place in the order
            visible: row.marked
            anchors.verticalCenter: parent.verticalCenter
            width: ui.px(18); height: width
            radius: width / 2
            color: ui.accent
            Txt {
                ui: row.ui
                anchors.centerIn: parent
                text: String(row.markIndex)
                color: ui.accentText
                font.pixelSize: ui.fs(10)
                font.weight: Font.DemiBold
            }
        }
        Rectangle {   // Alt+n
            visible: row.number > 0 && !row.marked
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: nLabel.implicitWidth + ui.px(10)
            implicitHeight: ui.px(18)
            radius: ui.r(1)
            color: ui.tint(row.selected ? 0.14 : 0.07)
            Txt {
                id: nLabel
                ui: row.ui
                anchors.centerIn: parent
                text: "Alt " + row.number
                font.pixelSize: ui.fs(9)
                opacity: 0.6
            }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onPositionChanged: function(m) { row.hovered(area.mapToGlobal(m.x, m.y)) }
        onClicked: function(m) {
            if (m.button === Qt.RightButton) row.menu()
            else row.picked()
        }
    }
}
