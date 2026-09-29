import QtQuick
import QtQuick.Controls
import QtQuick.Pdf
import "../../shell/theme" as Theme

Item {
    id: root

    readonly property bool isPdfView: true
    property url source: ""
    property string documentPassword: ""
    property string activeTool: "select"
    property color markColor: "#8bd5ca"
    property real strokeScale: 0.006
    property string searchText: ""
    property real userZoom: 1
    property bool showThumbnails: true
    property string sidebarMode: "pages"
    property string readingLayout: "single"
    property int spreadStartPage: 0
    property int activeSpreadPage: 0
    property bool syncingSpread: false
    property int textSelectionPage: -1
    property string textSelectionLayer: "primary"
    property string textSelectionTool: ""
    property point textSelectionStart: Qt.point(0, 0)
    property point textSelectionEnd: Qt.point(0, 0)
    property bool textSelectionDragging: false
    property var pageAnnotations: ({})
    property var formValues: ({})
    property var passwordFieldNames: []
    property var pageOrder: []
    property var savedPageOrder: null
    property var pageRotations: ({})
    readonly property int pageCount: pageOrder.length > 0 ? pageOrder.length : Math.max(0, pdfDocument.pageCount)
    readonly property int currentPage: readingLayout === "continuous" ? continuousView.currentPage
        : readingLayout === "two-page" ? activeSpreadPage
        : Math.max(0, pageOrder.indexOf(pageView.currentPage))
    readonly property int sourcePage: currentPage >= 0 && pageOrder.length > currentPage ? pageOrder[currentPage] : pageView.currentPage
    readonly property int contentsRowCount: contentsTree.rows
    readonly property int pageRotation: readingLayout === "two-page"
        ? ((activeSpreadPage === spreadStartPage ? pageView.rotation : spreadSecondView.rotation) % 360 + 360) % 360
        : readingLayout === "single" ? ((pageView.rotation % 360) + 360) % 360 : 0
    readonly property int zoomPercent: Math.round((readingLayout === "continuous" ? continuousView.renderScale : pageView.renderScale) * 100)
    readonly property string documentStatus: pdfDocument.status === PdfDocument.Ready
        ? pageCount + (pageCount === 1 ? " page" : " pages")
        : pdfDocument.status === PdfDocument.Loading ? "Loading PDF…"
        : pdfDocument.status === PdfDocument.Error ? (pdfDocument.error || "Could not load this PDF") : ""

    signal markupChanged()
    signal textRequested(real x, real y)
    signal textNoteRequested(string quote, var rects, int pageIndex)
    signal textAnnotationFailed(string message)
    signal digitalSignatureBoxRequested(int pageIndex, real x1, real y1, real x2, real y2, int rotation)
    signal passwordRequired()
    signal documentLoadFailed(string message)

    function setDocumentPassword(value) {
        documentPassword = String(value || "")
    }

    function loadMarkup(value) {
        pageAnnotations = value && value.pages ? value.pages : ({})
        formValues = value && value.form_values ? value.form_values : ({})
        savedPageOrder = value && Array.isArray(value.page_order) ? value.page_order.slice() : null
        pageRotations = value && value.page_rotations ? value.page_rotations : ({})
        Qt.callLater(applySavedPageOperations)
        loadVisibleMarkup()
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
        loadVisibleMarkup()
        Qt.callLater(updateFit)
    }

    function loadVisibleMarkup() {
        if (readingLayout === "two-page") {
            const firstSource = pageOrder[spreadStartPage]
            const secondSource = pageOrder[spreadStartPage + 1]
            markupLayer.annotations = firstSource === undefined ? [] : (pageAnnotations[String(firstSource)] || [])
            spreadSecondMarkup.annotations = secondSource === undefined ? [] : (pageAnnotations[String(secondSource)] || [])
        } else if (sourcePage >= 0) {
            markupLayer.annotations = pageAnnotations[String(sourcePage)] || []
        }
    }

    function hasPageOperations() {
        if (pdfDocument.status !== PdfDocument.Ready || pdfDocument.pageCount < 1) return true
        const order = pageOrder.length > 0 ? pageOrder : savedPageOrder
        if (order !== null) {
            if (!Array.isArray(order) || order.length !== pdfDocument.pageCount) return true
            for (let index = 0; index < order.length; index++) {
                if (order[index] !== index) return true
            }
        }
        return Object.keys(pageRotations).some(function(page) { return Number(pageRotations[page]) % 360 !== 0 })
    }

    function storeMarkupForSourcePage(sourceIndex, annotations) {
        if (sourceIndex < 0) return
        const next = Object.assign({}, pageAnnotations)
        next[String(sourceIndex)] = annotations
        pageAnnotations = next
        markupChanged()
    }

    function activePageView() {
        if (readingLayout === "two-page" && activeSpreadPage !== spreadStartPage) return spreadSecondView
        return pageView
    }

    function activeMarkupLayer() {
        if (readingLayout === "two-page" && activeSpreadPage !== spreadStartPage) return spreadSecondMarkup
        return markupLayer
    }

    function syncSpread(page) {
        if (page < 0 || page >= pageCount) return
        syncingSpread = true
        activeSpreadPage = page
        spreadStartPage = Math.floor(page / 2) * 2
        const firstSource = pageOrder[spreadStartPage]
        const secondSource = spreadStartPage + 1 < pageOrder.length ? pageOrder[spreadStartPage + 1] : -1
        if (firstSource !== undefined && pageView.currentPage !== firstSource) pageView.goToPage(firstSource)
        if (secondSource >= 0 && spreadSecondView.currentPage !== secondSource) spreadSecondView.goToPage(secondSource)
        syncingSpread = false
        loadVisibleMarkup()
        Qt.callLater(updateFit)
    }

    function setReadingLayout(mode) {
        if (["single", "continuous", "two-page"].indexOf(mode) < 0) return false
        if (mode !== "single" && pageOrder.length === 0 && pdfDocument.status === PdfDocument.Ready)
            applySavedPageOperations()
        if (mode !== "single" && hasPageOperations()) return false
        const displayPage = Math.max(0, Math.min(currentPage, pageCount - 1))
        const currentSource = pageOrder.length > displayPage ? pageOrder[displayPage] : pageView.currentPage
        if (mode === "single") {
            readingLayout = "single"
            if (currentSource >= 0 && pageView.currentPage !== currentSource) pageView.goToPage(currentSource)
            pageView.rotation = pageRotations[String(currentSource)] || 0
            loadVisibleMarkup()
        } else if (mode === "continuous") {
            readingLayout = "continuous"
            if (currentSource >= 0) continuousView.goToPage(currentSource)
        } else {
            readingLayout = "two-page"
            syncSpread(displayPage)
        }
        if (mode !== "single") activeTool = "select"
        Qt.callLater(updateFit)
        return true
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
        if (readingLayout === "single" && sourcePage >= 0) {
            next[String(sourcePage)] = markupLayer.annotations
        } else if (readingLayout === "two-page") {
            const firstSource = pageOrder[spreadStartPage]
            const secondSource = pageOrder[spreadStartPage + 1]
            if (firstSource !== undefined) next[String(firstSource)] = markupLayer.annotations
            if (secondSource !== undefined) next[String(secondSource)] = spreadSecondMarkup.annotations
        }
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
        activeMarkupLayer().addText(x, y, text)
    }

    function beginTextAnnotationSelection(layer, pageIndex, x, y) {
        if (readingLayout === "continuous" || pageIndex < 0 || pdfDocument.status !== PdfDocument.Ready) return
        textSelectionPage = pageIndex
        textSelectionLayer = layer
        textSelectionTool = activeTool
        textSelectionDragging = true
        textSelectionStart = Qt.point(x, y)
        textSelectionEnd = Qt.point(x, y)
    }

    function updateTextAnnotationSelection(layer, x, y) {
        if (!textSelectionDragging || layer !== textSelectionLayer) return
        textSelectionEnd = Qt.point(x, y)
    }

    function finishTextAnnotationSelection(layer) {
        if (!textSelectionDragging || layer !== textSelectionLayer) return
        textSelectionDragging = false
        Qt.callLater(function() {
            const quote = String(textSelectionCapture.text || "").trim()
            const rects = root.normalizedSelectionRectangles()
            if (!quote || rects.length === 0) {
                root.textAnnotationFailed("Drag across selectable PDF text to attach an annotation.")
                return
            }
            if (root.textSelectionTool === "note") {
                root.textNoteRequested(quote, rects, root.textSelectionPage)
                return
            }
            root.addTextAnchoredAnnotation(root.textSelectionTool, quote, rects, root.textSelectionPage, "")
        })
    }

    function normalizedSelectionRectangles() {
        const pageSize = textSelectionPage >= 0 && textSelectionPage < pdfDocument.pageCount
            ? pdfDocument.pagePointSize(textSelectionPage) : Qt.size(0, 0)
        if (pageSize.width <= 0 || pageSize.height <= 0) return []
        const geometry = textSelectionCapture.geometry
        const rects = []
        for (let polygonIndex = 0; polygonIndex < geometry.length && rects.length < 256; polygonIndex++) {
            const polygon = String(geometry[polygonIndex] || "")
            const pointPattern = /QPointF\(\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)\s*,\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)\s*\)/g
            let left = Infinity
            let top = Infinity
            let right = -Infinity
            let bottom = -Infinity
            let match
            while ((match = pointPattern.exec(polygon)) !== null) {
                const x = Number(match[1])
                const y = Number(match[2])
                if (!Number.isFinite(x) || !Number.isFinite(y)) continue
                left = Math.min(left, x)
                top = Math.min(top, y)
                right = Math.max(right, x)
                bottom = Math.max(bottom, y)
            }
            if (!Number.isFinite(left) || !Number.isFinite(top)) continue
            const x1 = Math.max(0, Math.min(1, left / pageSize.width))
            const y1 = Math.max(0, Math.min(1, top / pageSize.height))
            const x2 = Math.max(0, Math.min(1, right / pageSize.width))
            const y2 = Math.max(0, Math.min(1, bottom / pageSize.height))
            if (Number.isFinite(x1) && Number.isFinite(y1) && x2 > x1 && y2 > y1)
                rects.push([x1, y1, x2, y2])
        }
        if (rects.length === 0 && String(textSelectionCapture.text || "").trim()) {
            let x1 = Math.max(0, Math.min(1, Math.min(textSelectionStart.x, textSelectionEnd.x)))
            let y1 = Math.max(0, Math.min(1, Math.min(textSelectionStart.y, textSelectionEnd.y)))
            let x2 = Math.max(0, Math.min(1, Math.max(textSelectionStart.x, textSelectionEnd.x)))
            let y2 = Math.max(0, Math.min(1, Math.max(textSelectionStart.y, textSelectionEnd.y)))
            const minWidth = Math.min(0.02, 2 / pageSize.width)
            const minHeight = Math.min(0.02, 2 / pageSize.height)
            if (x2 - x1 < minWidth) x2 = Math.min(1, x1 + minWidth)
            if (y2 - y1 < minHeight) y2 = Math.min(1, y1 + minHeight)
            if (x2 > x1 && y2 > y1) rects.push([x1, y1, x2, y2])
        }
        return rects
    }

    function addTextAnchoredAnnotation(kind, quote, rects, pageIndex, noteText) {
        if (pageIndex < 0 || !Array.isArray(rects) || rects.length === 0) return
        const annotation = {
            type: kind,
            color: kind === "note" ? "#f3c969" : markColor.toString(),
            quote: String(quote),
            rects: rects
        }
        if (kind === "note") annotation.note = String(noteText || "")
        const next = (pageAnnotations[String(pageIndex)] || []).slice()
        next.push(annotation)
        storeMarkupForSourcePage(pageIndex, next)
        loadVisibleMarkup()
    }

    function undo() {
        activeMarkupLayer().undo()
    }

    function searchBack() {
        if (readingLayout === "continuous") continuousView.searchBack()
        else activePageView().searchBack()
    }

    function searchForward() {
        if (readingLayout === "continuous") continuousView.searchForward()
        else activePageView().searchForward()
    }

    function copySelection() {
        if (readingLayout === "continuous") continuousView.copySelectionToClipboard()
        else activePageView().copySelectionToClipboard()
    }

    function goToPage(page) {
        if (page < 0 || page >= pageCount) return
        const sourceIndex = pageOrder.length > page ? pageOrder[page] : page
        if (sourceIndex < 0 || sourceIndex >= pdfDocument.pageCount) return
        if (readingLayout === "continuous") continuousView.goToPage(sourceIndex)
        else if (readingLayout === "two-page") syncSpread(page)
        else pageView.goToPage(sourceIndex)
    }

    function goToBookmark(sourceIndex, location, zoom) {
        if (sourceIndex < 0 || sourceIndex >= pdfDocument.pageCount) return false
        if (pageOrder.length > 0 && pageOrder.indexOf(sourceIndex) < 0) return false
        if (pageOrder.length === 0 && savedPageOrder !== null) return false

        const validLocation = location
            && Number.isFinite(location.x) && Number.isFinite(location.y)
            && Math.abs(location.x) < 1000000000 && Math.abs(location.y) < 1000000000
        const validZoom = Number.isFinite(zoom) && zoom >= 0 && zoom < 1000000
        const displayIndex = pageOrder.indexOf(sourceIndex)
        if (displayIndex < 0) return false
        if (readingLayout === "continuous") continuousView.goToLocation(sourceIndex, validLocation ? location : Qt.point(-1, -1), validZoom ? zoom : 0)
        else if (readingLayout === "two-page") {
            syncSpread(displayIndex)
            activePageView().goToLocation(sourceIndex, validLocation ? location : Qt.point(-1, -1), validZoom ? zoom : 0)
        } else pageView.goToLocation(sourceIndex, validLocation ? location : Qt.point(-1, -1), validZoom ? zoom : 0)
        return true
    }

    function fit() {
        userZoom = 1
        updateFit()
        if (readingLayout === "single") Qt.callLater(function() { documentViewport.returnToBounds() })
    }

    function updateFit() {
        if (pdfDocument.status !== PdfDocument.Ready || currentPage < 0) return
        if (readingLayout === "continuous") {
            const size = pdfDocument.pagePointSize(continuousView.currentPage)
            if (size.width <= 0 || size.height <= 0) return
            const scale = Math.min(Math.max(120, continuousView.width - 52) / size.width,
                                   Math.max(120, continuousView.height - 52) / size.height) * userZoom
            continuousView.renderScale = Math.max(0.02, Math.min(8, scale))
            return
        }
        const size = pdfDocument.pagePointSize(sourcePage)
        if (size.width <= 0 || size.height <= 0) return
        const sideways = Math.abs(activePageView().rotation % 180) > 45 && Math.abs(activePageView().rotation % 180) < 135
        const pageWidth = sideways ? size.height : size.width
        const pageHeight = sideways ? size.width : size.height
        const hasSecondSpreadPage = readingLayout === "two-page" && spreadStartPage + 1 < pageCount
        const availableWidth = Math.max(120, (hasSecondSpreadPage ? spreadViewport.width / 2 - 32 : documentViewport.width - 72))
        const availableHeight = Math.max(120, (readingLayout === "two-page" ? spreadViewport.height - 64 : documentViewport.height - 72))
        let scale = Math.min(availableWidth / pageWidth, availableHeight / pageHeight)
        if (readingLayout === "two-page" && spreadStartPage + 1 < pageCount) {
            const otherSize = pdfDocument.pagePointSize(pageOrder[spreadStartPage + 1])
            if (otherSize.width > 0 && otherSize.height > 0)
                scale = Math.min(scale, availableWidth / otherSize.width, availableHeight / otherSize.height)
        }
        scale = Math.max(0.02, Math.min(8, scale * userZoom))
        pageView.renderScale = scale
        if (readingLayout === "two-page") spreadSecondView.renderScale = scale
    }

    function zoomBy(factor) {
        userZoom = Math.max(0.1, Math.min(8, userZoom * factor))
        updateFit()
    }

    function rotate(delta) {
        if (readingLayout !== "single") setReadingLayout("single")
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
        if (readingLayout !== "single") setReadingLayout("single")
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
        if (readingLayout !== "single") setReadingLayout("single")
        if (pageOrder.length <= 1 || currentPage < 0) return
        const next = pageOrder.slice()
        next.splice(currentPage, 1)
        const target = next[Math.min(currentPage, next.length - 1)]
        pageOrder = next
        if (target !== pageView.currentPage) pageView.goToPage(target)
        markupChanged()
    }

    function resetPageOperations() {
        if (readingLayout !== "single") setReadingLayout("single")
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
        password: root.documentPassword
        onPasswordRequired: root.passwordRequired()
        onSourceChanged: {
            root.readingLayout = "single"
            root.pageAnnotations = ({})
            root.formValues = ({})
            root.passwordFieldNames = []
            root.pageOrder = []
            root.savedPageOrder = null
            root.pageRotations = ({})
            root.sidebarMode = "pages"
            markupLayer.annotations = []
        }
    }

    PdfSelection {
        id: textSelectionCapture
        document: pdfDocument
        page: root.textSelectionPage
        from: {
            const size = root.textSelectionPage >= 0 && root.textSelectionPage < pdfDocument.pageCount
                ? pdfDocument.pagePointSize(root.textSelectionPage) : Qt.size(0, 0)
            return Qt.point(root.textSelectionStart.x * size.width, root.textSelectionStart.y * size.height)
        }
        to: {
            const size = root.textSelectionPage >= 0 && root.textSelectionPage < pdfDocument.pageCount
                ? pdfDocument.pagePointSize(root.textSelectionPage) : Qt.size(0, 0)
            return Qt.point(root.textSelectionEnd.x * size.width, root.textSelectionEnd.y * size.height)
        }
        hold: !root.textSelectionDragging
    }

    Connections {
        target: pdfDocument
        function onStatusChanged(status) {
            if (status === PdfDocument.Ready) {
                Qt.callLater(root.applySavedPageOperations)
            } else if (status === PdfDocument.Error) {
                const message = pdfDocument.error || "Could not load this PDF"
                if (/password|encrypted/i.test(message)) root.passwordRequired()
                else root.documentLoadFailed(message)
            }
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

        Item {
            id: readingSurface
            width: parent.width - thumbnailPanel.width
            height: parent.height

            Flickable {
                id: documentViewport
                anchors.fill: parent
                visible: root.readingLayout === "single"
                onWidthChanged: Qt.callLater(root.updateFit)
                onHeightChanged: Qt.callLater(root.updateFit)
                clip: true
                contentWidth: Math.max(width, pageView.x + pageView.width)
                contentHeight: Math.max(height, pageView.y + pageView.height)
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
            }

            Flickable {
                id: spreadViewport
                anchors.fill: parent
                visible: root.readingLayout === "two-page"
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: Math.max(width, spreadRow.width)
                contentHeight: Math.max(height, spreadRow.height)
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

                Row {
                    id: spreadRow
                    width: firstSpreadCell.width + (secondSpreadCell.visible ? secondSpreadCell.width + 12 : 0)
                    height: Math.max(spreadViewport.height, firstSpreadCell.height, secondSpreadCell.visible ? secondSpreadCell.height : 0)
                    x: Math.max(0, (spreadViewport.width - width) / 2)
                    y: Math.max(0, (spreadViewport.height - height) / 2)

                    Item {
                        id: firstSpreadCell
                        width: secondSpreadCell.visible ? Math.max(spreadViewport.width / 2 - 6, pageView.width + 16) : Math.max(spreadViewport.width, pageView.width + 16)
                        height: Math.max(spreadViewport.height, pageView.height + 16)
                        TapHandler {
                            onPressedChanged: if (pressed && root.readingLayout === "two-page") root.activeSpreadPage = root.spreadStartPage
                        }
                    }

                    Item {
                        id: secondSpreadCell
                        visible: root.spreadStartPage + 1 < root.pageCount
                        width: visible ? Math.max(spreadViewport.width / 2 - 6, spreadSecondView.width + 16) : 0
                        height: Math.max(spreadViewport.height, spreadSecondView.height + 16)
                        TapHandler {
                            onPressedChanged: if (pressed && root.readingLayout === "two-page") root.activeSpreadPage = root.spreadStartPage + 1
                        }
                    }
                }
            }

            PdfPageView {
                id: pageView
                parent: root.readingLayout === "two-page" ? firstSpreadCell : documentViewport.contentItem
                document: pdfDocument
                zoomEnabled: false
                color: "#ffffff"
                border.width: 1
                border.color: "#d6dbe3"
                x: root.readingLayout === "two-page" ? (parent.width - width) / 2 : Math.max(0, (documentViewport.width - width) / 2)
                y: root.readingLayout === "two-page" ? (parent.height - height) / 2 : Math.max(0, (documentViewport.height - height) / 2)
                visible: root.readingLayout !== "continuous"

                MarkupCanvas {
                    id: markupLayer
                    anchors.fill: parent
                    z: 100
                    activeTool: root.activeTool
                    inkColor: root.markColor
                    strokeScale: root.strokeScale
                    onMarkupChanged: root.storeMarkupForSourcePage(
                        root.readingLayout === "two-page" ? root.pageOrder[root.spreadStartPage] : pageView.currentPage,
                        markupLayer.annotations
                    )
                    onTextRequested: function(x, y) { root.textRequested(x, y) }
                    onTextSelectionStarted: function(x, y) { root.beginTextAnnotationSelection("primary", pageView.currentPage, x, y) }
                    onTextSelectionMoved: function(x, y) { root.updateTextAnnotationSelection("primary", x, y) }
                    onTextSelectionFinished: root.finishTextAnnotationSelection("primary")
                    onSignatureBoxRequested: function(x1, y1, x2, y2) {
                        const displayPage = root.readingLayout === "two-page" ? root.spreadStartPage : root.currentPage
                        root.digitalSignatureBoxRequested(displayPage, x1, y1, x2, y2, root.pageRotation)
                    }
                }
            }

            PdfPageView {
                id: spreadSecondView
                parent: secondSpreadCell
                document: pdfDocument
                zoomEnabled: false
                color: "#ffffff"
                border.width: 1
                border.color: "#d6dbe3"
                x: (parent.width - width) / 2
                y: (parent.height - height) / 2
                visible: root.readingLayout === "two-page" && root.spreadStartPage + 1 < root.pageCount

                MarkupCanvas {
                    id: spreadSecondMarkup
                    anchors.fill: parent
                    z: 100
                    activeTool: root.activeTool
                    inkColor: root.markColor
                    strokeScale: root.strokeScale
                    onMarkupChanged: root.storeMarkupForSourcePage(root.pageOrder[root.spreadStartPage + 1], spreadSecondMarkup.annotations)
                    onTextRequested: function(x, y) { root.textRequested(x, y) }
                    onTextSelectionStarted: function(x, y) { root.beginTextAnnotationSelection("secondary", spreadSecondView.currentPage, x, y) }
                    onTextSelectionMoved: function(x, y) { root.updateTextAnnotationSelection("secondary", x, y) }
                    onTextSelectionFinished: root.finishTextAnnotationSelection("secondary")
                    onSignatureBoxRequested: function(x1, y1, x2, y2) {
                        root.digitalSignatureBoxRequested(root.spreadStartPage + 1, x1, y1, x2, y2, 0)
                    }
                }
            }

            PdfMultiPageView {
                id: continuousView
                anchors.fill: parent
                visible: root.readingLayout === "continuous"
                document: pdfDocument
                pageRotation: 0
                searchString: root.searchText
                onWidthChanged: Qt.callLater(root.updateFit)
                onHeightChanged: Qt.callLater(root.updateFit)
            }
        }
    }

    Connections {
        target: pageView
        function onCurrentPageChanged() {
            if (root.syncingSpread) return
            if (root.readingLayout === "two-page") {
                const displayPage = root.pageOrder.indexOf(pageView.currentPage)
                if (displayPage >= 0) root.syncSpread(displayPage)
            } else if (root.readingLayout === "single") {
                const rotation = root.pageRotations[String(pageView.currentPage)] || 0
                if (pageView.rotation !== rotation) pageView.rotation = rotation
                root.loadVisibleMarkup()
                Qt.callLater(root.updateFit)
            }
        }
    }

    Connections {
        target: spreadSecondView
        function onCurrentPageChanged() {
            if (root.syncingSpread || root.readingLayout !== "two-page") return
            const displayPage = root.pageOrder.indexOf(spreadSecondView.currentPage)
            if (displayPage >= 0) root.syncSpread(displayPage)
        }
    }

    onWidthChanged: Qt.callLater(updateFit)
    onHeightChanged: Qt.callLater(updateFit)
    onSearchTextChanged: {
        pageView.searchString = searchText
        spreadSecondView.searchString = searchText
        continuousView.searchString = searchText
    }
    onActiveToolChanged: if (activeTool !== "select" && readingLayout !== "single") setReadingLayout("single")
}
