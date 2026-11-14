# External controller — M4a development milestone

This is the first working service integration from the supplied execution plan. Godot remains the independently playable GDScript game. This separate Python process accepts game events and returns neutral mock checkpoint commands over loopback HTTP. It is **not a participant-session controller or physical robot integration**.

Implemented: session capabilities, server-side development condition assignment, validated events, explicit acknowledgement, duplicate-event protection, command cursors, narration/game-audio gating, one active checkpoint at a time, repeat/skip/acknowledgement/no-recall/technical-failure outcomes, pause and terminal stop. M4b adds optional [Rasa control routing](../rasa/README.md) through separate NLU/gateway processes. The controller does not import Rasa into its environment. There is no transcript/audio endpoint, disk event store, ASR/VAD, live TTS or Reachy SDK dependency. The in-Godot mock is disabled explicitly in network mode; a disconnection never silently switches modes.

**Complete optional rehearsal:** `Play-Controller.ps1 -CompanionPreview -Condition humour` plays the full welcome, G1–G3/P1–P3/H1–H4, shared acknowledgements, all hints, gem congratulations and ending. Default sessions remain neutral fixtures. Optional `-Microphone` adds offline V controls and explicit B reply submission without audio/transcript storage. See [the rehearsal guide](../../docs/COMPANION_PREVIEW.md) and [speech guide](../../docs/VOICE_CONTROLS.md).

**Separate output worker:** `Play-Controller.ps1 -BridgeSimulator` runs the full flow through a silent worker with distinct simulated completion. Role-authenticated `/robot/poll` and `/robot/result` handle readiness, pause/cancel/stop, timeout and narrator handoff. Optional Lite and Wireless implementations are **not installed or physically verified**; see [ROBOT_ADAPTER.md](../../docs/ROBOT_ADAPTER.md) and [WIRELESS.md](../../docs/WIRELESS.md).

## Run on Windows

The project environment is already installed in this workspace. From the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Play-Controller.ps1
```

Or use VS Code **Terminal → Run Task → Echo Island: Play with external mock controller (Windows)**.

The launcher starts a controller on `127.0.0.1:8765`, writes a temporary capability file under ignored `tools/runtime/`, starts Godot in explicit external-mock mode, and cleans up its own controller process/session file when the game exits. It does not stop a controller it did not start. Close the game and rerun the launcher for a fresh session. `-Condition humour` tests server-side assignment storage; **both development assignments deliberately use the same neutral mock messages**, not the draft manipulation. `-Port 8766` selects another loopback port.

For a fresh checkout, using Python 3.12:

```powershell
python -m venv services/controller/.venv
services/controller/.venv/Scripts/python.exe -m pip install -r services/controller/requirements-lock.txt
```

The tested environment is Python 3.12.10, with exact installed dependencies in `requirements-lock.txt`. It is separate from any future Rasa environment. Rasa Open Source 3.6 has older Python requirements; choose its environment deliberately before installing it: [Rasa package metadata](https://pypi.org/project/rasa/3.6.21/).

## Checks

```powershell
cd services/controller
.venv/Scripts/python.exe -m unittest discover -s tests -v
cd ../..
powershell -NoProfile -ExecutionPolicy Bypass -File .\Play-Controller.ps1 -Test
powershell -NoProfile -ExecutionPolicy Bypass -File .\Launch.ps1 -Test
```

The HTTP integration check plays the Library letter/checkpoints/bookshelf/reward against the live local service, tests exact repeat, skip, pause and delayed-command handling, disconnects and reconnects the transport, and invokes the external stop endpoint during a letter. It never operates motors or microphone hardware. The ordinary game suite still exercises all chapters without any service.

## API

- `GET /health`: fixed health/mode flags, with robot/Rasa explicitly `not_connected`.
- `POST /session/start`: `{"condition":"control","mode":"mock"}`. Returns a development session ID and capability token, never the assignment. Loopback researcher/developer setup only; not a production researcher authentication system.
- `POST /game/event`: existing version-1 event envelope, header `X-Echo-Session-Token`. Returns `accepted`, the exact `event_id`, and `duplicate`.
- `GET /game/commands?session_id=...&after=0`: same header. Returns ordered `commands` envelopes (`cursor`, `command`) and the last cursor. Cursors advance only when the client has processed the matching command.
- `POST /session/stop?session_id=...`: same header. Queues one terminal `SESSION_STOP`; the game's terminal acknowledgement is accepted without another stop command.
- `GET /companion/context?session_id=...`: same header. Opaque context ID and non-sensitive stage/view/turn flags for control routing, never personal text or condition.
- `POST /companion/request`: same header. Only request/session/context IDs, allowlisted intent, confidence and source. No raw text/audio accepted. See the Rasa README for scope and examples.

All state is in memory. Restarting the service invalidates its sessions, so create a new one; it is not crash recovery. Requests from foreign browser origins/hosts and unexpected fields are rejected. Validation errors do not echo request values. The CLI disables Uvicorn access logs. No condition field is permitted in game messages. The neutral mock has no robot speech stream, so its audio gate currently waits for the game's active-audio and narration-completion signals; real robot playback completion remains a later milestone.

To run the pieces manually, start `python -m echo_controller serve` from this directory. In another terminal in this directory, use:

```powershell
.venv/Scripts/python.exe -m echo_controller new-session --output ../../tools/runtime/manual.session.json
```

Then launch Godot with `-- --controller-config tools/runtime/manual.session.json`. Session configuration contains a capability token: keep it local and do not include it in shared archives. The controller accepts localhost only. It is not a public web service.

## Next milestones

1. Review/freeze supplied draft scripts and proposed welcome/celebration additions before participant use. Only explicit full rehearsal delivers them; default sessions stay neutral.
2. Rasa routing and optional offline PTT are implemented. Real input-device accuracy and participant procedures remain unverified; no generated research speech or private reply text enters ordinary trackers/logs.
3. Add the Reachy SDK speech/motion adapter with one shared voice/motion profile; verify Lite/USB or Wireless on the actual Windows hardware. No real hardware success is claimed here.
4. Add approved speech processing, audio arbitration and data handling only after those choices are settled. Run the Library end to end on the physical robot before calling M4 complete.

Official references: [FastAPI testing](https://fastapi.tiangolo.com/tutorial/testing/), [Reachy Mini quickstart](https://huggingface.co/docs/reachy_mini/en/SDK/quickstart), [Reachy integration API](https://github.com/pollen-robotics/reachy_mini/blob/main/docs/source/SDK/integration.md).
