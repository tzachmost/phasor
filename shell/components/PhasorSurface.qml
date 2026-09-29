import QtQuick
import "../theme" as Theme

Rectangle {
    radius: Theme.Tokens.radiusMedium
    border.width: 1
    border.color: Theme.Tokens.separator
    gradient: Gradient {
        GradientStop { position: 0; color: Theme.Tokens.surfaceRaised }
        GradientStop { position: 0.3; color: Theme.Tokens.surface }
        GradientStop { position: 1; color: Theme.Tokens.surface }
    }
    Rectangle {
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 1 }
        height: 1
        color: Theme.Tokens.glassHighlight
    }
}
