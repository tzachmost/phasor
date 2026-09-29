import QtQuick
import QtQuick.Layouts
import "../../shell/components" as Components
import "../../shell/theme" as Theme

Item {
    required property var phasor
    implicitWidth: actionRow.implicitWidth
    implicitHeight: actionRow.implicitHeight

    function closeLauncherThen(target) {
        phasor.request("launcher.toggle", {}, function(result) {
            if (result.error) { console.warn("Phasor could not close the Launcher:", result.error); return }
            if (target === "settings") settingsHandoff.start()
            else actionsHandoff.start()
        })
    }

    Timer {
        id: settingsHandoff
        interval: Theme.Tokens.animationExit
        onTriggered: phasor.request("settings.toggle", { section: "appearance" }, function(result) {
            if (result.error) console.warn("Phasor could not open Settings:", result.error)
        })
    }

    Timer {
        id: actionsHandoff
        interval: Theme.Tokens.animationExit
        onTriggered: phasor.request("commands.toggle", {}, function(result) {
            if (result.error) console.warn("Phasor could not open Actions:", result.error)
        })
    }

    RowLayout {
        id: actionRow
        spacing: Theme.Tokens.spacingXS

        Components.PhasorButton {
            text: "Settings"
            Accessible.name: "Open Settings"
            onClicked: closeLauncherThen("settings")
        }

        Components.PhasorButton {
            text: "Actions"
            Accessible.name: "Open command palette"
            onClicked: closeLauncherThen("actions")
        }
    }
}
