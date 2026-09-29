import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../shell/theme" as Theme
Item {
    id: commandPalette
    width: 1
    height: 1
    property var phasor
    property bool open: false
    property string query: ""
    property string errorText: ""
    property var settingsData: ({})
    property var shortcuts: []
    property var commands: [
        { id: "launcher", title: "Open applications and files", detail: "Search apps, documents, and Spaces", section: "Applications" },
        { id: "settings", title: "Open Settings", detail: "Change the Phasor desktop setup", section: "Settings" },
        { id: "mango", title: "Configure tiling", detail: "Arrange windows and fine-tune layouts", section: "Settings" },
        { id: "shortcuts", title: "Change keyboard shortcuts", detail: "Open Settings on the shortcuts page", section: "Settings" },
        { id: "system", title: "Open system controls", detail: "Wi-Fi, Bluetooth, sound, and brightness", section: "Settings" },
        { id: "dock", title: "Toggle Dock", detail: "Show or hide the running windows Dock", section: "Shell" },
        { id: "previousSpace", title: "Switch to previous Space", detail: "Move to the Space on the left", section: "Spaces" },
        { id: "nextSpace", title: "Switch to next Space", detail: "Move to the Space on the right", section: "Spaces" }
    ]
    property var filteredCommands: []
    property int selectedIndex: 0

    function filterCommands() {
        const needle = query.trim().toLowerCase()
        const combined = commands.concat(shortcuts)
        filteredCommands = combined.filter(function(command) {
            return needle.length === 0 || (command.title + " " + command.detail + " " + command.section).toLowerCase().indexOf(needle) >= 0
        })
        selectedIndex = Math.min(selectedIndex, Math.max(filteredCommands.length - 1, 0))
    }

    function formatKey(value) {
        const names = { "SUPER": "Super", "CTRL": "Ctrl", "CONTROL": "Ctrl", "ALT": "Alt", "SHIFT": "Shift", "SPACE": "Space", "LEFT": "←", "RIGHT": "→", "UP": "↑", "DOWN": "↓", "comma": ",", "slash": "/", "TAB": "Tab", "RETURN": "Enter", "ESC": "Esc" }
        const key = String(value || "").trim()
        return names[key] || names[key.toUpperCase()] || (key.length === 1 ? key.toUpperCase() : key)
    }

    function loadShortcuts() {
        if (!phasor) return
        phasor.request("mango.config.get", {}, function(result) {
            if (result.error) { errorText = result.error; return }
            const rows = []
            const lines = String(result.config || "").split(/\r?\n/)
            for (let i = 0; i < lines.length; i++) {
                const match = lines[i].trim().match(/^(bind[a-z]*)\s*=\s*([^,]+),([^,]+),(.+)$/i)
                if (!match) continue
                const modifiers = match[2].split("+").map(formatKey).filter(function(part) { return part.length > 0 })
                const key = formatKey(match[3])
                rows.push({ id: "shortcut-" + i, kind: "shortcut", title: modifiers.concat([key]).join(" + "), detail: "Window manager · " + match[1] + " → " + match[4].trim(), section: "Keyboard shortcuts" })
            }
            shortcuts = rows
            filterCommands()
        })
    }

    function refreshSettings() {
        if (!phasor) return
        phasor.request("settings.get", {}, function(result) {
            if (!result.error) settingsData = result
        })
    }

    function finishRequest(result) {
        if (result && result.error) errorText = result.error
        else open = false
    }

    function run(command) {
        if (!phasor || !command) return
        errorText = ""
        if (command.kind === "shortcut") return
        if (command.id === "launcher") {
            phasor.request("launcher.toggle", {}, finishRequest)
        } else if (command.id === "settings") {
            phasor.request("settings.toggle", { section: "appearance" }, finishRequest)
        } else if (command.id === "shortcuts") {
            phasor.request("settings.toggle", { section: "shortcuts" }, finishRequest)
        } else if (command.id === "mango") {
            phasor.request("settings.toggle", { section: "mango" }, finishRequest)
        } else if (command.id === "system") {
            phasor.request("settings.toggle", { section: "system" }, finishRequest)
        } else if (command.id === "previousSpace") {
            phasor.request("spaces.previous", {}, finishRequest)
        } else if (command.id === "nextSpace") {
            phasor.request("spaces.next", {}, finishRequest)
        } else if (command.id === "dock") {
            phasor.request("settings.get", {}, function(result) {
                if (result.error) { errorText = result.error; return }
                const plugins = result.plugins || ({})
                const dock = plugins["dev.phasor.dock"] || ({})
                const patch = { plugins: { "dev.phasor.dock": { enabled: !Boolean(dock.enabled) } } }
                phasor.request("settings.update", { patch: patch }, finishRequest)
            })
        }
    }

    function displayShortcut(value, fallback) {
        const shortcut = value || fallback
        return String(shortcut).replace("+", " + ")
    }

    function moveSelection(direction) {
        if (filteredCommands.length === 0) return
        selectedIndex = (selectedIndex + direction + filteredCommands.length) % filteredCommands.length
        commandList.currentIndex = selectedIndex
    }

    onQueryChanged: filterCommands()
    onOpenChanged: {
        if (open) {
            query = ""
            errorText = ""
            filterCommands()
            refreshSettings()
            loadShortcuts()
            Qt.callLater(function() { commandSearch.forceActiveFocus() })
        }
    }

    Connections {
        target: commandPalette.phasor
        function onEventReceived(event) {
            if (event.type === "action" && event.name === "commands.toggle") commandPalette.open = !commandPalette.open
            if (event.type === "event" && event.name === "settings.changed" && commandPalette.open) { commandPalette.refreshSettings(); commandPalette.loadShortcuts() }
        }
    }

    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        visible: commandPalette.open
        focusable: commandPalette.open
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: commandPalette.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "phasor-commands"

        Rectangle {
            anchors.fill: parent
            color: Theme.Tokens.overlayScrim
            MouseArea { anchors.fill: parent; onClicked: commandPalette.open = false }
        }

        Rectangle {
            width: Math.min(620, parent.width - 40)
            height: Math.min(520, parent.height - 64)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Math.max(48, parent.height * 0.14)
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
                    Text { text: "⌘"; color: Theme.Tokens.accent; font.pixelSize: 24 }
                    TextField {
                        id: commandSearch
                        Layout.fillWidth: true
                        placeholderText: "Search commands and shortcuts"
                        color: Theme.Tokens.textPrimary
                        placeholderTextColor: Theme.Tokens.textSecondary
                        font.pixelSize: 17
                        selectByMouse: true
                        background: Rectangle { color: "transparent" }
                        onTextChanged: commandPalette.query = text
                        Keys.onPressed: function(event) {
                            if (event.key === Qt.Key_Escape) { commandPalette.open = false; event.accepted = true }
                            else if (event.key === Qt.Key_Down) { commandPalette.moveSelection(1); event.accepted = true }
                            else if (event.key === Qt.Key_Up) { commandPalette.moveSelection(-1); event.accepted = true }
                            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                if (commandPalette.filteredCommands.length > 0) commandPalette.run(commandPalette.filteredCommands[commandPalette.selectedIndex])
                                event.accepted = true
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.Tokens.separator }

                ListView {
                    id: commandList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: commandPalette.filteredCommands
                    currentIndex: commandPalette.selectedIndex
                    spacing: Theme.Tokens.spacingXS
                    delegate: Item {
                        id: commandRow
                        required property var modelData
                        required property int index
                        width: commandList.width
                        height: 58

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.Tokens.radiusSmall
                            color: commandPalette.selectedIndex === commandRow.index ? Theme.Tokens.surfaceRaised : "transparent"
                            border.width: commandPalette.selectedIndex === commandRow.index ? 1 : 0
                            border.color: Theme.Tokens.separator
                        }
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.Tokens.spacingM
                            anchors.rightMargin: Theme.Tokens.spacingM
                            spacing: 2
                            Text { Layout.fillWidth: true; text: commandRow.modelData.title; color: Theme.Tokens.textPrimary; font.pixelSize: 13; font.bold: true; elide: Text.ElideRight }
                            Text { Layout.fillWidth: true; text: commandRow.modelData.detail; color: Theme.Tokens.textSecondary; font.pixelSize: 11; elide: Text.ElideRight }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: { commandPalette.selectedIndex = commandRow.index; commandList.currentIndex = commandRow.index }
                            onClicked: commandPalette.run(commandRow.modelData)
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: commandPalette.filteredCommands.length === 0
                        text: "No commands match your search"
                        color: Theme.Tokens.textSecondary
                        font.pixelSize: 12
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: commandPalette.errorText.length > 0
                    text: commandPalette.errorText
                    color: Theme.Tokens.danger
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: commandPalette.displayShortcut(commandPalette.settingsData.commands ? commandPalette.settingsData.commands.shortcut : "Super+/", "Super+/") + " opens Commands"
                        color: Theme.Tokens.textSecondary
                        font.pixelSize: 10
                    }
                    Text { text: "↑ ↓ Navigate  ·  Enter Run action  ·  Esc Close"; color: Theme.Tokens.textSecondary; font.pixelSize: 10 }
                }
            }
        }
    }
}
