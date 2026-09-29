import QtQuick
import "../../shell/theme" as Theme

Item {
    id: root

    property url source: ""
    property string activeTool: "select"
    property color markColor: "#8bd5ca"
    property real strokeScale: 0.006
    property real userZoom: 1
    property real rotation: 0
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
                activeTool: root.activeTool
                inkColor: root.markColor
                strokeScale: root.strokeScale
                onMarkupChanged: root.markupChanged()
                onTextRequested: function(x, y) { root.textRequested(x, y) }
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
