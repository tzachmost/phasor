import QtQuick
import QtQuick.Controls
import "../theme" as Theme

Switch {
    id: control

    padding: 0
    spacing: 0
    implicitWidth: 42
    implicitHeight: 24

    indicator: Rectangle {
        implicitWidth: 42
        implicitHeight: 24
        x: control.leftPadding
        y: control.height / 2 - height / 2
        radius: height / 2
        color: control.checked ? Theme.Tokens.accent : Theme.Tokens.surfaceRaised
        border.width: 1
        border.color: control.checked ? Theme.Tokens.accent : Theme.Tokens.separator

        Rectangle {
            width: 16
            height: 16
            x: control.checked ? parent.width - width - 4 : 4
            y: (parent.height - height) / 2
            radius: height / 2
            color: Theme.Tokens.background
            Behavior on x { NumberAnimation { duration: Theme.Tokens.animationFast } }
        }
    }

    contentItem: Item { implicitWidth: 0; implicitHeight: 0 }
}
