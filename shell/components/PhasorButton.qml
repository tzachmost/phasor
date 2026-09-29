import QtQuick
import QtQuick.Controls
import "../theme" as Theme

Button {
    id: control

    property bool primary: false
    implicitHeight: 36
    font.pixelSize: 12
    opacity: enabled ? 1 : 0.45
    scale: down ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: Theme.Tokens.animationFast; easing.type: Easing.OutCubic } }
    padding: Theme.Tokens.spacingM
    background: Rectangle {
        radius: Theme.Tokens.radiusSmall
        color: control.primary || control.down ? Theme.Tokens.accent : control.hovered ? Theme.Tokens.surface : Theme.Tokens.surfaceRaised
        border.width: control.visualFocus ? 2 : 1
        border.color: control.visualFocus || control.hovered ? Theme.Tokens.accent : Theme.Tokens.separator
        Behavior on color { ColorAnimation { duration: Theme.Tokens.animationHover } }
        Behavior on border.color { ColorAnimation { duration: Theme.Tokens.animationHover } }
    }
    contentItem: Text {
        text: control.text
        font: control.font
        color: control.primary || control.down ? Theme.Tokens.background : Theme.Tokens.textPrimary
        horizontalAlignment: Text.AlignLeft
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        leftPadding: Theme.Tokens.spacingXS
        rightPadding: Theme.Tokens.spacingXS
    }
}
