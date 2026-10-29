import QtQuick

// The little picture on a settings tile, picked by setting and option. Sizes are fixed
// on purpose: the Spacing tile must not change shape because Spacing changed.
Item {
    id: root

    property var ui: null
    property string key: ""
    property string opt: ""
    property bool on: false

    width: 64
    height: 34

    readonly property color ink: on ? ui.accent : ui.tint(0.55)
    readonly property color soft: on ? ui.accentTint(0.40) : ui.tint(0.20)

    // row style
    Column {
        visible: root.key === "cardStyle"
        anchors.centerIn: parent
        spacing: 3
        Repeater {
            model: 2
            Rectangle {
                width: 44; height: 11; radius: 3
                color: root.opt === "soft" ? root.soft : "transparent"
                border.width: root.opt === "outline" ? 1.5 : 0
                border.color: root.ink
                Rectangle { x: 4; anchors.verticalCenter: parent.verticalCenter; width: 18; height: 3; radius: 1.5; color: root.ink }
            }
        }
    }

    // spacing
    Column {
        visible: root.key === "density"
        anchors.centerIn: parent
        spacing: root.opt === "compact" ? 1 : (root.opt === "spacious" ? 6 : 3)
        Repeater { model: 3; Rectangle { width: 40; height: 5; radius: 2; color: root.ink } }
    }

    // open as
    Item {
        visible: root.key === "openAs"
        anchors.fill: parent
        Rectangle { x: 6; y: 3; width: 52; height: 5; radius: 2; color: root.soft }
        Rectangle {
            x: root.opt === "panel" ? 10 : 18
            y: root.opt === "panel" ? 9 : 12
            width: 28; height: 20; radius: 3
            color: root.ink
        }
    }

    // where the picker opens
    Item {
        visible: root.key === "openAt"
        anchors.fill: parent
        Rectangle { anchors.fill: parent; anchors.margins: 2; radius: 4; color: "transparent"; border.width: 1; border.color: root.soft }
        Rectangle {
            width: 24; height: 14; radius: 2
            x: root.opt === "center" ? (parent.width - width) / 2 : 30
            y: root.opt === "center" ? (parent.height - height) / 2 : 13
            color: root.ink
        }
        Text {   // the pointer
            visible: root.opt === "mouse"
            x: 26; y: 6
            text: "➤"
            rotation: -110
            color: root.ink
            font.pixelSize: 10
        }
    }

    // Enter and click
    Row {
        visible: root.key === "enterAction"
        anchors.centerIn: parent
        spacing: 6
        Rectangle { width: 18; height: 22; radius: 3; color: root.soft; anchors.verticalCenter: parent.verticalCenter }
        Text { anchors.verticalCenter: parent.verticalCenter; text: root.opt === "paste" ? "→" : "⧉"; color: root.ink; font.pixelSize: 13 }
        Rectangle {
            width: 22; height: 18; radius: 3
            anchors.verticalCenter: parent.verticalCenter
            color: "transparent"
            border.width: 1.5
            border.color: root.ink
            Rectangle { visible: root.opt === "paste"; x: 4; y: 7; width: 12; height: 3; radius: 1.5; color: root.ink }
        }
    }

    // secrets
    Item {
        visible: root.key === "secrets"
        anchors.fill: parent
        Rectangle {
            anchors.centerIn: parent
            width: 46; height: 14; radius: 3
            color: root.soft
            opacity: root.opt === "skip" ? 0.35 : 1
            border.width: root.opt === "skip" ? 1 : 0
            border.color: root.ink
            Text {
                anchors.centerIn: parent
                text: root.opt === "mask" ? "••••••" : (root.opt === "keep" ? "aB3$9x" : "")
                color: root.ink
                font.pixelSize: 9
                font.bold: true
            }
        }
        Rectangle {   // struck out: not kept
            visible: root.opt === "skip"
            anchors.centerIn: parent
            width: 52; height: 1.5
            rotation: -18
            color: root.ink
        }
    }

    // rows
    Column {
        visible: root.key === "rows"
        anchors.centerIn: parent
        spacing: root.opt === "detailed" ? 4 : 3
        Repeater {
            model: root.opt === "detailed" ? 2 : 3
            Row {
                spacing: 3
                Rectangle { width: root.opt === "detailed" ? 10 : 6; height: width; radius: 2; color: root.ink }
                Column {
                    spacing: 2
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle { width: 30; height: 3; radius: 1.5; color: root.ink }
                    Rectangle { visible: root.opt === "detailed"; width: 20; height: 2; radius: 1; color: root.soft }
                }
            }
        }
    }
}
