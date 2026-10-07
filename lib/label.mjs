// Text for the label above a hovered icon. Pure.

const separators = [" - ", " — ", " – ", " | ", " · "];

const words = s => s.toLowerCase().split(/\s+/).filter(Boolean);

// Whether `segment`, less a trailing version number, names the app: a run of
// whole words at the start or end of either ("Mozilla Firefox" for Firefox).
function namesApp(segment, appName) {
    const seg = words(segment.replace(/\s+v?\d+(\.\d+)*$/i, ""));
    const app = words(appName);
    if (seg.length === 0 || app.length === 0)
        return false;
    const [short, long] = seg.length <= app.length ? [seg, app] : [app, seg];
    const same = (offset) => short.every((w, i) => w === long[offset + i]);
    return same(0) || same(long.length - short.length);
}

// The window title without a trailing " - App Name" that repeats the name
// shown above it. A title that would be left empty is kept as it is.
export function withoutAppSuffix(title, appName) {
    const text = (title || "").trim();
    if (!appName)
        return text;
    let cut = -1, sepLength = 0;
    for (const sep of separators) {
        const i = text.lastIndexOf(sep);
        if (i > cut) {
            cut = i;
            sepLength = sep.length;
        }
    }
    if (cut <= 0 || !namesApp(text.slice(cut + sepLength), appName))
        return text;
    return text.slice(0, cut).trim() || text;
}
