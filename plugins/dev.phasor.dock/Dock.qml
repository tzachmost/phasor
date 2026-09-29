import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
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
        const focus = function() {
            phasor.request("windows.focus", { id: window.id }, function(result) {
                if (result.error) errorText = result.error
                else refresh()
            })
        }
        if (window.minimized) {
            phasor.request("windows.restore", { id: window.id }, function(result) {
                if (result.error) errorText = result.error
                else focus()
            })
        } else focus()
    }

    function minimizeWindow(window) {
        const method = window.minimized ? "windows.restore" : "windows.minimize"
        phasor.request(method, { id: window.id }, function(result) {
            if (result.error) errorText = result.error
            else refresh()
        })
    }

    function closeWindow(window) {
        phasor.request("windows.close", { id: window.id }, function(result) {
            if (result.error) errorText = result.error
            else refresh()
        })
    }

    function iconSource(icon) {
        if (!icon) return ""
        return String(icon).startsWith("/") ? "file://" + icon : Quickshell.iconPath(icon)
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
            if (event.type === "snapshot") dock.refresh()
            if (event.type === "event" && event.name.indexOf("window.") === 0) dock.refresh()
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
            width: Math.min(parent.width - 24, Math.max(120, dockItems.implicitWidth + 28))
            height: 58
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            radius: Theme.Tokens.radiusLarge
            color: Theme.Tokens.surface
            border.width: 1
            border.color: Theme.Tokens.separator

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 1
                color: Theme.Tokens.glassHighlight
            }

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
                            width: 46
                            height: 46
                            anchors.verticalCenter: parent.verticalCenter
                            opacity: windowTile.modelData.minimized ? 0.64 : 1

                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.Tokens.radiusSmall
                                color: windowTile.modelData.focused ? Theme.Tokens.surfaceRaised : (tileHover.containsMouse ? Theme.Tokens.surfaceRaised : "transparent")
                                border.width: windowTile.modelData.focused ? 1 : 0
                                border.color: Theme.Tokens.accent
                            }

                            IconImage {
                                id: appIcon
                                anchors.centerIn: parent
                                width: 30
                                height: 30
                                implicitSize: 30
                                source: dock.iconSource(windowTile.modelData.icon)
                                visible: status === Image.Ready
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: !appIcon.visible
                                text: {
                                    const name = String(windowTile.modelData.appId || windowTile.modelData.title || "?")
                                    return name.length ? name.charAt(0).toUpperCase() : "?"
                                }
                                color: Theme.Tokens.accent
                                font.pixelSize: 20
                                font.bold: true
                            }

                            MouseArea {
                                id: tileHover
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: dock.focusWindow(windowTile.modelData)
                            }

                            ToolTip.visible: tileHover.containsMouse
                            ToolTip.text: (windowTile.modelData.title || windowTile.modelData.appId || "Window") + (windowTile.modelData.minimized ? " · Minimized" : "")
                            ToolTip.delay: 450

                            Button {
                                id: minimizeButton
                                visible: tileHover.containsMouse || windowTile.modelData.minimized
                                width: 18
                                height: 18
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 2
                                padding: 0
                                text: windowTile.modelData.minimized ? "↗" : "−"
                                Accessible.name: windowTile.modelData.minimized ? "Restore window" : "Minimize window"
                                background: Rectangle { radius: 1; color: minimizeButton.down ? Theme.Tokens.accent : Theme.Tokens.surfaceRaised; border.width: 1; border.color: Theme.Tokens.separator }
                                contentItem: Text { text: minimizeButton.text; color: minimizeButton.down ? Theme.Tokens.background : Theme.Tokens.textPrimary; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                onClicked: dock.minimizeWindow(windowTile.modelData)
                            }

                            Button {
                                id: closeButton
                                visible: dock.showCloseButtons && tileHover.containsMouse
                                width: 18
                                height: 18
                                anchors.bottom: parent.bottom
                                anchors.right: parent.right
                                anchors.margins: 2
                                padding: 0
                                text: "×"
                                Accessible.name: "Close window"
                                background: Rectangle { radius: 1; color: closeButton.down ? Theme.Tokens.danger : Theme.Tokens.surfaceRaised; border.width: 1; border.color: Theme.Tokens.separator }
                                contentItem: Text { text: closeButton.text; color: closeButton.down ? Theme.Tokens.background : Theme.Tokens.textPrimary; font.pixelSize: 15; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                onClicked: dock.closeWindow(windowTile.modelData)
                            }
                        }
                    }

                    Text {
                        visible: dock.windows.length === 0 && dock.showEmptyState
                        width: visible ? 180 : 0
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
