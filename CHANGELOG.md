# Changelog

All notable changes to Clipscape. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-10-29

### Added

- Clipboard history that stands in for Omarchy's own: **Super+Ctrl+V** and Clipboard in
  the Omarchy menu open Clipscape's picker. The history Omarchy kept is brought in the
  first time, pictures too.
- Text, links, emails, numbers, code, colors, copied files and pictures, each with an
  icon, a thumbnail or a swatch, and filters for each kind.
- Search as you type, with first-letter matches and `is:pinned`, `type:` and `app:`.
- A preview of the whole clip: the text, the picture, a color in hex, rgb and hsl, the
  files, and where and when it was copied.
- Pins in your own order, with names, that never expire and survive clearing.
- Marking several clips and pasting them together; editing a clip and keeping the edit
  as a new one; sixteen transforms; typing a clip out; Alt+1 to Alt+9.
- Pasting into the window you came from with Shift+Insert, Ctrl+V or Ctrl+Shift+V.
- Privacy: copies marked secret by a password manager are never kept, apps you list are
  skipped, clips that look like passwords, tokens, keys or card numbers are hidden and
  forgotten, a pasted secret can be cleared from the clipboard, and recording can be
  paused.
- A bar button and a panel, docked or popped out, with the history and every setting:
  color schemes (Follow theme, Window borders, Custom, Monochrome), row style, spacing,
  roundness, text size, the window outline, tint and opacity, and a search box over
  every tab. An About tab with the version.
- ipc: `picker`, `panel`, `settings`, `copy`, `paste`, `pause`, `resume`, `togglePause`,
  `clear` and `status`.
- Tests: `node tests/test_model.js` and `python3 tests/test_helper.py`.

[1.0.0]: https://github.com/qempexe/omarchy-clipscape/releases/tag/v1.0.0
