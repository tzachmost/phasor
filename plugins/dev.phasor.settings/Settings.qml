import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../shell/theme" as Theme
import "../../shell/components" as Components

Item {
    id: preferences
    width: 1
    height: 1
    property var phasor
    property bool open: false
    property bool loading: false
    property bool loadingSystem: false
    property bool savingAppearance: false
    property bool appearanceDirty: false
    property bool savingPreferences: false
    property bool savingPlugin: false
    property string savingPluginId: ""
    property bool systemBusy: false
    property var settingsData: ({})
    property string section: "appearance"
    property string errorText: ""
    property string statusText: ""
    property string systemErrorText: ""
    property var networkStatus: ({ available: false, error: "Open Settings to check Wi-Fi." })
    property var bluetoothStatus: ({ available: false, error: "Open Settings to check Bluetooth." })
    property var audioStatus: ({ available: false, error: "Open Settings to check audio." })
    property var brightnessStatus: ({ available: false, error: "Open Settings to check brightness." })
    property var notificationsStatus: ({ available: false, error: "Open Settings to check notifications." })

    function load(preserveAppearance) {
        if (!phasor) return
        loading = true
        errorText = ""
        phasor.request("settings.get", {}, function(result) {
            if (result.error) {
                errorText = result.error
                loading = false
                return
            }
            settingsData = result
            if (!preserveAppearance) {
                const schemes = ["system", "light", "dark"]
                schemeBox.currentIndex = Math.max(0, schemes.indexOf(result.appearance.theme))
                accentInput.text = result.appearance.accent
                motionSwitch.checked = result.appearance.reducedMotion
                wallpaperInput.text = result.appearance.wallpaper
                appearanceDirty = false
            }
            launcherRecentsSwitch.checked = Boolean(result.launcher.showRecents)
            workspaceCount.value = result.spaces.count
            spaceAnimationSlider.value = result.spaces.animationDuration
            focusModeBox.currentIndex = result.windows.focusMode === "sloppy" ? 1 : 0
            raiseOnFocusSwitch.checked = Boolean(result.windows.raiseOnFocus)
            dockCloseButtonsSwitch.checked = result.dock.showCloseButtons !== false
            dockEmptyStateSwitch.checked = result.dock.showEmptyState !== false
            launcherShortcutBox.currentIndex = Math.max(0, launcherShortcutChoices.indexOf(result.launcher.shortcut))
            commandShortcutBox.currentIndex = Math.max(0, commandShortcutChoices.indexOf(result.commands.shortcut))
            settingsShortcutBox.currentIndex = Math.max(0, settingsShortcutChoices.indexOf(result.settings.shortcut))
            loading = false
        })
    }

    function refreshSystem() {
        if (!phasor) return
        loadingSystem = true
        systemErrorText = ""
        let remaining = 5
        const completed = function() {
            remaining -= 1
            if (remaining === 0) loadingSystem = false
        }
        const requestStatus = function(method, propertyName) {
            phasor.request(method, {}, function(result) {
                if (result.error) preferences[propertyName] = { available: false, error: result.error }
                else if (result && typeof result === "object") preferences[propertyName] = result
                else preferences[propertyName] = { available: false, error: "No status data returned." }
                completed()
            })
        }
        requestStatus("network.status", "networkStatus")
        requestStatus("bluetooth.status", "bluetoothStatus")
        requestStatus("audio.status", "audioStatus")
        requestStatus("brightness.status", "brightnessStatus")
        requestStatus("notifications.status", "notificationsStatus")
    }

    function markAppearanceDirty() {
        if (loading || savingAppearance) return
        appearanceDirty = true
        statusText = ""
    }

    function saveAppearance() {
        if (!phasor || loading || savingAppearance) return
        const schemes = ["system", "light", "dark"]
        const patch = {
            appearance: {
                theme: schemes[schemeBox.currentIndex],
                accent: accentInput.text.trim(),
                reducedMotion: motionSwitch.checked,
                wallpaper: wallpaperInput.text.trim()
            }
        }
        errorText = ""
        statusText = ""
        savingAppearance = true
        phasor.request("settings.update", { patch: patch }, function(result) {
            savingAppearance = false
            if (result.error) {
                errorText = result.error
                return
            }
            settingsData = result
            appearanceDirty = false
            statusText = "Appearance settings saved"
        })
    }

    function resetAppearance() {
        schemeBox.currentIndex = 2
        accentInput.text = "#8bd5ca"
        motionSwitch.checked = false
        wallpaperInput.text = ""
        markAppearanceDirty()
    }

    function pluginEnabled(pluginId) {
        const plugins = settingsData.plugins || ({})
        const preference = plugins[pluginId] || ({})
        return Boolean(preference.enabled)
    }

    function systemAvailable(status) {
        return Boolean(status && status.available === true)
    }

    function systemError(status, label) {
        return status && status.error ? String(status.error) : label + " is unavailable."
    }

    function systemNumber(status, key) {
        if (!status || typeof status[key] !== "number" || !isFinite(status[key])) return 0
        return status[key]
    }

    property var launcherShortcutChoices: ["Super+Space", "Super+Alt+Space", "Super+D", "Super+R", "Alt+Space", "Ctrl+Space"]
    property var commandShortcutChoices: ["Super+/", "Super+Shift+/", "Ctrl+Alt+Space", "Super+Alt+/", "Ctrl+Shift+P"]
    property var settingsShortcutChoices: ["Super+,", "Super+Alt+Comma", "Super+Shift+Comma", "Ctrl+Alt+S"]

    function displayShortcut(value) {
        return String(value || "").split("+").join(" + ")
    }

    function savePreferences(patch, successText) {
        if (!phasor || loading || savingPreferences) return
        savingPreferences = true
        errorText = ""
        statusText = ""
        phasor.request("settings.update", { patch: patch }, function(result) {
            savingPreferences = false
            if (result.error) {
                errorText = result.error
                return
            }
            settingsData = result
            const session = result.sessionConfig || ({})
            if (session.customConfig) statusText = session.error || "Session preferences are saved, but the active custom Mango config keeps control."
            else if (session.restartRequired) statusText = session.error || "Saved. Restart the Phasor session to apply keyboard and workspace changes."
            else if (session.reloaded) statusText = successText + " · session updated"
            else statusText = successText
        })
    }

    function saveShellPreferences() {
        savePreferences({
            launcher: { showRecents: launcherRecentsSwitch.checked },
            dock: {
                showCloseButtons: dockCloseButtonsSwitch.checked,
                showEmptyState: dockEmptyStateSwitch.checked
            },
            spaces: {
                count: workspaceCount.value,
                animationDuration: Math.round(spaceAnimationSlider.value)
            },
            windows: {
                focusMode: focusModeBox.currentIndex === 1 ? "sloppy" : "click",
                raiseOnFocus: raiseOnFocusSwitch.checked
            }
        }, "Shell preferences saved")
    }

    function saveShortcutPreferences() {
        savePreferences({
            launcher: { shortcut: launcherShortcutChoices[launcherShortcutBox.currentIndex] },
            commands: { shortcut: commandShortcutChoices[commandShortcutBox.currentIndex] },
            settings: { shortcut: settingsShortcutChoices[settingsShortcutBox.currentIndex] }
        }, "Keyboard shortcuts saved")
    }

    function setPluginEnabled(pluginId, enabled) {
        if (!phasor || savingPlugin) return
        const patch = { plugins: {} }
        patch.plugins[pluginId] = { enabled: Boolean(enabled) }
        savingPlugin = true
        savingPluginId = pluginId
        statusText = ""
        phasor.request("settings.update", { patch: patch }, function(result) {
            savingPlugin = false
            savingPluginId = ""
            if (result.error) {
                errorText = result.error
                load(appearanceDirty)
                return
            }
            settingsData = result
            errorText = ""
            statusText = "Shell setting saved"
        })
    }

    function changeSystem(method, params, propertyName) {
        if (!phasor || systemBusy) return
        systemBusy = true
        systemErrorText = ""
        phasor.request(method, params, function(result) {
            systemBusy = false
            if (result.error) {
                systemErrorText = result.error
                return
            }
            if (result && typeof result === "object") preferences[propertyName] = result
            else preferences[propertyName] = { available: false, error: "No status data returned." }
        })
    }

    function changeDoNotDisturb(enabled) {
        if (!phasor || systemBusy) return
        systemBusy = true
        systemErrorText = ""
        phasor.request("notifications.set_dnd", { enabled: Boolean(enabled) }, function(result) {
            systemBusy = false
            if (result.error) {
                systemErrorText = result.error
                return
            }
            refreshSystem()
        })
    }

    onOpenChanged: {
        if (open) {
            load(false)
            refreshSystem()
            Qt.callLater(function() { schemeBox.forceActiveFocus() })
        }
    }

    Connections {
        target: preferences.phasor
        function onEventReceived(event) {
            if (event.type === "action" && event.name === "settings.toggle") {
                if (event.data && event.data.section) preferences.section = event.data.section
                preferences.open = !preferences.open
            }
            if (event.type === "event" && event.name === "settings.changed" && preferences.open) preferences.load(preferences.appearanceDirty)
        }
    }

    Shortcut {
        sequence: "Esc"
        enabled: preferences.open
        context: Qt.ApplicationShortcut
        onActivated: preferences.open = false
    }

    PanelWindow {
        id: overlay
        anchors { top: true; bottom: true; left: true; right: true }
        visible: preferences.open
        focusable: preferences.open
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: preferences.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "phasor-settings"

        Rectangle {
            anchors.fill: parent
            color: Theme.Tokens.overlayScrim
            MouseArea { anchors.fill: parent; onClicked: preferences.open = false }
        }

        Rectangle {
            width: Math.min(960, parent.width - 48)
            height: Math.min(680, parent.height - 48)
            anchors.centerIn: parent
            radius: Theme.Tokens.radiusLarge
            color: Theme.Tokens.surface
            border.width: 1
            border.color: Theme.Tokens.separator

            RowLayout {
                anchors.fill: parent
                spacing: 0

                Rectangle {
                    Layout.preferredWidth: 204
                    Layout.fillHeight: true
                    radius: Theme.Tokens.radiusLarge
                    color: Theme.Tokens.surfaceRaised

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.Tokens.spacingL
                        spacing: Theme.Tokens.spacingS

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.Tokens.spacingS
                            Rectangle {
                                Layout.preferredWidth: 30
                                Layout.preferredHeight: 30
                                radius: 10
                                color: Theme.Tokens.accent
                                Text { anchors.centerIn: parent; text: "P"; color: Theme.Tokens.background; font.pixelSize: 16; font.bold: true }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text { text: "Phasor"; color: Theme.Tokens.textPrimary; font.pixelSize: 16; font.bold: true }
                                Text { text: "Settings"; color: Theme.Tokens.textSecondary; font.pixelSize: 11 }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.Tokens.separator }

                        Repeater {
                            model: [
                                { id: "appearance", title: "Appearance", glyph: "◐" },
                                { id: "shell", title: "Shell", glyph: "▦" },
                                { id: "system", title: "System", glyph: "⌘" },
                                { id: "shortcuts", title: "Shortcuts", glyph: "⌨" },
                                { id: "about", title: "About", glyph: "ⓘ" }
                            ]
                            delegate: Button {
                                id: pageButton
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 40
                                leftPadding: Theme.Tokens.spacingS
                                rightPadding: Theme.Tokens.spacingS
                                onClicked: {
                                    preferences.section = modelData.id
                                    if (modelData.id === "system") preferences.refreshSystem()
                                }
                                background: Rectangle {
                                    radius: Theme.Tokens.radiusSmall
                                    color: preferences.section === pageButton.modelData.id ? Theme.Tokens.surface : "transparent"
                                    border.width: preferences.section === pageButton.modelData.id ? 1 : 0
                                    border.color: Theme.Tokens.separator
                                }
                                contentItem: RowLayout {
                                    spacing: Theme.Tokens.spacingS
                                    Text { text: pageButton.modelData.glyph; color: preferences.section === pageButton.modelData.id ? Theme.Tokens.accent : Theme.Tokens.textSecondary; font.pixelSize: 16; horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: 24 }
                                    Text { text: pageButton.modelData.title; color: Theme.Tokens.textPrimary; font.pixelSize: 13; Layout.fillWidth: true }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }

                        Text {
                            Layout.fillWidth: true
                            text: "A calm workspace, tuned to you."
                            color: Theme.Tokens.textSecondary
                            font.pixelSize: 11
                            wrapMode: Text.Wrap
                        }
                    }
                }

                Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: Theme.Tokens.separator }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: Theme.Tokens.spacingXL
                    spacing: Theme.Tokens.spacingM

                    RowLayout {
                        Layout.fillWidth: true
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: preferences.section === "appearance" ? "Appearance" : preferences.section === "shell" ? "Shell" : preferences.section === "system" ? "System" : preferences.section === "shortcuts" ? "Keyboard shortcuts" : "About Phasor"
                                color: Theme.Tokens.textPrimary
                                font.pixelSize: 23
                                font.bold: true
                            }
                            Text {
                                text: preferences.section === "appearance" ? "Make the desktop feel like yours." : preferences.section === "shell" ? "Choose which Phasor surfaces are active." : preferences.section === "system" ? "Control the devices and services available on this system." : preferences.section === "shortcuts" ? "The default keys for common Phasor actions." : "A portable desktop shell built around your workflow."
                                color: Theme.Tokens.textSecondary
                                font.pixelSize: 12
                            }
                        }
                        Components.PhasorButton { text: "Close"; onClicked: preferences.open = false }
                    }

                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.Tokens.separator }

                    ScrollView {
                        id: pageScroll
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        ScrollBar.vertical.policy: ScrollBar.AsNeeded

                        ColumnLayout {
                            width: pageScroll.availableWidth
                            spacing: Theme.Tokens.spacingM

                            ColumnLayout {
                                visible: preferences.section === "appearance"
                                Layout.fillWidth: true
                                spacing: Theme.Tokens.spacingM

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: themeCard.implicitHeight + Theme.Tokens.spacingL * 2
                                    radius: Theme.Tokens.radiusMedium
                                    color: Theme.Tokens.surfaceRaised
                                    border.width: 1
                                    border.color: Theme.Tokens.separator
                                    ColumnLayout {
                                        id: themeCard
                                        anchors.fill: parent
                                        anchors.margins: Theme.Tokens.spacingL
                                        spacing: Theme.Tokens.spacingM
                                        Text { text: "Color scheme"; color: Theme.Tokens.textPrimary; font.pixelSize: 14; font.bold: true }
                                        Text { text: "Use your system preference or choose a theme for Phasor."; color: Theme.Tokens.textSecondary; font.pixelSize: 11; wrapMode: Text.Wrap }
                                        ComboBox {
                                            id: schemeBox
                                            model: ["System", "Light", "Dark"]
                                            enabled: !preferences.loading && !preferences.savingAppearance
                                            implicitWidth: 220
                                            implicitHeight: 38
                                            onCurrentIndexChanged: preferences.markAppearanceDirty()
                                            contentItem: Text {
                                                leftPadding: Theme.Tokens.spacingM
                                                rightPadding: schemeBox.indicator.width + Theme.Tokens.spacingM
                                                text: schemeBox.displayText
                                                color: Theme.Tokens.textPrimary
                                                font: schemeBox.font
                                                verticalAlignment: Text.AlignVCenter
                                                elide: Text.ElideRight
                                            }
                                            indicator: Text {
                                                x: schemeBox.width - width - Theme.Tokens.spacingM
                                                y: (schemeBox.height - height) / 2
                                                text: "⌄"
                                                color: Theme.Tokens.textSecondary
                                                font.pixelSize: 15
                                            }
                                            background: Rectangle {
                                                radius: Theme.Tokens.radiusSmall
                                                color: Theme.Tokens.surface
                                                border.width: schemeBox.activeFocus ? 2 : 1
                                                border.color: schemeBox.activeFocus ? Theme.Tokens.accent : Theme.Tokens.separator
                                            }
                                            delegate: ItemDelegate {
                                                id: schemeDelegate
                                                required property var modelData
                                                required property int index
                                                width: schemeBox.width
                                                highlighted: schemeBox.highlightedIndex === index
                                                contentItem: Text {
                                                    text: modelData
                                                    color: schemeDelegate.highlighted ? Theme.Tokens.background : Theme.Tokens.textPrimary
                                                    font: schemeBox.font
                                                    verticalAlignment: Text.AlignVCenter
                                                    leftPadding: Theme.Tokens.spacingM
                                                }
                                                background: Rectangle { color: highlighted ? Theme.Tokens.accent : Theme.Tokens.surface }
                                            }
                                            popup: Popup {
                                                y: schemeBox.height - 1
                                                width: schemeBox.width
                                                implicitHeight: contentItem.implicitHeight
                                                padding: 1
                                                contentItem: ListView {
                                                    clip: true
                                                    implicitHeight: contentHeight
                                                    model: schemeBox.popup.visible ? schemeBox.delegateModel : null
                                                    currentIndex: schemeBox.highlightedIndex
                                                }
                                                background: Rectangle {
                                                    color: Theme.Tokens.surface
                                                    border.width: 1
                                                    border.color: Theme.Tokens.separator
                                                    radius: Theme.Tokens.radiusSmall
                                                }
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: accentCard.implicitHeight + Theme.Tokens.spacingL * 2
                                    radius: Theme.Tokens.radiusMedium
                                    color: Theme.Tokens.surfaceRaised
                                    border.width: 1
                                    border.color: Theme.Tokens.separator
                                    ColumnLayout {
                                        id: accentCard
                                        anchors.fill: parent
                                        anchors.margins: Theme.Tokens.spacingL
                                        spacing: Theme.Tokens.spacingS
                                        Text { text: "Accent color"; color: Theme.Tokens.textPrimary; font.pixelSize: 14; font.bold: true }
                                        Text { text: "Used for focus, highlights, and interactive controls."; color: Theme.Tokens.textSecondary; font.pixelSize: 11; wrapMode: Text.Wrap }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.Tokens.spacingS
                                            Components.PhasorTextField {
                                                id: accentInput
                                                Layout.preferredWidth: 150
                                                placeholderText: "#8bd5ca"
                                                enabled: !preferences.loading && !preferences.savingAppearance
                                                onTextChanged: preferences.markAppearanceDirty()
                                            }
                                            Repeater {
                                                model: ["#8bd5ca", "#8aadf4", "#c6a0f6", "#f5a97f", "#a6da95", "#ed8796"]
                                                delegate: Button {
                                                    required property string modelData
                                                    implicitWidth: 28
                                                    implicitHeight: 28
                                                    onClicked: { accentInput.text = modelData; preferences.markAppearanceDirty() }
                                                    background: Rectangle {
                                                        radius: width / 2
                                                        color: modelData
                                                        border.width: accentInput.text.toLowerCase() === modelData ? 3 : 1
                                                        border.color: Theme.Tokens.textPrimary
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: motionCard.implicitHeight + Theme.Tokens.spacingL * 2
                                    radius: Theme.Tokens.radiusMedium
                                    color: Theme.Tokens.surfaceRaised
                                    border.width: 1
                                    border.color: Theme.Tokens.separator
                                    RowLayout {
                                        id: motionCard
                                        anchors.fill: parent
                                        anchors.margins: Theme.Tokens.spacingL
                                        spacing: Theme.Tokens.spacingM
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.Tokens.spacingXS
                                            Text { text: "Reduced motion"; color: Theme.Tokens.textPrimary; font.pixelSize: 14; font.bold: true }
                                            Text { text: "Turn off animated transitions throughout Phasor."; color: Theme.Tokens.textSecondary; font.pixelSize: 11; wrapMode: Text.Wrap }
                                        }
                                        Components.PhasorSwitch {
                                            id: motionSwitch
                                            enabled: !preferences.loading && !preferences.savingAppearance
                                            onToggled: preferences.markAppearanceDirty()
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: wallpaperCard.implicitHeight + Theme.Tokens.spacingL * 2
                                    radius: Theme.Tokens.radiusMedium
                                    color: Theme.Tokens.surfaceRaised
                                    border.width: 1
                                    border.color: Theme.Tokens.separator
                                    ColumnLayout {
                                        id: wallpaperCard
                                        anchors.fill: parent
                                        anchors.margins: Theme.Tokens.spacingL
                                        spacing: Theme.Tokens.spacingS
                                        Text { text: "Wallpaper"; color: Theme.Tokens.textPrimary; font.pixelSize: 14; font.bold: true }
                                        Text { text: "Use an image path, or clear it to show the Phasor background color."; color: Theme.Tokens.textSecondary; font.pixelSize: 11; wrapMode: Text.Wrap }
                                        Components.PhasorTextField {
                                            id: wallpaperInput
                                            Layout.fillWidth: true
                                            placeholderText: "/home/you/Pictures/wallpaper.jpg"
                                            enabled: !preferences.loading && !preferences.savingAppearance
                                            onTextChanged: preferences.markAppearanceDirty()
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { Layout.fillWidth: true; text: preferences.loading ? "Loading preferences…" : preferences.appearanceDirty ? "You have unsaved appearance changes" : "Changes apply across Phasor"; color: Theme.Tokens.textSecondary; font.pixelSize: 11; wrapMode: Text.Wrap }
                                    Components.PhasorButton { text: "Reset"; enabled: !preferences.loading && !preferences.savingAppearance; onClicked: preferences.resetAppearance() }
                                    Components.PhasorButton { text: preferences.savingAppearance ? "Saving…" : "Save changes"; enabled: preferences.appearanceDirty && !preferences.loading && !preferences.savingAppearance; onClicked: preferences.saveAppearance() }
                                }
                            }

                            ColumnLayout {
                                visible: preferences.section === "shell"
                                Layout.fillWidth: true
                                spacing: Theme.Tokens.spacingM
                                Text { Layout.fillWidth: true; text: "Enable or hide Phasor surfaces. Your changes take effect while the session is running."; color: Theme.Tokens.textSecondary; font.pixelSize: 12; wrapMode: Text.Wrap }

                                Repeater {
                                    model: [
                                        { id: "dev.phasor.bar", title: "Top Bar", detail: "Spaces, clock, tray, notifications, clipboard, and quick actions." },
                                        { id: "dev.phasor.launcher", title: "Launcher", detail: "Search applications, files, and Spaces." },
                                        { id: "dev.phasor.desktop", title: "Desktop shortcuts", detail: "Home, Applications, and Settings shortcuts over the wallpaper." },
                                        { id: "dev.phasor.dock", title: "Dock", detail: "Focus and close running windows from the bottom edge." },
                                        { id: "dev.phasor.commands", title: "Command palette", detail: "Search for Phasor actions and open Settings pages." },
                                        { id: "dev.phasor.clipboard", title: "Clipboard history", detail: "Keep recent clipboard items available from the Bar." },
                                        { id: "dev.phasor.notifications", title: "Notification controls", detail: "Show notification count and Do Not Disturb controls." },
                                        { id: "dev.phasor.screenshot", title: "Screenshot action", detail: "Expose the screen capture action in the Bar." }
                                    ]
                                    delegate: Rectangle {
                                        id: pluginCard
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: pluginRow.implicitHeight + Theme.Tokens.spacingL * 2
                                        radius: Theme.Tokens.radiusMedium
                                        color: Theme.Tokens.surfaceRaised
                                        border.width: 1
                                        border.color: Theme.Tokens.separator
                                        RowLayout {
                                            id: pluginRow
                                            anchors.fill: parent
                                            anchors.margins: Theme.Tokens.spacingL
                                            spacing: Theme.Tokens.spacingM
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: Theme.Tokens.spacingXS
                                                Text { text: pluginCard.modelData.title; color: Theme.Tokens.textPrimary; font.pixelSize: 14; font.bold: true }
                                                Text { Layout.fillWidth: true; text: pluginCard.modelData.detail; color: Theme.Tokens.textSecondary; font.pixelSize: 11; wrapMode: Text.Wrap }
                                            }
                                            Components.PhasorSwitch {
                                                enabled: !preferences.loading && !preferences.savingPlugin
                                                checked: preferences.pluginEnabled(pluginCard.modelData.id)
                                                onClicked: preferences.setPluginEnabled(pluginCard.modelData.id, checked)
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: launcherBehavior.implicitHeight + Theme.Tokens.spacingL * 2
                                    radius: Theme.Tokens.radiusMedium
                                    color: Theme.Tokens.surfaceRaised
                                    border.width: 1
                                    border.color: Theme.Tokens.separator
                                    ColumnLayout {
                                        id: launcherBehavior
                                        anchors.fill: parent
                                        anchors.margins: Theme.Tokens.spacingL
                                        spacing: Theme.Tokens.spacingS
                                        Text { text: "Launcher"; color: Theme.Tokens.textPrimary; font.pixelSize: 14; font.bold: true }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: Theme.Tokens.spacingXS
                                                Text { text: "Show recent apps"; color: Theme.Tokens.textPrimary; font.pixelSize: 12 }
                                                Text { text: "Rank recently opened apps with your favorites when search is empty."; color: Theme.Tokens.textSecondary; font.pixelSize: 11; wrapMode: Text.Wrap }
                                            }
                                            Components.PhasorSwitch { id: launcherRecentsSwitch; enabled: !preferences.loading && !preferences.savingPreferences }
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: workspacePreferences.implicitHeight + Theme.Tokens.spacingL * 2
                                    radius: Theme.Tokens.radiusMedium
                                    color: Theme.Tokens.surfaceRaised
                                    border.width: 1
                                    border.color: Theme.Tokens.separator
                                    ColumnLayout {
                                        id: workspacePreferences
                                        anchors.fill: parent
                                        anchors.margins: Theme.Tokens.spacingL
                                        spacing: Theme.Tokens.spacingM
                                        Text { text: "Spaces and windows"; color: Theme.Tokens.textPrimary; font.pixelSize: 14; font.bold: true }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text { Layout.fillWidth: true; text: "Number of Spaces"; color: Theme.Tokens.textPrimary; font.pixelSize: 12 }
                                            SpinBox {
                                                id: workspaceCount
                                                from: 1
                                                to: 32
                                                value: 9
                                                editable: true
                                                enabled: !preferences.loading && !preferences.savingPreferences
                                            }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.Tokens.spacingXS
                                            RowLayout {
                                                Layout.fillWidth: true
                                                Text { Layout.fillWidth: true; text: "Space transition"; color: Theme.Tokens.textPrimary; font.pixelSize: 12 }
                                                Text { text: Math.round(spaceAnimationSlider.value) + " ms"; color: Theme.Tokens.textSecondary; font.pixelSize: 11 }
                                            }
                                            Slider {
                                                id: spaceAnimationSlider
                                                Layout.fillWidth: true
                                                from: 0
                                                to: 2000
                                                stepSize: 50
                                                value: 200
                                                enabled: !preferences.loading && !preferences.savingPreferences
                                            }
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text { Layout.fillWidth: true; text: "Focus behavior"; color: Theme.Tokens.textPrimary; font.pixelSize: 12 }
                                            ComboBox {
                                                id: focusModeBox
                                                model: ["Click to focus", "Focus follows pointer"]
                                                enabled: !preferences.loading && !preferences.savingPreferences
                                            }
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: Theme.Tokens.spacingXS
                                                Text { text: "Focus newly activated windows"; color: Theme.Tokens.textPrimary; font.pixelSize: 12 }
                                                Text { text: "Raise a window when an application requests focus."; color: Theme.Tokens.textSecondary; font.pixelSize: 11; wrapMode: Text.Wrap }
                                            }
                                            Components.PhasorSwitch { id: raiseOnFocusSwitch; enabled: !preferences.loading && !preferences.savingPreferences }
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: dockPreferences.implicitHeight + Theme.Tokens.spacingL * 2
                                    radius: Theme.Tokens.radiusMedium
                                    color: Theme.Tokens.surfaceRaised
                                    border.width: 1
                                    border.color: Theme.Tokens.separator
                                    ColumnLayout {
                                        id: dockPreferences
                                        anchors.fill: parent
                                        anchors.margins: Theme.Tokens.spacingL
                                        spacing: Theme.Tokens.spacingM
                                        Text { text: "Dock"; color: Theme.Tokens.textPrimary; font.pixelSize: 14; font.bold: true }
                                        Text { Layout.fillWidth: true; text: "The Dock can be enabled above. Choose which window controls it shows."; color: Theme.Tokens.textSecondary; font.pixelSize: 11; wrapMode: Text.Wrap }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: Theme.Tokens.spacingXS
                                                Text { text: "Show close buttons"; color: Theme.Tokens.textPrimary; font.pixelSize: 12 }
                                                Text { text: "Put a close control on each running window."; color: Theme.Tokens.textSecondary; font.pixelSize: 11; wrapMode: Text.Wrap }
                                            }
                                            Components.PhasorSwitch { id: dockCloseButtonsSwitch; enabled: !preferences.loading && !preferences.savingPreferences }
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: Theme.Tokens.spacingXS
                                                Text { text: "Show empty Dock state"; color: Theme.Tokens.textPrimary; font.pixelSize: 12 }
                                                Text { text: "Keep the Dock visible with an empty-state label when no windows are open."; color: Theme.Tokens.textSecondary; font.pixelSize: 11; wrapMode: Text.Wrap }
                                            }
                                            Components.PhasorSwitch { id: dockEmptyStateSwitch; enabled: !preferences.loading && !preferences.savingPreferences }
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { Layout.fillWidth: true; text: "Workspace changes update the active Phasor Mango session."; color: Theme.Tokens.textSecondary; font.pixelSize: 11; wrapMode: Text.Wrap }
                                    Components.PhasorButton { text: preferences.savingPreferences ? "Saving…" : "Save shell settings"; enabled: !preferences.loading && !preferences.savingPreferences; onClicked: preferences.saveShellPreferences() }
                                }
                            }

                            ColumnLayout {
                                visible: preferences.section === "system"
                                Layout.fillWidth: true
                                spacing: Theme.Tokens.spacingM

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { Layout.fillWidth: true; text: preferences.loadingSystem ? "Checking available controls…" : "Controls use the services installed on this system."; color: Theme.Tokens.textSecondary; font.pixelSize: 11; wrapMode: Text.Wrap }
                                    Components.PhasorButton { text: "Refresh"; enabled: !preferences.loadingSystem && !preferences.systemBusy; onClicked: preferences.refreshSystem() }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: networkRow.implicitHeight + Theme.Tokens.spacingL * 2
                                    radius: Theme.Tokens.radiusMedium
                                    color: Theme.Tokens.surfaceRaised
                                    border.width: 1
                                    border.color: Theme.Tokens.separator
                                    RowLayout {
                                        id: networkRow
                                        anchors.fill: parent
                                        anchors.margins: Theme.Tokens.spacingL
                                        spacing: Theme.Tokens.spacingM
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.Tokens.spacingXS
                                            Text { text: "Wi-Fi"; color: Theme.Tokens.textPrimary; font.pixelSize: 14; font.bold: true }
                                            Text { Layout.fillWidth: true; text: preferences.systemAvailable(preferences.networkStatus) ? "NetworkManager · " + String(preferences.networkStatus.state || "ready") + (preferences.networkStatus.connectivity ? " · " + preferences.networkStatus.connectivity : "") : preferences.systemError(preferences.networkStatus, "Wi-Fi controls"); color: Theme.Tokens.textSecondary; font.pixelSize: 11; wrapMode: Text.Wrap }
                                        }
                                        Components.PhasorSwitch {
                                            enabled: preferences.systemAvailable(preferences.networkStatus) && !preferences.systemBusy
                                            checked: Boolean(preferences.networkStatus && preferences.networkStatus.wifiEnabled)
                                            onClicked: preferences.changeSystem("network.set_wifi", { enabled: checked }, "networkStatus")
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: bluetoothRow.implicitHeight + Theme.Tokens.spacingL * 2
                                    radius: Theme.Tokens.radiusMedium
                                    color: Theme.Tokens.surfaceRaised
                                    border.width: 1
                                    border.color: Theme.Tokens.separator
                                    RowLayout {
                                        id: bluetoothRow
                                        anchors.fill: parent
                                        anchors.margins: Theme.Tokens.spacingL
                                        spacing: Theme.Tokens.spacingM
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.Tokens.spacingXS
                                            Text { text: "Bluetooth"; color: Theme.Tokens.textPrimary; font.pixelSize: 14; font.bold: true }
                                            Text { Layout.fillWidth: true; text: preferences.systemAvailable(preferences.bluetoothStatus) ? "Bluetooth adapter is " + (preferences.bluetoothStatus.powered ? "on" : "off") + "." : preferences.systemError(preferences.bluetoothStatus, "Bluetooth"); color: Theme.Tokens.textSecondary; font.pixelSize: 11; wrapMode: Text.Wrap }
                                        }
                                        Components.PhasorSwitch {
                                            enabled: preferences.systemAvailable(preferences.bluetoothStatus) && !preferences.systemBusy
                                            checked: Boolean(preferences.bluetoothStatus && preferences.bluetoothStatus.powered)
                                            onClicked: preferences.changeSystem("bluetooth.set_power", { enabled: checked }, "bluetoothStatus")
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: audioColumn.implicitHeight + Theme.Tokens.spacingL * 2
                                    radius: Theme.Tokens.radiusMedium
                                    color: Theme.Tokens.surfaceRaised
                                    border.width: 1
                                    border.color: Theme.Tokens.separator
                                    ColumnLayout {
                                        id: audioColumn
                                        anchors.fill: parent
                                        anchors.margins: Theme.Tokens.spacingL
                                        spacing: Theme.Tokens.spacingS
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text { Layout.fillWidth: true; text: "Sound"; color: Theme.Tokens.textPrimary; font.pixelSize: 14; font.bold: true }
                                            Text { text: preferences.systemAvailable(preferences.audioStatus) ? Math.round(preferences.systemNumber(preferences.audioStatus, "volume") * 100) + "%" : "Unavailable"; color: Theme.Tokens.textSecondary; font.pixelSize: 11 }
                                            Components.PhasorButton { text: preferences.audioStatus && preferences.audioStatus.muted ? "Unmute" : "Mute"; enabled: preferences.systemAvailable(preferences.audioStatus) && !preferences.systemBusy; onClicked: preferences.changeSystem("audio.toggle_mute", {}, "audioStatus") }
                                        }
                                        Slider {
                                            Layout.fillWidth: true
                                            from: 0
                                            to: 150
                                            stepSize: 1
                                            value: preferences.systemAvailable(preferences.audioStatus) ? Math.round(preferences.systemNumber(preferences.audioStatus, "volume") * 100) : 0
                                            enabled: preferences.systemAvailable(preferences.audioStatus) && !preferences.systemBusy
                                            onMoved: preferences.changeSystem("audio.set_volume", { value: value / 100 }, "audioStatus")
                                        }
                                        Text { Layout.fillWidth: true; text: preferences.systemAvailable(preferences.audioStatus) ? "PipeWire output volume" : preferences.systemError(preferences.audioStatus, "Audio controls"); color: Theme.Tokens.textSecondary; font.pixelSize: 11; wrapMode: Text.Wrap }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: brightnessColumn.implicitHeight + Theme.Tokens.spacingL * 2
                                    radius: Theme.Tokens.radiusMedium
                                    color: Theme.Tokens.surfaceRaised
                                    border.width: 1
                                    border.color: Theme.Tokens.separator
                                    ColumnLayout {
                                        id: brightnessColumn
                                        anchors.fill: parent
                                        anchors.margins: Theme.Tokens.spacingL
                                        spacing: Theme.Tokens.spacingS
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text { Layout.fillWidth: true; text: "Display brightness"; color: Theme.Tokens.textPrimary; font.pixelSize: 14; font.bold: true }
                                            Text { text: preferences.systemAvailable(preferences.brightnessStatus) ? Math.round(preferences.systemNumber(preferences.brightnessStatus, "percent")) + "%" : "Unavailable"; color: Theme.Tokens.textSecondary; font.pixelSize: 11 }
                                        }
                                        Slider {
                                            Layout.fillWidth: true
                                            from: 0
                                            to: 100
                                            stepSize: 1
                                            value: preferences.systemAvailable(preferences.brightnessStatus) ? Math.round(preferences.systemNumber(preferences.brightnessStatus, "percent")) : 0
                                            enabled: preferences.systemAvailable(preferences.brightnessStatus) && !preferences.systemBusy
                                            onMoved: preferences.changeSystem("brightness.set", { percent: value }, "brightnessStatus")
                                        }
                                        Text { Layout.fillWidth: true; text: preferences.systemAvailable(preferences.brightnessStatus) ? "Backlight device: " + String(preferences.brightnessStatus.device || "default") : preferences.systemError(preferences.brightnessStatus, "Display brightness"); color: Theme.Tokens.textSecondary; font.pixelSize: 11; wrapMode: Text.Wrap }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: notificationsRow.implicitHeight + Theme.Tokens.spacingL * 2
                                    radius: Theme.Tokens.radiusMedium
                                    color: Theme.Tokens.surfaceRaised
                                    border.width: 1
                                    border.color: Theme.Tokens.separator
                                    RowLayout {
                                        id: notificationsRow
                                        anchors.fill: parent
                                        anchors.margins: Theme.Tokens.spacingL
                                        spacing: Theme.Tokens.spacingM
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.Tokens.spacingXS
                                            Text { text: "Do Not Disturb"; color: Theme.Tokens.textPrimary; font.pixelSize: 14; font.bold: true }
                                            Text { Layout.fillWidth: true; text: preferences.systemAvailable(preferences.notificationsStatus) ? String(preferences.notificationsStatus.count || 0) + " notifications · SwayNotificationCenter" : preferences.systemError(preferences.notificationsStatus, "Notification controls"); color: Theme.Tokens.textSecondary; font.pixelSize: 11; wrapMode: Text.Wrap }
                                        }
                                        Components.PhasorSwitch {
                                            enabled: preferences.systemAvailable(preferences.notificationsStatus) && !preferences.systemBusy
                                            checked: Boolean(preferences.notificationsStatus && preferences.notificationsStatus.doNotDisturb)
                                            onClicked: preferences.changeDoNotDisturb(checked)
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: preferences.systemErrorText.length > 0
                                    text: preferences.systemErrorText
                                    color: Theme.Tokens.danger
                                    font.pixelSize: 11
                                    wrapMode: Text.Wrap
                                }
                            }

                            ColumnLayout {
                                visible: preferences.section === "shortcuts"
                                Layout.fillWidth: true
                                spacing: Theme.Tokens.spacingM
                                Text { Layout.fillWidth: true; text: "Choose the main shortcuts for Launcher, Commands, and Settings. Changes are applied by the active Phasor Mango session."; color: Theme.Tokens.textSecondary; font.pixelSize: 12; wrapMode: Text.Wrap }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: configurableShortcuts.implicitHeight + Theme.Tokens.spacingL * 2
                                    radius: Theme.Tokens.radiusMedium
                                    color: Theme.Tokens.surfaceRaised
                                    border.width: 1
                                    border.color: Theme.Tokens.separator
                                    ColumnLayout {
                                        id: configurableShortcuts
                                        anchors.fill: parent
                                        anchors.margins: Theme.Tokens.spacingL
                                        spacing: Theme.Tokens.spacingM
                                        Text { text: "Shortcut assignments"; color: Theme.Tokens.textPrimary; font.pixelSize: 14; font.bold: true }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text { Layout.fillWidth: true; text: "Launcher"; color: Theme.Tokens.textPrimary; font.pixelSize: 12 }
                                            ComboBox { id: launcherShortcutBox; model: preferences.launcherShortcutChoices; implicitWidth: 210; enabled: !preferences.loading && !preferences.savingPreferences }
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text { Layout.fillWidth: true; text: "Commands"; color: Theme.Tokens.textPrimary; font.pixelSize: 12 }
                                            ComboBox { id: commandShortcutBox; model: preferences.commandShortcutChoices; implicitWidth: 210; enabled: !preferences.loading && !preferences.savingPreferences }
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text { Layout.fillWidth: true; text: "Settings"; color: Theme.Tokens.textPrimary; font.pixelSize: 12 }
                                            ComboBox { id: settingsShortcutBox; model: preferences.settingsShortcutChoices; implicitWidth: 210; enabled: !preferences.loading && !preferences.savingPreferences }
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text { Layout.fillWidth: true; text: preferences.displayShortcut(preferences.settingsData.commands ? preferences.settingsData.commands.shortcut : "Super+/") + " opens Commands. The palette includes a shortcut to return here."; color: Theme.Tokens.textSecondary; font.pixelSize: 11; wrapMode: Text.Wrap }
                                            Components.PhasorButton { text: preferences.savingPreferences ? "Saving…" : "Save shortcuts"; enabled: !preferences.loading && !preferences.savingPreferences; onClicked: preferences.saveShortcutPreferences() }
                                        }
                                    }
                                }

                                Text { Layout.fillWidth: true; text: "Other active session shortcuts"; color: Theme.Tokens.textPrimary; font.pixelSize: 14; font.bold: true }
                                Repeater {
                                    model: [
                                        { keys: "Super + Shift + V", action: "Open clipboard history" },
                                        { keys: "Super + Ctrl + ← / →", action: "Move between Spaces" },
                                        { keys: "Super + Ctrl + 1…9", action: "Switch to a Space" },
                                        { keys: "Super + Shift + Ctrl + 1…9", action: "Move a window to a Space" },
                                        { keys: "Super + W", action: "Close the focused window" },
                                        { keys: "Super + ↑ / ↓", action: "Maximize or minimize the focused window" }
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: shortcutRow.implicitHeight + Theme.Tokens.spacingM * 2
                                        radius: Theme.Tokens.radiusSmall
                                        color: Theme.Tokens.surfaceRaised
                                        RowLayout {
                                            id: shortcutRow
                                            anchors.fill: parent
                                            anchors.margins: Theme.Tokens.spacingM
                                            Text { text: modelData.keys; color: Theme.Tokens.accent; font.pixelSize: 11; font.bold: true; Layout.preferredWidth: 190; wrapMode: Text.Wrap }
                                            Text { text: modelData.action; color: Theme.Tokens.textPrimary; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.Wrap }
                                        }
                                    }
                                }
                                Text { Layout.fillWidth: true; text: "Workspace, focus, and shortcut changes are written to the private Phasor session config. A custom Mango config remains in control when one is explicitly selected."; color: Theme.Tokens.textSecondary; font.pixelSize: 11; wrapMode: Text.Wrap }
                            }

                            ColumnLayout {
                                visible: preferences.section === "about"
                                Layout.fillWidth: true
                                spacing: Theme.Tokens.spacingM
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: aboutCard.implicitHeight + Theme.Tokens.spacingXL * 2
                                    radius: Theme.Tokens.radiusMedium
                                    color: Theme.Tokens.surfaceRaised
                                    border.width: 1
                                    border.color: Theme.Tokens.separator
                                    ColumnLayout {
                                        id: aboutCard
                                        anchors.fill: parent
                                        anchors.margins: Theme.Tokens.spacingXL
                                        spacing: Theme.Tokens.spacingM
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.Tokens.spacingM
                                            Rectangle {
                                                Layout.preferredWidth: 64
                                                Layout.preferredHeight: 64
                                                radius: 20
                                                color: Theme.Tokens.accent
                                                Text { anchors.centerIn: parent; text: "P"; color: Theme.Tokens.background; font.pixelSize: 34; font.bold: true }
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: Theme.Tokens.spacingXS
                                                Text { text: "Phasor"; color: Theme.Tokens.textPrimary; font.pixelSize: 22; font.bold: true }
                                                Text { text: "A portable desktop shell for MangoWM."; color: Theme.Tokens.textSecondary; font.pixelSize: 12; wrapMode: Text.Wrap }
                                            }
                                        }
                                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.Tokens.separator }
                                        Text { Layout.fillWidth: true; text: "Phasor keeps desktop services behind phasor-core and presents the workspace through Quickshell. Preview is the document and image application; Quick Look from the file workflow is on the product roadmap."; color: Theme.Tokens.textSecondary; font.pixelSize: 12; wrapMode: Text.Wrap; lineHeight: 1.25 }
                                        Text { text: "Project source: github.com/tzachmost/phasor"; color: Theme.Tokens.accent; font.pixelSize: 12 }
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: preferences.errorText.length > 0 || preferences.statusText.length > 0
                        text: preferences.errorText.length > 0 ? preferences.errorText : preferences.statusText
                        color: preferences.errorText.length > 0 ? Theme.Tokens.danger : Theme.Tokens.success
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Text { Layout.fillWidth: true; text: preferences.displayShortcut(preferences.settingsData.settings ? preferences.settingsData.settings.shortcut : "Super+,") + " opens Settings · " + preferences.displayShortcut(preferences.settingsData.commands ? preferences.settingsData.commands.shortcut : "Super+/") + " opens Commands"; color: Theme.Tokens.textSecondary; font.pixelSize: 11 }
                        Components.PhasorButton { text: "Close"; onClicked: preferences.open = false }
                    }
                }
            }
        }
    }
}
