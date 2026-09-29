import QtQuick
import QtQuick.Layouts
import "../../shell/theme" as Theme
import "../../shell/components" as Components

Item {
    id: control
    property var phasor
    property var notificationState: ({ available: false, doNotDisturb: false, count: 0 })
    implicitWidth: controls.implicitWidth
    implicitHeight: controls.implicitHeight

    function refresh() {
        if (!phasor) return
        phasor.request("notifications.status", {}, function(result) {
            if (!result.error) {
                notificationState = result
                dndSwitch.checked = Boolean(result.doNotDisturb)
            } else {
                notificationState = { available: false, doNotDisturb: false, count: 0, error: result.error }
            }
        })
    }

    function updateDnd(enabled) {
        phasor.request("notifications.set_dnd", { enabled: enabled }, function(result) {
            if (result.error) console.warn("Phasor could not update Do Not Disturb:", result.error)
            refresh()
        })
    }

    Component.onCompleted: refresh()

    Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: control.refresh()
    }

    RowLayout {
        id: controls
        spacing: Theme.Tokens.spacingXS

        Components.PhasorButton {
            text: control.notificationState.available ? "Alerts · " + control.notificationState.count : "Alerts"
            enabled: control.notificationState.available
            implicitHeight: 28
            onClicked: control.phasor.request("notifications.toggle", {}, function(result) {
                if (result.error) console.warn("Phasor could not open notifications:", result.error)
                control.refresh()
            })
        }

        Text {
            text: "DND"
            color: Theme.Tokens.textSecondary
            font.pixelSize: 11
            Accessible.name: "Do not disturb"
        }

        Components.PhasorSwitch {
            id: dndSwitch
            enabled: control.notificationState.available
            Accessible.name: "Do not disturb"
            onClicked: control.updateDnd(checked)
        }
    }
}
