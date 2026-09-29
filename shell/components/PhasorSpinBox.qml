import QtQuick
import QtQuick.Controls
import "../theme" as Theme

SpinBox {
    id: control
    implicitWidth: 128
    implicitHeight: 36
    editable: true
    font.pixelSize: 13
    leftPadding: 34
    rightPadding: 34
    opacity: enabled ? 1 : 0.45
    contentItem: TextInput {
        text: control.displayText
        font: control.font
        color: Theme.Tokens.textPrimary
        selectionColor: Theme.Tokens.accent
        selectedTextColor: Theme.Tokens.background
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        readOnly: !control.editable
        validator: control.validator
        inputMethodHints: Qt.ImhDigitsOnly
    }
    background: Rectangle { radius: 2; color: Theme.Tokens.background; border.width: 1; border.color: control.activeFocus ? Theme.Tokens.accent : Theme.Tokens.separator }
    down.indicator: Rectangle {
        x: 1; y: 1; width: 32; height: control.height - 2
        color: control.down.pressed ? Theme.Tokens.surfaceRaised : "transparent"
        Text { anchors.centerIn: parent; text: "−"; color: Theme.Tokens.textSecondary; font.pixelSize: 17 }
    }
    up.indicator: Rectangle {
        x: control.width - width - 1; y: 1; width: 32; height: control.height - 2
        color: control.up.pressed ? Theme.Tokens.surfaceRaised : "transparent"
        Text { anchors.centerIn: parent; text: "+"; color: Theme.Tokens.textSecondary; font.pixelSize: 17 }
    }
}
