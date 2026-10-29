.pragma library

// Every setting, in the groups and order the Settings tab shows them. resolve() turns
// what is saved into clean values, so a hand-edited settings.json can't break anything.
//
//   kind     enum, int, bool, string, or palette (a few colors edited together)
//   control  how an enum is drawn: scheme, tiles, seg or chips (seg or chips when left out)
//   section  a heading the row sits under, inside its tab
//   when     the row is dimmed unless another setting has one of these values

var swatches = [
  "#141414", "#1d1510", "#1a1b26", "#282a36", "#2e3440", "#2d353b", "#1f1f28", "#3b2a1f",
  "#e0e0e0", "#eadbc8", "#ffffff", "#c0caf5", "#d8dee9", "#dcd7ba", "#f8f8f2", "#e0def4",
  "#d4a35a", "#c8925a", "#7aa2f7", "#cba6f7", "#a7c080", "#88c0d0", "#fabd2f", "#ff6a1f"
];

var groups = [
  {
    title: "History",
    items: [
      { key: "historyLimit", label: "Clips kept", kind: "int", fallback: 500, min: 50, max: 2000, step: 50, section: "Keeping",
        hint: "The most clips kept. The oldest go first; pinned clips don't count and are never dropped." },
      { key: "keepFor", label: "Forget clips after", kind: "enum", fallback: "never", section: "Keeping",
        options: ["hour", "day", "week", "month", "never"],
        labels: { hour: "1 hour", day: "1 day", week: "1 week", month: "30 days", never: "Never" },
        hint: "Clips not copied or used again in this time are forgotten. Pinned clips stay." },
      { key: "images", label: "Keep pictures", kind: "bool", fallback: true, section: "What is kept",
        hint: "Screenshots and copied images, kept in Clipscape's own folder." },
      { key: "maxImageMB", label: "Largest picture", kind: "int", fallback: 20, min: 1, max: 50, step: 1, section: "What is kept",
        when: [{ key: "images", is: [true] }],
        hint: "Pictures bigger than this many megabytes are not kept." },
      { key: "maxTextKB", label: "Longest text", kind: "int", fallback: 256, min: 16, max: 1024, step: 16, section: "What is kept",
        hint: "Text longer than this many kilobytes is not kept." },
      { key: "skipApps", label: "Never keep copies from", kind: "string", fallback: "keepassxc, bitwarden, 1password, proton pass", maxLength: 300,
        section: "Privacy",
        hint: "Apps, by window class and separated by commas, whose copies are never kept. Copies a password manager marks as secret are never kept anyway." },
      { key: "secrets", label: "Clips that look like secrets", kind: "enum", fallback: "mask", control: "tiles", section: "Privacy",
        options: ["mask", "skip", "keep"], labels: { mask: "Hide and forget", skip: "Don't keep", keep: "Keep as is" },
        hint: "Passwords, tokens, keys and card numbers. Hide and forget shows them as dots, leaves them out of search and forgets them after a while." },
      { key: "secretMinutes", label: "Forget secrets after", kind: "int", fallback: 10, min: 1, max: 240, step: 1, section: "Privacy",
        when: [{ key: "secrets", is: ["mask"] }],
        hint: "Minutes before a hidden secret is forgotten, unless you pin it." },
      { key: "clearSecretSeconds", label: "Clear a pasted secret after", kind: "int", fallback: 0, min: 0, max: 120, step: 5, section: "Privacy",
        hint: "Seconds before the clipboard is emptied after you paste a secret from Clipscape, if it still holds it. 0 leaves it." }
    ]
  },
  {
    title: "Pasting",
    items: [
      { key: "enterAction", label: "Enter and click", kind: "enum", fallback: "paste", control: "tiles", section: "Picking",
        options: ["paste", "copy"], labels: { paste: "Paste it", copy: "Copy it" },
        hint: "Paste it puts the clip in the window you came from. Copy it only puts it on the clipboard. Shift+Enter always does the other." },
      { key: "pasteKeys", label: "Paste with", kind: "enum", fallback: "shift-insert", section: "Picking",
        options: ["shift-insert", "ctrl-v", "ctrl-shift-v", "type"],
        labels: { "shift-insert": "Shift+Insert", "ctrl-v": "Ctrl+V", "ctrl-shift-v": "Ctrl+Shift+V", type: "Type it out" },
        hint: "The keys pressed for you. Shift+Insert works in apps and terminals alike. Type it out types the text, for fields that block pasting." },
      { key: "usedToTop", label: "Used clips move up", kind: "bool", fallback: true, section: "Order",
        hint: "A clip you paste or copy from Clipscape goes back to the top of the history." },
      { key: "pinnedFirst", label: "Pinned clips first", kind: "bool", fallback: true, section: "Order",
        hint: "Pinned clips sit above the history in All. Off keeps them where they were copied." },
      { key: "joinWith", label: "Join marked clips with", kind: "enum", fallback: "newline", section: "Several at once",
        options: ["newline", "space", "none"], labels: { newline: "New line", space: "Space", none: "Nothing" },
        hint: "Mark clips with Ctrl+Space, then Enter pastes them together, in the order you marked them." }
    ]
  },
  {
    title: "Picker",
    items: [
      { key: "openAt", label: "Opens", kind: "enum", fallback: "center", control: "tiles", section: "Place",
        options: ["center", "mouse"], labels: { center: "In the middle", mouse: "At the mouse" },
        hint: "Where Super+Ctrl+V opens the picker." },
      { key: "pickerWidth", label: "Picker width", kind: "int", fallback: 860, min: 560, max: 1400, step: 20, section: "Place",
        hint: "How wide the picker is." },
      { key: "pickerHeight", label: "Picker height", kind: "int", fallback: 560, min: 380, max: 1000, step: 20, section: "Place",
        hint: "How tall the picker is." },
      { key: "dim", label: "Darken behind", kind: "int", fallback: 30, min: 0, max: 80, step: 5, section: "Place",
        hint: "How much the desktop behind the picker is darkened. 0 leaves it." },
      { key: "preview", label: "Preview", kind: "bool", fallback: true, section: "Look",
        hint: "The whole clip beside the list: all of the text, the picture, the color, the files." },
      { key: "rows", label: "Rows", kind: "enum", fallback: "detailed", control: "tiles", section: "Look",
        options: ["detailed", "compact"], labels: { detailed: "Two lines", compact: "One line" },
        hint: "Two lines adds what each clip is, its size, the app and when it was copied." },
      { key: "showApp", label: "App names", kind: "bool", fallback: true, section: "Look",
        when: [{ key: "rows", is: ["detailed"] }],
        hint: "The app each clip was copied from, on the second line." },
      { key: "numbers", label: "Numbers 1 to 9", kind: "bool", fallback: true, section: "Look",
        hint: "The first nine rows show Alt+1 to Alt+9, which paste that row straight away." },
      { key: "startFilter", label: "Opens on", kind: "enum", fallback: "all", section: "Look",
        options: ["all", "pinned", "last"], labels: { all: "All", pinned: "Pinned", last: "The last filter" },
        hint: "The filter the picker opens with." }
    ]
  },
  {
    title: "Colors",
    items: [
      { key: "colorMode", label: "Colors", kind: "enum", fallback: "theme", control: "scheme", section: "Scheme",
        options: ["theme", "borders", "custom", "monochrome"],
        labels: { theme: "Follow theme", borders: "Window borders", custom: "Custom", monochrome: "Monochrome" },
        hint: "Follow theme matches your Omarchy theme live. Window borders takes the accent from your theme's window border. Custom lets you choose the background, text and accent. Monochrome removes every hue." },
      { key: "customColors", label: "Custom colors", kind: "palette", section: "Scheme",
        fallback: { customBg: "#141414", customFg: "#e0e0e0", accentColor: "#d4a35a" },
        targets: [{ key: "customBg", label: "Background" }, { key: "customFg", label: "Text" }, { key: "accentColor", label: "Accent" }],
        presets: swatches,
        hint: "Choose Background, Text or Accent, then pick a swatch or type a hex. Each is used exactly as you pick it.",
        when: [{ key: "colorMode", is: ["custom"] }] },
      { key: "textColor", label: "Text", kind: "enum", fallback: "auto", section: "Text",
        options: ["auto", "theme", "custom"], labels: { auto: "Always readable", theme: "Theme", custom: "My text color" },
        when: [{ key: "colorMode", is: ["theme", "borders"] }],
        hint: "Always readable keeps your theme's text color, and switches to black or white when the window is too light or too dark for it. My text color uses the Text color from Custom colors." }
    ]
  },
  {
    title: "Appearance",
    items: [
      { key: "cardStyle", label: "Row style", kind: "enum", fallback: "soft", control: "tiles",
        options: ["soft", "outline", "flat"], labels: { soft: "Soft", outline: "Outline", flat: "Flat" },
        hint: "Soft fills the rows lightly, outline draws a border only, flat has neither." },
      { key: "density", label: "Spacing", kind: "enum", fallback: "comfortable", control: "tiles",
        options: ["compact", "comfortable", "spacious"], labels: { compact: "Compact", comfortable: "Comfortable", spacious: "Spacious" },
        hint: "How much air there is between things." },
      { key: "cornerRadius", label: "Roundness", kind: "int", fallback: 4, min: 0, max: 20, step: 2,
        hint: "0 is square, 20 is very round." },
      { key: "fontScale", label: "Text size", kind: "int", fallback: 100, min: 80, max: 150, step: 5, divisor: 100, decimals: 2,
        hint: "1 is normal, 1.25 is a quarter bigger." }
    ]
  },
  {
    title: "Window",
    items: [
      { key: "windowWidth", label: "Panel width", kind: "int", fallback: 520, min: 400, max: 1000, step: 20, section: "Size",
        hint: "How wide the bar panel opens." },
      { key: "windowHeight", label: "Panel height", kind: "int", fallback: 640, min: 420, max: 1100, step: 20, section: "Size",
        hint: "How tall the bar panel opens." },
      { key: "openAs", label: "Open as", kind: "enum", fallback: "panel", control: "tiles", section: "Layout",
        options: ["panel", "window"], labels: { panel: "Bar panel", window: "Own window" },
        hint: "Where the bar button opens Clipscape. You can always pop it out or dock it back from the header." },
      { key: "frame", label: "Window outline", kind: "bool", fallback: false, section: "Look",
        hint: "Draw the edge in your window border's colors instead of a plain neutral line. The picker gets it too." },
      { key: "frameGradient", label: "Outline gradient", kind: "bool", fallback: true, section: "Look",
        when: [{ key: "frame", is: [true] }],
        hint: "Use the window border's whole gradient, at its angle, when it has more than one color." },
      { key: "frameColor", label: "Outline color", kind: "enum", fallback: "accent", section: "Look",
        options: ["accent", "first", "middle", "last"],
        labels: { accent: "Accent", first: "Border's first", middle: "Border's middle", last: "Border's last" },
        when: [{ key: "frame", is: [true] }],
        hint: "The one color the outline takes when it isn't a gradient." },
      { key: "surfaceTint", label: "Window tint", kind: "int", fallback: 0, min: 0, max: 30, step: 2, section: "Look",
        hint: "How much of the accent washes over the background. 0 keeps it plain." },
      { key: "opacity", label: "Window opacity", kind: "int", fallback: 97, min: 50, max: 100, step: 1, section: "Look",
        hint: "100 is solid." }
    ]
  },
  {
    title: "Bar",
    items: [
      { key: "barShows", label: "Bar button shows", kind: "enum", fallback: "icon", section: "Button",
        options: ["icon", "count", "last"], labels: { icon: "Icon", count: "Icon and count", last: "Icon and last clip" },
        hint: "What sits on the bar. The last clip is cut short, and a secret is never shown." },
      { key: "middleClick", label: "Middle click", kind: "enum", fallback: "picker", section: "Button",
        options: ["picker", "pause", "none"], labels: { picker: "Open the picker", pause: "Pause or resume", none: "Nothing" },
        hint: "What a middle click on the bar button does." }
    ]
  }
];

// palette rows store their target keys (customBg...), not their own key
var colorKeys = {};

var defaults = (() => {
  const d = {};
  for (const g of groups)
    for (const it of g.items) {
      if (it.kind === "palette") {
        for (const t of it.targets) {
          d[t.key] = it.fallback[t.key];
          colorKeys[t.key] = it.fallback[t.key];
        }
      } else d[it.key] = it.fallback;
    }
  return d;
})();

var itemByKey = (() => {
  const m = {};
  for (const g of groups) for (const it of g.items) m[it.key] = it;
  return m;
})();

function validHex(s) { return /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(String(s)); }

// one value, made safe: a known option, a whole number in range, a real boolean, a hex
// color, or plain text that is not too long. Anything else is the default.
function clean(key, v) {
  if (colorKeys[key] !== undefined) return validHex(v) ? String(v).toLowerCase() : colorKeys[key];
  const it = itemByKey[key];
  if (!it) return undefined;
  if (v === null || v === undefined) return it.fallback;
  switch (it.kind) {
  case "enum":
    return it.options.indexOf(String(v)) >= 0 ? String(v) : it.fallback;
  case "int": {
    const n = typeof v === "number" ? v : (typeof v === "string" && /^-?[0-9]{1,7}$/.test(v) ? parseInt(v, 10) : NaN);
    return isFinite(n) ? Math.max(it.min, Math.min(it.max, Math.round(n))) : it.fallback;
  }
  case "bool":
    if (v === true || v === "true") return true;
    if (v === false || v === "false") return false;
    return it.fallback;
  default: {
    // text may be empty: an empty skip list means no app is skipped
    if (typeof v !== "string") return it.fallback;
    return v.replace(/[\u0000-\u001f\u007f]/g, " ").slice(0, it.maxLength || 64);
  }
  }
}

function resolve(values) {
  const out = {};
  const src = values && typeof values === "object" ? values : {};
  for (const k in defaults) out[k] = clean(k, src[k]);
  return out;
}

function isSetting(key) { return defaults[key] !== undefined; }

// Forget clips after, in milliseconds (0 = never)
var KEEP_MS = { hour: 3600000, day: 86400000, week: 604800000, month: 2592000000, never: 0 };
function keepMs(cfg) { return KEEP_MS[cfg.keepFor] || 0; }

// the skip list as lower-case app names
function skipList(s) {
  return String(s || "").split(",").map(x => x.trim().toLowerCase()).filter(x => x !== "").slice(0, 40);
}

if (typeof module !== "undefined") module.exports = { groups, defaults, clean, resolve, validHex, isSetting, keepMs, skipList };
