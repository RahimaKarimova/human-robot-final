# Uninterrupted companion speech

13 November 2026.

Ordinary UI navigation no longer cancels Reachy's active line. Skip, Repeat and Return-to-game requests wait for full playback; one pending action is retained so extra clicks cannot affect future lines. An initial Return click waits for the offered speech too. Closing a panel and triggering incidental greetings cannot replace active companion audio. Active hints/notices survive panel and stage changes. Letter narration waits until companion speech completes.

The local controller defers early checkpoint navigation until actual output completion, including requests received before SHOW_DIALOGUE is adopted. COMPANION_CANCEL_REQUESTED is now a compatible no-op for navigation. Explicit Stop clears queued actions. Pause/resume preserves position. Output errors, quitting and lost connection leases retain their existing recovery behavior; a timeout never counts as successful speech completion.

Verification:
- Controller: 115 tests run; 113 passed, two optional live-Rasa tests skipped. Includes queued repeat/bypass, first-action-only behavior, duplicate completion, early UI adoption and Stop.
- Offline Godot game: 576 assertions, zero failures.
- Muted real laptop WAV playback: 49 assertions, zero failures. Includes panel closure, incidental greeting rejection, queued return and explicit Stop.
- Full four-stage adventure: 64 assertions, zero failures through the laptop companion route.
- Silent bridge adapter: 32 assertions, zero failures.
- Official Reachy Mini SDK 1.14.0 mock simulator: 34 assertions, zero failures. Includes Repeat during the original question, full hint completion before letter narration, disconnection recovery and session Stop. Isolated test daemon 8004 was closed afterwards.
- Synthetic push-to-talk/Rasa fast-navigation run: 21 assertions, zero failures. No microphone opened.

Logs are under artifacts/voice-preview/uninterrupted-*.log. Updated controller source, scripts, tests, documentation and wireless agent ZIP are saved. The user's existing game was left open to preserve progress; a fresh launch loads the changes. Physical hardware was not tested.
