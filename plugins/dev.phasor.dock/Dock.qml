import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "../../shell/theme" as Theme
import "../../shell/components" as Components
import "../../shell/components/StableList.js" as StableList

Item {
    id: dock
    width: 1
    height: 1
    property var phasor
    property string errorText: ""
    property bool showCloseButtons: true
    property bool showEmptyState: true
    property bool refreshing: false
    property bool refreshQueued: false
    property var activeTile: null
    ListModel { id: windows }

    function refresh() {
        if (!phasor) return
        if (refreshing) { refreshQueued = true; return }
        refreshing = true
        phasor.request("windows.list", {}, function(result) {
            refreshing = false
            if (result.error) errorText = result.error
            else { StableList.sync(windows, result.items || []); errorText = "" }
            if (refreshQueued) { refreshQueued = false; refreshDelay.start() }
        })
    }
    function act(method, window) {
        activeTile = null
        phasor.request(method, { id: window.id }, function(result) {
            if (result.error) errorText = result.error
            else refreshDelay.start()
        })
    }
    function focusWindow(window) {
        activeTile = null
        if (window.minimized) {
            phasor.request("windows.restore", { id: window.id }, function(result) {
                if (result.error) errorText = result.error
                else act("windows.focus", window)
            })
        } else act("windows.focus", window)
    }
    function iconSource(icon) {
        if (!icon) return ""
        return String(icon).startsWith("/") ? "file://" + icon : Quickshell.iconPath(icon)
    }
    function refreshSettings() {
        if (!phasor) return
        phasor.request("settings.get", {}, function(result) {
            if (result.error) return
            const settings = result.dock || ({})
            showCloseButtons = settings.showCloseButtons !== false
            showEmptyState = settings.showEmptyState !== false
        })
    }
    Component.onCompleted: { refresh(); refreshSettings() }
    Connections {
        target: dock.phasor
        function onEventReceived(event) {
            if (event.type === "snapshot" || (event.type === "event" && event.name.indexOf("window.") === 0)) {
                if (!refreshDelay.running) refreshDelay.start()
            }
            if (event.type === "event" && event.name === "settings.changed") dock.refreshSettings()
        }
    }
    Timer { id: refreshDelay; interval: 60; onTriggered: dock.refresh() }
    Timer { interval: 3000; repeat: true; running: true; onTriggered: dock.refresh() }
    Timer {
        id: closeCard
        interval: 220
        onTriggered: if (!cardHover.hovered && !(dock.activeTile && dock.activeTile.hovered)) dock.activeTile = null
    }

    PanelWindow {
        id: dockWindow
        anchors { bottom: true; left: true; right: true }
        implicitHeight: 76
        exclusiveZone: 76
        color: "transparent"
        mask: Region { item: surface }
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "phasor-dock"

        Components.PhasorSurface {
            id: surface
            width: Math.min(parent.width - 32, Math.max(104, contents.implicitWidth + 24))
            height: 62
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            Behavior on width { NumberAnimation { duration: Theme.Tokens.animationLayout; easing.type: Easing.OutCubic } }

            Row {
                id: contents
                anchors.centerIn: parent
                height: 54
                spacing: 6
                Components.ExtensionSlot { anchors.verticalCenter: parent.verticalCenter; slotName: "dock.left"; providers: dock.phasor ? dock.phasor.extensions("dock.left") : [] }
                Components.ExtensionSlot { anchors.verticalCenter: parent.verticalCenter; slotName: "dock.center"; providers: dock.phasor ? dock.phasor.extensions("dock.center") : [] }
                ListView {
                    id: windowList
                    width: Math.min(windows.count * 54, Math.max(54, dockWindow.width - 260))
                    height: 54
                    orientation: ListView.Horizontal
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    spacing: 2
                    model: windows
                    Behavior on width { NumberAnimation { duration: Theme.Tokens.animationLayout; easing.type: Easing.OutCubic } }
                    add: Transition {
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.Tokens.animationEnter }
                            NumberAnimation { property: "scale"; from: .8; to: 1; duration: Theme.Tokens.animationEnter; easing.type: Easing.OutCubic }
                        }
                    }
                    remove: Transition {
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; to: 0; duration: Theme.Tokens.animationExit }
                            NumberAnimation { property: "scale"; to: .8; duration: Theme.Tokens.animationExit; easing.type: Easing.InCubic }
                        }
                    }
                    displaced: Transition { NumberAnimation { properties: "x,y"; duration: Theme.Tokens.animationLayout; easing.type: Easing.OutCubic } }
                    delegate: Item {
                        id: tile
                        required property string windowId
                        required property string title
                        required property string appId
                        required property string icon
                        required property bool focused
                        required property bool minimized
                        readonly property bool hovered: mouse.containsMouse
                        readonly property var window: ({ id: windowId, minimized: minimized, focused: focused, title: title })
                        width: 52
                        height: 54
                        Accessible.role: Accessible.Button
                        Accessible.name: title + (minimized ? ", minimized" : focused ? ", active" : "")
                        Accessible.onPressAction: dock.focusWindow(window)
                        onHoveredChanged: {
                            if (hovered) { closeCard.stop(); revealCard.restart() }
                            else { revealCard.stop(); closeCard.restart() }
                        }
                        Timer { id: revealCard; interval: 500; onTriggered: dock.activeTile = tile }
                        Rectangle {
                            x: 2; y: 4; width: 48; height: 44
                            radius: Theme.Tokens.radiusSmall
                            color: tile.hovered ? Qt.alpha(Theme.Tokens.accent, .14) : tile.focused ? Qt.alpha(Theme.Tokens.accent, .07) : "transparent"
                            border.width: 1
                            border.color: tile.hovered ? Qt.alpha(Theme.Tokens.accent, .3) : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.Tokens.animationHover } }
                            Behavior on border.color { ColorAnimation { duration: Theme.Tokens.animationHover } }
                        }
                        Item {
                            width: 34; height: 34
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: tile.hovered ? 5 : 8
                            scale: mouse.pressed ? .94 : tile.hovered ? 1.12 : 1
                            opacity: tile.minimized ? .55 : 1
                            Behavior on y { NumberAnimation { duration: Theme.Tokens.animationHover; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: Theme.Tokens.animationHover; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: Theme.Tokens.animationNormal } }
                            IconImage { id: appIcon; anchors.fill: parent; implicitSize: 40; source: dock.iconSource(tile.icon); visible: status === Image.Ready }
                            Text { anchors.centerIn: parent; visible: !appIcon.visible; text: (tile.appId || tile.title).charAt(0).toUpperCase(); color: Theme.Tokens.accent; font.pixelSize: 23; font.weight: Font.DemiBold }
                        }
                        Rectangle {
                            width: tile.focused ? 18 : 5
                            height: 2
                            y: 48
                            anchors.horizontalCenter: parent.horizontalCenter
                            radius: 1
                            color: tile.focused ? Theme.Tokens.accent : Theme.Tokens.textSecondary
                            opacity: tile.minimized ? .35 : .9
                            Behavior on width { NumberAnimation { duration: Theme.Tokens.animationNormal; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: Theme.Tokens.animationNormal } }
                        }
                        MouseArea {
                            id: mouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                            onClicked: function(event) {
                                if (event.button === Qt.RightButton) dock.activeTile = dock.activeTile === tile ? null : tile
                                else if (event.button === Qt.MiddleButton || (tile.focused && !tile.minimized)) dock.act(tile.minimized ? "windows.restore" : "windows.minimize", tile.window)
                                else dock.focusWindow(tile.window)
                            }
                        }
                    }
                }
                Text {
                    visible: windows.count === 0 && dock.showEmptyState
                    width: visible ? 170 : 0
                    height: parent.height
                    text: dock.errorText || "Your workspace is clear"
                    color: dock.errorText ? Theme.Tokens.danger : Theme.Tokens.textSecondary
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
                Components.ExtensionSlot { anchors.verticalCenter: parent.verticalCenter; slotName: "dock.right"; providers: dock.phasor ? dock.phasor.extensions("dock.right") : [] }
                Components.ExtensionSlot { anchors.verticalCenter: parent.verticalCenter; slotName: "dock.status"; providers: dock.phasor ? dock.phasor.extensions("dock.status") : [] }
            }
        }
    }
    PopupWindow {
        id: card
        anchor.item: dock.activeTile || surface
        anchor.edges: Edges.Top
        anchor.gravity: Edges.Top
        anchor.margins.bottom: 10
        implicitWidth: 280
        implicitHeight: cardContents.implicitHeight + 28
        visible: dock.activeTile !== null
        color: "transparent"
        Components.PhasorSurface {
            anchors.fill: parent
            HoverHandler { id: cardHover; onHoveredChanged: { if (hovered) closeCard.stop(); else closeCard.restart() } }
            ColumnLayout {
                id: cardContents
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                spacing: 12
                Text { Layout.fillWidth: true; text: dock.activeTile ? dock.activeTile.title : ""; color: Theme.Tokens.textPrimary; font.pixelSize: 12; maximumLineCount: 2; wrapMode: Text.Wrap; elide: Text.ElideRight }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Components.PhasorButton { Layout.fillWidth: true; text: dock.activeTile && dock.activeTile.minimized ? "Restore" : "Minimize"; onClicked: { if (dock.activeTile) dock.act(dock.activeTile.minimized ? "windows.restore" : "windows.minimize", dock.activeTile.window) } }
                    Components.PhasorButton { Layout.fillWidth: true; visible: dock.showCloseButtons; text: "Close"; onClicked: { if (dock.activeTile) dock.act("windows.close", dock.activeTile.window) } }
                }
            }
        }
    }
}
