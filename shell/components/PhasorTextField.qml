import QtQuick
import QtQuick.Controls
import "../theme" as Theme

TextField {
    id: control

    color: Theme.Tokens.textPrimary
    placeholderTextColor: Theme.Tokens.textSecondary
    selectionColor: Theme.Tokens.accent
    selectedTextColor: Theme.Tokens.background
    background: Rectangle {
        radius: Theme.Tokens.radiusSmall
        color: Theme.Tokens.surfaceRaised
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? Theme.Tokens.accent : Theme.Tokens.separator
    }
}
