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

## Legacy helper commands

Existing integrations can continue using:

    yoga-tablet status
    yoga-tablet toggle-lock
    yoga-tablet rotate next
    yoga-tablet osk toggle

These are compatibility entry points to the plugin-owned runtime.
