import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import "../../shell/components" as Components
import "../../shell/theme" as Theme

Item {
    required property var phasor
    implicitWidth: actionRow.implicitWidth
    implicitHeight: actionRow.implicitHeight

    RowLayout {
        id: actionRow
        spacing: Theme.Tokens.spacingXS

        Components.PhasorButton {
            text: "Settings"
            Accessible.name: "Open Settings"
            onClicked: phasor.request("launcher.toggle", {}, function(result) {
                if (result.error) { console.warn("Phasor could not close the Launcher:", result.error); return }
                Qt.callLater(function() {
                    phasor.request("settings.toggle", { section: "appearance" }, function(settingsResult) {
                        if (settingsResult.error) console.warn("Phasor could not open Settings:", settingsResult.error)
                    })
                })
            })
        }

        Components.PhasorButton {
            text: "Actions"
            Accessible.name: "Open command palette"
            onClicked: phasor.request("launcher.toggle", {}, function(result) {
                if (result.error) { console.warn("Phasor could not close the Launcher:", result.error); return }
                Qt.callLater(function() {
                    phasor.request("commands.toggle", {}, function(commandResult) {
                        if (commandResult.error) console.warn("Phasor could not open Commands:", commandResult.error)
                    })
                })
            })
        }
    }
}
