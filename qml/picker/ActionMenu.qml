import QtQuick
import "../controls"

// What can be done with the selected clip: a short list, with the keys that do the same
// thing without the menu. Up, Down and Enter, or the mouse; Esc closes it.
Rectangle {
    id: menu

    property var ui: null
    property string heading: ""
    property var actions: []        // [{ key, label, keys }]
    property int current: 0

    signal chosen(string key)
    signal dismissed()

    function move(d) {
        if (actions.length === 0) return
        current = (current + d + actions.length) % actions.length
        list.positionViewAtIndex(current, ListView.Contain)
    }
    function pick() { if (current >= 0 && current < actions.length) chosen(actions[current].key) }
    onActionsChanged: current = 0

    width: ui.px(280)
    height: Math.min(ui.px(420), head.height + list.contentHeight + ui.px(16))
    radius: ui.r(2.5)
    color: ui.surface
    border.width: 1
    border.color: ui.accentTint(0.5)

    // shadow-ish edge so it reads above the list
    Rectangle {
        anchors.fill: parent
        anchors.margins: -1
        z: -1
        radius: parent.radius + 1
        color: "transparent"
        border.width: 3
        border.color: Qt.rgba(0, 0, 0, 0.25)
    }

    Txt {
        id: head
        ui: menu.ui
        x: ui.px(12)
        y: ui.px(8)
        width: parent.width - ui.px(24)
        height: ui.px(22)
        text: menu.heading
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
        font.pixelSize: ui.fs(10)
        font.weight: Font.DemiBold
        opacity: 0.55
    }

    ListView {
        id: list
        anchors.top: head.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: ui.px(6)
        anchors.topMargin: ui.px(2)
        model: menu.actions
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        delegate: Rectangle {
            readonly property bool on: index === menu.current
            width: list.width
            height: ui.px(28)
            radius: ui.r(1.5)
            color: on ? ui.accentTint(0.2) : (rowArea.containsMouse ? ui.tint(0.06) : "transparent")
            Txt {
                ui: menu.ui
                anchors.left: parent.left
                anchors.leftMargin: ui.px(10)
                anchors.right: keysText.left
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label
                elide: Text.ElideRight
                color: modelData.danger ? ui.bad : ui.fg
                font.pixelSize: ui.fs(11)
            }
            Txt {
                id: keysText
                ui: menu.ui
                anchors.right: parent.right
                anchors.rightMargin: ui.px(10)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.keys || ""
                font.pixelSize: ui.fs(9)
                opacity: 0.45
            }
            MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: menu.current = index
                onClicked: { menu.current = index; menu.pick() }
            }
        }
    }
}
