// Plugin settings as stored by DMS, normalised to valid values. Stored values
// can be missing, strings, or out of range after a manual edit.

export const defaults = {
    // "bar": inside a DankBar via the Marina widget; "edge": own window per screen.
    "placement": "edge",
    "edge": "bottom",
    "edgeOffset": 8,
    "reserveSpace": true,
    "autoHide": false,
    // Briefly shows an auto-hidden edge dock when focus moves between tiled windows.
    "showOnSwitch": true,
    // Edge placement only; in a bar the widget's layout entry decides.
    "currentWorkspace": true,
    "currentMonitor": true,
    "groupByApp": false,
    "magnifyEnabled": true,
    // Edge placement only; in a bar the bar's size decides.
    "minIconPx": 24,
    "maxIconPx": 80,
    "radiusItems": 3,
    "animationMs": 220,
    "debugLog": false
};

export const ranges = {
    "edgeOffset": [0, 64],
    // Same range for both so their sliders share a scale.
    "minIconPx": [16, 128],
    "maxIconPx": [16, 128],
    "radiusItems": [1, 6],
    "animationMs": [0, 400]
};

export const steps = {
    "minIconPx": 8,
    "maxIconPx": 8
};

export const choices = {
    "placement": ["bar", "edge"],
    "edge": ["bottom", "top", "left", "right"]
};

function number(value, key) {
    const n = Number(value);
    if (value === null || value === undefined || value === "" || !Number.isFinite(n))
        return defaults[key];
    const [lo, hi] = ranges[key];
    const step = steps[key] || 0;
    const snapped = step > 0 ? Math.round(n / step) * step : n;
    return Math.max(lo, Math.min(hi, snapped));
}

function flag(value, key) {
    if (value === true || value === "true")
        return true;
    if (value === false || value === "false")
        return false;
    return defaults[key];
}

function choice(value, key) {
    return choices[key].indexOf(value) >= 0 ? value : defaults[key];
}

export function normalize(data) {
    const d = data || {};
    const out = {};
    for (const key in defaults) {
        if (key in choices)
            out[key] = choice(d[key], key);
        else if (key in ranges)
            out[key] = number(d[key], key);
        else
            out[key] = flag(d[key], key);
    }
    return out;
}
