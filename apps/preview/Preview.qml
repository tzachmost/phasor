import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../shell/theme" as Theme

ApplicationWindow {
    id: root

    width: 1240
    height: 820
    minimumWidth: 980
    minimumHeight: 620
    visible: true
    color: Theme.Tokens.background
    title: fileName.length > 0 ? fileName + " — Preview" : "Preview — Phasor"

    property string sourcePath: ""
    property url sourceUrl: ""
    property string fileName: ""
    property bool isPdf: sourcePath.toLowerCase().endsWith(".pdf")
    property string activeTool: "select"
    property color markColor: "#8bd5ca"
    property int markColorIndex: 0
    property real strokeScale: 0.006
    property string exportFormat: "PNG"
    property bool preserveAspect: true
    property string searchText: ""
    property string saveStatus: ""
    property string markupLoadPath: ""
    property var loadedMarkup: ({})
    property var pendingTextPosition: ({ x: 0, y: 0 })
    property string helperPath: Quickshell.env("PHASOR_PREVIEW_ROOT") + "/apps/preview/markup_store.py"
    property string documentOpsPath: Quickshell.env("PHASOR_PREVIEW_ROOT") + "/apps/preview/document_ops.py"

    function pathFromUrl(value) {
        let path = String(value)
        if (path.startsWith("file://")) path = path.substring(7)
        try { return decodeURIComponent(path) } catch (error) { return path }
    }

    function urlFromPath(path) {
        if (/^[a-z][a-z0-9+.-]*:\/\//i.test(path)) return path
        return "file://" + path.split("/").map(function(part) { return encodeURIComponent(part) }).join("/")
    }

    function nameFromPath(path) {
        const parts = path.split("/")
        return parts.length > 0 ? parts[parts.length - 1] : path
    }

    function openFile(value) {
        const incoming = String(value || "")
        if (incoming.length === 0) return
        const isUrl = /^[a-z][a-z0-9+.-]*:\/\//i.test(incoming)
        sourceUrl = isUrl ? incoming : urlFromPath(incoming)
        sourcePath = pathFromUrl(sourceUrl)
        fileName = nameFromPath(sourcePath)
        searchText = ""
        saveStatus = ""
        loadedMarkup = ({})
        activeTool = "select"
        autosaveTimer.stop()
        if (viewerLoader.item && viewerLoader.item.resetDocument) viewerLoader.item.resetDocument()
        if (viewerLoader.item && viewerLoader.item.loadMarkup) viewerLoader.item.loadMarkup(loadedMarkup)
        markupLoadPath = sourcePath
        loadProcess.exec(["python3", helperPath, "load", sourcePath])
    }

    function zoomBy(factor) {
        if (viewerLoader.item && viewerLoader.item.zoomBy) viewerLoader.item.zoomBy(factor)
    }

    function fitDocument() {
        if (viewerLoader.item && viewerLoader.item.fit) viewerLoader.item.fit()
    }

    function rotateDocument(delta) {
        if (viewerLoader.item && viewerLoader.item.rotate) viewerLoader.item.rotate(delta)
    }

    function saveMarkup() {
        if (!sourcePath || !viewerLoader.item || !viewerLoader.item.serializeMarkup) return
        if (root.isPdf && viewerLoader.item.sourcePage < 0) return
        saveProcess.exec([
            "python3",
            helperPath,
            "save",
            sourcePath,
            JSON.stringify(viewerLoader.item.serializeMarkup())
        ])
        saveStatus = "Saving markup…"
    }

    function openExportDialog() {
        if (!sourcePath || !viewerLoader.item) return
        exportOptionsDialog.open()
    }

    function chooseExportDestination() {
        exportOptionsDialog.close()
        exportFileDialog.open()
    }

    function exportTo(value) {
        if (!sourcePath || !viewerLoader.item || !viewerLoader.item.serializeMarkup) return
        let output = pathFromUrl(value)
        const suffix = root.isPdf ? "pdf" : root.exportFormat.toLowerCase() === "jpeg" ? "jpg" : root.exportFormat.toLowerCase()
        if (!/\.[^/]+$/.test(output)) output += "." + suffix
        const options = { markup: viewerLoader.item.serializeMarkup() }
        if (!root.isPdf) {
            options.crop = viewerLoader.item.cropRect || null
            options.rotation = viewerLoader.item.rotation || 0
            options.width = imageWidthInput.text
            options.height = imageHeightInput.text
            options.preserve_aspect = root.preserveAspect
            options.quality = imageQualityInput.value
        }
        exportProcess.exec([
            "python3",
            root.documentOpsPath,
            root.isPdf ? "pdf" : "image",
            root.sourcePath,
            output,
            JSON.stringify(options)
        ])
        saveStatus = "Exporting a copy…"
    }

    function setMarkColor(color) {
        markColor = color
    }

    function addText(text) {
        if (viewerLoader.item && viewerLoader.item.addText) {
            viewerLoader.item.addText(pendingTextPosition.x, pendingTextPosition.y, text)
        }
    }

    component ToolAction: Button {
        id: action
        property bool active: false
        property bool compact: false
        implicitHeight: 36
        implicitWidth: compact ? 40 : Math.max(62, text.length * 7 + 26)
        padding: 10
        background: Rectangle {
            radius: 10
            color: action.active ? Theme.Tokens.surfaceRaised : action.down ? Theme.Tokens.surfaceRaised : action.hovered ? Theme.Tokens.surface : "transparent"
            border.width: action.active ? 1 : 0
            border.color: action.active ? Theme.Tokens.accent : "transparent"
        }
        contentItem: Text {
            text: action.text
            color: action.active ? Theme.Tokens.accent : action.enabled ? Theme.Tokens.textPrimary : Theme.Tokens.textSecondary
            font.pixelSize: 12
            font.weight: action.active ? Font.DemiBold : Font.Medium
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }

    FileDialog {
        id: fileDialog
        title: "Open a document or image"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Documents and images (*.pdf *.png *.jpg *.jpeg *.webp *.svg *.bmp *.gif *.tif *.tiff)", "All files (*)"]
        onAccepted: root.openFile(selectedFile)
    }

    FileDialog {
        id: exportFileDialog
        title: root.isPdf ? "Export PDF copy" : "Export image copy"
        fileMode: FileDialog.SaveFile
        defaultSuffix: root.isPdf ? "pdf" : root.exportFormat.toLowerCase() === "jpeg" ? "jpg" : root.exportFormat.toLowerCase()
        nameFilters: root.isPdf
            ? ["PDF document (*.pdf)"]
            : root.exportFormat === "JPEG" ? ["JPEG image (*.jpg *.jpeg)"]
            : [root.exportFormat + " image (*." + (root.exportFormat === "TIFF" ? "tif *.tiff" : root.exportFormat.toLowerCase()) + ")"]
        onAccepted: root.exportTo(selectedFile)
    }

    onSourceUrlChanged: {
        if (viewerLoader.item) viewerLoader.item.source = sourceUrl
    }
    onActiveToolChanged: {
        if (viewerLoader.item && viewerLoader.item.activeTool !== undefined) viewerLoader.item.activeTool = activeTool
    }
    onMarkColorChanged: {
        if (viewerLoader.item && viewerLoader.item.markColor !== undefined) viewerLoader.item.markColor = markColor
    }
    onStrokeScaleChanged: {
        if (viewerLoader.item && viewerLoader.item.strokeScale !== undefined) viewerLoader.item.strokeScale = strokeScale
    }
    onSearchTextChanged: {
        if (viewerLoader.item && viewerLoader.item.searchText !== undefined) viewerLoader.item.searchText = searchText
    }

    Process {
        id: loadProcess
        command: ["python3"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.markupLoadPath !== root.sourcePath) return
                try {
                    root.loadedMarkup = JSON.parse(text)
                    if (root.loadedMarkup.error) root.saveStatus = root.loadedMarkup.error
                    else root.saveStatus = root.hasMarkup(root.loadedMarkup) ? "Markup loaded" : ""
                    if (viewerLoader.item && viewerLoader.item.loadMarkup) viewerLoader.item.loadMarkup(root.loadedMarkup)
                } catch (error) {
                    root.loadedMarkup = ({})
                    root.saveStatus = "Could not read saved markup"
                }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.length > 0) console.warn("Preview markup load:", text) }
    }

    Process {
        id: saveProcess
        command: ["python3"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text)
                    root.saveStatus = result.ok ? "Markup saved beside the document" : (result.error || "Could not save markup")
                } catch (error) {
                    root.saveStatus = "Could not save markup"
                }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.length > 0) console.warn("Preview markup save:", text) }
    }

    Process {
        id: exportProcess
        command: ["python3"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text)
                    root.saveStatus = result.ok
                        ? "Exported " + root.nameFromPath(result.path) + (result.pages ? " · " + result.pages + " pages" : "")
                        : (result.error || "Could not export this file")
                } catch (error) {
                    root.saveStatus = "Could not export this file"
                }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.length > 0) console.warn("Preview export:", text) }
    }

    Timer {
        id: autosaveTimer
        interval: 650
        repeat: false
        onTriggered: root.saveMarkup()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 62
            color: Theme.Tokens.surface

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                spacing: 7

                ColumnLayout {
                    Layout.preferredWidth: 152
                    spacing: 1
                    Text {
                        text: "PHASOR"
                        color: Theme.Tokens.textSecondary
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 1.6
                    }
                    Text {
                        text: "Preview"
                        color: Theme.Tokens.textPrimary
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                    }
                }

                Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 30; color: Theme.Tokens.separator }

                ToolAction { text: "Open"; onClicked: fileDialog.open() }
                ToolAction { text: "Pages"; visible: root.isPdf; active: Boolean(viewerLoader.item && viewerLoader.item.showThumbnails); onClicked: if (viewerLoader.item) viewerLoader.item.showThumbnails = !viewerLoader.item.showThumbnails }

                Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 26; color: Theme.Tokens.separator }

                ToolAction { text: "Select"; active: root.activeTool === "select"; onClicked: root.activeTool = "select" }
                ToolAction { text: "Pen"; active: root.activeTool === "pen"; onClicked: root.activeTool = "pen" }
                ToolAction { text: "Highlight"; active: root.activeTool === "highlight"; onClicked: root.activeTool = "highlight" }
                ToolAction { text: "Shape"; active: root.activeTool === "rectangle"; onClicked: root.activeTool = "rectangle" }
                ToolAction { text: "Text"; active: root.activeTool === "text"; onClicked: root.activeTool = "text" }
                ToolAction { text: "Crop"; visible: !root.isPdf; active: root.activeTool === "crop"; onClicked: root.activeTool = root.activeTool === "crop" ? "select" : "crop" }

                ToolAction { text: "Color"; onClicked: {
                    const colors = ["#8bd5ca", "#f3c969", "#ed8796", "#a8c7fa", "#f0f1f4"]
                    root.markColorIndex = (root.markColorIndex + 1) % colors.length
                    root.setMarkColor(colors[root.markColorIndex])
                } }
                ToolAction { text: "Undo"; enabled: Boolean(viewerLoader.item); onClicked: if (viewerLoader.item && viewerLoader.item.undo) viewerLoader.item.undo() }
                ToolAction { text: "Save marks"; enabled: Boolean(root.sourcePath && viewerLoader.item && (!root.isPdf || viewerLoader.item.sourcePage >= 0)); onClicked: root.saveMarkup() }
                ToolAction { id: pageActionsButton; text: "Page ▾"; visible: root.isPdf; onClicked: pageMenu.popup(pageActionsButton, Qt.point(0, pageActionsButton.height)) }
                ToolAction { text: "Export"; enabled: Boolean(root.sourcePath && viewerLoader.item && (!root.isPdf || viewerLoader.item.pageCount > 0)); onClicked: root.openExportDialog() }

                Item { Layout.fillWidth: true }

                ToolAction { text: "↶"; compact: true; enabled: Boolean(root.sourcePath); onClicked: root.rotateDocument(-90) }
                ToolAction { text: "−"; compact: true; enabled: Boolean(root.sourcePath); onClicked: root.zoomBy(0.8) }
                Text {
                    Layout.preferredWidth: 48
                    text: viewerLoader.item ? viewerLoader.item.zoomPercent + "%" : "—"
                    color: Theme.Tokens.textSecondary
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                }
                ToolAction { text: "+"; compact: true; enabled: Boolean(root.sourcePath); onClicked: root.zoomBy(1.25) }
                ToolAction { text: "Fit"; enabled: Boolean(root.sourcePath); onClicked: root.fitDocument() }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.Tokens.separator }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            spacing: 10

            Text {
                Layout.fillWidth: true
                text: root.sourcePath ? root.fileName : "Open a PDF or image to get started"
                color: root.sourcePath ? Theme.Tokens.textPrimary : Theme.Tokens.textSecondary
                font.pixelSize: 12
                font.weight: Font.Medium
                elide: Text.ElideMiddle
            }

            RowLayout {
                visible: root.isPdf
                spacing: 6
                ToolAction { text: "‹"; compact: true; enabled: Boolean(viewerLoader.item && viewerLoader.item.currentPage > 0); onClicked: viewerLoader.item.goToPage(viewerLoader.item.currentPage - 1) }
                TextField {
                    id: pageInput
                    Layout.preferredWidth: 50
                    Layout.preferredHeight: 32
                    text: viewerLoader.item && viewerLoader.item.pageCount > 0 ? String(viewerLoader.item.currentPage + 1) : "—"
                    horizontalAlignment: TextInput.AlignHCenter
                    color: Theme.Tokens.textPrimary
                    selectByMouse: true
                    background: Rectangle { radius: 8; color: Theme.Tokens.surfaceRaised; border.color: pageInput.activeFocus ? Theme.Tokens.accent : Theme.Tokens.separator }
                    onAccepted: {
                        if (viewerLoader.item && viewerLoader.item.goToPage) viewerLoader.item.goToPage(Number(text) - 1)
                        focus = false
                    }
                    Connections {
                        target: viewerLoader.item
                        ignoreUnknownSignals: true
                        function onCurrentPageChanged() {
                            if (!pageInput.activeFocus && viewerLoader.item) pageInput.text = String(viewerLoader.item.currentPage + 1)
                        }
                        function onPageOrderChanged() {
                            if (!pageInput.activeFocus && viewerLoader.item) pageInput.text = String(viewerLoader.item.currentPage + 1)
                        }
                    }
                }
                Text { text: "/ " + (viewerLoader.item ? viewerLoader.item.pageCount : 0); color: Theme.Tokens.textSecondary; font.pixelSize: 11 }
                ToolAction { text: "›"; compact: true; enabled: Boolean(viewerLoader.item && viewerLoader.item.currentPage + 1 < viewerLoader.item.pageCount); onClicked: viewerLoader.item.goToPage(viewerLoader.item.currentPage + 1) }
            }

            TextField {
                id: searchInput
                visible: root.isPdf
                Layout.preferredWidth: 210
                Layout.preferredHeight: 32
                placeholderText: "Find in PDF"
                text: root.searchText
                color: Theme.Tokens.textPrimary
                onTextChanged: root.searchText = text
                background: Rectangle { radius: 8; color: Theme.Tokens.surfaceRaised; border.color: searchInput.activeFocus ? Theme.Tokens.accent : Theme.Tokens.separator }
            }
            ToolAction { text: "Find ‹"; visible: root.isPdf; enabled: Boolean(viewerLoader.item && root.searchText.length > 0); onClicked: viewerLoader.item.searchBack() }
            ToolAction { text: "Find ›"; visible: root.isPdf; enabled: Boolean(viewerLoader.item && root.searchText.length > 0); onClicked: viewerLoader.item.searchForward() }
            ToolAction { text: "Copy text"; visible: root.isPdf; enabled: Boolean(viewerLoader.item); onClicked: if (viewerLoader.item && viewerLoader.item.copySelection) viewerLoader.item.copySelection() }
            Menu {
                id: pageMenu
                MenuItem { text: "Move page earlier"; enabled: Boolean(viewerLoader.item && viewerLoader.item.currentPage > 0); onTriggered: viewerLoader.item.moveCurrentPage(-1) }
                MenuItem { text: "Move page later"; enabled: Boolean(viewerLoader.item && viewerLoader.item.currentPage + 1 < viewerLoader.item.pageCount); onTriggered: viewerLoader.item.moveCurrentPage(1) }
                MenuSeparator { }
                MenuItem { text: "Exclude page from export"; enabled: Boolean(viewerLoader.item && viewerLoader.item.pageCount > 1); onTriggered: viewerLoader.item.excludeCurrentPage() }
                MenuItem { text: "Reset page operations"; enabled: Boolean(viewerLoader.item); onTriggered: viewerLoader.item.resetPageOperations() }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.Tokens.separator }

        Item {
            id: contentArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            Rectangle {
                anchors.fill: parent
                color: Theme.Tokens.dark ? "#111318" : "#e3e6ec"
            }

            Loader {
                id: viewerLoader
                anchors.fill: parent
                active: root.sourcePath.length > 0
                source: !active ? "" : root.isPdf ? Qt.resolvedUrl("PdfDocumentView.qml") : Qt.resolvedUrl("ImageDocumentView.qml")
                onLoaded: {
                    if (item) {
                        item.source = root.sourceUrl
                        if (item.activeTool !== undefined) item.activeTool = root.activeTool
                        if (item.markColor !== undefined) item.markColor = root.markColor
                        if (item.strokeScale !== undefined) item.strokeScale = root.strokeScale
                        if (root.isPdf && item.searchText !== undefined) item.searchText = root.searchText
                        if (item.loadMarkup) item.loadMarkup(root.loadedMarkup)
                    }
                }
                onStatusChanged: {
                    if (status === Loader.Error && root.isPdf) {
                        root.saveStatus = "PDF viewing needs QtQuick.Pdf (the Qt PDF package)."
                        console.warn("Preview cannot load QtQuick.Pdf; install the optional Qt PDF runtime module.")
                    }
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: Math.min(440, parent.width - 44)
                height: 228
                radius: 22
                color: Theme.Tokens.surface
                border.color: Theme.Tokens.separator
                visible: root.sourcePath.length === 0

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 26
                    spacing: 10
                    Text { text: "◫"; color: Theme.Tokens.accent; font.pixelSize: 36; Layout.alignment: Qt.AlignHCenter }
                    Text {
                        text: "A closer look at your files"
                        color: Theme.Tokens.textPrimary
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Text {
                        text: "View PDFs and images, find text, and add editable markup that stays beside the original."
                        color: Theme.Tokens.textSecondary
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        Layout.fillWidth: true
                    }
                    ToolAction { text: "Open a file"; Layout.alignment: Qt.AlignHCenter; onClicked: fileDialog.open() }
                }
            }

            DropArea {
                anchors.fill: parent
                onDropped: function(drop) {
                    if (drop.urls && drop.urls.length > 0) root.openFile(drop.urls[0])
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            color: Theme.Tokens.surface

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                Text {
                    Layout.fillWidth: true
                    text: root.sourcePath && viewerLoader.item
                        ? viewerLoader.item.documentStatus + (root.isPdf ? " · PDF" : root.activeTool === "crop" ? " · Drag to select crop" : " · Image")
                        : "PDF · PNG · JPEG · SVG · WebP"
                    color: Theme.Tokens.textSecondary
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
                Text {
                    text: root.saveStatus
                    color: root.saveStatus.indexOf("Could not") === 0 || root.saveStatus.indexOf("needs") >= 0 ? Theme.Tokens.warning : Theme.Tokens.textSecondary
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }
        }
    }

    Dialog {
        id: textDialog
        title: "Add text markup"
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        onOpened: textInput.forceActiveFocus()
        onAccepted: root.addText(textInput.text)

        contentItem: ColumnLayout {
            implicitWidth: 360
            spacing: 10
            Text { text: "The text stays editable in the Preview markup sidecar."; color: Theme.Tokens.textSecondary; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            TextField { id: textInput; Layout.fillWidth: true; placeholderText: "Type a note"; onAccepted: textDialog.accept() }
        }
    }

    Dialog {
        id: exportOptionsDialog
        title: root.isPdf ? "Export PDF" : "Export image"
        modal: true
        standardButtons: Dialog.Cancel

        contentItem: ColumnLayout {
            implicitWidth: 420
            spacing: 12

            Text {
                Layout.fillWidth: true
                text: root.isPdf
                    ? "Save a new PDF with your markup drawn onto each page. Page order, excluded pages, and rotations are applied to the exported copy. Text and original page content stay searchable."
                    : "Save a new image with markup applied. The original stays untouched. A crop selection is applied before rotation and resizing."
                color: Theme.Tokens.textSecondary
                wrapMode: Text.WordWrap
            }

            GridLayout {
                visible: !root.isPdf
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 12
                rowSpacing: 9

                Text { text: "Maximum width"; color: Theme.Tokens.textPrimary; font.pixelSize: 12 }
                TextField { id: imageWidthInput; Layout.fillWidth: true; placeholderText: "Keep original"; inputMethodHints: Qt.ImhDigitsOnly; validator: IntValidator { bottom: 0; top: 32768 } }
                Text { text: "Maximum height"; color: Theme.Tokens.textPrimary; font.pixelSize: 12 }
                TextField { id: imageHeightInput; Layout.fillWidth: true; placeholderText: "Keep original"; inputMethodHints: Qt.ImhDigitsOnly; validator: IntValidator { bottom: 0; top: 32768 } }
                Text { text: "Format"; color: Theme.Tokens.textPrimary; font.pixelSize: 12 }
                ComboBox {
                    id: formatInput
                    Layout.fillWidth: true
                    model: ["PNG", "JPEG", "WebP", "TIFF", "BMP"]
                    currentIndex: Math.max(0, ["PNG", "JPEG", "WebP", "TIFF", "BMP"].indexOf(root.exportFormat))
                    onActivated: root.exportFormat = currentText
                }
                Text { text: "Quality"; visible: root.exportFormat === "JPEG" || root.exportFormat === "WebP"; color: Theme.Tokens.textPrimary; font.pixelSize: 12 }
                SpinBox { id: imageQualityInput; visible: root.exportFormat === "JPEG" || root.exportFormat === "WebP"; from: 1; to: 100; value: 92; editable: true; Layout.fillWidth: true }
                CheckBox { text: "Preserve aspect ratio"; checked: root.preserveAspect; visible: !root.isPdf; Layout.columnSpan: 2; onToggled: root.preserveAspect = checked }
                RowLayout {
                    visible: Boolean(viewerLoader.item && viewerLoader.item.cropRect)
                    Layout.columnSpan: 2
                    Text { text: "A crop selection will be applied."; color: Theme.Tokens.accent; font.pixelSize: 12; Layout.fillWidth: true }
                    Button { text: "Clear"; onClicked: viewerLoader.item.clearCrop() }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: "Choose destination…"; highlighted: true; onClicked: root.chooseExportDestination() }
            }
        }
    }

    Shortcut { sequence: "Ctrl+O"; onActivated: fileDialog.open() }
    Shortcut { sequence: "Ctrl+S"; onActivated: root.saveMarkup() }
    Shortcut { sequence: "Ctrl++"; onActivated: root.zoomBy(1.25) }
    Shortcut { sequence: "Ctrl+="; onActivated: root.zoomBy(1.25) }
    Shortcut { sequence: "Ctrl+-"; onActivated: root.zoomBy(0.8) }
    Shortcut { sequence: "Escape"; onActivated: root.activeTool = "select" }

    Connections {
        target: viewerLoader.item
        ignoreUnknownSignals: true
        function onMarkupChanged() {
            root.saveStatus = "Markup changed"
            autosaveTimer.restart()
        }
        function onTextRequested(x, y) {
            root.pendingTextPosition = { x: x, y: y }
            textInput.text = ""
            textDialog.open()
        }
    }

    function hasMarkup(value) {
        if (!value) return false
        if (value.kind === "image") return Boolean(value.annotations && value.annotations.length)
        if (value.kind === "pdf") {
            for (const page of Object.keys(value.pages || {})) {
                if (value.pages[page] && value.pages[page].length) return true
            }
            if (value.page_order && value.page_order.some(function(page, index) { return page !== index })) return true
            for (const page of Object.keys(value.page_rotations || {})) {
                if (value.page_rotations[page] !== 0) return true
            }
        }
        return false
    }

    Component.onCompleted: {
        const initialFile = String(Quickshell.env("PHASOR_PREVIEW_FILE") || "")
        if (initialFile.length > 0) openFile(initialFile)
    }
}
