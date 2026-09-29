import QtQuick
import QtQuick.Controls
import "../theme" as Theme

Button {
    id: control

    implicitHeight: 36
    padding: Theme.Tokens.spacingM
    background: Rectangle {
        radius: Theme.Tokens.radiusSmall
        color: control.down ? Theme.Tokens.surface : Theme.Tokens.surfaceRaised
        border.width: control.visualFocus ? 2 : 1
        border.color: control.visualFocus ? Theme.Tokens.accent : Theme.Tokens.separator
    }
    contentItem: Text {
        text: control.text
        font: control.font
        color: control.enabled ? Theme.Tokens.textPrimary : Theme.Tokens.textSecondary
        horizontalAlignment: Text.AlignLeft
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        leftPadding: Theme.Tokens.spacingXS
        rightPadding: Theme.Tokens.spacingXS
    }
}
