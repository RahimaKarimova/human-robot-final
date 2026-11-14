# Repeatable simulation audit

Run this before a hardware bench session. It never selects a physical output route and substitutes synthetic WAV input for microphone capture.

First, in a separate terminal:

```powershell
powershell -ExecutionPolicy Bypass -File .\Start-Rasa.ps1
```

Then, from the project root:

```powershell
powershell -ExecutionPolicy Bypass -File .\Test-Simulation.ps1
```

The audit requires the already-installed project-local environments and bundled test fixtures. It does not install packages or download models. It leaves an existing Rasa server running; close that server separately when finished. All controllers/output/speech workers created by game checks are session-owned and cleaned up by their launchers. The audit verifies that no new temporary capability files remain.

It runs fourteen checks:

- Controller/worker/API unit tests with actual local Rasa, including the public control phrase bank, role tokens, event idempotence, stale contexts, cancellation, stop and failure cases.
- Offline ASR tests using public synthetic WAVs; uncertain inputs fail closed, and negation/unrelated speech/silence cannot become replies or commands.
- The complete independently playable offline game.
- The full four-chapter/cave/ending campaign through the separate simulator worker in both control and humour variants.
- Actual Rasa-to-Godot control routing in both variants.
- Bridge disconnection, narrator ownership handoff and recovery.
- Full laptop audio playback/caption completion through the campaign (automated speaker output is muted).
- Stop before Begin.
- Push-to-talk controls, explicit replies, cancellation and stop using actual Vosk/Rasa with fake capture.
- A rendered voice/reply-panel check, saved to `artifacts/companion-preview/voice-reply-controls.png`.
- Wireless package rebuild and ZIP integrity/content checks, including compile checks of packaged Python and exclusion of capabilities/private runtime data.

`artifacts/SIMULATION_AUDIT.md` records the overall result and links to timestamped logs under `artifacts/simulation-audit/`. A failed or partial run is marked **FAILED OR INCOMPLETE**, not passed. `-SkipRenderedCheck` is available for headless-only environments and explicitly reduces the check count.

## Recovery guarantees checked in software

The output worker has a failure-only playback watchdog: expected fixed-clip/motion duration plus five seconds of active playback. Paused time does not consume that allowance. This deadline never creates a successful audio-completed event. A missing EOS, device error or cancellation error yields technical failure and caption controls rather than an indefinitely disabled Continue button.

Speech input closes after eight wall-clock seconds even if a device produces no samples. A release cannot reverse cancellation or replace the processing phase. Recognition results received before explicit release cannot execute a command or submit a reply. These are transport/device limits, not question-answer deadlines; ordinary silence while deciding what to say never advances a question.

## What this cannot certify

The simulator is a software output fake, not a robot physics/digital-twin simulation. Native SDK/GStreamer, Linux ALSA, SSH, robot speakers/microphones/motors, real stopping latency, room noise and human ASR accuracy remain unverified. Passing this audit means the tested software paths are ready for a supervised hardware bench test, not that a participant study or unattended robot operation has been validated.
