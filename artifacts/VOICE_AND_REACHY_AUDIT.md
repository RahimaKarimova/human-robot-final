# Combined push-to-talk and expressive Reachy verification

13 November 2026, official Reachy Mini Control mock simulator and matching SDK 1.14.0, local Rasa and offline Vosk.

- **21 combined Godot/HTTP/Vosk/Rasa/SDK assertions passed**: synthetic control input pauses the game; cancellation discards it; explicit reply input is bound to the current question and reaches acknowledgement; terminal stop closes capture. Natural fixed robot output and expressive SDK movement remain enabled (automated sound is muted). [Combined log](official-reachy/voice-and-expression-controls.log).
- **33 native SDK game-control/recovery assertions passed** after the handoff fix, with no output technical-failure fallback. [Recovery log](official-reachy/voice-handoff-recovery.log).
- **Four offline recognizer tests passed**, using synthetic fixtures.
- **91 controller tests run: 89 passed, two optional live-Rasa unit checks skipped**. The combined test above uses actual local Rasa.
- The default Realtek PC microphone reports support for mono 16 kHz PCM. Format discovery does not open a capture stream.

The combined test exposed a quick-bypass race: an opening line could be cancelled before Godot adopted its utterance ID, leaving a delivery gate without a later UI acknowledgement. The owning SDK worker's confirmed requested cancellation now clears that matching delivery. A new regression test ensures microphone requests stay blocked before confirmation and become eligible afterward. Natural completion still requires real EOS and game acknowledgement.

`Play-Reachy-Voice.cmd` starts/reuses the local router and opens the simulator-connected game with push-to-talk. Input stays closed until an explicit V/B request is accepted. Tests substitute synthetic WAV capture; no live microphone, recordings or private transcripts were used. Live speech accuracy and physical robot setup remain unverified. Controls recognize fixed public phrases; reply mode acknowledges that speech was supplied without interpreting or retaining its meaning.
