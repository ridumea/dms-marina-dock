pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Plugins
import qs.Services
import "lib/dragTarget.mjs" as DragTarget
import "lib/geometry.mjs" as Geometry
import "lib/label.mjs" as Label
import "lib/niriPlan.mjs" as NiriPlan
import "lib/placement.mjs" as Placement
import "lib/rowModel.mjs" as RowModel
import "lib/settings.mjs" as Prefs

// Running apps as a magnifying dock.
// Based on DMS Modules/DankBar/Widgets/RunningApps.qml (DMS 1.6.2).
// Magnified icons are drawn in a separate overlay window, since the bar surface is only as thick as the bar.
BasePill {
    id: root

    enableBackgroundHover: false
    enableCursor: false
    section: "left"

    property var widgetData: null
    readonly property bool isAutoHideBar: barConfig?.autoHide ?? false
    readonly property var barWindow: Window.window
    property Item contentRootItem: null

    function captureAnchor() {
        const c = contentRootItem;
        if (!c)
            return;
        const p0 = c.mapToItem(null, 0, 0);
        const start = isVerticalOrientation ? p0.y : p0.x;
        const len = isVerticalOrientation ? c.height : c.width;
        // A side-section widget keeps its outer end when floatSpace changes, so anchor the row there.
        const lead = (floatsInside && section === "left") ? floatSpace : 0;
        anchorScene = barMainInset + (section === "left" ? start - lead : (section === "right" ? start + len : start + len / 2));

        const crossCenter = isVerticalOrientation ? (p0.x + c.width / 2) : (p0.y + c.height / 2);
        const winCross = barWindow ? (isVerticalOrientation ? barWindow.width : barWindow.height) : barThickness;
        // An edge dock may be mid-slide; keep the distance it settles at.
        const offset = edgeIsFar ? (winCross - (crossCenter + iconBase / 2)) : (crossCenter - iconBase / 2);
        measuredEdgeOffset = hosted ? offset + edgeShift : Math.max(0, offset);
    }

    // An edge dock sets settings from the daemon and leaves pluginService unset.
    property string pluginId: ""
    property var pluginService: null
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

    property var settings: Prefs.normalize(pluginData)

    // Runs in a DankBar or hosted in an edge dock; only the one matching the placement setting shows.
    property bool hosted: false
    readonly property bool placementActive: hosted ? settings.placement === "edge" : settings.placement === "bar"
    // Distance from the screen edge to the widget's window: 0 in a bar.
    property real edgeMargin: 0
    property bool aboveFullscreen: false
    // How far the hover area reaches past the widget towards the screen edge (edge dock only).
    property real edgeReach: 0
    property bool edgeHover: false
    // Set by the edge dock; 0 in a bar, where the bar's thickness decides.
    property real restIconPx: 0
    readonly property bool menuOpen: contextMenuLoader.active

    readonly property bool magnifyEnabled: settings.magnifyEnabled
    // Side sections do not magnify: icons would be cut off at the screen edge or cover neighbouring widgets.
    readonly property bool magnifyActive: magnifyEnabled && (hosted || section === "center")
    readonly property int maxIconPx: settings.maxIconPx
    readonly property real radiusItems: settings.radiusItems
    readonly property int animMs: settings.animationMs
    readonly property bool debugLog: settings.debugLog

    readonly property int longPressMs: 350
    readonly property real dragStartPx: 6          // movement before a drag target counts
    readonly property int joinDwellMs: 600         // rest over a single icon to stack onto it
    readonly property real joinDwellStillPx: 4     // movement that restarts that wait
    readonly property int layoutAnimMs: 120
    readonly property int leaveDelayMs: 60         // bar and overlay hand the pointer to each other
    readonly property real insetSnapPx: 12         // hand-off measurement taken as a one-ended inset
    readonly property int labelLingerMs: 150
    readonly property int pendingOrderMs: 1500
    readonly property int assumedFocusMs: 1000
    readonly property int layoutCheckMs: 500

    readonly property real effectiveBarThickness: {
        if (barThickness > 0 && barSpacing > 0) {
            return barThickness + barSpacing;
        }
        return Theme.barThickness(barConfig?.innerPadding ?? 4, CompositorService.getScreenScale(parentScreen)) + (barConfig?.spacing ?? 4);
    }

    readonly property real minTooltipY: {
        if (!parentScreen || !isVerticalOrientation) {
            return 0;
        }
        if (isAutoHideBar) {
            return 0;
        }
        if (parentScreen.y > 0) {
            return effectiveBarThickness;
        }
        return 0;
    }

    readonly property string barEdge: axis?.edge ?? "bottom"
    readonly property int barPosition: Placement.positions[barEdge] ?? Placement.positions.bottom
    readonly property bool edgeIsFar: barEdge === "bottom" || barEdge === "right"
    readonly property real screenMain: parentScreen ? (isVerticalOrientation ? parentScreen.height : parentScreen.width) : 0
    readonly property real screenCross: parentScreen ? (isVerticalOrientation ? parentScreen.width : parentScreen.height) : 0

    property int _desktopEntriesUpdateTrigger: 0
    property int _toplevelsUpdateTrigger: 0
    property int _appIdSubstitutionsTrigger: 0

    // Only compact mode comes from the bar entry; the edge dock passes it as always on.
    readonly property bool _currentWorkspace: settings.currentWorkspace
    readonly property bool _currentMonitor: settings.currentMonitor
    readonly property bool _groupByApp: settings.groupByApp
    readonly property bool compact: widgetData?.runningAppsCompactMode !== undefined ? widgetData.runningAppsCompactMode : SettingsData.runningAppsCompactMode

    readonly property var sortedToplevels: {
        _toplevelsUpdateTrigger;
        let toplevels = CompositorService.sortedToplevels;
        if (!toplevels || toplevels.length === 0)
            return [];
        if (CompositorService.isNiri && NiriService.windows)
            toplevels = RowModel.dropClosed(toplevels, new Set(NiriService.windows.map(w => w.id)));

        const all = toplevels;
        if (_currentWorkspace)
            toplevels = CompositorService.filterCurrentWorkspace(toplevels, parentScreen?.name) || [];
        if (_currentMonitor)
            toplevels = CompositorService.filterCurrentDisplay(toplevels, parentScreen?.name) || [];
        // A window niri is moving with the mouse is on no workspace until the
        // drop; hold it at its last place instead of letting the filters drop it.
        if (CompositorService.isNiri && (_currentWorkspace || _currentMonitor)) {
            const screenName = parentScreen?.name;
            const workspaces = NiriService.allWorkspaces || [];
            const active = workspaces.find(w => w.output === screenName && w.is_active)?.id;
            const onOutput = new Set(workspaces.filter(w => w.output === screenName).map(w => w.id));
            const allowed = ws => (!_currentWorkspace || ws === active) && (!_currentMonitor || onOutput.has(ws));
            toplevels = RowModel.holdMovingWindows(all, toplevels, placeMemory, allowed);
        }
        return toplevels;
    }
    // Updated in place, without notifying, after every model change.
    readonly property var placeMemory: ({})

    Connections {
        target: CompositorService
        function onToplevelsChanged() {
            _toplevelsUpdateTrigger++;
        }
    }

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            _desktopEntriesUpdateTrigger++;
        }
    }

    Connections {
        target: SettingsData
        function onAppIdSubstitutionsChanged() {
            _appIdSubstitutionsTrigger++;
        }
    }

    readonly property var groupedWindows: {
        if (!_groupByApp) {
            return [];
        }
        try {
            if (!sortedToplevels || sortedToplevels.length === 0) {
                return [];
            }
            const appGroups = new Map();
            sortedToplevels.forEach(toplevel => {
                if (!toplevel)
                    return;
                const appId = toplevel?.appId || "unknown";
                if (!appGroups.has(appId)) {
                    appGroups.set(appId, {
                        "appId": appId,
                        "windows": []
                    });
                }
                appGroups.get(appId).windows.push({
                    "toplevel": toplevel
                });
            });
            return Array.from(appGroups.values());
        } catch (e) {
            return [];
        }
    }

    // On niri: floating windows in the user's drag order, a separator, then tiled windows.
    property var floatingOrder: []
    readonly property var separatorEntry: ({
            "dockSeparator": true,
            "niriWindowId": RowModel.separatorId,
            "appId": "",
            "title": ""
        })
    readonly property var arrangedToplevels: {
        const list = sortedToplevels;
        if (!CompositorService.isNiri || !NiriService.windows || list.length === 0)
            return list;
        const floating = new Set();
        for (const w of NiriService.windows)
            if (w.is_floating)
                floating.add(w.id);
        return RowModel.arrange(list, floating, floatingOrder, separatorEntry);
    }
    readonly property var modelValues: _groupByApp ? groupedWindows : arrangedToplevels
    function isSeparatorAt(index) {
        return RowModel.isSeparator(modelValues[index]);
    }
    // On niri, window objects lack `address` and are recreated on every change,
    // so key by niriWindowId to update icons in place.
    readonly property string modelKey: {
        if (_groupByApp)
            return "appId";
        if (CompositorService.isAqueous && AqueousService.available)
            return "aqueousKey";
        if (CompositorService.isNiri)
            return "niriWindowId";
        return CompositorService.isHyprland ? "address" : "";
    }
    readonly property int windowCount: modelValues?.length || 0

    readonly property string focusedAppId: {
        if (!sortedToplevels || sortedToplevels.length === 0)
            return "";
        for (let i = 0; i < sortedToplevels.length; i++) {
            if (sortedToplevels[i].activated)
                return sortedToplevels[i].appId || "";
        }
        return "";
    }

    visible: windowCount > 0 && placementActive

    // Per icon: a "workspace:column" key, a workspace id (null when unknown) and a kind.
    // Not computed in grouped mode, where an icon may span columns.
    readonly property var niriLayout: {
        const niriWindows = NiriService.windows;
        if (!CompositorService.isNiri || _groupByApp || !niriWindows || windowCount === 0)
            return {
                "keys": [],
                "ws": [],
                "kinds": []
            };
        return RowModel.layoutOf(modelValues, niriWindows, placeMemory);
    }
    readonly property var columnKeys: niriLayout.keys
    readonly property var workspaceIds: niriLayout.ws
    readonly property var itemKinds: niriLayout.kinds

    readonly property var stackRuns: NiriPlan.stackRuns(columnKeys, (dragging && dragJoin) ? dragJoinItem : -1)

    // Drag to reorder (niri): the row is laid out in slots, the remaining icons plus
    // one hole that is the dragged icon's home or its target.
    readonly property bool canReorder: CompositorService.isNiri && !_groupByApp

    // A floating window dropped into the row is moved to tiling.
    function canLift(index) {
        return canReorder && index >= 0 && index < windowCount && (!!columnKeys[index] || itemKinds[index] === "float");
    }
    property bool dragging: false
    property int dragIndex: -1
    property real dragPointer: 0
    property int dragSlot: -1      // target as a reduced insertion index, or -1 while none
    property real dragStartPointer: 0
    readonly property bool hasGap: dragging && dragSlot >= 0 && !dragAtHome
    readonly property bool hasHome: dragging && !hasGap
    readonly property int holeSlot: !dragging ? -1 : (hasGap ? dragSlot : dragIndex)
    readonly property int homeSlot: hasHome ? holeSlot : -1
    readonly property int gapSlot: hasGap ? holeSlot : -1
    readonly property int slotCount: windowCount

    property bool dragJoin: false        // the target is inside a column (join it) rather than between columns
    property string dragJoinKey: ""
    property int dragJoinItem: -1
    property bool dragMoved: false
    property bool dragAtHome: true
    property string dragZone: "tile"     // the target is among the columns ("tile") or the floating icons ("float")
    property bool dragOutside: false
    property real dragCross: 0           // the pointer's distance from the screen edge the bar sits on
    readonly property real dragOutsidePx: edgeOffset + iconBase * maxScale + 16
    readonly property real dragEndReachPx: iconBase * maxScale / 2
    // The icon just released appears in its slot at once instead of gliding.
    property int snapIndex: -1
    // If the model changes during a drag every index is stale, so the drag is cancelled.
    property var dragIds: []
    // Joining a single icon needs the pointer to rest over it, so passing over never opens a tray.
    property string dragPendingJoinKey: ""
    property int dragPendingJoinSlot: -1
    property int dragPendingJoinItem: -1
    property real dragPendingJoinPointer: 0
    Timer {
        id: joinDwellTimer
        interval: root.joinDwellMs
        repeat: false
        onTriggered: {
            if (root.dragging && root.dragPendingJoinKey)
                root.setDragTarget(root.dragPendingJoinSlot, true, root.dragPendingJoinKey, root.dragPendingJoinItem);
            root.dragPendingJoinKey = "";
        }
    }

    function setDragTarget(slot, join, key, item, zone) {
        dragSlot = slot;
        dragJoin = join;
        dragJoinKey = join ? key : "";
        dragJoinItem = join ? item : -1;
        dragZone = zone || "tile";
        dragAtHome = false;
    }

    function cancelPendingJoin() {
        joinDwellTimer.stop();
        dragPendingJoinKey = "";
    }

    readonly property var modelIds: modelValues.map(t => t?.niriWindowId)

    // After a drop the row keeps the requested order (window ids) until the model catches up or pendingTimer fires.
    property var pendingIds: []
    readonly property var pendingOrder: RowModel.pendingOrder(modelIds, pendingIds, RowModel.separatorId)
    readonly property int pendingGapSlot: RowModel.pendingGapSlot(modelIds, pendingIds, RowModel.separatorId)
    // Handled here, not on modelValues, so modelIds is current here and in endDrag.
    onModelIdsChanged: {
        if (CompositorService.isNiri && !_groupByApp) {
            const live = new Set();
            const keyById = {};
            for (const w of NiriService.windows || []) {
                live.add(w.id);
                // undefined, not null: a moving window keeps its remembered place.
                keyById[w.id] = RowModel.isMoving(w) ? undefined : RowModel.columnKeyOf(w);
            }
            RowModel.rememberPlaces(placeMemory, sortedToplevels, id => (id in keyById) ? keyById[id] : null, live);
        }
        clearFocusOverrideIfConfirmed();
        if (dragging && !RowModel.sameIds(modelIds, dragIds))
            endDrag(true);
        if (!pendingIds || pendingIds.length === 0)
            return;
        if (RowModel.sameIds(modelIds, pendingIds))
            pendingIds = [];
    }
    Timer {
        id: pendingTimer
        interval: root.pendingOrderMs
        repeat: false
        onTriggered: root.pendingIds = []
    }

    // During a drag the dragged item has no slot (-1), the hole occupies holeSlot and the others fill the rest.
    function slotOf(index) {
        if (dragging) {
            if (index === dragIndex)
                return -1;
            return DragTarget.slotOfReduced(holeSlot, index < dragIndex ? index : index - 1);
        }
        const order = pendingOrder;
        return order ? order.indexOf(index) : index;
    }

    function itemAtSlot(slot) {
        if (dragging)
            return DragTarget.itemAtSlot(windowCount, dragIndex, holeSlot, slot);
        const order = pendingOrder;
        return order ? (order[slot] ?? -1) : slot;
    }

    readonly property string dragIconSource: {
        _desktopEntriesUpdateTrigger;
        _appIdSubstitutionsTrigger;
        const entry = dragging ? entryAt(dragIndex) : null;
        const effectiveAppId = entry ? Paths.moddedAppId(entry.appId || "") : "";
        if (!effectiveAppId)
            return "";
        return Paths.getAppIcon(effectiveAppId, DesktopEntries.heuristicLookup(effectiveAppId));
    }

    // The dragged member has no slot, so trays must not stretch to it.
    function runFirstPlaced(run) {
        let i = run.first;
        while (i <= run.last && slotOf(i) < 0)
            i++;
        return i;
    }

    function runLastPlaced(run) {
        let i = run.last;
        while (i >= run.first && slotOf(i) < 0)
            i--;
        return i;
    }

    // Shared by the bar row and the overlay so both trays match across the crossfade.
    function trayRange(run) {
        const firstPlaced = runFirstPlaced(run);
        const lastPlaced = runLastPlaced(run);
        const includesGap = hasGap && dragJoin && dragJoinKey === columnKeys[run.first];
        const includesHome = hasHome && dragAtHome && dragIndex >= run.first && dragIndex <= run.last;
        const visible = lastPlaced >= firstPlaced && (lastPlaced > firstPlaced || includesGap || includesHome);
        return {
            "visible": visible,
            "includesGap": includesGap,
            "includesHome": includesHome,
            "startSlot": visible ? Math.min(slotOf(firstPlaced), includesGap ? gapSlot : 1e9, includesHome ? homeSlot : 1e9) : 0,
            "endSlot": visible ? Math.max(slotOf(lastPlaced), includesGap ? gapSlot : -1, includesHome ? homeSlot : -1) : 0
        };
    }

    function beginDrag(index, sceneMain) {
        if (!canLift(index))
            return;
        // A previous drop is still waiting for niri, so the column keys would be stale.
        if (pendingIds && pendingIds.length > 0)
            return;
        dragIds = modelIds;
        dragIndex = index;
        dragSlot = -1;
        dragAtHome = true;
        dragZone = itemKinds[index] === "float" ? "float" : "tile";
        dragOutside = false;
        dragStartPointer = sceneMain;
        dragJoin = false;
        dragJoinKey = "";
        dragJoinItem = -1;
        cancelPendingJoin();
        dragMoved = false;
        dragPointer = sceneMain;
        pointerScene = sceneMain;
        dragging = true;
        hideLabel();
    }

    function updateDrag(sceneMain, crossFromEdge) {
        if (!dragging)
            return;
        dragPointer = sceneMain;
        pointerScene = sceneMain;
        dragCross = crossFromEdge;
        const b = sceneMain - baseStartScene;
        dragOutside = DragTarget.isOffDock(b, baseTotal, crossFromEdge, dragOutsidePx, dragEndReachPx);
        const half = Theme.spacingXS / 2;
        // Jitter on a plain click must not count as a move.
        if (Math.abs(sceneMain - dragStartPointer) > dragStartPx || b < -half || b > baseTotal + half || dragOutside)
            dragMoved = true;
        if (!dragMoved)
            return;
        const r = DragTarget.resolve({
            "b": b,
            "n": windowCount,
            "pitch": pitch,
            "spacing": Theme.spacingXS,
            "baseTotal": baseTotal,
            "keys": columnKeys,
            "ws": workspaceIds,
            "kinds": itemKinds,
            "sepCell": liveGapCell,
            "outside": dragOutside,
            "dragIndex": dragIndex,
            "holeSlot": holeSlot,
            "hasGap": hasGap,
            "current": {
                "slot": dragSlot,
                "join": dragJoin,
                "key": dragJoinKey
            }
        });
        if (r.cancelDwell)
            cancelPendingJoin();
        if (r.target) {
            setDragTarget(r.target.slot, r.target.join, r.target.key, r.target.item, r.target.zone);
            if (r.target.atHome)
                dragAtHome = true;
        }
        if (r.dwell) {
            if (dragPendingJoinKey !== r.dwell.key || Math.abs(sceneMain - dragPendingJoinPointer) > joinDwellStillPx) {
                dragPendingJoinKey = r.dwell.key;
                dragPendingJoinPointer = sceneMain;
                joinDwellTimer.restart();
            }
            dragPendingJoinSlot = r.dwell.slot;
            dragPendingJoinItem = r.dwell.item;
        }
    }

    // Stops and returns false when the socket is unavailable.
    function sendActions(actions) {
        for (const a of actions)
            if (!NiriService.send({
                "Action": a
            }))
                return false;
        return true;
    }

    function endDrag(cancel) {
        if (!dragging)
            return;
        const drop = {
            "keys": columnKeys,
            "ws": workspaceIds,
            "kinds": itemKinds,
            "zone": dragZone,
            "sepId": RowModel.separatorId,
            "ids": modelIds,
            "from": dragIndex,
            "slot": dragSlot,
            "join": dragJoin,
            "joinKey": dragJoinKey,
            "moved": dragMoved,
            "atHome": dragAtHome
        };
        const stillSame = RowModel.sameIds(dragIds, drop.ids);
        cancelPendingJoin();
        snapIndex = drop.from;
        Qt.callLater(() => {
            if (snapIndex === drop.from)
                snapIndex = -1;
        });
        dragging = false;
        dragIndex = -1;
        dragSlot = -1;
        dragJoin = false;
        dragJoinKey = "";
        dragJoinItem = -1;
        dragZone = "tile";
        dragOutside = false;
        if (!cancel && stillSame) {
            const plan = NiriPlan.planDrop(drop);
            const sent = plan.actions.length > 0 && sendActions(plan.actions);
            // Floating order is the plugin's own: a reorder among floats applies without niri,
            // a float or tile change only once sent.
            if (plan.floatingOrder && (sent || plan.actions.length <= 1))
                floatingOrder = plan.floatingOrder;
            if (sent) {
                if (plan.order) {
                    pendingIds = plan.order;
                    pendingTimer.restart();
                }
                assumeFocus(drop.ids[drop.from]);
            } else if (plan.actions.length > 0) {
                console.warn("[marina] niri socket unavailable, drop not applied");
            }
            if (debugLog)
                console.info("[marina] drop", JSON.stringify({
                    "from": drop.from,
                    "slot": drop.slot,
                    "join": drop.join,
                    "onto": plan.onto,
                    "above": plan.above,
                    "moved": drop.moved,
                    "atHome": drop.atHome,
                    "zone": drop.zone,
                    "ownEdge": plan.ownEdge,
                    "floatingOrder": plan.floatingOrder,
                    "apps": modelValues.map(t => (t?.appId || "").slice(0, 8)),
                    "keys": drop.keys,
                    "ws": drop.ws,
                    "actions": plan.actions,
                    "sent": sent
                }));
        }
        updateHover();
    }

    // A dropped or clicked window is assumed focused until niri confirms it or the timeout passes.
    property var focusOverrideId: undefined
    Timer {
        id: focusOverrideTimer
        interval: root.assumedFocusMs
        repeat: false
        onTriggered: root.focusOverrideId = undefined
    }
    function assumeFocus(id) {
        if (id === undefined || id === null)
            return;
        focusOverrideId = id;
        focusOverrideTimer.restart();
    }

    // niri reports a window it is moving with the mouse on no workspace.
    readonly property var movingWindowId: {
        if (!CompositorService.isNiri)
            return null;
        const w = (NiriService.windows || []).find(x => x.workspace_id === null || x.workspace_id === undefined);
        return w ? w.id : null;
    }

    readonly property int focusedIndex: {
        const values = modelValues;
        if (!values)
            return -1;
        if (focusOverrideId !== undefined) {
            for (let i = 0; i < values.length; i++)
                if (values[i]?.niriWindowId === focusOverrideId)
                    return i;
        }
        // On niri, follow the focus event: the model only catches up after a sort debounce.
        if (CompositorService.isNiri && !_groupByApp) {
            // A window being moved keeps the marker for the whole move.
            const moving = movingWindowId;
            if (moving !== null) {
                for (let i = 0; i < values.length; i++)
                    if (values[i]?.niriWindowId === moving)
                        return i;
            }
            const focused = NiriService.lastFocusedWindowId;
            if (focused !== null && focused !== undefined) {
                for (let i = 0; i < values.length; i++)
                    if (values[i]?.niriWindowId === focused)
                        return i;
            }
        }
        for (let i = 0; i < values.length; i++) {
            const t = values[i];
            if (_groupByApp ? (t?.appId === focusedAppId && focusedAppId) : t?.activated)
                return i;
        }
        return -1;
    }
    onFocusedAppIdChanged: clearFocusOverrideIfConfirmed()
    function clearFocusOverrideIfConfirmed() {
        if (focusOverrideId === undefined)
            return;
        const values = modelValues;
        for (let i = 0; i < values.length; i++)
            if (values[i]?.niriWindowId === focusOverrideId && values[i]?.activated) {
                focusOverrideId = undefined;
                focusOverrideTimer.stop();
                return;
            }
    }
    readonly property int focusSlot: {
        if (focusedIndex < 0)
            return -1;
        const slot = slotOf(focusedIndex);
        return slot >= 0 ? slot : holeSlot;
    }
    // Not animated, so the marker never trails niri's focus; left unchanged with no
    // focused window so the line fades out in place.
    property real animFocusSlot: 0
    onFocusSlotChanged: {
        if (focusSlot >= 0)
            animFocusSlot = focusSlot;
    }
    Component.onCompleted: {
        if (focusSlot >= 0)
            animFocusSlot = focusSlot;
    }

    function iconMainCenterF(f) {
        const cell = cellAtSlotF(f);
        const size = cell - 6;
        const inset = (compact || isVerticalOrientation) ? (cell - size) / 2 : Theme.spacingXS;
        return slotMainStartF(f) + inset + size / 2;
    }

    // Shared with the stack line so the active line is exactly its segment under the icon;
    // cross-axis values snap to device pixels.
    readonly property real indicatorGap: Theme.snap(2.5, dpr)
    readonly property real indicatorThickness: Theme.snap(3, dpr)
    readonly property real indicatorLength: 10
    readonly property color stackTrayColor: Theme.withAlpha(Theme.surfaceText, 0.14)
    readonly property color stackTrayBorderColor: Theme.withAlpha(Theme.surfaceText, 0.30)
    // Concentric with the widget pill, which the tray sits inset inside.
    readonly property real stackTrayRadius: Math.max(0, Theme.cornerRadius - (widgetThickness - iconCellSize) / 2)
    // Flatter at rest; rounds towards the concentric radius as the icons magnify.
    readonly property real stackTrayRestRadius: Math.max(0, Math.round(Theme.cornerRadius * 0.55))
    function stackTrayRadiusFor(cross) {
        const t = Math.max(0, Math.min(1, (cross - iconCellSize) / iconBase));
        return stackTrayRestRadius + (stackTrayRadius - stackTrayRestRadius) * t;
    }

    function runMaxIconSize(run) {
        let m = 0;
        for (let i = run.first; i <= run.last; i++)
            if (slotOf(i) >= 0)
                m = Math.max(m, iconSizeFor(i));
        return m;
    }

    readonly property real iconBase: restIconPx > 0 ? restIconPx : Theme.barIconSize(barThickness, undefined, barConfig?.maximizeWidgetIcons, barConfig?.iconScale)
    readonly property real iconCellSize: iconBase + 6
    readonly property real baseCell: (isVerticalOrientation || compact) ? iconCellSize : (iconCellSize + Theme.spacingXS + 120)
    readonly property real pitch: baseCell + Theme.spacingXS
    // Gap cell between the floating icons and the tiled dock; never magnifies.
    readonly property real separatorCell: Math.max(0, horizontalPadding * 2 - Theme.spacingXS * 2)
    readonly property int separatorIndex: itemKinds.indexOf("sep")
    readonly property int separatorSlot: separatorIndex < 0 ? -1 : slotOf(separatorIndex)
    // The gap takes no room in the live layout when no floating icon will remain.
    readonly property int floatCount: itemKinds.filter(k => k === "float").length
    readonly property bool gapVanishing: {
        if (separatorIndex < 0)
            return false;
        if (dragging)
            return floatCount - (itemKinds[dragIndex] === "float" ? 1 : 0) + (dragZone === "float" ? 1 : 0) === 0;
        return pendingIds.length > 0 && pendingIds.indexOf(RowModel.separatorId) < 0;
    }
    readonly property real liveGapCell: gapVanishing ? -Theme.spacingXS : separatorCell
    readonly property real baseTotal: Geometry.baseTotal(barProfile)
    readonly property real restBaseTotal: Geometry.baseTotal(restProfile)
    // The widget's bar size counts only the tiled part, so floating icons never push the dock aside;
    // computed from the model so the bar never relays out during a drag.
    readonly property var restProfile: Geometry.makeProfile(windowCount, baseCell, Theme.spacingXS, 1, 0, separatorIndex, separatorCell)
    readonly property real tiledOffset: separatorIndex >= 0 ? Geometry.slotBase(restProfile, separatorIndex + 1) : 0
    readonly property real tiledLength: Math.max(0, restBaseTotal - tiledOffset)
    // In a side section, floating icons drawn outside the pill would be cut off or cover the next widget.
    readonly property bool floatsInside: !hosted && section !== "center"
    // Follows the post-drop row outside a drag, so the bar resizes at the drop;
    // fixed during a drag so the bar does not shift under the pointer.
    readonly property real floatSpace: floatsInside ? (dragging ? tiledOffset : viewTiledOffset) : 0
    readonly property real barTiledLength: (floatsInside && !dragging) ? viewTiledLength : tiledLength
    // With no floating windows yet, a drag towards the floating area opens its slot first,
    // so the pill starts after it.
    readonly property int pillStartSlot: separatorSlot >= 0 ? separatorSlot + 1 : ((hasGap && dragZone === "float") ? gapSlot + 1 : Math.max(0, pendingGapSlot))
    readonly property real maxScale: magnifyActive ? Math.max(1, maxIconPx / iconBase) : 1
    // Icons load at the fully magnified size so magnifying never re-requests them.
    readonly property int iconMaxPx: Math.ceil(iconBase * maxScale * dpr)
    readonly property real radiusPx: Math.max(1, radiusItems) * pitch

    // Main-axis positions are in the overlay's window coordinates, which are the screen's.
    property bool barHover: false
    property bool overlayHover: false
    property bool hoverActive: false
    // Never animated: a running animation makes Qt redraw every window each frame,
    // and a DankBar frame is expensive.
    property real pointerScene: 0
    property real anchorScene: 0

    function sceneMainOf(item, mx, my) {
        const p = item.mapToItem(null, mx, my);
        return isVerticalOrientation ? p.y : p.x;
    }

    // Layer shell does not report a surface's position, so the inset of a bar window shortened
    // by perpendicular bars is measured at the bar-to-overlay hand-off; a value within
    // insetSnapPx of either end snaps to it. Bar coordinates add barMainInset.
    readonly property real barMainSlack: (hosted || !barWindow) ? 0 : Math.max(0, screenMain - (isVerticalOrientation ? barWindow.height : barWindow.width))
    property real measuredMainInset: 0
    readonly property real barMainInset: barMainSlack > 0 ? Math.max(0, Math.min(barMainSlack, measuredMainInset)) : 0
    property real barPointerRaw: NaN
    property double barExitTime: 0

    function calibrateMainInset(overlayMain) {
        if (barMainSlack <= 0 || isNaN(barPointerRaw) || Date.now() - barExitTime > leaveDelayMs)
            return;
        let m = Math.max(0, Math.min(barMainSlack, overlayMain - barPointerRaw));
        if (m <= insetSnapPx)
            m = 0;
        else if (barMainSlack - m <= insetSnapPx)
            m = barMainSlack;
        // The row was anchored with the previous inset.
        const delta = m - barMainInset;
        measuredMainInset = m;
        anchorScene += delta;
    }
    // captureAnchor's measurement wins until the geometry changes; kept separate so restEdgeOffset stays a binding.
    property real measuredEdgeOffset: NaN
    readonly property real restEdgeOffset: isNaN(measuredEdgeOffset) ? (barThickness - iconBase) / 2 : measuredEdgeOffset
    onBarThicknessChanged: measuredEdgeOffset = NaN
    onIconBaseChanged: measuredEdgeOffset = NaN
    // Set by the edge dock while it slides; the magnified row moves with it in the same frame.
    property real edgeShift: 0
    readonly property real edgeOffset: restEdgeOffset - edgeShift

    property real magnifyAmount: 0
    Behavior on magnifyAmount {
        NumberAnimation {
            duration: root.animMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: (root.hoverActive && !root.dragOutside) ? Anims.standardDecel : Anims.standard
        }
    }

    // The bar's pill is swapped with the overlay's, not crossfaded: two translucent copies
    // at partial opacity look lighter than one.
    Binding {
        target: root.visualContent
        property: "opacity"
        value: root.overlayWanted ? (root.barIconsHidden ? 0 : 1) : 1
    }

    // In a side section the pill keeps to the tiled icons at the far end of the widget's space.
    width: isVerticalOrientation ? barThickness : visualWidth + floatSpace
    height: isVerticalOrientation ? visualHeight + floatSpace : barThickness
    Binding {
        target: root.visualContent.anchors
        property: root.isVerticalOrientation ? "verticalCenterOffset" : "horizontalCenterOffset"
        value: root.floatSpace / 2
    }

    // A surface above a fullscreen window keeps the output composited, so the overlay goes
    // away unless the bar or edge dock is itself above fullscreen windows.
    readonly property bool hiddenForFullscreen: !barUsesOverlayLayer && !(hosted && aboveFullscreen) && CompositorService.fullscreenToplevelOnScreen(parentScreen)
    readonly property bool overlayWanted: windowCount > 0 && placementActive && !hiddenForFullscreen
    // The overlay's pointer events stop when it goes away, so its hover and drag end here.
    onOverlayWantedChanged: {
        if (overlayWanted)
            return;
        endDrag(true);
        overlayHover = false;
    }
    // The bar hides its icons slightly after the overlay starts drawing, so both overlap for a few frames.
    readonly property bool overlayDrawing: overlayWanted && (magnifyAmount > 0 || dragging)
    readonly property bool barIconsHidden: overlayWanted && (magnifyAmount > 0.15 || dragging)
    // Room for the label: two rows across, or its width along a vertical bar.
    readonly property real labelSpace: isVerticalOrientation ? 320 : 60
    // From the settled distance, so a sliding edge dock does not resize it.
    readonly property real overlayThickness: Math.ceil(restEdgeOffset + iconBase * maxScale + 12 + labelSpace)

    // The live row is laid out as after the drop, so only icons after an opening slot move
    // and the drop itself moves nothing.
    readonly property real viewTiledOffset: pillStartSlot > 0 ? Geometry.slotBase(barProfile, pillStartSlot) : 0
    readonly property real viewTiledLength: Math.max(0, baseTotal - viewTiledOffset)
    readonly property real baseStartTarget: section === "left" ? anchorScene - (floatsInside ? 0 : viewTiledOffset) : (section === "right" ? anchorScene - baseTotal : anchorScene - viewTiledLength / 2 - viewTiledOffset)
    property real baseStartScene: baseStartTarget
    Behavior on baseStartScene {
        enabled: root.dragging
        NumberAnimation {
            duration: root.layoutAnimMs
            easing.type: Easing.OutCubic
        }
    }

    // The row is laid out so this base point is drawn exactly under the pointer (see rowStartScene).
    readonly property real basePointer: pointerScene - baseStartScene

    // Spacing belongs to the nearest icon, so there is always a hovered icon over the row.
    readonly property int hoveredSlot: (hoverActive && windowCount > 0) ? Geometry.slotAt(profile, basePointer) : -1
    readonly property int hoveredIndex: hoveredSlot < 0 ? -1 : itemAtSlot(hoveredSlot)

    // A drag's open slot is always a fully magnified icon wide; when it moves, the old slot
    // fades out as the new one fades in.
    property int holeFrom: -1
    property int holeTo: -1
    property real holeBlend: 1
    NumberAnimation {
        id: holeBlendAnim
        target: root
        property: "holeBlend"
        from: 0
        to: 1
        duration: root.layoutAnimMs
        easing.type: Easing.OutCubic
    }
    onHoleSlotChanged: {
        holeFrom = holeTo;
        holeTo = holeSlot;
        holeBlendAnim.restart();
    }
    // Empty when there is no hole, so the profile shares geometry's empty list.
    readonly property var fixedSlots: holeTo < 0 && holeFrom < 0 ? [] : [
        {
            "slot": holeTo,
            "weight": holeBlend,
            "full": true
        },
        {
            "slot": holeFrom,
            "weight": 1 - holeBlend,
            "full": true
        }
    ]
    readonly property var profile: Geometry.makeProfile(slotCount, baseCell, Theme.spacingXS, radiusPx, iconBase * (maxScale - 1) * magnifyAmount, separatorSlot, liveGapCell, fixedSlots)
    // The same row fully magnified, for sizing the overlay's input region.
    readonly property var fullProfile: Geometry.makeProfile(slotCount, baseCell, Theme.spacingXS, radiusPx, iconBase * (maxScale - 1), separatorSlot, liveGapCell)

    // Independent of magnification, so the bar's bindings are not re-evaluated on every magnify frame.
    readonly property var barProfile: Geometry.makeProfile(slotCount, baseCell, Theme.spacingXS, 1, 0, separatorSlot, liveGapCell)

    function restSlotStart(slot) {
        return Geometry.slotBase(barProfile, slot);
    }

    function restSlotCell(slot) {
        return Geometry.slotCell(barProfile, slot);
    }

    function growAtSlot(slot, b) {
        return Geometry.growAtSlot(profile, slot, b);
    }

    function slotMainStart(slot) {
        return Geometry.slotStart(profile, rowStartScene, slot, basePointer);
    }

    function slotMainStartF(f) {
        return Geometry.slotStartF(profile, rowStartScene, f, basePointer);
    }

    function cellAtSlotF(f) {
        return Geometry.cellAtSlotF(profile, f, basePointer);
    }

    property real animSlotCount: slotCount
    Behavior on animSlotCount {
        enabled: root.dragging
        NumberAnimation {
            duration: root.layoutAnimMs
            easing.type: Easing.OutCubic
        }
    }

    function growFor(index) {
        const slot = slotOf(index);
        return slot < 0 ? 0 : growAtSlot(slot, basePointer);
    }

    function factorFor(index) {
        return 1 + growFor(index) / iconBase;
    }

    function iconSizeFor(index) {
        return iconBase + growFor(index);
    }

    readonly property real magTotal: Geometry.magTotal(profile, basePointer)
    // Pins the base point under the pointer, so a magnified row expands away from the cursor.
    readonly property real rowStartScene: pointerScene - Geometry.magOffsetAt(profile, basePointer)

    function itemMainStart(index) {
        const slot = slotOf(index);
        return slot < 0 ? rowStartScene : slotMainStart(slot);
    }

    function itemMainCenter(index) {
        return itemMainStart(index) + (baseCell + growFor(index)) / 2;
    }

    // How far the magnified item reaches from the screen edge, past any bar an edge dock sits beyond.
    function crossExtentFor(index) {
        return edgeMargin + Math.max(barThickness + barSpacing, edgeOffset + iconSizeFor(index) + 6);
    }

    Timer {
        id: leaveTimer
        interval: root.leaveDelayMs
        repeat: false
        onTriggered: {
            if (root.barHover || root.overlayHover || root.edgeHover || root.dragging || root.menuOpen)
                return;
            root.hoverActive = false;
            root.magnifyAmount = 0;
        }
    }

    function updateHover() {
        if (barHover || overlayHover || edgeHover || dragging) {
            leaveTimer.stop();
            hoverActive = true;
            magnifyAmount = (dragging && dragOutside) ? 0 : 1;
        } else if (menuOpen && hoverActive) {
            // The menu window takes the pointer; the row stays as it was until the menu closes.
            leaveTimer.stop();
        } else {
            leaveTimer.restart();
        }
    }
    onMenuOpenChanged: updateHover()
    onBarHoverChanged: updateHover()
    onEdgeHoverChanged: updateHover()
    onDragOutsideChanged: {
        if (dragging)
            updateHover();
    }
    onOverlayHoverChanged: {
        updateHover();
        syncBarReveal();
    }

    // The input region covers the row's largest extent, so leaving the row by position ends
    // the hover at once and clears the region before a click can land.
    function setOverlayInside(inside) {
        if (overlayHover === inside)
            return;
        overlayHover = inside;
        if (!inside && !barHover && !edgeHover && !dragging) {
            leaveTimer.stop();
            hoverActive = false;
            magnifyAmount = 0;
        }
    }

    // source is "bar", "overlay" or "edge"; main is the pointer along the main axis in that source's window.
    function pointerEntered(source, main) {
        if (source === "overlay")
            calibrateMainInset(main);
        else
            captureAnchor();
        pointerMoved(source, main);
        if (source === "bar")
            barHover = true;
        else if (source === "edge")
            edgeHover = true;
    }
    function pointerMoved(source, main) {
        if (source === "bar") {
            barPointerRaw = main;
            pointerScene = main + barMainInset;
        } else {
            pointerScene = main;
        }
    }
    // The overlay's leave skips the fast exit: the pointer may be crossing back to the bar.
    function pointerLeft(source) {
        if (source === "bar") {
            barExitTime = Date.now();
            barHover = false;
        } else if (source === "edge") {
            edgeHover = false;
        } else {
            overlayHover = false;
        }
    }

    // An auto-hiding bar would slide away while the overlay has the pointer, so hold it
    // with an IPC reveal; only a reveal Marina set is cleared.
    property string barRevealId: ""
    function syncBarReveal() {
        const id = (!hosted && placementActive && isAutoHideBar) ? (barConfig?.id ?? "") : "";
        if (barRevealId !== "" && (barRevealId !== id || (!hoverActive && !dragging)))
            releaseBarReveal();
        if (id === "" || !(overlayHover || dragging) || SettingsData.isBarIpcRevealed(id))
            return;
        SettingsData.setBarIpcReveal(id, true);
        barRevealId = id;
    }
    function releaseBarReveal() {
        if (barRevealId === "")
            return;
        SettingsData.setBarIpcReveal(barRevealId, false);
        barRevealId = "";
    }
    onDraggingChanged: syncBarReveal()
    onIsAutoHideBarChanged: syncBarReveal()
    onPlacementActiveChanged: syncBarReveal()
    Component.onDestruction: releaseBarReveal()

    onWindowCountChanged: {
        if (windowCount === 0) {
            barHover = false;
            edgeHover = false;
            overlayHover = false;
            hoverActive = false;
            magnifyAmount = 0;
        }
    }

    function entryAt(index) {
        const values = modelValues;
        return (values && index >= 0 && index < values.length) ? values[index] : null;
    }

    function labelTitleFor(index) {
        _desktopEntriesUpdateTrigger;
        _appIdSubstitutionsTrigger;
        const entry = entryAt(index);
        if (!entry)
            return "";
        const appId = entry.appId || "";
        const effectiveAppId = Paths.moddedAppId(appId);
        const desktopEntry = effectiveAppId ? DesktopEntries.heuristicLookup(effectiveAppId) : null;
        return effectiveAppId ? Paths.getAppName(effectiveAppId, desktopEntry) : I18n.trFor("marina", "Unknown");
    }

    // Empty when it would only repeat the app's name; drops the app-name suffix many titles end with.
    function labelDetailFor(index) {
        const entry = entryAt(index);
        if (!entry)
            return "";
        let detail;
        if (_groupByApp) {
            const n = entry.windows?.length || 0;
            detail = n > 1 ? I18n.trFor("marina", "%1 windows").arg(n) : (n > 0 ? (entry.windows[0].toplevel?.title || "") : "");
        } else {
            detail = entry.title || "";
        }
        const name = labelTitleFor(index).trim();
        detail = Label.withoutAppSuffix(detail, name);
        return detail.toLowerCase() === name.toLowerCase() ? "" : detail;
    }

    property int labelIndex: -1
    property bool labelShown: false

    Timer {
        id: labelHideTimer
        interval: root.labelLingerMs
        repeat: false
        onTriggered: root.labelShown = false
    }

    function hideLabel() {
        labelHideTimer.stop();
        labelShown = false;
    }

    onHoveredIndexChanged: {
        if (hoveredIndex >= 0 && !isSeparatorAt(hoveredIndex)) {
            labelHideTimer.stop();
            labelIndex = hoveredIndex;
            labelShown = true;
        } else {
            // Linger so crossing between icons does not blink the label.
            labelHideTimer.restart();
        }
    }
    onHoverActiveChanged: {
        if (!hoverActive)
            hideLabel();
        syncBarReveal();
    }

    property real scrollAccumulator: 0
    property real touchpadThreshold: 500

    // Also called by the overlay, which gets the wheel events while it is up.
    function cycleWindows(deltaY) {
        const isMouseWheel = Math.abs(deltaY) >= 120 && (Math.abs(deltaY) % 120) === 0;

        // Cycles in row order from the focus marker; grouped apps keep DMS's order.
        let windows, currentIndex = -1;
        if (_groupByApp) {
            windows = root.sortedToplevels.filter(w => !w.skipSwitcher);
            currentIndex = windows.findIndex(w => w.activated);
        } else {
            windows = [];
            const values = modelValues || [];
            for (let i = 0; i < values.length; i++) {
                if (isSeparatorAt(i) || values[i]?.skipSwitcher)
                    continue;
                if (i === focusedIndex)
                    currentIndex = windows.length;
                windows.push(values[i]);
            }
        }
        if (windows.length < 2)
            return;

        function cycle(direction) {
            let nextIndex;
            if (direction < 0) {
                nextIndex = currentIndex === -1 ? 0 : Math.min(currentIndex + 1, windows.length - 1);
            } else {
                nextIndex = currentIndex === -1 ? windows.length - 1 : Math.max(currentIndex - 1, 0);
            }
            const nextWindow = windows[nextIndex];
            if (nextWindow)
                CompositorService.activateToplevel(nextWindow);
        }

        if (isMouseWheel) {
            cycle(deltaY);
        } else {
            scrollAccumulator += deltaY;
            if (Math.abs(scrollAccumulator) >= touchpadThreshold) {
                cycle(scrollAccumulator);
                scrollAccumulator = 0;
            }
        }
    }

    onWheel: function (wheelEvent) {
        wheelEvent.accepted = true;
        cycleWindows(wheelEvent.angleDelta.y);
    }

    content: Component {
        Item {
            id: contentRoot
            implicitWidth: root.isVerticalOrientation ? root.barThickness : root.barTiledLength
            implicitHeight: root.isVerticalOrientation ? root.barTiledLength : root.barThickness
            Component.onCompleted: root.contentRootItem = contentRoot
            Component.onDestruction: {
                if (root.contentRootItem === contentRoot)
                    root.contentRootItem = null;
            }

            // Hover owner while the overlay is not up. Delegates only take clicks.
            MouseArea {
                id: trackArea
                z: -1
                readonly property real nearReach: root.edgeIsFar ? 0 : root.edgeReach
                readonly property real floatReach: root.floatsInside ? root.floatSpace : root.tiledOffset
                x: root.isVerticalOrientation ? -root.leftMargin - nearReach : -floatReach
                y: root.isVerticalOrientation ? -floatReach : -root.topMargin - nearReach
                width: parent.width + (root.isVerticalOrientation ? root.leftMargin + root.rightMargin + root.edgeReach : floatReach)
                height: parent.height + (root.isVerticalOrientation ? floatReach : root.topMargin + root.bottomMargin + root.edgeReach)
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                cursorShape: (root.hoveredIndex >= 0 && !root.isSeparatorAt(root.hoveredIndex)) ? Qt.PointingHandCursor : Qt.ArrowCursor

                onEntered: root.pointerEntered("bar", root.sceneMainOf(trackArea, mouseX, mouseY))
                onPositionChanged: mouse => root.pointerMoved("bar", root.sceneMainOf(trackArea, mouse.x, mouse.y))
                onExited: root.pointerLeft("bar")
            }

            // Positioned by slot, not a Row, so the bar and the overlay share one geometry.
            Repeater {
                model: ScriptModel {
                    values: root.modelValues
                    objectProp: root.modelKey
                }
                delegate: MarinaDelegate {
                    dock: root
                    inOverlay: false
                }
            }

            Rectangle {
                readonly property bool active: root.focusSlot >= 0
                readonly property real iconInset: (root.compact || root.isVerticalOrientation) ? (root.baseCell - root.iconBase) / 2 : Theme.spacingXS
                readonly property real center: Geometry.slotBaseF(root.barProfile, root.animFocusSlot) - root.viewTiledOffset + iconInset + root.iconBase / 2
                readonly property real iconFar: (root.barThickness + root.iconBase) / 2
                readonly property real crossPos: Theme.snap(root.edgeIsFar ? (iconFar + root.indicatorGap) : (root.barThickness - iconFar - root.indicatorGap - root.indicatorThickness), root.dpr)
                visible: active
                width: root.isVerticalOrientation ? root.indicatorThickness : root.indicatorLength
                height: root.isVerticalOrientation ? root.indicatorLength : root.indicatorThickness
                radius: root.indicatorThickness / 2
                color: Theme.primary
                x: root.isVerticalOrientation ? crossPos : center - width / 2
                y: root.isVerticalOrientation ? center - height / 2 : crossPos
                z: 2
            }

            Repeater {
                model: root.stackRuns
                Rectangle {
                    required property var modelData
                    readonly property var range: root.trayRange(modelData)
                    visible: range.visible
                    readonly property int startSlot: range.startSlot
                    readonly property int endSlot: range.endSlot
                    readonly property real mainStart: visible ? root.restSlotStart(startSlot) - root.viewTiledOffset : 0
                    readonly property real mainEnd: visible ? root.restSlotStart(endSlot) + root.restSlotCell(endSlot) - root.viewTiledOffset : 0
                    readonly property real crossPos: (root.barThickness - root.iconCellSize) / 2
                    x: root.isVerticalOrientation ? crossPos : mainStart
                    y: root.isVerticalOrientation ? mainStart : crossPos
                    width: root.isVerticalOrientation ? root.iconCellSize : (mainEnd - mainStart)
                    height: root.isVerticalOrientation ? (mainEnd - mainStart) : root.iconCellSize
                    radius: root.stackTrayRestRadius
                    color: root.stackTrayColor
                    border.width: 1
                    border.color: root.stackTrayBorderColor
                    z: -1
                }
            }
        }
    }

    Loader {
        id: overlayLoader
        active: root.overlayWanted && root.parentScreen !== null
        sourceComponent: MarinaOverlay {
            dock: root
        }
    }

    Loader {
        active: root.debugLog
        sourceComponent: MarinaLayoutCheck {
            dock: root
            rows: overlayLoader.item?.rows ?? null
        }
    }

    Loader {
        active: root.dragging && root.overlayWanted && root.parentScreen !== null
        sourceComponent: MarinaDragGhost {
            dock: root
        }
    }

    Loader {
        id: contextMenuLoader
        active: false
        sourceComponent: MarinaContextMenu {
            targetScreen: root.parentScreen
            onDismissed: contextMenuLoader.active = false
        }
    }

    function openContextMenu(index, toplevel) {
        hideLabel();
        contextMenuLoader.active = true;
        const menu = contextMenuLoader.item;
        if (!menu)
            return;
        menu.currentWindow = toplevel;
        menu.triggerBarConfig = barConfig;
        menu.triggerBarPosition = barPosition;
        menu.triggerBarThickness = barThickness;
        menu.triggerBarSpacing = barSpacing;
        const mainCenter = itemMainCenter(index);
        const extent = crossExtentFor(index);
        if (isVerticalOrientation) {
            const xPos = barEdge === "left" ? (extent + Theme.spacingXS) : (screenCross - extent - Theme.spacingXS);
            menu.showAt(xPos, mainCenter + minTooltipY, true, barEdge);
        } else {
            const yPos = barEdge === "bottom" ? (screenCross - extent - menu.menuHeight - Theme.spacingXS) : (extent + Theme.spacingXS);
            menu.showAt(mainCenter, yPos, false, barEdge);
        }
    }
}
