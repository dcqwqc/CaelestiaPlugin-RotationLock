# Vendored wvkbd

This directory tracks the source used for TabletMode's `wvkbd-mobintl` build.
It is based on [jjsullivan5196/wvkbd](https://github.com/jjsullivan5196/wvkbd),
release **v0.20** (the upstream `config.mk` and `CHANGELOG.md` identify the
snapshot). It was imported as source, without build outputs.

Upstream copyright and licence notices are retained verbatim in `COPYING`,
`LICENSE`, and `COPYING_WESTON`. wvkbd itself is GPL-3.0-only; the Wayland
compatibility files retain their upstream MIT/X licence notice. Any
redistribution of this plugin must preserve those notices and meet the GPL-3.0
requirements for this vendored derivative.

TabletMode-local changes are deliberately contained here:

- tablet spacing and a blank first row for the companion toolbar;
- an uncluttered typing layer and separate desktop/tools layer;
- `--glide-fd`, layer-control signals, long-press alternates, and primary-touch
  ownership.

Run `scripts/build-wvkbd` from this plugin to reproduce the installed binary.
