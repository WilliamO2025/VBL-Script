# VBL Script

## v6 rotation regression fix

The earlier saved working implementation (`work/published-v3.lua`) used a writable CFrame and upward velocity, without requiring ground APIs or a readable LookVector. Later changes introduced those extra requirements. v6 removes that regression: when contact is unavailable, rotation activates on upward velocity crossing 5 studs/s and stops at the apex. Auto receive still requires verified ground contact. Snap writes once; Free remains rate limited. Missing frame Position/LookVector members are tolerated, and immediate readback no longer disables rotation because external reads may lag. Existing saved OFF settings are preserved: enable Jump rotation after reloading. The menu shows SCRIPT / 06.

Simulated tests cover unavailable ground APIs and frame members, one-shot Snap, apex cleanup and no falling writes. In-game verification is still needed. The CFrame property itself must remain writable, as in the earlier implementation.

## v5 update (historical)

- Ball page now labels the resizer **Ball hitbox extender** and reports verified size writes and failures for live parts and templates. This changes local ball part dimensions; it does not prove the server accepts a larger hit radius. Character receive-part resizing remains available separately.
- Added **Ball tracker** (marker, distance, measured speed) and **Incoming indicator** (approaching/moving away relative to character motion). These use the same sampled motion as prediction. Approaching is a direction indicator, not a guaranteed collision or enemy attack.
- Fixed missed jump activation when ground contact changes a frame before upward velocity. The takeoff window expires after 0.2 seconds so a later upward change does not trigger a stale jump.
- Movement now shows rotation diagnostics and ground-contact status. Rotation writes are read back and checked instead of assuming a successful assignment changed orientation. Errors are also printed with a `[VBL] Jump rotation:` prefix.
- **Rotation compatibility is still unresolved on Matcha builds without writable BasePart.CFrame.** The inspected original uses old hard-coded memory offsets; those are not verified for the current build and have not been copied. This release is not a claim that rotation now works in every runtime.
- Simulated regression tests pass, including delayed takeoff, expired takeoff, tracker speed/direction and drawing cleanup. No live game validation was available.

Runtime references reviewed: [Matcha classes](https://huoadf.github.io/matcha-docs/classes/) and [Wabi Matcha classes](https://doc.wabisabi.mom/matcha/classes/). Both list BasePart size/position/velocity, but neither lists BasePart.CFrame. Documentation absence is a compatibility warning, not proof of the capability of a particular installed build.

A standalone Drawing-based GUI with Ball, Character, Movement, Prediction, LOS, Assist, Counter, Match, and Settings pages.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/WilliamO2025/VBL-Script/main/ball-resizer.lua"))()
```

Open the menu with **F1**, or your saved menu key. Start in a fresh script session if the previous ball-resizer-only version is still running.

The menu leaves game input enabled, so you can move your character and interact with the game while it is open. Mouse clicks on the overlay may also reach the game.

## Implemented behavior

- Ball resizing: 0.1–30 studs; updates live `CLIENT_BALL_` models and replicated ball templates. Disabling or stopping restores recorded sizes where the parts still exist.
- Character receive-hitbox resizer: scales identified `ReceiveHitbox`, `ReceiverHitbox`, `ReceivingHitbox`, `BumpHitbox`, or `Hitbox` parts directly under Receive/Receiving/Bump containers inside your character. The Character page reports how many were found. Scaling is relative to the original size, from 1x to 5x; disable or Stop restores it. This does not resize body parts or create a receive mechanism. If the game exposes no such part, resizing is unavailable. Server-calculated receive range may remain unchanged.
- Jump rotation: Snap once per grounded-to-airborne takeoff, or rate-limited Free turns while airborne, facing away from the camera. Landing, losing focus, opening the menu, disabling rotation, and Stop restore the humanoid's original AutoRotate value when that property is supported. Rotation uses freshly read frame position and never writes velocity. **Requires writable `BasePart.CFrame`. When ground detection is unavailable, rotation uses upward velocity and finishes at the apex; auto receive does not use that fallback. In-game behavior remains unverified.**
- Ball prediction: estimates landing from sampled motion, configurable gravity and court-floor Y, line or arrow trajectories, and a landing circle. Defaults of gravity 17 and floor Y -5 come from the older original source; adjust for the current game. Predictions ignore bounces and special ability changes.
- LOS: local, teammate, and opponent facing arrows, with configurable length, thickness, and colors. As in the older source, this means facing direction, not a wall-occlusion test. **Requires readable `BasePart.CFrame`; unsupported runtimes show a message.**
- Auto receive: grounded only. Fresh installs default to **Bump (left click)**; **Set (Q/custom key)** is also available. Existing saved action choices are preserved. The default **Serves / spikes** filter requires a resolved opposing last hitter and either a likely serve or a fast non-rising attack. **Enemy returns** also permits softer opposing returns. Your own and teammate touches never trigger it. Ground contact uses FloorMaterial or the filtered foot probe; unknown contact pauses receiving.
- Counter-spike: enable on **Counter** and choose **Always**, **Toggle**, or **Hold**. Always needs no arm key. Toggle switches the feature on/off with E or your chosen binding. Hold requires the chosen key while enabled. Jump and aim manually; counters require an airborne character and a predicted incoming enemy fast attack, excluding likely serves. Reach, speed threshold, and lead are adjustable. Counter input is evaluated every frame from the first valid motion interval; it does not wait through the receive cooldown. This is still experimental and does not guarantee perfect hits.
- Keybinds accept **Mouse 4 / Mouse 5** (Windows VK 0x05 / 0x06) for menu, counter, and custom set bindings. Click Rebind, then press the side button. Escape cancels. Toggle edges are suppressed while the menu is open or the game is unfocused. If the counter key equals the menu key, the menu takes priority; choose distinct keys.
- Shared ball prediction: both drawings and assists use the same measured motion and configurable gravity. Contact prediction accounts for your character's velocity and checks the path through the reach area, including fast shots that cross it between frames. The default counter lead is 40 ms; this is a tuning value, not a measured server tick or ping correction. Invalid, stale, outgoing, and missed paths are rejected. A per-ball latch prevents repeats; a changed hitter/serve or a departed ball can rearm it for a new approach. Live-ball discovery runs every 0.1 seconds.
- Match page: displays your team, LastHitter, the hitter's team, ServedByPlayer, inferred shot category, attack speed threshold, and pause reason. Attributes are read from ReplicatedStorage, as in the statically inspected older source. Hitters resolve by exact player name or user ID; teams use Player.Team.Name, then ReplicatedStorage/PlayerInfo/<name>/Team.Value. Missing/unsupported data pauses both assists. These global hit attributes are used only with exactly one detected live ball, to avoid assigning one ball's hitter to another.
- Serve/spike categories are **estimates**: matching server and hitter implies a likely serve until a different hitter is observed. A fast non-rising trajectory implies an attack. No verified shot-type field was found. The server marker can persist across a rally; it is not treated as an ongoing serve after an intervening touch. Joining mid-rally, missing touch updates, repeated serves by the same player without marker changes, and special abilities can defeat this inference. The filter may skip valid shots or misclassify them.
- Both assists pause with the menu open or Roblox unfocused and release owned inputs on state changes, teammate touches, missing team data, or Stop. No automatic movement or jumping. Mouse assist requires mouse1press and mouse1release support.
- Settings: rebindable menu key, colors, validated JSON configuration, autosave, Save, and Reset. Legacy Luna size/key preferences are imported when no new config exists.
- Stop releases injected keys, restores recorded sizes, and removes this script's drawings. A repeated run replaces this version when the runtime shares `_G`.

## Validation and limits

This is a readable reimplementation based on the screenshots and an inspected older revision, **not a complete unpacking or safety certification of the current obfuscated vbl.lua**. Full compatibility with the current Matcha/game build is not established. In particular, rotation and LOS need a verified runtime adapter before they can be considered supported on Matcha versions without BasePart.CFrame.

Local tests use a simulated Lua environment. They cover all nine menu pages, configuration validation and saving, menu-key changes and cancellation, game input passthrough, ball and receive-hitbox restoration, grounded/apex/freefall/unknown-contact receive gating, filtered raycast fallback, automatic key release, Snap/Free rotation transitions, landing at a different height, focus restoration, prediction math, capability handling, and cleanup. These tests do not establish in-game behavior.

The script makes no network requests, loads no further code, and uses no raw memory access. It writes only `vbl_script_config.json` and reads that file plus the named legacy Luna preference files. No claim is made about the safety of the host executor/runtime.

Feature references: [0x1cx original, April 3 revision](https://github.com/0x1cx/random-lua/blob/a46fe389f772d5a56c1868673a2d3500e03ad3ea/matcha-supported/vbl.lua), [Luna ball resizer](https://github.com/Luna7070/585438). Original hitbox credit: huss.

## Research and verification

The [official VBL controls](https://www.roblox.com/games/73956553001240/Volleyball-Legends) specify click for bump/spike and Q for set/block. The [receiving tutorial](https://www.youtube.com/watch?v=yHw1lkC-QK4) and [counter-spike tutorial](https://www.youtube.com/watch?v=kG2goB34W9U) were found through indexed descriptions; the footage/transcripts were inaccessible and were not watched. No verified universal one-tick perfect-hit window was found.

The user-supplied [older source](https://github.com/pokraczkas123/matcha/blob/main/volleyball-legends.lua) was inspected as data without running it. Its serialized Lua prototypes confirm ReplicatedStorage:GetAttribute("LastHitter"), ReplicatedStorage:GetAttribute("ServedByPlayer"), and the PlayerInfo team fallback. These are historical implementation evidence, not confirmation that the current live game still exposes identical data. The Match page reports what this version can resolve in your session.

[Matcha input documentation](https://huoadf.github.io/matcha-docs/functions-console-input/) documents Windows virtual-key polling, and [Microsoft's key table](https://learn.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes) identifies side-button codes. [Matcha class documentation](https://huoadf.github.io/matcha-docs/classes/) documents GetAttribute, Player.Team, Player.UserId, and ValueBase.Value. Physical side-button behavior still depends on the runtime and mouse driver.

The simulated Lua checks additionally cover both side buttons through the actual GUI rebinding flow, Always/Toggle/Hold activation, teammate/unknown-hit rejection, numeric hitter IDs, PlayerInfo fallback, missing teams, ambiguous multi-ball metadata, serve-marker persistence, soft/rising returns, rapid close counter rearming during receive cooldown, and swept ballistic interception. A 500-stud/s test triggers from the first valid motion interval. These tests do not validate actual game timing or hit registration; live gameplay remains unverified.