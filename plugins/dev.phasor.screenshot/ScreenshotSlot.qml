import QtQuick
import QtQuick.Layouts
import "../../shell/theme" as Theme
import "../../shell/components" as Components

Item {
    id: screenshot
    property var phasor
    property string statusText: ""
    implicitWidth: controls.implicitWidth
    implicitHeight: controls.implicitHeight

    RowLayout {
        id: controls
        spacing: Theme.Tokens.spacingXS

        Components.PhasorButton {
            text: "Capture"
            implicitHeight: 28
            onClicked: screenshot.phasor.request("screenshots.capture", {}, function(result) {
                screenshot.statusText = result.error ? result.error : "Screenshot tool opened"
                if (result.error) console.warn("Phasor screenshot:", result.error)
            })
        }

        Text {
            visible: screenshot.statusText.length > 0
            text: screenshot.statusText
            color: Theme.Tokens.textSecondary
            font.pixelSize: 10
            elide: Text.ElideRight
        }
    }
}
