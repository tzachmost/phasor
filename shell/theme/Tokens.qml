pragma Singleton
import QtQuick

QtObject {
    readonly property color background: "#111318"
    readonly property color surface: "#1a1d24"
    readonly property color surfaceRaised: "#242833"
    readonly property color textPrimary: "#f0f1f4"
    readonly property color textSecondary: "#a4aab6"
    readonly property color accent: "#8bd5ca"
    readonly property color borderFocused: "#8bd5ca"
    readonly property color danger: "#ed8796"
    readonly property color warning: "#eed49f"
    readonly property color success: "#a6da95"
    readonly property int spacingXS: 4
    readonly property int spacingS: 8
    readonly property int spacingM: 12
    readonly property int spacingL: 18
    readonly property int spacingXL: 24
    readonly property int radiusSmall: 8
    readonly property int radiusMedium: 14
    readonly property int radiusLarge: 20
    readonly property int animationFast: 100
    readonly property int animationNormal: 200
    readonly property int animationSlow: 320
    readonly property string animationEaseOut: "cubic-bezier(0.16, 1, 0.3, 1)"
}
