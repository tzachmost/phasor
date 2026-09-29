import QtQuick
import "../../shell/theme" as Theme

Item {
    id: preview
    property string layout: "grid"
    property bool selected: false
    readonly property var cells: {
        switch (layout) {
        case "tile": return [[0,0,.56,1],[.60,0,.40,.48],[.60,.52,.40,.48]]
        case "center_tile": return [[0,0,.23,1],[.27,0,.46,1],[.77,0,.23,1]]
        case "vertical_tile": return [[0,0,1,.56],[0,.60,.48,.40],[.52,.60,.48,.40]]
        case "scroller": return [[0,0,.19,1],[.23,0,.54,1],[.81,0,.19,1]]
        case "vertical_scroller": return [[0,0,1,.19],[0,.23,1,.54],[0,.81,1,.19]]
        case "monocle": return [[0,0,1,1]]
        case "deck": return [[0,0,.56,1],[.60,.12,.28,.76],[.66,.06,.28,.88],[.72,0,.28,1]]
        default: return [[0,0,.48,.48],[.52,0,.48,.48],[0,.52,.48,.48],[.52,.52,.48,.48]]
        }
    }
    Repeater {
        model: preview.cells
        Rectangle {
            required property var modelData
            x: modelData[0] * preview.width
            y: modelData[1] * preview.height
            width: modelData[2] * preview.width
            height: modelData[3] * preview.height
            radius: 1
            color: preview.selected ? Qt.alpha(Theme.Tokens.accent, 0.25) : Theme.Tokens.surfaceRaised
            border.width: 1
            border.color: preview.selected ? Theme.Tokens.accent : Theme.Tokens.textSecondary
            Behavior on color { ColorAnimation { duration: Theme.Tokens.animationHover } }
        }
    }
}
