import QtQuick
import QtQuick.Controls

Item {
    id: root

    property var annotations: []
    property string activeTool: "select"
    property color inkColor: "#8bd5ca"
    property real strokeScale: 0.006
    property var activeAnnotation: null

    signal markupChanged()
    signal textRequested(real x, real y)
    signal signatureBoxRequested(real x1, real y1, real x2, real y2)
    signal textSelectionStarted(real x, real y)
    signal textSelectionMoved(real x, real y)
    signal textSelectionFinished()

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
        } else if (mark.type === "signature_box" && mark.x1 !== undefined) {
            context.save()
            context.setLineDash([7, 5])
            context.lineWidth = 2
            context.strokeStyle = "#1c1d20"
            context.fillStyle = "rgba(139, 212, 202, 0.18)"
            const left = Math.min(mark.x1, mark.x2) * width
            const top = Math.min(mark.y1, mark.y2) * height
            const rectWidth = Math.abs(mark.x2 - mark.x1) * width
            const rectHeight = Math.abs(mark.y2 - mark.y1) * height
            context.fillRect(left, top, rectWidth, rectHeight)
            context.strokeRect(left, top, rectWidth, rectHeight)
            context.restore()
        } else if (mark.type === "redaction" && mark.x1 !== undefined) {
            const left = Math.min(mark.x1, mark.x2) * width
            const top = Math.min(mark.y1, mark.y2) * height
            const rectWidth = Math.abs(mark.x2 - mark.x1) * width
            const rectHeight = Math.abs(mark.y2 - mark.y1) * height
            context.globalAlpha = 1
            context.fillStyle = "#000000"
            context.fillRect(left, top, rectWidth, rectHeight)
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
        } else if (["text_highlight", "underline", "strike", "note"].indexOf(mark.type) >= 0
                   && Array.isArray(mark.rects)) {
            context.lineWidth = Math.max(1, unit * 0.0018)
            for (const rect of mark.rects) {
                const left = rect[0] * width
                const top = rect[1] * height
                const right = rect[2] * width
                const bottom = rect[3] * height
                if (mark.type === "text_highlight") {
                    context.globalAlpha = 0.3
                    context.fillRect(left, top, right - left, bottom - top)
                    context.globalAlpha = 1
                } else {
                    const lineY = mark.type === "strike" ? (top + bottom) / 2 : bottom
                    context.beginPath()
                    context.moveTo(left, lineY)
                    context.lineTo(right, lineY)
                    context.stroke()
                }
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
            if (["text_highlight", "underline", "strike", "note"].indexOf(root.activeTool) >= 0) {
                root.textSelectionStarted(x, y)
                return
            }
            if (root.activeTool === "text") {
                root.textRequested(x, y)
                return
            }

            if (["rectangle", "highlight", "redaction", "signature_box"].indexOf(root.activeTool) >= 0) {
                root.activeAnnotation = {
                    type: root.activeTool,
                    x1: x,
                    y1: y,
                    x2: x,
                    y2: y,
                    width: root.strokeScale,
                    color: root.activeTool === "redaction" ? "#000000" : root.inkColor.toString()
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
            if (!pressed) return
            const x = root.normalized(mouse.x, root.width)
            const y = root.normalized(mouse.y, root.height)
            if (["text_highlight", "underline", "strike", "note"].indexOf(root.activeTool) >= 0) {
                root.textSelectionMoved(x, y)
                return
            }
            if (!root.activeAnnotation) return
            if (root.activeAnnotation.type === "redaction"
                && (Math.abs(root.activeAnnotation.x2 - root.activeAnnotation.x1) < 0.002
                    || Math.abs(root.activeAnnotation.y2 - root.activeAnnotation.y1) < 0.002)) {
                root.activeAnnotation = null
                canvas.requestPaint()
                return
            }
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
            if (["text_highlight", "underline", "strike", "note"].indexOf(root.activeTool) >= 0) {
                root.textSelectionFinished()
                return
            }
            if (!root.activeAnnotation) return
            if (root.activeAnnotation.type === "signature_box") {
                const mark = root.activeAnnotation
                root.activeAnnotation = null
                canvas.requestPaint()
                root.signatureBoxRequested(
                    Math.min(mark.x1, mark.x2), Math.min(mark.y1, mark.y2),
                    Math.max(mark.x1, mark.x2), Math.max(mark.y1, mark.y2)
                )
                return
            }
            const next = root.annotations.slice()
            next.push(root.activeAnnotation)
            root.annotations = next
            root.activeAnnotation = null
            canvas.requestPaint()
            root.markupChanged()
        }

        onCanceled: {
            if (["text_highlight", "underline", "strike", "note"].indexOf(root.activeTool) >= 0) {
                root.textSelectionFinished()
                return
            }
            root.activeAnnotation = null
            canvas.requestPaint()
        }
    }

    Repeater {
        model: root.annotations.filter(function(mark) {
            return mark.type === "note" && Array.isArray(mark.rects) && mark.rects.length > 0
        })

        delegate: Rectangle {
            required property var modelData
            readonly property var anchorRect: modelData.rects[0]
            readonly property real markerSize: 18
            x: Math.max(0, Math.min(root.width - markerSize, anchorRect[2] * root.width - markerSize / 2))
            y: Math.max(0, Math.min(root.height - markerSize, anchorRect[1] * root.height - markerSize / 2))
            width: markerSize
            height: markerSize
            radius: 5
            z: 10
            color: "#f3c969"
            border.width: 1
            border.color: "#6b5315"

            Text {
                anchors.centerIn: parent
                text: "i"
                color: "#34290c"
                font.pixelSize: 12
                font.weight: Font.Bold
            }

            MouseArea {
                id: noteMarker
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
            }
            ToolTip.visible: noteMarker.containsMouse
            ToolTip.text: modelData.note
            ToolTip.delay: 300
            Accessible.name: "Text note: " + modelData.note
        }
    }

    onAnnotationsChanged: canvas.requestPaint()
    onActiveAnnotationChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
}
