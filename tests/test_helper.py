#!/usr/bin/env python3
"""The helper, bin/clipscape, against fake wl-paste, wl-copy, wtype and hyprctl in a
throwaway home folder:  python3 tests/test_helper.py -v"""
import json
import os
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HELPER = os.path.join(ROOT, "bin", "clipscape")

FAKES = {
    # the clipboard is $HOME/clip/data[.<type>], its types in $HOME/clip/types
    "wl-paste": r'''#!/bin/bash
D="$HOME/clip"; echo "wl-paste $*" >> "$D/log"; type=""
while (( $# > 0 )); do
  case "$1" in
    --list-types) cat "$D/types" 2>/dev/null; exit 0 ;;
    --type) type="$2"; shift 2 ;;
    *) shift ;;
  esac
done
f="$D/data"; [[ -n $type ]] && f="$D/data.$(echo "$type" | tr '/;=' '___')"; [[ -f $f ]] || f="$D/data"
cat "$f"
''',
    "wl-copy": '#!/bin/bash\nD="$HOME/clip"; echo "wl-copy $*" >> "$D/log"\n[[ $1 == --clear ]] && exit 0\ncat > "$D/copied"\n',
    "wtype": '#!/bin/bash\nD="$HOME/clip"; if [[ $1 == - ]]; then echo "wtype - $(cat)" >> "$D/log"; else echo "wtype $*" >> "$D/log"; fi\n',
    "hyprctl": '#!/bin/bash\ncat "$HOME/clip/app" 2>/dev/null || echo \'{"class": ""}\'\n',
}


def png(w, h):
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + b"\x10\x20\x30" * w for _ in range(h))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


class Helper(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = self.tmp.name
        self.clip = os.path.join(self.home, "clip")
        self.bin = os.path.join(self.home, "bin")
        os.makedirs(self.clip)
        os.makedirs(self.bin)
        for name, body in FAKES.items():
            p = os.path.join(self.bin, name)
            with open(p, "w") as f:
                f.write(body)
            os.chmod(p, 0o755)
        self.state = os.path.join(self.home, ".local", "state", "omarchy-clipscape")
        self.images = os.path.join(self.state, "images")

    def tearDown(self):
        self.tmp.cleanup()

    def put(self, name, data):
        with open(os.path.join(self.clip, name), "wb" if isinstance(data, bytes) else "w") as f:
            f.write(data)

    def run_helper(self, *args, env=None, stdin=""):
        e = {"HOME": self.home, "PATH": self.bin + ":/usr/bin:/bin", "LANG": "C.UTF-8"}
        e.update(env or {})
        return subprocess.run(["python3", HELPER] + list(args), env=e, input=stdin.encode(),
                              capture_output=True, timeout=30)

    def capture(self, *args, **kw):
        out = self.run_helper("capture", *args, **kw).stdout.decode().strip()
        return json.loads(out) if out else None

    def log(self):
        try:
            with open(os.path.join(self.clip, "log")) as f:
                return f.read()
        except FileNotFoundError:
            return ""

    # ---- capture -----------------------------------------------------------------------
    def test_text_and_its_app(self):
        self.put("types", "text/plain;charset=utf-8\ntext/plain\n")
        self.put("data", "hello ✓")
        self.put("app", '{"class": "firefox"}')
        c = self.capture()
        self.assertEqual(c["kind"], "text")
        self.assertEqual(c["text"], "hello ✓")
        self.assertEqual(c["app"], "firefox")

    def test_text_wins_over_a_picture_of_it(self):
        # spreadsheets offer a picture of the cells along with their text
        self.put("types", "image/png\ntext/plain\n")
        self.put("data", "A1\tB1")
        self.put("data.image_png", png(4, 4))
        self.assertEqual(self.capture()["kind"], "text")

    def test_picture(self):
        self.put("types", "image/png\n")
        self.put("data.image_png", png(7, 3))
        c = self.capture()
        self.assertEqual((c["kind"], c["w"], c["h"], c["mime"]), ("image", 7, 3, "image/png"))
        self.assertEqual(os.path.dirname(c["path"]), self.images)
        st = os.stat(c["path"])
        self.assertEqual(stat.S_IMODE(st.st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(os.stat(self.images).st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(os.stat(self.state).st_mode), 0o700)

    def test_pictures_off(self):
        self.put("types", "image/png\n")
        self.put("data.image_png", png(2, 2))
        self.assertIsNone(self.capture("--images", "0"))

    def test_marked_sensitive_is_never_kept(self):
        self.put("types", "text/plain\nx-kde-passwordManagerHint\n")
        self.put("data", "hunter2")
        self.assertIsNone(self.capture())
        self.put("types", "text/plain\n")
        self.assertIsNone(self.capture(env={"CLIPBOARD_STATE": "sensitive"}))
        self.assertIsNone(self.capture(env={"CLIPBOARD_STATE": "clear"}))

    def test_skipped_app(self):
        self.put("types", "text/plain\n")
        self.put("data", "secret")
        self.put("app", '{"class": "org.keepassxc.KeePassXC"}')
        self.assertIsNone(self.capture("--skip", "keepassxc,bitwarden"))
        self.assertIsNotNone(self.capture("--skip", "bitwarden"))

    def test_too_big(self):
        self.put("types", "text/plain\n")
        self.put("data", "x" * 5000)
        self.assertIsNone(self.capture("--max-text", "4096"))
        self.assertEqual(len(self.capture("--max-text", "8192")["text"]), 5000)

    def test_files_and_a_picture_file(self):
        pic = os.path.join(self.home, "shot.png")
        with open(pic, "wb") as f:
            f.write(png(2, 2))
        self.put("types", "text/uri-list\ntext/plain\n")
        self.put("data.text_uri-list", "file://" + pic + "\n")
        c = self.capture()
        self.assertTrue(c["text"].startswith("file://"))
        self.assertTrue(c.get("thumb"))
        self.put("data.text_uri-list", "file:///nowhere/x.png\n")
        self.assertNotIn("thumb", self.capture())

    def test_whitespace_only_is_dropped(self):
        self.put("types", "text/plain\n")
        self.put("data", "  \n\t")
        self.assertIsNone(self.capture())

    # ---- copy and paste ----------------------------------------------------------------
    def history(self, clips):
        os.makedirs(self.images, exist_ok=True)
        with open(os.path.join(self.state, "history.json"), "w") as f:
            json.dump({"version": 1, "clips": clips}, f)

    def test_copy_and_paste_keys(self):
        self.history([{"id": "a1", "kind": "text", "text": "two\nlines"}])
        self.assertEqual(self.run_helper("copy", "a1").returncode, 0)
        with open(os.path.join(self.clip, "copied")) as f:
            self.assertEqual(f.read(), "two\nlines")
        self.assertNotIn("wtype", self.log())
        self.run_helper("copy", "a1", "--paste", "shift-insert")
        self.assertIn("wtype -M shift -k Insert -m shift", self.log())
        self.run_helper("copy", "a1", "--paste", "ctrl-shift-v")
        self.assertIn("wtype -M ctrl -M shift -k v -m shift -m ctrl", self.log())
        self.run_helper("copy", "a1", "--paste", "type")
        self.assertIn("wtype - two\nlines", self.log())
        self.run_helper("copy", "a1", "--paste", "rm -rf")
        self.assertEqual(self.log().count("wtype"), 3, "unknown keys press nothing")

    def test_files_go_back_as_a_uri_list(self):
        self.history([{"id": "f1", "kind": "text", "text": "file:///a/b.txt\n"}])
        self.run_helper("copy", "f1")
        self.assertIn("wl-copy --type text/uri-list", self.log())

    def test_only_own_pictures_are_copied(self):
        good = os.path.join(self.images, "a" * 64 + ".png")
        self.history([{"id": "i1", "kind": "image", "path": good, "mime": "image/png"},
                      {"id": "i2", "kind": "image", "path": "/etc/hostname", "mime": "image/png"},
                      {"id": "i3", "kind": "image", "path": os.path.join(self.images, "b" * 64 + ".png"), "mime": "image/png"}])
        with open(good, "wb") as f:
            f.write(png(1, 1))
        os.symlink("/etc/hostname", os.path.join(self.images, "b" * 64 + ".png"))
        self.assertEqual(self.run_helper("copy", "i1").returncode, 0)
        self.assertIn("wl-copy --type image/png", self.log())
        self.assertEqual(self.run_helper("copy", "i2").returncode, 1)
        self.assertEqual(self.run_helper("copy", "i3").returncode, 1, "a link is not followed")

    def test_bad_ids(self):
        self.history([])
        self.assertEqual(self.run_helper("copy", "../../x").returncode, 2)
        self.assertEqual(self.run_helper("copy", "nope").returncode, 1)

    # ---- tidying -------------------------------------------------------------------------
    def test_gc_deletes_only_unused_pictures(self):
        keep = os.path.join(self.images, "a" * 64 + ".png")
        drop = os.path.join(self.images, "b" * 64 + ".png")
        other = os.path.join(self.images, "notes.txt")
        link = os.path.join(self.images, "c" * 64 + ".png")
        self.history([{"id": "i1", "kind": "image", "path": keep}])
        for p in (keep, drop, other):
            open(p, "w").close()
        os.symlink(os.path.join(self.home, "clip", "log"), link)
        out = json.loads(self.run_helper("gc").stdout)
        self.assertEqual(out["removed"], 1)
        self.assertTrue(os.path.exists(keep) and os.path.exists(other) and os.path.lexists(link))
        self.assertFalse(os.path.exists(drop))

    def test_import_from_omarchy(self):
        odir = os.path.join(self.home, ".local", "state", "omarchy")
        oimg = os.path.join(odir, "clipboard-images")
        os.makedirs(oimg)
        with open(os.path.join(oimg, "x.png"), "wb") as f:
            f.write(png(5, 6))
        with open(os.path.join(odir, "clipboard-history.json"), "w") as f:
            json.dump([{"type": "text", "text": "newest"}, "plain string",
                       {"type": "image", "path": os.path.join(oimg, "x.png"), "mime": "image/png"},
                       {"type": "image", "path": "/etc/hostname", "mime": "image/png"},
                       {"type": "text", "text": "  "}], f)
        out = json.loads(self.run_helper("import").stdout)
        self.assertEqual([c.get("text", c["kind"]) for c in out], ["newest", "plain string", "image"])
        self.assertEqual(os.path.dirname(out[2]["path"]), self.images)
        self.assertEqual((out[2]["w"], out[2]["h"]), (5, 6))
        self.assertGreater(out[0]["at"], out[1]["at"])

    def test_import_without_history(self):
        self.assertEqual(json.loads(self.run_helper("import").stdout), [])

    def test_secure(self):
        os.makedirs(self.images)
        os.chmod(self.state, 0o755)
        p = os.path.join(self.state, "history.json")
        open(p, "w").close()
        os.chmod(p, 0o644)
        self.run_helper("secure")
        self.assertEqual(stat.S_IMODE(os.stat(self.state).st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(os.stat(p).st_mode), 0o600)


if __name__ == "__main__":
    unittest.main()
