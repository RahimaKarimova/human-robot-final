# The Lost Treasure of Echo Island

A complete offline Godot 4 3D treasure hunt: explore a compact island, visit four characters, read their narrated letters, solve four puzzles and collect four precious gems to unlock a sealed cave.

For **planned conversations with natural spoken turn-taking**, start Simulation in Reachy Mini Control and double-click **Play-Reachy-Conversation.cmd**. Reachy asks, listens after speaking, detects the end of your answer and gives its fixed response without V/B. See [conversation setup](docs/CONVERSATION.md).

Optional integration now includes the full companion adventure, offline push-to-talk controls/replies, a silent output simulator and prepared Lite/Wireless workers. See [current progress](docs/INTEGRATION_PROGRESS.md), [voice setup](docs/VOICE_CONTROLS.md) and [Wireless setup/package](docs/WIRELESS.md). The robot is unavailable, so physical audio/motion and actual input devices remain unverified. Normal offline play still needs none of these services.

Before hardware testing, run the [repeatable simulation audit](docs/SIMULATION_CHECKS.md). Its report and individual logs are saved under `artifacts/`.

The rewards are emerald (Zümrüt), ruby (Yakut), sapphire (Safir) and amethyst (Ametist). Each appears as a polished, faceted 3D stone in its gift and a matching inventory icon. At the cave, press E or the on-screen Place button for each gem, or click its matching socket. All four stones must be inserted before the door slides open. Walk through the doorway to reveal the hidden chest; approach it and press E to finish. The chest stays hidden from outside until you enter the unlocked chamber.

The adventure interface includes a live circular minimap, compass guidance, compact quest tracker, gemstone inventory, illustrated item choices and a cinematic title view. The stylised island uses original procedural grass/water shaders, coastal terraces, tree canopies, pitched roofs and distant scenery.

**Puzzles take place in the 3D world:** search six books on Elara's shelves, pick up coloured gears from Milo's tray and place or swap them in numbered sockets, carry Nia's parcel across the wooden bridge to the riverside cottage, and press the glowing runes on Ori's three stone pillars. The book pulls out, the repaired clock turns and opens its drawer, and the temple's stone lids slide apart. Characters cheer when their puzzle is solved. Each reward is an opening physical present with a floating gemstone and a small notification. Letters and the journal remain readable overlays. Simple puzzle panels remain an optional accessibility setting.

At Milo's workbench, select a loose gear on the left with the mouse or Q/T, then click or press E to pick it up. Select a numbered socket and use it to place the gear. Using an occupied socket swaps the gear into your hand; using one with an empty hand picks its gear back up. The correct left-to-right arrangement starts the clock automatically; the visible Check gear order button gives feedback whenever needed. F moves the camera close enough to see the tray and all three sockets.

**Default play: Godot + GDScript, offline.** The companion is a clearly labelled mock. No server, Python, robot or microphone is required to play. Optional integration now includes an [external development controller](services/controller/README.md) and [local Rasa control-request routing](services/rasa/README.md). Physical Reachy operation, microphone speech recognition, live personal questions and experimental humour are not enabled.

## Play

Double-click **`Play.cmd`** in this workspace, or open **`project.godot`** in **Godot 4.5 or newer** and press **F5**.

Already reached the Market and got stuck? **`Resume-Market.cmd`** is an explicit offline development recovery shortcut: it restores your emerald and ruby, places you at the Market with the parcel, and starts in walking mode at step 2. It is a recovery fixture, not a participant-session resume or a standard puzzle reward path.

On this workspace a portable Godot 4.5.2 is available in ignored `tools/godot/`. From PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Launch.ps1
```

Open the editor with `-Editor`; run the automated suite with `-Test`. For another installation:

```powershell
.\Launch.ps1 -GodotPath 'C:\path\to\Godot.exe'
```

The launcher keeps portable settings and caches in ignored `tools/runtime/`. No installation or internet is needed to play once Godot is available. A fresh checkout does not include the ignored engine binary: use your installed Godot. Editor scene nodes are generated when the game runs; world construction lives in `scripts/world.gd`.

## Controls

| Input | Action |
|---|---|
| WASD | Walk; automatically leave puzzle inspection |
| Shift + WASD | Sprint (no stamina limit) |
| Hold right mouse + move | Orbit camera; release to use buttons |
| Mouse wheel or + / − | Smooth camera zoom, clamped to safe distances |
| Left click / E during a task | Use the highlighted physical object |
| Q / T during a task | Cycle object selection without precise mouse aiming |
| F / Inspect button during a task | Enter/leave a close 3D inspection camera |
| E / on-screen Interact | Read dock sign, visit active character, open chest |
| R / Letter | Replay the current discovered letter |
| H / Hint | Hint or destination guidance |
| Tab / Journal | Open/close journal while exploring |
| Esc / Pause | Pause/resume; available during letters and puzzles |
| Tab, Shift+Tab, Enter/Space in panels | Keyboard button navigation |
| Stop | Immediately end the current run |

Start at the dock and read the sign. Follow the golden marker and HUD direction arrow. Chapters unlock in this order: Library → Workshop → Market → Temple → Cave. Future areas can be viewed, but only the active chapter grants interactions/rewards. Nothing requires jumping, speed or a spoken answer.

Gold ground markers follow authored paths between chapters, around buildings and back over the wooden bridge after delivery. The destination advances as you reach each turn. If you wander to the wrong bank before making the required crossing, Market guidance leads you back to the bridge's market side first. Use **Hide hint / feedback** to uncover objects after reading a hint. Every puzzle has a visible Inspect button, and WASD returns to walking from every close-up view. If you lose your bearings, **Esc → Return to quest path** returns you to the current chapter's approach, preserving earned gems and held puzzle items; it grants no reward and does not count as crossing the bridge.

Narration uses **bundled neural-voice WAV recordings**, replacing the robotic Windows system voice. Each NPC has a distinct fixed voice for greetings, task instructions, retries and success lines. Elara's delivery is gentle, Milo's brisk, Nia's bright and Ori's calm. The letters keep a separate story narrator. Settings provides voice previews. Captions show the letters and speaker names; important clue phrases are highlighted. With narration disabled, select **Skip narration / finish reading**, then Continue. This explicit action is recorded as caption acknowledgement, never as completed audio playback. No model or voice service runs while playing.

An original looping score and nature ambience (surf, wind and birds) play quietly in the background and automatically duck during speech. Settings has separate voice, music and ambience levels. Pause preserves audio playback positions; Stop silences everything.

Each solved puzzle reveals a ribboned present opening in the world to show the earned gemstone, with a short reward chime and a clear description of who gave it to you. Character models have layered fantasy outfits, articulated limbs, idle/pacing animations, proximity waves, eye blinks and speech mouth movement. Twelve decorative birds fly, flap, bank and glide over the island. Drifting clouds, swaying meadow grass, flowers, rose planters, ivy and bunting add life to the scene.

Market guidance is explicit: **1. Pick up parcel → 2. Walk across the wooden bridge → 3. Deliver at a cottage's delivery box**. Gold ground markers, a floating destination marker and pickup/delivery buttons show the next action. Every close-up has a visible Return to walking button; pressing WASD in the Market overview returns to walking automatically. Clock gears finish immediately when correctly ordered, with a visible Check gear order button for feedback.

Mock companion panels simulate checkpoint timing only. Use **Mock acknowledgement**, **Skip**, **Repeat**, **Cannot recall**, **technical failure**, or **Resume game**. They never ask the actual personal questions and collect no answers. All choices preserve puzzle access and rewards.

## Architecture

- `data/game.json`: authoritative letters, hints, puzzle definitions, destinations and checkpoint IDs.
- `world.gd`, `player_controller.gd`: original low-poly world, collisions, third-person camera and movement.
- `character.gd`, `character_portrait.gd`: articulated original characters, proximity greetings, animation and live 3D portraits.
- `game_state.gd`, `quest_manager.gd`: ordered progression and idempotent fragments/completion; no participant data.
- `letter_reader.gd`, `speech.gd`: readable letter, bundled voice playback/completion, repeat and explicit skip.
- `soundscape.gd`, `reward_art.gd`: original music/ambience, audio ducking and animated gift rewards.
- `puzzle_base.gd`, `world_puzzles.gd`, `world_item.gd`: physical puzzle props, camera ray selection, keyboard selection, gear/clock state, parcel pickup/bridge crossing/delivery and symbol sequence.
- `puzzle_panel.gd`: optional simplified accessibility interface for the same puzzle solutions.
- `gift_3d.gd`, `bird.gd`, `scenery.gd`: physical reward animation, animated flock and original decorative landscape.
- `ui.gd`, `main.gd`: HUD, journal, settings, pause, stop, ending and scene coordination.
- `api_client.gd`: local event signal and validated command entry point; **no network client**.
- `mock_robot_adapter.gd`, `dialogue_checkpoint.gd`: local mock handshakes and nonblocking development controls.
- `tests/`: actual Godot scene tests, including end-to-end route and UI button actions.

See [event payloads and commands](docs/EVENT_CONTRACT.md), [QA checklist](docs/QA.md), and [asset credits](ASSET_CREDITS.md).

## Verification

```powershell
.\Launch.ps1 -Test
```

Or with a Godot executable on PATH:

```text
godot --headless --path . --editor --import --quit
godot --headless --path . res://tests/runner.tscn
```

The suite walks the signposted route using actual player movement and collisions, solves all four 3D puzzles and completes the cave with every mock conversation skipped. It uses a real camera ray to click the golden-feather book and walks the delivery route, testing wrong cottages and refusing riverside delivery before the bridge is crossed. It also checks hints, local sequence reset, reward deduplication, replay, accessibility panels, voice/subtitle consistency, narration completion, pause and safe stop. Tests return a nonzero exit code on assertion failures; the launcher also catches GDScript runtime errors.

Optional rendered screenshot run (launches an engine window):

```text
godot --path . res://tests/runner.tscn -- --capture
```

Screenshots are saved in `artifacts/screenshots/`. They are actual game captures, not concept images.

## Packaging

Ready-to-share archives, when built, are `build/EchoIsland-Windows.zip` and `build/EchoIsland-macOS.zip`. The macOS preset exports a Universal app for Intel and Apple Silicon, uses Godot's built-in ad-hoc signature and preserves executable permissions by exporting directly to ZIP. It is not Apple Developer ID signed or notarized. Mac-specific opening instructions and credits are included in that ZIP. The Mac archive was checked on Windows, but launch, rendering, audio and Gatekeeper still require an actual Mac playtest. Add documentation outside the `.app` bundle so its signature remains intact.

In Godot use Project → Export → add Windows Desktop, install official matching export templates if needed, and export to an ignored `build/` directory. Include `data/*.json,assets/audio/*.json` in the export's non-resource file filter. The project includes an export preset with those filters. No Python or external service is packaged. Test the exported game on the intended lab laptop before distribution.

Optional authoring tools under `dev/` can regenerate the original music with Godot or rebake the fixed voice clips using standalone Piper plus the credited Alba/VCTK models. Those ignored authoring binaries/models are not used by the game. See [audio attribution and reproduction](docs/AUDIO.md).

## Current limits

- This is a game development build, not a validated research instrument. The supplied protocol's actual personal questions, humour, allocation and robot/backend milestones are intentionally out of scope.
- The world and characters use original stylised procedural meshes and joint animation. They are a small fantasy-adventure interpretation, not imported Genshin characters or production anime character assets.
- Progress is kept in memory. Stop is irreversible for that run; New development session starts fresh. No crash recovery or participant data persistence.
- Narration is synthetic neural audio, not human voice acting. Playback, captions, pause and ducking are checked automatically; voice pronunciation, mix and subjective quality still need listening QA on the target machine.
- The approximately 20-minute target needs human playtesting. No timer interrupts responses or gameplay. Automated completion time is not a human pacing measurement.
- Hardware performance and accessibility need target-laptop/manual validation. See QA for what has actually been checked.
