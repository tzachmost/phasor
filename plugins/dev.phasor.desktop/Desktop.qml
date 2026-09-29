import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "../../shell/theme" as Theme

Item {
    id: desktop
    width: 1
    height: 1
    property var phasor
    property var shortcuts: [
        { id: "home", name: "Home", icon: "user-home" },
        { id: "launcher", name: "Applications", icon: "view-grid" },
        { id: "settings", name: "Settings", icon: "preferences-system" }
    ]

    function activate(shortcut) {
        if (shortcut.id === "home") {
            phasor.request("files.open", { path: Quickshell.env("HOME") }, function(result) {
                if (result.error) console.warn("Phasor Desktop could not open Home:", result.error)
            })
        } else if (shortcut.id === "launcher") {
            phasor.request("launcher.toggle", {}, function(result) {
                if (result.error) console.warn("Phasor Desktop could not open the Launcher:", result.error)
            })
        } else if (shortcut.id === "settings") {
            phasor.request("settings.toggle", {}, function(result) {
                if (result.error) console.warn("Phasor Desktop could not open Settings:", result.error)
            })
        }
    }

    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "phasor-desktop"

        Row {
            anchors { top: parent.top; left: parent.left; topMargin: 58; leftMargin: 20 }
            spacing: Theme.Tokens.spacingM

            Repeater {
                model: desktop.shortcuts

                delegate: Item {
                    id: shortcut
                    required property var modelData
                    width: 76
                    height: 94

                    Rectangle {
                        id: iconTile
                        width: 64
                        height: 64
                        anchors.horizontalCenter: parent.horizontalCenter
                        radius: Theme.Tokens.radiusMedium
                        color: iconMouse.containsMouse ? Theme.Tokens.surfaceRaised : Theme.Tokens.surface
                        border.width: 1
                        border.color: iconMouse.containsMouse ? Theme.Tokens.accent : Theme.Tokens.separator

                        IconImage {
                            id: shortcutIcon
                            anchors.centerIn: parent
                            width: 32
                            height: 32
                            implicitSize: 32
                            source: Quickshell.iconPath(shortcut.modelData.icon)
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: shortcutIcon.status !== Image.Ready
                            text: shortcut.modelData.name.substring(0, 1)
                            color: Theme.Tokens.accent
                            font.pixelSize: 24
                            font.bold: true
                        }
                    }

                    Text {
                        anchors.top: iconTile.bottom
                        anchors.topMargin: Theme.Tokens.spacingXS
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: shortcut.modelData.name
                        color: Theme.Tokens.textPrimary
                        font.pixelSize: 11
                    }

                    MouseArea {
                        id: iconMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: desktop.activate(shortcut.modelData)
                    }
                }
            }
        }
    }
}
