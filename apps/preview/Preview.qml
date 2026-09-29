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
    property string formsLoadPath: ""
    property var formFields: []
    property string formsStatus: ""
    property bool formsReady: false
    property bool markupReady: true
    property bool deferredMarkupSave: false
    property string pendingFileToOpen: ""
    property var printerNames: []
    property string defaultPrinter: ""
    property string printerStatus: ""
    property var mergeInputPaths: []
    property int signingPageIndex: -1
    property int signingRotation: 0
    property var signingBox: []
    property string signingPasswordPending: ""
    property var signingOptionsPending: ({})
    property var loadedMarkup: ({})
    property var documentInfo: ({})
    property string infoLoadPath: ""
    property bool infoReady: true
    readonly property var documentInfoRows: {
        const info = root.documentInfo || ({})
        if (info.error) return [{ label: "Status", value: info.error }]
        if (Object.keys(info).length === 0) return [{ label: "Status", value: "Loading document information…" }]

        const rows = [
            { label: "Name", value: info.name },
            { label: "Location", value: info.path },
            { label: "Type", value: info.kind === "pdf" ? "PDF document" : info.format || "Image" },
            { label: "File size", value: root.formatBytes(info.size_bytes) },
            { label: "Modified", value: info.modified }
        ]
        if (info.kind === "pdf") {
            rows.push({ label: "Pages", value: info.page_count === undefined ? "Password protected" : info.page_count })
            if (info.pdf_version) rows.push({ label: "PDF version", value: info.pdf_version })
            if (info.encrypted) rows.push({ label: "Security", value: "Password protected" })
            for (const key of ["title", "author", "subject", "keywords", "creator", "producer", "created", "modified_document"]) {
                if (info[key]) rows.push({ label: key.replace(/_/g, " "), value: info[key] })
            }
        } else if (info.kind === "image") {
            if (info.width && info.height) rows.push({ label: "Dimensions", value: info.width + " × " + info.height + " pixels" })
            if (info.mode) rows.push({ label: "Color mode", value: info.mode })
            if (info.metadata_error) rows.push({ label: "Details", value: info.metadata_error })
            if (info.frames > 1) rows.push({ label: "Animation", value: info.frames + " frames" })
            if (info.dpi) rows.push({ label: "Resolution", value: info.dpi[0] + " × " + info.dpi[1] + " dpi" })
            if (info.camera_make) rows.push({ label: "Camera", value: info.camera_make + (info.camera_model ? " " + info.camera_model : "") })
            if (info.captured) rows.push({ label: "Captured", value: info.captured })
            if (info.exif_fields) rows.push({ label: "EXIF fields", value: info.exif_fields })
        }
        return rows.filter(function(row) { return row.value !== undefined && row.value !== null && String(row.value).length > 0 })
    }
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

    function formatBytes(value) {
        let size = Number(value)
        if (!Number.isFinite(size) || size < 0) return "Unknown"
        if (size < 1024) return size + " B"
        const units = ["KB", "MB", "GB", "TB"]
        size /= 1024
        let index = 0
        while (size >= 1024 && index < units.length - 1) {
            size /= 1024
            index++
        }
        return size.toFixed(size < 10 ? 1 : 0) + " " + units[index]
    }

    function openDocumentInfo() {
        if (sourcePath) documentInfoDialog.open()
    }

    function openFile(value) {
        const incoming = String(value || "")
        if (incoming.length === 0) return
        const isUrl = /^[a-z][a-z0-9+.-]*:\/\//i.test(incoming)
        const nextSourceUrl = isUrl ? incoming : urlFromPath(incoming)
        const nextSourcePath = pathFromUrl(nextSourceUrl)
        if (sourcePath && (!markupReady || (root.isPdf && !formsReady) || !infoReady)) {
            pendingFileToOpen = nextSourcePath
            return
        }
        if (sourcePath && (autosaveTimer.running || deferredMarkupSave)) {
            autosaveTimer.stop()
            saveMarkup()
        }
        signingOptionsDialog.close()
        signingCertificateDialog.close()
        signingOutputDialog.close()
        signingPasswordInput.clear()
        signingPasswordPending = ""
        signingOptionsPending = ({})
        signingPageIndex = -1
        sourcePath = nextSourcePath
        sourceUrl = nextSourceUrl
        fileName = nameFromPath(sourcePath)
        searchText = ""
        saveStatus = ""
        loadedMarkup = ({})
        documentInfo = ({})
        infoReady = false
        formFields = []
        formsStatus = isPdf ? "Loading form fields…" : ""
        formsReady = !isPdf
        markupReady = false
        deferredMarkupSave = false
        pendingFileToOpen = ""
        activeTool = "select"
        autosaveTimer.stop()
        if (viewerLoader.item && viewerLoader.item.resetDocument) viewerLoader.item.resetDocument()
        if (viewerLoader.item && viewerLoader.item.loadMarkup) viewerLoader.item.loadMarkup(loadedMarkup)
        applyFormFieldMetadata()
        markupLoadPath = sourcePath
        loadProcess.exec(["python3", helperPath, "load", sourcePath])
        if (isPdf) {
            formsLoadPath = sourcePath
            formsProcess.exec(["python3", documentOpsPath, "forms", sourcePath])
        }
        infoLoadPath = sourcePath
        infoProcess.exec(["python3", documentOpsPath, "inspect", sourcePath])
    }

    function continueAfterDocumentReady() {
        if (!markupReady || (root.isPdf && !formsReady) || !infoReady) return

        const pending = pendingFileToOpen
        pendingFileToOpen = ""
        if (pending.length > 0 && pending !== sourcePath) {
            if (autosaveTimer.running || deferredMarkupSave) {
                autosaveTimer.stop()
                saveMarkup()
            }
            Qt.callLater(function() { root.openFile(pending) })
            return
        }

        if (deferredMarkupSave) autosaveTimer.restart()
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
        if (!markupReady || (root.isPdf && !formsReady)) {
            deferredMarkupSave = true
            return
        }
        deferredMarkupSave = false
        saveProcess.sourcePathAtStart = sourcePath
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
        const options = { markup: viewerLoader.item.serializeMarkup(true) }
        if (!root.isPdf) {
            options.crop = viewerLoader.item.cropRect || null
            options.rotation = viewerLoader.item.rotation || 0
            options.frame_index = viewerLoader.item.currentPage || 0
            options.width = imageWidthInput.text
            options.height = imageHeightInput.text
            options.preserve_aspect = root.preserveAspect
            options.quality = imageQualityInput.value
        }
        exportProcess.inputPayload = JSON.stringify(options)
        exportProcess.exec([
            "python3",
            root.documentOpsPath,
            root.isPdf ? "pdf" : "image",
            root.sourcePath,
            output,
            "-"
        ])
        saveStatus = "Exporting a copy…"
    }

    function formValue(field) {
        const values = viewerLoader.item && viewerLoader.item.formValues ? viewerLoader.item.formValues : ({})
        return Object.prototype.hasOwnProperty.call(values, field.name) ? values[field.name] : field.value
    }

    function setFormValue(field, value) {
        if (viewerLoader.item && viewerLoader.item.setFormValue) viewerLoader.item.setFormValue(field.name, value)
    }

    function applyFormFieldMetadata() {
        if (!viewerLoader.item || !viewerLoader.item.setPasswordFieldNames) return
        const names = root.formFields
            .filter(function(field) { return field.password })
            .map(function(field) { return field.name })
        viewerLoader.item.setPasswordFieldNames(names)
    }

    function beginMerge() {
        if (!root.isPdf || !root.sourcePath || !viewerLoader.item || viewerLoader.item.pageCount < 1) return
        mergeInputDialog.open()
    }

    function beginCertificateSigning() {
        if (!root.isPdf || !viewerLoader.item || viewerLoader.item.currentPage < 0) return
        root.activeTool = "signature_box"
        root.saveStatus = "Drag on the page to place the digital signature."
    }

    function collectSignatureBox(pageIndex, x1, y1, x2, y2, rotation) {
        if (pageIndex < 0) return
        root.signingPageIndex = pageIndex
        root.signingRotation = rotation
        root.signingBox = [x1, y1, x2, y2]
        root.activeTool = "select"
        signingCertificateDialog.open()
    }

    function signTo(value) {
        if (!root.isPdf || !viewerLoader.item || root.signingPageIndex < 0) return
        if (signProcess.running) {
            root.saveStatus = "A PDF signing operation is already running."
            return
        }
        let output = root.pathFromUrl(value)
        if (!/\.pdf$/i.test(output)) output += ".pdf"
        const options = {
            markup: viewerLoader.item.serializeMarkup(true),
            page_index: root.signingPageIndex,
            box: root.signingBox,
            rotation: root.signingRotation,
            reason: signingReasonInput.text,
            location: signingLocationInput.text
        }
        root.signingPasswordPending = signingPasswordInput.text
        root.signingOptionsPending = options
        signingPasswordInput.clear()
        signProcess.exec([
            "python3",
            root.documentOpsPath,
            "sign",
            root.sourcePath,
            output,
            root.pathFromUrl(signingCertificateDialog.selectedFile)
        ])
        signingOptionsDialog.close()
        root.saveStatus = "Signing a new PDF copy…"
    }

    function prepareMerge(files) {
        const paths = [root.sourcePath]
        const seen = Object.create(null)
        seen[root.sourcePath] = true
        for (const file of files) {
            const path = root.pathFromUrl(file)
            if (!path || seen[path]) continue
            seen[path] = true
            paths.push(path)
        }
        if (paths.length < 2) {
            root.saveStatus = "Choose at least one additional PDF to merge."
            return
        }
        root.mergeInputPaths = paths
        mergeOutputDialog.open()
    }

    function mergeTo(value) {
        if (!root.isPdf || !viewerLoader.item || !viewerLoader.item.serializeMarkup) return
        let output = root.pathFromUrl(value)
        if (!/\.pdf$/i.test(output)) output += ".pdf"
        const options = { markup: viewerLoader.item.serializeMarkup(true) }
        mergeProcess.inputPayload = JSON.stringify(options)
        mergeProcess.exec([
            "python3",
            root.documentOpsPath,
            "merge",
            output,
            JSON.stringify(root.mergeInputPaths),
            "-"
        ])
        saveStatus = "Merging " + root.mergeInputPaths.length + " PDFs…"
    }

    function openPrintDialog() {
        if (!sourcePath || !viewerLoader.item) return
        printerStatus = "Checking available printers…"
        printerProcess.exec(["python3", documentOpsPath, "printers"])
        printDialog.open()
    }

    function submitPrint() {
        if (!sourcePath || !viewerLoader.item || !viewerLoader.item.serializeMarkup) return
        const options = {
            markup: viewerLoader.item.serializeMarkup(true),
            printer: printerInput.currentIndex > 0 ? printerInput.currentText : "",
            copies: copyInput.value,
            pages: pageRangeInput.text.trim()
        }
        if (!root.isPdf) {
            options.crop = viewerLoader.item.cropRect || null
            options.rotation = viewerLoader.item.rotation || 0
            options.frame_index = viewerLoader.item.currentPage || 0
        }
        printProcess.inputPayload = JSON.stringify(options)
        printProcess.exec(["python3", documentOpsPath, "print", sourcePath, "-"])
        printDialog.close()
        saveStatus = "Preparing print job…"
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

    FileDialog {
        id: mergeInputDialog
        title: "Choose PDFs to append"
        fileMode: FileDialog.OpenFiles
        nameFilters: ["PDF documents (*.pdf)"]
        onAccepted: root.prepareMerge(selectedFiles)
    }

    FileDialog {
        id: mergeOutputDialog
        title: "Save merged PDF copy"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "pdf"
        nameFilters: ["PDF document (*.pdf)"]
        onAccepted: root.mergeTo(selectedFile)
    }

    FileDialog {
        id: signingCertificateDialog
        title: "Choose a signing certificate"
        fileMode: FileDialog.OpenFile
        nameFilters: ["PKCS#12 certificates (*.p12 *.pfx)", "All files (*)"]
        onAccepted: signingOptionsDialog.open()
    }

    FileDialog {
        id: signingOutputDialog
        title: "Save signed PDF copy"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "pdf"
        nameFilters: ["PDF document (*.pdf)"]
        onAccepted: root.signTo(selectedFile)
        onRejected: signingPasswordInput.clear()
    }

    onSourceUrlChanged: {
        if (viewerLoader.item && viewerLoader.item.source !== undefined
            && Boolean(viewerLoader.item.isPdfView) === root.isPdf) {
            viewerLoader.item.source = sourceUrl
        }
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

    Connections {
        target: viewerLoader.item
        ignoreUnknownSignals: true
        function onDigitalSignatureBoxRequested(pageIndex, x1, y1, x2, y2, rotation) {
            root.collectSignatureBox(pageIndex, x1, y1, x2, y2, rotation)
        }
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
                    root.applyFormFieldMetadata()
                } catch (error) {
                    root.loadedMarkup = ({})
                    root.saveStatus = "Could not read saved markup"
                }
                root.markupReady = true
                root.continueAfterDocumentReady()
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.length > 0) console.warn("Preview markup load:", text) }
    }

    Process {
        id: formsProcess
        command: ["python3"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.formsLoadPath !== root.sourcePath) return
                try {
                    const result = JSON.parse(text)
                    root.formFields = result.fields || []
                    root.formsStatus = result.error
                        || (root.formFields.length > 0 ? root.formFields.length + " fields found" : "This PDF has no editable form fields.")
                    root.formsReady = true
                    root.applyFormFieldMetadata()
                } catch (error) {
                    root.formFields = []
                    root.formsStatus = "Could not read PDF form fields"
                    root.formsReady = true
                }
                root.continueAfterDocumentReady()
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.length > 0) console.warn("Preview forms:", text) }
    }

    Process {
        id: infoProcess
        command: ["python3"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.infoLoadPath !== root.sourcePath) return
                try {
                    root.documentInfo = JSON.parse(text)
                } catch (error) {
                    root.documentInfo = ({ error: "Could not read document information" })
                }
                root.infoReady = true
                root.continueAfterDocumentReady()
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.length > 0) console.warn("Preview document info:", text) }
    }

    Process {
        id: saveProcess
        command: ["python3"]
        property string sourcePathAtStart: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (saveProcess.sourcePathAtStart !== root.sourcePath) return
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
        stdinEnabled: true
        property string inputPayload: ""
        onStarted: {
            exportProcess.write(inputPayload + "\n")
            inputPayload = ""
        }
        onExited: inputPayload = ""
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

    Process {
        id: mergeProcess
        command: ["python3"]
        stdinEnabled: true
        property string inputPayload: ""
        onStarted: {
            mergeProcess.write(inputPayload + "\n")
            inputPayload = ""
        }
        onExited: inputPayload = ""
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text)
                    root.saveStatus = result.ok
                        ? "Merged " + result.documents + " PDFs · " + result.pages + " pages · " + root.nameFromPath(result.path)
                        : (result.error || "Could not merge these PDFs")
                } catch (error) {
                    root.saveStatus = "Could not merge these PDFs"
                }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.length > 0) console.warn("Preview merge:", text) }
    }

    Process {
        id: signProcess
        command: ["python3"]
        stdinEnabled: true
        onStarted: {
            signProcess.write(JSON.stringify({
                password: root.signingPasswordPending,
                options: root.signingOptionsPending
            }) + "\n")
            root.signingPasswordPending = ""
            root.signingOptionsPending = ({})
        }
        onExited: {
            root.signingPasswordPending = ""
            root.signingOptionsPending = ({})
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text)
                    root.saveStatus = result.ok
                        ? "Digitally signed copy saved · page " + result.page + " · " + root.nameFromPath(result.path)
                        : (result.error || "Could not sign this PDF")
                } catch (error) {
                    root.saveStatus = "Could not sign this PDF"
                }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.length > 0) console.warn("Preview PDF signing:", text) }
    }

    Process {
        id: printerProcess
        command: ["python3"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text)
                    root.printerNames = result.printers || []
                    root.defaultPrinter = result.default || ""
                    root.printerStatus = result.error || result.message || ""
                } catch (error) {
                    root.printerNames = []
                    root.defaultPrinter = ""
                    root.printerStatus = "Could not query printers"
                }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.length > 0) console.warn("Preview printers:", text) }
    }

    Process {
        id: printProcess
        command: ["python3"]
        stdinEnabled: true
        property string inputPayload: ""
        onStarted: {
            printProcess.write(inputPayload + "\n")
            inputPayload = ""
        }
        onExited: inputPayload = ""
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text)
                    root.saveStatus = result.ok
                        ? "Sent to " + (result.printer || "the system printer") + (result.job ? " · " + result.job : "")
                        : (result.error || "Could not print this document")
                } catch (error) {
                    root.saveStatus = "Could not print this document"
                }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.length > 0) console.warn("Preview print:", text) }
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
                ToolAction { id: documentToolsButton; text: "More ▾"; enabled: Boolean(root.sourcePath); onClicked: documentToolsMenu.popup(documentToolsButton, Qt.point(0, documentToolsButton.height)) }
                Menu {
                    id: documentToolsMenu
                    MenuItem { text: "Document info…"; onTriggered: root.openDocumentInfo() }
                    MenuSeparator { }
                    MenuItem { text: "Fill PDF forms…"; enabled: root.isPdf; onTriggered: formsDialog.open() }
                    MenuItem { text: root.activeTool === "signature" ? "Stop signing" : "Draw signature"; checkable: true; checked: root.activeTool === "signature"; onTriggered: root.activeTool = root.activeTool === "signature" ? "select" : "signature" }
                    MenuItem { text: "Sign with certificate…"; enabled: Boolean(root.isPdf && viewerLoader.item && viewerLoader.item.pageCount > 0 && !signProcess.running); onTriggered: root.beginCertificateSigning() }
                    MenuSeparator { }
                    MenuItem { text: "Merge PDFs…"; enabled: Boolean(root.isPdf && viewerLoader.item && viewerLoader.item.pageCount > 0); onTriggered: root.beginMerge() }
                    MenuItem { text: "Print…"; enabled: Boolean(root.sourcePath && viewerLoader.item); onTriggered: root.openPrintDialog() }
                }

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
                visible: root.isPdf || Boolean(viewerLoader.item && viewerLoader.item.pageCount > 1)
                spacing: 6
                Text { text: root.isPdf ? "Page" : "Frame"; color: Theme.Tokens.textSecondary; font.pixelSize: 11 }
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
                ToolAction {
                    text: viewerLoader.item && viewerLoader.item.framePlaybackPaused ? "Play" : "Pause"
                    compact: true
                    visible: Boolean(!root.isPdf && viewerLoader.item && viewerLoader.item.hasAnimation)
                    onClicked: if (viewerLoader.item && viewerLoader.item.toggleFramePlayback) viewerLoader.item.toggleFramePlayback()
                }
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
                        root.applyFormFieldMetadata()
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
                        ? viewerLoader.item.documentStatus + (root.activeTool === "signature" ? " · Draw signature" : root.activeTool === "signature_box" ? " · Drag to place certificate signature" : root.isPdf ? " · PDF" : root.activeTool === "crop" ? " · Drag to select crop" : " · Image")
                        : "PDF · PNG · JPEG · SVG · WebP"
                    color: Theme.Tokens.textSecondary
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
                Text {
                    text: root.saveStatus
                    color: root.saveStatus.indexOf("Could not") === 0 || root.saveStatus.indexOf("needs") >= 0 || root.saveStatus.indexOf("already has a digital signature") >= 0 ? Theme.Tokens.warning : Theme.Tokens.textSecondary
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
        id: formsDialog
        title: "Fill PDF forms"
        modal: true
        width: Math.min(640, Math.max(460, root.width - 32))
        height: Math.min(620, Math.max(220, root.height - 32))
        standardButtons: Dialog.Close
        background: Rectangle {
            radius: Theme.Tokens.radiusMedium
            color: Theme.Tokens.surface
            border.color: Theme.Tokens.separator
        }

        contentItem: ColumnLayout {
            implicitWidth: 620
            implicitHeight: 480
            spacing: 10

            Text {
                Layout.fillWidth: true
                text: root.formsStatus || "Loading form fields…"
                color: Theme.Tokens.textSecondary
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            ListView {
                id: formFieldsList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 7
                model: root.formFields

                delegate: Rectangle {
                    id: formFieldRow
                    required property var modelData
                    property var field: modelData
                    width: formFieldsList.width
                    height: fieldContents.implicitHeight + 18
                    radius: Theme.Tokens.radiusSmall
                    color: Theme.Tokens.surfaceRaised
                    border.width: 1
                    border.color: Theme.Tokens.separator

                    ColumnLayout {
                        id: fieldContents
                        anchors.fill: parent
                        anchors.margins: 9
                        spacing: 5

                        Text {
                            Layout.fillWidth: true
                            text: formFieldRow.field.label + (formFieldRow.field.required ? " *" : "")
                                + (formFieldRow.field.pages && formFieldRow.field.pages.length ? " · page " + formFieldRow.field.pages.join(", ") : "")
                            color: Theme.Tokens.textPrimary
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        TextField {
                            visible: formFieldRow.field.type === "text"
                                && (!formFieldRow.field.multiline || formFieldRow.field.password)
                            Layout.fillWidth: true
                            placeholderText: formFieldRow.field.name
                            text: String(root.formValue(formFieldRow.field) || "")
                            readOnly: formFieldRow.field.read_only
                            echoMode: formFieldRow.field.password ? TextInput.Password : TextInput.Normal
                            onEditingFinished: root.setFormValue(formFieldRow.field, text)
                        }

                        ScrollView {
                            visible: formFieldRow.field.type === "text"
                                && formFieldRow.field.multiline && !formFieldRow.field.password
                            Layout.fillWidth: true
                            Layout.preferredHeight: 104
                            clip: true

                            TextArea {
                                placeholderText: formFieldRow.field.name
                                text: String(root.formValue(formFieldRow.field) || "")
                                readOnly: formFieldRow.field.read_only
                                wrapMode: TextEdit.Wrap
                                onEditingFinished: root.setFormValue(formFieldRow.field, text)
                            }
                        }

                        ComboBox {
                            visible: formFieldRow.field.type === "choice" || formFieldRow.field.type === "radio"
                            Layout.fillWidth: true
                            model: formFieldRow.field.options || []
                            textRole: "label"
                            enabled: !formFieldRow.field.read_only
                            editable: formFieldRow.field.editable
                            editText: {
                                if (!formFieldRow.field.editable) return ""
                                const selected = root.formValue(formFieldRow.field)
                                const values = formFieldRow.field.options || []
                                for (let index = 0; index < values.length; index++) {
                                    if (values[index].value === selected) return values[index].label
                                }
                                return String(selected || "")
                            }
                            currentIndex: {
                                const selected = root.formValue(formFieldRow.field)
                                const values = formFieldRow.field.options || []
                                for (let index = 0; index < values.length; index++) {
                                    if (values[index].value === selected) return index
                                }
                                return -1
                            }
                            onActivated: function(index) {
                                const values = formFieldRow.field.options || []
                                if (index >= 0 && index < values.length) root.setFormValue(formFieldRow.field, values[index].value)
                            }
                            onEditTextChanged: {
                                if (editable && activeFocus) root.setFormValue(formFieldRow.field, editText)
                            }
                            onAccepted: {
                                const values = formFieldRow.field.options || []
                                for (let index = 0; index < values.length; index++) {
                                    if (values[index].label === editText) {
                                        root.setFormValue(formFieldRow.field, values[index].value)
                                        return
                                    }
                                }
                                root.setFormValue(formFieldRow.field, editText)
                            }
                        }

                        CheckBox {
                            visible: formFieldRow.field.type === "checkbox"
                            text: "Checked"
                            enabled: !formFieldRow.field.read_only
                            checked: {
                                const selected = root.formValue(formFieldRow.field)
                                return selected !== "" && selected !== "/Off"
                            }
                            onToggled: {
                                const choices = formFieldRow.field.options || []
                                root.setFormValue(formFieldRow.field, checked ? choices.length ? choices[0].value : "/Yes" : "/Off")
                            }
                        }

                        ColumnLayout {
                            visible: formFieldRow.field.type === "multi_choice"
                            Layout.fillWidth: true
                            Repeater {
                                model: formFieldRow.field.options || []
                                delegate: CheckBox {
                                    required property var modelData
                                    text: modelData.label
                                    enabled: !formFieldRow.field.read_only
                                    checked: {
                                        const selected = root.formValue(formFieldRow.field)
                                        return Array.isArray(selected) && selected.indexOf(modelData.value) >= 0
                                    }
                                    onToggled: {
                                        const current = root.formValue(formFieldRow.field)
                                        const selected = Array.isArray(current) ? current.slice() : []
                                        const position = selected.indexOf(modelData.value)
                                        if (checked && position < 0) selected.push(modelData.value)
                                        else if (!checked && position >= 0) selected.splice(position, 1)
                                        root.setFormValue(formFieldRow.field, selected)
                                    }
                                }
                            }
                        }

                        Text {
                            visible: formFieldRow.field.type === "signature"
                            Layout.fillWidth: true
                            text: "Use More → Draw signature to place a visible signature mark on the page."
                            color: Theme.Tokens.textSecondary
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }

                        Text {
                            visible: formFieldRow.field.type === "unsupported"
                            Layout.fillWidth: true
                            text: "This field type cannot be edited in Preview yet."
                            color: Theme.Tokens.textSecondary
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: documentInfoDialog
        title: "Document information"
        modal: true
        width: Math.min(700, Math.max(460, root.width - 32))
        height: Math.min(600, Math.max(280, root.height - 32))
        standardButtons: Dialog.Close
        background: Rectangle {
            radius: Theme.Tokens.radiusMedium
            color: Theme.Tokens.surface
            border.color: Theme.Tokens.separator
        }

        contentItem: ColumnLayout {
            implicitWidth: 660
            implicitHeight: 520
            spacing: 10

            Text {
                Layout.fillWidth: true
                text: root.fileName
                color: Theme.Tokens.textPrimary
                font.pixelSize: 15
                font.weight: Font.DemiBold
                elide: Text.ElideMiddle
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: availableWidth

                ColumnLayout {
                    width: parent.width
                    spacing: 7

                    Repeater {
                        model: root.documentInfoRows
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 12

                            Text {
                                Layout.preferredWidth: 116
                                text: modelData.label
                                color: Theme.Tokens.textSecondary
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                textFormat: Text.PlainText
                            }

                            Text {
                                Layout.fillWidth: true
                                text: String(modelData.value)
                                color: Theme.Tokens.textPrimary
                                font.pixelSize: 11
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: signingOptionsDialog
        title: "Sign PDF with certificate"
        modal: true
        standardButtons: Dialog.Cancel
        onOpened: signingPasswordInput.forceActiveFocus()
        onAccepted: signingOutputDialog.open()
        onRejected: signingPasswordInput.clear()
        background: Rectangle {
            radius: Theme.Tokens.radiusMedium
            color: Theme.Tokens.surface
            border.color: Theme.Tokens.separator
        }

        contentItem: ColumnLayout {
            implicitWidth: 430
            spacing: 10

            Text {
                Layout.fillWidth: true
                text: "Preview creates a visible certificate signature in a new PDF copy. It leaves the source untouched. The signature password is sent to the local signing helper and is not saved."
                color: Theme.Tokens.textSecondary
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                text: "Certificate: " + root.nameFromPath(root.pathFromUrl(signingCertificateDialog.selectedFile))
                color: Theme.Tokens.textPrimary
                font.pixelSize: 12
                elide: Text.ElideMiddle
            }

            TextField {
                id: signingPasswordInput
                Layout.fillWidth: true
                placeholderText: "Certificate password (if required)"
                echoMode: TextInput.Password
                passwordCharacter: "●"
                selectByMouse: true
                onAccepted: signingOptionsDialog.accept()
            }

            TextField {
                id: signingReasonInput
                Layout.fillWidth: true
                placeholderText: "Reason (optional)"
                maximumLength: 256
            }

            TextField {
                id: signingLocationInput
                Layout.fillWidth: true
                placeholderText: "Location (optional)"
                maximumLength: 256
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: "Choose output and sign…"; highlighted: true; onClicked: signingOptionsDialog.accept() }
            }
        }
    }

    Dialog {
        id: printDialog
        title: "Print document"
        modal: true
        standardButtons: Dialog.Cancel
        background: Rectangle {
            radius: Theme.Tokens.radiusMedium
            color: Theme.Tokens.surface
            border.color: Theme.Tokens.separator
        }

        contentItem: ColumnLayout {
            implicitWidth: 440
            spacing: 11

            Text {
                Layout.fillWidth: true
                text: "Preview sends a temporary copy with markup and PDF form values applied. Your source file stays untouched."
                color: Theme.Tokens.textSecondary
                wrapMode: Text.WordWrap
            }

            Text { text: "Printer"; color: Theme.Tokens.textPrimary; font.pixelSize: 12 }
            ComboBox {
                id: printerInput
                Layout.fillWidth: true
                model: ["System default"].concat(root.printerNames)
                currentIndex: root.defaultPrinter ? Math.max(0, root.printerNames.indexOf(root.defaultPrinter) + 1) : 0
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 12
                rowSpacing: 8
                Text { text: "Copies"; color: Theme.Tokens.textPrimary; font.pixelSize: 12 }
                SpinBox { id: copyInput; from: 1; to: 99; value: 1; editable: true; Layout.fillWidth: true }
                Text { text: "Pages"; color: Theme.Tokens.textPrimary; font.pixelSize: 12 }
                TextField { id: pageRangeInput; Layout.fillWidth: true; placeholderText: "All pages, or 1-3,5" }
            }

            Text {
                Layout.fillWidth: true
                text: root.printerStatus || "Page ranges use the order of the prepared document."
                color: root.printerStatus.indexOf("Could not") === 0 || root.printerStatus.indexOf("CUPS") >= 0 ? Theme.Tokens.warning : Theme.Tokens.textSecondary
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: "Print"; highlighted: true; onClicked: root.submitPrint() }
            }
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
    Shortcut { sequence: "Ctrl+I"; onActivated: root.openDocumentInfo() }
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
            if (Object.keys(value.form_values || {}).length > 0) return true
        }
        return false
    }

    Component.onCompleted: {
        const initialFile = String(Quickshell.env("PHASOR_PREVIEW_FILE") || "")
        if (initialFile.length > 0) openFile(initialFile)
    }
}
