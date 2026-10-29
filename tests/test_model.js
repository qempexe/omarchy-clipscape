#!/usr/bin/env node
// The pure logic, in node:  node tests/test_model.js
const fs = require("fs"), path = require("path"), assert = require("assert");
const root = path.join(__dirname, "..");
function load(file) {
  const src = fs.readFileSync(path.join(root, "qml", "js", file), "utf8").replace(".pragma library", "");
  const module = { exports: {} };
  new Function("module", src)(module);
  return module.exports;
}
const C = load("Clips.js");
const S = load("Schema.js");

let failed = 0, passed = 0;
function test(name, fn) {
  try { fn(); passed++; console.log("  ok   " + name); }
  catch (e) { failed++; console.log("  FAIL " + name + "\n       " + e.message); }
}
const IMG = "/home/u/.local/state/omarchy-clipscape/images";
const DIR = IMG;
const t = (text, extra) => C.normalize(Object.assign({ kind: "text", text: text, at: 1000 }, extra || {}), DIR, 5000);

test("classify", () => {
  const cases = {
    "https://github.com/qempexe": "link", "www.omarchy.org/x": "link", "a@b.io": "email", "mailto:a@b.io": "email",
    "#fff": "color", "#d4a35a": "color", "#d4a35a80": "color", "rgb(1, 2, 3)": "color", "hsl(120 50% 50%)": "color",
    "42": "number", "-3.14": "number", "1,299.99": "number",
    "file:///home/a/b.png": "files", "file:///a\nfile:///b%20c": "files",
    "const x = () => { return 1; }": "code", "import os\nprint(os.getcwd())": "code",
    "hello world": "text", "Dear team,\nsee you tomorrow.": "text", "": "text"
  };
  for (const k in cases) assert.strictEqual(C.classify(k), cases[k], JSON.stringify(k));
});

test("file uris are decoded and anything else is not a file list", () => {
  assert.deepStrictEqual(C.fileUris("file:///a/b%20c.txt\nfile://localhost/d"), ["/a/b c.txt", "/d"]);
  assert.deepStrictEqual(C.fileUris("file:///a\nhttps://x"), []);
  assert.deepStrictEqual(C.fileUris("file://relative"), []);
});

test("secrets: tokens, keys, cards and passwords, never sentences or paths", () => {
  const yes = ["ghp_abcdefghijklmnopqrstuvwxyz0123456789", "github_pat_11ABCDEFG0123456789_abcdefghijklmnopqrstuvwxyz0123",
    "glpat-abcdefghij1234567890", "xoxb-123456789012-abcdefghij", "sk-proj-abcdefghijklmnopqrstuvwx", "sk_live_abcdefghijklmnop12",
    "AKIAIOSFODNN7EXAMPLE", "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U",
    "-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----", "4111 1111 1111 1111", "4111111111111111",
    "Hunter2!xx", "aB3dE5fG7hJ9kL1mN3pQ5rS7tV9wX1yZ"];
  const no = ["hello world", "4111 1111 1111 1112", "/home/u/Projects", "myVariableName", "https://example.com/?a=Bc1!",
    "a@b.io", "#d4a35a", "Password123 is not a good one", "0123456789abcdef0123456789abcdef", "README.md"];
  for (const s of yes) assert.notStrictEqual(C.secretKind(s), "", "should be secret: " + s);
  for (const s of no) assert.strictEqual(C.secretKind(s), "", "should not be secret: " + s);
});

test("normalize keeps what is valid and refuses the rest", () => {
  assert.strictEqual(C.normalize({ kind: "text", text: "   " }, DIR, 1), null);
  assert.strictEqual(C.normalize(null, DIR, 1), null);
  assert.strictEqual(C.normalize({ kind: "image", path: "/etc/passwd" }, DIR, 1), null);
  assert.strictEqual(C.normalize({ kind: "image", path: "/tmp/" + "a".repeat(64) + ".png" }, DIR, 1), null, "outside the images folder");
  const img = C.normalize({ kind: "image", path: DIR + "/" + "a".repeat(64) + ".png", mime: "text/html", w: -5 }, DIR, 1);
  assert.strictEqual(img.mime, "image/png");
  assert.strictEqual(img.w, 0);
  const c = t("x", { id: "../../etc", app: "fire\nfox", label: "a".repeat(200), pinned: "yes", uses: -4 });
  assert.notStrictEqual(c.id, "../../etc");
  assert.strictEqual(c.app, "fire fox");
  assert.strictEqual(c.label.length, 60);
  assert.strictEqual(c.pinned, false);
  assert.strictEqual(c.uses, 1);
});

test("parseStore drops duplicates and broken entries, and survives garbage", () => {
  const raw = JSON.stringify({ version: 1, clips: [{ kind: "text", text: "a", id: "x" }, { kind: "text", text: "a" }, { kind: "text", text: "b", id: "x" }, 7, "s"] });
  const list = C.parseStore(raw, DIR, 1);
  assert.deepStrictEqual(list.map(c => c.text), ["a", "b"]);
  assert.notStrictEqual(list[0].id, list[1].id);
  assert.deepStrictEqual(C.parseStore("not json", DIR, 1), []);
  assert.deepStrictEqual(C.parseStore("", DIR, 1), []);
});

test("add: newest on top, a copy again moves up and counts, pins and names stay", () => {
  let list = [t("a", { at: 1 }), t("b", { at: 2, pinned: true, pin: 1, label: "B" })];
  list = C.add(list, t("b", { at: 9, app: "kitty" }), 500);
  assert.deepStrictEqual(list.map(c => c.text), ["b", "a"]);
  assert.strictEqual(list[0].uses, 2);
  assert.strictEqual(list[0].pinned, true);
  assert.strictEqual(list[0].label, "B");
  assert.strictEqual(list[0].at, 2);
  assert.strictEqual(list[0].last, 9);
});

test("cap: pinned clips don't count and are never dropped", () => {
  let list = [];
  for (let i = 0; i < 5; i++) list.push(t("n" + i, { at: i }));
  list.push(t("p", { pinned: true, pin: 1 }));
  const out = C.cap(list, 2);
  assert.deepStrictEqual(out.map(c => c.text), ["n0", "n1", "p"]);
});

test("prune: forget after, secrets after, pinned stay", () => {
  const now = 10 * 86400000;
  const list = [t("old", { at: 0, last: 0 }), t("pinned", { at: 0, last: 0, pinned: true, pin: 1 }), t("new", { at: now, last: now }),
                t("secret", { at: now - 20 * 60000, last: now, secret: true })];
  const out = C.prune(list, 86400000, 10 * 60000, now);
  assert.deepStrictEqual(out.map(c => c.text), ["pinned", "new"]);
  assert.strictEqual(C.prune(list, 0, 0, now).length, 4);
});

test("pinning, moving pins, unpinning forgets the name", () => {
  let list = [t("a", { id: "a" }), t("b", { id: "b" }), t("c", { id: "c" })];
  list = C.setPinned(list, "a", true);
  list = C.setPinned(list, "c", true);
  assert.deepStrictEqual(list.filter(c => c.pinned).sort((x, y) => x.pin - y.pin).map(c => c.id), ["a", "c"]);
  list = C.movePin(list, "c", -1);
  assert.deepStrictEqual(list.filter(c => c.pinned).sort((x, y) => x.pin - y.pin).map(c => c.id), ["c", "a"]);
  list = C.update(list, "a", { label: "Name" });
  list = C.setPinned(list, "a", false);
  assert.strictEqual(C.byId(list, "a").label, "");
  assert.strictEqual(C.clearUnpinned(list).map(c => c.id).join(), "c");
});

test("search: words, fuzzy starts, tokens, filters, pinned first", () => {
  const list = [t("git status --short", { id: "g", app: "kitty" }), t("https://github.com/qempexe", { id: "l", app: "firefox" }),
                t("Meeting notes", { id: "m", pinned: true, pin: 1 }), t("#d4a35a", { id: "c" }),
                t("ghp_abcdefghijklmnopqrstuvwxyz0123456789", { id: "s", secret: true })];
  const ids = (q, f, p, r) => C.search(list, q, f || "all", p !== false, r).map(c => c.id);
  assert.deepStrictEqual(ids(""), ["m", "g", "l", "c", "s"]);
  assert.deepStrictEqual(ids("", "all", false), ["g", "l", "m", "c", "s"]);
  assert.deepStrictEqual(ids("gst"), ["g"]);
  assert.deepStrictEqual(ids("type:link"), ["l"]);
  assert.deepStrictEqual(ids("app:kit"), ["g"]);
  assert.deepStrictEqual(ids("is:pinned"), ["m"]);
  assert.deepStrictEqual(ids("", "color"), ["c"]);
  assert.deepStrictEqual(ids("", "pinned"), ["m"]);
  assert.deepStrictEqual(ids("ghp"), [], "a hidden secret is not searched");
  assert.deepStrictEqual(ids("ghp", "all", true, true), ["s"], "unless secrets are shown");
  assert.deepStrictEqual(ids("secret"), ["s"]);
  assert.deepStrictEqual(ids("zzzz"), []);
  const n = C.counts(list);
  assert.strictEqual(n.all, 5);
  assert.strictEqual(n.pinned, 1);
  assert.strictEqual(n.link, 1);
});

test("titles: names, masks, pictures, files", () => {
  assert.strictEqual(C.title(t("  first\nsecond")), "first");
  assert.strictEqual(C.title(t("x", { label: "Mine" })), "Mine");
  assert.ok(C.title(t("ghp_abcdefghijklmnopqrstuvwxyz0123456789", { secret: true }), true).indexOf("ghp") < 0);
  assert.strictEqual(C.title(t("file:///a/b.txt")), "b.txt");
  assert.strictEqual(C.title(t("file:///a/1\nfile:///a/2")), "2 files: 1, 2");
  const img = C.normalize({ kind: "image", path: DIR + "/" + "b".repeat(64) + ".png", mime: "image/png", w: 10, h: 20 }, DIR, 1);
  assert.strictEqual(C.title(img), "Image · 10 × 20 · PNG");
});

test("colors in three notations", () => {
  assert.deepStrictEqual(C.colorInfo("#f80"), { hex: "#ff8800", alpha: 1, rgb: "rgb(255, 136, 0)", hsl: "hsl(32, 100%, 50%)" });
  assert.strictEqual(C.colorInfo("hsl(120, 50%, 50%)").hex, "#40bf40");
  assert.strictEqual(C.colorInfo("rgba(0, 0, 0, 0.5)").alpha, 0.5);
  assert.strictEqual(C.colorInfo("red"), null);
});

test("transforms", () => {
  assert.strictEqual(C.transform("upper", "ab"), "AB");
  assert.strictEqual(C.transform("title", "hello wORLD-foo"), "Hello World-Foo");
  assert.strictEqual(C.transform("squash", " a \n\n b "), "a b");
  assert.strictEqual(C.transform("unique", "a\nb\na"), "a\nb");
  assert.strictEqual(C.transform("jsonPretty", '{"a":1}'), '{\n  "a": 1\n}');
  assert.strictEqual(C.transform("jsonPretty", "nope"), null);
  assert.strictEqual(C.transform("urlDecode", "a%20b+c"), "a b c");
  assert.strictEqual(C.transform("b64Encode", "héllo ✓"), "aMOpbGxvIOKckw==");
  assert.strictEqual(C.transform("b64Decode", "aMOpbGxvIOKckw=="), "héllo ✓");
  assert.strictEqual(C.transform("b64Decode", "!!"), null);
  assert.strictEqual(C.transform("markdownLink", "https://www.omarchy.org/"), "[omarchy.org](https://www.omarchy.org/)");
  assert.strictEqual(C.transform("nope", "x"), null);
});

test("joining marked clips", () => {
  const a = t("a"), b = t("b");
  assert.strictEqual(C.joined([a, b], "newline"), "a\nb");
  assert.strictEqual(C.joined([a, b], "space"), "a b");
  assert.strictEqual(C.joined([a, b], "none"), "ab");
});

test("settings are cleaned", () => {
  const cfg = S.resolve({ historyLimit: "999999", keepFor: "forever", images: "false", customBg: "red", skipApps: "a\u0000b", colorMode: "x" });
  assert.strictEqual(cfg.historyLimit, 2000);
  assert.strictEqual(cfg.keepFor, "never");
  assert.strictEqual(cfg.images, false);
  assert.strictEqual(cfg.customBg, "#141414");
  assert.strictEqual(cfg.skipApps, "a b");
  assert.strictEqual(cfg.colorMode, "theme");
  assert.strictEqual(S.resolve({ skipApps: "" }).skipApps, "", "an empty skip list stays empty");
  assert.deepStrictEqual(S.skipList(" KeePassXC, ,1Password "), ["keepassxc", "1password"]);
  assert.strictEqual(S.keepMs({ keepFor: "day" }), 86400000);
  for (const g of S.groups) for (const it of g.items) {
    assert.ok(it.hint && it.label, it.key + " has a label and a hint");
    if (it.kind === "enum") assert.ok(it.options.indexOf(it.fallback) >= 0, it.key + " default is an option");
    if (it.kind === "int") assert.ok(it.fallback >= it.min && it.fallback <= it.max, it.key + " default in range");
  }
});

test("manifest", () => {
  const m = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"));
  assert.strictEqual(m.id, "io.github.qempexe.clipscape");
  assert.ok(/^\d+\.\d+\.\d+$/.test(m.version));
  assert.strictEqual(m.omarchy.clonedFrom, "omarchy.clipboard");
  for (const k in m.entryPoints) assert.ok(fs.existsSync(path.join(root, m.entryPoints[k])), m.entryPoints[k] + " exists");
});

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
