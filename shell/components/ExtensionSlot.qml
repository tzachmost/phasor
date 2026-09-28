import QtQuick
import "../api" as PhasorApi

Row {
    id: slot
    property string slotName
    property var providers: []
    spacing: 8

    Component {
        id: contextFactory
        PhasorApi.PluginContext { pluginId: ""; backend: PhasorApi.Api }
    }

    Repeater {
        model: slot.providers
        delegate: Loader {
            property var provider: modelData
            Component.onCompleted: {
                const context = contextFactory.createObject(slot, { pluginId: provider.pluginId })
                if (context) setSource(provider.entrypoint, { phasor: context })
            }
            onStatusChanged: {
                if (status === Loader.Error) PhasorApi.Api.reportPluginFailure(provider.pluginId, "Extension failed to load in slot " + slot.slotName)
            }
            width: item ? (item.implicitWidth || item.width) : 0
            height: item ? (item.implicitHeight || item.height) : 0
        }
    }
}
