# Recognition accuracy and contextual joke revision

14 November 2026.

The user reported wrong caption words, flat joke delivery and unclear references to game objects. They requested task-specific setups about Reachy having tried the puzzles.

Changes:
- Conversation live captions now use local Whisper base.en, replacing the Vosk preview. Vosk remains available in the separate push-to-talk mode.
- Final English transcription now uses local Whisper small.en with deterministic beam-five decoding. Both models are cached and loaded without network access. No suggested answer text is supplied to recognition.
- Quiet-speech gain is bounded to four times; silence is not amplified. Live preview buffers retain up to twelve seconds without invalidating the final turn. Preview words can revise. Very short partial windows are withheld until there is enough context.
- Closed-input final processing receives its own bounded 30-second budget after a long spoken turn. The UI's 35-second wait no longer discards a valid slow result early. The mic closes before decoding.
- H1-H4 now name the bookshelf/golden-feather book, Milo's clock/blue gear, Nia's parcel/cottages and the temple's stone symbols. Each is explicitly a fictional practice-run story about Reachy's mistake. The neutral variant shares the setup and has a neutral ending.
- Bella remains the voice. Humour clips render setup and punchline separately with a 350 ms pause and a measured punchline pace. This improves audible structure; it is not an emotion-controlled speech model, and the user must judge how the delivery sounds.
- The revised wording is a user-requested development draft, not participant-approved research material. Questions, schedule and single-exposure rules remain unchanged.

Verification:
- Controller suite: 116 tests run, 114 passed and two optional live-Rasa checks skipped.
- Speech suite: twelve tests passed; includes quiet gain, silence suppression, rolling preview limits and existing VAD/ASR checks.
- Four synthetic English phrase tests retained the expected words. Standalone final decoding initially measured 2.38-4.42 seconds; these are fixture timings, not promised real-world accuracy or latency.
- All four joke WAVs passed a local recognition check for task context and punchline words. Durations: H1 10.87s, H2 8.96s, H3 11.55s, H4 8.99s.
- Official SDK 1.14.0 mock simulator full adventure with new recognition and humour: 68 assertions, zero failures. All seven questions, four puzzles/gems and cave ending completed with actual muted output EOS and no caption-only fallback.
- Separate official SDK conversation rerun: 22 assertions, zero failures. Includes synthetic name Alex, context-specific negative-book reply, captions, repeat, wait, pause/cancel and terminal stop.
- One initial conversation attempt stalled on WELCOME while two runs shared the simulator. The full route passed; the conversation route then passed when rerun separately. The cause of the initial startup failure was not proven. The first-attempt log is retained.
- Godot imported the revised audio and scripts successfully.

Auditions: artifacts/voice-preview/jokes.html. Logs: accurate-captions-conversation.log, accurate-captions-startup-attempt.log, context-jokes-full.log, context-jokes-check.json and whisper-small-check.json under artifacts/voice-preview.

All automated audio was synthetic; no live microphone or participant recording was used. The PC's selected input was read as the Realtek microphone array without recording it. Accented live speech, room noise and preferred delivery remain user listening tests. A fresh conversation game/controller launch loads the update; an already open game is not replaced automatically.

Final isolated fixture rerun through actual conversation Rasa also passed: synthetic name, negative-book preference, REPEAT and STOP all produced the expected control outcomes. Final decode timings were 2.77, 2.59, 2.62 and 3.81 seconds. Incremental Whisper preview words appeared before the synthetic negative-book turn ended, and the final preview retained books. See whisper-small-check.json.
