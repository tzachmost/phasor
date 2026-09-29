import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "../../shell/theme" as Theme
import "../../shell/components" as Components

Item {
    id: bar
    width: 1
    height: 1
    property var phasor
    property var spaces: []

    function refreshSpaces() {
        if (!phasor) return
        phasor.request("spaces.list", {}, function(result) {
            if (!result.error) spaces = result.items || []
        })
    }

    function activateSpace(space) {
        if (!phasor) return
        phasor.request("spaces.switch", { id: space.id }, function(result) {
            if (result.error) console.warn("Phasor Bar could not switch Space:", result.error)
            else refreshSpaces()
        })
    }

    Component.onCompleted: refreshSpaces()

    Connections {
        target: bar.phasor
        function onEventReceived(event) {
            if (event.type === "snapshot") bar.spaces = (event.data && event.data.spaces) || []
            if (event.type === "event" && event.name === "space.changed") bar.spaces = event.data || []
        }
    }

    Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: bar.refreshSpaces()
    }

    PanelWindow {
        id: barWindow
        anchors { top: true; left: true; right: true }
        implicitHeight: 40
        exclusiveZone: implicitHeight
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "phasor-bar"

        Rectangle {
            id: barContent
            anchors.fill: parent
            color: Theme.Tokens.surface
            border.width: 1
            border.color: Theme.Tokens.separator

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.Tokens.spacingM
                anchors.rightMargin: Theme.Tokens.spacingM
                spacing: Theme.Tokens.spacingM

                Text {
                    text: "Phasor"
                    color: Theme.Tokens.accent
                    font.pixelSize: 13
                    font.bold: true
                }

                Components.ExtensionSlot {
                    slotName: "bar.left"
                    providers: bar.phasor ? bar.phasor.extensions("bar.left") : []
                }

                Item { Layout.fillWidth: true }

                Row {
                    spacing: Theme.Tokens.spacingXS
                    Layout.alignment: Qt.AlignVCenter

                    Repeater {
                        model: bar.spaces

                        delegate: Item {
                            id: spaceChip
                            required property var modelData
                            implicitWidth: 32
                            implicitHeight: 26

                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.Tokens.radiusSmall
                                color: spaceChip.modelData.active ? Theme.Tokens.accent : "transparent"
                                border.width: spaceChip.modelData.urgent ? 1 : 0
                                border.color: Theme.Tokens.danger
                            }

                            Text {
                                anchors.centerIn: parent
                                text: spaceChip.modelData.name.replace("Space ", "")
                                color: spaceChip.modelData.active ? Theme.Tokens.background : Theme.Tokens.textSecondary
                                font.pixelSize: 12
                                font.bold: spaceChip.modelData.active
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: bar.activateSpace(spaceChip.modelData)
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                Row {
                    spacing: Theme.Tokens.spacingXS
                    Layout.alignment: Qt.AlignVCenter

                    Repeater {
                        model: SystemTray.items

                        delegate: Item {
                            id: trayButton
                            required property var modelData
                            property var trayItem: modelData
                            width: trayItem.status === 0 ? 0 : 28
                            height: 28
                            visible: width > 0

                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.Tokens.radiusSmall
                                color: trayMouse.containsMouse ? Theme.Tokens.surfaceRaised : "transparent"
                            }

                            IconImage {
                                anchors.centerIn: parent
                                width: 20
                                height: 20
                                implicitSize: 20
                                source: trayButton.trayItem.icon.length > 0 ? Quickshell.iconPath(trayButton.trayItem.icon) : ""
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: trayButton.trayItem.icon.length === 0
                                text: trayButton.trayItem.title.length > 0 ? trayButton.trayItem.title.substring(0, 1).toUpperCase() : "•"
                                color: Theme.Tokens.textPrimary
                                font.pixelSize: 12
                            }

                            ToolTip.visible: trayMouse.containsMouse && (trayButton.trayItem.tooltipTitle.length > 0 || trayButton.trayItem.title.length > 0)
                            ToolTip.text: trayButton.trayItem.tooltipTitle.length > 0 ? trayButton.trayItem.tooltipTitle : trayButton.trayItem.title
                            ToolTip.delay: 500

                            MouseArea {
                                id: trayMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                                onClicked: function(mouse) {
                                    const position = trayButton.mapToItem(barContent, trayButton.width / 2, trayButton.height)
                                    if (mouse.button === Qt.MiddleButton) {
                                        trayButton.trayItem.secondaryActivate()
                                    } else if (mouse.button === Qt.RightButton || trayButton.trayItem.onlyMenu) {
                                        if (trayButton.trayItem.hasMenu) trayButton.trayItem.display(barWindow, position.x, position.y)
                                        else trayButton.trayItem.activate()
                                    } else {
                                        trayButton.trayItem.activate()
                                    }
                                }
                            }
                        }
                    }

                    Components.ExtensionSlot {
                        slotName: "bar.right"
                        providers: bar.phasor ? bar.phasor.extensions("bar.right") : []
                    }

                    Components.PhasorButton {
                        text: "Settings"
                        implicitHeight: 28
                        onClicked: bar.phasor.request("settings.toggle", {}, function(result) {
                            if (result.error) console.warn("Phasor Bar could not open Settings:", result.error)
                        })
                    }
                }
            }
        }
    }
}
