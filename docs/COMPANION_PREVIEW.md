# Reachy full adventure rehearsal

This optional development mode rehearses every companion chapter on the laptop. It plays 36 bundled fixed synthetic voice clips and an animated screen face. By default it uses no robot, microphone or live TTS. Optional `-Microphone` adds offline push-to-talk controls and explicitly submitted replies without saving audio/transcripts; see [VOICE_CONTROLS.md](VOICE_CONTROLS.md). The normal offline game remains playable separately.

From the project root in Windows PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Play-Controller.ps1 -CompanionPreview -Condition humour
```

Choose `-Condition control` for matched non-humorous H1–H4. Both variants use the same voice, gestures, questions, hints, puzzles and celebrations. Only H1–H4 wording/recordings change. The assignment remains in the controller, outside game state and event payloads. Click **Begin the adventure**.

The sequence is:

1. Reachy welcomes you and waves on screen. Rehearsal starts directly with Reachy, without a second narrator introduction.
2. An optional name question waits for **Mock reply given · continue** or **Skip question**. No name is entered or saved. The introduction then points toward Elara.
3. At the Library, read/listen to Elara's letter. Its completion releases H1 and then the exact G1 question from the supplied v2 plan.
4. G1 waits indefinitely for an explicit mock outcome. **Repeat question** repeats G1 only. Skip uses the supplied shared skip acknowledgement; a mock reply uses the supplied shared acknowledgement. No extra joke is inserted on repeats, failed book selections or letter replay.
5. Search the actual bookshelf. **H / Hint** uses the game's same three fixed hints, with laptop voice when available. Rapid requests coalesce to the latest requested level. A stale hint is cancelled when entering a letter/checkpoint or leaving the Library.
6. Pull the golden-feather book on the upper shelf beside the globe. The emerald is earned by solving the puzzle. Reachy celebrates on screen and congratulates you, then the existing physical gift/reward appears.

Questions never infer an answer from silence. There is no answer time limit. Continue is disabled during speech; question skip and **Resume game without companion** stay available. Muted/missing/mismatched clips fall back to captions and an enabled Continue button. Pausing freezes playback/animation. Stop cancels speech and cannot resume. Network failure exposes the existing explicit bypass; it never silently switches adapters or grants a gem.

After the Library, the Workshop delivers P1 and H2, the Market delivers G2/P2 and H3, and the Temple delivers G3/P3 and H4. Every question has the same shared reply/skip acknowledgement. Each puzzle has its own three voiced hints and gemstone celebration. The sealed cave and hidden chest lead to the supplied shared companion ending, without a duplicate narrator ending clip.

G1–G3, P1–P3, H1–H4 and shared acknowledgements/ending come from the supplied newer execution plan/game catalogue. The welcome/name exchange and gem congratulations are **proposed development additions**, stored in `services/protocol/companion_preview.json` and labelled in the UI. All scripts remain draft. Personal replies are optional; no transcript, name or score is retained. Default sessions without `-CompanionPreview` still use neutral fixtures.

## Adapter contract and next connection

`SHOW_DIALOGUE` in rehearsal adds `preview: true`, `stage_id`, unique `utterance_id`, `audio_id`, `motion_id`, `provenance` and `question`. `COMPANION_CUE` uses the same delivery fields for nonmodal hints. Motion IDs are WAVE, NOD, LISTEN, POINT and CELEBRATE; the current adapter visualizes them on screen only. They are not calibrated robot motor commands.

The laptop adapter emits `COMPANION_PLAYBACK_COMPLETED` with `{utterance_id, completion}`. Completion is `audio_completed` only after the actual `AudioStreamPlayer.finished` callback; cancellation, explicit skip and failure are separate outcomes. There is at most one outstanding delivery. A question also needs its independent `CHECKPOINT_ITEM_COMPLETED` outcome. Later hardware needs its own real audio/motion completion and cancellation callbacks; a laptop acknowledgement is not proof of robot playback.

Optional push-to-talk speech is implemented separately. Lite and Wireless output implementations are prepared, but actual SDK/device connection, physical gestures/audio, microphone quality and real participant use remain unverified because the robot is unavailable. Typed Rasa controls continue to work separately.

The separate output channel is now implemented and tested with a silent `-BridgeSimulator`. A Lite SDK/output-device implementation is prepared in source but not installed or physically verified; the robot was unavailable. This does not change the audible laptop mode above. See [ROBOT_ADAPTER.md](ROBOT_ADAPTER.md) for what is tested, the distinct simulated completion protocol, and the remaining hardware/Wireless work.

## Verify / author

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Play-Controller.ps1 -Test -CompanionPreview -Condition control
powershell -NoProfile -ExecutionPolicy Bypass -File .\Play-Controller.ps1 -Test -CompanionPreview -Condition humour
powershell -NoProfile -ExecutionPolicy Bypass -File .\Play-Controller.ps1 -Test -CompanionPreview -RenderTest -Condition humour
powershell -NoProfile -ExecutionPolicy Bypass -File .\Play-Controller.ps1 -Test -BridgeSimulator -FullCompanionTest -Condition humour
```

The rendered check saves screens under `artifacts/companion-preview/`. Automated checks mute their audio output before accelerating playback; normal play uses natural pitch and speed. Fixed WAVs are already bundled. Rebuild only after editing scripts using `services/controller/.venv/Scripts/python.exe dev/bake_companion.py`, then import assets in Godot after generation completes. This optional authoring tool uses Piper's `en_US-ljspeech-high` single-speaker model with length scale 1.1 and 0.4-second sentence breaks. It replaces the earlier VCTK speaker 93 companion voice after unclear-pronunciation feedback. Runtime playback does not invoke Python/TTS to synthesize speech.
