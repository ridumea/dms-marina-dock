pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

Item {
    id: delegateItem

    required property int index
    required property var modelData
    required property var dock
    required property bool inOverlay
    readonly property bool isVertical: delegateItem.dock.isVerticalOrientation
    readonly property bool isSeparator: modelData?.dockSeparator === true
    readonly property real iconOpacity: delegateItem.isMinimized ? 0.4 : 1
    readonly property bool tintedIcon: delegateItem.appId === "org.quickshell" || delegateItem.appId === "com.danklinux.dms"

    readonly property bool showVisuals: inOverlay ? delegateItem.dock.overlayDrawing : !delegateItem.dock.barIconsHidden

    readonly property bool isGrouped: delegateItem.dock._groupByApp
    readonly property var groupData: delegateItem.isGrouped ? modelData : null
    readonly property var toplevelData: delegateItem.isGrouped ? (modelData.windows.length > 0 ? modelData.windows[0].toplevel : null) : modelData
    readonly property string appId: delegateItem.isGrouped ? modelData.appId : (modelData.appId || "")
    readonly property string effectiveAppId: {
        delegateItem.dock._appIdSubstitutionsTrigger;
        return Paths.moddedAppId(delegateItem.appId);
    }
    readonly property string windowTitle: toplevelData ? (toplevelData.title || I18n.trFor("marina", "(Unnamed)")) : I18n.trFor("marina", "(Unnamed)")
    readonly property var toplevelObject: toplevelData
    readonly property int windowCount: delegateItem.isGrouped ? modelData.windows.length : 1
    readonly property bool isMinimized: {
        if (!CompositorService.supportsMinimize)
            return false;
        if (delegateItem.isGrouped)
            return delegateItem.groupData.windows.length > 0 && delegateItem.groupData.windows.every(w => w.toplevel.minimized);
        return delegateItem.toplevelObject?.minimized === true;
    }

    readonly property real factor: inOverlay ? delegateItem.dock.factorFor(index) : 1
    readonly property real iconSize: delegateItem.dock.iconBase * factor
    readonly property real grow: iconSize - delegateItem.dock.iconBase

    // The dragged item stays visible at the open slot: its mouse area holds the drag's grab, which Qt drops for invisible items.
    readonly property int slot: delegateItem.dock.slotOf(index)
    readonly property bool isDragged: delegateItem.dock.dragging && delegateItem.dock.dragIndex === index
    readonly property real restCell: delegateItem.isSeparator ? delegateItem.dock.separatorCell : delegateItem.dock.baseCell
    readonly property real mainSize: Math.max(0, restCell + grow)
    readonly property int layoutSlot: slot >= 0 ? slot : (isDragged ? Math.max(0, delegateItem.dock.homeSlot) : 0)
    property real animSlot: layoutSlot
    Behavior on animSlot {
        // Only while dragging: the model catching up with niri after the drop must not animate.
        enabled: delegateItem.inOverlay && delegateItem.dock.dragging && delegateItem.dock.snapIndex !== delegateItem.index
        NumberAnimation {
            duration: delegateItem.dock.layoutAnimMs
            easing.type: Easing.OutCubic
        }
    }
    readonly property real mainPos: inOverlay ? delegateItem.dock.slotMainStartF(animSlot) - delegateItem.dock.rowStartScene : delegateItem.dock.restSlotStart(layoutSlot) - delegateItem.dock.viewTiledOffset
    visible: slot >= 0 || isDragged
    x: isVertical ? 0 : mainPos
    y: isVertical ? mainPos : 0
    readonly property real bgCross: delegateItem.dock.iconCellSize + grow
    readonly property real hostCross: inOverlay ? (isVertical ? (parent ? parent.width : 0) : (parent ? parent.height : 0)) : delegateItem.dock.barThickness
    readonly property real bgCrossPos: {
        if (!inOverlay)
            return Math.round((hostCross - bgCross) / 2);
        const margin = delegateItem.dock.edgeOffset - 3;
        return delegateItem.dock.edgeIsFar ? (hostCross - margin - bgCross) : margin;
    }

    width: isVertical ? hostCross : mainSize
    height: isVertical ? mainSize : hostCross

    Item {
        id: visualContent
        visible: !delegateItem.isDragged
        x: delegateItem.isVertical ? delegateItem.bgCrossPos : 0
        y: delegateItem.isVertical ? 0 : delegateItem.bgCrossPos
        width: delegateItem.isVertical ? delegateItem.bgCross : delegateItem.mainSize
        height: delegateItem.isVertical ? delegateItem.mainSize : delegateItem.bgCross

        Item {
            id: iconLayer
            anchors.fill: parent
            opacity: delegateItem.showVisuals ? 1 : 0

            // Plain Image with a fixed sourceSize: IconImage re-requests the icon at every size and blinks while magnifying.
            Image {
                id: iconImg
                x: (delegateItem.dock.compact || delegateItem.isVertical) ? Math.round((parent.width - width) / 2) : Theme.spacingXS
                y: Math.round((parent.height - height) / 2)
                width: delegateItem.iconSize
                height: delegateItem.iconSize
                sourceSize: Qt.size(delegateItem.dock.iconMaxPx, delegateItem.dock.iconMaxPx)
                fillMode: Image.PreserveAspectFit
                source: {
                    delegateItem.dock._desktopEntriesUpdateTrigger;
                    delegateItem.dock._appIdSubstitutionsTrigger;
                    if (!delegateItem.effectiveAppId)
                        return "";
                    const desktopEntry = DesktopEntries.heuristicLookup(delegateItem.effectiveAppId);
                    return Paths.getAppIcon(delegateItem.effectiveAppId, desktopEntry);
                }
                smooth: true
                mipmap: true
                asynchronous: true
                visible: status === Image.Ready
                opacity: delegateItem.iconOpacity
                layer.enabled: delegateItem.tintedIcon
                layer.smooth: true
                layer.mipmap: true
                layer.effect: MultiEffect {
                    saturation: 0
                    colorization: 1
                    colorizationColor: Theme.primary
                }
            }

            DankIcon {
                x: (delegateItem.dock.compact || delegateItem.isVertical) ? Math.round((parent.width - width) / 2) : Theme.spacingXS
                y: Math.round((parent.height - height) / 2)
                // A hidden glyph keeps a fixed size so it does not re-lay out on every pointer move.
                size: visible ? delegateItem.iconSize : delegateItem.dock.iconBase
                name: "sports_esports"
                color: Theme.widgetTextColor
                visible: !iconImg.visible && Paths.isSteamApp(delegateItem.effectiveAppId)
                opacity: delegateItem.iconOpacity
            }

            StyledText {
                anchors.horizontalCenter: iconImg.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                visible: !delegateItem.isSeparator && !iconImg.visible && !Paths.isSteamApp(delegateItem.effectiveAppId)
                text: {
                    delegateItem.dock._desktopEntriesUpdateTrigger;
                    if (!delegateItem.effectiveAppId)
                        return "?";
                    const desktopEntry = DesktopEntries.heuristicLookup(delegateItem.effectiveAppId);
                    const appName = Paths.getAppName(delegateItem.effectiveAppId, desktopEntry);
                    return appName.charAt(0).toUpperCase();
                }
                font.pixelSize: visible ? Math.round(10 * delegateItem.factor) : 10
                color: Theme.widgetTextColor
                opacity: delegateItem.iconOpacity
            }

            Rectangle {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: delegateItem.dock.compact ? -2 : 2
                anchors.bottomMargin: -2
                width: 14
                height: 14
                radius: 7
                color: Theme.primary
                visible: delegateItem.isGrouped && delegateItem.windowCount > 1
                z: 10

                StyledText {
                    anchors.centerIn: parent
                    text: delegateItem.windowCount > 9 ? "9+" : delegateItem.windowCount
                    font.pixelSize: 9
                    color: Theme.surface
                }
            }

            StyledText {
                anchors.left: iconImg.right
                anchors.leftMargin: Theme.spacingXS
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                visible: !delegateItem.isSeparator && !delegateItem.dock.compact && !delegateItem.isVertical
                text: delegateItem.windowTitle
                font.pixelSize: Theme.barTextSize(delegateItem.dock.barThickness, delegateItem.dock.barConfig?.fontScale, delegateItem.dock.barConfig?.maximizeWidgetText)
                color: Theme.widgetTextColor
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        DankRipple {
            id: itemRipple
            cornerRadius: Theme.cornerRadius
        }
    }

    MouseArea {
        id: mouseArea
        readonly property real gapHalf: Theme.spacingXS / 2
        y: delegateItem.isVertical ? -gapHalf : (delegateItem.inOverlay ? 0 : -delegateItem.dock.topMargin)
        x: delegateItem.isVertical ? (delegateItem.inOverlay ? 0 : -delegateItem.dock.leftMargin) : -gapHalf
        width: parent.width + (delegateItem.isVertical ? (delegateItem.inOverlay ? 0 : delegateItem.dock.leftMargin + delegateItem.dock.rightMargin) : gapHalf * 2)
        height: parent.height + (delegateItem.isVertical ? gapHalf * 2 : (delegateItem.inOverlay ? 0 : delegateItem.dock.topMargin + delegateItem.dock.bottomMargin))
        hoverEnabled: false
        enabled: !delegateItem.isSeparator
        property bool dragStarted: false
        property bool justDragged: false
        preventStealing: dragStarted
        cursorShape: dragStarted ? Qt.DragMoveCursor : Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        function sceneMain(mx, my) {
            return delegateItem.dock.sceneMainOf(mouseArea, mx, my);
        }

        // During a drag the pointer is grabbed, so it can be reported beyond the overlay.
        function crossFromEdge(mx, my) {
            const p = mapToItem(null, mx, my);
            const v = delegateItem.dock.isVerticalOrientation ? p.x : p.y;
            return delegateItem.dock.edgeIsFar ? delegateItem.dock.overlayThickness - v : v;
        }

        Timer {
            id: longPressTimer
            interval: delegateItem.dock.longPressMs
            repeat: false
            onTriggered: {
                if (!mouseArea.pressed || !delegateItem.inOverlay || !delegateItem.dock.canLift(delegateItem.index))
                    return;
                mouseArea.dragStarted = true;
                delegateItem.dock.beginDrag(delegateItem.index, mouseArea.sceneMain(mouseArea.mouseX, mouseArea.mouseY));
            }
        }

        onPressed: mouse => {
            justDragged = false;
            const pos = mapToItem(visualContent, mouse.x, mouse.y);
            itemRipple.trigger(pos.x, pos.y);
            if (mouse.button === Qt.LeftButton && delegateItem.inOverlay && delegateItem.dock.canLift(delegateItem.index))
                longPressTimer.start();
        }
        onPositionChanged: mouse => {
            if (dragStarted)
                delegateItem.dock.updateDrag(sceneMain(mouse.x, mouse.y), crossFromEdge(mouse.x, mouse.y));
        }
        onReleased: mouse => {
            longPressTimer.stop();
            if (dragStarted) {
                dragStarted = false;
                justDragged = true;
                delegateItem.dock.endDrag(false);
            }
        }
        onCanceled: {
            longPressTimer.stop();
            if (dragStarted) {
                dragStarted = false;
                delegateItem.dock.endDrag(true);
            }
        }
        onClicked: mouse => {
            if (justDragged) {
                justDragged = false;
                return;
            }
            if (mouse.button === Qt.LeftButton) {
                if (delegateItem.isGrouped && delegateItem.windowCount > 1) {
                    let currentIndex = -1;
                    for (var i = 0; i < delegateItem.groupData.windows.length; i++) {
                        if (delegateItem.groupData.windows[i].toplevel.activated) {
                            currentIndex = i;
                            break;
                        }
                    }
                    const nextIndex = (currentIndex + 1) % delegateItem.groupData.windows.length;
                    const next = delegateItem.groupData.windows[nextIndex].toplevel;
                    CompositorService.activateToplevel(next);
                    delegateItem.dock.assumeFocus(next?.niriWindowId);
                } else if (delegateItem.toplevelObject) {
                    CompositorService.toggleToplevel(delegateItem.toplevelObject);
                    // The marker moves at once; niri's confirmation follows.
                    if (!delegateItem.toplevelObject.activated)
                        delegateItem.dock.assumeFocus(delegateItem.toplevelObject.niriWindowId);
                }
            } else if (mouse.button === Qt.RightButton) {
                delegateItem.dock.openContextMenu(delegateItem.index, delegateItem.toplevelObject);
            } else if (mouse.button === Qt.MiddleButton) {
                if (delegateItem.toplevelObject) {
                    if (typeof delegateItem.toplevelObject.close === "function") {
                        delegateItem.toplevelObject.close();
                    }
                }
            }
        }
    }
}
