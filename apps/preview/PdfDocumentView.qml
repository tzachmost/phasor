import QtQuick
import QtQuick.Controls
import QtQuick.Pdf
import "../../shell/theme" as Theme

Item {
    id: root

    readonly property bool isPdfView: true
    property url source: ""
    property string activeTool: "select"
    property color markColor: "#8bd5ca"
    property real strokeScale: 0.006
    property string searchText: ""
    property real userZoom: 1
    property bool showThumbnails: true
    property string sidebarMode: "pages"
    property var pageAnnotations: ({})
    property var formValues: ({})
    property var passwordFieldNames: []
    property var pageOrder: []
    property var savedPageOrder: null
    property var pageRotations: ({})
    readonly property int pageCount: pageOrder.length > 0 ? pageOrder.length : Math.max(0, pdfDocument.pageCount)
    readonly property int currentPage: Math.max(0, pageOrder.indexOf(pageView.currentPage))
    readonly property int sourcePage: pageView.currentPage
    readonly property int contentsRowCount: contentsTree.rows
    readonly property int pageRotation: ((pageView.rotation % 360) + 360) % 360
    readonly property int zoomPercent: Math.round(pageView.renderScale * 100)
    readonly property string documentStatus: pdfDocument.status === PdfDocument.Ready
        ? pageCount + (pageCount === 1 ? " page" : " pages")
        : pdfDocument.status === PdfDocument.Loading ? "Loading PDF…"
        : pdfDocument.status === PdfDocument.Error ? (pdfDocument.error || "Could not load this PDF") : ""

    signal markupChanged()
    signal textRequested(real x, real y)
    signal digitalSignatureBoxRequested(int pageIndex, real x1, real y1, real x2, real y2, int rotation)

    function loadMarkup(value) {
        pageAnnotations = value && value.pages ? value.pages : ({})
        formValues = value && value.form_values ? value.form_values : ({})
        savedPageOrder = value && Array.isArray(value.page_order) ? value.page_order.slice() : null
        pageRotations = value && value.page_rotations ? value.page_rotations : ({})
        Qt.callLater(applySavedPageOperations)
        loadCurrentPageMarkup()
    }

    function applySavedPageOperations() {
        if (pdfDocument.status !== PdfDocument.Ready || pdfDocument.pageCount < 1) return
        let order = []
        if (savedPageOrder === null) {
            for (let page = 0; page < pdfDocument.pageCount; page++) order.push(page)
        } else {
            for (const page of savedPageOrder) {
                if (Number.isInteger(page) && page >= 0 && page < pdfDocument.pageCount && order.indexOf(page) < 0) order.push(page)
            }
            if (order.length === 0) order.push(0)
        }
        pageOrder = order
        if (pageOrder.indexOf(pageView.currentPage) < 0) pageView.goToPage(pageOrder[0])
        pageView.rotation = pageRotations[String(pageView.currentPage)] || 0
        Qt.callLater(updateFit)
    }

    function loadCurrentPageMarkup() {
        markupLayer.annotations = pageAnnotations[String(sourcePage)] || []
    }

    function storeCurrentPageMarkup() {
        const next = Object.assign({}, pageAnnotations)
        next[String(sourcePage)] = markupLayer.annotations
        pageAnnotations = next
        markupChanged()
    }

    function setPasswordFieldNames(names) {
        passwordFieldNames = Array.isArray(names) ? names.slice() : []
        const next = Object.assign({}, formValues)
        let removed = false
        for (const name of passwordFieldNames) {
            if (Object.prototype.hasOwnProperty.call(next, name)) {
                delete next[name]
                removed = true
            }
        }
        if (!removed) return
        formValues = next
        markupChanged()
    }

    function serializeMarkup(includePasswordValues) {
        const next = Object.assign({}, pageAnnotations)
        if (sourcePage >= 0) next[String(sourcePage)] = markupLayer.annotations
        const savedFormValues = Object.assign({}, formValues)
        if (!includePasswordValues) {
            for (const name of passwordFieldNames) delete savedFormValues[name]
        }
        return {
            version: 1,
            kind: "pdf",
            pages: next,
            page_order: pageOrder.length > 0 ? pageOrder : savedPageOrder,
            page_rotations: pageRotations,
            form_values: savedFormValues
        }
    }

    function setFormValue(name, value) {
        const next = Object.assign({}, formValues)
        next[name] = value
        formValues = next
        markupChanged()
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
        if (page < 0 || page >= pageCount) return
        const sourceIndex = pageOrder.length > page ? pageOrder[page] : page
        if (sourceIndex >= 0 && sourceIndex < pdfDocument.pageCount) pageView.goToPage(sourceIndex)
    }

    function goToBookmark(sourceIndex, location, zoom) {
        if (sourceIndex < 0 || sourceIndex >= pdfDocument.pageCount) return false
        if (pageOrder.length > 0 && pageOrder.indexOf(sourceIndex) < 0) return false
        if (pageOrder.length === 0 && savedPageOrder !== null) return false

        const validLocation = location
            && Number.isFinite(location.x) && Number.isFinite(location.y)
            && Math.abs(location.x) < 1000000000 && Math.abs(location.y) < 1000000000
        const validZoom = Number.isFinite(zoom) && zoom >= 0 && zoom < 1000000
        pageView.goToLocation(
            sourceIndex,
            validLocation ? location : Qt.point(-1, -1),
            validZoom ? zoom : 0
        )
        return true
    }

    function fit() {
        userZoom = 1
        updateFit()
        Qt.callLater(function() { documentViewport.returnToBounds() })
    }

    function updateFit() {
        if (pdfDocument.status !== PdfDocument.Ready || currentPage < 0) return
        const size = pdfDocument.pagePointSize(sourcePage)
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
        if (sourcePage < 0) return
        const rotation = ((pageRotations[String(sourcePage)] || 0) + delta + 360) % 360
        const next = Object.assign({}, pageRotations)
        next[String(sourcePage)] = rotation
        pageRotations = next
        pageView.rotation = rotation
        updateFit()
        markupChanged()
    }

    function moveCurrentPage(delta) {
        const from = currentPage
        const to = from + delta
        if (from < 0 || to < 0 || from >= pageOrder.length || to >= pageOrder.length) return
        const next = pageOrder.slice()
        const value = next[from]
        next[from] = next[to]
        next[to] = value
        pageOrder = next
        markupChanged()
    }

    function excludeCurrentPage() {
        if (pageOrder.length <= 1 || currentPage < 0) return
        const next = pageOrder.slice()
        next.splice(currentPage, 1)
        const target = next[Math.min(currentPage, next.length - 1)]
        pageOrder = next
        if (target !== pageView.currentPage) pageView.goToPage(target)
        markupChanged()
    }

    function resetPageOperations() {
        const next = []
        for (let page = 0; page < pdfDocument.pageCount; page++) next.push(page)
        pageOrder = next
        pageRotations = ({})
        if (next.length > 0 && next.indexOf(pageView.currentPage) < 0) pageView.goToPage(next[0])
        pageView.rotation = 0
        updateFit()
        markupChanged()
    }

    PdfDocument {
        id: pdfDocument
        source: root.source
        onSourceChanged: {
            root.pageAnnotations = ({})
            root.formValues = ({})
            root.passwordFieldNames = []
            root.pageOrder = []
            root.savedPageOrder = null
            root.pageRotations = ({})
            root.sidebarMode = "pages"
            markupLayer.annotations = []
        }
        function onStatusChanged(status) {
            if (status === PdfDocument.Ready) Qt.callLater(root.applySavedPageOperations)
        }
    }

    PdfBookmarkModel {
        id: bookmarkModel
        document: pdfDocument
    }

    Row {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            id: thumbnailPanel
            width: root.showThumbnails ? 224 : 0
            height: parent.height
            color: Theme.Tokens.surface
            visible: width > 0

            Column {
                anchors.fill: parent
                spacing: 0

                Row {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 42
                    spacing: 2

                    ToolButton {
                        text: "Pages"
                        height: parent.height
                        checkable: true
                        checked: root.sidebarMode === "pages"
                        onClicked: root.sidebarMode = "pages"
                    }

                    ToolButton {
                        text: "Contents"
                        height: parent.height
                        checkable: true
                        checked: root.sidebarMode === "contents"
                        onClicked: root.sidebarMode = "contents"
                    }
                }

                ListView {
                    id: thumbnails
                    width: parent.width
                    height: parent.height - 42
                    clip: true
                    spacing: Theme.Tokens.spacingM
                    visible: root.sidebarMode === "pages"
                    model: pdfDocument.status === PdfDocument.Ready ? root.pageCount : 0

                    delegate: Rectangle {
                        required property int index
                        readonly property int sourceIndex: root.pageOrder.length > index ? root.pageOrder[index] : index
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
                                    currentFrame: sourceIndex
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

                TreeView {
                    id: contentsTree
                    width: parent.width
                    height: parent.height - 42
                    clip: true
                    visible: root.sidebarMode === "contents"
                    model: bookmarkModel

                    delegate: Rectangle {
                        required property int row
                        required property int depth
                        required property bool hasChildren
                        required property bool expanded
                        required property string title
                        required property int page
                        required property point location
                        required property real zoom

                        implicitWidth: contentsTree.width
                        implicitHeight: 34
                        color: "transparent"

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.goToBookmark(page, location, zoom)
                        }

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 6 + depth * 10
                            anchors.rightMargin: 6
                            spacing: 1

                            ToolButton {
                                width: 24
                                height: parent.height
                                visible: hasChildren
                                text: expanded ? "⌄" : "›"
                                onClicked: contentsTree.toggleExpanded(row)
                            }

                            Item {
                                width: hasChildren ? 0 : 24
                                height: 1
                                visible: !hasChildren
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 30
                                text: title
                                color: Theme.Tokens.textSecondary
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

            }

            Text {
                anchors.centerIn: parent
                width: parent.width - 24
                visible: root.sidebarMode === "contents" && contentsTree.rows === 0
                text: "This PDF has no table of contents."
                color: Theme.Tokens.textSecondary
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
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
            onWidthChanged: Qt.callLater(root.updateFit)
            onHeightChanged: Qt.callLater(root.updateFit)
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
                    onSignatureBoxRequested: function(x1, y1, x2, y2) {
                        root.digitalSignatureBoxRequested(root.currentPage, x1, y1, x2, y2, root.pageRotation)
                    }
                }
            }
        }
    }

    Connections {
        target: pageView
        function onCurrentPageChanged() {
            const rotation = root.pageRotations[String(root.sourcePage)] || 0
            if (pageView.rotation !== rotation) pageView.rotation = rotation
            root.loadCurrentPageMarkup()
            Qt.callLater(root.updateFit)
        }
    }

    onWidthChanged: Qt.callLater(updateFit)
    onHeightChanged: Qt.callLater(updateFit)
    onSearchTextChanged: pageView.searchString = searchText
}
