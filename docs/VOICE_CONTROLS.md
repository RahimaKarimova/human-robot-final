Current conversation mode uses Whisper base.en for rolling captions and small.en for the final transcript. Vosk remains the recognizer for the separate legacy push-to-talk mode. See CONVERSATION.md.

For automatic English conversations, live captions, session nickname memory and contextual replies, see [CONVERSATION.md](CONVERSATION.md). The instructions below describe the separate push-to-talk mode.

# Offline push-to-talk speech

The optional speech worker is installed in **`services/speech/.venv`** (Python 3.12), separately from the controller and Rasa. It uses **Vosk 0.3.45** and sounddevice, with the official small English model. It does not call a cloud speech service or write captured audio/transcripts. Normal game and simulator launches keep this worker disabled.

## Use it

For the installed Reachy Mini Control simulator, start the local simulator in that app and double-click **Play-Reachy-Voice.cmd**. It starts/reuses the local command router and opens the game with the natural fixed voice, expressive simulator and optional push-to-talk enabled. It opens no microphone at launch. The regular `Play-Reachy-Control.cmd` keeps speech input disabled. A router created by the voice launcher closes when its game ends; an existing router is left running.

Combined-mode check, 13 November 2026: **21 Godot/HTTP/Vosk/Rasa/official-SDK assertions passed** against Control app mock simulation 1.14.0, using synthetic WAV input and muted robot output. Four offline ASR tests passed. A quick-bypass handoff bug was fixed: when a checkpoint was bypassed before the game adopted its opening utterance, the owning SDK worker's confirmed cancellation now releases the controller's audio gate, allowing later microphone requests. Listening stays blocked until cancellation is confirmed. Controller regressions run 91 tests, with two optional live-Rasa unit-suite skips; the combined test above uses actual local Rasa. See [combined-mode log](../artifacts/official-reachy/voice-and-expression-controls.log).

First start local Rasa in a separate terminal:

```powershell
powershell -ExecutionPolicy Bypass -File .\Start-Rasa.ps1
```

Then launch the audible full companion rehearsal with optional speech:

```powershell
powershell -ExecutionPolicy Bypass -File .\Play-Controller.ps1 -Microphone -Condition humour
```

Use `-BridgeSimulator -Microphone` for silent output simulation instead. On Windows this captures the **PC microphone**, not a robot microphone. `-InputDevice NUMBER` selects another sounddevice input index; list inputs with `services/speech/.venv/Scripts/python.exe -c "import sounddevice; print(sounddevice.query_devices())"`. Selecting/validating Reachy's actual USB or Wireless input remains a physical setup task.

- Hold **V** for a control command, wait for **LISTENING**, speak, then release V. Examples: “I need a break,” “resume the game,” “repeat the question,” “skip the question,” “give me a hint,” or “stop the session.” Commands still go through the existing conservative Rasa/context route; exact confident STOP has the existing safety route if NLU is down.
- During an optional question, hold **B** to give a reply, then release B to submit it. This is an explicit reply action, not an automatic answer deadline. Confident recognized control phrases still take precedence. Other recognized speech completes only the current question; its words/name are discarded, and the companion uses the shared fixed acknowledgement. No nickname is remembered or repeated, disclosure scored, or personal answer stored.
- Silence, unclear speech, buffer overflow, recognition failure or cancellation never counts as an answer. Buttons remain available for reply completion, skip, repeat, pause and stop. Short single words can be unreliable with the small model; use a longer phrase or a button. There is no claim of measured human ASR accuracy.

The input device remains closed while idle and opens only after the explicit key request is accepted. The banner distinguishes opening, listening, **microphone off / processing**, and finished/unavailable. Releasing the key closes input **before decoding**. Processing has a separate bounded ten-second worker lease so normal recognition time is not mistaken for an input-device disconnect. Capture is limited to eight seconds per held-key request; reaching the limit discards rather than interpreting truncated speech. This is a bounded input buffer, not a question timer. Releasing after an overlong reply does not submit it; use the completion button or a shorter push-to-talk reply.

Switching away cancels capture. Pause is supported; V can request resume while the game is paused. Stop closes input and is terminal. A narrator handoff waits for cancellation acknowledgement or the existing bounded connection-loss recovery. Narrator/companion playback blocks new capture so the program does not intentionally recognize its own voice. On input overflow, a device error, context change or lost controller connection, the worker discards the buffer before retrying. A changed question cannot receive an earlier capture's reply.

The eight-second cap also uses a monotonic wall clock, so a stalled input device cannot stay open indefinitely just because it produces no samples. Cancellation is irreversible for that capture. Duplicate releases cannot undo cancellation or downgrade the input-closed processing lease, and an early recognition result cannot execute before an explicit release.

## Data flow

The listening card now includes live input levels. The speech worker computes a normalized RMS/dB level from callback PCM and posts only that scalar plus capture ID/sequence to role-authenticated `/speech/level`, at most about eight times per second. The controller retains only the latest value in RAM, expires it after 600 ms, and includes it as optional `microphone` metadata in command polling. Level updates do not enter command history, Rasa or disk. The game clears the meter on processing, stop, mismatched capture, stale data or lost connection. It never animates level bars from an idle clock.

Audio is short-lived PCM in the speech process, and text exists only transiently inside offline recognition/whole-phrase filtering. The worker never prints text or raw exception values and does not send waveforms/transcripts to Rasa, the controller, Godot or disk. Rasa receives **only exact public allowlisted control phrases**, never a personal reply/name. The worker sends a structured intent/confidence/source or a `REPLY` completion boolean to the controller through a separate role token. The controller binds it to the context captured **before** listening, and requires explicit reply-purpose mode plus the same active question for acknowledgement. Silence never advances a question.

The game/session/worker statuses and capture IDs are not answer contents. The existing development checkpoint completion flag remains `mock: true`; this software rehearsal is not an approved participant data-collection system. No consent, transcript archive, balancing or study analysis is introduced.

## Installed model and reproduction

Official [Vosk microphone example](https://github.com/alphacep/vosk-api/blob/master/python/example/test_microphone.py) and [model catalogue](https://alphacephei.com/vosk/models). The **vosk-model-small-en-us-0.15** model is listed as Apache 2.0. Its downloaded ZIP has SHA256 **30f26242c4eb449f948e42cb302dd7a686cb29a3423a8367f99ff41780942498**. The model and environment stay under ignored development directories, outside Godot exports.

For another checkout, create `services/speech/.venv` with Python 3.12, install `services/speech/requirements-lock.txt`, and extract the official model ZIP into `tools/speech/vosk-model-small-en-us-0.15`. No PATH/global Python changes are needed. Recreate only the **public synthetic test fixtures** with `services/controller/.venv/Scripts/python.exe dev/bake_voice_fixtures.py` (optional Piper authoring tool). These WAVs are test phrases, not participant recordings.

## Checks and limits

### Natural conversation mode

`Play-Reachy-Conversation.cmd` enables question-only automatic listening through WebRTC VAD, Vosk and Rasa Core. Reachy listens after its fixed question, detects the end of speech and gives the planned acknowledgement without V/B. Spoken wait/privacy/repeat/skip and no-recall requests are supported, with fixed voice responses. Silence never submits an answer. The original push-to-talk launch remains available. See [conversation setup](CONVERSATION.md) and [verified full route](../artifacts/NATURAL_CONVERSATION_AUDIT.md).

All nine speech tests pass: four offline ASR tests and five endpoint tests. The combined natural mode passed all seven questions in the full 68-assertion native route and 19 branch checks. Automatic listening is explicitly selected by the conversation launcher; it is not enabled in other modes.

```powershell
services/speech/.venv/Scripts/python.exe -m unittest discover -s services/speech/tests -v
powershell -ExecutionPolicy Bypass -File .\Play-Controller.ps1 -Test -Microphone
```

Start Rasa first for the end-to-end test. **Test mode substitutes a synthetic WAV capture and never opens a microphone.** It exercises actual offline Vosk, actual local Rasa, controller commands and Godot controls. The ASR smoke test requires most public fixtures to be recognized correctly and permits uncertain inputs to fail closed; it does not accept a wrong command or pretend every fixture/accent is recognized. Separate tests check unrelated speech/negation/silence, role tokens, cancellation, stale question protection and buffer handling. Live speakers, room noise, physical input devices and real Reachy audio still need validation.
