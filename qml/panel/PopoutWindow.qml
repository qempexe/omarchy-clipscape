import QtQuick
import Quickshell

// panel as a normal window. title is "Clipscape" so you can add window rules
FloatingWindow {
    id: win

    property var svc: null
    readonly property var ui: svc ? svc.ui : null

    title: "Clipscape"
    visible: false
    color: "transparent"
    implicitWidth: ui ? ui.cfgSafe.windowWidth : 600
    implicitHeight: ui ? ui.cfgSafe.windowHeight : 680

    Loader {
        anchors.fill: parent
        active: win.svc !== null
        sourceComponent: Component { PanelView { svc: win.svc; shown: win.visible; focus: true } }
    }
}
