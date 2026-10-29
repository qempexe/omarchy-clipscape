.pragma library

// Everything Clipscape knows about clips, with no Qt in it, so the tests run in node.
//
// A clip, as it is saved in history.json:
//   id      a short random name that never changes
//   kind    "text" or "image"
//   text    the text (text clips)
//   path, mime, w, h, bytes   the picture (image clips), kept in Clipscape's own folder
//   at      when it was first copied (ms), last  when it was last copied or used
//   uses    how many times it was copied or pasted
//   app     the app it was copied from (its window class), or ""
//   pinned, pin, label   pinned clips keep their place (pin) and can have a name
//   thumb   a copied picture file, shown in the list (the helper saw it when it came in)
//   secret  it looked like a password, a key or a card number when it came in

var MAX_TEXT = 1048576;            // what a text clip can hold at most, whatever the settings say
var SHOWN = 4096;                  // how much of a clip the list looks at and draws

var IMAGE_MIMES = { "image/png": "png", "image/jpeg": "jpg", "image/webp": "webp", "image/gif": "gif",
                    "image/bmp": "bmp", "image/tiff": "tiff" };

var FILTERS = [
  { key: "all", label: "All" },
  { key: "pinned", label: "Pinned" },
  { key: "text", label: "Text" },
  { key: "link", label: "Links" },
  { key: "image", label: "Images" },
  { key: "files", label: "Files" },
  { key: "color", label: "Colors" },
  { key: "code", label: "Code" }
];
var FILTER_KEYS = FILTERS.map(f => f.key);

// ---- small helpers -----------------------------------------------------------------

function str(v) { return typeof v === "string" ? v : ""; }
function num(v, fallback) { return typeof v === "number" && isFinite(v) ? v : fallback; }
function clampInt(v, lo, hi, fallback) {
  const n = num(v, NaN);
  return isFinite(n) ? Math.max(lo, Math.min(hi, Math.round(n))) : fallback;
}
// names shown in the list: no control characters, not too long
function plain(s, max) { return str(s).replace(/[\u0000-\u001f\u007f]/g, " ").trim().slice(0, max); }

function newId(at) {
  return Math.floor(num(at, 0)).toString(36) + "-" + Math.floor(Math.random() * 2176782336).toString(36);
}

// ---- reading and cleaning what is saved ------------------------------------------------

// one clip, made safe, or null. imgDir: the only folder an image clip may point into.
function normalize(v, imgDir, now) {
  if (!v || typeof v !== "object" || Array.isArray(v)) return null;
  const t = num(now, Date.now());
  const out = {
    id: /^[a-z0-9-]{1,40}$/.test(str(v.id)) ? v.id : newId(t),
    kind: v.kind === "image" ? "image" : "text",
    at: Math.max(0, num(v.at, t)),
    last: 0,
    uses: clampInt(v.uses, 1, 1000000, 1),
    app: plain(v.app, 64),
    pinned: v.pinned === true,
    pin: clampInt(v.pin, 0, 100000, 0),
    label: plain(v.label, 60),
    secret: v.secret === true
  };
  out.last = Math.max(out.at, num(v.last, out.at));
  if (out.kind === "text") {
    const text = str(v.text);
    if (text.trim() === "" || text.length > MAX_TEXT) return null;
    out.text = text;
    if (v.thumb === true) out.thumb = true;
  } else {
    const path = str(v.path);
    const dir = str(imgDir).replace(/\/+$/, "");
    const m = /^(.*)\/([0-9a-f]{64})\.(png|jpg|webp|gif|bmp|tiff)$/.exec(path);
    if (!m || (dir !== "" && m[1] !== dir)) return null;
    out.path = path;
    out.mime = IMAGE_MIMES[str(v.mime)] ? v.mime : "image/png";
    out.w = clampInt(v.w, 0, 100000, 0);
    out.h = clampInt(v.h, 0, 100000, 0);
    out.bytes = clampInt(v.bytes, 0, 1e10, 0);
  }
  return out;
}

// history.json: { version: 1, clips: [...] }, newest first
function parseStore(raw, imgDir, now) {
  let data;
  try { data = JSON.parse(String(raw || "")); } catch (e) { return []; }
  const list = Array.isArray(data) ? data : (data && Array.isArray(data.clips) ? data.clips : []);
  const out = [], seen = {}, ids = {};
  for (const v of list) {
    const c = normalize(v, imgDir, now);
    if (!c) continue;
    const k = keyOf(c);
    if (seen[k]) continue;
    seen[k] = true;
    while (ids[c.id]) c.id = newId(c.at);
    ids[c.id] = true;
    out.push(c);
  }
  return out;
}

function serialize(list) {
  return JSON.stringify({ version: 1, clips: list }) + "\n";
}

// two clips are the same when they hold the same text or the same picture
function keyOf(c) { return c.kind === "image" ? "i:" + c.path : "t:" + c.text; }

// ---- what kind of text a clip is -----------------------------------------------------

function fileUris(text) {
  const lines = str(text).split(/\r?\n/).map(l => l.trim()).filter(l => l !== "" && l.charAt(0) !== "#");
  if (lines.length === 0) return [];
  const paths = [];
  for (const l of lines) {
    if (l.indexOf("file://") !== 0) return [];
    let p = l.slice(7);
    if (p.indexOf("localhost/") === 0) p = p.slice(9);
    if (p.charAt(0) !== "/") return [];
    try { p = decodeURIComponent(p); } catch (e) { /* keep it as it is */ }
    paths.push(p);
  }
  return paths;
}

var COLOR_RE = /^\s*(#(?:[0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})|rgba?\(\s*\d{1,3}%?\s*[, ]\s*\d{1,3}%?\s*[, ]\s*\d{1,3}%?\s*(?:[,/]\s*[\d.]+%?\s*)?\)|hsla?\(\s*\d{1,3}(?:deg)?\s*[, ]\s*\d{1,3}%\s*[, ]\s*\d{1,3}%\s*(?:[,/]\s*[\d.]+%?\s*)?\))\s*$/i;

function looksLikeCode(text) {
  const t = text.slice(0, SHOWN);
  const lines = t.split("\n");
  let score = 0;
  if (/[{};]\s*$/m.test(t)) score += 2;
  if (/^\s{2,}\S/m.test(t) && lines.length > 1) score += 1;
  if (/=>|->|::|===|!==|&&|\|\||\+=|<\/?[a-z]+[^>]*>/.test(t)) score += 1;
  if (/^\s*(import|export|const|let|var|function|def|class|return|if|for|while|fn|pub|func|package|#include|using|public|private|SELECT|INSERT|UPDATE|local|echo|cd|git|npm|cargo|make)\b/m.test(t)) score += 2;
  if (/^\s*[$#] \S/m.test(t)) score += 1;
  if (/\b[a-zA-Z_]\w*\([^()]*\)/.test(t)) score += 1;
  return score >= 3 || (lines.length === 1 && score >= 2 && t.length < 400);
}

// text | link | email | color | number | files | code
function classify(text) {
  const t = str(text);
  const s = t.trim();
  if (s === "") return "text";
  if (fileUris(s).length > 0) return "files";
  if (s.length <= 64 && COLOR_RE.test(s)) return "color";
  if (!/\s/.test(s) && s.length <= 4096) {
    if (/^(https?|ftp):\/\/[^\s/$.?#][^\s]*$/i.test(s) || /^www\.[^\s.]+\.[^\s]+$/i.test(s)) return "link";
    if (/^(mailto:)?[^\s@<>()]+@[^\s@<>()]+\.[a-z]{2,}$/i.test(s)) return "email";
  }
  if (s.length <= 40 && /^[-+]?(\d[\d\s.,_']*)(e[-+]?\d+)?%?$/i.test(s)) return "number";
  if (looksLikeCode(t)) return "code";
  return "text";
}

// which filter chips a clip shows up under
function matchesFilter(c, filter) {
  if (filter === "all" || !filter) return true;
  if (filter === "pinned") return c.pinned === true;
  if (filter === "image") return c.kind === "image";
  if (c.kind !== "text") return false;
  const k = kindOf(c);
  if (filter === "text") return k === "text" || k === "email" || k === "number";
  return k === filter;
}

// cached on the clip, so a list of hundreds doesn't classify on every keystroke
function kindOf(c) {
  if (c.kind === "image") return "image";
  if (c._k === undefined) c._k = classify(c.text);
  return c._k;
}

// ---- secrets ------------------------------------------------------------------------

function luhn(digits) {
  let sum = 0, alt = false;
  for (let i = digits.length - 1; i >= 0; i--) {
    let d = digits.charCodeAt(i) - 48;
    if (alt) { d *= 2; if (d > 9) d -= 9; }
    sum += d;
    alt = !alt;
  }
  return sum % 10 === 0;
}

function entropy(s) {
  const f = {};
  for (const ch of s) f[ch] = (f[ch] || 0) + 1;
  let e = 0;
  const n = s.length;
  for (const k in f) { const p = f[k] / n; e -= p * Math.log2(p); }
  return e;
}

var TOKEN_RES = [
  /-----BEGIN ((RSA|EC|DSA|OPENSSH|PGP|ENCRYPTED) )?PRIVATE KEY( BLOCK)?-----/,
  /^eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}$/,           // a JSON web token
  /^(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}$/, /^github_pat_[A-Za-z0-9_]{40,}$/, // GitHub
  /^glpat-[A-Za-z0-9_-]{20,}$/,                                                 // GitLab
  /^xox[abposr]-[A-Za-z0-9-]{10,}$/,                                            // Slack
  /^sk-(proj-|ant-)?[A-Za-z0-9_-]{20,}$/, /^(sk|rk|pk)_(live|test)_[A-Za-z0-9]{16,}$/,
  /^AKIA[0-9A-Z]{16}$/, /^AIza[0-9A-Za-z_-]{35}$/, /^npm_[A-Za-z0-9]{36}$/, /^hf_[A-Za-z0-9]{30,}$/,
  /^(SG\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,})$/, /^dop_v1_[a-f0-9]{64}$/
];

// "" when it looks ordinary, else what it looks like: key, token, card or password.
// Only one word (no spaces) is ever taken for a password or a token; sentences never are.
function secretKind(text) {
  const s = str(text).trim();
  if (s === "" || s.length > 16384) return "";
  if (TOKEN_RES[0].test(s)) return "key";
  if (/\s/.test(s)) {
    const digits = s.replace(/[\s-]/g, "");
    if (/^\d{13,19}$/.test(digits) && /^[\d\s-]+$/.test(s) && luhn(digits)) return "card";
    return "";
  }
  for (let i = 1; i < TOKEN_RES.length; i++) if (TOKEN_RES[i].test(s)) return "token";
  if (/^\d{13,19}$/.test(s) && luhn(s)) return "card";
  const k = classify(s);
  if (k !== "text" && k !== "code") return "";
  if (/^[./~]/.test(s) || s.indexOf("/") >= 0) return "";
  const lower = /[a-z]/.test(s), upper = /[A-Z]/.test(s), digit = /[0-9]/.test(s), sym = /[^A-Za-z0-9]/.test(s);
  if (s.length >= 24 && s.length <= 256 && lower && upper && digit && entropy(s) >= 4.2) return "token";
  if (s.length >= 8 && s.length <= 64 && lower && upper && digit && sym) return "password";
  return "";
}

// ---- adding, removing, keeping ----------------------------------------------------------

// The clip goes to the top. Copying the same thing again moves the old one up instead of
// adding it twice: it keeps its pin, name and first time, and counts one more use.
function add(list, clip, limit) {
  const k = keyOf(clip);
  let merged = clip;
  const rest = [];
  for (const c of list) {
    if (keyOf(c) === k) {
      merged = Object.assign({}, c, {
        last: Math.max(c.last, clip.at), uses: c.uses + 1,
        app: clip.app || c.app, secret: c.secret || clip.secret
      });
    } else {
      rest.push(c);
    }
  }
  return cap([merged].concat(rest), limit);
}

// keep at most `limit` clips that aren't pinned (pinned ones don't count)
function cap(list, limit) {
  const max = Math.max(1, Math.round(num(limit, 500)));
  let n = 0;
  return list.filter(c => c.pinned || ++n <= max);
}

// what Forget after and Forget secrets after allow (0 = keep them)
function prune(list, keepMs, secretMs, now) {
  const t = num(now, Date.now());
  return list.filter(c => {
    if (c.pinned) return true;
    if (keepMs > 0 && t - c.last > keepMs) return false;
    if (c.secret && secretMs > 0 && t - c.at > secretMs) return false;
    return true;
  });
}

function indexOfId(list, id) {
  for (let i = 0; i < list.length; i++) if (list[i].id === id) return i;
  return -1;
}
function byId(list, id) { const i = indexOfId(list, id); return i >= 0 ? list[i] : null; }

function remove(list, ids) {
  const drop = {};
  for (const id of [].concat(ids)) drop[id] = true;
  return list.filter(c => !drop[c.id]);
}

// everything but the pinned clips
function clearUnpinned(list) { return list.filter(c => c.pinned); }

function update(list, id, change) {
  return list.map(c => c.id === id ? Object.assign({}, c, change) : c);
}

// pinning puts a clip at the end of the pinned ones; the others keep their order
function setPinned(list, id, on) {
  let top = 0;
  for (const c of list) if (c.pinned) top = Math.max(top, c.pin);
  return list.map(c => {
    if (c.id !== id) return c;
    return on ? Object.assign({}, c, { pinned: true, pin: c.pinned ? c.pin : top + 1 })
              : Object.assign({}, c, { pinned: false, pin: 0, label: "" });
  });
}

// move a pinned clip up (d = -1) or down (d = 1) among the pinned ones
function movePin(list, id, d) {
  const pins = list.filter(c => c.pinned).sort((a, b) => a.pin - b.pin);
  const i = pins.findIndex(c => c.id === id);
  const j = i + d;
  if (i < 0 || j < 0 || j >= pins.length) return list;
  const order = pins.map(c => c.id);
  order.splice(j, 0, order.splice(i, 1)[0]);
  const rank = {};
  order.forEach((x, n) => { rank[x] = n + 1; });
  return list.map(c => c.pinned ? Object.assign({}, c, { pin: rank[c.id] }) : c);
}

// image files still in use (the helper deletes the others)
function imagePaths(list) { return list.filter(c => c.kind === "image").map(c => c.path); }

// ---- what the list shows ----------------------------------------------------------------

function firstLine(text) {
  const t = str(text).slice(0, SHOWN);
  const lines = t.split(/\r?\n/);
  for (const l of lines) if (l.trim() !== "") return l.replace(/\s+/g, " ").trim();
  return "";
}

function baseName(p) { const parts = str(p).split("/"); return parts[parts.length - 1] || p; }

var SECRET_NAMES = { key: "a private key", token: "a token", card: "a card number", password: "a password" };

function mask(c) {
  const k = secretKind(c.text);
  return "•••••••• " + (SECRET_NAMES[k] ? "(looks like " + SECRET_NAMES[k] + ")" : "(hidden)");
}

// the one line a row shows. masked: secrets as dots
function title(c, masked) {
  if (c.label) return c.label;
  if (c.kind === "image") return "Image" + (c.w > 0 ? " · " + c.w + " × " + c.h : "") + " · " + (IMAGE_MIMES[c.mime] || "png").toUpperCase();
  if (c.secret && masked) return mask(c);
  if (kindOf(c) === "files") {
    const p = fileUris(c.text);
    return p.length === 1 ? baseName(p[0]) : p.length + " files: " + p.slice(0, 3).map(baseName).join(", ") + (p.length > 3 ? "…" : "");
  }
  return firstLine(c.text).slice(0, 240);
}

function bytesText(n) {
  if (n < 1024) return n + " B";
  if (n < 1048576) return (n / 1024).toFixed(n < 10240 ? 1 : 0) + " KB";
  return (n / 1048576).toFixed(1) + " MB";
}

function ago(ms, now) {
  const s = Math.max(0, Math.round((num(now, Date.now()) - ms) / 1000));
  if (s < 45) return "just now";
  if (s < 3600) return Math.max(1, Math.round(s / 60)) + " min ago";
  if (s < 86400) return Math.round(s / 3600) + " h ago";
  const d = Math.round(s / 86400);
  if (d === 1) return "yesterday";
  if (d < 30) return d + " days ago";
  const dt = new Date(ms);
  const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  return dt.getDate() + " " + months[dt.getMonth()] + (d > 300 ? " " + dt.getFullYear() : "");
}

var KIND_NAMES = { text: "Text", link: "Link", email: "Email", color: "Color", number: "Number",
                   files: "Files", code: "Code", image: "Image" };

// the small line under it: what it is, its size, where it came from, when
function meta(c, now, showApp) {
  const parts = [KIND_NAMES[kindOf(c)] || "Text"];
  if (c.kind === "image") {
    if (c.bytes > 0) parts.push(bytesText(c.bytes));
  } else if (kindOf(c) === "files") {
    const n = fileUris(c.text).length;
    parts.push(n === 1 ? "1 file" : n + " files");
  } else {
    const n = c.text.length;
    const lines = c.text.split("\n").length;
    parts.push(lines > 1 ? lines + " lines" : n + (n === 1 ? " character" : " characters"));
  }
  if (showApp && c.app) parts.push(c.app);
  parts.push(ago(c.last, now));
  if (c.uses > 1) parts.push(c.uses + "×");
  return parts.join(" · ");
}

// what the search looks at
function haystack(c, revealed) {
  const bits = [c.label, c.app, KIND_NAMES[kindOf(c)] || ""];
  if (c.secret) bits.push("secret");
  if (c.kind === "image") bits.push("image picture screenshot " + (IMAGE_MIMES[c.mime] || "") + " " + c.w + "x" + c.h);
  else if (kindOf(c) === "files") bits.push(fileUris(c.text).join(" "));
  else bits.push(c.secret && !revealed ? "" : c.text.slice(0, SHOWN));
  return bits.join(" ").toLowerCase();
}

// How well one word matches: in the text is best (earlier is better, at a word start
// better still). Its letters in order, starting at a word and close together
// ("gst" in "git status"), is a weaker match. No match is -1.
function isStart(hay, i) { return i === 0 || /[\s/._:@#(-]/.test(hay.charAt(i - 1)); }
function wordScore(hay, w) {
  const i = hay.indexOf(w);
  if (i >= 0) return 100 + (isStart(hay, i) ? 40 : 0) - Math.min(30, i / 50);
  if (w.length < 3) return -1;
  let best = -1;
  for (let s = hay.indexOf(w.charAt(0)); s >= 0 && s < hay.length; s = hay.indexOf(w.charAt(0), s + 1)) {
    if (!isStart(hay, s)) continue;
    let j = 1, k = s + 1;
    const limit = s + w.length * 2 + 2;
    for (; k < hay.length && k < limit && j < w.length; k++) if (hay.charAt(k) === w.charAt(j)) j++;
    if (j === w.length) best = Math.max(best, 60 - (k - s - w.length) * 4);
  }
  return best;
}

// a query: words, plus is:pinned, type:link (or any kind), app:firefox
function parseQuery(q) {
  const out = { words: [], kind: "", app: "", pinned: false };
  for (const part of str(q).toLowerCase().split(/\s+/)) {
    if (part === "") continue;
    let m;
    if (part === "is:pinned" || part === "is:pin") out.pinned = true;
    else if ((m = /^type:(\w+)$/.exec(part)) !== null) out.kind = m[1];
    else if ((m = /^app:(.+)$/.exec(part)) !== null) out.app = m[1];
    else out.words.push(part);
  }
  return out;
}

function kindMatches(c, want) {
  if (want === "") return true;
  const k = kindOf(c);
  const name = (KIND_NAMES[k] || "").toLowerCase();
  return k.indexOf(want) === 0 || name.indexOf(want) === 0;
}

// The rows to show, best first. With words typed, the best match leads (more recent wins
// a tie). Without, the newest leads, and pinned clips come first when pinnedFirst. A
// secret's text is only searched while secrets are shown (revealed).
function search(list, query, filter, pinnedFirst, revealed) {
  const q = parseQuery(query);
  const rows = [];
  for (let i = 0; i < list.length; i++) {
    const c = list[i];
    if (!matchesFilter(c, filter)) continue;
    if (q.pinned && !c.pinned) continue;
    if (!kindMatches(c, q.kind)) continue;
    if (q.app !== "" && c.app.toLowerCase().indexOf(q.app) < 0) continue;
    let score = 0;
    if (q.words.length > 0) {
      const hay = haystack(c, revealed === true);
      let ok = true;
      for (const w of q.words) {
        const s = wordScore(hay, w);
        if (s < 0) { ok = false; break; }
        score += s;
      }
      if (!ok) continue;
    }
    rows.push({ clip: c, score: score, order: i });
  }
  if (q.words.length > 0) rows.sort((a, b) => b.score - a.score || a.order - b.order);
  else if (pinnedFirst || filter === "pinned") rows.sort((a, b) => {
    if (a.clip.pinned !== b.clip.pinned) return a.clip.pinned ? -1 : 1;
    if (a.clip.pinned) return a.clip.pin - b.clip.pin;
    return a.order - b.order;
  });
  return rows.map(r => r.clip);
}

// how many clips each chip has
function counts(list) {
  const out = {};
  for (const f of FILTER_KEYS) out[f] = 0;
  for (const c of list) for (const f of FILTER_KEYS) if (matchesFilter(c, f)) out[f]++;
  return out;
}

// ---- colors -------------------------------------------------------------------------------

function hex2(n) { const s = Math.max(0, Math.min(255, Math.round(n))).toString(16); return s.length < 2 ? "0" + s : s; }

// a color clip as #rrggbb, rgb() and hsl(), or null
function colorInfo(text) {
  const s = str(text).trim();
  if (!COLOR_RE.test(s)) return null;
  let r, g, b, a = 1, m;
  if (s.charAt(0) === "#") {
    let h = s.slice(1);
    if (h.length <= 4) h = h.split("").map(x => x + x).join("");
    r = parseInt(h.slice(0, 2), 16); g = parseInt(h.slice(2, 4), 16); b = parseInt(h.slice(4, 6), 16);
    if (h.length === 8) a = parseInt(h.slice(6, 8), 16) / 255;
  } else if ((m = /^rgba?\(\s*(\d+)(%?)\s*[, ]\s*(\d+)(%?)\s*[, ]\s*(\d+)(%?)\s*(?:[,/]\s*([\d.]+)(%?)\s*)?\)$/i.exec(s)) !== null) {
    const ch = (v, pct) => pct ? Number(v) * 2.55 : Number(v);
    r = ch(m[1], m[2]); g = ch(m[3], m[4]); b = ch(m[5], m[6]);
    if (m[7] !== undefined) a = m[8] ? Number(m[7]) / 100 : Number(m[7]);
  } else if ((m = /^hsla?\(\s*(\d+)(?:deg)?\s*[, ]\s*(\d+)%\s*[, ]\s*(\d+)%\s*(?:[,/]\s*([\d.]+)(%?)\s*)?\)$/i.exec(s)) !== null) {
    const hh = (Number(m[1]) % 360) / 360, ss = Math.min(100, Number(m[2])) / 100, ll = Math.min(100, Number(m[3])) / 100;
    const q = ll < 0.5 ? ll * (1 + ss) : ll + ss - ll * ss, p = 2 * ll - q;
    const f = t => { t = (t + 1) % 1; return t < 1 / 6 ? p + (q - p) * 6 * t : t < 0.5 ? q : t < 2 / 3 ? p + (q - p) * (2 / 3 - t) * 6 : p; };
    r = f(hh + 1 / 3) * 255; g = f(hh) * 255; b = f(hh - 1 / 3) * 255;
    if (m[4] !== undefined) a = m[5] ? Number(m[4]) / 100 : Number(m[4]);
  } else {
    return null;
  }
  r = Math.min(255, r); g = Math.min(255, g); b = Math.min(255, b);
  const max = Math.max(r, g, b) / 255, min = Math.min(r, g, b) / 255, l = (max + min) / 2;
  let h = 0, sat = 0;
  if (max !== min) {
    const d = max - min;
    sat = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    const R = r / 255, G = g / 255, B = b / 255;
    h = max === R ? (G - B) / d + (G < B ? 6 : 0) : max === G ? (B - R) / d + 2 : (R - G) / d + 4;
    h *= 60;
  }
  const hex = "#" + hex2(r) + hex2(g) + hex2(b);
  return {
    hex: hex,
    alpha: Math.max(0, Math.min(1, a)),
    rgb: "rgb(" + Math.round(r) + ", " + Math.round(g) + ", " + Math.round(b) + ")",
    hsl: "hsl(" + Math.round(h) + ", " + Math.round(sat * 100) + "%, " + Math.round(l * 100) + "%)"
  };
}

// ---- changing text --------------------------------------------------------------------------

function utf8Bytes(s) {
  const out = [];
  for (const ch of s) {
    const cp = ch.codePointAt(0);
    if (cp < 0x80) out.push(cp);
    else if (cp < 0x800) out.push(0xc0 | cp >> 6, 0x80 | cp & 63);
    else if (cp < 0x10000) out.push(0xe0 | cp >> 12, 0x80 | cp >> 6 & 63, 0x80 | cp & 63);
    else out.push(0xf0 | cp >> 18, 0x80 | cp >> 12 & 63, 0x80 | cp >> 6 & 63, 0x80 | cp & 63);
  }
  return out;
}
function utf8Text(bytes) {
  let s = "", i = 0;
  while (i < bytes.length) {
    const b = bytes[i];
    let cp, n;
    if (b < 0x80) { cp = b; n = 1; }
    else if (b >> 5 === 6) { cp = b & 31; n = 2; }
    else if (b >> 4 === 14) { cp = b & 15; n = 3; }
    else if (b >> 3 === 30) { cp = b & 7; n = 4; }
    else return null;
    if (i + n > bytes.length) return null;
    for (let k = 1; k < n; k++) {
      if (bytes[i + k] >> 6 !== 2) return null;
      cp = cp << 6 | bytes[i + k] & 63;
    }
    s += String.fromCodePoint(cp);
    i += n;
  }
  return s;
}
var B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
function base64Encode(s) {
  const b = utf8Bytes(s);
  let out = "";
  for (let i = 0; i < b.length; i += 3) {
    const n = b[i] << 16 | (b[i + 1] || 0) << 8 | (b[i + 2] || 0);
    out += B64[n >> 18 & 63] + B64[n >> 12 & 63] + (i + 1 < b.length ? B64[n >> 6 & 63] : "=") + (i + 2 < b.length ? B64[n & 63] : "=");
  }
  return out;
}
function base64Decode(s) {
  const t = s.replace(/\s+/g, "").replace(/-/g, "+").replace(/_/g, "/");
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(t) || t.length === 0) return null;
  const bytes = [];
  let buf = 0, bits = 0;
  for (const ch of t.replace(/=+$/, "")) {
    buf = buf << 6 | B64.indexOf(ch);
    bits += 6;
    if (bits >= 8) { bits -= 8; bytes.push(buf >> bits & 255); }
  }
  return utf8Text(bytes);
}

function titleCase(s) { return s.toLowerCase().replace(/(^|[\s\-_/(["'])(\S)/g, (m, a, b) => a + b.toUpperCase()); }

// Transform in the actions menu. Each takes the text and gives the new text, or null when
// it doesn't apply (a JSON one on text that isn't JSON).
var TRANSFORMS = [
  { key: "upper", label: "UPPER CASE", run: s => s.toUpperCase() },
  { key: "lower", label: "lower case", run: s => s.toLowerCase() },
  { key: "title", label: "Title Case", run: titleCase },
  { key: "trim", label: "Trim spaces", run: s => s.split("\n").map(l => l.replace(/\s+$/, "")).join("\n").trim() },
  { key: "squash", label: "One line", run: s => s.replace(/\s+/g, " ").trim() },
  { key: "noblank", label: "Remove empty lines", run: s => s.split(/\r?\n/).filter(l => l.trim() !== "").join("\n") },
  { key: "sort", label: "Sort lines", run: s => s.split(/\r?\n/).sort((a, b) => a.localeCompare(b)).join("\n") },
  { key: "unique", label: "Remove repeated lines", run: s => s.split(/\r?\n/).filter((l, i, a) => a.indexOf(l) === i).join("\n") },
  { key: "jsonPretty", label: "Format JSON", run: s => { try { return JSON.stringify(JSON.parse(s), null, 2); } catch (e) { return null; } } },
  { key: "jsonMin", label: "Minify JSON", run: s => { try { return JSON.stringify(JSON.parse(s)); } catch (e) { return null; } } },
  { key: "urlEncode", label: "URL encode", run: s => encodeURIComponent(s) },
  { key: "urlDecode", label: "URL decode", run: s => { try { return decodeURIComponent(s.replace(/\+/g, " ")); } catch (e) { return null; } } },
  { key: "b64Encode", label: "Base64 encode", run: base64Encode },
  { key: "b64Decode", label: "Base64 decode", run: base64Decode },
  { key: "markdownLink", label: "Markdown link", run: s => /^https?:\/\/\S+$/i.test(s.trim()) ? "[" + s.trim().replace(/^https?:\/\/(www\.)?/i, "").replace(/\/$/, "") + "](" + s.trim() + ")" : null },
  { key: "quote", label: "Quote lines (>)", run: s => s.split(/\r?\n/).map(l => "> " + l).join("\n") }
];

function transform(key, text) {
  for (const t of TRANSFORMS) if (t.key === key) {
    const out = t.run(str(text));
    return typeof out === "string" && out !== "" && out.length <= MAX_TEXT ? out : null;
  }
  return null;
}

// several clips pasted together, in the order they were marked
function joined(clips, how) {
  const sep = how === "space" ? " " : (how === "none" ? "" : "\n");
  return clips.filter(c => c && c.kind === "text").map(c => c.text).join(sep);
}

// Omarchy's own history (~/.local/state/omarchy/clipboard-history.json), brought in the
// first time Clipscape runs. Text only here; the helper brings the pictures.
function fromOmarchy(raw, now) {
  let data;
  try { data = JSON.parse(String(raw || "")); } catch (e) { return []; }
  if (!Array.isArray(data)) return [];
  const t = num(now, Date.now());
  const out = [];
  for (let i = 0; i < data.length && out.length < 2000; i++) {
    const v = data[i];
    const text = typeof v === "string" ? v : (v && v.type === "text" ? str(v.text) : "");
    if (text.trim() === "" || text.length > MAX_TEXT) continue;
    // the list is newest first; give them times a second apart, in that order
    out.push({ id: newId(t - i * 1000), kind: "text", text: text, at: t - i * 1000, last: t - i * 1000,
               uses: 1, app: "", pinned: false, pin: 0, label: "", secret: secretKind(text) !== "" });
  }
  return out;
}

if (typeof module !== "undefined") module.exports = {
  MAX_TEXT, FILTERS, FILTER_KEYS, TRANSFORMS, normalize, parseStore, serialize, keyOf, classify, kindOf,
  matchesFilter, fileUris, secretKind, luhn, add, cap, prune, remove, clearUnpinned, update, setPinned,
  movePin, byId, indexOfId, imagePaths, title, meta, ago, bytesText, search, parseQuery, counts,
  colorInfo, transform, joined, base64Encode, base64Decode, fromOmarchy, firstLine
};
