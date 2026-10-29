# Contributing

Clipscape is small: one list of settings, one file of pure logic, one helper, and the
QML that shows them. Most changes touch one or two files.

```
qml/Service.qml           settings, colors, the theme's window border, ipc
qml/Picker.qml            the picker on Super+Ctrl+V
qml/BarWidget.qml         the bar button, docking and popping out
qml/core/ClipStore.qml    the history: reading and writing it, the watcher, putting a
                          clip back on the clipboard (the only writer of history.json)
qml/core/UiState.qml      colors, spacing and the open tab, shared by every window (`ui.*`)
qml/picker/ClipView.qml   search, the list, the preview, the keys; the picker and the
                          panel's Clips tab are both this view
qml/js/Clips.js           pure logic: kinds, secrets, search, transforms, keeping
qml/js/Schema.js          every setting, in the tabs and order the Settings tab shows them
bin/clipscape             the helper: capture, copy, gc, import, secure
```

## A new setting

1. Add it to a group in `qml/js/Schema.js`: a `key` that never changes once released, a
   `kind` (`bool`, `int`, `enum`, `string` or `palette`), a `label`, a `fallback` and a
   one-sentence `hint`. An `int` takes `min`, `max` and `step`; an `enum` takes
   `options` and `labels`, and `control: "tiles"` to draw it as tiles (add its picture
   to `qml/panel/TileArt.qml`). `section` puts it under a heading, `when` dims it unless
   another setting has one of the given values.
2. Read it as `cfg.<key>`. The value is already clean (`Schema.resolve`).

## A new kind, filter or transform

- A kind is decided by `classify()` in `qml/js/Clips.js`; give it a name in `KIND_NAMES`
  and a glyph in `qml/picker/KindIcon.qml`, and a chip in `FILTERS` if it gets one.
- A transform is one entry in `TRANSFORMS`: a `key`, a `label`, and `run(text)` that
  returns the new text, or `null` when it doesn't apply.

## Rules

- `qml/js/Clips.js` and `qml/js/Schema.js` stay pure: no Qt, so the tests run in node.
- What is copied is read only by `bin/clipscape capture`, with a size limit and a time
  limit, and never when it is marked sensitive. Pictures go in Clipscape's own folder,
  named by their SHA-256, readable by you alone.
- `history.json` is written only by `ClipStore.qml`. The helper reads it, and only
  copies a picture that is a regular file in the images folder.
- Clip contents never go on a command line: back to the clipboard through `wl-copy`'s
  stdin, typed out through `wtype -`'s stdin. Commands are argument arrays.
- Clips are shown as plain text (`controls/Txt.qml`), and a text clip is edited in a
  plain text field.
- Links open through `xdg-open` only when they are http or https; a copied file is
  never opened, only its folder shown.
- ES6 JavaScript: `const` and `let`, and arrow functions for callbacks.

## Tests

```bash
node tests/test_model.js
python3 tests/test_helper.py -v
```

The first checks the kinds, the secrets, searching, keeping and forgetting, pins,
colors, transforms, the settings and the manifest. The second runs the helper against
fake `wl-paste`, `wl-copy`, `wtype` and `hyprctl` in a throwaway home folder: what is
captured and what is refused, the folder's modes, copying and the paste keys, that only
Clipscape's own pictures are copied, deleting unused pictures, and bringing in Omarchy's
history.

After installing a changed copy, run `omarchy restart shell`: the shell keeps the old
QML loaded otherwise.

Everyone taking part is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).
