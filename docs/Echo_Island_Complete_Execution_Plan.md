# The Lost Treasure of Echo Island — Complete Game Execution Plan

**Project:** Human–Robot Interaction final coursework  
**Version:** 2.0 — implementation-ready planning baseline  
**Game:** compact 3D voxel/low-poly treasure hunt  
**Game engine:** Godot 4.x stable, **GDScript**  
**Editor:** Godot editor + VS Code with Codex  
**Integration:** Python orchestrator + Rasa + Reachy Mini SDK  
**Target:** approximately **20 minutes total**, including all narration, game activity, robot questions, and responses (validate in pilot sessions)

> **Status:** Complete implementation plan, not a finished game. All character names, puzzles and jokes are proposed and need a pilot and professor approval. Do not start recording identifiable human responses until the agreed privacy and ethics procedure is approved.

## 0. Architectural decision

Choose **Godot + GDScript** for the interactive 3D game. Godot is the renderer and game simulation; Python/Rasa/Reachy is a separate process. Both programs run locally and communicate by a well-defined HTTP API or WebSocket. Codex in VS Code can scaffold scenes/scripts, create assets and tests, but the team must verify the running game inside the Godot editor. Use Unity/C# only if the team is already skilled in Unity; **Java is not required** and is not the same as Unity's C#.

A 20-minute experience does not mean a huge map. Build one **compact island** with four signposted zones and a cave, with meaningful scripted puzzles and conversations. No procedural Minecraft world, survival mechanics, fighting, inventories with crafting, terrain generation, or advanced NPC AI.

### Definition of success

- Any participant can finish the game without giving personal information.
- Same game, characters, narrator, letters, hints, timing policy, controls and robot animations across both conditions.
- The **only planned manipulated factor** is self-deprecating humour in specific Reachy utterances. Control lines acknowledge the same events and convey equal puzzle information.
- Personal questions occur **during** the adventure at fixed checkpoints, mixed with general questions.
- 3 participant-target questions are **exactly** the ones approved by the team, in the pre-registered order **procrastination → difficulties → worries**; these are relabelled below by checkpoint to avoid confusion with original user list.
- Robot never requests more details after a personal answer and never blocks a treasure map piece because of a skipped question.
- Speech processing retains **no voice recordings**; if transcriptions are retained, they are consented, minimised, protected and not falsely represented as anonymous.
- Game remains playable if robot/audio/Rasa becomes unavailable through documented pause/recovery or an agreed test-only mock mode.

## 1. Study alignment and operational definition

**RQ:** Does self-deprecating humour from Reachy Mini while jointly exploring a treasure island influence voluntary participant self-disclosure?

**H1:** Participants exposed to Reachy Mini's preapproved self-deprecating comments during the treasure hunt exhibit greater mean disclosure depth on three mildly personal questions than participants exposed to matched, friendly, non-humorous comments.

**Design:** between subjects, ~20 people, ~10 per condition; same physical Reachy Mini; participant ID random assignment external to the game.

**Primary DV:** mean of 0–3 independently coded disclosure-depth ratings across the three designated personal questions. Missing/skip coded explicitly as status; pre-specify whether skip contributes score 0 to the composite (recommended yes, plus skip-rate analysis). **Do not use word count as the primary measure.**

**Secondary outcomes:** personal-question answer rate, response word count, warmth/competence/humour manipulation checks, perceived judgement, hint usage, completion time, errors/technical interruptions.

**Critical methodological point:** Humour may also change perceived competence or vulnerability. Pilot paired scripts to make both conditions acknowledge the same limitation or minor error and match tone/duration/accuracy. Differences in perceived competence must be reported, not suppressed.

## 2. Player experience overview

**Title:** The Lost Treasure of Echo Island. An explorer arrives on an island with a map torn into four pieces. Four NPCs have letters describing the location of a hidden piece. Reachy Mini is the explorer's physical partner, present on the desk; fictional island characters are on the computer screen. Collect four map fragments, assemble them, and unlock the cave chest.

**Core loop:** Explore short path → encounter NPC → open a readable letter → hear its **separate narrator voice** → Reachy comments → Reachy asks a general or target question at a designated checkpoint → listen to participant or skip → solve clue puzzle with optional identical hints → earn map piece → follow waypoint.

**Game interaction:** third-person character, WASD move, mouse look, E/interact; accessible on-screen interact and hint buttons; R/replay letter; ESC/pause; map journal/tab. Require keyboard/mouse, not gamepad. No timer pressure, death, loss of items, score shaming or sudden failure.

**Visual direction:** attractive, coherent low-poly/voxel *inspired* visuals; original or appropriately licensed assets; gentle daylight, warm village, forest paths, recognisable silhouettes, readable high-contrast UI, stylised readable parchment. Do not claim a licensed Minecraft product; do not copy Minecraft art/code.

**Camera:** third-person follow, mouse yaw with sane bounds, collision-avoidance or simple static camera in narrow places. 60 FPS target on lab laptop, 30 FPS minimum tested. Provide mouse sensitivity control if feasible.

**Navigation accessibility:** clear signs, glowing objective marker, optional objective arrow, no maze-like map. Each area should be reachable within ~30 seconds from the prior stage.

## 3. Scene and stage map

```text
START DOCK / TUTORIAL
   |
   v
FOREST LIBRARY (general warm-up, map piece #1)
   |
   v
INVENTOR'S WORKSHOP (target question: procrastination, piece #2)
   |
   v
MARKET / MERCHANT (target question: difficulties, piece #3)
   |
   v
ANCIENT TEMPLE (target question: recent worries, piece #4)
   |
   v
TREASURE CAVE (combine fragments, end)
```

Players may look around each unlocked zone but cannot skip mandatory game puzzles. Personal answers are **never** mandatory. Avoid world teleport that changes trial length unpredictably; use controlled paths and unlockable gates. If players get lost, show an unobtrusive waypoint hint.

### Proposed pacing (not a hard deadline)

| Elapsed target | Step | Question/humour |
|---|---|---|
| 0:00–1:30 | Welcome and movement tutorial | identical greeting |
| 1:30–5:00 | Forest Library | General G1; matched humour H1 |
| 5:00–9:30 | Inventor's Workshop | Target P1: procrastination; H2 |
| 9:30–14:00 | Market | General G2 then target P2: difficulty (not back-to-back with humour); H3 |
| 14:00–18:30 | Temple | General G3 then target P3: worries; H4 |
| 18:30–20:00 | Treasure cave | identical ending; questionnaire follows |

Actual response times may vary. **Never interrupt personal answers to enforce 20 minutes.** Log length and use bounded game-only assistance for long puzzle stalls. Pilot timing with people unfamiliar with games.

## 4. Complete narrative content and puzzles

All written text, source of correct answers, narrator lines and hint ladders must be **data-driven JSON**, not scattered through scene scripts. Proposed exact text follows; edit and freeze before the pilot.

### Stage 0: Dock / introduction

**Environment:** spawn dock, sea, compact visible island, sign to library; on-screen tutorial prompts.

**Visual UI:** quest tracker shows `0/4 map fragments`, destination `The Library`, small avatar tutorial.

**Narrator:** none. **Reachy:** shared greeting only, no humour.

**Tutorial tasks:** move to glowing footsteps, turn toward sign, press E at sign; no scoring. If unable after 45 seconds offer tooltip; if stuck after further delay, offer researcher technical help. Handoff to next scene only on confirmed interaction.

**Technical event:** `tutorial_completed`.

### Stage 1: Forest Library — stories and general conversation

**NPC:** Elara, librarian. **Environment:** cosy wooden library, 6 marked books, golden feather emblem on one book, reading desk.

**Letter** (voice narration, identical groups):
> "Welcome, traveller. Books have always taken me to places I could never visit. My favourite tales are journeys across strange islands. Our cartographer left a fragment inside the book marked with a golden feather. Look for it on the upper shelf beside the globe. — Elara"

**General question G1** (not primary outcome):
> "What kind of stories or books do you enjoy?"

**Main puzzle:** identify golden-feather book on the upper shelf beside globe. Four lower shelf distractors; one other feather-like mark elsewhere, but only one satisfies all constraints. Player can click/access books via interaction prompt. Correct triggers `puzzle_solved`. Incorrect highlights "Not quite; check the letter again" without negative feedback.

**Hint 1:** "There are two details about the book's location in the letter."

**Hint 2:** "Check the shelf nearest the globe."

**Hint 3:** "It's the golden-feather book on the upper shelf, beside the globe."

**Map reward:** fragment #1 behind selected book.

**Humour pair H1** (keep questions separate from comment if practical):
- Humour: "I almost missed that shelf. If overlooking clues were a talent, I'd be a champion."
- Control: "I almost missed that shelf. I need to check the clues more carefully."

**Trigger:** after opening letter and before puzzle interaction, at same event point in both conditions. Do not add more jokes on retries.

### Stage 2: Inventor's Workshop — personal habit / procrastination

**NPC:** Milo, inventor. **Environment:** workbench, 3 movable coloured gears or tiles (red, blue, yellow), 3 labelled sockets, visual instruction card. Implement as simple GUI drag/drop or click-to-cycle; not physics.

**Letter:**
> "I've been putting off repairing my little clock for days. Every time I pass the workbench I tell myself I'll do it tomorrow. Today I finally made a start! The clock works when the small blue gear goes between the red gear and the yellow gear, from left to right. Fix it, and the next map piece is yours. — Milo"

**Personal target P1 (procrastination)** — exact wording:
> **"What's something you often put off doing, even though you know you should do it?"**

**Puzzle:** set order RED–BLUE–YELLOW. To avoid relying on the participant understanding gear mechanics, use visually clear 3-slot ordering puzzle. The ordering clue is explicit; difficulty comes from finding and placing the parts, not deciphering jargon.

**Hint 1:** "Think about which colour belongs in the middle."

**Hint 2:** "The inventor said the blue gear goes between the other two."

**Hint 3:** "From left to right, place red, blue, then yellow."

**Map reward:** piece #2 under clock lid.

**Humour pair H2:**
- Humour: "I nearly forgot which gear goes where. My memory should probably come with a sticky-note subscription."
- Control: "I nearly forgot which gear goes where. I should review the instruction before we continue."

**Timing rule:** ask P1 at story checkpoint after letter, allow full answer/skip, then guide to workbench. H2 may be at completion of gear puzzle to avoid immediate prime of disclosure.

### Stage 3: Village Market — personal difficulties

**NPC:** Nia, merchant. **Environment:** four delivery cottages marked tree, river, hill, bridge; stylised cart and route signs.

**Letter:**
> "People think deliveries are easy, but I still struggle with directions on this island. Yesterday I sent a parcel the wrong way. The package was meant for the cottage beside the river, *after* the wooden bridge, not the cottage on the hill. Find the correct route and I'll show you where the next map fragment is hidden. — Nia"

**General G2:** "Do you like exploring new places, or do you prefer somewhere familiar?" (general, not primary outcome).

**Personal target P2 (difficulties)** — exact wording:
> **"What's something you sometimes find difficult or uncomfortable, even if it seems easy to other people?"**

**Puzzle:** three signposted route choices; correct `bridge → riverside cottage`. Show fully accessible map and path. Wrong route redirects to map without loss. Puzzle must be unambiguous in all visual resolutions and for colour-blind participants (labels, not only colours).

**Hint 1:** "The letter mentioned two landmarks in a specific order."

**Hint 2:** "Cross the wooden bridge, then look toward the river."

**Hint 3:** "Choose the cottage next to the river immediately after the wooden bridge."

**Map reward:** piece #3 in correct delivery chest.

**Humour pair H3:**
- Humour: "I got my directions mixed up for a moment. Navigation genius of the year—definitely not me."
- Control: "I got my directions mixed up for a moment. Let's check the landmarks again."

**Timing rule:** G2 just after entering market, then letter and puzzle intro; P2 after opening letter at a separate checkpoint; H3 after investigating the route. Avoid direct joke→personal question coupling.

### Stage 4: Ancient Temple — recent worries

**NPC:** Ori, explorer (only letter, not necessarily 3D animated NPC). **Environment:** stylised temple, large stone symbols, three switches, final altar.

**Letter:**
> "When I first reached this temple, I worried about taking the wrong path. I waited outside for ages. In the end, I noticed the symbols carved above the entrance: sun, wave, star. Press those symbols in that order to reveal the final map piece. — Ori"

**General G3:** "If you could explore any place in a story, where would you go?"

**Personal target P3 (recent worries)** — exact wording:
> **"What's something you've been worrying about lately, even if it's just a small thing?"**

**Puzzle:** press SUN → WAVE → STAR. Buttons must be clear shapes with labels and simple reset after mistake. Avoid high-stakes failure effect.

**Hint 1:** "The entrance has an ordered sequence."

**Hint 2:** "The sequence starts with the sun and ends with the star."

**Hint 3:** "Press sun, then wave, then star."

**Map reward:** piece #4 from altar.

**Humour pair H4:**
- Humour: "I almost scrambled that sequence. Turns out my brilliant memory has a very short opening act."
- Control: "I almost scrambled that sequence. Let's read the sequence carefully before we press anything."

**Timing rule:** H4 at puzzle-checkpoint after question response, not while participant is answering. P3 is more sensitive and must be skippable without extra follow-up. If participant volunteers distress, stop probing and offer pause or researcher assistance.

### Stage 5: Treasure Cave / resolution

**Environment:** a short path, glowing closed chest, map pedestal, reward animation.

**Puzzle:** four fragments automatically snap into map; final symbol is revealed; open chest by interacting. No additional personal questions.

**Reachy ending, identical both conditions:** "We found it! That was great teamwork. Thanks for exploring Echo Island with me!"

**Interaction complete:** emit `game_completed` once. Launch separate questionnaire, debrief and approved withdrawal instructions outside the game.

## 5. Dialogue, disclosure and ethical rules

### Required staged conversation contract

1. Character letter appears and separate narrator reads it. Game blocks **only this letter panel's close** until narration completes or participant explicitly skips narration; skip narration option must be identical across conditions and loggable.
2. Game pauses movement at a designated conversation checkpoint, but not indefinitely: participant may answer, decline, say "I can't think of anything", request repetition, or ask privacy/stop questions.
3. Reachy asks the same exact target question in both groups.
4. Accept ordinary answers with the **same warm, non-judgemental acknowledgement** independent of detail level. Example: "Thanks for telling me. Ready to carry on?" (ready-to-carry-on question can itself add complication: preferably use "Thanks for telling me! Let's keep exploring." and resume after the response finishes).
5. When skipped: "Of course! No worries at all. Let's carry on." Never require disclosure to proceed.
6. If unclear: repeat the original question once; then offer approved clarification or skip.
7. If no answer: wait through measured silence; one gentle opt-out reminder; then allow skip. Never infer unwillingness from silence alone.
8. If asks why it's personal or about privacy: approved factual response about study purpose and **researcher access to text transcripts**, then offer to continue/skip/end.
9. If "nothing comes to mind": mark `NO_RECALL` separately from `SKIP` if explicitly distinguishable. Do not force explanation.
10. If a participant reports serious distress: terminate the questioning and offer assistance; do not improvise counselling.

### Experimental scripts

Use a single dialogue library `dialogue.json` keyed by ID with condition overrides **only for H1-H4**. Same question names, robot motions and speech profiles; the game never emits humour itself. Freeze the two script variants before main sessions. No LLM-generated live answers, hints or jokes.

### Transcript and data safeguards

Do not persist raw participant audio. Use short-lived in-memory VAD/ASR buffers and purge on shutdown/error. Before choosing local/cloud speech-to-text, verify exactly where bytes flow. Logs must exclude unconsented raw utterances and nicknames; pseudonymised transcripts may still contain identifiable personal statements. Avoid distributing transcripts through Git, crash logs, Rasa trackers or analytics. Implement consent-specific retention and deletion behaviour. Professor should approve exact questions and speech-to-text implementation.

## 6. Game UI specification

### Minimum screens

- Start: title, Begin, Settings, Accessibility, consent handoff **handled outside game**, clear FPS controls.
- Tutorial overlay: movement + interaction + hint controls.
- Exploration: player, camera, waypoint/objective, progress `n/4`, small minimap optional.
- Letter modal: parchment, large typography, Replay Audio, Close, subtitles available (actual letter text displayed always).
- Conversation status: subtle "Reachy is asking a question"/"Listening..." text; Skip and Repeat buttons so speech-recognition failures cannot trap the participant.
- Puzzle panel: interaction controls and hint button; clear success/error feedback.
- Journal: visited letters, collected map pieces, current objective; no stored personal responses.
- Pause: continue, help, exit study (requires safe session handling).
- Ending: chest animation, thank-you, questionnaire handoff.

### Quality checklist

- Consistent colour palette, font and iconography; source asset license file.
- All text readable on 1366×768 and 1920×1080.
- No letter-only narration; subtitles necessary for accessibility.
- No confusing NPC dialogue that implies Reachy is the NPC or uses LLM magic.
- Allow audio mute with captions (if research protocol permits), handle mic permissions honestly.
- No animation that delays asking the same question across conditions.

## 7. Technical architecture and module boundaries

```text
Godot Game (GDScript)
  Scenes, character controller, puzzles, letter UI, visual progression
    │ local HTTP POST events / poll commands or WebSocket
    ▼
Python Experiment Orchestrator
  owns session state, assigned condition, approved dialogue IDs,
  question scheduling, privacy controls, researcher override, event logs
    │                                  │
    ├──► Rasa dialogue manager          ├──► SQLite research event store
    │      handles allowed intents      │
    │      and dialogue branches        │
    └──► Reachy SDK + TTS/ASR ◄────────┘
           physical speech, gestures, mic and playback
```

**Authority rules:** Godot owns game progression; orchestrator owns the experimental protocol; Rasa owns conversation flow *within* orchestrator constraints; Reachy SDK owns hardware. Neither game nor Rasa is allowed to rewrite the participant's experimental condition or invent questions.

### API contract (minimal)

`POST /session/start` (researcher-only): session ID, condition assignment, build version; starts after consent.  
`POST /game/event`: event ID, session ID, stage, payload; idempotent on event ID.  
`GET /game/commands?after=cursor`: controller commands `PAUSE_GAME`, `RESUME_GAME`, `SHOW_OBJECTIVE`, `SESSION_STOP`.  
`GET /health`: service connection and status (no transcripts).  
`POST /session/stop`: safety stop; researcher-controlled.  

Example event:

```json
{
  "event_id": "S017-workshop-letter-opened-1",
  "session_id": "S017",
  "stage_id": "workshop",
  "event_type": "LETTER_OPENED",
  "payload": {"letter_id":"L2", "game_build":"0.2.0"}
}
```

Rules: schema validation; ignore duplicate events; never trust client-generated experiment `condition`; use local-only access and short-lived session token if endpoints are reachable beyond localhost. Explicit ACK to prevent race conditions. Use event queue so Reachy's audio never overlaps the letter narration.

### Audio scheduling

Game fires `LETTER_OPENED`; orchestrator tells game to play/await narrator or game plays a known-duration audio and sends `LETTER_NARRATION_COMPLETED`. After completion, only the orchestrator can start Reachy's spoken comment, then question. **A single speaker coordinator owns playback lock**. On timeouts/disconnects, pause and offer resume rather than speaking over the narrator or participant.

### Core event names

`SESSION_READY`, `TUTORIAL_COMPLETED`, `NPC_REACHED`, `LETTER_OPENED`, `LETTER_NARRATION_COMPLETED`, `CONVERSATION_CHECKPOINT_REQUESTED`, `QUESTION_ANSWERED`, `QUESTION_SKIPPED`, `PUZZLE_ATTEMPTED`, `HINT_REQUESTED`, `PUZZLE_SOLVED`, `FRAGMENT_COLLECTED`, `STAGE_COMPLETED`, `GAME_COMPLETED`, `PAUSE_REQUESTED`, `SESSION_TERMINATED`, `TECHNICAL_ERROR`.

### Idempotent checkpoint

`CONVERSATION_CHECKPOINT_REQUESTED` must be marked completed once per `session_id/question_id`. Reloading scene, pressing E twice, or retrying network must never cause the same personal question twice or give a second humour exposure.

## 8. Godot project structure

```text
EchoIsland/
  project.godot
  README.md
  ASSET_CREDITS.md
  scenes/
    main.tscn
    player/player.tscn
    island/island.tscn
    zones/library.tscn
    zones/workshop.tscn
    zones/market.tscn
    zones/temple.tscn
    zones/cave.tscn
    ui/hud.tscn
    ui/letter_modal.tscn
    ui/puzzle_modal.tscn
    ui/pause_menu.tscn
  scripts/
    player_controller.gd
    interactable.gd
    game_state.gd
    quest_manager.gd
    puzzle_base.gd
    puzzle_library.gd
    puzzle_workshop.gd
    puzzle_market.gd
    puzzle_temple.gd
    letter_reader.gd
    hint_panel.gd
    dialogue_checkpoint.gd
    api_client.gd
    event_bus.gd
  data/
    stages.json
    letters.json
    puzzles.json
    hints.json
  assets/
    models/
    textures/
    audio/narration/
    fonts/
  test/
    test_stage_logic.gd
    test_puzzle_solutions.gd
    test_event_deduplication.gd

services/
  orchestrator/
  rasa/
  reachy_bridge/
  tests/
```

Autoloads: `GameState`, `QuestManager`, `EventBus`, `ApiClient`. Store only game progress in game state, not names or participant transcripts.

## 9. Execution backlog (order, deliverable, acceptance)

### Milestone M0 — Freeze requirements and research protocol

Tasks: agree target 20 minutes, chosen exact P1/P2/P3 order, condition scripts, target participant hardware, privacy consent, data policy, narrator voice, three-hint rule, study metrics. Draft user story and event matrix. **Deliverable:** versioned protocol + dialogue/letter catalogue + risk register. **Done when:** professor approves sensitive questions/protocol and team signs off exact scripts.

### Milestone M1 — Environment setup and empty playable island

Tasks: install stable Godot 4, VS Code + Godot extension/Codex, create repo with ignore rules, project settings, 3D renderer, input map, folder structure, scene loader, player with capsule collider, movement and mouse camera, terrain and four blockout landmarks. **Done when:** game launches on target laptop, avatar moves/looks/interacts and can navigate all zones, acceptable frame rate.

### Milestone M2 — UI foundations and quest system

Tasks: HUD objective, interact prompts, readable letter modal, replay narrator button, pause/help, hint panel, map progress, session state machine; add generic `Interactable` component to doors/books/NPC. Create placeholder accessibility settings. **Done when:** interact via E or mouse, letters can be opened/replayed/closed, objective advances and `4/4` state cannot be cheated by duplicate events.

### Milestone M3 — Vertical slice: complete Forest Library

Tasks: library props, Elara NPC, voice letter, golden-feather puzzle, three hints, fragment reveal, stage completion, general question checkpoint placeholder, H1 event. Connect `LETTER_OPENED`, `NARRATION_COMPLETED`, `HINT_REQUESTED` to local mock orchestrator; verify narration and Reachy comments do not overlap. **Done when:** new tester can play Library from start to fragment #1 without developer help. **Do not start stages 2–4 until this passes.**

### Milestone M4 — Experiment service integration

Tasks: Python event receiver/controller, experiment condition stored outside game, Rasa API connector, Reachy Mini speech bridge, dialogue IDs, question/skip/repeat/stop branches, event logging, local ASR with approved data policy; mock robot mode for dev. **Done when:** full stage with real robot asks G1 and gives H1 or control at same event, without dialogue drift and with correct failure fallbacks.

### Milestone M5 — Workshop and Market

Tasks: gear/tile puzzle with correct order; shipment routing puzzle; NPC art and audio; stage transition barriers; P1/P2 checkpoints; H2/H3 events; full hint ladders and accessibility labels. **Done when:** either condition traverses both stages, answers/skips do not affect progression, all hint information identical.

### Milestone M6 — Temple and finale

Tasks: symbol press puzzle, P3 and G3 checkpoints, H4 event, treasure cave map reconstruction, final reveal animation, post-game handoff. **Done when:** can finish entire story with no personal answers, and no arbitrary timed cutoff.

### Milestone M7 — Polish and reliability

Tasks: lighting, models, sound mix, clean HUD, transitions, progression saving *only for test recovery* (avoid resuming participants without approved protocol), UI sizes, asset credits, measured script timings, optional wayfinding, clean disconnect handling. **Done when:** five complete scripted test runs with no critical failures; average game time near 20 minutes.

### Milestone M8 — Pilot and experimental freeze

Tasks: 3–4 pilot volunteers not in main analysis; test sarcasm perceived as self-deprecating; comfort; script pair equivalence; puzzle fairness; STT accents; response completion; exact timing; consent and transcription. Revise before freezing; log build/version/hash, scripts/version/hash, Rasa model, robot calibration. **Done when:** reliable complete experience, questions and humour approved, two conditions differ only as planned.

### Milestone M9 — Participant runs and analysis

Tasks: randomise and run ~20 participants, log approved raw responses, coder-blind redacted transcripts, score ordinal disclosure rubric with two raters, weighted Cohen kappa/agreement, per-participant mean, group comparison, effect sizes/uncertainty, questionnaire outcomes, confound limitations. **Done when:** report reproducible from frozen dataset/scripts and compliant with coursework constraints.

## 10. Task ownership / parallel tracks

**Developer A (Game 3D):** M1, M2, scene art, player, UX, M3 library, stage layout, credits.  
**Developer B (Game mechanics):** content JSON, four puzzles, hint system, event payloads, testing; begin on placeholders while A builds island.  
**Developer C (HRI):** Python orchestrator, Rasa states, speech bridge, research scripts, logs, pilot/test protocol; develop against mock `game/event` messages before Godot ready.  

Merge only when shared API contract is agreed. Each workstream can simulate the others. All three conduct pilot, recording/data audit and report review.

## 11. Acceptance tests and critical edge cases

| Test ID | Input/condition | Expected outcome |
|---|---|---|
| T01 | New session starts | Same greeting for both conditions; game ready |
| T02 | Player tries to access Temple early | Locked with objective, no broken quest |
| T03 | Player opens same letter twice | Narration replay allowed; no duplicate personal question |
| T04 | Wrong puzzle solution | Gentle feedback, no punishment or progression loss |
| T05 | Requests hint repeatedly | Three fixed escalating hints, no extra info in humour condition |
| T06 | Reachy/STT unavailable | Pause, clear error/fallback; never silently invent answers |
| T07 | Participant says skip | Mark skip, no map penalty, next gameplay resumes |
| T08 | Participant is silent | One neutral prompt then opt-out; no endless loop |
| T09 | Participant asks "repeat" | Exact question repeated, no extra joke |
| T10 | Participant is mid-speech when game advances | Game waits; no interruption |
| T11 | Trigger delivered twice over HTTP | One logical checkpoint, no duplicate humour or scoring |
| T12 | Participant requests to stop | Stop speech/interaction immediately and follow researcher protocol |
| T13 | Audio narrator still playing | Reachy speech delayed until narrator done |
| T14 | Both conditions compared stage-by-stage | Identical clues, puzzles, movements, questions, hint availability |
| T15 | No personal answers given | Game still finishes successfully |
| T16 | No robot connected (developer test) | Mock mode works but NOT silently used in real study |
| T17 | Unusual names / private details in answer | No nickname in logs; restricted transcript policy |
| T18 | Game loses focus or user presses ESC | Pause and safe resume; no event duplication |
| T19 | Slow participant exceeds 20 min | May finish; no rushed disclosure; report actual duration |
| T20 | Platform exit/failure during question | No partial text double-scored; log technical interruption |

**Pre-study release gates:** 100% scripted state/edge branch unit tests; no unhandled stop/skip in realistic pilot cases; 0 double-trigger question events; no raw recorded voice files; confirmed target hardware performance and ASR quality; acceptable coder agreement; professor-reviewed question list; fixed experiment build and scripts.

## 12. Risks, alternatives and fallback

- **3D scope overflow:** keep four small zones, simple interactable props; no open world. Replace complex 3D puzzle with polished 2D overlay inside 3D game.
- **Insufficient engagement:** expand optional scenery interaction and puzzle quality, not random extra dialogue; pilot 20-minute pacing.
- **Overlong sessions:** reduce traversal/repetitive transitions, not disclosure response time.
- **Participant frustrated by puzzle:** identical bounded hint ladder and assisted completion path.
- **Humour inseparable from competency:** both conditions admit same minor limitation; pilot perceived competence.
- **User self-disclosure too identifiable:** local STT and redaction; consent+restricted access; pre-agreed deletion.
- **Integration delay:** run Godot with mock event service; Rasa/Reachy with simulated Godot events; connect late.
- **Unity debate:** if a team member already knows Unity and can deliver vertical slice faster, switch game only; do not rewrite robot/Rasa components.

## 13. Useful references

- Godot official documentation: https://docs.godotengine.org/en/stable/
- Godot GDScript basics: https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html
- Godot 3D starter: https://docs.godotengine.org/en/stable/getting_started/first_3d_game/index.html
- Reachy Mini SDK: https://github.com/pollen-robotics/reachy_mini
- Rasa documentation: https://rasa.com/docs/

**Next engineering action:** Use `Echo_Island_Codex_Master_Prompt.md` to create the **M1 + M2 + M3 library vertical slice**, and demonstrate it in Godot before requesting the remaining chapters.
