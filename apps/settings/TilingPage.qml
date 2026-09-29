import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../shell/theme" as Theme
import "../../shell/components" as Components

ColumnLayout {
    id: page
    property var phasor
    property var settings: ({})
    property bool loading: false
    property bool saving: false
    property bool dirty: false
    property string message: ""
    property bool failed: false
    property var draft: ({})
    readonly property var layouts: [
        { id: "grid", name: "Grid", detail: "Equal space for every window." },
        { id: "tile", name: "Main + stack", detail: "A large main window beside a stack." },
        { id: "center_tile", name: "Centered", detail: "Your main window in the middle." },
        { id: "vertical_tile", name: "Top + stack", detail: "A main window above the others." },
        { id: "scroller", name: "Columns", detail: "A horizontal strip of windows." },
        { id: "vertical_scroller", name: "Rows", detail: "A vertical strip of windows." },
        { id: "monocle", name: "One at a time", detail: "Each window fills the workspace." },
        { id: "deck", name: "Deck", detail: "A main window and overlapping stack." }
    ]
    readonly property var groups: [
        { title: "Spacing & edges", detail: "Fine-tune the breathing room around your windows.", fields: [
            { key: "innerHorizontal", label: "Between rows", suffix: "px", min: 0, max: 100, fallback: 8 },
            { key: "innerVertical", label: "Between columns", suffix: "px", min: 0, max: 100, fallback: 8 },
            { key: "outerHorizontal", label: "Top and bottom edges", suffix: "px", min: 0, max: 100, fallback: 10 },
            { key: "outerVertical", label: "Left and right edges", suffix: "px", min: 0, max: 100, fallback: 10 },
            { key: "borderWidth", label: "Window border", suffix: "px", min: 0, max: 12, fallback: 2 },
            { key: "smartGaps", label: "Remove outer gaps for a single window", toggle: true, fallback: false },
            { key: "hideSingleBorder", label: "Hide the border for a single window", toggle: true, fallback: false }
        ] },
        { title: "Main window & stack", detail: "Used by Main + stack, Centered, Top + stack, and Deck.", fields: [
            { key: "masterCount", label: "Main windows", suffix: "", min: 1, max: 10, fallback: 1 },
            { key: "masterRatio", label: "Main area size", suffix: "%", min: 10, max: 90, factor: 100, fallback: 0.55 },
            { key: "newIsMaster", label: "Open new windows in the main area", toggle: true, fallback: true }
        ] },
        { title: "Scrolling layouts", detail: "Used by Columns and Rows.", fields: [
            { key: "scrollerWidth", label: "Window size", suffix: "%", min: 10, max: 100, factor: 100, fallback: 0.8 },
            { key: "centerScroller", label: "Center the focused window", toggle: true, fallback: false },
            { key: "preferCenter", label: "Prefer a centered position", toggle: true, fallback: false }
        ] },
        { title: "Split behavior", detail: "Used when arranging windows with manual split layouts.", fields: [
            { key: "smartSplit", label: "Choose split direction from window shape", toggle: true, fallback: false },
            { key: "preserveSplit", label: "Preserve existing split directions", toggle: true, fallback: false }
        ] }
    ]

    spacing: 16
    onSettingsChanged: if (!dirty) draft = Object.assign({ layout: "grid" }, settings)
    Component.onCompleted: draft = Object.assign({ layout: "grid" }, settings)

    function setField(key, value) {
        const next = Object.assign({}, draft)
        next[key] = value
        draft = next
        dirty = true
        message = ""
    }

    function undo() { dirty = false; draft = Object.assign({ layout: "grid" }, settings); message = "" }

    function save() {
        saving = true
        message = ""
        phasor.request("settings.update", { patch: { tiling: draft } }, function(result) {
            saving = false
            failed = Boolean(result.error)
            if (failed) { message = result.error; return }
            dirty = false
            draft = Object.assign({}, result.tiling)
            const session = result.sessionConfig || ({})
            failed = Boolean(session.error)
            message = session.reloaded ? "Tiling preferences saved and applied." : session.error || "Saved. Your next session will use these preferences."
        })
    }

    Text { visible: page.message.length > 0; Layout.fillWidth: true; text: page.message; color: page.failed ? Theme.Tokens.danger : Theme.Tokens.success; font.pixelSize: 12; wrapMode: Text.Wrap }
    Text { text: "Default layout"; color: Theme.Tokens.textPrimary; font.pixelSize: 16; font.weight: Font.DemiBold }
    Text { Layout.fillWidth: true; text: "Used across your Spaces. Grid gives every window an equal share."; color: Theme.Tokens.textSecondary; font.pixelSize: 12; wrapMode: Text.Wrap }
    GridLayout {
        Layout.fillWidth: true
        columns: 4
        columnSpacing: 8
        rowSpacing: 8
        Repeater {
            model: page.layouts
            delegate: Button {
                id: layoutButton
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 120
                implicitHeight: 96
                enabled: !page.loading && !page.saving
                Accessible.name: modelData.name + ". " + modelData.detail
                checkable: true
                checked: page.draft.layout === modelData.id
                onClicked: page.setField("layout", modelData.id)
                background: Rectangle {
                    radius: Theme.Tokens.radiusSmall
                    color: layoutButton.checked ? Qt.alpha(Theme.Tokens.accent, .09) : layoutButton.hovered ? Theme.Tokens.surfaceRaised : Theme.Tokens.surface
                    border.width: 1
                    border.color: layoutButton.checked || layoutButton.visualFocus ? Theme.Tokens.accent : Theme.Tokens.separator
                    Behavior on color { ColorAnimation { duration: Theme.Tokens.animationHover } }
                }
                contentItem: Column {
                    spacing: 10
                    LayoutPreview { width: 62; height: 40; anchors.horizontalCenter: parent.horizontalCenter; layout: layoutButton.modelData.id; selected: layoutButton.checked }
                    Text { width: parent.width; text: layoutButton.modelData.name; horizontalAlignment: Text.AlignHCenter; color: Theme.Tokens.textPrimary; font.pixelSize: 11; elide: Text.ElideRight }
                }
                ToolTip.visible: hovered
                ToolTip.delay: 600
                ToolTip.text: modelData.detail
            }
        }
    }
    Repeater {
        model: page.groups
        delegate: Rectangle {
            id: group
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: contents.implicitHeight + 36
            color: Theme.Tokens.surface
            border.width: 1
            border.color: Theme.Tokens.separator
            radius: Theme.Tokens.radiusMedium
            ColumnLayout {
                id: contents
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
                spacing: 12
                Text { text: group.modelData.title; color: Theme.Tokens.textPrimary; font.pixelSize: 14; font.weight: Font.DemiBold }
                Text { Layout.fillWidth: true; text: group.modelData.detail; color: Theme.Tokens.textSecondary; font.pixelSize: 11; wrapMode: Text.Wrap }
                Repeater {
                    model: group.modelData.fields
                    delegate: RowLayout {
                        id: field
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 12
                        Text { Layout.fillWidth: true; text: field.modelData.label; color: Theme.Tokens.textPrimary; font.pixelSize: 12; wrapMode: Text.Wrap }
                        Text { visible: !field.modelData.toggle; text: field.modelData.suffix || ""; color: Theme.Tokens.textSecondary; font.pixelSize: 11 }
                        Components.PhasorSpinBox {
                            visible: !field.modelData.toggle
                            enabled: !page.loading && !page.saving
                            from: field.modelData.min || 0
                            to: field.modelData.max || 100
                            value: Math.round((page.draft[field.modelData.key] === undefined ? field.modelData.fallback : page.draft[field.modelData.key]) * (field.modelData.factor || 1))
                            onValueModified: page.setField(field.modelData.key, value / (field.modelData.factor || 1))
                            Accessible.name: field.modelData.label
                        }
                        Components.PhasorSwitch {
                            visible: Boolean(field.modelData.toggle)
                            enabled: !page.loading && !page.saving
                            checked: Boolean(page.draft[field.modelData.key] === undefined ? field.modelData.fallback : page.draft[field.modelData.key])
                            onToggled: page.setField(field.modelData.key, checked)
                            Accessible.name: field.modelData.label
                        }
                    }
                }
            }
        }
    }

}
