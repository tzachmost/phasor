import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../shell/theme" as Theme
import "../../shell/components" as Components

Item {
    id: clipboard
    property var phasor
    property bool open: false
    property var entries: []
    property string errorText: ""
    implicitWidth: openButton.implicitWidth
    implicitHeight: openButton.implicitHeight

    function refresh() {
        if (!phasor) return
        phasor.request("clipboard.history", { limit: 60 }, function(result) {
            if (result.error) {
                errorText = result.error
                entries = []
                return
            }
            errorText = result.error || ""
            entries = result.entries || []
        })
    }

    function restore(entry) {
        phasor.request("clipboard.restore", { id: entry.id }, function(result) {
            if (result.error) errorText = result.error
            else open = false
        })
    }

    onOpenChanged: if (open) { errorText = ""; refresh() }

    Connections {
        target: clipboard.phasor
        function onEventReceived(event) {
            if (event.type === "action" && event.name === "clipboard.toggle") clipboard.open = !clipboard.open
        }
    }

    Components.PhasorButton {
        id: openButton
        text: "Clipboard"
        implicitHeight: 28
        onClicked: clipboard.phasor.request("clipboard.toggle", {}, function(result) {
            if (result.error) clipboard.errorText = result.error
        })
    }

    PanelWindow {
        id: historyWindow
        anchors { top: true; bottom: true; left: true; right: true }
        visible: clipboard.open
        focusable: clipboard.open
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: clipboard.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "phasor-clipboard"

        Rectangle {
            anchors.fill: parent
            color: Theme.Tokens.overlayScrim
            MouseArea { anchors.fill: parent; onClicked: clipboard.open = false }
        }

        Rectangle {
            width: Math.min(420, parent.width - 32)
            height: Math.min(480, parent.height - 64)
            anchors { top: parent.top; right: parent.right; topMargin: 52; rightMargin: 16 }
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
                    Text {
                        Layout.fillWidth: true
                        text: "Clipboard history"
                        color: Theme.Tokens.textPrimary
                        font.pixelSize: 18
                        font.bold: true
                    }
                    Components.PhasorButton { text: "Refresh"; onClicked: clipboard.refresh() }
                    Components.PhasorButton { text: "Close"; onClicked: clipboard.open = false }
                }

                Text {
                    Layout.fillWidth: true
                    visible: clipboard.errorText.length > 0 || clipboard.entries.length === 0
                    text: clipboard.errorText.length > 0 ? clipboard.errorText : "No clipboard items yet"
                    color: clipboard.errorText.length > 0 ? Theme.Tokens.danger : Theme.Tokens.textSecondary
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: Theme.Tokens.spacingXS
                    model: clipboard.entries

                    delegate: Item {
                        id: entryRow
                        required property var modelData
                        width: ListView.view.width
                        height: 48

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.Tokens.radiusSmall
                            color: entryMouse.containsMouse ? Theme.Tokens.surfaceRaised : Theme.Tokens.surface
                            border.width: 1
                            border.color: Theme.Tokens.separator
                        }

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.Tokens.spacingM
                            anchors.rightMargin: Theme.Tokens.spacingM
                            text: entryRow.modelData.preview
                            color: Theme.Tokens.textPrimary
                            font.pixelSize: 12
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            maximumLineCount: 2
                        }

                        MouseArea {
                            id: entryMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: clipboard.restore(entryRow.modelData)
                        }
                    }
                }
            }
        }
    }
}
