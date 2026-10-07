pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import "lib/settings.mjs" as Prefs

// Runs once per shell. In edge placement it opens an edge dock on every
// screen; in bar placement it does nothing and the bar widget is the dock.
Item {
    id: root

    property var pluginService: null
    property string pluginId: ""
    property var pluginData: ({})

    function loadPluginData() {
        pluginData = (pluginService && pluginId) ? (SettingsData.getPluginSettingsForPlugin(pluginId) || {}) : {};
    }
    onPluginServiceChanged: loadPluginData()
    onPluginIdChanged: loadPluginData()

    Connections {
        target: root.pluginService
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === root.pluginId)
                root.loadPluginData();
        }
    }

    readonly property var settings: Prefs.normalize(pluginData)

    // `dms ipc call marina debug on|off|status`; persisted as the debugLog setting.
    IpcHandler {
        target: "marina"

        function debug(mode: string): string {
            if (mode === "on" || mode === "off") {
                if (!root.pluginService)
                    return "error: plugin service not ready";
                root.pluginService.savePluginData(root.pluginId, "debugLog", mode === "on");
                return "debug logging " + mode;
            }
            if (mode === "status" || mode === "")
                return "debug logging " + (root.settings.debugLog ? "on" : "off");
            return "usage: dms ipc call marina debug on|off|status";
        }
    }

    Variants {
        model: root.settings.placement === "edge" ? Quickshell.screens : []
        delegate: MarinaEdgeDock {
            settings: root.settings
        }
    }
}
