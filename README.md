# Caelestia Tablet Mode

Convertible-laptop support for Caelestia/Hyprland, packaged as one plugin.

It owns the complete Yoga tablet runtime:

- hinge-driven laptop/tablet mode
- accelerometer auto-rotation for the panel, touchscreen and pen
- rotation lock quick toggle
- on-screen keyboard and swipe handle
- live Caelestia keyboard theming
- plugin settings in **Nexus → Plugins → RotationLock (Tablet Mode)**

The daemon source, OSK shell and Caelestia integration all live in this
repository. `~/.local/bin/yoga-tablet` may exist as a compatibility symlink for
Hyprland keybinds and CLI use; it is not a second copy of the daemon.

## Install

Install from Caelestia's plugin manager with:

`https://github.com/dcqwqc/CaelestiaPlugin-TabletMode`

or clone it as:

```sh
git clone https://github.com/dcqwqc/CaelestiaPlugin-TabletMode \
  ~/.local/share/caelestia/plugins/tablet-mode
```

Enable `dcqwqc/rotationlock` in the Plugins page.

## Settings

The plugin stores user-facing configuration in
`~/.config/caelestia/plugins.json` under `dcqwqc/rotationlock`. The daemon reads
those values directly and reloads them live.

The old `~/.config/yoga-tablet/config.json` format is read only as a migration
fallback and is no longer written.

## CLI

```sh
yoga-tablet status
yoga-tablet toggle-lock
yoga-tablet rotate next
yoga-tablet osk toggle
```

## Licence

GPL-3.0-or-later.
