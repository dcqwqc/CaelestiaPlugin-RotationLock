# Caelestia Tablet Mode

Convertible-laptop support for Caelestia and Hyprland.

The plugin provides:

- tablet-mode state integration for foldable/convertible hardware
- accelerometer-driven auto-rotation through all four orientations
- matching touchscreen and pen transforms
- rotation lock
- an on-screen keyboard and tablet-mode input handling
- optional disabling of physical keyboard/touchpad input while folded

Hardware selection is not tied to a particular laptop model. The runtime discovers the internal display from common internal-panel connector types and uses Hyprland's main-keyboard and touchpad device information instead of vendor-specific input names.

## Compatibility names

The historical helper executable is named `yoga-tablet`, and older installations may have state under `~/.config/yoga-tablet`. Those names are retained for compatibility only; the plugin is not restricted to Lenovo Yoga hardware.

## Configuration

Use the Caelestia Plugins page for rotation thresholds, auto-rotation, rotation lock behavior, on-screen keyboard options, and folded-input policy. A specific monitor can be selected where automatic internal-panel detection is not suitable.

## Keyboard

TabletMode builds its keyboard from the tracked `vendor/wvkbd` source; no copy
from a cache directory is required. Install it for the current user with:

    ./scripts/build-wvkbd

The normal layer is deliberately sparse and touch-friendly: letters, numbers,
and explicit Esc, Ctrl, Alt, Super, and Tab stay available while arrows,
navigation keys, Insert/Delete, and F1–F12 live in the Tools layer. A compact
top row is part of the keyboard's own exclusive-zone footprint and provides
Keyboard, Clipboard, Emoji, Tools, Protocol7, and Hide controls.

Clipboard history is available only with `cliphist`, `wl-paste`, `wl-copy`, and
`wtype`; it displays at most eight entries and passes selected bytes directly
to `wl-copy`, never through a shell. Emoji uses `wtype` and the installed emoji
font fallback. Protocol7 currently exports no dictation IPC method, so its
button injects the configured physical hotkey through `ydotool` as a
compatibility bridge.

Glide typing captures a drag over alphabetic keys without emitting the crossed
letters. The plugin-owned decoder scores local German/English hunspell
dictionaries (or its compact fallback lexicon) outside the keyboard process
and inserts one predicted word. It only enables when the vendored keyboard,
decoder, lexicon, and `wtype` validation succeed; otherwise ordinary taps are
unchanged. Long-pressing a, o, u, s, e, period, hyphen, or apostrophe emits a
useful German/Latin alternate.

## Legacy helper commands

Existing integrations can continue using:

    yoga-tablet status
    yoga-tablet toggle-lock
    yoga-tablet rotate next
    yoga-tablet osk toggle

These are compatibility entry points to the plugin-owned runtime.
