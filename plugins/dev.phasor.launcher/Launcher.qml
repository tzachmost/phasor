import QtQuick
import "Search.js" as Search
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "../../shell/theme" as Theme
import "../../shell/components" as Components

Item {
    id: launcher
    width: 1
    height: 1
    property var phasor
    property bool open: false
    property bool closing: false
    property string query: ""
    property int selectedIndex: 0
    property var results: []
    property var spaceItems: []
    property bool showingActions: false
    property var selectedItem: null
    property var searchController: null
    property bool searching: false
    property bool indexing: false
    property bool renamingFile: false
    property bool confirmingTrash: false
    property string proposedName: ""
    property string errorText: ""
    property string infoText: ""

    function loadSpaces() {
        if (!phasor) return
        phasor.request("spaces.list", {}, function(result) {
            if (result.error) {
                spaceItems = []
                return
            }
            spaceItems = result.items || []
        })
    }

    function switchSpace(space) {
        phasor.request("spaces.switch", { id: space.id }, function(result) {
            if (result.error) errorText = result.error
            else loadSpaces()
        })
    }

    function applyFileAction(method, params) {
        phasor.request(method, params, function(result) {
            if (result.error) {
                errorText = result.error
                return
            }
            if (method === "files.share") {
                infoText = "File link copied to the clipboard"
            } else if (method === "files.copy") {
                search()
                infoText = "Copy created: " + result.copied
            } else {
                showingActions = false
                selectedItem = null
                search()
            }
        })
    }

    function search() {
        if (!phasor) return
        if (!searchController) searchController = Search.create(
            function(method, params, callback) { phasor.request(method, params, callback) },
            function(result) {
                searching = false
                results = result.items
                errorText = result.error
                indexing = result.indexing
                selectedIndex = Math.min(selectedIndex, Math.max(0, results.length - 1))
            })
        errorText = ""
        infoText = ""
        searching = true
        indexing = false
        searchController.search(query)
    }

    function iconSource(icon) {
        if (!icon) return ""
        return String(icon).startsWith("/") ? "file://" + icon : Quickshell.iconPath(icon)
    }

    function activate(index) {
        if (index < 0 || index >= results.length) return
        const item = results[index]
        if (item.kind === "app") {
            phasor.request("apps.launch", { id: item.id }, function(result) {
                if (result.error) errorText = result.error
                else open = false
            })
        } else {
            phasor.request("files.open", { path: item.id }, function(result) {
                if (result.error) errorText = result.error
                else open = false
            })
        }
    }

    function openActions() {
        if (selectedIndex < 0 || selectedIndex >= results.length) return
        selectedItem = results[selectedIndex]
        proposedName = selectedItem.name
        renamingFile = false
        confirmingTrash = false
        showingActions = true
    }

    onOpenChanged: {
        if (open) {
            closing = false
            closeAnimationTimer.stop()
            query = ""
            showingActions = false
            renamingFile = false
            confirmingTrash = false
            searchInput.text = ""
            searchDebounce.stop()
            search()
            loadSpaces()
            inputFocusTimer.restart()
            Qt.callLater(function() { searchInput.forceActiveFocus() })
        } else {
            if (searchController) searchController.cancel()
            searchDebounce.stop()
            searching = false
            closing = true
            closeAnimationTimer.restart()
        }
    }

    Timer {
        id: closeAnimationTimer
        interval: Theme.Tokens.animationExit
        repeat: false
        onTriggered: launcher.closing = false
    }

    Timer {
        id: inputFocusTimer
        interval: 90
        repeat: false
        onTriggered: if (launcher.open) searchInput.forceActiveFocus()
    }

    Component.onCompleted: loadSpaces()

    Connections {
        target: launcher.phasor
        function onEventReceived(event) {
            if (event.type === "action" && event.name === "launcher.toggle") launcher.open = !launcher.open
            if (event.type === "snapshot") launcher.spaceItems = (event.data && event.data.spaces) || []
            if (event.type === "event" && event.name === "space.changed") launcher.spaceItems = event.data || []
            if (event.type === "event" && event.name === "files.indexReady" && launcher.open && launcher.query.trim().length >= 2) launcher.search()
            if (event.type === "event" && event.name === "files.changed" && launcher.open && launcher.query.trim().length >= 2) launcher.search()
        }
    }

    Timer {
        id: searchDebounce
        interval: 100
        repeat: false
        onTriggered: launcher.search()
    }

    PanelWindow {
        id: overlay
        anchors { top: true; bottom: true; left: true; right: true }
        visible: launcher.open || launcher.closing
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        // Do not also bind focusable: it downgrades Exclusive to OnDemand.
        WlrLayershell.keyboardFocus: launcher.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "phasor-launcher"
        onVisibleChanged: if (visible && launcher.open) inputFocusTimer.restart()

        Rectangle {
            anchors.fill: parent
            color: Theme.Tokens.overlayScrim
            opacity: launcher.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: launcher.open ? Theme.Tokens.animationNormal : Theme.Tokens.animationExit; easing.type: launcher.open ? Easing.OutCubic : Easing.InCubic } }
            MouseArea { anchors.fill: parent; onClicked: launcher.open = false }
        }

        Components.PhasorSurface {
            id: panel
            width: Math.min(720, parent.width - 40)
            height: Math.min(650, parent.height - 64)
            anchors.centerIn: parent
            opacity: launcher.open ? 1 : 0
            scale: launcher.open ? 1 : 0.975
            transformOrigin: Item.Center
            radius: Theme.Tokens.radiusMedium
            color: Theme.Tokens.surface
            border.width: 1
            border.color: Theme.Tokens.separator
            Behavior on opacity { NumberAnimation { duration: launcher.open ? Theme.Tokens.animationEnter : Theme.Tokens.animationExit; easing.type: launcher.open ? Easing.OutCubic : Easing.InCubic } }
            Behavior on scale { NumberAnimation { duration: launcher.open ? Theme.Tokens.animationEnter : Theme.Tokens.animationExit; easing.type: launcher.open ? Easing.OutCubic : Easing.InCubic } }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.Tokens.spacingXL
                spacing: Theme.Tokens.spacingM

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.Tokens.spacingM
                    Rectangle {
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 34
                        radius: Theme.Tokens.radiusSmall
                        color: Theme.Tokens.surfaceRaised
                        Text { anchors.centerIn: parent; text: "⌕"; color: Theme.Tokens.accent; font.pixelSize: 23 }
                    }
                    TextField {
                        id: searchInput
                        Layout.fillWidth: true
                        focus: launcher.open
                        activeFocusOnTab: true
                        placeholderText: "Find an app, file, or setting…"
                        selectionColor: Theme.Tokens.accent
                        selectedTextColor: Theme.Tokens.background
                        color: Theme.Tokens.textPrimary
                        placeholderTextColor: Theme.Tokens.textSecondary
                        font.pixelSize: 18
                        selectByMouse: true
                        background: Rectangle { color: "transparent" }
                        onTextChanged: { launcher.query = text; if (launcher.searchController) launcher.searchController.cancel(); launcher.searching = true; launcher.selectedIndex = 0; searchDebounce.restart() }
                        Keys.onPressed: function(event) {
                            if (event.key === Qt.Key_Escape) { if (launcher.showingActions) launcher.showingActions = false; else launcher.open = false; event.accepted = true }
                            else if (event.key === Qt.Key_Down) { launcher.selectedIndex = Math.min(launcher.results.length - 1, launcher.selectedIndex + (launcher.query.trim().length === 0 ? gridResults.columnCount : 1)); event.accepted = true }
                            else if (event.key === Qt.Key_Up) { launcher.selectedIndex = Math.max(0, launcher.selectedIndex - (launcher.query.trim().length === 0 ? gridResults.columnCount : 1)); event.accepted = true }
                            else if (launcher.query.trim().length === 0 && event.key === Qt.Key_Left) { launcher.selectedIndex = Math.max(0, launcher.selectedIndex - 1); event.accepted = true }
                            else if (launcher.query.trim().length === 0 && event.key === Qt.Key_Right) { launcher.selectedIndex = Math.min(launcher.results.length - 1, launcher.selectedIndex + 1); event.accepted = true }
                            else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ShiftModifier)) { launcher.openActions(); event.accepted = true }
                            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { launcher.activate(launcher.selectedIndex); event.accepted = true }
                        }
                    }
                    Components.ExtensionSlot {
                        Layout.alignment: Qt.AlignVCenter
                        slotName: "launcher.status"
                        providers: launcher.phasor ? launcher.phasor.extensions("launcher.status") : []
                    }
                    Text { text: "ESC"; color: Theme.Tokens.textSecondary; font.pixelSize: 11 }
                }

                Flickable {
                    Layout.fillWidth: true
                    Layout.preferredHeight: visible ? 34 : 0
                    visible: launcher.spaceItems.length > 0
                    contentWidth: spaceRow.implicitWidth
                    contentHeight: height
                    clip: true

                    Row {
                        id: spaceRow
                        spacing: Theme.Tokens.spacingXS
                        height: parent.height

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Spaces"
                            color: Theme.Tokens.textSecondary
                            font.pixelSize: 11
                            rightPadding: Theme.Tokens.spacingS
                        }

                        Repeater {
                            model: launcher.spaceItems
                            delegate: Components.PhasorButton {
                                required property var modelData
                                text: modelData.id
                                Accessible.name: modelData.name + (modelData.active ? ", active" : "")
                                font.pixelSize: 12
                                implicitWidth: 34
                                implicitHeight: 30
                                anchors.verticalCenter: parent.verticalCenter
                                onClicked: launcher.switchSpace(modelData)
                                background: Rectangle {
                                    radius: Theme.Tokens.radiusSmall
                                    color: modelData.active ? Theme.Tokens.accent : Theme.Tokens.surfaceRaised
                                }
                                contentItem: Text {
                                    text: modelData.id
                                    color: modelData.active ? Theme.Tokens.background : Theme.Tokens.textPrimary
                                    font: parent.font
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.Tokens.separator }

                ListView {
                    id: resultList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    ScrollIndicator.vertical: ScrollIndicator {}
                    model: launcher.results
                    currentIndex: launcher.selectedIndex
                    highlightMoveDuration: Theme.Tokens.animationFast
                    spacing: Theme.Tokens.spacingXS
                    add: Transition { NumberAnimation { properties: "opacity,scale"; from: 0; to: 1; duration: Theme.Tokens.animationNormal; easing.type: Easing.OutCubic } }
                    remove: Transition { NumberAnimation { properties: "opacity,scale"; to: 0; duration: Theme.Tokens.animationExit; easing.type: Easing.InCubic } }
                    displaced: Transition { NumberAnimation { properties: "y"; duration: Theme.Tokens.animationLayout; easing.type: Easing.OutCubic } }
                    visible: launcher.query.trim().length > 0 && !launcher.showingActions && launcher.results.length > 0
                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        width: resultList.width
                        height: 58
                        scale: 1
                        Behavior on scale { NumberAnimation { duration: Theme.Tokens.animationHover; easing.type: Easing.OutCubic } }
                        radius: Theme.Tokens.radiusSmall
                        color: index === launcher.selectedIndex ? Qt.alpha(Theme.Tokens.accent, .10) : "transparent"
                        border.width: 1
                        border.color: index === launcher.selectedIndex ? Qt.alpha(Theme.Tokens.accent, .28) : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.Tokens.animationHover } }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.Tokens.spacingM
                            anchors.rightMargin: Theme.Tokens.spacingM
                            spacing: Theme.Tokens.spacingM
                            Rectangle {
                                Layout.preferredWidth: 34
                                Layout.preferredHeight: 34
                                radius: Theme.Tokens.radiusSmall
                                color: modelData.kind === "app" ? Theme.Tokens.appIconSurface : Theme.Tokens.fileIconSurface
                                IconImage {
                                    id: resultIcon
                                    anchors.centerIn: parent
                                    width: 26
                                    height: 26
                                    implicitSize: 26
                                    source: modelData.kind === "app" ? launcher.iconSource(modelData.icon) : ""
                                    visible: status === Image.Ready
                                }
                                Text { anchors.centerIn: parent; visible: !resultIcon.visible; text: modelData.kind === "app" ? (modelData.name.length ? modelData.name.charAt(0).toUpperCase() : "A") : "↗"; color: Theme.Tokens.accent; font.pixelSize: 16; font.bold: true }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Text { text: modelData.name; color: Theme.Tokens.textPrimary; font.pixelSize: 15; elide: Text.ElideRight; Layout.fillWidth: true }
                                Text { text: modelData.detail; color: Theme.Tokens.textSecondary; font.pixelSize: 11; elide: Text.ElideMiddle; Layout.fillWidth: true }
                            }
                            Text { text: modelData.kind === "app" ? (modelData.favorite ? "PINNED" : modelData.recent ? "RECENT" : "APP") : "FILE"; color: modelData.favorite || modelData.recent ? Theme.Tokens.accent : Theme.Tokens.textSecondary; font.pixelSize: 10 }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: launcher.selectedIndex = index
                            onClicked: launcher.activate(index)
                        }
                    }
                }

                GridView {
                    id: gridResults
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: launcher.query.trim().length === 0 && !launcher.showingActions && launcher.results.length > 0
                    clip: true
                    ScrollIndicator.vertical: ScrollIndicator {}
                    model: launcher.results
                    currentIndex: launcher.selectedIndex
                    highlightMoveDuration: Theme.Tokens.animationFast
                    readonly property int columnCount: Math.max(1, Math.floor(width / 132))
                    cellWidth: Math.floor(width / Math.max(1, Math.floor(width / 132)))
                    cellHeight: 100
                    add: Transition { NumberAnimation { properties: "opacity,scale"; from: 0; to: 1; duration: Theme.Tokens.animationNormal; easing.type: Easing.OutCubic } }
                    remove: Transition { NumberAnimation { properties: "opacity,scale"; to: 0; duration: Theme.Tokens.animationExit; easing.type: Easing.InCubic } }
                    displaced: Transition { NumberAnimation { properties: "x,y"; duration: Theme.Tokens.animationLayout; easing.type: Easing.OutCubic } }
                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        width: gridResults.cellWidth - 8
                        height: gridResults.cellHeight - 8
                        scale: 1
                        Behavior on scale { NumberAnimation { duration: Theme.Tokens.animationHover; easing.type: Easing.OutCubic } }
                        radius: Theme.Tokens.radiusSmall
                        color: index === launcher.selectedIndex ? Qt.alpha(Theme.Tokens.accent, .10) : "transparent"
                        border.width: 1
                        border.color: index === launcher.selectedIndex ? Qt.alpha(Theme.Tokens.accent, .28) : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.Tokens.animationHover } }
                        Column {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 6
                            Rectangle {
                                width: 38
                                height: 38
                                radius: Theme.Tokens.radiusSmall
                                anchors.horizontalCenter: parent.horizontalCenter
                                color: "transparent"
                                IconImage {
                                    id: gridAppIcon
                                    anchors.centerIn: parent
                                    width: 36
                                    height: 36
                                    implicitSize: 40
                                    source: launcher.iconSource(modelData.icon)
                                    visible: status === Image.Ready
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: !gridAppIcon.visible
                                    text: modelData.name.length ? modelData.name.charAt(0).toUpperCase() : "A"
                                    color: Theme.Tokens.accent
                                    font.pixelSize: 18
                                    font.bold: true
                                }
                            }
                            Text {
                                width: parent.width
                                text: modelData.name
                                color: Theme.Tokens.textPrimary
                                font.pixelSize: 11
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: launcher.selectedIndex = index
                            onClicked: launcher.activate(index)
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: launcher.results.length === 0 && !launcher.showingActions
                    Column {
                        anchors.centerIn: parent
                        spacing: 10
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: launcher.searching ? "Searching…" : "Nothing found yet"; color: Theme.Tokens.textPrimary; font.pixelSize: 18 }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: launcher.searching ? "Apps and files, all in one place." : "Try an app name or a different filename."; color: Theme.Tokens.textSecondary; font.pixelSize: 12 }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: launcher.showingActions
                    spacing: Theme.Tokens.spacingM
                    Text { text: launcher.selectedItem ? launcher.selectedItem.name : "Actions"; color: Theme.Tokens.textPrimary; font.pixelSize: 17; font.bold: true }
                    Text { text: launcher.selectedItem ? launcher.selectedItem.detail : ""; color: Theme.Tokens.textSecondary; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere }

                    Components.PhasorButton {
                        visible: launcher.selectedItem && launcher.selectedItem.kind === "app"
                        text: launcher.selectedItem && launcher.selectedItem.favorite ? "Unpin from favorites" : "Pin to favorites"
                        onClicked: phasor.request("apps.favorite", { id: launcher.selectedItem.id, enabled: !launcher.selectedItem.favorite }, function(result) {
                            if (result.error) launcher.errorText = result.error
                            else { launcher.showingActions = false; launcher.search() }
                        })
                    }
                    Components.PhasorButton {
                        visible: launcher.selectedItem && launcher.selectedItem.kind === "app"
                        text: "App info"
                        onClicked: launcher.infoText = launcher.selectedItem.id + "\n" + launcher.selectedItem.detail
                    }
                    Components.PhasorButton {
                        visible: launcher.selectedItem && launcher.selectedItem.kind === "app"
                        text: "Open in Bazaar to manage or uninstall"
                        onClicked: phasor.request("apps.open_store", { id: launcher.selectedItem.id }, function(result) {
                            if (result.error) launcher.errorText = result.error
                            else launcher.showingActions = false
                        })
                    }
                    Components.PhasorButton {
                        visible: launcher.selectedItem && launcher.selectedItem.kind === "file" && !launcher.renamingFile && !launcher.confirmingTrash
                        text: "Open"
                        onClicked: phasor.request("files.open", { path: launcher.selectedItem.id }, function(result) {
                            if (result.error) launcher.errorText = result.error
                            else launcher.open = false
                        })
                    }
                    Components.PhasorButton {
                        visible: launcher.selectedItem && launcher.selectedItem.kind === "file" && !launcher.renamingFile && !launcher.confirmingTrash
                        text: "Reveal in Files"
                        onClicked: phasor.request("files.reveal", { path: launcher.selectedItem.id }, function(result) {
                            if (result.error) launcher.errorText = result.error
                            else launcher.showingActions = false
                        })
                    }
                    Components.PhasorButton {
                        visible: launcher.selectedItem && launcher.selectedItem.kind === "file" && !launcher.renamingFile && !launcher.confirmingTrash
                        text: "Copy path"
                        onClicked: phasor.request("files.copy_path", { path: launcher.selectedItem.id }, function(result) {
                            if (result.error) launcher.errorText = result.error
                            else launcher.showingActions = false
                        })
                    }
                    Components.PhasorButton {
                        visible: launcher.selectedItem && launcher.selectedItem.kind === "file" && !launcher.renamingFile && !launcher.confirmingTrash
                        text: "Share file link"
                        onClicked: launcher.applyFileAction("files.share", { path: launcher.selectedItem.id })
                    }
                    Components.PhasorButton {
                        visible: launcher.selectedItem && launcher.selectedItem.kind === "file" && !launcher.selectedItem.directory && !launcher.renamingFile && !launcher.confirmingTrash
                        text: "Copy file"
                        onClicked: launcher.applyFileAction("files.copy", { path: launcher.selectedItem.id })
                    }
                    Components.PhasorButton {
                        visible: launcher.selectedItem && launcher.selectedItem.kind === "file" && !launcher.renamingFile && !launcher.confirmingTrash
                        text: "Rename"
                        onClicked: {
                            launcher.proposedName = launcher.selectedItem.name
                            launcher.renamingFile = true
                            Qt.callLater(function() { renameInput.forceActiveFocus(); renameInput.selectAll() })
                        }
                    }
                    Components.PhasorTextField {
                        id: renameInput
                        visible: launcher.renamingFile
                        Layout.fillWidth: true
                        text: launcher.proposedName
                        selectByMouse: true
                        onTextChanged: launcher.proposedName = text
                    }
                    Components.PhasorButton {
                        visible: launcher.renamingFile
                        text: "Save name"
                        enabled: launcher.proposedName.trim().length > 0
                        onClicked: launcher.applyFileAction("files.rename", { path: launcher.selectedItem.id, name: launcher.proposedName.trim() })
                    }
                    Components.PhasorButton {
                        visible: launcher.selectedItem && launcher.selectedItem.kind === "file" && !launcher.renamingFile && !launcher.confirmingTrash
                        text: "Move to Trash"
                        onClicked: launcher.confirmingTrash = true
                    }
                    Text {
                        visible: launcher.confirmingTrash
                        text: launcher.selectedItem ? "Move “" + launcher.selectedItem.name + "” to Trash? You can restore it from your file manager." : ""
                        color: Theme.Tokens.warning
                        font.pixelSize: 12
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                    }
                    Components.PhasorButton {
                        visible: launcher.confirmingTrash
                        text: "Confirm Move to Trash"
                        onClicked: launcher.applyFileAction("files.trash", { path: launcher.selectedItem.id })
                    }
                    Components.PhasorButton {
                        text: launcher.renamingFile || launcher.confirmingTrash ? "Cancel" : "Back"
                        onClicked: {
                            if (launcher.renamingFile) launcher.renamingFile = false
                            else if (launcher.confirmingTrash) launcher.confirmingTrash = false
                            else launcher.showingActions = false
                        }
                    }
                    Item { Layout.fillHeight: true }
                }

                Text {
                    Layout.fillWidth: true
                    visible: launcher.errorText.length > 0 || launcher.infoText.length > 0 || launcher.indexing
                    text: launcher.errorText.length > 0 ? launcher.errorText : (launcher.infoText.length > 0 ? launcher.infoText : (launcher.indexing ? "Indexing Home in the background…" : (launcher.results.length === 0 ? "No matching apps or files" : "")))
                    color: launcher.errorText.length > 0 ? Theme.Tokens.danger : Theme.Tokens.textSecondary
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: launcher.showingActions ? "Actions" : (launcher.query.length >= 2 ? "Apps and files" : "Applications"); color: Theme.Tokens.textSecondary; font.pixelSize: 11 }
                    Item { Layout.fillWidth: true }
                    Components.ExtensionSlot {
                        slotName: "launcher.actions"
                        providers: launcher.phasor ? launcher.phasor.extensions("launcher.actions") : []
                    }
                    Text { text: "↑ ↓"; color: Theme.Tokens.textSecondary; font.pixelSize: 11 }
                    Text { text: launcher.showingActions ? "ESC  Close" : "↵ Open · ⇧↵ More"; color: Theme.Tokens.textSecondary; font.pixelSize: 11 }
                }
            }
        }
    }
}
