// Where the dock goes on screen, from DMS's bar configuration. Pure: bar
// configs come in as plain objects, screen matching as a callback.

export const positions = {
    "top": 0,
    "bottom": 1,
    "left": 2,
    "right": 3
};

// Space the DMS bars on `edge` take on this screen. thicknessOf(bc) is a bar's
// own thickness; covers(bc) whether it is on this screen.
export function barZoneOnEdge(barConfigs, edge, covers, thicknessOf) {
    const pos = positions[edge];
    let zone = 0;
    for (const bc of barConfigs || []) {
        if (!bc || bc.enabled === false || bc.autoHide || bc.visible === false || bc.island)
            continue;
        if ((bc.position ?? 0) !== pos || !covers(bc))
            continue;
        zone += thicknessOf(bc) + (bc.spacing ?? 4) + (bc.bottomGap ?? 0);
    }
    return zone;
}

// The bars and sections that hold the widget `id`. `vertical` marks a left or
// right bar, whose "left" and "right" sections are its top and bottom.
export function barAttachments(barConfigs, id) {
    const out = [];
    for (const bc of barConfigs || []) {
        if (!bc || bc.enabled === false)
            continue;
        for (const section of ["left", "center", "right"]) {
            const list = bc[section + "Widgets"] || [];
            const found = list.some(w => (typeof w === "string" ? w : w?.id) === id && (typeof w === "string" || w?.enabled !== false));
            if (found)
                out.push({
                    "bar": bc.name || bc.id || "",
                    "section": section,
                    "vertical": bc.position === positions.left || bc.position === positions.right
                });
        }
    }
    return out;
}
