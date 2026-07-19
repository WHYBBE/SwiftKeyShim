# SwiftKeyShim

[中文说明](README.zh-CN.md)

> OpenCode vibe coding · ≤ `8aafdb1` GPT-5.5 · after that Grok 4.5

SwiftKeyShim is a small personal macOS menu bar app for a few specific keyboard remaps. It is built with Swift and SwiftUI for my own workflow, so it intentionally stays narrow instead of becoming a general-purpose remapper.

By default, tapping Left Shift sends F18. Holding Shift still works as a normal Shift modifier. Optionally, Escape and Caps Lock can be remapped independently (or swapped); on MacBook built-in keyboards the Caps Lock LED follows correctly.

![SwiftKeyShim English settings preview](docs/preview-en.png)

## Features

- Tap Left Shift to send F18 by default.
- Keep normal Shift behavior when the key is held.
- Choose Left Shift, Right Shift, or both Shift keys as the trigger.
- Send F17, F18, F19, or a custom macOS virtual key code.
- Adjust the tap/hold threshold.
- Optional **ESC → Caps Lock** and **Caps Lock → ESC**, each independently, or both for a full swap.
- Enable or disable remapping from the menu bar.
- Show abnormal status in the menu bar icon when remapping is enabled but the app is not listening correctly.
- Switch the app interface between English and Chinese.
- Start automatically at login.

## Requirements

- macOS 15.0 or later.
- Xcode for building from source.
- Accessibility permission for the Shift tap mapper (`CGEventTap`).
- ESC / Caps Lock remaps use system `hidutil` HID-layer `UserKeyMapping`; they are cleared when disabled or when the app quits.

## Usage

1. Open `SwiftKeyShim.xcodeproj` in Xcode.
2. Build and run the `SwiftKeyShim` scheme.
3. Grant Accessibility permission when macOS asks for it, or enable it manually in System Settings.
4. If you want F18 to switch input sources, set the input source shortcut to F18 in `System Settings -> Keyboard -> Keyboard Shortcuts -> Input Sources`.
5. Optionally enable ESC / Caps Lock remaps in Settings; each toggle is independent.
6. Use the menu bar icon to open settings, enable or disable remapping, configure launch at login, or quit the app.

## Build

```sh
xcodebuild -project SwiftKeyShim.xcodeproj -scheme SwiftKeyShim -configuration Debug -destination 'platform=macOS,arch=arm64' build
```

## How It Works

SwiftKeyShim uses **two different mechanisms** for different keys, instead of one technique for everything.

```
Physical keyboard
   │
   ▼
┌──────────────────────────────────┐
│  HID layer (hidutil UserKeyMapping) │  ← ESC / Caps Lock
│  Keycodes remapped very early       │
└──────────────────────────────────┘
   │
   ▼
┌──────────────────────────────────┐
│  CGEventTap (session layer)         │  ← Shift tap / hold
│  App-level intercept, suppress, inject │
└──────────────────────────────────┘
   │
   ▼
Apps / system receive final keys
```

### 1. ESC / Caps Lock: HID layer (`hidutil`)

Implemented in `HIDKeyMapper.swift`.

When the corresponding options are on, the app runs:

```sh
hidutil property --set '{"UserKeyMapping":[...]}'
```

and writes system `UserKeyMapping`. Keys are HID Keyboard usages (page `0x07`):

| Option | Mapping |
|--------|---------|
| Caps Lock → ESC | usage `0x39` → `0x29` |
| ESC → Caps Lock | usage `0x29` → `0x39` |
| Both enabled | swap |

Remapping happens **before** `CGEvent`: the system treats the physical key as the destination key. So:

- Physical Caps Lock mapped to ESC **does not toggle case lock**;
- On MacBook **built-in keyboards**, the Caps Lock **LED** is driven with HID/driver state and stays consistent with logical Caps Lock;
- The app does not need to synthesize Caps `flagsChanged` events or “repair” the LED afterward.

Turning off the master switch, turning off both options, or quitting the app writes an empty `UserKeyMapping` so the remap does not linger.

**Why not `CGEventTap` for Caps Lock?**  
On MacBook built-in keyboards, Caps Lock lock state and LED are often handled below the session event tap. Returning `nil` from a tap or posting synthetic Caps events commonly fails: LED still lights, lock still toggles, Escape injection is flaky. Remapping at the HID layer with `hidutil` is the most reliable lightweight approach for built-in hardware.

### 2. Shift: `CGEventTap` (session layer)

Implemented in `KeyboardRemapper.swift`.

Requires Accessibility. The tap listens for `keyDown` / `keyUp` / `flagsChanged` and only special-cases the configured Shift key(s); everything else passes through.

State machine (summary):

1. **Press** configured Shift: suppress the original `flagsChanged`, enter `pending`, start the tap timer (default ~160ms).
2. **Release within the threshold** with no other key activity: post target key (e.g. F18) down + up; the system never saw that Shift press.
3. **Timer fires**, or another `keyDown` / `flagsChanged` arrives while pending: promote to `held`, re-inject real Shift down, then behave as a normal modifier.
4. **Release while held**: post Shift up.

Synthetic events are tagged with `eventSourceUserData` so the callback ignores the app’s own posts and does not remapping them again.

**Why not `hidutil` for Shift?**  
`hidutil` only does static keycode swaps. It cannot implement “tap sends F18, hold is Shift, chords with other keys act as a modifier.” That needs session-level timing and context, which fits `CGEventTap`.

### 3. Permissions and lifecycle

| Feature | Mechanism | Permission / notes |
|---------|-----------|--------------------|
| ESC / Caps Lock | `hidutil` UserKeyMapping | Usually no Accessibility; cleared on quit |
| Shift tap | `CGEventTap` | Accessibility required |
| Settings change | `objectWillChange` → restart tap + refresh HID map | — |
| Quit | `AppDelegate` calls `stop()` | Clears HID map + tears down EventTap |

Inspect the current HID mapping:

```sh
hidutil property --get UserKeyMapping
```

## Notes

- The app runs as a menu bar utility and does not show a Dock icon.
- This is a personal app built around my own input-source and key layout habits. It may help others, but it is not meant to cover every remapping use case.
- I made this instead of continuing with Karabiner because Karabiner is very powerful but felt too heavy for this small need. I also hit unresolved bugs in my setup and was concerned about potential memory leak behavior.
- If remapping is enabled but Accessibility is missing or the event tap cannot run, the menu bar icon becomes `keyboard.badge.ellipsis`. HID ESC/Caps mappings may still be active in that case; Shift tap will not work.
- Launch at login uses `SMAppService.mainApp`, so behavior may differ between a build launched from Xcode and an app installed in `/Applications`.
- Other remappers (Karabiner, system modifier key settings, etc.) can conflict with this app’s `UserKeyMapping` or EventTap.

## License

SwiftKeyShim is released under the [MIT License](LICENSE).
