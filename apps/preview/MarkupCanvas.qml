import QtQuick

Item {
    id: root

    property var annotations: []
    property string activeTool: "select"
    property color inkColor: "#8bd5ca"
    property real strokeScale: 0.006
    property var activeAnnotation: null

    signal markupChanged()
    signal textRequested(real x, real y)

    function normalized(value, extent) {
        return extent > 0 ? Math.max(0, Math.min(1, value / extent)) : 0
    }

    function addText(x, y, text) {
        const value = String(text || "").trim()
        if (value.length === 0) return
        const next = annotations.slice()
        next.push({
            type: "text",
            x: x,
            y: y,
            text: value,
            color: inkColor.toString(),
            size: 0.038
        })
        annotations = next
        markupChanged()
    }

    function undo() {
        if (annotations.length === 0) return
        const next = annotations.slice()
        next.pop()
        annotations = next
        markupChanged()
    }

    function drawAnnotation(context, mark) {
        const unit = Math.min(width, height)
        const color = mark.color || "#8bd5ca"
        context.save()
        context.lineCap = "round"
        context.lineJoin = "round"
        context.strokeStyle = color
        context.fillStyle = color
        context.lineWidth = Math.max(1.5, (mark.width || strokeScale) * unit)

        if ((mark.type === "stroke" || mark.type === "signature") && Array.isArray(mark.points) && mark.points.length > 0) {
            context.beginPath()
            context.moveTo(mark.points[0][0] * width, mark.points[0][1] * height)
            for (let index = 1; index < mark.points.length; index++) {
                context.lineTo(mark.points[index][0] * width, mark.points[index][1] * height)
            }
            context.stroke()
        } else if ((mark.type === "rectangle" || mark.type === "highlight") && mark.x1 !== undefined) {
            const left = Math.min(mark.x1, mark.x2) * width
            const top = Math.min(mark.y1, mark.y2) * height
            const rectWidth = Math.abs(mark.x2 - mark.x1) * width
            const rectHeight = Math.abs(mark.y2 - mark.y1) * height
            if (mark.type === "highlight") {
                context.globalAlpha = 0.28
                context.fillRect(left, top, rectWidth, rectHeight)
            } else {
                context.strokeRect(left, top, rectWidth, rectHeight)
            }
        } else if (mark.type === "text" && mark.text) {
            context.font = Math.max(12, (mark.size || 0.038) * unit) + "px sans-serif"
            context.fillText(mark.text, mark.x * width, mark.y * height)
        }
        context.restore()
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Threaded
        onPaint: {
            const context = getContext("2d")
            context.clearRect(0, 0, width, height)
            for (const mark of root.annotations) root.drawAnnotation(context, mark)
            if (root.activeAnnotation) root.drawAnnotation(context, root.activeAnnotation)
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.activeTool !== "select"
        preventStealing: true
        cursorShape: root.activeTool === "text" ? Qt.IBeamCursor : Qt.CrossCursor

        onPressed: function(mouse) {
            const x = root.normalized(mouse.x, root.width)
            const y = root.normalized(mouse.y, root.height)
            if (root.activeTool === "text") {
                root.textRequested(x, y)
                return
            }

            if (root.activeTool === "rectangle" || root.activeTool === "highlight") {
                root.activeAnnotation = {
                    type: root.activeTool,
                    x1: x,
                    y1: y,
                    x2: x,
                    y2: y,
                    width: root.strokeScale,
                    color: root.inkColor.toString()
                }
            } else {
                root.activeAnnotation = {
                    type: root.activeTool === "signature" ? "signature" : "stroke",
                    width: root.strokeScale,
                    color: root.inkColor.toString(),
                    points: [[x, y]]
                }
            }
            canvas.requestPaint()
        }

        onPositionChanged: function(mouse) {
            if (!pressed || !root.activeAnnotation) return
            const x = root.normalized(mouse.x, root.width)
            const y = root.normalized(mouse.y, root.height)
            if (root.activeAnnotation.type === "stroke" || root.activeAnnotation.type === "signature") {
                const points = root.activeAnnotation.points.slice()
                if (points.length < 6000) points.push([x, y])
                root.activeAnnotation = Object.assign({}, root.activeAnnotation, { points: points })
            } else {
                root.activeAnnotation = Object.assign({}, root.activeAnnotation, { x2: x, y2: y })
            }
            canvas.requestPaint()
        }

        onReleased: {
            if (!root.activeAnnotation) return
            const next = root.annotations.slice()
            next.push(root.activeAnnotation)
            root.annotations = next
            root.activeAnnotation = null
            canvas.requestPaint()
            root.markupChanged()
        }

        onCanceled: {
            root.activeAnnotation = null
            canvas.requestPaint()
        }
    }

    onAnnotationsChanged: canvas.requestPaint()
    onActiveAnnotationChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
}
