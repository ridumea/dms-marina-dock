import { test } from "node:test";
import assert from "node:assert/strict";
import { isOffDock, itemAtSlot, resolve, slotOfReduced } from "../lib/dragTarget.mjs";

// Resting geometry from the reference setup: 22 px cells, 4 px gaps.
const baseCell = 22;
const spacing = 4;
const pitch = baseCell + spacing;
const none = { slot: -1, join: false, key: "" };

function state(keys, ws, dragIndex, b, extra = {}) {
    const n = keys.length;
    return {
        b, n, pitch, spacing,
        baseTotal: n * baseCell + (n - 1) * spacing,
        keys, ws, dragIndex,
        kinds: keys.map(k => k ? "tile" : "other"),
        holeSlot: dragIndex,
        hasGap: false,
        current: none,
        ...extra
    };
}
// Base coordinate at fraction f across slot s.
const at = (s, f) => s * pitch + f * pitch - spacing / 2;

test("itemAtSlot skips the hole and the dragged icon", () => {
    assert.equal(itemAtSlot(4, 1, 1, 1), -1);
    assert.equal(itemAtSlot(4, 1, 1, 0), 0);
    assert.equal(itemAtSlot(4, 1, 1, 2), 2);
    assert.equal(itemAtSlot(4, 1, 3, 1), 2);
});

test("slotOfReduced steps over the hole and inverts itemAtSlot", () => {
    assert.equal(slotOfReduced(2, 0), 0);
    assert.equal(slotOfReduced(2, 1), 1);
    assert.equal(slotOfReduced(2, 2), 3);
    assert.equal(slotOfReduced(0, 0), 1);
    for (let hole = 0; hole < 4; hole++) {
        for (let slot = 0; slot < 4; slot++) {
            const i = itemAtSlot(4, 1, hole, slot);
            if (i < 0)
                continue;
            const r = i < 1 ? i : i - 1;
            assert.equal(slotOfReduced(hole, r), slot);
        }
    }
});

test("over its own reserved spot the target goes home", () => {
    const r = resolve(state(["1:1", "1:2", "1:3"], [1, 1, 1], 1, at(1, 0.5)));
    assert.equal(r.target.atHome, true);
    assert.equal(r.target.slot, 1);
});

test("over the open gap the target is kept", () => {
    const r = resolve(state(["1:1", "1:2", "1:3"], [1, 1, 1], 0, at(2, 0.5), { holeSlot: 2, hasGap: true }));
    assert.equal(r.target, undefined);
    assert.equal(r.cancelDwell, true);
});

test("outer band of a single icon opens an insert slot beside it", () => {
    const keys = ["1:1", "1:2", "1:3"];
    const r = resolve(state(keys, [1, 1, 1], 0, at(2, 0.9)));
    assert.deepEqual(r.target, { slot: 2, join: false, key: "", item: -1, atHome: false, zone: "tile" });
});

test("centre of a single icon asks for a dwell before joining", () => {
    const keys = ["1:1", "1:2", "1:3"];
    const r = resolve(state(keys, [1, 1, 1], 0, at(2, 0.6)));
    assert.equal(r.target, undefined);
    assert.deepEqual(r.dwell, { key: "1:3", slot: 2, item: 2 });
});

test("a stack accepts a join at once, above or below the tile", () => {
    const keys = ["1:1", "1:2", "1:2", "1:2"];
    const ws = [1, 1, 1, 1];
    assert.deepEqual(resolve(state(keys, ws, 0, at(2, 0.3))).target, { slot: 1, join: true, key: "1:2", item: 2, atHome: false, zone: "tile" });
    assert.deepEqual(resolve(state(keys, ws, 0, at(2, 0.7))).target, { slot: 2, join: true, key: "1:2", item: 2, atHome: false, zone: "tile" });
});

test("narrow bands on a stack's end tiles insert beside the stack", () => {
    const keys = ["1:1", "1:2", "1:2"];
    const r = resolve(state(keys, [1, 1, 1], 0, at(2, 0.95)));
    assert.deepEqual(r.target, { slot: 2, join: false, key: "", item: -1, atHome: false, zone: "tile" });
});

test("crossing the band into an existing join at that end keeps the join", () => {
    const keys = ["1:1", "1:2", "1:2"];
    const current = { slot: 2, join: true, key: "1:2" };
    const r = resolve(state(keys, [1, 1, 1], 0, at(2, 0.95), { current }));
    assert.equal(r.target, undefined);
    assert.equal(r.cancelDwell, false);
});

test("icons on another workspace are not targets", () => {
    const keys = ["1:1", "1:2", "2:1", "2:2"];
    const ws = [1, 1, 2, 2];
    for (const f of [0.1, 0.5, 0.9]) {
        const r = resolve(state(keys, ws, 0, at(2, f)));
        assert.equal(r.target.atHome, true, "fraction " + f);
    }
});

test("past the row's ends the slot opens at the ends of the dragged window's workspace", () => {
    const keys = ["1:1", "1:2", "1:3", "2:1"];
    const ws = [1, 1, 1, 2];
    const s = state(keys, ws, 1, 0);
    assert.deepEqual(resolve({ ...s, b: -20 }).target, { slot: 0, join: false, key: "", item: -1, atHome: false, zone: "tile" });
    assert.deepEqual(resolve({ ...s, b: s.baseTotal + 20 }).target, { slot: 2, join: false, key: "", item: -1, atHome: false, zone: "tile" });
});

test("alone on its workspace a window has nowhere to go", () => {
    const r = resolve(state(["1:1", "2:1"], [1, 2], 0, -20));
    assert.equal(r.target.atHome, true);
});

// ---- floating zone ----
// Two floating windows, the gap, three tiled columns.
const fKeys = [null, null, null, "1:1", "1:2", "1:3"];
const fWs = [1, 1, null, 1, 1, 1];
const fKinds = ["float", "float", "sep", "tile", "tile", "tile"];
const fState = (dragIndex, b, extra = {}) => state(fKeys, fWs, dragIndex, b, { kinds: fKinds, ...extra });
const T = (slot, zone, atHome = false) => ({ slot, join: false, key: "", item: -1, atHome, zone });

test("a floating icon moved among the floating icons only reorders them", () => {
    assert.deepEqual(resolve(fState(0, at(1, 0.7))).target, T(1, "float"));
    assert.deepEqual(resolve(fState(0, at(1, 0.2))).target, T(0, "float", true));
});

test("a floating icon over a column targets the columns, never its own spot", () => {
    assert.deepEqual(resolve(fState(0, at(5, 0.9))).target, T(5, "tile"));
    assert.deepEqual(resolve(fState(0, at(3, 0.1))).target, T(2, "tile"));
});

test("the gap's halves end the floating icons and start the columns", () => {
    assert.deepEqual(resolve(fState(5, at(2, 0.3))).target, T(2, "float"));
    assert.deepEqual(resolve(fState(5, at(2, 0.8))).target, T(3, "tile"));
});

test("a tiled icon over a floating icon targets the floating zone", () => {
    assert.deepEqual(resolve(fState(5, at(0, 0.3))).target, T(0, "float"));
});

test("off the dock a tiled icon lands last among the floating icons, next to the dock", () => {
    assert.deepEqual(resolve(fState(4, at(4, 0.5), { outside: true })).target, T(2, "float"));
    assert.equal(resolve(fState(0, at(4, 0.5), { outside: true })).target.atHome, true);
});

test("off the dock with no floating windows the slot opens at the start", () => {
    const r = resolve(state(["1:1", "1:2"], [1, 1], 1, at(1, 0.5), { outside: true }));
    assert.deepEqual(r.target, T(0, "float"));
});

test("past the start with floating icons the slot opens before the first of them", () => {
    assert.deepEqual(resolve(fState(5, -20)).target, T(0, "float"));
    assert.equal(resolve(fState(0, -20)).target.atHome, true);
});

test("a floating icon is never a join target", () => {
    const r = resolve(fState(4, at(1, 0.4)));
    assert.equal(r.dwell, undefined);
    assert.deepEqual(r.target, T(1, "float"));
});

test("a floating source dropped past the end or in a band is never at home", () => {
    // Slot 5 is the last floating icon's own index, but among the columns.
    const past = fState(1, 0);
    assert.deepEqual(resolve({ ...past, b: past.baseTotal + 20 }).target, T(5, "tile"));
    assert.deepEqual(resolve(fState(1, at(5, 0.85))).target, T(5, "tile"));   // outer-right band of the last column
    // The same slot for the last tiled icon is its reserved spot.
    const tiled = fState(5, 0);
    assert.equal(resolve({ ...tiled, b: tiled.baseTotal + 20 }).target.atHome, true);
});

test("past the end the slot opens after the last column", () => {
    const s = fState(3, 0);
    assert.deepEqual(resolve({ ...s, b: s.baseTotal + 20 }).target, T(5, "tile"));
});

test("with a narrow gap, its halves and the icons around it map by their real spans", () => {
    // Gap cell 8 px (span 12 px) at slot 2; icons 22 px (span 26 px).
    const s = (dragIndex, b) => ({ ...fState(dragIndex, b), sepCell: 8, baseTotal: 6 * 22 + 5 * 4 - 14 });
    const gapStart = 2 * pitch - spacing / 2;          // 50..62
    assert.deepEqual(resolve(s(5, gapStart + 3)).target, T(2, "float"));
    assert.deepEqual(resolve(s(5, gapStart + 9)).target, T(3, "tile"));
    assert.deepEqual(resolve(s(5, 40)).target, T(2, "float"));      // second floating icon, second half
    assert.deepEqual(resolve(s(5, 30)).target, T(1, "float"));      // its first half
    assert.deepEqual(resolve(s(5, gapStart + 12 + 5)).target, T(3, "tile"));   // first column's leading band
});

test("with a zero-length gap, the last floating icon and the first column split the boundary", () => {
    // Floating icons 0..1, gap 2 with no length, columns from slot 3 at the normal pitch.
    const s = (dragIndex, b) => ({ ...fState(dragIndex, b), sepCell: -spacing, baseTotal: 5 * 22 + 4 * 4 });
    const boundary = 2 * pitch - spacing / 2;          // 50: end of floating icon 1, start of the first column
    assert.deepEqual(resolve(s(5, boundary - 3)).target, T(2, "float"));   // floating icon's second half
    assert.deepEqual(resolve(s(5, boundary + 3)).target, T(3, "tile"));    // first column's leading band
});

test("the dock is an area: beside it, even low on the screen, is off the dock", () => {
    // Row 300 px long, 92 px tall region, 32 px of reach past each end.
    const off = (b, cross) => isOffDock(b, 300, cross, 92, 32);
    assert.equal(off(150, 20), false);
    assert.equal(off(150, 120), true);
    assert.equal(off(-20, 20), false);
    assert.equal(off(320, 20), false);
    assert.equal(off(-40, 5), true);
    assert.equal(off(400, 5), true);
});
