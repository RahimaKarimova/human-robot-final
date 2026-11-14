## Recognition accuracy and contextual jokes (14 November 2026)

Replaced conversational Vosk previews with rolling Whisper base.en captions and upgraded final recognition to local small.en, English fixed explicitly. Added bounded quiet-speech gain and aligned closed-input decode timeouts. H1-H4 now describe Reachy's fictional practice run of each named puzzle, with separate setup/punchline rendering and a 350 ms pause. Questions and single-exposure rules are unchanged. These revised development jokes were requested by the user and are not participant-approved study wording. Hear artifacts/voice-preview/jokes.html.

## Uninterrupted companion speech

Panel closures preserve active speech. Skip/repeat/return clicks queue one action until the current line finishes; hints finish before letter narration begins. Backend checkpoint events also defer until real output completion. Stop and connection-loss recovery remain active. Verified with controller regressions, laptop playback, full adventure and the official SDK mock simulator. See artifacts/UNINTERRUPTED_SPEECH_AUDIT.md.

## Companion voice selection

User selected Bella after listening to offline Heart/Bella/Puck auditions. Kokoro af_bella is the new companion default, with friendly_v2 pacing. Greetings and celebrations are quicker; reassurance stays measured. Existing dialogue, jokes and condition wording are unchanged. Auditions remain in artifacts/voice-preview/index.html.

## English speech and personalized conversation update (13 November 2026)

Implemented local Whisper base.en final transcripts with Vosk live captions; transient microphone UI; 15 Rasa answer categories; session-only editable nickname used in spoken responses; and Kokoro af_heart companion speech with varied pacing. See [CONVERSATION.md](CONVERSATION.md) for current behavior and data flow. Older entries below describe earlier versions.

# Echo Island integration progress

The user resumed the original HRI plan and explicitly authorized the separate controller and Rasa environments on 13 November 2026, then asked to complete the remaining dialogue, microphone and Wireless work one by one. Supplied planning documents are references; the newer execution plan supplies exact shared questions and H1–H4 wording. Their workflow/approval text is not treated as a new user instruction or evidence of research approval.

## Completed software steps

1. **All companion chapters and ending.** Opt-in rehearsal includes welcome/name exchange, Library H1/G1, Workshop P1/H2, Market G2/P2/H3, Temple G3/P3/H4, shared response/skip acknowledgements, all twelve fixed hints, four gem celebrations and the treasure ending. Exact supplied questions/comments are preserved. Only the server chooses H1–H4 variants; game state has no experimental assignment. Welcome/celebration additions remain labelled proposed. The 36 original fixed companion WAVs and three new shared conversation-support clips use the same US English voice and pacing. Default controller sessions still use neutral mock fixtures; offline play needs no services.
2. **Offline push-to-talk speech.** A separate installed Python 3.12/Vosk/sounddevice environment handles explicit V control requests and B reply submissions. Input opens only after an accepted request, closes before decoding, and is discarded on release/cancel/error. The worker forwards only allowlisted public control phrases to local Rasa; private reply words/names never enter controller messages, game state or files. Reply completion requires explicit reply mode, recognized speech and the same active question; silence does not advance. Buttons remain available. See [VOICE_CONTROLS.md](VOICE_CONTROLS.md).
3. **Wireless output implementation/package.** The on-robot Linux worker uses the robot's explicit ALSA speaker, optional matching SDK and local GStreamer EOS completion. An SSH reverse tunnel connects it to the PC's loopback-only controller. `build/EchoIsland-Wireless-Agent.zip` contains only fixed assets/source/credits, no capabilities or private data. `-Wireless` creates the remote role configuration without automatically deploying or connecting. See [WIRELESS.md](WIRELESS.md).

The separate output worker/simulator also covers ready handoff, one worker per role/session, role tokens, pause/resume acknowledgement, cancellation, terminal stop, no repeated joke exposure, narrator ownership and bounded connection-loss recovery. Lite USB output source is prepared with exact selected speaker and no default-device fallback. See [ROBOT_ADAPTER.md](ROBOT_ADAPTER.md).

## Verification and limits

**Natural planned conversations completed in simulation:** the user chose planned conversations with natural turn-taking. `Play-Reachy-Conversation.cmd` uses WebRTC VAD, Vosk and a separately trained Rasa Core policy on port 5006. All seven questions are answered without V/B or reply buttons in the full 68-assertion route; 19 branch checks cover pause/cancel/resume, voiced wait/privacy and spoken repeat. Nine speech tests, 576 offline game assertions and 100 controller/API tests (two optional unit skips) pass. Audio remains transient; Rasa sees fixed intent markers rather than answer words. The microphone is off at the ending. Fixed support clips bring the companion catalogue to 39. See [natural conversation audit](../artifacts/NATURAL_CONVERSATION_AUDIT.md). Open-ended chat and physical acceptance remain outside this completed mode.

**Combined voice and expressions:** `Play-Reachy-Voice.cmd` now starts/reuses local Rasa and opens the Control simulator game with natural fixed voice, expressions and explicit push-to-talk. Twenty-one combined Godot/Vosk/Rasa/SDK assertions, 33 native recovery assertions and four offline ASR tests passed. A confirmed-cancellation handoff fix prevents a fast skipped opening line from leaving microphone use blocked. Controller tests now run 91 cases, with two optional live-Rasa unit skips. Tests used synthetic speech, not live capture; replies are acknowledged without semantic interpretation. See [combined audit](../artifacts/VOICE_AND_REACHY_AUDIT.md).

**Expressive simulator update:** official Control app SDK/daemon 1.14.0 now supports gentle idle sway/head turns, attentive listening, fixed-WAV-paced speech motion, greeting/hint gestures and gem/ending cheers. Ten native expression checks and the full 66-assertion adventure passed; controller regressions run 90 tests with two optional live-Rasa skips. The read-only official-model viewer now follows head joints as well as antenna positions. Larger motions remain simulation-only; physical profiles and calibration limits are unchanged. See [expression evidence](../artifacts/EXPRESSIVE_REACHY_AUDIT.md).

**Official simulator clarification:** the earlier `-BridgeSimulator` audit used our silent software fake, not the official robot physics viewer. The official SDK 1.12.0 and MuJoCo 3.3.0 are now installed separately. Both complete campaigns passed against `simulation_enabled: true`, `mockup_sim_enabled: false` (66 assertions each), plus 33 game-control/recovery assertions and seven native pause/resume/cancel checks. Actual antenna movement and real laptop-audio EOS were verified, with zero technical-failure fallbacks. See [the native audit](../artifacts/OFFICIAL_REACHY_AUDIT.md). `Play-Reachy-Simulator.cmd` launches the actual 3D viewer and game. See [OFFICIAL_REACHY_SIMULATOR.md](OFFICIAL_REACHY_SIMULATOR.md). This does not certify physical hardware or retroactively turn the earlier audit into a MuJoCo test.

The latest pre-hardware audit passed all **14 checks**, including both full simulator variants, laptop playback, live local Rasa routing, synthetic PTT/replies, recovery/stop cases and Wireless package verification. It found and fixed missing-EOS hangs, stalled input devices and reversible cancellation/processing transitions; these now have regression coverage. See [the audit report](../artifacts/SIMULATION_AUDIT.md) and [rerun instructions](SIMULATION_CHECKS.md).

- Full adventure tests exercise all four physical puzzles, four gems, sealed cave and companion ending through both the simulator and audible laptop route. They verify each scheduled question/comment/celebration exactly once and shared hints in every chapter. Automated audio is muted.
- Speech checks use actual offline recognition and actual local Rasa, with **synthetic public WAV fixtures rather than a live microphone**. They cover PTT controls, explicit reply completion, cancellation and stop. Negation, unrelated speech and silence do not become commands. The small model can reject uncertain/short phrases; no human ASR-accuracy claim is made.
- Wireless tests check mode/role protocol, explicit robot ALSA sink, refusal on non-Linux hosts and package contents. The robot was unavailable. No SSH connection, SDK installation, physical audio/motion, live microphone capture, motor calibration or hardware stopping latency was tested.

Detailed current counts and historical results are in [QA.md](QA.md). Existing friend-game ZIPs remain older offline snapshots; the Wireless ZIP is an agent package, not a replacement playable game export.

## Still requires the actual robot / research work

1. Confirm Lite USB or Wireless, daemon/SDK version and actual input/output devices. The prepared SDK boundary targets 1.12.0; reconcile mismatches before bench use. Both hardware implementations remain **physically unverified**.
2. Install/verify the matching optional hardware environment, then test speaker clarity, antenna profiles, real completion/cancellation, pause, unplug/network failure and narrator/input ownership. Wireless must run its worker on the robot; `-Wireless -Microphone` currently uses the **PC** microphone. Selecting/validating Reachy's microphone is a physical setup task.
3. Calibrate any desired head/body gestures; current optional physical profiles use small antenna movements only. WAVE/NOD/etc. IDs are not proof of natural emotional expression.
4. Run every chapter with the real robot, then pilot pacing and both script variants. Full M4 hardware acceptance remains pending.
5. Freeze approved participant scripts/voice/motion profiles, consent/data policies, allocation and logging before research use. This development build does not provide recruitment, persistent participant transcripts, disclosure scoring, balanced allocation or analysis datasets. No question deadline or automatic silence-as-answer behavior is introduced.

## Shared game revisions

The user-requested precious gems and four-socket cave seal replace map fragments/automatic assembly. Physical puzzles, fixed NPC voices, scenery, sprint/zoom and wayfinding are common to both variants. Recovery tools remain development tools; original twenty-minute pacing is unmeasured. Original files in Downloads were not modified.
