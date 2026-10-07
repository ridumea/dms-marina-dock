import { makeProfile, slotAt, slotSpan } from "./geometry.mjs";
import { inStack, sameWorkspace } from "./niriPlan.mjs";

// Drop targeting while an icon is lifted; all positions are in resting-row pixels.
// A column's outer bands are insert targets beside it and each tile's halves are join targets.
// Every target is in zone "float" (left of the gap) or "tile" (niri's columns).

export const insertBandSingle = 0.3;
export const insertBandStack = 0.15;

// Whether a lifted icon is off the dock; b is the pointer in resting-row coordinates.
export function isOffDock(b, baseTotal, crossFromEdge, crossLimit, endMargin) {
    return crossFromEdge > crossLimit || b < -endMargin || b > baseTotal + endMargin;
}

// Icon shown in `slot` during a drag, or -1 for the hole.
export function itemAtSlot(n, dragIndex, holeSlot, slot) {
    if (slot === holeSlot)
        return -1;
    const r = slot - (slot > holeSlot ? 1 : 0);
    if (r < 0 || r >= n - 1)
        return -1;
    return r < dragIndex ? r : r + 1;
}

export function slotOfReduced(holeSlot, r) {
    return r + (r >= holeSlot ? 1 : 0);
}

// Floating icons have no column, so they are never targets.
function isTarget(s, i) {
    return !!s.keys[i] && sameWorkspace(s.ws, i, s.dragIndex);
}

// Reduced-index range of the other tiled icons on the dragged window's workspace.
function targetRange(s) {
    let first = -1;
    let last = -1;
    for (let i = 0; i < s.n; i++) {
        if (i === s.dragIndex || !isTarget(s, i))
            continue;
        const r = i < s.dragIndex ? i : i - 1;
        if (first < 0)
            first = r;
        last = r;
    }
    return first < 0 ? null : {
        "first": first,
        "last": last
    };
}

function home(dragIndex, zone) {
    return {
        "cancelDwell": true,
        "target": {
            "slot": dragIndex,
            "join": false,
            "key": "",
            "item": -1,
            "atHome": true,
            "zone": zone
        }
    };
}

function insert(slot, atHome, zone) {
    return {
        "cancelDwell": true,
        "target": {
            "slot": slot,
            "join": false,
            "key": "",
            "item": -1,
            "atHome": atHome,
            "zone": zone || "tile"
        }
    };
}

const unchanged = {
    "cancelDwell": false
};

// s: { b (pointer in resting-row coordinates), n, pitch, spacing, baseTotal, keys, ws,
//   dragIndex, holeSlot, hasGap, kinds ("tile" | "float" | "sep" | "other"), sepCell?,
//   outside, current: { slot, join, key } }
// Returns { cancelDwell, target?, dwell? }; a dwell is a join applied after the pointer rests.
export function resolve(s) {
    const half = s.spacing / 2;
    const n = s.n;
    const own = inStack(s.keys, s.dragIndex);
    const floatDrag = s.kinds[s.dragIndex] === "float";
    const ownZone = floatDrag ? "float" : "tile";
    // The dragged icon's own index is its home only in its own zone.
    const homeSlot = slot => slot === s.dragIndex && !own && !floatDrag;
    const floatHome = slot => slot === s.dragIndex && floatDrag;
    let sepFull = -1;
    for (let i = 0; i < n; i++)
        if (s.kinds[i] === "sep")
            sepFull = i;
    const endSlot = n - 1;   // insertion index after the last icon
    // Inserting at the gap's reduced index puts an icon last in the floating zone.
    const sepR = sepFull < 0 ? -1 : (sepFull < s.dragIndex ? sepFull : sepFull - 1);

    // A floating window with no column to join is still tiled.
    const tiledStart = afterGap => {
        const range = targetRange(s);
        if (range)
            return insert(range.first, homeSlot(range.first), "tile");
        return floatDrag ? insert(afterGap, false, "tile") : home(s.dragIndex, ownZone);
    };

    // Off the dock, a tiled window is floated next to the dock and a floating one stays put.
    if (s.outside)
        return floatDrag ? home(s.dragIndex, ownZone) : insert(sepR >= 0 ? sepR : 0, false, "float");

    // Past the start: the floating zone's start if any; otherwise a new first or last column.
    if (s.b < -half || s.b > s.baseTotal + half) {
        if (s.b < -half && sepFull >= 0)
            return insert(0, floatHome(0), "float");
        const range = targetRange(s);
        if (!range)
            return floatDrag ? insert(endSlot, false, "tile") : home(s.dragIndex, ownZone);
        const slot = s.b < -half ? range.first : range.last + 1;
        return insert(slot, homeSlot(slot), "tile");
    }

    // The gap's slot is wherever the hole has pushed it.
    const sepSlot = sepFull < 0 ? -1 : slotOfReduced(s.holeSlot, sepR);
    const rest = makeProfile(n, s.pitch - s.spacing, s.spacing, 1, 0, s.sepCell !== undefined ? sepSlot : -1, s.sepCell);
    const p = Math.max(0, slotAt(rest, s.b));
    const span = slotSpan(rest, p);
    if (p === s.holeSlot)
        return s.hasGap ? {
            "cancelDwell": true
        } : home(s.dragIndex, ownZone);

    const item = itemAtSlot(n, s.dragIndex, s.holeSlot, p);
    if (item < 0)
        return unchanged;
    const kind = s.kinds[item];
    const ri = item < s.dragIndex ? item : item - 1;
    const ui = s.b - span.start;
    // The gap's first half ends the floating zone and its second half starts the columns.
    if (kind === "sep") {
        if (ui < span.length / 2)
            return insert(ri, floatHome(ri), "float");
        return tiledStart(ri + 1);
    }
    if (kind === "float") {
        const slot = ui < span.length / 2 ? ri : ri + 1;
        return insert(slot, floatHome(slot), "float");
    }
    if (!isTarget(s, item))
        return home(s.dragIndex, ownZone);

    const keyAt = r => s.keys[r < s.dragIndex ? r : r + 1];
    const r = item < s.dragIndex ? item : item - 1;
    const key = keyAt(r);
    let rf = r;
    let rl = r;
    if (key) {
        while (rf > 0 && keyAt(rf - 1) === key)
            rf--;
        while (rl < n - 2 && keyAt(rl + 1) === key)
            rl++;
    }
    const u = ui;
    const isStack = rl > rf;
    const band = isStack ? insertBandStack : insertBandSingle;
    const joiningThis = s.current.join && s.current.key === key;

    // Crossing an outer band on the way into a join slot at that end must not cancel the join.
    if (p === slotOfReduced(s.holeSlot, rf) && u < span.length * band) {
        if (joiningThis && s.current.slot === rf)
            return unchanged;
        return insert(rf, homeSlot(rf), "tile");
    }
    if (p === slotOfReduced(s.holeSlot, rl) && u > span.length * (1 - band)) {
        if (joiningThis && s.current.slot === rl + 1)
            return unchanged;
        return insert(rl + 1, homeSlot(rl + 1), "tile");
    }
    if (!key)
        return unchanged;

    const k = u < span.length / 2 ? r : r + 1;
    if (isStack || joiningThis)
        return {
            "cancelDwell": true,
            "target": {
                "slot": k,
                "join": true,
                "key": key,
                "item": item,
                "atHome": false,
                "zone": "tile"
            }
        };
    return {
        "cancelDwell": false,
        "dwell": {
            "key": key,
            "slot": k,
            "item": item
        }
    };
}
