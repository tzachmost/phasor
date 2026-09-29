import QtQuick
import "../../shell/theme" as Theme

Item {
    id: root

    readonly property bool isPdfView: false
    property url source: ""
    property string activeTool: "select"
    property color markColor: "#8bd5ca"
    property real strokeScale: 0.006
    property real userZoom: 1
    property real rotation: 0
    property bool framePlaybackPaused: false
    property bool flippedHorizontally: false
    property bool flippedVertically: false
    property var cropRect: null
    property var lassoPoints: []
    property var activeLassoPoints: []
    property bool lassoDrawing: false
    readonly property bool hasLassoSelection: lassoPoints.length >= 3
    readonly property bool sideways: Math.abs(rotation % 180) > 45 && Math.abs(rotation % 180) < 135
    readonly property real fitScale: {
        if (image.status !== Image.Ready || image.implicitWidth <= 0 || image.implicitHeight <= 0) return 1
        const contentWidth = sideways ? image.implicitHeight : image.implicitWidth
        const contentHeight = sideways ? image.implicitWidth : image.implicitHeight
        return Math.max(0.02, Math.min((viewport.width - 72) / contentWidth, (viewport.height - 72) / contentHeight))
    }
    readonly property real effectiveZoom: fitScale * userZoom
    readonly property int zoomPercent: Math.round(effectiveZoom * 100)
    readonly property int pageCount: Math.max(1, image.frameCount)
    readonly property int currentPage: image.status === Image.Ready && image.frameCount > 0 ? image.currentFrame : 0
    readonly property bool hasAnimation: pageCount > 1
    readonly property string documentStatus: image.status === Image.Ready
        ? image.implicitWidth + " × " + image.implicitHeight + " px"
            + (hasAnimation ? " · Frame " + (currentPage + 1) + " of " + pageCount : "")
        : image.status === Image.Loading ? "Loading image…" : image.status === Image.Error ? "Could not load this image" : ""

    signal markupChanged()
    signal textRequested(real x, real y)

    function fit() {
        userZoom = 1
        Qt.callLater(function() { viewport.returnToBounds() })
    }

    function zoomBy(factor) {
        userZoom = Math.max(0.1, Math.min(12, userZoom * factor))
    }

    function rotate(delta) {
        rotation = (rotation + delta + 360) % 360
        userZoom = 1
    }

    function goToPage(page) {
        if (!hasAnimation || !Number.isInteger(page) || page < 0 || page >= pageCount) return
        framePlaybackPaused = true
        image.currentFrame = page
    }

    function toggleFramePlayback() {
        if (hasAnimation) framePlaybackPaused = !framePlaybackPaused
    }

    function toggleHorizontalFlip() {
        flippedHorizontally = !flippedHorizontally
    }

    function toggleVerticalFlip() {
        flippedVertically = !flippedVertically
    }

    function clearCrop() {
        cropRect = null
    }

    function clearLasso() {
        lassoPoints = []
        activeLassoPoints = []
        lassoDrawing = false
        lassoCanvas.requestPaint()
    }

    function resetDocument() {
        cropRect = null
        rotation = 0
        userZoom = 1
        framePlaybackPaused = false
        flippedHorizontally = false
        flippedVertically = false
        clearLasso()
        Qt.callLater(function() { viewport.returnToBounds() })
    }

    function loadMarkup(value) {
        markupLayer.annotations = value && value.annotations ? value.annotations : []
    }

    function serializeMarkup() {
        return { version: 1, kind: "image", annotations: markupLayer.annotations }
    }

    function addText(x, y, text) {
        markupLayer.addText(x, y, text)
    }

    function undo() {
        markupLayer.undo()
    }

    Flickable {
        id: viewport
        anchors.fill: parent
        clip: true
        interactive: root.activeTool === "select"
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: Math.max(width, stage.width)
        contentHeight: Math.max(height, stage.height)

        Item {
            id: stage
            width: root.sideways ? image.height : image.width
            height: root.sideways ? image.width : image.height
            x: Math.max(0, (viewport.width - width) / 2)
            y: Math.max(0, (viewport.height - height) / 2)

            AnimatedImage {
                id: image
                source: root.source
                asynchronous: true
                cache: false
                autoTransform: true
                playing: root.hasAnimation
                paused: root.framePlaybackPaused
                fillMode: Image.PreserveAspectFit
                smooth: true
                width: status === Image.Ready ? implicitWidth * root.effectiveZoom : 1
                height: status === Image.Ready ? implicitHeight * root.effectiveZoom : 1
                anchors.centerIn: parent
                transform: [
                    Rotation { origin.x: image.width / 2; origin.y: image.height / 2; angle: root.rotation },
                    Scale {
                        origin.x: image.width / 2
                        origin.y: image.height / 2
                        xScale: root.flippedHorizontally ? -1 : 1
                        yScale: root.flippedVertically ? -1 : 1
                    }
                ]
            }

            MarkupCanvas {
                id: markupLayer
                width: image.width
                height: image.height
                anchors.centerIn: image
                z: 10
                transform: [
                    Rotation { origin.x: markupLayer.width / 2; origin.y: markupLayer.height / 2; angle: root.rotation },
                    Scale {
                        origin.x: markupLayer.width / 2
                        origin.y: markupLayer.height / 2
                        xScale: root.flippedHorizontally ? -1 : 1
                        yScale: root.flippedVertically ? -1 : 1
                    }
                ]
                activeTool: root.activeTool === "crop" || root.activeTool === "lasso" ? "select" : root.activeTool
                inkColor: root.markColor
                strokeScale: root.strokeScale
                onMarkupChanged: root.markupChanged()
                onTextRequested: function(x, y) { root.textRequested(x, y) }
            }

            Item {
                id: cropLayer
                width: image.width
                height: image.height
                anchors.centerIn: image
                transform: [
                    Rotation { origin.x: cropLayer.width / 2; origin.y: cropLayer.height / 2; angle: root.rotation },
                    Scale {
                        origin.x: cropLayer.width / 2
                        origin.y: cropLayer.height / 2
                        xScale: root.flippedHorizontally ? -1 : 1
                        yScale: root.flippedVertically ? -1 : 1
                    }
                ]
                z: 20

                Rectangle {
                    visible: Boolean(root.cropRect)
                    x: root.cropRect ? root.cropRect.x * parent.width : 0
                    y: root.cropRect ? root.cropRect.y * parent.height : 0
                    width: root.cropRect ? root.cropRect.width * parent.width : 0
                    height: root.cropRect ? root.cropRect.height * parent.height : 0
                    color: "#268bd5ca"
                    border.width: 2
                    border.color: Theme.Tokens.accent
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.activeTool === "crop"
                    preventStealing: true
                    cursorShape: Qt.CrossCursor
                    property real startX: 0
                    property real startY: 0

                    function updateCrop(x, y) {
                        const endX = Math.max(0, Math.min(1, x / width))
                        const endY = Math.max(0, Math.min(1, y / height))
                        root.cropRect = {
                            x: Math.min(startX, endX),
                            y: Math.min(startY, endY),
                            width: Math.abs(endX - startX),
                            height: Math.abs(endY - startY)
                        }
                    }

                    onPressed: function(mouse) {
                        startX = Math.max(0, Math.min(1, mouse.x / width))
                        startY = Math.max(0, Math.min(1, mouse.y / height))
                        updateCrop(mouse.x, mouse.y)
                    }
                    onPositionChanged: function(mouse) {
                        if (pressed) updateCrop(mouse.x, mouse.y)
                    }
                    onReleased: {
                        if (root.cropRect && (root.cropRect.width < 0.005 || root.cropRect.height < 0.005)) root.cropRect = null
                    }
                    onCanceled: root.cropRect = null
                }
            }

            Item {
                id: lassoLayer
                width: image.width
                height: image.height
                anchors.centerIn: image
                transform: [
                    Rotation { origin.x: lassoLayer.width / 2; origin.y: lassoLayer.height / 2; angle: root.rotation },
                    Scale {
                        origin.x: lassoLayer.width / 2
                        origin.y: lassoLayer.height / 2
                        xScale: root.flippedHorizontally ? -1 : 1
                        yScale: root.flippedVertically ? -1 : 1
                    }
                ]
                z: 30

                Canvas {
                    id: lassoCanvas
                    anchors.fill: parent
                    renderStrategy: Canvas.Threaded
                    onPaint: {
                        const context = getContext("2d")
                        context.clearRect(0, 0, width, height)
                        const points = root.lassoDrawing ? root.activeLassoPoints : root.lassoPoints
                        if (!points || points.length < 2) return
                        context.save()
                        context.lineWidth = 2
                        context.lineJoin = "round"
                        context.lineCap = "round"
                        context.strokeStyle = "#f7f7f7"
                        context.fillStyle = "rgba(139, 212, 202, 0.12)"
                        context.beginPath()
                        context.moveTo(points[0][0] * width, points[0][1] * height)
                        for (let index = 1; index < points.length; index++)
                            context.lineTo(points[index][0] * width, points[index][1] * height)
                        if (!root.lassoDrawing) {
                            context.closePath()
                            context.fill()
                            context.setLineDash([7, 5])
                        }
                        context.stroke()
                        context.restore()
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.activeTool === "lasso"
                    preventStealing: true
                    cursorShape: Qt.CrossCursor

                    function pointAt(x, y) {
                        return [Math.max(0, Math.min(1, x / width)), Math.max(0, Math.min(1, y / height))]
                    }

                    onPressed: function(mouse) {
                        root.lassoPoints = []
                        root.lassoDrawing = true
                        root.activeLassoPoints = [pointAt(mouse.x, mouse.y)]
                        lassoCanvas.requestPaint()
                    }
                    onPositionChanged: function(mouse) {
                        if (!pressed || root.activeLassoPoints.length >= 6000) return
                        const next = pointAt(mouse.x, mouse.y)
                        const previous = root.activeLassoPoints[root.activeLassoPoints.length - 1]
                        const dx = (next[0] - previous[0]) * width
                        const dy = (next[1] - previous[1]) * height
                        if (dx * dx + dy * dy < 2.25) return
                        const points = root.activeLassoPoints.slice()
                        points.push(next)
                        root.activeLassoPoints = points
                        lassoCanvas.requestPaint()
                    }
                    onReleased: {
                        if (root.activeLassoPoints.length >= 3) root.lassoPoints = root.activeLassoPoints.slice()
                        root.activeLassoPoints = []
                        root.lassoDrawing = false
                        lassoCanvas.requestPaint()
                    }
                    onCanceled: {
                        root.activeLassoPoints = []
                        root.lassoDrawing = false
                        lassoCanvas.requestPaint()
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(380, parent.width - 48)
        height: 84
        radius: Theme.Tokens.radiusMedium
        color: Theme.Tokens.surface
        border.color: Theme.Tokens.separator
        visible: image.status === Image.Error

        Text {
            anchors.fill: parent
            anchors.margins: Theme.Tokens.spacingL
            text: "This image format could not be opened. Try PNG, JPEG, WebP, SVG, or another Qt-supported format."
            color: Theme.Tokens.textSecondary
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: 13
        }
    }
}
