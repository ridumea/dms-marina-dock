pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import "lib/geometry.mjs" as Geometry

// Transparent layer-shell window drawing the magnified row; its input region is empty unless hovering.
PanelWindow { // qmllint disable uncreatable-type
    id: overlayWindow

    required property var dock
    // Read by the debug layout self-check.
    readonly property alias rows: rowRepeater

    screen: overlayWindow.dock.parentScreen
    color: "transparent"
    visible: true

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "dms:marina"
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    margins { // qmllint disable unresolved-type unqualified
        top: overlayWindow.dock.barEdge === "top" ? overlayWindow.dock.edgeMargin : 0
        bottom: overlayWindow.dock.barEdge === "bottom" ? overlayWindow.dock.edgeMargin : 0
        left: overlayWindow.dock.barEdge === "left" ? overlayWindow.dock.edgeMargin : 0
        right: overlayWindow.dock.barEdge === "right" ? overlayWindow.dock.edgeMargin : 0
    }

    anchors {
        top: overlayWindow.dock.isVerticalOrientation ? true : overlayWindow.dock.barEdge === "top"
        bottom: overlayWindow.dock.isVerticalOrientation ? true : overlayWindow.dock.barEdge === "bottom"
        left: overlayWindow.dock.isVerticalOrientation ? overlayWindow.dock.barEdge === "left" : true
        right: overlayWindow.dock.isVerticalOrientation ? overlayWindow.dock.barEdge === "right" : true
    }
    implicitWidth: overlayWindow.dock.isVerticalOrientation ? overlayWindow.dock.overlayThickness : 0
    implicitHeight: overlayWindow.dock.isVerticalOrientation ? 0 : overlayWindow.dock.overlayThickness

    // The input region stays fixed at the row's largest extent for the whole hover: changing it per pointer motion commits the surface and stutters.
    readonly property real sideGrowMax: Geometry.sideGrowMax(overlayWindow.dock.fullProfile)
    readonly property real maskMainStart: overlayWindow.dock.baseStartScene - sideGrowMax - overlayWindow.dock.horizontalPadding
    readonly property real maskMainLen: overlayWindow.dock.baseTotal + sideGrowMax * 2 + overlayWindow.dock.horizontalPadding * 2
    readonly property real maskCross: overlayWindow.dock.restEdgeOffset + overlayWindow.dock.iconCellSize + overlayWindow.dock.iconBase * (overlayWindow.dock.maxScale - 1) + Theme.spacingXS
    readonly property real crossSize: overlayWindow.dock.isVerticalOrientation ? width : height
    readonly property real maskCrossStart: overlayWindow.dock.edgeIsFar ? (crossSize - maskCross) : 0

    mask: Region {
        x: overlayWindow.dock.hoverActive ? (overlayWindow.dock.isVerticalOrientation ? overlayWindow.maskCrossStart : overlayWindow.maskMainStart) : 0
        y: overlayWindow.dock.hoverActive ? (overlayWindow.dock.isVerticalOrientation ? overlayWindow.maskMainStart : overlayWindow.maskCrossStart) : 0
        width: overlayWindow.dock.hoverActive ? (overlayWindow.dock.isVerticalOrientation ? overlayWindow.maskCross : overlayWindow.maskMainLen) : 0
        height: overlayWindow.dock.hoverActive ? (overlayWindow.dock.isVerticalOrientation ? overlayWindow.maskMainLen : overlayWindow.maskCross) : 0
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton

        // The input region is larger than the row, so hover is decided by position.
        function updateInside(mx, my) {
            const b = (overlayWindow.dock.isVerticalOrientation ? my : mx) - overlayWindow.dock.baseStartScene;
            overlayWindow.dock.setOverlayInside(b >= -overlayWindow.dock.horizontalPadding && b <= overlayWindow.dock.baseTotal + overlayWindow.dock.horizontalPadding);
        }
        onEntered: {
            overlayWindow.dock.pointerEntered("overlay", overlayWindow.dock.isVerticalOrientation ? mouseY : mouseX);
            updateInside(mouseX, mouseY);
        }
        onPositionChanged: mouse => {
            overlayWindow.dock.pointerMoved("overlay", overlayWindow.dock.isVerticalOrientation ? mouse.y : mouse.x);
            updateInside(mouse.x, mouse.y);
        }
        onExited: overlayWindow.dock.pointerLeft("overlay")
        onWheel: wheel => {
            wheel.accepted = true;
            overlayWindow.dock.cycleWindows(wheel.angleDelta.y);
        }
    }

    Item {
        anchors.fill: parent

        Rectangle {
            id: overlayPill
            readonly property real pad: overlayWindow.dock.horizontalPadding
            readonly property real crossCenter: overlayWindow.dock.edgeIsFar ? ((overlayWindow.dock.isVerticalOrientation ? parent.width : parent.height) - overlayWindow.dock.edgeOffset - overlayWindow.dock.iconBase / 2) : (overlayWindow.dock.edgeOffset + overlayWindow.dock.iconBase / 2)
            // Covers the tiled icons only; floating icons sit before it without a background.
            property real animStartSlot: overlayWindow.dock.pillStartSlot
            Behavior on animStartSlot {
                enabled: overlayWindow.dock.dragging
                NumberAnimation {
                    duration: overlayWindow.dock.layoutAnimMs
                    easing.type: Easing.OutCubic
                }
            }
            readonly property real mainStart: overlayWindow.dock.slotMainStartF(animStartSlot)
            visible: overlayWindow.dock.pillStartSlot < overlayWindow.dock.slotCount
            x: overlayWindow.dock.isVerticalOrientation ? crossCenter - overlayWindow.dock.widgetThickness / 2 : mainStart - pad
            y: overlayWindow.dock.isVerticalOrientation ? mainStart - pad : crossCenter - overlayWindow.dock.widgetThickness / 2
            readonly property real animLength: overlayWindow.dock.animSlotCount > 0 ? overlayWindow.dock.slotMainStartF(overlayWindow.dock.animSlotCount - 1) + overlayWindow.dock.cellAtSlotF(overlayWindow.dock.animSlotCount - 1) - mainStart : 0
            width: overlayWindow.dock.isVerticalOrientation ? overlayWindow.dock.widgetThickness : animLength + pad * 2
            height: overlayWindow.dock.isVerticalOrientation ? animLength + pad * 2 : overlayWindow.dock.widgetThickness
            radius: (overlayWindow.dock.barConfig?.noBackground ?? false) ? 0 : Theme.cornerRadius
            opacity: overlayWindow.dock.overlayDrawing ? 1 : 0
            color: {
                if (overlayWindow.dock.barConfig?.noBackground ?? false)
                    return "transparent";
                const transparency = (overlayWindow.dock.barConfig && overlayWindow.dock.barConfig.widgetTransparency !== undefined) ? overlayWindow.dock.barConfig.widgetTransparency : 1.0;
                const baseColor = Theme.widgetBaseBackgroundColor;
                return Theme.widgetBackgroundHasAlpha ? Theme.blendAlpha(baseColor, transparency) : Theme.withAlpha(baseColor, transparency);
            }
            border.width: (overlayWindow.dock.barConfig?.widgetOutlineEnabled ?? false) ? (overlayWindow.dock.barConfig?.widgetOutlineThickness ?? 1) : 0
            border.color: {
                if (!(overlayWindow.dock.barConfig?.widgetOutlineEnabled ?? false))
                    return "transparent";
                const opacity = overlayWindow.dock.barConfig?.widgetOutlineOpacity ?? 1.0;
                switch (overlayWindow.dock.barConfig?.widgetOutlineColor || "primary") {
                case "surfaceText":
                    return Theme.withAlpha(Theme.surfaceText, opacity);
                case "secondary":
                    return Theme.withAlpha(Theme.secondary, opacity);
                default:
                    return Theme.withAlpha(Theme.primary, opacity);
                }
            }
        }

        Rectangle {
            id: overlayLabel
            readonly property int idx: overlayWindow.dock.labelIndex
            readonly property bool active: overlayWindow.dock.labelShown && idx >= 0 && idx < overlayWindow.dock.windowCount
            readonly property real extent: active ? (overlayWindow.dock.edgeOffset + overlayWindow.dock.iconSizeFor(idx) + 6) : 0
            readonly property real mainCenter: active ? overlayWindow.dock.itemMainCenter(idx) : 0
            readonly property real hostCross: overlayWindow.dock.isVerticalOrientation ? parent.width : parent.height
            visible: active && opacity > 0
            opacity: (active && !overlayWindow.dock.dragging) ? overlayWindow.dock.magnifyAmount : 0
            readonly property real maxTextWidth: 300 - Theme.spacingM * 2
            width: Math.min(300, Math.max(120, labelRows.implicitWidth + Theme.spacingM * 2))
            height: labelRows.implicitHeight + Theme.spacingS * 2
            x: {
                if (overlayWindow.dock.isVerticalOrientation)
                    return overlayWindow.dock.barEdge === "left" ? (extent + Theme.spacingXS) : (hostCross - extent - Theme.spacingXS - width);
                return Math.round(Math.max(Theme.spacingS, Math.min(overlayWindow.dock.screenMain - width - Theme.spacingS, mainCenter - width / 2)));
            }
            y: {
                if (overlayWindow.dock.isVerticalOrientation)
                    return Math.round(Math.max(Theme.spacingS, Math.min(overlayWindow.dock.screenMain - height - Theme.spacingS, mainCenter - height / 2)));
                return overlayWindow.dock.barEdge === "bottom" ? (hostCross - extent - Theme.spacingXS - height) : (extent + Theme.spacingXS);
            }
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
            border.width: BlurService.borderWidth
            border.color: BlurService.borderColor

            Column {
                id: labelRows
                anchors.centerIn: parent
                spacing: 2

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: overlayLabel.active ? overlayWindow.dock.labelTitleFor(overlayLabel.idx) : ""
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.DemiBold
                    color: Theme.surfaceText
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, overlayLabel.maxTextWidth)
                }

                StyledText {
                    id: labelDetail
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: text !== ""
                    text: overlayLabel.active ? overlayWindow.dock.labelDetailFor(overlayLabel.idx) : ""
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, overlayLabel.maxTextWidth)
                }
            }
        }

        Repeater {
            model: overlayWindow.dock.stackRuns
            Rectangle {
                required property var modelData
                readonly property real hostCross: overlayWindow.dock.isVerticalOrientation ? parent.width : parent.height
                readonly property var range: overlayWindow.dock.trayRange(modelData)
                readonly property bool includesGap: range.includesGap
                readonly property bool includesHome: range.includesHome
                visible: range.visible
                readonly property int startSlot: range.startSlot
                readonly property int endSlot: range.endSlot
                property real animStartSlot: startSlot
                property real animEndSlot: endSlot
                Behavior on animStartSlot {
                    enabled: overlayWindow.dock.dragging
                    NumberAnimation {
                        duration: overlayWindow.dock.layoutAnimMs
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on animEndSlot {
                    enabled: overlayWindow.dock.dragging
                    NumberAnimation {
                        duration: overlayWindow.dock.layoutAnimMs
                        easing.type: Easing.OutCubic
                    }
                }
                readonly property real mainStart: visible ? overlayWindow.dock.slotMainStartF(animStartSlot) : 0
                readonly property real mainEnd: visible ? overlayWindow.dock.slotMainStartF(animEndSlot) + overlayWindow.dock.cellAtSlotF(animEndSlot) : 0
                readonly property real crossSize: visible ? Math.max(overlayWindow.dock.runMaxIconSize(modelData), includesGap ? overlayWindow.dock.iconBase + overlayWindow.dock.growAtSlot(overlayWindow.dock.gapSlot, overlayWindow.dock.basePointer) : 0, includesHome ? overlayWindow.dock.iconBase + overlayWindow.dock.growAtSlot(overlayWindow.dock.homeSlot, overlayWindow.dock.basePointer) : 0) + 6 : 0
                readonly property real crossPos: overlayWindow.dock.edgeIsFar ? (hostCross - (overlayWindow.dock.edgeOffset - 3) - crossSize) : (overlayWindow.dock.edgeOffset - 3)
                x: overlayWindow.dock.isVerticalOrientation ? crossPos : mainStart
                y: overlayWindow.dock.isVerticalOrientation ? mainStart : crossPos
                width: overlayWindow.dock.isVerticalOrientation ? crossSize : (mainEnd - mainStart)
                height: overlayWindow.dock.isVerticalOrientation ? (mainEnd - mainStart) : crossSize
                radius: overlayWindow.dock.stackTrayRadiusFor(crossSize)
                color: overlayWindow.dock.stackTrayColor
                border.width: 1
                border.color: overlayWindow.dock.stackTrayBorderColor
                opacity: overlayWindow.dock.overlayDrawing ? 1 : 0
            }
        }

        // Without magnification this is the only hover feedback.
        Rectangle {
            readonly property int slot: overlayWindow.dock.hoveredSlot
            readonly property real hostCross: overlayWindow.dock.isVerticalOrientation ? parent.width : parent.height
            readonly property bool active: !overlayWindow.dock.magnifyActive && !overlayWindow.dock.dragging && overlayWindow.dock.hoveredIndex >= 0 && !overlayWindow.dock.isSeparatorAt(overlayWindow.dock.hoveredIndex)
            readonly property real inset: 2
            readonly property real mainLength: overlayWindow.dock.baseCell + Theme.spacingXS
            readonly property real mainCenter: active ? overlayWindow.dock.iconMainCenterF(slot) : 0
            readonly property real crossLength: overlayWindow.dock.widgetThickness - inset * 2
            readonly property real crossCenter: overlayWindow.dock.edgeIsFar ? (hostCross - overlayWindow.dock.edgeOffset - overlayWindow.dock.iconBase / 2) : (overlayWindow.dock.edgeOffset + overlayWindow.dock.iconBase / 2)
            visible: active && opacity > 0
            opacity: overlayWindow.dock.magnifyAmount
            x: Math.round(overlayWindow.dock.isVerticalOrientation ? crossCenter - crossLength / 2 : mainCenter - mainLength / 2)
            y: Math.round(overlayWindow.dock.isVerticalOrientation ? mainCenter - mainLength / 2 : crossCenter - crossLength / 2)
            width: overlayWindow.dock.isVerticalOrientation ? crossLength : mainLength
            height: overlayWindow.dock.isVerticalOrientation ? mainLength : crossLength
            radius: Math.max(0, Theme.cornerRadius - inset)
            // Stronger than DMS's hover tint so it reads over the translucent pill.
            color: Theme.withAlpha(Theme.surfaceText, 0.16)
        }

        Rectangle {
            readonly property bool active: overlayWindow.dock.focusSlot >= 0
            readonly property real hostCross: overlayWindow.dock.isVerticalOrientation ? parent.width : parent.height
            readonly property bool underGhost: overlayWindow.dock.dragging && overlayWindow.dock.focusedIndex === overlayWindow.dock.dragIndex
            readonly property real center: underGhost ? overlayWindow.dock.dragPointer : overlayWindow.dock.iconMainCenterF(overlayWindow.dock.animFocusSlot)
            readonly property real crossPos: Theme.snap(overlayWindow.dock.edgeIsFar ? (hostCross - overlayWindow.dock.edgeOffset + overlayWindow.dock.indicatorGap) : (overlayWindow.dock.edgeOffset - overlayWindow.dock.indicatorGap - overlayWindow.dock.indicatorThickness), overlayWindow.dock.dpr)
            visible: active && opacity > 0 && !(underGhost && overlayWindow.dock.dragOutside)
            opacity: overlayWindow.dock.overlayDrawing ? 1 : 0
            width: overlayWindow.dock.isVerticalOrientation ? overlayWindow.dock.indicatorThickness : overlayWindow.dock.indicatorLength
            height: overlayWindow.dock.isVerticalOrientation ? overlayWindow.dock.indicatorLength : overlayWindow.dock.indicatorThickness
            radius: overlayWindow.dock.indicatorThickness / 2
            color: Theme.primary
            x: overlayWindow.dock.isVerticalOrientation ? crossPos : center - width / 2
            y: overlayWindow.dock.isVerticalOrientation ? center - height / 2 : crossPos
            z: 3
        }

        Image {
            id: dragGhost
            readonly property real hostCross: overlayWindow.dock.isVerticalOrientation ? parent.width : parent.height
            // Off the dock the full-screen drag window draws it instead.
            visible: overlayWindow.dock.dragging && !overlayWindow.dock.dragOutside && source !== ""
            source: overlayWindow.dock.dragIconSource
            width: overlayWindow.dock.iconBase * overlayWindow.dock.maxScale
            height: width
            sourceSize: Qt.size(overlayWindow.dock.iconMaxPx, overlayWindow.dock.iconMaxPx)
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            asynchronous: true
            opacity: 0.95
            readonly property real crossPos: overlayWindow.dock.edgeIsFar ? hostCross - overlayWindow.dock.edgeOffset - width : overlayWindow.dock.edgeOffset
            z: 20
            x: overlayWindow.dock.isVerticalOrientation ? crossPos : overlayWindow.dock.dragPointer - width / 2
            y: overlayWindow.dock.isVerticalOrientation ? overlayWindow.dock.dragPointer - height / 2 : crossPos
        }

        Item {
            x: overlayWindow.dock.isVerticalOrientation ? 0 : overlayWindow.dock.rowStartScene
            y: overlayWindow.dock.isVerticalOrientation ? overlayWindow.dock.rowStartScene : 0
            width: overlayWindow.dock.isVerticalOrientation ? parent.width : overlayWindow.dock.magTotal
            height: overlayWindow.dock.isVerticalOrientation ? overlayWindow.dock.magTotal : parent.height
            Repeater {
                id: rowRepeater
                model: ScriptModel {
                    values: overlayWindow.dock.modelValues
                    objectProp: overlayWindow.dock.modelKey
                }
                delegate: MarinaDelegate {
                    dock: overlayWindow.dock
                    inOverlay: true
                }
            }
        }
    }
}
