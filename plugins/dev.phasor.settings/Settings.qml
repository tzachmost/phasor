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
    property var settingsData: ({})
    property string errorText: ""
    property string statusText: ""

    function load() {
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
            const schemes = ["system", "light", "dark"]
            schemeBox.currentIndex = Math.max(0, schemes.indexOf(result.appearance.theme))
            accentInput.text = result.appearance.accent
            motionSwitch.checked = result.appearance.reducedMotion
            wallpaperInput.text = result.appearance.wallpaper
            loading = false
        })
    }

    function save() {
        const schemes = ["system", "light", "dark"]
        const patch = {
            appearance: {
                theme: schemes[schemeBox.currentIndex],
                accent: accentInput.text.trim(),
                reducedMotion: motionSwitch.checked,
                wallpaper: wallpaperInput.text.trim()
            },
            plugins: {
                "dev.phasor.dock": { enabled: dockSwitch.checked },
                "dev.phasor.desktop": { enabled: desktopSwitch.checked }
            }
        }
        errorText = ""
        statusText = ""
        phasor.request("settings.update", { patch: patch }, function(result) {
            if (result.error) {
                errorText = result.error
                return
            }
            settingsData = result
            statusText = "Settings saved"
        })
    }

    onOpenChanged: {
        if (open) {
            load()
            Qt.callLater(function() { schemeBox.forceActiveFocus() })
        }
    }

    Connections {
        target: preferences.phasor
        function onEventReceived(event) {
            if (event.type === "action" && event.name === "settings.toggle") preferences.open = !preferences.open
            if (event.type === "event" && event.name === "settings.changed" && preferences.open) preferences.load()
        }
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
            width: Math.min(560, parent.width - 40)
            height: Math.min(520, parent.height - 48)
            anchors.centerIn: parent
            radius: Theme.Tokens.radiusLarge
            color: Theme.Tokens.surface
            border.width: 1
            border.color: Theme.Tokens.borderFocused

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.Tokens.spacingXL
                spacing: Theme.Tokens.spacingL

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: "Settings"
                        color: Theme.Tokens.textPrimary
                        font.pixelSize: 22
                        font.bold: true
                    }
                    Components.PhasorButton { text: "Close"; onClicked: preferences.open = false }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.Tokens.separator }

                RowLayout {
                    Layout.fillWidth: true
                    Text { Layout.fillWidth: true; text: "Color scheme"; color: Theme.Tokens.textPrimary; font.pixelSize: 14 }
                    ComboBox {
                        id: schemeBox
                        model: ["System", "Light", "Dark"]
                        enabled: !preferences.loading
                        implicitWidth: 180
                        implicitHeight: 36
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
                            color: Theme.Tokens.surfaceRaised
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
                            background: Rectangle {
                                color: highlighted ? Theme.Tokens.accent : Theme.Tokens.surface
                            }
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

                RowLayout {
                    Layout.fillWidth: true
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.Tokens.spacingXS
                        Text { text: "Desktop shortcuts"; color: Theme.Tokens.textPrimary; font.pixelSize: 14 }
                        Text { text: "Show Home, Applications, and Settings on the desktop"; color: Theme.Tokens.textSecondary; font.pixelSize: 11 }
                    }
                    Components.PhasorSwitch {
                        id: desktopSwitch
                        enabled: !preferences.loading
                        checked: Boolean(preferences.settingsData.plugins && preferences.settingsData.plugins["dev.phasor.desktop"] && preferences.settingsData.plugins["dev.phasor.desktop"].enabled)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.Tokens.spacingXS
                        Text { text: "Dock"; color: Theme.Tokens.textPrimary; font.pixelSize: 14 }
                        Text { text: "Show running windows at the bottom of the screen"; color: Theme.Tokens.textSecondary; font.pixelSize: 11 }
                    }
                    Components.PhasorSwitch {
                        id: dockSwitch
                        enabled: !preferences.loading
                        checked: Boolean(preferences.settingsData.plugins && preferences.settingsData.plugins["dev.phasor.dock"] && preferences.settingsData.plugins["dev.phasor.dock"].enabled)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text { Layout.fillWidth: true; text: "Accent color"; color: Theme.Tokens.textPrimary; font.pixelSize: 14 }
                    Components.PhasorTextField {
                        id: accentInput
                        Layout.preferredWidth: 180
                        placeholderText: "#8bd5ca"
                        enabled: !preferences.loading
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.Tokens.spacingXS
                        Text { text: "Reduced motion"; color: Theme.Tokens.textPrimary; font.pixelSize: 14 }
                        Text { text: "Turn off animated transitions"; color: Theme.Tokens.textSecondary; font.pixelSize: 11 }
                    }
                    Components.PhasorSwitch {
                        id: motionSwitch
                        enabled: !preferences.loading
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.Tokens.spacingS
                    Text { text: "Wallpaper path"; color: Theme.Tokens.textPrimary; font.pixelSize: 14 }
                    Components.PhasorTextField {
                        id: wallpaperInput
                        Layout.fillWidth: true
                        placeholderText: "Leave empty for the Phasor background"
                        enabled: !preferences.loading
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: preferences.errorText.length > 0 || preferences.statusText.length > 0
                    text: preferences.errorText.length > 0 ? preferences.errorText : preferences.statusText
                    color: preferences.errorText.length > 0 ? Theme.Tokens.danger : Theme.Tokens.success
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true
                    Text { Layout.fillWidth: true; text: preferences.loading ? "Loading…" : "Super+, opens Settings"; color: Theme.Tokens.textSecondary; font.pixelSize: 11 }
                    Components.PhasorButton { text: "Save changes"; enabled: !preferences.loading; onClicked: preferences.save() }
                }
            }
        }
    }
}
