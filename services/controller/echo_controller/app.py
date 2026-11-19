"""Loopback-only game orchestration with transient role-bound speech metadata."""
import hmac
import time
from typing import Literal

from fastapi import FastAPI, Header, HTTPException, Query, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field

from .core import ProtocolError, Session
from .request_routing import route_request


class StartSession(BaseModel):
    model_config = ConfigDict(extra="forbid")
    condition: Literal["control", "humour"] = "control"
    mode: Literal["mock"] = "mock"
    preview: bool = False
    speech: bool = False
    conversation: bool = False
    push_to_talk: bool = False  # Conversation mode without automatic listening (hold B to reply).
    transcript: bool = False  # Opt-in private researcher transcript (transcripts/conversations.md).
    output: Literal["laptop", "bridge_simulator", "reachy_lite", "reachy_wireless", "reachy_mujoco", "reachy_control_simulator"] = "laptop"


class RobotPoll(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    session_id: str = Field(max_length=64)
    worker_id: str = Field(min_length=16, max_length=64, pattern=r"^[a-zA-Z0-9_-]+$")


class RobotResult(RobotPoll):
    utterance_id: str = Field(max_length=64)
    completion: Literal["audio_completed", "simulated_completed", "cancelled", "technical_failure"]


class GameEvent(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    version: Literal[1]
    session_id: str = Field(min_length=1, max_length=64, pattern=r"^[a-zA-Z0-9_-]+$")
    event_id: str = Field(min_length=1, max_length=128, pattern=r"^[a-zA-Z0-9_-]+$")
    stage_id: str = Field(max_length=24)
    event_type: str = Field(max_length=64)
    payload: dict = Field(max_length=8)


class CompanionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    session_id: str = Field(min_length=1, max_length=64, pattern=r"^[a-zA-Z0-9_-]+$")
    request_id: str = Field(min_length=1, max_length=128, pattern=r"^[a-zA-Z0-9_-]+$")
    context_id: str = Field(max_length=64, pattern=r"^[a-zA-Z0-9_-]*$")
    intent: Literal["STOP", "PAUSE", "RESUME", "SKIP", "REPEAT", "HINT", "WAIT", "NO_RECALL", "CLARIFY", "PRIVACY", "UNKNOWN"]
    confidence: float = Field(ge=0, le=1, allow_inf_nan=False)
    source: Literal["rasa", "safety", "manual", "unavailable", "unrecognized"]


class SpeechStarted(RobotPoll):
    capture_id: str = Field(min_length=1, max_length=32, pattern=r"^[a-f0-9]+$")


class SpeechResult(SpeechStarted):
    speech_detected: bool = False
    intent: CompanionRequest.model_fields["intent"].annotation | Literal["REPLY"]
    confidence: float = Field(ge=0,le=1,allow_inf_nan=False)
    source: CompanionRequest.model_fields["source"].annotation | Literal["reply"]
    reply_kind: str = Field(default='DEFAULT',max_length=40,pattern=r'^[A-Z_]+$')
    nickname: str = Field(default='',max_length=32)
    reply_text: str = Field(default='',max_length=220)


class SpeechLevel(SpeechStarted):
    level: float = Field(ge=0,le=1,allow_inf_nan=False)
    sequence: int = Field(ge=1)


class SpeechCaption(SpeechStarted):
    text: str = Field(max_length=4000)  # Long free answers are kept whole in the transcript.
    revision: int = Field(ge=1)
    final: bool = False


class SessionName(BaseModel):
    model_config=ConfigDict(extra='forbid',strict=True)
    name: str=Field(max_length=32)


def create_app() -> FastAPI:
    app = FastAPI(title="Echo Island external mock controller", docs_url=None, redoc_url=None)
    app.state.sessions = {}
    app.state.rasa_seen = False

    @app.middleware("http")
    async def guard(request: Request, call_next):
        host = request.headers.get("host", "").split(":")[0]
        if host not in {"127.0.0.1", "localhost", "testserver"} or request.headers.get("origin"):
            return JSONResponse({"detail": "Loopback development requests only."}, status_code=403)
        length = request.headers.get("content-length", "0")
        if not length.isdigit() or int(length) > 8192 or request.headers.get("transfer-encoding"):
            return JSONResponse({"detail": "Request body limit exceeded."}, status_code=413)
        return await call_next(request)

    @app.exception_handler(RequestValidationError)
    async def validation_error(_request, _exception):
        return JSONResponse({"detail": "Invalid request fields."}, status_code=422)

    @app.exception_handler(ProtocolError)
    async def protocol_error(_request, exception):
        return JSONResponse({"detail": str(exception)}, status_code=409)

    def session(session_id: str, token: str | None) -> Session:
        value = app.state.sessions.get(session_id)
        if value is None or not token or not hmac.compare_digest(value.token, token):
            raise HTTPException(401, "Unknown session or invalid token.")
        return value

    @app.get("/health")
    def health():
        return {"status": "ok", "mode": "mock", "robot": "not_connected", "rasa": "intent_requests_received" if app.state.rasa_seen else "not_connected",
                "retains_audio": False, "retains_answers": False}

    @app.get("/companion/context")
    def context(session_id: str, x_echo_session_token: str | None = Header(default=None)):
        value = session(session_id, x_echo_session_token)
        with value.lock:
            return value.context()

    @app.post("/companion/request")
    def companion_request(body: CompanionRequest, x_echo_session_token: str | None = Header(default=None)):
        value = session(body.session_id, x_echo_session_token)
        with value.lock:
            result = route_request(value, body.model_dump())
        if body.source == "rasa":
            app.state.rasa_seen = True
        return result

    @app.post("/session/start")
    def start(body: StartSession):
        if len(app.state.sessions) >= 16:
            raise HTTPException(409, "Restart the development controller to clear old sessions.")
        if body.output != "laptop" and not body.preview:
            raise HTTPException(422, "Robot output requires the draft Library preview.")
        if body.conversation and (not body.speech or not body.preview):
            raise HTTPException(422, "Conversation requires explicit speech and preview mode.")
        value = Session(body.condition, preview_enabled=body.preview, output=body.output, speech_enabled=body.speech, conversation_enabled=body.conversation, push_to_talk=body.push_to_talk)
        if body.transcript:
            from .transcript import TranscriptLog
            value.transcript = TranscriptLog(body.condition, body.output)
        app.state.sessions[value.session_id] = value
        result = {"session_id": value.session_id, "token": value.token, "mode": "mock"}
        if value.transcript:
            result["participant_id"] = value.transcript.participant_id  # Launcher console only.
        if value.robot:
            result["robot_token"] = value.robot.token
        if value.speech:
            result["speech_token"] = value.speech.token
        return result

    def speech_session(body, token):
        value = app.state.sessions.get(body.session_id)
        if value is None or value.speech is None or not token or not hmac.compare_digest(value.speech.token, token):
            raise HTTPException(401, "Unknown speech session or invalid speech token.")
        return value

    @app.post("/speech/poll")
    def speech_poll(body: RobotPoll, x_echo_speech_token: str | None = Header(default=None)):
        value = speech_session(body, x_echo_speech_token)
        with value.lock:
            return value.speech.poll(value, body.worker_id)

    @app.post("/speech/result")
    def speech_result(body: SpeechResult, x_echo_speech_token: str | None = Header(default=None)):
        value = speech_session(body, x_echo_speech_token)
        with value.lock:
            if value.speech.worker_id != body.worker_id:
                raise HTTPException(409, "Worker does not own this session.")
            value.speech.finish(value, body.model_dump())
        return {"accepted":True, "capture_id":body.capture_id}

    @app.post("/speech/started")
    def speech_started(body: SpeechStarted, x_echo_speech_token: str | None = Header(default=None)):
        value = speech_session(body, x_echo_speech_token)
        with value.lock:
            if value.speech.worker_id != body.worker_id:
                raise HTTPException(409, "Worker does not own this session.")
            if value.speech.job and value.speech.job["capture_id"] == body.capture_id and value.speech.job["phase"] == "listen":
                value.speech.status(value, body.capture_id, "LISTENING")
        return {"accepted":True}

    @app.post("/speech/processing")
    def speech_processing(body: SpeechStarted, x_echo_speech_token: str | None = Header(default=None)):
        value = speech_session(body,x_echo_speech_token)
        with value.lock:
            if value.speech.worker_id != body.worker_id:
                raise HTTPException(409,"Worker does not own this session.")
            if value.speech.job and value.speech.job["capture_id"] == body.capture_id and value.speech.job["phase"] in {"finish","processing"}:
                if value.speech.job['phase']!='processing':
                    value.speech.job['processing_at']=value.speech.clock()
                value.speech.job["phase"]="processing"
                value.speech.last_seen=value.speech.clock()
                value.speech.status(value,body.capture_id,"PROCESSING")
        return {"accepted":True}

    @app.post('/speech/level')
    def speech_level(body: SpeechLevel,x_echo_speech_token: str | None = Header(default=None)):
        value=speech_session(body,x_echo_speech_token)
        with value.lock:
            if value.speech.worker_id!=body.worker_id:
                raise HTTPException(409,'Worker does not own this session.')
            value.speech.update_meter(body.capture_id,body.level,body.sequence)
        return {'accepted':True}

    @app.post('/speech/caption')
    def speech_caption(body: SpeechCaption,x_echo_speech_token: str | None = Header(default=None)):
        value=speech_session(body,x_echo_speech_token)
        with value.lock:
            if value.speech.worker_id!=body.worker_id:
                raise HTTPException(409,'Worker does not own this session.')
            value.speech.update_caption(value,body.capture_id,body.text,body.revision,body.final)
        return {'accepted':True}

    @app.post('/session/name')
    def session_name(body: SessionName,session_id: str,x_echo_session_token: str | None = Header(default=None)):
        value=session(session_id,x_echo_session_token)
        from .reply_understanding import extract_nickname
        with value.lock:
            if not value.conversation_enabled or value.stopped:
                raise HTTPException(409,'No active conversation session.')
            name=extract_nickname(body.name) if body.name else ''
            if body.name and not name:
                raise HTTPException(422,'Use a short name containing letters, spaces, apostrophes or hyphens.')
            value.nickname=name
        return {'name':name}

    @app.post("/speech/end-turn")
    def speech_end_turn(body: SpeechStarted, x_echo_speech_token: str | None = Header(default=None)):
        value=speech_session(body,x_echo_speech_token)
        with value.lock:
            if value.speech.worker_id != body.worker_id:
                raise HTTPException(409,"Worker does not own this session.")
            job=value.speech.job
            if job and job["capture_id"]==body.capture_id and job.get("automatic") and job["phase"]=="listen":
                job["phase"]="finish"
        return {"accepted":True}

    def robot_session(body, token):
        value = app.state.sessions.get(body.session_id)
        if value is None or value.robot is None or not token or not hmac.compare_digest(value.robot.token, token):
            raise HTTPException(401, "Unknown robot session or invalid robot token.")
        return value

    @app.post("/robot/poll")
    def robot_poll(body: RobotPoll, x_echo_robot_token: str | None = Header(default=None)):
        value = robot_session(body, x_echo_robot_token)
        with value.lock:
            return value.robot.poll(value, body.worker_id)

    @app.post("/robot/result")
    def robot_result(body: RobotResult, x_echo_robot_token: str | None = Header(default=None)):
        value = robot_session(body, x_echo_robot_token)
        with value.lock:
            if value.robot.worker_id != body.worker_id:
                raise HTTPException(409, "Worker does not own this session.")
            value.robot.finish(value, body.utterance_id, body.completion)
        return {"accepted": True, "utterance_id": body.utterance_id}

    @app.post("/game/event")
    def event(body: GameEvent, x_echo_session_token: str | None = Header(default=None)):
        value = session(body.session_id, x_echo_session_token)
        with value.lock:
            duplicate = value.accept(body.model_dump())
        return {"accepted": True, "event_id": body.event_id, "duplicate": duplicate}

    @app.get("/game/commands")
    def commands(session_id: str, after: int = Query(default=0, ge=0), x_echo_session_token: str | None = Header(default=None)):
        value = session(session_id, x_echo_session_token)
        with value.lock:
            value.last_game_poll=time.monotonic()
            if value.speech:
                value.speech.expire(value)
            if value.robot:
                value.robot.game_seen = value.robot.clock()
                value.robot.expire(value)
            if after > len(value.commands):
                raise HTTPException(409, "Command cursor is ahead of this session.")
            batch = value.commands[after:after + 32]
            microphone=value.speech.meter_state() if value.speech else {'capture_id':'','level':0.,'sequence':0,'live':False}
            caption=value.speech.caption_state(value) if value.speech else {}
            nickname=value.nickname
        return {"commands": batch, "cursor": batch[-1]["cursor"] if batch else after, "mode": "mock",'microphone':microphone,
                'speech_caption':caption,'session_name':nickname}

    @app.post("/session/stop")
    def stop(session_id: str, x_echo_session_token: str | None = Header(default=None)):
        value = session(session_id, x_echo_session_token)
        with value.lock:
            value.stop()
        return {"stopped": True}

    return app


app = create_app()
