# RotationLock

Rotation lock for a convertible, as a Caelestia quick toggle.

The `yoga-tablet` daemon owns the lock, and other things flip it — a keybind,
folding the hinge — so this never caches a guess. It re-reads the daemon's state
whenever the toggle comes back on screen, and again after every write.

Where the daemon is not installed or not answering, the toggle hides itself
rather than sitting there dead. Nothing to configure.

## Requires

The `yoga-tablet` daemon from [kagami](https://github.com/dcqwqc/kagami).

## Status

Caelestia's plugin loader is not released yet — it lives on upstream's unmerged
`feat/plugins` branch, and the Plugins page there is a mockup rendering four
fake cards. So this needs a shell that carries the loader:

- **On upstream Caelestia**, wait for that branch to merge.
- **On a fork that has cherry-picked it** (`plugin/src/Caelestia/Plugins`, plus a
  Plugins page and the quick-toggle / bar-entry hooks), it loads and is managed
  from Nexus → Plugins today.

The manifest and entry points are built against that branch's own parser rather
than a guess at it, so the shape is the real one.

## Install

Clone into Caelestia's plugin directory:

    git clone https://github.com/dcqwqc/CaelestiaPlugin-RotationLock ~/.local/share/caelestia/plugins/rotation-lock

Or clone anywhere and add the parent to `path` in
`~/.config/caelestia/plugins.json`.

## Licence

GPL-3.0-or-later, matching Caelestia.
