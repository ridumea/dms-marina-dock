// Magnification geometry along the bar's main axis: the magnified row is the
// integral of a bell-shaped scale density centred on the pointer's base point b.
// Base coordinates are resting-row pixels from the start of the first cell.

// Raised cosine: 1 at d = 0, 0 at d >= 1.
export function bell(d) {
    return d < 1 ? 0.5 * (1 + Math.cos(Math.PI * d)) : 0;
}

// Integral of bell(|t| / r) from 0 to x (odd in x).
function bellArea(x, r) {
    const ax = Math.min(Math.abs(x), r);
    const area = 0.5 * ax + (r / (2 * Math.PI)) * Math.sin(Math.PI * ax / r);
    return x < 0 ? -area : area;
}

const noFixed = [];

// `narrow` is a slot with a narrower cell that never grows, or -1. Each `fixed`
// entry { slot, weight, full } grows by maxGrow if full, else 0, blended by weight.
export function makeProfile(n, baseCell, spacing, radiusPx, maxGrow, narrow, narrowCell, fixed) {
    const pitch = baseCell + spacing;
    const r = Math.max(1, radiusPx);
    const grow = Math.max(0, maxGrow);
    const hasNarrow = narrow !== undefined && narrow >= 0 && narrow < n;
    return {
        "n": n,
        "baseCell": baseCell,
        "spacing": spacing,
        "pitch": pitch,
        "radiusPx": r,
        "maxGrow": grow,
        "a": grow > 0 ? grow / (2 * bellArea(pitch / 2, r)) : 0,
        "narrow": hasNarrow ? narrow : -1,
        "narrowCell": hasNarrow ? Math.min(baseCell, narrowCell) : baseCell,
        "fixed": (fixed && fixed.length > 0) ? fixed.filter(f => f && f.slot >= 0 && f.slot < n && f.weight > 0 && !(hasNarrow && f.slot === narrow)) : noFixed
    };
}

function shrink(p) {
    return p.narrow >= 0 ? p.baseCell - p.narrowCell : 0;
}

// Resting start of slot k's cell.
export function slotBase(p, k) {
    return k * p.pitch - (p.narrow >= 0 && k > p.narrow ? shrink(p) : 0);
}

export function slotBaseF(p, f) {
    const a = Math.floor(f);
    const t = f - a;
    const x0 = slotBase(p, a);
    return t > 0 ? x0 + (slotBase(p, a + 1) - x0) * t : x0;
}

// Resting length of slot k's cell.
export function slotCell(p, k) {
    return k === p.narrow ? p.narrowCell : p.baseCell;
}

export function baseTotal(p) {
    return p.n > 0 ? p.n * p.baseCell + (p.n - 1) * p.spacing - shrink(p) : 0;
}

// Growth of the line between base points u0 < u1, clipped to the row.
function growthBetween(p, u0, u1, b) {
    if (p.a <= 0 || p.n <= 0)
        return 0;
    const half = p.spacing / 2;
    const lo = Math.max(u0, -half);
    const hi = Math.min(u1, baseTotal(p) + half);
    if (hi <= lo)
        return 0;
    let area = bellArea(hi - b, p.radiusPx) - bellArea(lo - b, p.radiusPx);
    if (p.narrow >= 0) {
        const ns = slotBase(p, p.narrow) - half;
        const nlo = Math.max(lo, ns);
        const nhi = Math.min(hi, ns + p.narrowCell + p.spacing);
        if (nhi > nlo)
            area -= bellArea(nhi - b, p.radiusPx) - bellArea(nlo - b, p.radiusPx);
    }
    let fixedDelta = 0;
    // Indexed loop: this runs hundreds of times per pointer move.
    for (let i = 0; i < p.fixed.length; i++) {
        const f = p.fixed[i];
        const fs = slotBase(p, f.slot) - half;
        const span = p.baseCell + p.spacing;
        const flo = Math.max(lo, fs);
        const fhi = Math.min(hi, fs + span);
        if (fhi <= flo)
            continue;
        const bellGrowth = p.a * (bellArea(fhi - b, p.radiusPx) - bellArea(flo - b, p.radiusPx));
        const setGrowth = f.full ? p.maxGrow * (fhi - flo) / span : 0;
        fixedDelta += Math.min(1, f.weight) * (setGrowth - bellGrowth);
    }
    return p.a * area + fixedDelta;
}

export function growAtSlot(p, slot, b) {
    const start = slotBase(p, slot) - p.spacing / 2;
    return growthBetween(p, start, start + slotCell(p, slot) + p.spacing, b);
}

export function cellAtSlot(p, slot, b) {
    return slotCell(p, slot) + growAtSlot(p, slot, b);
}

export function magTotal(p, b) {
    if (p.n <= 0)
        return 0;
    return baseTotal(p) + growthBetween(p, -Infinity, Infinity, b);
}

// Offset within the magnified row at which base coordinate b is drawn.
export function magOffsetAt(p, b) {
    return b + growthBetween(p, -Infinity, b, b);
}

// Start of `slot` in the magnified row drawn from rowStart.
export function slotStart(p, rowStart, slot, b) {
    const base = slotBase(p, slot);
    return rowStart + base + growthBetween(p, -Infinity, base - p.spacing / 2, b);
}

// Fractional slots interpolate linearly, so items glide between slot layouts.
export function slotStartF(p, rowStart, f, b) {
    const a = Math.floor(f);
    const t = f - a;
    const x0 = slotStart(p, rowStart, a, b);
    return t > 0 ? x0 + (slotStart(p, rowStart, a + 1, b) - x0) * t : x0;
}

export function cellAtSlotF(p, f, b) {
    const a = Math.floor(f);
    const t = f - a;
    const c0 = cellAtSlot(p, a, b);
    return t > 0 ? c0 + (cellAtSlot(p, a + 1, b) - c0) * t : c0;
}

// Slot under base point b, or -1 past the row's ends. A gap belongs to the
// nearest cell, so there is always a hovered slot over the row.
export function slotAt(p, b) {
    if (p.n <= 0)
        return -1;
    const half = p.spacing / 2;
    if (b < -half || b > baseTotal(p) + half)
        return -1;
    let k;
    if (p.narrow < 0) {
        k = Math.floor((b + half) / p.pitch);
    } else {
        const ns = slotBase(p, p.narrow) - half;
        const ne = ns + p.narrowCell + p.spacing;
        k = b < ns ? Math.floor((b + half) / p.pitch) : (b < ne ? p.narrow : p.narrow + 1 + Math.floor((b - ne) / p.pitch));
    }
    return Math.max(0, Math.min(p.n - 1, k));
}

// Resting span of slot k: its cell plus half the gap on either side.
export function slotSpan(p, k) {
    return {
        "start": slotBase(p, k) - p.spacing / 2,
        "length": slotCell(p, k) + p.spacing
    };
}

// Largest growth on one side of the pointer.
export function sideGrowMax(p) {
    return p.a * bellArea(p.radiusPx, p.radiusPx);
}
