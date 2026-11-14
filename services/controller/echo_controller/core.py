"""Deterministic, in-memory development orchestration. Never accepts answer text or audio."""
from __future__ import annotations

import hashlib
import json
import secrets
import threading
from . import preview
from dataclasses import dataclass, field
from pathlib import Path

CATALOGUE = json.loads((Path(__file__).resolve().parents[3] / "data/game.json").read_text(encoding="utf-8"))
STAGES = {stage["id"]: stage for stage in CATALOGUE["stages"]}
STATUSES = {"ACKNOWLEDGED", "SKIPPED", "NO_RECALL", "TECHNICAL_FAILURE"}
PAYLOADS = {
    "SESSION_READY": {}, "TUTORIAL_COMPLETED": {}, "NPC_REACHED": {"npc_id": str},
    "LETTER_OPENED": {"letter_id": str},
    "LETTER_NARRATION_COMPLETED": {"letter_id": str, "completion": str, "replay": bool},
    "CONVERSATION_CHECKPOINT_REQUESTED": {"checkpoint_id": str, "phase": str},
    "CHECKPOINT_ITEM_COMPLETED": {"checkpoint_id": str, "line_id": str, "status": str, "mock": bool},
    "MOCK_REPEAT_REQUESTED": {"checkpoint_id": str, "line_id": str},
    "MOCK_CHECKPOINT_BYPASSED": {"checkpoint_id": str},
    "GAME_AUDIO_STATE_CHANGED": {"active": bool},
    "COMPANION_PLAYBACK_COMPLETED": {"utterance_id": str, "completion": str},
    "COMPANION_PLAYBACK_READY": {"utterance_id": str},
    "COMPANION_CANCEL_REQUESTED": {"utterance_id": str},
    "VOICE_CONTROL_REQUESTED": {"capture_id": str, "purpose": str},
    "VOICE_CONTROL_RELEASED": {"capture_id": str, "cancel": bool},
    "GAME_CONTEXT_CHANGED": {"view": str, "puzzle_active": bool, "pause_id": str},
    "PUZZLE_ATTEMPTED": {"puzzle_id": str, "correct": bool, "complete": bool},
    "HINT_REQUESTED": {"level": int}, "PUZZLE_SOLVED": {"puzzle_id": str},
    "GEM_COLLECTED": {"gem_id": str, "count": int},
    "CAVE_GEM_INSERTED": {"gem_id": str, "count": int},
    "CAVE_UNLOCKED": {}, "CAVE_ENTERED": {}, "STAGE_COMPLETED": {}, "GAME_COMPLETED": {},
    "PAUSE_REQUESTED": {}, "GAME_RESUMED": {}, "SESSION_TERMINATED": {},
    "WAYFINDING_RETURNED": {}, "DEVELOPMENT_RECOVERY": {"fragments": int, "mock": bool},
}


class ProtocolError(ValueError):
    """A fixed, non-sensitive error description only."""


def validate_event(event: dict) -> None:
    kind, payload = event["event_type"], event["payload"]
    if kind not in PAYLOADS or event["stage_id"] not in STAGES:
        raise ProtocolError("Unsupported event or stage.")
    allowed = PAYLOADS[kind]
    if set(payload) - set(allowed):
        raise ProtocolError("Unsupported payload fields; answer text and audio are not accepted.")
    for key, value in payload.items():
        if type(value) is not allowed[key] or (isinstance(value, str) and len(value) > 128):
            raise ProtocolError("Invalid payload value.")
    # Only complete is optional; an attempted answer always supplies correct/puzzle_id.
    if set(allowed) - set(payload) - ({"complete"} if kind == "PUZZLE_ATTEMPTED" else set()):
        raise ProtocolError("Missing payload fields.")
    stage = STAGES[event["stage_id"]]
    if "npc_id" in payload and payload["npc_id"] != stage["npc"]:
        raise ProtocolError("NPC does not match stage.")
    if "puzzle_id" in payload and (payload["puzzle_id"] != event["stage_id"] or event["stage_id"] == "cave"):
        raise ProtocolError("Puzzle does not match stage.")
    gems = {"library": "emerald", "workshop": "ruby", "market": "sapphire", "temple": "amethyst"}
    if "gem_id" in payload and (payload["gem_id"] not in gems.values() or (kind == "GEM_COLLECTED" and payload["gem_id"] != gems.get(event["stage_id"]))):
        raise ProtocolError("Gem does not match the event.")
    if "count" in payload and not 1 <= payload["count"] <= 4:
        raise ProtocolError("Gem count must be between one and four.")
    if "completion" in payload and payload["completion"] not in ({"audio_completed", "simulated_completed", "explicit_skip", "technical_failure", "cancelled"} if kind == "COMPANION_PLAYBACK_COMPLETED" else {"audio_completed", "explicit_skip_or_caption_ack"}):
        raise ProtocolError("Unsupported narration completion.")
    if "letter_id" in payload and payload["letter_id"] != stage.get("letter_id"):
        raise ProtocolError("Letter does not match stage.")
    if "checkpoint_id" in payload:
        key = payload["checkpoint_id"]
        if not any(key == event["stage_id"] + "_" + phase for phase in ("entry", "before", "after", "welcome", "ending")):
            raise ProtocolError("Checkpoint does not match stage.")
    if kind == "CONVERSATION_CHECKPOINT_REQUESTED" and payload["checkpoint_id"] != event["stage_id"] + "_" + payload["phase"]:
        raise ProtocolError("Checkpoint phase mismatch.")
    if kind == "CHECKPOINT_ITEM_COMPLETED" and (payload["status"] not in STATUSES or payload["mock"] is not True):
        raise ProtocolError("Unsupported development outcome.")
    if "line_id" in payload and payload["line_id"] not in preview.LINE_IDS:
        raise ProtocolError("Unknown line ID.")
    if "level" in payload and not 1 <= payload["level"] <= 3:
        raise ProtocolError("Hint level must be between one and three.")
    if "purpose" in payload and payload["purpose"] not in {"control", "reply"}:
        raise ProtocolError("Unsupported capture purpose.")
    if kind == "GAME_CONTEXT_CHANGED":
        if payload["view"] not in {"title", "tutorial", "explore", "letter", "checkpoint", "puzzle", "reward", "finale", "journal", "stopped"}:
            raise ProtocolError("Unsupported game view.")
        if payload["pause_id"] and (len(payload["pause_id"]) != 16 or any(c not in "0123456789abcdef" for c in payload["pause_id"])):
            raise ProtocolError("Invalid pause capability.")


@dataclass
class Checkpoint:
    stage: str
    phase: str
    lines: list[str]
    index: int = 0
    waiting: bool = False
    done: bool = False


@dataclass
class Session:
    condition: str  # Server-side development assignment; never returned to the game.
    preview_enabled: bool = False
    output: str = "laptop"
    speech_enabled: bool = False
    conversation_enabled: bool = False
    last_game_poll: float | None = None
    nickname: str = field(default='',repr=False)
    reply_kinds: dict = field(default_factory=dict,repr=False)
    reply_texts: dict = field(default_factory=dict,repr=False)
    session_id: str = field(default_factory=lambda: "dev-" + secrets.token_hex(12))
    token: str = field(default_factory=lambda: secrets.token_urlsafe(32), repr=False)
    stopped: bool = False
    paused: bool = False
    audio_active: bool = False
    seen: dict[str, str] = field(default_factory=dict)
    commands: list[dict] = field(default_factory=list)
    checkpoints: dict[str, Checkpoint] = field(default_factory=dict)
    narrator_ready: set[str] = field(default_factory=set)
    started: bool = False
    game_view: str = "unknown"
    game_stage: str = "library"
    puzzle_active: bool = False
    pause_id: str = ""
    context_id: str = field(default_factory=lambda: secrets.token_hex(12))
    context_signature: tuple = ()
    control_requests: dict = field(default_factory=dict)
    delivery: dict = field(default_factory=dict)
    after_speech_event: dict = field(default_factory=dict, repr=False)
    hint_queue: list = field(default_factory=list)
    skipped_questions: dict = field(default_factory=dict)
    robot: object = None
    speech: object = None
    lock: object = field(default_factory=threading.RLock, repr=False)

    def __post_init__(self):
        if self.speech_enabled:
            from .speech_channel import SpeechChannel
            self.speech = SpeechChannel()
        if self.output != "laptop":
            from .robot_channel import RobotChannel
            self.robot = RobotChannel(self.output)

    def cancel_delivery(self):
        if self.robot and self.robot.job:
            self.robot.cancel()
        else:
            self.delivery.clear()

    def deliver(self, kind, stage, **payload):
        utterance_id = secrets.token_hex(12)
        self.delivery = {"utterance_id": utterance_id, "stage_id": stage,
                         "checkpoint_id": payload.get("checkpoint_id", "")}
        self.command(kind, stage_id=stage, utterance_id=utterance_id, preview=True, output_route=self.output, **payload)
        if self.robot:
            self.robot.offer(self.commands[-1]["command"])

    def context(self) -> dict:
        key, line = "", ""
        for checkpoint_id, checkpoint in self.checkpoints.items():
            if checkpoint.waiting and not checkpoint.done:
                key, line = checkpoint_id, checkpoint.lines[checkpoint.index]
                break
        signature = (self.game_view, self.game_stage, self.puzzle_active, self.paused, self.stopped, self.pause_id, key, line)
        if signature != self.context_signature:
            self.context_signature = signature
            self.context_id = secrets.token_hex(12)
        return {"context_id": self.context_id, "stage_id": self.game_stage, "view": self.game_view,
                "bridge_ready": bool(self.robot and self.robot.worker_seen is not None and self.robot.clock()-self.robot.worker_seen < 2),
                "puzzle_active": self.puzzle_active, "paused": self.paused, "stopped": self.stopped,
                "checkpoint_id": key, "line_id": line,
                "question": line in preview.QUESTIONS if self.preview_enabled else bool(line and not line.startswith("H"))}

    def command(self, kind: str, **payload) -> None:
        cursor = len(self.commands) + 1
        self.commands.append({"cursor": cursor, "command": {
            "command_id": f"controller-{self.session_id}-{cursor}",
            "session_id": self.session_id, "type": kind, **payload,
        }})

    def drain(self) -> None:
        if self.stopped or self.paused or self.audio_active or self.delivery or (self.robot and self.robot.job) or (self.speech and self.speech.job):
            return
        if any(checkpoint.waiting and not checkpoint.done for checkpoint in self.checkpoints.values()):
            return
        for key, checkpoint in self.checkpoints.items():
            if checkpoint.done or checkpoint.waiting:
                continue
            if checkpoint.phase not in {"entry", "welcome", "ending"} and checkpoint.stage not in self.narrator_ready:
                continue
            if checkpoint.index >= len(checkpoint.lines):
                checkpoint.done = True
                self.command("RESUME_GAME", checkpoint_id=key)
                continue
            line_id = checkpoint.lines[checkpoint.index]
            if self.preview_enabled:
                self.deliver("SHOW_DIALOGUE", checkpoint.stage, checkpoint_id=key, line_id=line_id,
                             **preview.script(line_id, self.condition, self.skipped_questions.get(line_id.removesuffix("_ACK"), False),
                                              reply_kind=self.reply_kinds.get(line_id.removesuffix('_ACK'),'DEFAULT'),nickname=self.nickname,
                                              reply_text=self.reply_texts.get(line_id.removesuffix('_ACK'),'')))
                checkpoint.waiting = True
                return
            # Draft research questions/humour are deliberately not delivered by this stub.
            message = f"External mock checkpoint {line_id}. No personal question is asked and no answer is collected. Use the development controls to continue."
            self.command("SHOW_DIALOGUE", checkpoint_id=key, line_id=line_id,
                         text=message, question=not line_id.startswith("H"))
            checkpoint.waiting = True
            return
        if self.hint_queue:
            stage, level = self.hint_queue.pop(0)
            self.deliver("COMPANION_CUE", stage, **preview.hint(level, stage))

    def stop(self) -> None:
        if not self.stopped:
            self.after_speech_event.clear()
            self.stopped = True
            self.nickname=''
            self.reply_kinds.clear()
            self.reply_texts.clear()
            for record in self.commands:
                command=record['command']
                if command.get('generated_reply') or command.get('provenance','').startswith('session_'):
                    command['text']='[Session-only reply cleared]'
                    command.pop('speech_text',None)
            self.audio_active = False
            self.delivery.clear()
            self.hint_queue.clear()
            if self.robot:
                self.robot.cancel()
            if self.speech:
                self.speech.cancel()
            self.command("SESSION_STOP")
            self.context()

    def accept(self, event: dict) -> bool:
        validate_event(event)
        digest = hashlib.sha256(json.dumps(event, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        event_id = event["event_id"]
        if event_id in self.seen:
            if self.seen[event_id] != digest:
                raise ProtocolError("Event ID was reused with a different payload.")
            return True
        if self.stopped:
            if event["event_type"] in {"SESSION_TERMINATED", "GAME_AUDIO_STATE_CHANGED", "COMPANION_PLAYBACK_COMPLETED", "GAME_CONTEXT_CHANGED", "COMPANION_CANCEL_REQUESTED", "COMPANION_PLAYBACK_READY", "VOICE_CONTROL_RELEASED"}:
                # Acknowledge in-flight observations without reviving terminal state.
                self.seen[event_id] = digest
                return False
            raise ProtocolError("Session is stopped.")
        if len(self.seen) >= 10000:
            raise ProtocolError("Development session event limit reached.")
        kind, stage, payload = event["event_type"], event["stage_id"], event["payload"]
        # UI navigation cannot cut an offered line short, including a fast click
        # before the game has adopted SHOW_DIALOGUE. Only one action is queued.
        if (self.preview_enabled and kind in {'CHECKPOINT_ITEM_COMPLETED','MOCK_REPEAT_REQUESTED','MOCK_CHECKPOINT_BYPASSED'}
                and self.delivery and self.delivery.get('checkpoint_id') == payload['checkpoint_id']
                and not (kind=='CHECKPOINT_ITEM_COMPLETED' and payload['status']=='ACKNOWLEDGED')
                and not (kind=='MOCK_REPEAT_REQUESTED' and payload.get('line_id') not in preview.QUESTIONS)):
            checkpoint=self.checkpoints.get(payload['checkpoint_id'])
            if not checkpoint or (kind!='MOCK_CHECKPOINT_BYPASSED' and payload.get('line_id')!=checkpoint.lines[checkpoint.index]):
                raise ProtocolError('Response does not match the active mock line.')
            if not self.after_speech_event:
                self.after_speech_event={**event,'event_id':'after-speech-'+secrets.token_hex(12),'payload':dict(payload)}
            if self.robot and self.robot.job:
                self.robot.job['ready']=True
            self.seen[event_id]=digest
            return False
        if kind == "SESSION_READY":
            if self.started:
                raise ProtocolError("Create a fresh controller session for each game run.")
            self.started = True
        elif not self.started:
            raise ProtocolError("SESSION_READY must be the first event.")
        if kind == "LETTER_OPENED":
            self.narrator_ready.discard(stage)
        elif kind == "LETTER_NARRATION_COMPLETED":
            self.narrator_ready.add(stage)
        elif kind == "GAME_AUDIO_STATE_CHANGED":
            self.audio_active = payload["active"]
            if not self.audio_active and self.speech and self.conversation_enabled:
                self.speech.auto_after=max(self.speech.auto_after,self.speech.clock()+.6)
            if self.audio_active and self.speech:
                self.speech.cancel()
        elif kind == "VOICE_CONTROL_REQUESTED" and self.speech:
            self.speech.start(self, payload["capture_id"], payload["purpose"])
        elif kind == "VOICE_CONTROL_RELEASED" and self.speech:
            self.speech.release(payload["capture_id"], payload["cancel"])
        elif kind == "COMPANION_PLAYBACK_COMPLETED":
            if self.delivery.get("utterance_id") == payload["utterance_id"]:
                if self.speech and self.conversation_enabled:
                    self.speech.auto_after=max(self.speech.auto_after,self.speech.clock()+.6)
                if self.delivery["stage_id"] != stage:
                    raise ProtocolError("Playback stage mismatch.")
                if self.robot and payload["completion"] in {"audio_completed", "simulated_completed"} and self.delivery.get("robot_completion") != payload["completion"]:
                    raise ProtocolError("Wait for the robot bridge's completion result.")
                if self.robot and self.robot.job:
                    self.robot.cancel()
                else:
                    self.delivery.clear()
                    if self.after_speech_event:
                        action,self.after_speech_event=self.after_speech_event,{}
                        self.accept(action)
        elif kind == "COMPANION_PLAYBACK_READY":
            if self.robot and self.robot.job and self.robot.job["utterance_id"] == payload["utterance_id"] and self.robot.job["stage_id"] == stage:
                self.robot.job["ready"] = True
        elif kind == "COMPANION_CANCEL_REQUESTED":
            # Closing a panel is not consent to truncate speech. Stop and lost
            # game/worker leases remain the terminal cancellation mechanisms.
            pass
        elif kind == "HINT_REQUESTED" and self.preview_enabled and stage != "cave":
            # Coalesce rapid hint presses to the latest explicit hint level.
            self.hint_queue[:] = [(stage, payload["level"])]
        elif kind in {"PUZZLE_SOLVED", "STAGE_COMPLETED"}:
            self.hint_queue.clear()
        elif kind == "GAME_CONTEXT_CHANGED":
            self.game_stage = stage
            self.game_view = payload["view"]
            self.puzzle_active = payload["puzzle_active"]
            self.pause_id = payload["pause_id"]
        elif kind == "CONVERSATION_CHECKPOINT_REQUESTED":
            key, phase = payload["checkpoint_id"], payload["phase"]
            ordinary = phase in {"entry", "before", "after"} and stage != "cave"
            special = self.preview_enabled and ((phase == "welcome" and stage == "library") or (phase == "ending" and stage == "cave"))
            if not (ordinary or special):
                raise ProtocolError("Unsupported conversation phase.")
            lines = list(STAGES[stage].get(phase, []))
            if self.preview_enabled:
                lines = preview.schedule(stage, phase, self.condition)
            self.checkpoints.setdefault(key, Checkpoint(stage, phase, lines))
        elif kind in {"CHECKPOINT_ITEM_COMPLETED", "MOCK_REPEAT_REQUESTED", "MOCK_CHECKPOINT_BYPASSED"}:
            checkpoint = self.checkpoints.get(payload["checkpoint_id"])
            if checkpoint is None:
                raise ProtocolError("Checkpoint has not been requested.")
            if not checkpoint.done:
                if kind == "MOCK_CHECKPOINT_BYPASSED":
                    checkpoint.index, checkpoint.waiting = len(checkpoint.lines), False
                    if self.delivery.get("checkpoint_id") == payload["checkpoint_id"]:
                        self.cancel_delivery()
                elif checkpoint.waiting and payload["line_id"] == checkpoint.lines[checkpoint.index]:
                    if self.preview_enabled:
                        if kind == "MOCK_REPEAT_REQUESTED" and payload["line_id"] not in preview.QUESTIONS:
                            self.seen[event_id] = digest
                            return False  # Never replay a humour exposure on retries.
                        if kind == "CHECKPOINT_ITEM_COMPLETED" and payload["status"] == "ACKNOWLEDGED" and self.delivery:
                            raise ProtocolError("Wait for playback completion before acknowledgement.")
                        self.cancel_delivery()  # Wait for external cancellation before another delivery.
                        if kind == "CHECKPOINT_ITEM_COMPLETED" and payload["line_id"] in preview.QUESTIONS:
                            self.skipped_questions[payload["line_id"]] = payload["status"] != "ACKNOWLEDGED"
                    checkpoint.waiting = False
                    if kind == "CHECKPOINT_ITEM_COMPLETED":
                        checkpoint.index += 1
                else:
                    raise ProtocolError("Response does not match the active mock line.")
        elif kind == "PAUSE_REQUESTED":
            self.paused = True
        elif kind == "GAME_RESUMED":
            self.paused = False
        elif kind == "SESSION_TERMINATED":
            self.stop()
        self.seen[event_id] = digest
        self.drain()
        self.context()
        return False
