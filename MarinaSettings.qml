import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "lib/placement.mjs" as Placement
import "lib/settings.mjs" as Prefs

PluginSettings {
    id: root
    pluginId: "marina"

    readonly property bool edgePlacement: placementSetting.value === "edge"
    readonly property var attachments: Placement.barAttachments(SettingsData.barConfigs, "marina")
    readonly property bool inSideSection: attachments.some(a => a.section !== "center")
    // Approximates the edge dock's check: ignores which screens a bar covers, and assumes DMS's frame reserves the edge.
    readonly property bool barReservesEdge: !SettingsData.frameEnabled && Placement.barZoneOnEdge(SettingsData.barConfigs, edgeSetting.value, bc => !SettingsData.isIslandBarConfig(bc), () => 1) > 0

    function sectionName(a) {
        if (a.section === "center")
            return a.vertical ? I18n.trFor("marina", "Middle Section") : I18n.trFor("marina", "Center Section");
        if (a.section === "left")
            return a.vertical ? I18n.trFor("marina", "Top Section") : I18n.trFor("marina", "Left Section");
        return a.vertical ? I18n.trFor("marina", "Bottom Section") : I18n.trFor("marina", "Right Section");
    }

    StyledText {
        width: parent.width
        text: "Marina Dock"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: I18n.trFor("marina", "A dock for niri that shows your open windows the way niri arranges them. Tiled windows line up in the dock in niri's column order, stacked windows share a tray, and floating windows sit beside the dock. Drag icons to reorder, stack, tile or float windows.")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    SelectionSetting {
        id: placementSetting
        settingKey: "placement"
        label: I18n.trFor("marina", "Placement")
        description: I18n.trFor("marina", "In the bar, the dock shows where you add the Marina Dock widget to a bar. At the screen edge, it has its own window on every screen.")
        options: [
            {
                "label": I18n.trFor("marina", "In the bar"),
                "value": "bar"
            },
            {
                "label": I18n.trFor("marina", "At the screen edge"),
                "value": "edge"
            }
        ]
        defaultValue: Prefs.defaults.placement
    }

    StyledText {
        visible: !root.edgePlacement
        width: parent.width
        text: root.attachments.length > 0 ? I18n.trFor("marina", "In the bar: %1.").arg(root.attachments.map(a => a.bar + ", " + root.sectionName(a)).join("; ")) : I18n.trFor("marina", "Add the Marina Dock widget to a bar in Settings → Bar → Widgets.")
        font.pixelSize: Theme.fontSizeSmall
        color: root.attachments.length > 0 ? Theme.surfaceVariantText : Theme.primary
        wrapMode: Text.WordWrap
    }

    StyledText {
        visible: !root.edgePlacement && root.inSideSection
        width: parent.width
        text: I18n.trFor("marina", "Icons magnify only in a bar's Center Section (Middle Section on a vertical bar). To magnify, move Marina Dock there in Settings → Bar → Widgets.")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.warning
        wrapMode: Text.WordWrap
    }

    StyledText {
        visible: root.edgePlacement && SettingsData.showDock
        width: parent.width
        text: I18n.trFor("marina", "DMS's own Dock is also on. Turn it off in Settings → Dock & Launcher → Dock to keep one dock.")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.warning
        wrapMode: Text.WordWrap
    }

    Column {
        width: parent.width
        spacing: Theme.spacingM
        enabled: root.edgePlacement
        opacity: enabled ? 1 : 0.45

        // The page loads saved values only into its direct children, so forward it to this group.
        function loadValue() {
            for (let i = 0; i < children.length; i++) {
                const child = children[i];
                if (typeof child.loadValue === "function")
                    child.loadValue();
            }
        }

        StyledText {
            visible: !root.edgePlacement
            width: parent.width
            text: I18n.trFor("marina", "These apply at the screen edge. In a bar, the bar's position and size decide them.")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        SelectionSetting {
            id: edgeSetting
            settingKey: "edge"
            label: I18n.trFor("marina", "Screen edge")
            options: [
                {
                    "label": I18n.trFor("marina", "Bottom"),
                    "value": "bottom"
                },
                {
                    "label": I18n.trFor("marina", "Top"),
                    "value": "top"
                },
                {
                    "label": I18n.trFor("marina", "Left"),
                    "value": "left"
                },
                {
                    "label": I18n.trFor("marina", "Right"),
                    "value": "right"
                }
            ]
            defaultValue: Prefs.defaults.edge
        }

        MarinaSliderSetting {
            settingKey: "edgeOffset"
            label: I18n.trFor("marina", "Distance from the edge")
            description: I18n.trFor("marina", "Space between the dock and the screen edge, or a bar on that edge.")
            defaultValue: Prefs.defaults.edgeOffset
            minimum: Prefs.ranges.edgeOffset[0]
            maximum: Prefs.ranges.edgeOffset[1]
            unit: "px"
        }

        ToggleSetting {
            id: autoHideToggle
            settingKey: "autoHide"
            label: I18n.trFor("marina", "Auto-hide")
            description: I18n.trFor("marina", "Slide the dock out of view until the pointer reaches its edge. Over a fullscreen window it always does.")
            defaultValue: Prefs.defaults.autoHide
        }

        ToggleSetting {
            enabled: autoHideToggle.value
            opacity: enabled ? 1 : 0.45
            settingKey: "showOnSwitch"
            label: I18n.trFor("marina", "Show when switching tiled windows")
            description: autoHideToggle.value ? I18n.trFor("marina", "Show the dock for a moment when focus moves between tiled windows, to see where you are in the workspace.") : I18n.trFor("marina", "Applies when the dock auto-hides.")
            defaultValue: Prefs.defaults.showOnSwitch
        }

        ToggleSetting {
            enabled: !autoHideToggle.value && !root.barReservesEdge
            opacity: enabled ? 1 : 0.45
            settingKey: "reserveSpace"
            label: I18n.trFor("marina", "Reserve space")
            description: autoHideToggle.value ? I18n.trFor("marina", "An auto-hiding dock reserves no space.") : root.barReservesEdge ? I18n.trFor("marina", "A bar on this edge reserves space; the dock sits beyond it and reserves none.") : I18n.trFor("marina", "Keep tiled windows clear of the dock.")
            defaultValue: Prefs.defaults.reserveSpace
        }
    }

    ToggleSetting {
        settingKey: "currentWorkspace"
        label: I18n.trFor("marina", "Current workspace only")
        description: I18n.trFor("marina", "Show only the windows on each screen's current workspace.")
        defaultValue: Prefs.defaults.currentWorkspace
    }

    ToggleSetting {
        settingKey: "currentMonitor"
        label: I18n.trFor("marina", "Current screen only")
        description: I18n.trFor("marina", "Show only the windows on the dock's own screen.")
        defaultValue: Prefs.defaults.currentMonitor
    }

    ToggleSetting {
        settingKey: "groupByApp"
        label: I18n.trFor("marina", "Group by app")
        description: I18n.trFor("marina", "One icon per app, with a window count. Stacks, floating windows and dragging are off in this mode.")
        defaultValue: Prefs.defaults.groupByApp
    }

    ToggleSetting {
        id: magnifyToggle
        settingKey: "magnifyEnabled"
        label: I18n.trFor("marina", "Magnification")
        description: I18n.trFor("marina", "Grow icons as the pointer moves over them. Off, icons keep their size and everything else works as usual. In a bar, icons magnify only in the Center (Middle) Section.")
        defaultValue: Prefs.defaults.magnifyEnabled
    }

    MarinaSliderSetting {
        id: minIconSlider
        enabled: root.edgePlacement
        opacity: enabled ? 1 : 0.45
        settingKey: "minIconPx"
        label: I18n.trFor("marina", "Min icon size")
        description: root.edgePlacement ? I18n.trFor("marina", "Size of the icons at rest, in steps of 8 px. The dock's pill grows with them.") : I18n.trFor("marina", "Applies at the screen edge. In a bar, the bar's size decides it.")
        defaultValue: Prefs.defaults.minIconPx
        minimum: Prefs.ranges.minIconPx[0]
        maximum: Prefs.ranges.minIconPx[1]
        highest: maxIconSlider.value
        step: Prefs.steps.minIconPx
        unit: "px"
    }

    MarinaSliderSetting {
        id: maxIconSlider
        visible: magnifyToggle.value
        settingKey: "maxIconPx"
        label: I18n.trFor("marina", "Max icon size")
        description: I18n.trFor("marina", "Size of the icon directly under the pointer, in steps of 8 px, and at least the min icon size. Icons grow past the dock's edge in an overlay; larger sizes take more work to draw.")
        defaultValue: Prefs.defaults.maxIconPx
        minimum: Prefs.ranges.maxIconPx[0]
        maximum: Prefs.ranges.maxIconPx[1]
        // Not below the min icon size, which applies only at the screen edge.
        lowest: root.edgePlacement ? Math.max(minimum, minIconSlider.value) : minimum
        step: Prefs.steps.maxIconPx
        unit: "px"
    }

    MarinaSliderSetting {
        visible: magnifyToggle.value
        settingKey: "radiusItems"
        label: I18n.trFor("marina", "Falloff radius")
        description: I18n.trFor("marina", "How many icons on each side are affected. Wider keeps neighbours closer in size to the hovered icon.")
        defaultValue: Prefs.defaults.radiusItems
        minimum: Prefs.ranges.radiusItems[0]
        maximum: Prefs.ranges.radiusItems[1]
        unit: I18n.trFor("marina", " items")
    }

    MarinaSliderSetting {
        visible: magnifyToggle.value
        settingKey: "animationMs"
        label: I18n.trFor("marina", "Enter/exit animation")
        description: I18n.trFor("marina", "Ramp-up when the pointer enters the dock and ramp-down when it leaves")
        defaultValue: Prefs.defaults.animationMs
        minimum: Prefs.ranges.animationMs[0]
        maximum: Prefs.ranges.animationMs[1]
        unit: "ms"
    }
}
