import QtQuick
import QtQuick.Controls
import QtQuick.Pdf
import "../../shell/theme" as Theme

Item {
    id: root

    property url source: ""
    property string activeTool: "select"
    property color markColor: "#8bd5ca"
    property real strokeScale: 0.006
    property string searchText: ""
    property real userZoom: 1
    property bool showThumbnails: true
    property var pageAnnotations: ({})
    readonly property int pageCount: pdfDocument.pageCount
    readonly property int currentPage: Math.max(0, pageView.currentPage)
    readonly property int zoomPercent: Math.round(pageView.renderScale * 100)
    readonly property string documentStatus: pdfDocument.status === PdfDocument.Ready
        ? pageCount + (pageCount === 1 ? " page" : " pages")
        : pdfDocument.status === PdfDocument.Loading ? "Loading PDF…"
        : pdfDocument.status === PdfDocument.Error ? (pdfDocument.error || "Could not load this PDF") : ""

    signal markupChanged()
    signal textRequested(real x, real y)

    function loadMarkup(value) {
        pageAnnotations = value && value.pages ? value.pages : ({})
        loadCurrentPageMarkup()
    }

    function loadCurrentPageMarkup() {
        markupLayer.annotations = pageAnnotations[String(currentPage)] || []
    }

    function storeCurrentPageMarkup() {
        const next = Object.assign({}, pageAnnotations)
        next[String(currentPage)] = markupLayer.annotations
        pageAnnotations = next
        markupChanged()
    }

    function serializeMarkup() {
        const next = Object.assign({}, pageAnnotations)
        next[String(currentPage)] = markupLayer.annotations
        return { version: 1, kind: "pdf", pages: next }
    }

    function addText(x, y, text) {
        markupLayer.addText(x, y, text)
    }

    function undo() {
        markupLayer.undo()
    }

    function searchBack() {
        pageView.searchBack()
    }

    function searchForward() {
        pageView.searchForward()
    }

    function copySelection() {
        pageView.copySelectionToClipboard()
    }

    function goToPage(page) {
        if (page >= 0 && page < pdfDocument.pageCount) pageView.goToPage(page)
    }

    function fit() {
        userZoom = 1
        updateFit()
        Qt.callLater(function() { documentViewport.returnToBounds() })
    }

    function updateFit() {
        if (pdfDocument.status !== PdfDocument.Ready || currentPage < 0) return
        const size = pdfDocument.pagePointSize(currentPage)
        if (size.width <= 0 || size.height <= 0) return
        const sideways = Math.abs(pageView.rotation % 180) > 45 && Math.abs(pageView.rotation % 180) < 135
        const pageWidth = sideways ? size.height : size.width
        const pageHeight = sideways ? size.width : size.height
        const availableWidth = Math.max(120, documentViewport.width - 72)
        const availableHeight = Math.max(120, documentViewport.height - 72)
        pageView.renderScale = Math.max(0.02, Math.min(availableWidth / pageWidth, availableHeight / pageHeight)) * userZoom
    }

    function zoomBy(factor) {
        userZoom = Math.max(0.1, Math.min(8, userZoom * factor))
        updateFit()
    }

    function rotate(delta) {
        pageView.rotation = (pageView.rotation + delta + 360) % 360
        updateFit()
    }

    PdfDocument {
        id: pdfDocument
        source: root.source
        onSourceChanged: {
            root.pageAnnotations = ({})
            markupLayer.annotations = []
        }
        function onStatusChanged(status) {
            if (status === PdfDocument.Ready) Qt.callLater(root.fit)
        }
    }

    Row {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            id: thumbnailPanel
            width: root.showThumbnails ? 176 : 0
            height: parent.height
            color: Theme.Tokens.surface
            visible: width > 0

            Column {
                anchors.fill: parent
                spacing: 0

                Text {
                    text: "PAGES"
                    height: 42
                    leftPadding: Theme.Tokens.spacingL
                    rightPadding: Theme.Tokens.spacingM
                    verticalAlignment: Text.AlignVCenter
                    color: Theme.Tokens.textSecondary
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 1.2
                }

                ListView {
                    id: thumbnails
                    width: parent.width
                    height: parent.height - 42
                    clip: true
                    spacing: Theme.Tokens.spacingM
                    model: pdfDocument.status === PdfDocument.Ready ? pdfDocument.pageCount : 0

                    delegate: Rectangle {
                        required property int index
                        width: thumbnails.width - 24
                        height: 148
                        anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
                        radius: Theme.Tokens.radiusSmall
                        color: index === root.currentPage ? Theme.Tokens.surfaceRaised : "transparent"
                        border.width: index === root.currentPage ? 2 : 1
                        border.color: index === root.currentPage ? Theme.Tokens.accent : Theme.Tokens.separator

                        Column {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 5
                            Rectangle {
                                width: parent.width
                                height: 112
                                radius: 3
                                color: "#ffffff"
                                clip: true
                                PdfPageImage {
                                    document: pdfDocument
                                    currentFrame: index
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    sourceSize: Qt.size(width * 2, height * 2)
                                }
                            }
                            Text {
                                text: "Page " + (index + 1)
                                width: parent.width
                                color: Theme.Tokens.textSecondary
                                font.pixelSize: 11
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.goToPage(index)
                        }
                    }
                }
            }

            Rectangle {
                anchors.right: parent.right
                width: 1
                height: parent.height
                color: Theme.Tokens.separator
            }
        }

        Flickable {
            id: documentViewport
            width: parent.width - thumbnailPanel.width
            height: parent.height
            clip: true
            contentWidth: Math.max(width, pageView.x + pageView.width)
            contentHeight: Math.max(height, pageView.y + pageView.height)
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

            PdfPageView {
                id: pageView
                document: pdfDocument
                zoomEnabled: false
                color: "#ffffff"
                border.width: 1
                border.color: "#d6dbe3"
                x: Math.max(0, (documentViewport.width - width) / 2)
                y: Math.max(0, (documentViewport.height - height) / 2)

                MarkupCanvas {
                    id: markupLayer
                    anchors.fill: parent
                    z: 100
                    activeTool: root.activeTool
                    inkColor: root.markColor
                    strokeScale: root.strokeScale
                    onMarkupChanged: root.storeCurrentPageMarkup()
                    onTextRequested: function(x, y) { root.textRequested(x, y) }
                }
            }
        }
    }

    Connections {
        target: pageView
        function onCurrentPageChanged() {
            root.loadCurrentPageMarkup()
            Qt.callLater(root.updateFit)
        }
    }

    onWidthChanged: Qt.callLater(updateFit)
    onHeightChanged: Qt.callLater(updateFit)
    onSearchTextChanged: pageView.searchString = searchText
}
