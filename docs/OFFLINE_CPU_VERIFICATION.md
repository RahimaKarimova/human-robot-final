# Offline CPU update verification — 14 November 2026

Verified on the author's Windows laptop, with synthetic English answers. No real microphone or physical robot was used.

- Controller after the two-mode update: 124 tests run, 122 passed, 2 optional live-service tests skipped.
- Speech: 12 tests passed.
- Godot standalone game: 576 assertions, no failures.
- Actual game + official Reachy Mini Control mock simulator + local Rasa: 22 conversation assertions, no failures. Covered name use, wait, privacy, repeat, negative book preference and fallback controls.
- Separate muted official simulator test: generated CPU speech reached GStreamer EOS and survived pause/resume. Report: artifacts/expressive-voice/cpu-simulator-check.json.
- CPU reply extraction and streaming: six synthetic question types plus three unclear/instruction inputs checked. Report: artifacts/expressive-voice/offline-cpu-check.json. Its first-audio figure excludes recognition, reply extraction and model startup. Under concurrent workloads extraction varied up to several seconds. No sub-three-second end-to-end guarantee is made.
- Live local Rasa checks selected science, history and disliking books correctly and routed repeat, clarify, wait, no-recall and privacy support markers.
- 56 current fixed companion WAVs match their scripts. Cached WAV playback needs no GPU. The optional generated-reply worker uses CPU-only PyTorch and checks that CUDA remains uninitialized.

Latest mode checks: complete Godot companion campaigns passed 64 assertions each for Jokes on and Jokes off. Both solved all four stages, socketed all gems and reached the treasure ending. Off delivered no H1-H4 lines, while every non-joke line retained the same order and content. The opening now contains only WELCOME; it no longer asks for a name. A separate updated laptop preview passed 49 assertions for welcome, question introductions, repeat, skip, fallback, hints and speech completion. The earlier 22-check official simulator run above predates removal of the opening name question.

The local environment emitted a Godot system certificate-store warning and a GStreamer cache-permission warning during sandboxed checks; assertions and actual audio completion passed. These offline checks did not need a certificate store or internet.

Remaining user validation: real microphone/accent accuracy, subjective voice warmth and joke delivery, latency on the friend's CPU, macOS setup and physical robot behavior. Generated Marius speech and Kokoro name words can sound different from the fixed Ryan recordings. Nothing in these checks establishes perfect interpretation of every possible answer.

Start a fresh session with Play-Reachy-Conversation.cmd to load the new source, recordings and local Rasa archive. Previously running game processes are not updated in place.
