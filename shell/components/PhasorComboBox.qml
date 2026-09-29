import QtQuick
import QtQuick.Controls
import "../theme" as Theme

ComboBox {
    id: control
    implicitHeight: 38
    implicitWidth: 210
    font.pixelSize: 13
    leftPadding: 12
    rightPadding: 30
    opacity: enabled ? 1 : 0.45
    contentItem: Text {
        text: control.displayText
        font: control.font
        color: Theme.Tokens.textPrimary
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: Text {
        x: control.width - width - 12
        y: (control.height - height) / 2
        text: "⌄"
        color: Theme.Tokens.textSecondary
    }
    background: Rectangle {
        radius: Theme.Tokens.radiusSmall
        color: control.hovered ? Theme.Tokens.surfaceRaised : Theme.Tokens.background
        border.width: 1
        border.color: control.visualFocus ? Theme.Tokens.accent : Theme.Tokens.separator
        Behavior on color { ColorAnimation { duration: Theme.Tokens.animationHover } }
    }
    delegate: ItemDelegate {
        id: option
        required property var modelData
        required property int index
        width: control.width - 8
        height: 36
        highlighted: control.highlightedIndex === index
        contentItem: Text { text: option.modelData; color: Theme.Tokens.textPrimary; verticalAlignment: Text.AlignVCenter; font: control.font }
        background: Rectangle { radius: 2; color: option.highlighted ? Theme.Tokens.surfaceRaised : "transparent" }
    }
    popup: Popup {
        y: control.height + 4
        width: control.width
        padding: 4
        implicitHeight: Math.min(320, contentItem.implicitHeight + 8)
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator {}
        }
        background: Rectangle { color: Theme.Tokens.background; radius: 4; border.width: 1; border.color: Theme.Tokens.separator }
        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.Tokens.animationFast } }
        exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Theme.Tokens.animationFast } }
    }
}
