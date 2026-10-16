# VBL Script

A standalone Drawing-based GUI with Ball, Character, Movement, Prediction, LOS, Assist, Counter, and Settings pages.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/WilliamO2025/VBL-Script/main/ball-resizer.lua"))()
```

Open the menu with **F1**, or your saved menu key. Start in a fresh script session if the previous ball-resizer-only version is still running.

The menu leaves game input enabled, so you can move your character and interact with the game while it is open. Mouse clicks on the overlay may also reach the game.

## Implemented behavior

- Ball resizing: 0.1–30 studs; updates live `CLIENT_BALL_` models and replicated ball templates. Disabling or stopping restores recorded sizes where the parts still exist.
- Character receive-hitbox resizer: scales identified `ReceiveHitbox`, `ReceiverHitbox`, `ReceivingHitbox`, `BumpHitbox`, or `Hitbox` parts directly under Receive/Receiving/Bump containers inside your character. The Character page reports how many were found. Scaling is relative to the original size, from 1x to 5x; disable or Stop restores it. This does not resize body parts or create a receive mechanism. If the game exposes no such part, resizing is unavailable. Server-calculated receive range may remain unchanged.
- Jump rotation: Snap once per grounded-to-airborne takeoff, or rate-limited Free turns while airborne, facing away from the camera. Landing, losing focus, opening the menu, disabling rotation, and Stop restore the humanoid's original AutoRotate value when that property is supported. Rotation uses freshly read frame position and never writes velocity. **Requires writable `BasePart.CFrame` and ground-contact detection. In-game behavior remains unverified.**
- Ball prediction: estimates landing from sampled motion, configurable gravity and court-floor Y, line or arrow trajectories, and a landing circle. Defaults of gravity 17 and floor Y -5 come from the older original source; adjust for the current game. Predictions ignore bounces and special ability changes.
- LOS: local, teammate, and opponent facing arrows, with configurable length, thickness, and colors. As in the older source, this means facing direction, not a wall-occlusion test. **Requires readable `BasePart.CFrame`; unsupported runtimes show a message.**
- Auto receive: grounded-only, with selectable **Set (Q/custom key)** or **Bump (left click)**. Set remains the default to preserve previous behavior. Requires fresh consistent ball-motion samples, an approaching path that passes through your reach, and a cooldown. Stationary, outgoing, and glancing paths are rejected. One representative part per live ball prevents duplicate inputs; another input is allowed only after the ball has departed beyond the interaction area. This conservative rule can miss rapid close-range returns. Ground detection uses FloorMaterial or the filtered foot probe; unknown contact pauses receiving.
- Experimental counter-spike: enable on **Counter**, close the menu, jump and **hold E** (rebindable). Aim manually. It clicks once when a fast approaching ball is near your upper body. Reach, minimum speed, and prediction lead are adjustable; defaults are 4 studs, 25 studs/s, and 40 ms. The lead extrapolates current motion; it is not a measured server tick or latency compensation. It cannot identify the last hitter or distinguish an enemy spike from another incoming ball. No perfect-hit guarantee; in-game tuning is required. It shares the Assist cooldown and per-ball latch with receiving.
- Both assists pause with the menu open or Roblox unfocused and release their owned inputs on state changes or Stop. No automatic movement or jumping. Mouse assist requires `mouse1press` and `mouse1release` support.
- Settings: rebindable menu key, colors, validated JSON configuration, autosave, Save, and Reset. Legacy Luna size/key preferences are imported when no new config exists.
- Stop releases injected keys, restores recorded sizes, and removes this script's drawings. A repeated run replaces this version when the runtime shares `_G`.

## Validation and limits

This is a readable reimplementation based on the screenshots and an inspected older revision, **not a complete unpacking or safety certification of the current obfuscated vbl.lua**. Full compatibility with the current Matcha/game build is not established. In particular, rotation and LOS need a verified runtime adapter before they can be considered supported on Matcha versions without BasePart.CFrame.

Local tests use a simulated Lua environment. They cover all eight menu pages, configuration validation and saving, menu-key changes and cancellation, game input passthrough, ball and receive-hitbox restoration, grounded/apex/freefall/unknown-contact receive gating, filtered raycast fallback, automatic key release, Snap/Free rotation transitions, landing at a different height, focus restoration, prediction math, capability handling, and cleanup. These tests do not establish in-game behavior.

The script makes no network requests, loads no further code, and uses no raw memory access. It writes only `vbl_script_config.json` and reads that file plus the named legacy Luna preference files. No claim is made about the safety of the host executor/runtime.

Feature references: [0x1cx original, April 3 revision](https://github.com/0x1cx/random-lua/blob/a46fe389f772d5a56c1868673a2d3500e03ad3ea/matcha-supported/vbl.lua), [Luna ball resizer](https://github.com/Luna7070/585438). Original hitbox credit: huss.

## Counter-spike research

The [official game controls](https://www.roblox.com/games/73956553001240/Volleyball-Legends) specify click for bump/spike and Q for set/block. The description of [Its_ Dgann�s counter-spike tutorial](https://www.youtube.com/watch?v=kG2goB34W9U) describes spiking an opponent�s spike back and distinguishes normal, front-tilt, and glide counters. Only the indexed description was accessible; the video was not watched. No verified universal one-tick perfect-hit window was found.

Additional simulated tests cover stationary/outgoing/missed approaches, one input per pass, held-user-input protection, bump mouse release on focus loss, and airborne/armed/height gating for counter assist. They do not validate actual game hit registration or timing.