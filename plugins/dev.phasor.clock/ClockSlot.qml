import QtQuick
import "../../shell/theme" as Theme

Item {
    id: clock
    property var phasor
    property string timeText: Qt.formatTime(new Date(), "HH:mm")
    implicitWidth: clockText.implicitWidth + 20
    implicitHeight: 28

    Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: clock.timeText = Qt.formatTime(new Date(), "HH:mm")
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.Tokens.radiusSmall
        color: Theme.Tokens.surfaceRaised
        Text {
            id: clockText
            anchors.centerIn: parent
            text: clock.timeText
            color: Theme.Tokens.textSecondary
            font.pixelSize: 12
            font.family: "monospace"
        }
    }
}
