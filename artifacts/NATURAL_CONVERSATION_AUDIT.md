# Planned natural conversation verification

13 November 2026. Official Reachy Mini SDK/mock simulator **1.14.0**, offline WebRTC VAD **2.0.14.post1**, Vosk **0.3.45**, Rasa **3.6.21** with a trained Core RulePolicy. All automated input was synthetic; no live microphone was opened. Robot test output used real GStreamer EOS with muted sound.

| Check | Result | Evidence |
| --- | --- | --- |
| Full adventure with automatic spoken turns | **68 assertions, zero failures** | [Full log](official-reachy/natural-adventure-verified.log) |
| Natural turns, pause/cancel/resume, voiced privacy/wait and spoken repeat | **19 assertions, zero failures** | [Branch log](official-reachy/natural-conversation-branches.log) |
| Standalone natural greeting/name/Library flow | **16 assertions, zero failures** | [Initial flow log](official-reachy/natural-conversation-verified.log) |
| Offline game regression | **576 assertions, zero failures** | [Offline log](official-reachy/conversation-offline-regression.log) |
| Controller/API/worker regressions | **100 tests run: 98 passed, two optional live-Rasa unit checks skipped** | `services/controller/tests/` |
| Offline recognizer + actual WebRTC endpointing | **Nine tests passed** | `services/speech/tests/` |
| Actual local Rasa Core | All twelve fixed dialogue branches returned their expected markers | Real REST calls to model `echo_conversation.tar.gz` on localhost:5006 |

The full route answers **NAME, G1–G3 and P1–P3** through actual endpointing, ASR, Rasa NLU/Core and the game/controller path. It contains no V/B input or question reply/skip button automation in conversation mode. It solves all four puzzles, earns all four gems, opens the sealed cave and reaches the shared ending. Every scheduled voice/hint required native completion; no technical-failure output fallback occurred. The ending assertion requires the microphone capture ID and automatic-listening flag to be clear.

The branch fixture includes an input cancelled by pause, a spoken privacy request and fixed voiced response, a normal name reply, a spoken wait request and voiced response, a repeat request that replays only G1, and an ordinary answer. It preserves question/turn ownership and game progression.

## Turn and data contract

The game explicitly opts into `conversation` mode. The server starts automatic reply turns only at a ready question, after output stops and a short echo gap, with fresh game polling and no pause/narration/stop. The owning speech worker reports end-of-turn through `/speech/end-turn`; that endpoint cannot release a manual push-to-talk capture. Processing cannot start before the appropriate release/end-of-turn. Stale or cancelled captures cannot answer another question. Silence does not become an answer. Unknown speech repeats the exact question once, then offers a fixed retry/skip response.

VAD/transcription buffers stay in RAM and are discarded on cancellation/error. Ordinary answer words never enter Rasa or the controller: Core receives only `/reply_given`; public controls use their allowlisted intent markers. Rasa uses in-memory tracking with opaque sender IDs. Fixed voice assets now total **39**, adding shared wait/privacy/repair clips without altering target questions or jokes. Spoken STOP retains its recognizer-side safety path if Rasa is unavailable.

Run **Play-Reachy-Conversation.cmd** after starting Simulation in Reachy Mini Control. [Setup and reproduction](../docs/CONVERSATION.md).

Live launch was also checked against the app-managed simulator on port 8000 with conversation/speech enabled and `bridge_ready=true` before the game opened. The SDK readiness wait now allows up to sixty seconds instead of relying on forty short polling attempts; an unavailable adapter still fails explicitly without a silent output fallback.

## Limits

This is the selected planned conversation with fixed responses. It does not interpret/score answer meaning, store names, generate dialogue, or provide open-ended chat. Automated tests do not establish human speech accuracy, noise robustness, physical microphone/speaker quality, motor calibration or research acceptance. Physical hardware remains unverified. The known restricted-environment Godot certificate-store startup warning is separate from passed assertions.
