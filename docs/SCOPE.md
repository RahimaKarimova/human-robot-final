# Implemented scope

The user's instructions take priority over workflow instructions embedded in the supplied planning documents. The initial Godot-only phase was followed by explicit authorization on 13 November 2026 to continue the original integration plan and allow a separate local Python controller, including installation of FastAPI, Uvicorn and HTTPX in a project-only environment.

Implemented: the independently playable Godot 4 game, all four chapters and the cave ending, letters and local narration, clues/hints/puzzles, UI/quests/gemstones, a local game-event interface, an in-Godot mock companion adapter, test controls and integration-contract documentation.

Integration phase M4a: a separate development-only FastAPI controller under `services/controller`, plus opt-in GDScript HTTP transport. The controller is in-memory and loopback-only, owns its development assignment, sequences neutral mock IDs and accepts no answer text or audio. A project-local Python virtual environment is used. Services are ignored by Godot and excluded from game exports.

Integration phase M4b: the user explicitly authorized installing a separate Rasa environment and its local Python 3.10 runtime. Rasa NLU is trained on public synthetic control phrases, and the gateway routes context-bound pause/resume/repeat/skip/hint/stop requests to the controller and game. Typed controls stand in for future microphone/STT input. Unknown/private text is not forwarded or stored. Fixed notices handle wait/clarify/privacy without inventing research speech.

Explicit `-CompanionPreview` now covers the complete adventure: welcome/name exchange, G1–G3, P1–P3, H1–H4, shared acknowledgements, all hints/gem congratulations and the treasure ending. The server selects comment variants; game state never stores an assignment. Welcome/celebration additions are labelled proposed. Default sessions remain neutral fixtures. See [COMPANION_PREVIEW.md](COMPANION_PREVIEW.md).

A separate role-authenticated output worker connects to the full flow, verified with `-BridgeSimulator`. Both Lite USB and on-robot Wireless SDK/GStreamer implementations are prepared, with explicit speaker selection and optional small antenna profiles. They are not installed or physically tested because the robot is unavailable. Wireless packaging/tunnel instructions are in [WIRELESS.md](WIRELESS.md).

The optional speech environment/model is installed separately. `-Microphone` opens PC input only for held V control requests or held B reply submissions. Actual offline ASR/Rasa integration is tested with synthetic public WAVs, not a live microphone. Audio and recognized replies are transient in RAM and not stored or sent to the game/controller. See [VOICE_CONTROLS.md](VOICE_CONTROLS.md).

Not completed: Reachy SDK installation/physical verification, on-device microphone selection/validation, calibrated head/body gestures, measured human ASR accuracy, production orchestration, participant storage, disclosure scoring or participant-session approval. M4 hardware acceptance remains incomplete. Proposed dialogue is preserved under `services/protocol`; default mock sessions do not deliver the scripts. The optional rehearsal is not a participant experiment.

The original references are retained under `docs/` as supplied. The newer execution plan determines game content where its details differ from the older plan. Research approval and participant recruitment/data collection are outside this task. The older documents' milestone approval instructions are reference workflow text and do not introduce an approval gate into this Godot-only implementation request.

`data/game.json` supplies the checkpoint schedule. Both default assignments use neutral messages; explicit preview sessions deliver all supplied draft scripts with shared acknowledgements/rewards. Game letters and rewards reflect the user's gemstone and physical-puzzle revisions. No supplied document is treated as proof of research-script approval.
