import QtQuick

// A window's background and edge: the panel, the pop-out window and the picker all
// wear the same one. The edge is a plain neutral line, one color when Window outline
// is on, or the theme's window border gradient at its angle.
Item {
    id: root

    property var ui: null

    Rectangle {
        anchors.fill: parent
        radius: ui ? ui.r(3) : 0
        color: ui ? ui.panelColor : "black"
    }
    Rectangle {   // the accent wash (Window tint, 0 by default)
        anchors.fill: parent
        radius: ui ? ui.r(3) : 0
        visible: ui !== null && ui.tintPct > 0
        color: ui ? ui.accentTint(ui.tintPct / 100) : "transparent"
    }
    Rectangle {
        anchors.fill: parent
        radius: ui ? ui.r(3) : 0
        color: "transparent"
        visible: ui !== null && !ui.frameGradientOn
        border.width: 1
        border.color: !ui ? "transparent" : (ui.frameOn ? ui.frameColor : ui.tint(0.14))
        opacity: ui && ui.frameOn ? 0.85 : 1
    }
    Canvas {
        anchors.fill: parent
        visible: ui !== null && ui.frameGradientOn
        opacity: 0.85
        readonly property var stops: ui ? ui.borderColors : []
        readonly property real angle: ui ? ui.borderAngle : 0
        readonly property real rad: ui ? ui.r(3) : 0
        onStopsChanged: requestPaint()
        onAngleChanged: requestPaint()
        onRadChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onVisibleChanged: if (visible) requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const n = stops.length
            if (!visible || n < 2 || width < 4 || height < 4) return
            const a = angle * Math.PI / 180, dx = Math.cos(a), dy = Math.sin(a)
            const half = (Math.abs(dx) * width + Math.abs(dy) * height) / 2
            const g = ctx.createLinearGradient(width / 2 - dx * half, height / 2 - dy * half,
                                               width / 2 + dx * half, height / 2 + dy * half)
            for (let i = 0; i < n; i++) g.addColorStop(i / (n - 1), stops[i])
            const r = Math.max(0, Math.min(rad, width / 2, height / 2)), x = 0.5, y = 0.5, w = width - 1, h = height - 1
            ctx.strokeStyle = g
            ctx.lineWidth = 1
            ctx.beginPath()
            ctx.moveTo(x + r, y)
            ctx.arcTo(x + w, y, x + w, y + h, r)
            ctx.arcTo(x + w, y + h, x, y + h, r)
            ctx.arcTo(x, y + h, x, y, r)
            ctx.arcTo(x, y, x + w, y, r)
            ctx.closePath()
            ctx.stroke()
        }
    }
}
