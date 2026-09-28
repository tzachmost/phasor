import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../shell/theme" as Theme
import "../../shell/components" as Components
import "../../shell/components" as Components

Item {
    id: launcher
    width: 1
    height: 1
    property var phasor
    property bool open: false
    property string query: ""
    property int selectedIndex: 0
    property var results: []
    property bool showingActions: false
    property var selectedItem: null
    property bool indexing: false
    property string errorText: ""
    property string infoText: ""

    function search() {
        const text = query.trim()
        errorText = ""
        infoText = ""
        if (text.length === 0) {
            phasor.request("apps.search", { query: "", limit: 30 }, function(result) {
                if (result.error) { errorText = result.error; return }
                results = (result.items || []).map(function(app) {
                    return { kind: "app", id: app.id, name: app.name, detail: app.genericName || app.comment || "Application", icon: app.icon, favorite: app.favorite }
                })
                selectedIndex = 0
            })
            return
        }
        let remaining = text.length >= 2 ? 2 : 1
        let apps = []
        let files = []
        const update = function() {
            if (--remaining > 0) return
            results = apps.concat(files)
            selectedIndex = Math.min(selectedIndex, Math.max(results.length - 1, 0))
        }
        phasor.request("apps.search", { query: text, limit: 24 }, function(result) {
            if (result.error) errorText = result.error
            else apps = (result.items || []).map(function(app) {
                return { kind: "app", id: app.id, name: app.name, detail: app.genericName || app.comment || "Application", icon: app.icon, favorite: app.favorite }
            })
            update()
        })
        if (text.length >= 2) {
            phasor.request("files.search", { query: text, limit: 30 }, function(result) {
                if (result.error) errorText = result.error
                else {
                    files = (result.items || []).map(function(file) {
                        return { kind: "file", id: file.path, name: file.name, detail: file.path, directory: file.directory }
                    })
                    indexing = Boolean(result.status && result.status.indexing)
                }
                update()
            })
        }
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
        showingActions = true
    }

    onOpenChanged: {
        if (open) {
            query = ""
            showingActions = false
            searchInput.text = ""
            search()
            Qt.callLater(function() { searchInput.forceActiveFocus() })
        }
    }

    Connections {
        target: launcher.phasor
        function onEventReceived(event) {
            if (event.type === "action" && event.name === "launcher.toggle") launcher.open = !launcher.open
            if (event.type === "event" && event.name === "files.indexReady" && launcher.open && launcher.query.trim().length >= 2) launcher.search()
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
        visible: launcher.open
        focusable: launcher.open
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: launcher.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "phasor-launcher"

        Rectangle {
            anchors.fill: parent
            color: "#88080a0e"
            opacity: launcher.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.Tokens.animationFast } }
            MouseArea { anchors.fill: parent; onClicked: launcher.open = false }
        }

        Rectangle {
            id: panel
            width: Math.min(680, parent.width - 40)
            height: Math.min(600, parent.height - 64)
            anchors.centerIn: parent
            radius: Theme.Tokens.radiusLarge
            color: Theme.Tokens.surface
            border.width: 1
            border.color: Theme.Tokens.borderFocused

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.Tokens.spacingL
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
                        placeholderText: "Search apps and files"
                        color: Theme.Tokens.textPrimary
                        placeholderTextColor: Theme.Tokens.textSecondary
                        font.pixelSize: 18
                        selectByMouse: true
                        background: Rectangle { color: "transparent" }
                        onTextChanged: { launcher.query = text; searchDebounce.restart() }
                        Keys.onPressed: function(event) {
                            if (event.key === Qt.Key_Escape) { if (launcher.showingActions) launcher.showingActions = false; else launcher.open = false; event.accepted = true }
                            else if (event.key === Qt.Key_Down) { launcher.selectedIndex = Math.min(launcher.results.length - 1, launcher.selectedIndex + (launcher.query.trim().length === 0 ? gridResults.columns : 1)); event.accepted = true }
                            else if (event.key === Qt.Key_Up) { launcher.selectedIndex = Math.max(0, launcher.selectedIndex - (launcher.query.trim().length === 0 ? gridResults.columns : 1)); event.accepted = true }
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

                Rectangle { Layout.fillWidth: true; height: 1; color: "#343943" }

                ListView {
                    id: resultList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: launcher.results
                    currentIndex: launcher.selectedIndex
                    spacing: Theme.Tokens.spacingXS
                    visible: launcher.query.trim().length > 0 && !launcher.showingActions
                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        width: resultList.width
                        height: 58
                        radius: Theme.Tokens.radiusSmall
                        color: index === launcher.selectedIndex ? Theme.Tokens.surfaceRaised : "transparent"
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.Tokens.spacingM
                            anchors.rightMargin: Theme.Tokens.spacingM
                            spacing: Theme.Tokens.spacingM
                            Rectangle {
                                Layout.preferredWidth: 34
                                Layout.preferredHeight: 34
                                radius: Theme.Tokens.radiusSmall
                                color: modelData.kind === "app" ? "#30394a" : "#383244"
                                Text { anchors.centerIn: parent; text: modelData.kind === "app" ? "A" : "↗"; color: Theme.Tokens.accent; font.pixelSize: 16; font.bold: true }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Text { text: modelData.name; color: Theme.Tokens.textPrimary; font.pixelSize: 15; elide: Text.ElideRight; Layout.fillWidth: true }
                                Text { text: modelData.detail; color: Theme.Tokens.textSecondary; font.pixelSize: 11; elide: Text.ElideMiddle; Layout.fillWidth: true }
                            }
                            Text { text: modelData.kind === "app" ? (modelData.favorite ? "PINNED" : "APP") : "FILE"; color: modelData.favorite ? Theme.Tokens.accent : Theme.Tokens.textSecondary; font.pixelSize: 10 }
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
                    visible: launcher.query.trim().length === 0 && !launcher.showingActions
                    clip: true
                    model: launcher.results
                    currentIndex: launcher.selectedIndex
                    cellWidth: Math.floor(width / Math.max(1, Math.floor(width / 132)))
                    cellHeight: 88
                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        width: gridResults.cellWidth - 8
                        height: gridResults.cellHeight - 8
                        radius: Theme.Tokens.radiusSmall
                        color: index === launcher.selectedIndex ? Theme.Tokens.surfaceRaised : "transparent"
                        Column {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 6
                            Rectangle {
                                width: 38
                                height: 38
                                radius: Theme.Tokens.radiusSmall
                                anchors.horizontalCenter: parent.horizontalCenter
                                color: "#30394a"
                                Text {
                                    anchors.centerIn: parent
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

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: launcher.showingActions
                    spacing: Theme.Tokens.spacingM
                    Text { text: launcher.selectedItem ? launcher.selectedItem.name : "Actions"; color: Theme.Tokens.textPrimary; font.pixelSize: 17; font.bold: true }
                    Text { text: launcher.selectedItem ? launcher.selectedItem.detail : ""; color: Theme.Tokens.textSecondary; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere }

                    Button {
                        visible: launcher.selectedItem && launcher.selectedItem.kind === "app"
                        text: launcher.selectedItem && launcher.selectedItem.favorite ? "Unpin from favorites" : "Pin to favorites"
                        onClicked: phasor.request("apps.favorite", { id: launcher.selectedItem.id, enabled: !launcher.selectedItem.favorite }, function(result) {
                            if (result.error) launcher.errorText = result.error
                            else { launcher.showingActions = false; launcher.search() }
                        })
                    }
                    Button {
                        visible: launcher.selectedItem && launcher.selectedItem.kind === "app"
                        text: "App info"
                        onClicked: launcher.infoText = launcher.selectedItem.id + "\n" + launcher.selectedItem.detail
                    }
                    Button {
                        visible: launcher.selectedItem && launcher.selectedItem.kind === "app"
                        text: "Open in Bazaar to manage or uninstall"
                        onClicked: phasor.request("apps.open_store", { id: launcher.selectedItem.id }, function(result) {
                            if (result.error) launcher.errorText = result.error
                            else launcher.showingActions = false
                        })
                    }
                    Button {
                        visible: launcher.selectedItem && launcher.selectedItem.kind === "file"
                        text: "Open"
                        onClicked: phasor.request("files.open", { path: launcher.selectedItem.id }, function(result) {
                            if (result.error) launcher.errorText = result.error
                            else launcher.open = false
                        })
                    }
                    Button {
                        visible: launcher.selectedItem && launcher.selectedItem.kind === "file"
                        text: "Reveal in Files"
                        onClicked: phasor.request("files.reveal", { path: launcher.selectedItem.id }, function(result) {
                            if (result.error) launcher.errorText = result.error
                            else launcher.showingActions = false
                        })
                    }
                    Button {
                        visible: launcher.selectedItem && launcher.selectedItem.kind === "file"
                        text: "Copy path"
                        onClicked: phasor.request("files.copy_path", { path: launcher.selectedItem.id }, function(result) {
                            if (result.error) launcher.errorText = result.error
                            else launcher.showingActions = false
                        })
                    }
                    Button { text: "Back"; onClicked: launcher.showingActions = false }
                    Item { Layout.fillHeight: true }
                }

                Text {
                    Layout.fillWidth: true
                    visible: launcher.errorText.length > 0 || launcher.infoText.length > 0 || launcher.indexing || launcher.results.length === 0
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
                    Text { text: "↑ ↓  Navigate"; color: Theme.Tokens.textSecondary; font.pixelSize: 11 }
                    Text { text: launcher.showingActions ? "ESC  Close" : "↵ Open · ⇧↵ Actions"; color: Theme.Tokens.textSecondary; font.pixelSize: 11 }
                }
            }
        }
    }
}
