# Robot output adapter preparation

The robot was **not available**. The controller/game integration and separate worker are tested with a silent software fake. Lite USB and on-robot Wireless SDK/GStreamer implementations are prepared but **not installed, connected or physically verified**. Optional offline PTT controls/reply submission are installed and tested with synthetic speech, not a live microphone. Physical head/body gestures, hardware audio/input validation and participant procedures remain pending. See [WIRELESS.md](WIRELESS.md) and [VOICE_CONTROLS.md](VOICE_CONTROLS.md).

## Try the simulator now

From the project root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Play-Controller.ps1 -BridgeSimulator -Condition humour
```

This starts the controller, a separate output worker and the full draft companion flow. It is **silent**: the worker models playback progress and antenna profiles while the game shows captions and an animated mock. By default it accesses no SDK, speaker, microphone, camera or robot. It reports `simulated_completed`, not `audio_completed`. Normal simulator play uses the fixed WAV's duration; automated tests alone accelerate its clock. Optional `-Microphone` is a separate explicit input choice.

For the existing audible laptop rehearsal, use `-CompanionPreview` instead of `-BridgeSimulator`. Normal `Play.cmd` still runs the entire offline game without either service.

The bridge handles the complete welcome, all questions/comments, shared acknowledgements/hints, four celebrations and ending. Explicit buttons remain available; optional B reply input submits completion without saving words/names. Only the server selects H1–H4 variants. Default sessions without preview remain neutral fixtures.

## What the prepared Lite implementation does

`services/controller/echo_controller/robot_output.py` provides two interchangeable outputs:

- `SimulatedOutput`: silent, explicitly simulated completion and motion profiles, with an injectable clock for tests.
- `ReachyLiteOutput`: lazy optional Reachy Mini **1.12.0** SDK connection to an already-running localhost daemon, plus a GStreamer output-only WAV pipeline targeting an **exact, explicitly selected Reachy/ReSpeaker output device**. No default/laptop-speaker fallback. Completion requires an actual GStreamer EOS message and the end of any enabled antenna profile; elapsed clip duration alone never confirms physical speech.

The hardware implementation uses `media_backend="no_media"`, `spawn_daemon=False` and `automatic_body_yaw=False`. It does not start an input recording pipeline, read microphone buffers, acquire camera frames, start head tracking, enable torque or command a sleep pose. The SDK's no-media mode releases the daemon's media devices for direct output access; normal SDK context cleanup restores daemon media ownership. This does not physically disable the robot's microphone or control other apps' capture.

The output worker also has a failure-only watchdog for missing EOS: the fixed clip/motion duration plus five seconds of active playback. Paused time does not count. Timeout reports technical failure, never spoken completion. Cleanup exceptions cannot turn cancellation failure into a successful result. See [the repeatable simulation audit](SIMULATION_CHECKS.md).

Optional gesture profiles use only the antennas, at most nine degrees away from their measured starting positions, with a smooth envelope returning to the starting pose. WAVE/NOD/LISTEN/POINT/CELEBRATE are software profile IDs; these antenna patterns are **not calibrated physical head nods or validated emotions**. Physical head/body animation remains pending. Gestures default off. Pause stops profile progress and pauses the pipeline; cancel removes the pipeline and sends no further trajectory points. It does not disable gravity support. Motor/device/network latency and emergency-stop behavior still require bench testing.

The SDK methods/options were reviewed against [pinned v1.12.0 source](https://github.com/pollen-robotics/reachy_mini/blob/v1.12.0/src/reachy_mini/reachy_mini.py). Upstream recommends matching SDK/daemon versions. The [integration guide](https://huggingface.co/docs/reachy_mini/en/SDK/integration) describes Lite localhost and Wireless network access. The new Wireless adapter runs on the robot and uses its ALSA speaker over an SSH-forwarded control channel; it never routes robot speech to a default laptop speaker. Physical verification remains pending.

## Handoff and failure behavior

1. A preview session selects `output: laptop | bridge_simulator | reachy_lite`. The launcher writes separate game and robot capability files under ignored `tools/runtime/`. The robot file contains only its own role token; the game file contains no robot token or condition. Both are removed on exit. The Rasa control terminal continues to find only the game `*.session.json` file.
2. The controller issues the normal caption/dialogue command with `output_route`. An external output job cannot begin until the game emits `COMPANION_PLAYBACK_READY`. Robot-routed lines are not also played through the game's speech player.
3. The worker polls `/robot/poll` and reports `/robot/result`, using `X-Echo-Robot-Token`, a per-process worker ID and an utterance ID. Only one worker can own a session. Reconnecting never replays a seen utterance. A restarted worker needs a fresh session rather than replaying a potentially half-heard joke.
4. Results become `COMPANION_OUTPUT_RESULT` game commands. The game acknowledges playback completion separately, and a question additionally needs an explicit mock outcome. Simulator results cannot attest physical audio, and game credentials cannot drive the output endpoint or manufacture a successful bridge result.
5. Pause, terminal stop, explicit skip, repeat and bypass cancel or suspend the outstanding job. A narrator handoff waits for hint cancellation instead of playing over the external hint. The worker cancels locally on controller/device error before retrying. Stale or duplicate results cannot complete a different utterance.
6. Heartbeats use monotonic time: two seconds without a worker produces a technical failure, four seconds without an initial worker produces a technical failure, and two seconds without game polling asks the worker to cancel. These are **transport leases, not question/answer deadlines**. Question silence has no automatic outcome. Local cancellation has a five-second recovery limit so lost communication cannot permanently lock gameplay. Software timing limits do not guarantee physical stopping latency before hardware tests.
7. Failures expose caption Continue/Skip and explicit Resume without silently switching adapters or awarding gems. The puzzle alone earns its gem. All mutable per-session API operations share a lock so game events and worker results cannot race the dialogue scheduler.

## When the robot arrives

First confirm **Lite USB or Wireless** and its daemon version. Do not install this Lite setup for a Wireless unit.

For a Lite unit only, create a separate Python 3.12 environment for the optional SDK and controller dependencies (not required or installed for today's simulation):

```powershell
python -m venv services/robot/.venv
services/robot/.venv/Scripts/python.exe -m pip install -r services/controller/requirements-reachy.txt
```

If the daemon is not version 1.12.0, reconcile/review the adapter against the matching SDK first; do not change robot firmware blindly. Start the robot's own daemon separately, identify the exact GStreamer output-device display name, and first test fixed speech with gestures off:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Play-Controller.ps1 -ReachyLite -RobotPython .\services\robot\.venv\Scripts\python.exe -SpeakerName "EXACT Reachy OUTPUT DEVICE NAME" -Condition control
```

The placeholder must be replaced with the actual device name. Start failures are explicit and select no fallback. Add `-Gestures` only for a supervised antenna bench check after confirming the starting pose and cancellation behavior. No physical test was run here. Verify both conditions, real speaker clarity, pause/resume, cancellation, unplug/disconnect, absence of unintended capture, and narrator handoff before extending the hardware flow to the other chapters.

## Software checks

### Simulation expressions

The official MuJoCo and Control app simulator adapters now support continuous speech gestures, idle sway/head turns, an attentive tilt, greeting waves, directional hints and gem/ending cheers. Movement uses fixed WAV loudness windows rather than microphone input. The maximum simulation antenna target is 40 degrees from upright, approached at no more than 75 degrees/second; head targets stay within 10 degrees and 5 mm lift, approached smoothly from the measured starting pose. These larger poses and head movement are simulation-only. Physical adapters retain their previous measured-baseline antenna limits.

The internal `/robot/poll` response adds `idle_allowed` (boolean) and `idle_motion` (`IDLE` or `LISTEN`). Idle is allowed only with a recent game heartbeat, no active output job, no narration, no pause and no stopped session. The worker disables idle locally on connection failure. `LISTEN` is an attentive animation while an optional question awaits a button/reply; it does not enable a microphone or infer an answer. Cancellation and stop issue no neutral/sleep movement. Game event payloads and external command names are unchanged.

```powershell
cd services/controller
.venv/Scripts/python.exe -m unittest discover -s tests -v
cd ../..
powershell -NoProfile -ExecutionPolicy Bypass -File .\Play-Controller.ps1 -Test -BridgeSimulator -Condition control
powershell -NoProfile -ExecutionPolicy Bypass -File .\Play-Controller.ps1 -Test -BridgeSimulator -Condition humour
```

These checks exercise the actual Godot/HTTP/separate-worker path and fake device lifecycle, not a real robot or GStreamer device. The automated tests mute laptop audio and never select the hardware route. Optional live Rasa checks are separate; this step does not change its NLU model.
