# M4b — local Rasa control requests

The optional **planned-conversation model** now runs separately on port 5006 using Rasa Core RulePolicy as well as NLU. `Start-Rasa-Conversation.ps1` trains/starts it; `Play-Reachy-Conversation.cmd` opens the automatic-turn game mode. Rasa receives public commands and synthetic reply markers, never raw personal answer words. The original NLU-only setup below is retained for push-to-talk. See [conversation setup](../../docs/CONVERSATION.md).

This connects **public control phrase → local Rasa NLU → controller intent request → Godot command**. Rasa itself does not start a microphone or motors. Default checkpoints stay neutral; opt-in [full rehearsal](../../docs/COMPANION_PREVIEW.md) delivers the supplied draft scripts. A separate optional [offline push-to-talk worker](../../docs/VOICE_CONTROLS.md) now recognizes V controls and explicitly submitted B replies; Rasa receives only allowlisted public commands, never private replies/names. Hardware validation remains pending.

Rasa 3.6.21 is installed in `services/rasa/.venv` using project-local Python 3.10.22 under ignored `tools/python/`. The controller stays in its separate Python 3.12 environment. No global Python, PATH or registry change is needed. Exact Windows dependency versions are in `requirements-lock.txt`.

## Try it on this Windows workspace

Use three VS Code terminals at the repository root:

```powershell
# Terminal 1: local NLU; keep it running.
powershell -NoProfile -ExecutionPolicy Bypass -File .\Start-Rasa.ps1
```

```powershell
# Terminal 2: game and controller; keep them running.
powershell -NoProfile -ExecutionPolicy Bypass -File .\Play-Controller.ps1
```

```powershell
# Terminal 3: explicit typed controls instead of a microphone.
powershell -NoProfile -ExecutionPolicy Bypass -File .\Control-Companion.ps1
```

Start the adventure, then try `pause`, `resume`, `repeat the question`, `skip this question`, `give me a hint` or `stop`. Switching away from the game pauses it automatically; `resume` explicitly releases that pause. Repeat/skip/no-recall apply only to an active G/P question checkpoint, not H comment IDs. In this prototype, use the **Mock acknowledgement** button for H comments. Hints work only during a puzzle. `stop` ends the session, including at the title screen.

All listed phrases are in `services/protocol/control_phrases.json`. Unknown input, “no, not really,” and sentences such as “please do not stop” do not advance a question or become an answer. The typed terminal is a developer fixture: do not enter personal answers. Ctrl+C closes that terminal without implicitly ending the game; the game's Stop button remains available. Close the game to stop its automatically started controller; Ctrl+C stops the separately started Rasa terminal.

## Boundaries and protection against stale requests

The gateway captures an opaque context ID before recognition. The controller checks that ID, the active question and game view before queuing an action. Request IDs and Godot command IDs prevent retries from applying twice. A late skip cannot affect a new question. Pause is idempotent; explicit resume carries the current game's pause ID so an old resume cannot cancel a newer pause. Recognizer outages or uncertain results produce a fixed UI notice and keep button controls available. Exact explicit stop phrases use a local safety route so stopping does not depend on Rasa being online.

No answer text/audio endpoint was added to the controller. The gateway sends only complete, allowlisted public control phrases to Rasa's `/model/parse` endpoint, and sends only intent/confidence/context IDs to the controller. Other input is discarded, not sent to Rasa or stored. It never uses `/webhooks/rest/webhook` or conversation trackers. This is a deliberately conservative command grammar, **not** general conversational understanding or a validated ASR system. Rasa's `KeywordIntentClassifier` is the baseline; both conditions use the same routing.

Training uses 83 synthetic examples generated from the public phrase bank, with no player data. No cloud model is downloaded at runtime. `run_local.py` forces telemetry off and redirects Rasa's global configuration to project-local `.runtime/`. Services bind to loopback. Neither request text nor personal responses are written to application logs.

## Checks

With Terminal 1 running:

```powershell
cd services/controller
$env:ECHO_TEST_RASA = '1'
.venv/Scripts/python.exe -m unittest discover -s tests -v
cd ../..
powershell -NoProfile -ExecutionPolicy Bypass -File .\Play-Controller.ps1 -Test -Rasa
powershell -NoProfile -ExecutionPolicy Bypass -File .\Play-Controller.ps1 -Test -PrestartStop
powershell -NoProfile -ExecutionPolicy Bypass -File .\Launch.ps1 -Test
```

The real Rasa check exercises all 83 phrases through the trained local model. The Godot check sends synthetic repeat, pause, resume, skip, hint and stop through the gateway/model/controller, then checks their actual game effects. Separate routing checks cover no-recall/wait/clarify/privacy notices, duplicate requests, stale turns/pauses, low confidence, missing tokens, negated commands, private-text rejection and NLU outage. These are **not microphone or hardware tests**.

Rasa 3.6 uses an extended-path model extractor incompatible with current Python 3.10.22's Windows tar directory handling. The project entry point substitutes normal-path extraction of regular files/directories only, using Python's `data` filter; traversal and link members are rejected, and Rasa's version/metadata checks still run. The shim has its own tests under `tests/test_model_archive.py`. Third-party site-packages are not edited. Legacy Rasa dependencies emit deprecation notices, which are distinct from test failures.

## Recreate the isolated environment

With an already installed Python 3.10, create `services/rasa/.venv` and install `services/rasa/requirements-lock.txt`. This workspace used the following explicit local runtime setup:

```powershell
uv python install 3.10.22 --install-dir tools/python --no-bin --no-registry --cache-dir tools/uv-cache
uv venv --python tools/python/cpython-3.10.22-windows-x86_64-none/python.exe services/rasa/.venv --cache-dir tools/uv-cache
uv pip install --python services/rasa/.venv/Scripts/python.exe -r services/rasa/requirements-lock.txt --cache-dir tools/uv-cache
```

`Start-Rasa.ps1 -Train` regenerates the synthetic training data and model. Installation needs internet; play/recognition after setup uses only local files and loopback services.

Official references: [Rasa NLU components](https://legacy-docs-oss.rasa.com/docs/rasa/components/), [Rasa HTTP API](https://legacy-docs-oss.rasa.com/docs/rasa/http-api/), [Rasa 3.6.21 requirements](https://pypi.org/project/rasa/3.6.21/).

Next: connect an agreed STT/manual stream through this same gateway and implement the Reachy SDK speech/motion adapter on the actual Lite/USB or Wireless Windows hardware. Freeze scripts, voice/motion, consent and fallback policies before participant use.
