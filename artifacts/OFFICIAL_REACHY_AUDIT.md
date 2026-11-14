# Official Reachy Mini / MuJoCo verification

13 November 2026. **Passed against the official Reachy Mini SDK 1.12.0 and MuJoCo 3.3.0**, installed in the project-local robot environment. This is a separate audit from the earlier silent bridge-fake tests.

Two isolated official daemons on localhost ports 8001 and 8002 reported `simulation_enabled=true`, `mockup_sim_enabled=false`. Tests used the real SDK connection and GStreamer decoding, playback clock and end-of-stream; automated output was muted. No live microphone was opened.

| Check | Result | Evidence |
| --- | --- | --- |
| Complete control adventure, four puzzles/gems, cave, all companion lines and hints | 66 assertions, zero failures | [control.log](official-reachy/control.log) |
| Complete humour adventure, same route | 66 assertions, zero failures | [humour.log](official-reachy/humour.log) |
| Game/SDK controls and recovery, including repeat/pause/resume/cancellation/stop | 33 assertions, zero failures | [controls.log](official-reachy/controls.log) |
| Native pause, frozen scheduler, no motion targets while paused, resume to real EOS, cancellation and no later targets | All seven checks passed | [native-lifecycle.json](official-reachy/native-lifecycle.json) |
| Measured simulated antenna movement during both campaigns | 858 state samples per daemon, no read errors; maximum excursions 0.131 and 0.126 radians | [measured-motion.json](official-reachy/measured-motion.json) |

Both campaigns additionally required zero technical-failure output fallbacks and native completion for every scheduled line/hint. The separate lifecycle test measured 0.110 radians of antenna movement. The controller regression suite passed 82 tests with two optional live-Rasa checks skipped; Rasa and synthetic speech coverage from the earlier audit is recorded separately.

The output worker uses the same SDK movement pipeline as the prepared hardware adapters. Simulator mode refuses a physical or lightweight mockup daemon. Tests also uncovered and fixed a startup race: the launcher now waits for native worker readiness before starting the game, instead of allowing slow SDK initialization to trigger a missing-worker fallback. Isolated ports allow verification without interrupting the interactive viewer.

## Reproduce

Start two official headless simulation daemons on ports 8001/8002 using the project-local robot environment, with separate robot names and `--sim --headless --no-media --no-preload-datasets --fastapi-host 127.0.0.1`. Then run these commands separately (the two full campaigns can run concurrently):

```powershell
./Play-Controller.ps1 -Test -ReachySimulator -FullCompanionTest -SimulatorPort 8001 -Port 8766 -Condition control
./Play-Controller.ps1 -Test -ReachySimulator -FullCompanionTest -SimulatorPort 8002 -Port 8767 -Condition humour
./Play-Controller.ps1 -Test -ReachySimulator -SimulatorPort 8001 -Port 8766 -Condition humour
./services/robot/.venv/Scripts/python.exe dev/test_official_reachy_lifecycle.py --port 8002
```

Run the lifecycle test after the campaigns finish. The observer script `dev/observe_official_simulation.py` reads the isolated daemons' real state during the campaigns. Interactive use is `Play-Reachy-Simulator.cmd` on port 8000, with audible PC output and the official 3D viewer.

## Limits

Post-completion recheck on 13 November: started a fresh isolated official daemon and reran all seven native lifecycle checks and all 33 SDK/game-control assertions; all passed again. Antenna excursion was 0.111 radians. See [fresh control log](official-reachy/final-recheck-controls.log) and the updated [lifecycle result](official-reachy/native-lifecycle.json). The interactive game and official viewer remained responsive, and the play-session daemon still reported running official simulation after test cleanup.

**Physical Reachy Mini remains unverified because no robot was available.** USB/Wireless connection setup, on-robot speaker/microphone, unplug/network behavior, motor calibration and real stopping latency need a bench test. Current gestures use small antenna movements; natural head/body expressions are not calibrated. Simulation uses the PC speaker path and does not prove physical speaker playback. No human speech-recognition accuracy or listening-quality claim is made.

Godot emits the known restricted-environment certificate-store startup warning; the offline/loopback assertions above passed. This audit does not replace the manual usability and physical acceptance checklists.
