import { test } from "node:test";
import assert from "node:assert/strict";
import * as G from "../lib/geometry.mjs";

// Reference setup: 16 px icons in 22 px cells, 4 px gaps, 64 px maximum,
// radius 3 icons.
const iconBase = 16;
const maxGrow = 64 - iconBase;
const pitch = 26;
const make = (n, radiusItems, grow = maxGrow) => G.makeProfile(n, 22, 4, radiusItems * pitch, grow);
const profile = make(7, 3);
const rest = make(7, 3, 0);
const eps = 1e-9;

function sweep(p, fn, lo = -3, hi = G.baseTotal(p) + 3, step = 0.25) {
    for (let b = lo; b <= hi; b += step)
        fn(b);
}

// Ends of the magnified row relative to the resting row's ends, with the row
// placed so that base point b is drawn under the pointer.
function ends(p, b) {
    const rowStart = b - G.magOffsetAt(p, b);
    return [rowStart, rowStart + G.magTotal(p, b) - G.baseTotal(p)];
}

test("at rest the row is drawn at its resting geometry", () => {
    sweep(rest, b => assert.ok(Math.abs(G.magOffsetAt(rest, b) - b) < eps));
    assert.equal(G.magTotal(rest, 40), G.baseTotal(rest));
});

test("over the row the drawn position moves forward with the pointer", () => {
    let prev = -Infinity;
    sweep(profile, b => {
        const x = G.magOffsetAt(profile, b);
        assert.ok(x > prev, "b=" + b);
        prev = x;
    }, -2, G.baseTotal(profile) + 2);
});

test("the drawn row never jumps as the pointer moves", () => {
    let prev = null;
    sweep(profile, b => {
        const e = ends(profile, b);
        if (prev !== null)
            assert.ok(Math.abs(e[0] - prev[0]) < 1 && Math.abs(e[1] - prev[1]) < 1, "b=" + b);
        prev = e;
    }, -20, G.baseTotal(profile) + 20);
});

test("past an end the row's end stays at its resting position", () => {
    const total = G.baseTotal(profile);
    for (const b of [total + 3, total + 10, total + 40])
        assert.ok(Math.abs(ends(profile, b)[1]) < 1e-9, "b=" + b);
    for (const b of [-3, -10, -40])
        assert.ok(Math.abs(ends(profile, b)[0]) < 1e-9, "b=" + b);
});

test("the row's ends stay fixed while the whole bell lies inside the row", () => {
    // A long row of 23 icons; the bell spans 3 icons each side.
    const p = make(23, 3);
    const [l0, r0] = ends(p, 11 * pitch);
    assert.ok(l0 < -40 && r0 > 40);
    sweep(p, b => {
        const [l, r] = ends(p, b);
        assert.ok(Math.abs(l - l0) < 1e-6 && Math.abs(r - r0) < 1e-6, "b=" + b);
    }, 3.5 * pitch, 19.5 * pitch);
});

test("near an end only that end moves", () => {
    const p = make(23, 3);
    const [lMid, rMid] = ends(p, 11 * pitch);
    const [l, r] = ends(p, 22 * pitch + 11);
    assert.ok(Math.abs(l - lMid) < 1e-6);
    assert.ok(r < rMid - 10);
});

test("the ends of the row and the slots agree", () => {
    sweep(profile, b => {
        const last = profile.n - 1;
        const end = G.slotStart(profile, 0, last, b) + G.cellAtSlot(profile, last, b);
        assert.ok(Math.abs(end - G.magTotal(profile, b)) < 1e-6, "b=" + b);
        let x = 0;
        for (let s = 0; s < profile.n; s++) {
            assert.ok(Math.abs(G.slotStart(profile, 0, s, b) - x) < 1e-6, "b=" + b + " slot=" + s);
            x += G.cellAtSlot(profile, s, b) + profile.spacing;
        }
    });
});

test("the hovered cell contains the pointer and is the largest", () => {
    sweep(profile, b => {
        const slot = G.slotAt(profile, b);
        if (slot < 0)
            return;
        // The pointer sits at 0; the row is placed so base point b is under it.
        const rowStart = -G.magOffsetAt(profile, b);
        const start = G.slotStart(profile, rowStart, slot, b);
        const cell = G.cellAtSlot(profile, slot, b);
        const slack = profile.spacing / 2 + eps;
        assert.ok(start - slack <= 0 && 0 <= start + cell + slack, "b=" + b);
        for (let s = 0; s < profile.n; s++)
            assert.ok(G.cellAtSlot(profile, s, b) <= cell + eps, "b=" + b + " slot=" + s);
    });
});

test("the icon under the pointer reaches the maximum size at its centre", () => {
    const b = 3 * pitch + 11;
    assert.ok(Math.abs(iconBase + G.growAtSlot(profile, 3, b) - 64) < 1e-9);
});

test("immediate neighbours reach about 80% of the hovered size", () => {
    const b = 3 * pitch + 11;
    const ratio = (iconBase + G.growAtSlot(profile, 4, b)) / (iconBase + G.growAtSlot(profile, 3, b));
    assert.ok(ratio > 0.75 && ratio < 0.9, "ratio " + ratio);
});

test("fractional slots interpolate between neighbours", () => {
    const b = 50;
    const a = G.slotStart(profile, 0, 2, b);
    const c = G.slotStart(profile, 0, 3, b);
    assert.ok(Math.abs(G.slotStartF(profile, 0, 2.5, b) - (a + c) / 2) < eps);
    assert.equal(G.slotStartF(profile, 0, 2, b), a);
});

test("fractional resting starts and cells interpolate between neighbours", () => {
    const b = 50;
    assert.equal(G.slotBaseF(profile, 2), G.slotBase(profile, 2));
    assert.ok(Math.abs(G.slotBaseF(profile, 2.5) - (G.slotBase(profile, 2) + G.slotBase(profile, 3)) / 2) < eps);
    const a = G.cellAtSlot(profile, 1, b);
    const c = G.cellAtSlot(profile, 2, b);
    assert.equal(G.cellAtSlotF(profile, 1, b), a);
    assert.ok(Math.abs(G.cellAtSlotF(profile, 1.25, b) - (0.75 * a + 0.25 * c)) < eps);
});

test("slotAt gives gaps to the nearest cell and -1 past the ends", () => {
    assert.equal(G.slotAt(profile, -3), -1);
    assert.equal(G.slotAt(profile, 0), 0);
    assert.equal(G.slotAt(profile, 23), 0);
    assert.equal(G.slotAt(profile, 25), 1);
    assert.equal(G.slotAt(profile, G.baseTotal(profile) + 3), -1);
});

test("sideGrowMax bounds the growth on either side of the pointer", () => {
    const max = G.sideGrowMax(profile);
    sweep(profile, b => {
        const [l, r] = ends(profile, b);
        assert.ok(-l <= max + eps && r <= max + eps, "b=" + b);
    });
});

// ---- a narrow slot (the separator) ----
const withSep = (grow = maxGrow) => G.makeProfile(9, 22, 4, 3 * pitch, grow, 6, 8);

test("the narrow slot is shorter at rest and the row with it", () => {
    const p = withSep(0);
    assert.equal(G.slotCell(p, 6), 8);
    assert.equal(G.slotBase(p, 7) - G.slotBase(p, 6), 12);
    assert.equal(G.baseTotal(p), 9 * 22 + 8 * 4 - 14);
});

test("the narrow slot never grows, whatever the pointer's position", () => {
    const p = withSep();
    sweep(p, b => assert.ok(Math.abs(G.growAtSlot(p, 6, b)) < 1e-9, "b=" + b));
});

test("with a narrow slot, slots and the row's total still agree", () => {
    const p = withSep();
    sweep(p, b => {
        let x = 0;
        for (let s = 0; s < p.n; s++) {
            assert.ok(Math.abs(G.slotStart(p, 0, s, b) - x) < 1e-6, "b=" + b + " slot=" + s);
            x += G.cellAtSlot(p, s, b) + p.spacing;
        }
        assert.ok(Math.abs(x - p.spacing - G.magTotal(p, b)) < 1e-6, "b=" + b);
    });
});

test("with a narrow slot, the pointer maps to the slot it is over", () => {
    const p = withSep(0);
    for (let s = 0; s < p.n; s++) {
        const mid = G.slotBase(p, s) + G.slotCell(p, s) / 2;
        assert.equal(G.slotAt(p, mid), s, "slot " + s);
        const span = G.slotSpan(p, s);
        assert.equal(G.slotAt(p, span.start + 0.01), s, "start of " + s);
        assert.equal(G.slotAt(p, span.start + span.length - 0.01), s, "end of " + s);
    }
});

test("with a narrow slot, the hovered cell contains the pointer and nothing jumps", () => {
    const p = withSep();
    let prev = null;
    sweep(p, b => {
        const slot = G.slotAt(p, b);
        if (slot >= 0) {
            const rowStart = -G.magOffsetAt(p, b);
            const start = G.slotStart(p, rowStart, slot, b);
            const slack = p.spacing / 2 + eps;
            assert.ok(start - slack <= 0 && 0 <= start + G.cellAtSlot(p, slot, b) + slack, "b=" + b);
        }
        const e = ends(p, b);
        if (prev !== null)
            assert.ok(Math.abs(e[0] - prev[0]) < 1 && Math.abs(e[1] - prev[1]) < 1, "b=" + b);
        prev = e;
    });
});

// ---- a zero-length slot (the gap before the dock) ----
// A cell of minus the spacing takes no room: its neighbours sit one normal
// spacing apart, as if it were not there.
const withGap = (grow = maxGrow) => G.makeProfile(6, 22, 4, 3 * pitch, grow, 2, -4);

test("a zero-length slot leaves its neighbours at the normal spacing", () => {
    const p = withGap(0);
    assert.equal(G.slotBase(p, 3) - (G.slotBase(p, 1) + 22), 4);
    assert.equal(G.baseTotal(p), 5 * 22 + 4 * 4);
});

test("a zero-length slot is never under the pointer and never grows", () => {
    const p = withGap();
    sweep(p, b => {
        assert.notEqual(G.slotAt(p, b), 2, "b=" + b);
        assert.ok(Math.abs(G.growAtSlot(p, 2, b)) < 1e-9, "b=" + b);
    });
});

test("with a zero-length slot, magnified slots stay one spacing apart and add up", () => {
    const p = withGap();
    sweep(p, b => {
        const gapLeft = G.slotStart(p, 0, 3, b) - (G.slotStart(p, 0, 1, b) + G.cellAtSlot(p, 1, b));
        assert.ok(Math.abs(gapLeft - 4) < 1e-6, "b=" + b);
        const last = p.n - 1;
        assert.ok(Math.abs(G.slotStart(p, 0, last, b) + G.cellAtSlot(p, last, b) - G.magTotal(p, b)) < 1e-6, "b=" + b);
    });
});

// ---- fixed slots (the open slot of a drag) ----
const withFixed = (fixed, grow = maxGrow) => G.makeProfile(9, 22, 4, 3 * pitch, grow, -1, 22, fixed);

test("a fixed slot keeps its resting size while its neighbours magnify", () => {
    const p = withFixed([{ slot: 4, weight: 1 }]);
    const b = 4 * pitch + 11;
    assert.ok(Math.abs(G.growAtSlot(p, 4, b)) < 1e-9);
    assert.ok(G.growAtSlot(p, 3, b) > 20 && G.growAtSlot(p, 5, b) > 20);
});

test("a fixed slot's weight scales its growth", () => {
    const b = 4 * pitch + 11;
    const full = G.growAtSlot(withFixed([]), 4, b);
    assert.ok(Math.abs(G.growAtSlot(withFixed([{ slot: 4, weight: 0.25 }]), 4, b) - 0.75 * full) < 1e-9);
});

test("with fixed slots, slots and the row's total still agree", () => {
    const p = withFixed([{ slot: 4, weight: 0.6 }, { slot: 5, weight: 0.4 }]);
    sweep(p, b => {
        let x = 0;
        for (let s = 0; s < p.n; s++) {
            assert.ok(Math.abs(G.slotStart(p, 0, s, b) - x) < 1e-6, "b=" + b + " slot=" + s);
            x += G.cellAtSlot(p, s, b) + p.spacing;
        }
        assert.ok(Math.abs(x - p.spacing - G.magTotal(p, b)) < 1e-6, "b=" + b);
    });
});

test("moving the fixed weight from one slot to the next changes the row smoothly", () => {
    // As the open slot moves, the old slot's weight fades out while the new one's fades in.
    const b = 4 * pitch + 20;
    let prev = null;
    for (let t = 0; t <= 1.0001; t += 0.05) {
        const p = withFixed([{ slot: 4, weight: 1 - t }, { slot: 5, weight: t }]);
        const e = ends(p, b);
        if (prev !== null)
            assert.ok(Math.abs(e[0] - prev[0]) < 3 && Math.abs(e[1] - prev[1]) < 3, "t=" + t);
        prev = e;
    }
});

test("a full fixed slot is a fully magnified icon wide wherever the pointer is", () => {
    const p = withFixed([{ slot: 8, weight: 1, full: true }]);
    for (const b of [8 * pitch + 11, 8 * pitch - 30, G.baseTotal(p) + 10])
        assert.ok(Math.abs(G.growAtSlot(p, 8, b) - maxGrow) < 1e-9, "b=" + b);
    assert.ok(Math.abs(G.growAtSlot(withFixed([{ slot: 8, weight: 1, full: true }], 0), 8, 50)) < 1e-9);
});

test("with a full fixed slot, slots add up and the row never jumps as the pointer moves", () => {
    const p = withFixed([{ slot: 4, weight: 1, full: true }]);
    let prev = null;
    sweep(p, b => {
        let x = 0;
        for (let s = 0; s < p.n; s++) {
            assert.ok(Math.abs(G.slotStart(p, 0, s, b) - x) < 1e-6, "b=" + b + " slot=" + s);
            x += G.cellAtSlot(p, s, b) + p.spacing;
        }
        assert.ok(Math.abs(x - p.spacing - G.magTotal(p, b)) < 1e-6, "b=" + b);
        const e = ends(p, b);
        if (prev !== null)
            assert.ok(Math.abs(e[0] - prev[0]) < 3 && Math.abs(e[1] - prev[1]) < 3, "b=" + b);
        prev = e;
    });
});
