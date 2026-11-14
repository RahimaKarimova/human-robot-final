# Planned conversations with natural turn-taking

Open Reachy Mini Control, choose Simulation, and press Start. Double-click `Play-Reachy-Conversation.cmd`, then Begin in the game. The game and read-only robot view open together.

Choose **Play-Reachy-Jokes-On.cmd** or **Play-Reachy-Jokes-Off.cmd** for the two modes. The ordinary conversation launcher defaults to Jokes on. Both modes have the same welcome, self-introductions, six questions, personalized replies, hints, celebrations, puzzles and ending. Jokes off omits the four H1-H4 comments entirely; it does not substitute neutral comments or leave empty joke panels. Internally the existing `humour` condition means on and `control` means off. Select a mode before launching a new session.

Reachy finishes each question before listening. The microphone panel appears only during opening, listening and processing. Green bars show actual microphone volume; amber means input is closed while the answer is processed. Speak English, then pause for about a second to finish. Live captions may change; the final caption shows the recognized answer. The PC's selected microphone is used. No key is needed during a question.

Each of the six planned questions now begins with a short fictional Reachy preference or island experience, followed by the original question. For example, before the exploration question: "I enjoy finding new paths, but I keep a map handy. What about you?" The introduction and question share one complete fixed recording, so listening opens only after both finish. The same introductions apply in both development conditions; question IDs, answer categories, skip/repeat controls and schedule remain the same. These are user-requested development dialogue revisions, not approved participant-study scripts.

Reachy introduces itself in the opening, then the adventure begins. It does not ask the player for a name or open the microphone during the welcome/tutorial. The first automatic listening turn follows the first planned Library question. Legacy nickname commands remain supported for compatibility but are not part of the opening.

Rasa recognizes 17 authored answer categories, including science, history and disliking reading. Uncertain matches go to a small offline CPU topic extractor for a grounded acknowledgement across all six questions. Unclear answers trigger repair instead of a generic thanks. Fixed dialogue uses expressive Ryan recordings; new acknowledgements stream using CPU Marius, and names use CPU Kokoro. These voices can sound different. See services/dialogue/README.md for the additional local setup.

Say skip the question, repeat the question, nothing comes to mind, give me a moment, are you recording, pause or stop the session. Buttons remain available. Silence never completes a question. Listening closes during robot speech, narration, pause, disconnection and stop. Outside questions, hold V for control commands.

## Local processing and privacy

WebRTC VAD detects speech boundaries. Local Whisper base.en supplies rolling live captions. The larger Whisper small.en supplies the final English transcript on CPU. Both are English-only in this conversation mode. Answer text goes to local Rasa's stateless /model/parse endpoint; Core receives only fixed intent markers. Captions and the nickname are transient session state. Raw audio and captions are not written to files or tracker messages. Personalized output text can be present in active controller command memory and is sanitized on session stop; input captions expire. Personalized speech is synthesized in memory. No cloud speech service or internet is needed after setup.

The controller uses localhost 8769, conversation Rasa 5006, and Control simulation 8000. Push-to-talk Rasa 5005 remains separate. Cancellation and context changes discard active input. Real microphone quality, accent accuracy and physical hardware still require user testing. Automated tests use synthetic speech and muted simulation; they never open a real microphone.

## Verification

With an isolated official mock simulator on port 8004 and the trained conversation model on 5007:

```powershell
./Play-Controller.ps1 -Test -ControlSimulator -SimulatorPort 8004 -Conversation -ConversationRouterPort 5007 -Port 8775
./Play-Controller.ps1 -Test -ControlSimulator -SimulatorPort 8004 -Conversation -ConversationRouterPort 5007 -FullCompanionTest -Port 8776
```

Play-Reachy-Voice.cmd retains push-to-talk; Play-Reachy-Control.cmd keeps the microphone off.

## Additional setup and interface

For a new checkout, the optional speech environment needs the pinned packages in services/speech/requirements-lock.txt, Vosk's English model, and the Systran/faster-whisper-base.en and Systran/faster-whisper-small.en repository files under tools/speech/whisper-base.en and tools/speech/whisper-small.en respectively. The installed recognizer loads them with local_files_only and English fixed explicitly. Kokoro's official model-files-v1.1 release supplies kokoro-v1.0.onnx and voices-v1.0.bin under tools/narration/kokoro. Cached fixed companion WAVs remain available without authoring tools. Re-render fixed clips with the speech environment's Python and dev/bake_companion.py.

POST /speech/caption uses the speech-role token and session_id, worker_id, capture_id, text (maximum 400 characters), revision and final. Only the current capture/context may update it. GET /game/commands adds transient speech_caption and session_name metadata, separate from command history. POST /session/name uses the game-role token and accepts session_id and name (maximum 32 characters) only at the name checkpoint. POST /speech/result carries the bounded reply_kind, optional nickname and optional reply_text (220 characters) alongside existing control fields. reply_text is accepted only for the current question/capture and stays in session memory. Game event payloads never carry transcripts. Captions expire after 15 seconds; stop clears the nickname.

Caption decoding runs outside the capture polling loop. A slow caption may omit partial words without invalidating the final audio buffer. Input closes before final decoding, whose worker lease is bounded to 30 seconds; this does not extend recording. Existing cancellation, maximum capture duration and game-loss checks remain active.

## Speech completion and navigation

Closing a game panel does not cancel Reachy. Skip, Repeat and Return-to-game clicks during a line queue one action and wait for playback to finish; repeated clicks cannot advance later lines. A repeat starts the entire question again after the original ends. Active hints and notices finish even if the puzzle or panel changes. Opening a letter waits for Reachy before starting its narrator. Incidental character greetings and settings previews cannot replace an active companion clip.

The controller also defers early checkpoint navigation until actual output completion. COMPANION_CANCEL_REQUESTED is retained as a compatible no-op for ordinary UI navigation. Pause holds the current playback position; Resume continues it. Explicit Session Stop, quitting the application, output failure or a lost game/controller connection can still end output. A timeout is reported as failure, never as successful speech completion. Existing keyboard and button fallback controls remain available after a genuine output failure.

Changes require a fresh game/controller launch; an already running session is left untouched to preserve its progress.

## Contextual jokes and delivery revision

The revised H1-H4 jokes explicitly name the book, clock, parcel and temple tasks and describe fictional robot mistakes. Their fixed Ryan WAVs use separate playful delivery instructions; celebrations use a celebratory style. These development scripts are not participant-approved research wording. Hear the style comparison at artifacts/expressive-voice/index.html. Cached playback needs no GPU.

Captions use a bounded twelve-second rolling preview and may revise words; the final recognizer still receives the full bounded turn. Quiet-speech gain is limited to four times and silence is not amplified. Neither recognizer receives an answer prompt that could steer a personal response. Final processing has its own bounded 30-second lease after input closes; the UI allows 35 seconds so it does not discard an otherwise valid result early. The microphone remains closed while decoding. No live microphone recording is used in automated tests.
