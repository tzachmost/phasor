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
    property var cropRect: null
    readonly property bool sideways: Math.abs(rotation % 180) > 45 && Math.abs(rotation % 180) < 135
    readonly property real fitScale: {
        if (image.status !== Image.Ready || image.implicitWidth <= 0 || image.implicitHeight <= 0) return 1
        const contentWidth = sideways ? image.implicitHeight : image.implicitWidth
        const contentHeight = sideways ? image.implicitWidth : image.implicitHeight
        return Math.max(0.02, Math.min((viewport.width - 72) / contentWidth, (viewport.height - 72) / contentHeight))
    }
    readonly property real effectiveZoom: fitScale * userZoom
    readonly property int zoomPercent: Math.round(effectiveZoom * 100)
    readonly property int pageCount: 1
    readonly property int currentPage: 0
    readonly property string documentStatus: image.status === Image.Ready
        ? image.implicitWidth + " × " + image.implicitHeight + " px"
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

    function clearCrop() {
        cropRect = null
    }

    function resetDocument() {
        cropRect = null
        rotation = 0
        userZoom = 1
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

            Image {
                id: image
                source: root.source
                asynchronous: true
                cache: false
                autoTransform: true
                fillMode: Image.PreserveAspectFit
                smooth: true
                width: status === Image.Ready ? implicitWidth * root.effectiveZoom : 1
                height: status === Image.Ready ? implicitHeight * root.effectiveZoom : 1
                anchors.centerIn: parent
                rotation: root.rotation
            }

            MarkupCanvas {
                id: markupLayer
                width: image.width
                height: image.height
                anchors.centerIn: image
                z: 10
                rotation: root.rotation
                activeTool: root.activeTool === "crop" ? "select" : root.activeTool
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
                rotation: root.rotation
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
