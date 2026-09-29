import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "../../shell/theme" as Theme
import "../../shell/components" as Components

Item {
    id: dock
    width: 1
    height: 1
    property var phasor
    property var windows: []
    property string errorText: ""
    property bool showCloseButtons: true
    property bool showEmptyState: true

    function refresh() {
        if (!phasor) return
        phasor.request("windows.list", {}, function(result) {
            if (result.error) errorText = result.error
            else {
                windows = result.items || []
                errorText = ""
            }
        })
    }

    function focusWindow(window) {
        phasor.request("windows.focus", { id: window.id }, function(result) {
            if (result.error) errorText = result.error
        })
    }

    function closeWindow(window) {
        phasor.request("windows.close", { id: window.id }, function(result) {
            if (result.error) errorText = result.error
            else refresh()
        })
    }

    function refreshSettings() {
        if (!phasor) return
        phasor.request("settings.get", {}, function(result) {
            if (result.error) return
            const dockSettings = result.dock || ({})
            showCloseButtons = dockSettings.showCloseButtons !== false
            showEmptyState = dockSettings.showEmptyState !== false
        })
    }

    Component.onCompleted: { refresh(); refreshSettings() }

    Connections {
        target: dock.phasor
        function onEventReceived(event) {
            if (event.type === "snapshot") dock.windows = (event.data && event.data.windows) || []
            if (event.type === "event" && event.name === "window.opened") dock.refresh()
            if (event.type === "event" && event.name === "window.closed") dock.refresh()
            if (event.type === "event" && event.name === "window.focused") dock.refresh()
            if (event.type === "event" && event.name === "settings.changed") dock.refreshSettings()
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: true
        onTriggered: dock.refresh()
    }

    PanelWindow {
        id: dockWindow
        anchors { bottom: true; left: true; right: true }
        implicitHeight: 70
        exclusiveZone: implicitHeight
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "phasor-dock"

        Rectangle {
            width: Math.min(parent.width - 24, Math.max(260, dockItems.implicitWidth + 28))
            height: 58
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            radius: Theme.Tokens.radiusLarge
            color: Theme.Tokens.surface
            border.width: 1
            border.color: Theme.Tokens.separator

            Flickable {
                anchors.fill: parent
                anchors.margins: Theme.Tokens.spacingS
                contentWidth: dockItems.implicitWidth
                contentHeight: height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: dockItems
                    spacing: Theme.Tokens.spacingXS
                    height: parent.height

                    Components.ExtensionSlot {
                        slotName: "dock.left"
                        providers: dock.phasor ? dock.phasor.extensions("dock.left") : []
                    }

                    Components.ExtensionSlot {
                        slotName: "dock.center"
                        providers: dock.phasor ? dock.phasor.extensions("dock.center") : []
                    }

                    Repeater {
                        model: dock.windows

                        delegate: Item {
                            id: windowTile
                            required property var modelData
                            width: Math.min(210, Math.max(120, titleText.implicitWidth + 52))
                            height: 42
                            anchors.verticalCenter: parent.verticalCenter

                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.Tokens.radiusSmall
                                color: windowTile.modelData.focused ? Theme.Tokens.surfaceRaised : "transparent"
                                border.width: windowTile.modelData.focused ? 1 : 0
                                border.color: Theme.Tokens.accent
                            }

                            Text {
                                id: titleText
                                anchors.left: parent.left
                                anchors.right: dock.showCloseButtons ? closeButton.left : parent.right
                                anchors.leftMargin: Theme.Tokens.spacingM
                                anchors.rightMargin: dock.showCloseButtons ? Theme.Tokens.spacingXS : Theme.Tokens.spacingM
                                anchors.verticalCenter: parent.verticalCenter
                                text: windowTile.modelData.title.length > 0 ? windowTile.modelData.title : windowTile.modelData.appId
                                color: windowTile.modelData.focused ? Theme.Tokens.textPrimary : Theme.Tokens.textSecondary
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }

                            MouseArea {
                                anchors.fill: parent
                                anchors.rightMargin: 30
                                onClicked: dock.focusWindow(windowTile.modelData)
                            }

                            Button {
                                id: closeButton
                                visible: dock.showCloseButtons
                                width: 24
                                height: 24
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.Tokens.spacingXS
                                anchors.verticalCenter: parent.verticalCenter
                                text: "×"
                                padding: 0
                                background: Rectangle {
                                    radius: Theme.Tokens.radiusSmall
                                    color: closeButton.down ? Theme.Tokens.danger : "transparent"
                                }
                                contentItem: Text {
                                    text: closeButton.text
                                    color: closeButton.down ? Theme.Tokens.background : Theme.Tokens.textSecondary
                                    font.pixelSize: 16
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                onClicked: dock.closeWindow(windowTile.modelData)
                            }
                        }
                    }

                    Text {
                        visible: dock.windows.length === 0 && dock.showEmptyState
                        width: visible ? 220 : 0
                        height: parent.height
                        text: dock.errorText.length > 0 ? dock.errorText : "No open windows"
                        color: dock.errorText.length > 0 ? Theme.Tokens.danger : Theme.Tokens.textSecondary
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }

                    Components.ExtensionSlot {
                        slotName: "dock.right"
                        providers: dock.phasor ? dock.phasor.extensions("dock.right") : []
                    }

                    Components.ExtensionSlot {
                        slotName: "dock.status"
                        providers: dock.phasor ? dock.phasor.extensions("dock.status") : []
                    }
                }
            }
        }
    }
}
