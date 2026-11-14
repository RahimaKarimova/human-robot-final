# Godot-side integration contract, version 1

Offline play uses the local signal interface and `MockRobotAdapter`. The optional loopback controller defaults to neutral mock checkpoints. Explicit full rehearsal adds supplied draft questions/comments and shared companion lines; optional role-authenticated input/output workers add offline PTT and prepared Lite/Wireless routes. Native robot/device operation and participant-session acceptance remain unverified. No game event contains condition, raw audio, names or reply text.

## Outbound events

Subscribe in Godot with `ApiClient.event_emitted.connect(handler)`. Events are emitted synchronously; adapters must defer commands to avoid changing a scene during its input handler. Events are not written to disk. Optional `ControllerTransport` queues copies, posts them with stable IDs until acknowledged and polls ordered commands. Network transport is never required for offline play. See [the controller README](../services/controller/README.md) for its capability-authenticated loopback API.

```json
{
  "version": 1,
  "session_id": "demo-123456",
  "event_id": "demo-123456-7",
  "stage_id": "library",
  "event_type": "LETTER_NARRATION_COMPLETED",
  "payload": {
    "letter_id": "L1",
    "completion": "explicit_skip_or_caption_ack",
    "replay": false
  }
}
```

`session_id` is a transient generated development ID, not a participant identifier. `event_id` increases monotonically within that ID. Future transport retries must preserve the original event ID and payload. Receivers should deduplicate by `(session_id, event_id)` and acknowledge that ID. The built-in mock ignores repeated event IDs.

| Event | Minimal payload | Meaning |
|---|---|---|
| `SESSION_READY` | `{}` | New offline development run |
| `DEVELOPMENT_RECOVERY` | `fragments`, `mock: true` | Explicit local recovery launcher restoring already-earned pieces; not a production participant-session resume |
| `TUTORIAL_COMPLETED` | `{}` | Dock sign acknowledged |
| `NPC_REACHED` | `npc_id` | Active destination interacted with |
| `LETTER_OPENED` | `letter_id` | First reading of a chapter letter |
| `LETTER_NARRATION_COMPLETED` | `letter_id`, `completion`, `replay` | Bundled voice clip ended, or user explicitly skipped/finished caption reading |
| `GAME_AUDIO_STATE_CHANGED` | `active` | External-controller mode only: fixed game audio starts/ends; includes no audio bytes or text |
| `GAME_CONTEXT_CHANGED` | `view`, `puzzle_active`, `pause_id` | External mode only: non-sensitive context for routing; pause ID changes for each new explicit pause |
| `CONVERSATION_CHECKPOINT_REQUESTED` | `checkpoint_id`, `phase` | Request fixed `entry`, `before` or `after` checkpoint |
| `CHECKPOINT_ITEM_COMPLETED` | `checkpoint_id`, `line_id`, `status`, `mock: true` | Mock acknowledgement, skip, cannot recall or technical failure |
| `MOCK_REPEAT_REQUESTED` | `checkpoint_id`, `line_id` | Repeat the same mock message |
| `MOCK_CHECKPOINT_BYPASSED` | `checkpoint_id` | Development-only immediate resume |
| `PUZZLE_ATTEMPTED` | `puzzle_id`, `correct`, optional `complete` | Attempt; never includes participant speech |
| `HINT_REQUESTED` | `level` | Fixed hint level, saturating at 3 |
| `PUZZLE_SOLVED` | `puzzle_id` | Puzzle completed once |
| `GEM_COLLECTED` | `gem_id`, `count` | Named gemstone awarded exactly once per chapter; replaces `FRAGMENT_COLLECTED` |
| `CAVE_GEM_INSERTED` | `gem_id`, `count` | Collected gem placed in its matching door socket, once per gem |
| `CAVE_UNLOCKED` | `{}` | All four gems inserted and door opening animation finished |
| `CAVE_ENTERED` | `{}` | Player first walks into the unlocked cave; hidden chest becomes visible |
| `STAGE_COMPLETED` | `{}` | Chapter advances |
| `GAME_COMPLETED` | `{}` | Chest opened inside the unlocked cave, once |
| `PAUSE_REQUESTED`, `GAME_RESUMED` | `{}` | Local pause state |
| `WAYFINDING_RETURNED` | `{}` | Player used Return to quest path; earned gems and held items are preserved, no reward or bridge-crossing credit is granted |
| `SESSION_TERMINATED` | `{}` | Irreversible stop of this run |

No event contains experimental condition, names, personal answers, free-form answer text or audio. Status values used by the mock are `ACKNOWLEDGED`, `SKIPPED`, `NO_RECALL`, `TECHNICAL_FAILURE`. These are software test choices, not measures of participant disclosure.

Gem IDs are `emerald` (library), `ruby` (workshop), `sapphire` (market), and `amethyst` (temple); definitions live in `data/gems.json`. The internal `GameState.fragments` dictionary and legacy `award_fragment` helper retain their names for compatibility but track these gem rewards. `DEVELOPMENT_RECOVERY.fragments` likewise counts restored gems. No external command grants gems, fills sockets or unlocks the cave.

## Incoming commands

Call `ApiClient.receive_command(command)` from an eventual adapter. It returns `false` for duplicates, missing IDs, wrong sessions, unsupported command types, malformed dialogue fields and every command after session stop. The current adapter executes on the Godot main thread.

```json
{
  "command_id": "mock-8",
  "session_id": "demo-123456",
  "type": "SHOW_DIALOGUE",
  "checkpoint_id": "library_before",
  "line_id": "G1",
  "text": "Mock optional conversation checkpoint G1. No answer is collected.",
  "question": true
}
```

| Command | Fields beyond IDs | Client action |
|---|---|---|
| `SHOW_DIALOGUE` | `checkpoint_id`, `line_id`, `text`, optional boolean `question` | Show mock controls only if the checkpoint matches the active checkpoint |
| `RESUME_GAME` | `checkpoint_id` | Finish that checkpoint and continue the preserved quest action |
| `PAUSE_GAME` | none | Pause without replacing the underlying letter/puzzle/checkpoint |
| `SHOW_OBJECTIVE` | `text` | Replace HUD guidance only; no quest reward |
| `STOP_SESSION` or `SESSION_STOP` | none | Stop local speech, disable interaction, show stopped screen |
| `RESUME_PLAY` | `pause_id` | Explicit routed resume for that exact current pause; an older pause ID cannot unpause a new pause |
| `COMPANION_CHECKPOINT_ACTION` | `checkpoint_id`, `line_id`, `action`, `request_id` | Apply skip/repeat/no-recall only to the matching active question; game emits its normal checkpoint acknowledgement |
| `REQUEST_HINT` | `stage_id`, `request_id` | Use the unchanged hint ladder only for the current active puzzle |
| `COMPANION_NOTICE` | `notice_id`, `request_id` | Show an allowlisted software notice; never generated or research robot speech |

`RESUME_GAME` finishes a conversation checkpoint; it cannot cancel an explicit player pause or undo a stop. Player pause resumes using the local Resume button. Commands cannot grant fragments, change solutions, alter condition or bypass puzzle validation.

M4b also supports explicit control-request resume with `RESUME_PLAY`, bound to the game's current random pause ID. The gateway obtains `/companion/context` before recognition and posts an intent-only `/companion/request` with an opaque context ID. Question actions are restricted to G/P turns, so repeating a question does not repeat an H comment. Requests are idempotent and stale context produces a fixed notice rather than advancing a new question. No utterance, raw answer, audio or condition is included in these requests. Exact explicit stop survives a Rasa outage through the labelled local safety route. See [the Rasa setup and boundaries](../services/rasa/README.md).

## Checkpoint order

The default order below preserves the newer supplied plan. **Default mode simulates IDs only**. Explicit full preview delivers every supplied question/comment in this order, with shared acknowledgements and gemstone celebrations added as described below.

| Chapter | Entry | After letter, before puzzle | After solve |
|---|---|---|---|
| Library | none | H1, G1 | none |
| Workshop | none | P1 | H2 |
| Market | G2 | P2 | H3 |
| Temple | G3 | P3, H4 | none |

The adapter waits for explicit narration completion or caption acknowledgement before handling `before`/`after`. Letter replay never schedules another checkpoint. All mock outcomes release gameplay equally; each panel also has a development Resume control. A stopped session cannot be resumed by a late command.

Production orchestration, approved research-script playback, allocation policy, physical robot playback/listening arbitration, participant storage and hardware safety remain future work. Rasa NLU now provides a constrained development control layer; it does not generate speech or process/store participant answers. Default controller sessions still use neutral mock checkpoint content.

## Explicit full draft companion preview

The optional external output channel adds session field `output` (`laptop` by default; `bridge_simulator`, `reachy_lite` or `reachy_wireless` only with preview). Commands carry `output_route`. `COMPANION_PLAYBACK_READY` and `COMPANION_CANCEL_REQUESTED` game events contain `{utterance_id}`. The separate role-authenticated worker receives fixed IDs via `POST /robot/poll` and reports `{session_id, worker_id, utterance_id, completion}` via `POST /robot/result`, using `X-Echo-Robot-Token`. The game token cannot access these routes. A worker result becomes `COMPANION_OUTPUT_RESULT` with `checkpoint_id`, `stage_id`, `utterance_id`, `completion`; the game acknowledges it using `COMPANION_PLAYBACK_COMPLETED`. `simulated_completed` is an additional completion value and is accepted only for the simulator route. Game credentials alone cannot manufacture successful external output. Pausing remains active until the game acknowledges `GAME_RESUMED`. Late result IDs cannot advance another turn, and narrator handoff waits for external hint cancellation. Both physical implementations are unverified; see [the full output protocol and leases](ROBOT_ADAPTER.md).

`POST /session/start` accepts optional boolean `preview` (default false). Preview adds `library_welcome` (WELCOME, NAME, NAME_ACK), an `_ACK` line after each G/P question, a `<STAGE>_SUCCESS` line after each solved stage's normal after-comments, and `cave_ending` (ENDING). The base question/comment order remains the table above. NAME and all G/P IDs are questions; acknowledgements, H comments and celebrations are not. Shared reply/skip acknowledgements depend only on explicit outcomes. Supplied wording and proposed welcome/celebration additions are distinguished by `provenance`.

Preview `SHOW_DIALOGUE` adds `preview: true`, `stage_id`, unique `utterance_id`, fixed `audio_id`, `motion_id` and `provenance`. `COMPANION_CUE` uses the same fields plus `text` and `question: false` for each chapter's fixed hints. Motion IDs are WAVE/NOD/LISTEN/POINT/CELEBRATE; the default adapter animates a screen face, optional hardware uses bounded antenna profiles. No arbitrary paths, dynamic speech or motor commands are accepted from game messages.

## Optional offline speech contract

Session field `speech` defaults false. The launcher writes a separate `.speech.json` capability with `speech_token`, never a game/robot token or condition. `VOICE_CONTROL_REQUESTED` carries `{capture_id, purpose: control|reply}`; `VOICE_CONTROL_RELEASED` carries `{capture_id, cancel: bool}`. Capture IDs are random opaque values. The controller rejects listening during output and binds an accepted capture to its pre-listening context. Reply-purpose capture additionally requires an active question.

The speech worker calls `/speech/poll`, `/speech/started` and `/speech/result` using `X-Echo-Speech-Token` and its worker ID. Results contain only `capture_id`, allowlisted `intent`, bounded `confidence` and `source`. No raw audio, text, names or transcript fields are accepted. `REPLY`/`source: reply` is valid only for explicit reply-mode submission with the same current question; its command is `COMPANION_CHECKPOINT_ACTION` with `action: ack`. The existing game acknowledgement advances the turn; this does not store or score an answer.

`VOICE_CONTROL_STATUS` returns capture ID and one fixed status: STARTING, LISTENING, PROCESSING, SENT, NO_COMMAND, CANCELLED or UNAVAILABLE. LISTENING is issued only after the input worker confirms opening capture. Release closes the stream before `/speech/processing` announces recognition with a separate bounded decode lease. Silence, low confidence, overflow, cancellation, changed context and unavailable workers never count as replies. See [VOICE_CONTROLS.md](VOICE_CONTROLS.md) for buffer limits, tests and physical-input limitations.

New game event `COMPANION_PLAYBACK_COMPLETED` has `{utterance_id: string, completion: string}`. Completions are `audio_completed`, `explicit_skip`, `technical_failure`, `cancelled`. Natural completion comes from the audio player's callback; failure/skip must not masquerade as spoken completion. One outstanding delivery gates later commands. Questions independently wait for an explicit `CHECKPOINT_ITEM_COMPLETED` outcome; silence does not advance them. Repeats target NAME/G1 only, never replay H1. Muted audio exposes caption Continue, and explicit bypass always releases the game locally. Stops ignore late playback/context/audio observations while acknowledging them; they never resume work. See [COMPANION_PREVIEW.md](COMPANION_PREVIEW.md).
