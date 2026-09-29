pragma Singleton
import QtQuick
import Quickshell.Io
import "../api" as PhasorApi

Item {
    id: tokens
    visible: false
    width: 1
    height: 1

    property string requestedScheme: "dark"
    property color accentColor: "#8bd5ca"
    property bool reducedMotion: false

    SystemPalette { id: systemPalette }

    readonly property bool dark: requestedScheme === "dark" ||
        (requestedScheme === "system" && systemPalette.window.hslLightness < 0.5)
    readonly property color background: dark ? "#111318" : "#f3f5f8"
    readonly property color surface: dark ? "#e61a1d24" : "#eaf3f5f8"
    readonly property color surfaceRaised: dark ? "#e8242833" : "#e8e8ecf2"
    readonly property color textPrimary: dark ? "#f0f1f4" : "#1b2028"
    readonly property color textSecondary: dark ? "#a4aab6" : "#596575"
    readonly property color accent: accentColor
    readonly property color borderFocused: accent
    readonly property color danger: dark ? "#ed8796" : "#b4233a"
    readonly property color warning: dark ? "#eed49f" : "#8b5b00"
    readonly property color success: dark ? "#a6da95" : "#327a36"
    readonly property color overlayScrim: dark ? "#99080a0e" : "#66090d14"
    readonly property color appIconSurface: dark ? "#30394a" : "#dbe5f2"
    readonly property color fileIconSurface: dark ? "#383244" : "#e8def2"
    readonly property color separator: dark ? "#783e4654" : "#78b6c0cb"
    readonly property color glassHighlight: dark ? "#38ffffff" : "#aaffffff"
    readonly property int spacingXS: 4
    readonly property int spacingS: 8
    readonly property int spacingM: 12
    readonly property int spacingL: 18
    readonly property int spacingXL: 24
    readonly property int radiusSmall: 2
    readonly property int radiusMedium: 4
    readonly property int radiusLarge: 8
    readonly property int animationFast: reducedMotion ? 0 : 100
    readonly property int animationNormal: reducedMotion ? 0 : 200
    readonly property int animationSlow: reducedMotion ? 0 : 320
    readonly property string animationEaseOut: "cubic-bezier(0.16, 1, 0.3, 1)"

    function refresh() {
        themeRequest.exec(["phasorctl", "rpc", "theme.get", "{}"])
    }

    Process {
        id: themeRequest
        command: ["phasorctl", "rpc", "theme.get", "{}"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const settings = JSON.parse(text)
                    tokens.requestedScheme = settings.theme || "dark"
                    tokens.accentColor = settings.accent || "#8bd5ca"
                    tokens.reducedMotion = Boolean(settings.reducedMotion)
                } catch (error) {
                    console.warn("Phasor theme settings returned invalid JSON", error)
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.length > 0) console.warn("Phasor theme settings:", text)
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: tokens.refresh()
    }

    Connections {
        target: PhasorApi.Api
        function onEventReceived(event) {
            if (event.type === "event" && event.name === "settings.changed") tokens.refresh()
        }
    }

    Component.onCompleted: refresh()
}
