pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import "lib/placement.mjs" as Placement
import "lib/settings.mjs" as Prefs

// One screen's dock: a thin window along the edge holding a Marina widget, beyond any DMS bar there.
Scope {
    id: dockScope

    required property var modelData
    property var settings: Prefs.normalize({})

    readonly property var screen: modelData
    readonly property string edge: settings.edge
    readonly property bool vertical: edge === "left" || edge === "right"
    readonly property real dpr: CompositorService.getScreenScale(screen)
    readonly property real offset: settings.edgeOffset

    readonly property var barConfig: Object.assign({}, SettingsData.getPrimaryBarConfig() || {}, {
        "position": Placement.positions[edge],
        "autoHide": false,
        "spacing": 0,
        "bottomGap": 0
    })
    readonly property real iconPx: settings.minIconPx
    readonly property real widgetThickness: Theme.snapEven(iconPx + 12, dpr)
    readonly property real thickness: widgetThickness + 12
    // The pill's padding sits past the screen edge, so an offset of 0 puts the pill against the edge.
    readonly property real inset: (thickness - widgetThickness) / 2
    readonly property real extent: widgetThickness + offset
    readonly property real barZone: Placement.barZoneOnEdge(SettingsData.barConfigs, edge, bc => SettingsData.barConfigCoversScreen(bc, screen) && !SettingsData.isIslandBarConfig(bc), bc => Theme.barThickness(bc.innerPadding ?? 4, dpr))
    // -1 unless the frame is shown on this screen and reserves this edge itself.
    readonly property real frameZone: {
        SettingsData.barConfigs; // re-evaluate when the bars change
        if (!SettingsData.frameEnabled || !CompositorService.frameWindowVisibleForScreen(screen))
            return -1;
        const barEdge = SettingsData.getActiveBarEdgesForScreen(screen).includes(edge);
        const hostsBand = CompositorService.frameHostsSurfacesForScreen(screen) && !SettingsData.getOverlayBarEdgesForScreen(screen).includes(edge);
        if (barEdge && !hostsBand)
            return -1;
        return SettingsData.frameEdgeReservation(screen, edge);
    }
    readonly property real edgeZone: fullscreenHere ? fullscreenBarZone : frameZone >= 0 ? frameZone : barZone
    // A dock exclusive zone beside a bar can be arranged before the bar's and push the bar over the dock.
    readonly property bool barReserves: frameZone < 0 && barZone > 0
    // A fullscreen window covers Top-layer bars; only overlay-layer bars outside the frame window stay above it.
    readonly property bool fullscreenHere: CompositorService.fullscreenToplevelOnScreen(screen)
    readonly property real fullscreenBarZone: Placement.barZoneOnEdge(SettingsData.barConfigs, edge, bc => SettingsData.barConfigCoversScreen(bc, screen) && !SettingsData.isIslandBarConfig(bc) && ((bc.useOverlayLayer ?? false) || (CompositorService.framePeerSurfacesUseOverlayForScreen(screen) && !CompositorService.frameHostsBarForConfig(screen, bc))), bc => Theme.barThickness(bc.innerPadding ?? 4, dpr))
    readonly property var axis: ({
            "edge": edge,
            "isVertical": vertical
        })

    readonly property bool autoHide: settings.autoHide || fullscreenHere
    property bool stripHover: false
    readonly property bool wanted: !autoHide || stripHover || switchShown || dockWidget.hoverActive || dockWidget.dragging || dockWidget.menuOpen
    property bool shown: true
    readonly property int hideDelayMs: 400
    readonly property int slideInMs: 120
    readonly property int slideOutMs: 200
    readonly property real stripPx: 3
    onWantedChanged: {
        if (wanted) {
            hideTimer.stop();
            shown = true;
        } else {
            hideTimer.restart();
        }
    }
    onFullscreenHereChanged: {
        if (!fullscreenHere || wanted)
            return;
        hideTimer.stop();
        popping = true;
        shown = false;
        popping = false;
    }
    Component.onCompleted: {
        shown = wanted;
        if (showOnSwitch && CompositorService.isNiri)
            noteFocus();
    }
    Timer {
        id: hideTimer
        interval: dockScope.hideDelayMs
        repeat: false
        onTriggered: {
            if (!dockScope.wanted)
                dockScope.shown = false;
        }
    }

    readonly property bool showOnSwitch: settings.autoHide && settings.showOnSwitch
    readonly property int switchShowMs: 1200
    property bool switchShown: false
    Timer {
        id: switchTimer
        interval: dockScope.switchShowMs
        repeat: false
        onTriggered: dockScope.switchShown = false
    }
    property var lastFocus: null
    Connections {
        target: NiriService
        enabled: CompositorService.isNiri && dockScope.showOnSwitch
        function onLastFocusedWindowIdChanged() {
            dockScope.noteFocus();
        }
        // Records the initial focus once niri's windows are known.
        function onWindowsChanged() {
            if (!dockScope.lastFocus)
                dockScope.noteFocus();
        }
    }
    // Reset so a focus change made while this was off is not taken for a switch.
    onShowOnSwitchChanged: {
        lastFocus = null;
        if (showOnSwitch && CompositorService.isNiri)
            noteFocus();
    }
    function noteFocus() {
        const windows = NiriService.windows || [];
        // DMS sets lastFocusedWindowId only after niri's first focus change.
        const id = NiriService.lastFocusedWindowId ?? windows.find(x => x.is_focused)?.id;
        const w = windows.find(x => x.id === id);
        const prev = lastFocus;
        lastFocus = w ? {
            "id": w.id,
            "ws": w.workspace_id,
            "tiled": !w.is_floating
        } : null;
        if (!w || !prev || w.is_floating || !prev.tiled || w.id === prev.id || w.workspace_id !== prev.ws)
            return;
        const ws = (NiriService.allWorkspaces || []).find(x => x.id === w.workspace_id);
        if (!ws || !ws.is_active || ws.output !== screen?.name)
            return;
        popping = true;
        switchShown = true;
        popping = false;
        switchTimer.restart();
    }

    // Hidden, the widget and its padding are fully off screen so only the reveal strip takes the pointer.
    property real slide: shown ? 0 : extent + inset
    property bool popping: false
    Behavior on slide {
        enabled: !dockScope.popping
        NumberAnimation {
            duration: dockScope.shown ? dockScope.slideInMs : dockScope.slideOutMs
            easing.type: Easing.OutCubic
        }
    }

    PanelWindow { // qmllint disable uncreatable-type
        id: hostWindow

        screen: dockScope.screen
        color: "transparent"

        WlrLayershell.layer: dockScope.fullscreenHere ? WlrLayer.Overlay : WlrLayer.Top
        WlrLayershell.namespace: "dms:marina-dock"
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
            top: dockScope.edge === "top" || dockScope.vertical
            bottom: dockScope.edge === "bottom" || dockScope.vertical
            left: dockScope.edge === "left" || !dockScope.vertical
            right: dockScope.edge === "right" || !dockScope.vertical
        }
        margins { // qmllint disable unresolved-type unqualified
            top: dockScope.edge === "top" ? dockScope.edgeZone : 0
            bottom: dockScope.edge === "bottom" ? dockScope.edgeZone : 0
            left: dockScope.edge === "left" ? dockScope.edgeZone : 0
            right: dockScope.edge === "right" ? dockScope.edgeZone : 0
        }
        implicitWidth: dockScope.vertical ? dockScope.extent : 0
        implicitHeight: dockScope.vertical ? 0 : dockScope.extent

        mask: dockScope.shown ? shownRegion : hiddenRegion
        Region {
            id: shownRegion
            item: hitArea
            Region {
                item: revealStrip
            }
        }
        Region {
            id: hiddenRegion
            item: revealStrip
        }

        Item {
            id: revealStrip
            visible: dockScope.autoHide
            x: dockScope.vertical ? (dockScope.edge === "left" ? 0 : hostWindow.width - width) : hitArea.x
            y: dockScope.vertical ? hitArea.y : (dockScope.edge === "top" ? 0 : hostWindow.height - height)
            width: dockScope.vertical ? dockScope.stripPx : hitArea.width
            height: dockScope.vertical ? hitArea.height : dockScope.stripPx

            MouseArea {
                id: stripArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton

                onEntered: {
                    dockScope.stripHover = true;
                    dockWidget.pointerEntered("edge", dockWidget.sceneMainOf(stripArea, mouseX, mouseY));
                }
                onPositionChanged: mouse => dockWidget.pointerMoved("edge", dockWidget.sceneMainOf(stripArea, mouse.x, mouse.y))
                onExited: {
                    dockScope.stripHover = false;
                    dockWidget.pointerLeft("edge");
                }
            }
        }

        Item {
            id: hitArea
            // Reaches the screen edge so a pointer pushed against the edge hits the dock.
            x: dockScope.vertical ? (dockScope.edge === "left" ? 0 : dockWidget.x) : dockWidget.x - dockWidget.tiledOffset
            y: dockScope.vertical ? dockWidget.y - dockWidget.tiledOffset : (dockScope.edge === "top" ? 0 : dockWidget.y)
            width: dockScope.vertical ? (dockScope.edge === "left" ? dockWidget.x + dockWidget.width : hostWindow.width - dockWidget.x) : dockWidget.width + dockWidget.tiledOffset
            height: dockScope.vertical ? dockWidget.height + dockWidget.tiledOffset : (dockScope.edge === "top" ? dockWidget.y + dockWidget.height : hostWindow.height - dockWidget.y)
        }

        MarinaWidget {
            id: dockWidget

            hosted: true
            settings: dockScope.settings
            parentScreen: dockScope.screen
            axis: dockScope.axis
            section: "center"
            barThickness: dockScope.thickness
            barSpacing: 0
            widgetThickness: dockScope.widgetThickness
            barConfig: dockScope.barConfig
            edgeMargin: dockScope.edgeZone
            restIconPx: dockScope.iconPx
            edgeReach: dockScope.offset
            edgeShift: dockScope.slide
            aboveFullscreen: dockScope.fullscreenHere && dockScope.shown
            widgetData: ({
                    "runningAppsCompactMode": true
                })

            x: dockScope.vertical ? (dockScope.edge === "left" ? dockScope.offset - dockScope.inset - dockScope.slide : dockScope.slide - dockScope.inset) : Math.round((hostWindow.width - width) / 2)
            y: dockScope.vertical ? Math.round((hostWindow.height - height) / 2) : (dockScope.edge === "top" ? dockScope.offset - dockScope.inset - dockScope.slide : dockScope.slide - dockScope.inset)
        }
    }

    PanelWindow { // qmllint disable uncreatable-type
        screen: dockScope.screen
        visible: dockScope.settings.reserveSpace && !dockScope.autoHide && !dockScope.barReserves
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "dms:marina-reserve"
        WlrLayershell.exclusiveZone: dockScope.extent
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
            top: dockScope.edge === "top" || dockScope.vertical
            bottom: dockScope.edge === "bottom" || dockScope.vertical
            left: dockScope.edge === "left" || !dockScope.vertical
            right: dockScope.edge === "right" || !dockScope.vertical
        }
        implicitWidth: dockScope.vertical ? 1 : 0
        implicitHeight: dockScope.vertical ? 0 : 1
        mask: Region {}
    }
}
