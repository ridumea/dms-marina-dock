import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Minimize/Restore appear only where the compositor supports them (not niri).
PanelWindow { // qmllint disable uncreatable-type
    id: contextMenuWindow

    property var targetScreen: null

    // Emitted once the menu has closed; the owner destroys it.
    signal dismissed

    WindowBlur {
        targetWindow: contextMenuWindow
        blurX: contextMenuRect.x
        blurY: contextMenuRect.y
        blurWidth: contextMenuWindow.isVisible ? contextMenuRect.width : 0
        blurHeight: contextMenuWindow.isVisible ? contextMenuRect.height : 0
        blurRadius: Theme.cornerRadius
    }

    property var currentWindow: null
    readonly property real menuHeight: contextMenuRect.height
    property bool isVisible: false
    property point anchorPos: Qt.point(0, 0)
    property bool isVertical: false
    property string edge: "top"

    property int triggerBarPosition: (SettingsData.getPrimaryBarConfig()?.position ?? SettingsData.Position.Top)
    property real triggerBarThickness: 0
    property real triggerBarSpacing: 0
    property var triggerBarConfig: null

    readonly property real effectiveBarThickness: {
        if (triggerBarThickness > 0 && triggerBarSpacing > 0) {
            return triggerBarThickness + triggerBarSpacing;
        }
        return Theme.barThickness(triggerBarConfig?.innerPadding ?? 4, CompositorService.getScreenScale(contextMenuWindow.screen)) + (triggerBarConfig?.spacing ?? 4);
    }

    property var barBounds: {
        if (!contextMenuWindow.screen || !triggerBarConfig) {
            return {
                "x": 0,
                "y": 0,
                "width": 0,
                "height": 0,
                "wingSize": 0
            };
        }
        return SettingsData.getBarBounds(contextMenuWindow.screen, effectiveBarThickness, triggerBarPosition, triggerBarConfig);
    }

    property real barY: barBounds.y

    function showAt(x, y, vertical, barEdge) {
        screen = targetScreen;
        anchorPos = Qt.point(x, y);
        isVertical = vertical ?? false;
        edge = barEdge ?? "top";
        isVisible = true;
        visible = true;

        if (screen) {
            TrayMenuManager.registerMenu(screen.name, contextMenuWindow);
        }
    }

    function close() {
        isVisible = false;
        visible = false;

        if (screen) {
            TrayMenuManager.unregisterMenu(screen.name);
        }
        dismissed();
    }

    implicitWidth: 100
    implicitHeight: 40
    visible: false
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    Component.onDestruction: {
        if (screen) {
            TrayMenuManager.unregisterMenu(screen.name);
        }
    }

    Connections {
        target: PopoutManager
        function onPopoutOpening() {
            contextMenuWindow.close();
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: contextMenuWindow.close()
    }

    Rectangle {
        id: contextMenuRect
        x: {
            if (contextMenuWindow.isVertical) {
                if (contextMenuWindow.edge === "left") {
                    return Math.min(contextMenuWindow.width - width - 10, contextMenuWindow.anchorPos.x);
                } else {
                    return Math.max(10, contextMenuWindow.anchorPos.x - width);
                }
            } else {
                const left = 10;
                const right = contextMenuWindow.width - width - 10;
                const want = contextMenuWindow.anchorPos.x - width / 2;
                return Math.max(left, Math.min(right, want));
            }
        }
        y: {
            if (contextMenuWindow.isVertical) {
                const top = Math.max(contextMenuWindow.barY, 10);
                const bottom = contextMenuWindow.height - height - 10;
                const want = contextMenuWindow.anchorPos.y - height / 2;
                return Math.max(top, Math.min(bottom, want));
            } else {
                return contextMenuWindow.anchorPos.y;
            }
        }
        width: 120
        height: menuColumn.height + Theme.spacingXS * 2
        color: Theme.withAlpha(Theme.surfaceContainer, Theme.popupTransparency)
        radius: Theme.cornerRadius
        border.width: BlurService.borderWidth
        border.color: BlurService.borderColor

        Column {
            id: menuColumn
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Theme.spacingXS
            width: parent.width - Theme.spacingXS * 2
            spacing: 1

            Rectangle {
                visible: CompositorService.canMinimize(contextMenuWindow.currentWindow)
                width: parent.width
                height: 28
                radius: Theme.cornerRadius
                color: minimizeMouseArea.containsMouse ? BlurService.hoverColor(Theme.widgetBaseHoverColor) : "transparent"

                StyledText {
                    anchors.centerIn: parent
                    text: contextMenuWindow.currentWindow?.minimized ? I18n.trFor("marina", "Restore") : I18n.trFor("marina", "Minimize")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.widgetTextColor
                }

                MouseArea {
                    id: minimizeMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const targetWindow = contextMenuWindow.currentWindow;
                        if (targetWindow) {
                            if (targetWindow.minimized) {
                                CompositorService.activateToplevel(targetWindow);
                            } else {
                                targetWindow.minimized = true;
                            }
                        }
                        contextMenuWindow.close();
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 28
                radius: Theme.cornerRadius
                color: closeMouseArea.containsMouse ? BlurService.hoverColor(Theme.widgetBaseHoverColor) : "transparent"

                StyledText {
                    anchors.centerIn: parent
                    text: I18n.trFor("marina", "Close")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.widgetTextColor
                }

                MouseArea {
                    id: closeMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (contextMenuWindow.currentWindow) {
                            contextMenuWindow.currentWindow.close();
                        }
                        contextMenuWindow.close();
                    }
                }
            }
        }
    }
}
