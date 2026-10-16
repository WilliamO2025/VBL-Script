# VBL Script

A new standalone Drawing-based GUI with Ball, Movement, Prediction, LOS, Assist, and Settings pages.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/WilliamO2025/VBL-Script/main/ball-resizer.lua"))()
```

Open the menu with **F1**, or your saved menu key. Start in a fresh script session if the previous ball-resizer-only version is still running.

## Implemented behavior

- Ball resizing: 0.1–30 studs; updates live `CLIENT_BALL_` models and replicated ball templates. Disabling or stopping restores recorded sizes where the parts still exist.
- Jump rotation: Snap once at takeoff, or Free while airborne, facing away from the camera. **Requires writable `BasePart.CFrame`. This is not verified on Matcha; the control reports unavailability and disables itself if the API is missing.**
- Ball prediction: estimates landing from sampled motion, configurable gravity and court-floor Y, line or arrow trajectories, and a landing circle. Defaults of gravity 17 and floor Y -5 come from the older original source; adjust for the current game. Predictions ignore bounces and special ability changes.
- LOS: local, teammate, and opponent facing arrows, with configurable length, thickness, and colors. As in the older source, this means facing direction, not a wall-occlusion test. **Requires readable `BasePart.CFrame`; unsupported runtimes show a message.**
- Auto set/receive: presses Q (rebindable) when a live ball enters the selected distance; configurable cooldown. It pauses with the menu open or Roblox unfocused. No automatic walking.
- Settings: rebindable menu key, colors, validated JSON configuration, autosave, Save, and Reset. Legacy Luna size/key preferences are imported when no new config exists.
- Stop releases injected keys, restores recorded sizes, and removes this script's drawings. A repeated run replaces this version when the runtime shares `_G`.

## Validation and limits

This is a readable reimplementation based on the screenshots and an inspected older revision, **not a complete unpacking or safety certification of the current obfuscated vbl.lua**. Full compatibility with the current Matcha/game build is not established. In particular, rotation and LOS need a verified runtime adapter before they can be considered supported on Matcha versions without BasePart.CFrame.

Local tests use a simulated Lua environment. They cover all six menu pages, configuration validation and saving, menu-key changes and cancellation, ball restoration, automatic key release and focus handling, prediction math, rotation capability handling, and cleanup. These tests do not establish in-game behavior.

The script makes no network requests, loads no further code, and uses no raw memory access. It writes only `vbl_script_config.json` and reads that file plus the named legacy Luna preference files. No claim is made about the safety of the host executor/runtime.

Feature references: [0x1cx original, April 3 revision](https://github.com/0x1cx/random-lua/blob/a46fe389f772d5a56c1868673a2d3500e03ad3ea/matcha-supported/vbl.lua), [Luna ball resizer](https://github.com/Luna7070/585438). Original hitbox credit: huss.

