//@ pragma AppId phasor-settings
import Quickshell
import "apps/settings" as SettingsApp
import "shell/api" as PhasorApi

ShellRoot {
    SettingsApp.Settings {
        phasor: PhasorApi.PluginContext {
            pluginId: "dev.phasor.settings"
            backend: PhasorApi.Api
        }
    }
}
