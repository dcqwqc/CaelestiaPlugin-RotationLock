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

The normal layer keeps desktop essentials such as Esc, Ctrl, Alt, Super and Tab,
while navigation keys, Insert/Delete and F1-F12 live on the desktop layer. A
compact icon row stays visible for the whole lifetime of the OSK and switches
between keyboard, clipboard, emoji, desktop controls and Protocol7 dictation
history. The microphone is an action rather than a mode, so starting or stopping
Protocol7 does not dismiss the keyboard or replace the current panel.

Clipboard, emoji and dictation history are full keyboard-area panels: native
keys are completely covered while the panel is open. Clipboard history is
searchable and uses `cliphist`; dictation history reads Protocol7's existing
`~/.config/protocol-7/history.json` rather than creating another database. The
emoji browser searches the local Noctalia emoji catalogue (currently 1,913
entries), exposes category filters and loads additional pages while scrolling.
Each search field has its own touch keyboard, so filtering does not require a
physical keyboard. Clipboard and history text are passed only through argv/stdin
helpers and are never evaluated as shell commands.

Glide typing records the actual touch trajectory instead of merely collecting
the keys crossed by the finger. wvkbd draws a continuous anti-aliased trail and
sends a bounded `(x, y, time)` trace plus the live key-centre geometry to an
asynchronous decoder. The decoder uniformly resamples the path, creates ideal
word traces from the current keyboard geometry, prunes by start/end anchors and
combines shape, location, path-length, corner/order and repeated-letter evidence.
This is an original compact implementation informed by the SHARK2 family and the
open geometric architecture used by CleverKeys; it does not depend on Android or
a proprietary swipe library. German and English use local hunspell dictionaries
when present and fall back to the tracked compact lexicon. Long-press alternates
and primary-touch ownership remain active.

## Legacy helper commands

Existing integrations can continue using:

    yoga-tablet status
    yoga-tablet toggle-lock
    yoga-tablet rotate next
    yoga-tablet osk toggle

These are compatibility entry points to the plugin-owned runtime.
