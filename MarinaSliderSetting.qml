import QtQuick
import qs.Common
import qs.Widgets

Column {
    id: root

    required property string settingKey
    required property string label
    property string description: ""
    property int defaultValue: 0
    // A moving limit changes only the shown value, so loading one setting never overwrites another not yet loaded.
    property int storedValue: defaultValue
    property int value: defaultValue
    property int minimum: 0
    property int maximum: 100
    property int step: 1
    // Limits within the track: the track keeps its scale and the thumb stops at the limit.
    property int lowest: minimum
    property int highest: maximum
    property string unit: ""

    width: parent.width
    spacing: Theme.spacingS

    function limited(v) {
        return Math.max(lowest, Math.min(highest, v));
    }

    function settingsPage() {
        const methods = ["saveValue", "loadValue"];
        let item = root.parent;
        while (item) {
            const candidate = item;
            if (methods.every(m => typeof candidate[m] === "function"))
                return item;
            item = item.parent;
        }
        return null;
    }

    // Also called by the settings page once it has its plugin service and whenever settings change.
    function loadValue() {
        const settings = settingsPage();
        if (!settings || !settings.pluginService)
            return;
        storedValue = settings.loadValue(settingKey, defaultValue);
        applyLimits();
    }

    function applyLimits() {
        value = limited(storedValue);
        slider.value = value;
    }

    // Only user actions save.
    function save(v) {
        storedValue = limited(v);
        applyLimits();
        const settings = settingsPage();
        if (settings)
            settings.saveValue(settingKey, storedValue);
    }

    Component.onCompleted: loadValue()
    onLowestChanged: applyLimits()
    onHighestChanged: applyLimits()

    Row {
        width: parent.width
        spacing: Theme.spacingS

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - resetButton.width - Theme.spacingS
            spacing: Theme.spacingXS

            StyledText {
                width: parent.width
                text: root.label
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            StyledText {
                visible: root.description !== ""
                width: parent.width
                text: root.description
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }
        }

        DankActionButton {
            id: resetButton
            anchors.verticalCenter: parent.verticalCenter
            buttonSize: 36
            iconName: "restart_alt"
            iconSize: 20
            iconColor: Theme.surfaceVariantText
            opacity: root.value !== root.defaultValue ? 1 : 0
            enabled: root.value !== root.defaultValue
            onClicked: root.save(root.defaultValue)
        }
    }

    DankSlider {
        id: slider
        width: parent.width
        value: root.value
        minimum: root.minimum
        maximum: root.maximum
        step: root.step
        unit: root.unit
        wheelEnabled: false
        thumbOutlineColor: Theme.withAlpha(Theme.surfaceContainerHighest, Theme.popupTransparency)
        onSliderValueChanged: newValue => root.save(newValue)
    }
}
