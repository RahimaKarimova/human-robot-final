# English speech and personalized conversation verification

13 November 2026. PC simulation only; physical hardware and live human speech accuracy have not been verified.

Implemented:
- Vosk live partial captions and local Whisper base.en final English recognition.
- Asynchronous partial decoding, bounded preview buffer and a 30-second closed-input processing lease. Slow previews do not invalidate final answers or block capture polling.
- Microphone panel visible only while opening/listening/processing, with actual input-volume bars.
- Fifteen authored answer categories selected through local stateless Rasa NLU and a trained Core rule policy. Negative reading preferences have an explicit guard.
- Session-only nickname extraction, an editable name field, spoken personalized greeting, selected celebrations and ending.
- Fifty-four offline Kokoro af_heart companion clips with varied pacing. Personalized lines are synthesized in memory and reach actual GStreamer end-of-stream through official SDK 1.14.0.
- Live service on 5006 reloaded with the new trained model and checked against an actual fantasy-book answer.

Checks:
- Controller: 112 tests run, 110 passed, two optional live-Rasa tests skipped. New tests cover slow preview decoding, bounded buffers, stale captions, role tokens, name memory, intent boundaries, pause/cancel and decode expiry.
- Offline speech: nine tests passed using synthetic fixtures; no real microphone opened.
- Godot offline game: 576 assertions, zero failures.
- Personalized conversation branch run: 22 assertions, zero failures, actual Whisper/Rasa/official SDK. Includes synthetic Alex, negative book preference and captions. This run preceded the asynchronous-preview change; the full run below includes that change.
- Final full adventure: 68 assertions, zero failures with asynchronous previews, Whisper, Rasa and official SDK mock simulation on isolated port 8004. All seven questions answered without keys or reply buttons; all four puzzles/gems, cave door and treasure ending completed. No caption-only output fallback occurred.
- Muted native SDK test: personalized Kokoro audio reached actual EOS.

An earlier full run stalled because synchronous preview decoding could exceed the capture heartbeat lease under CPU load. Preview work now runs separately; regression tests confirm polling continues while it is pending. The final full rerun passed.

Logs: official-reachy/personalised-kokoro-conversation.log, official-reachy/personalised-kokoro-full.log, official-reachy/personalised-offline-game.log.

The game was reopened with the updated speech worker and its bridge_ready status was verified against the Control app's official mock simulator on port 8000. The visible robot view is a read-only mirror of that daemon. No physical robot was selected. Actual room noise, pronunciation, preferred voice and microphone choice still require the user's listening test. No participant recordings, transcript files or persistent names were created by these checks.
