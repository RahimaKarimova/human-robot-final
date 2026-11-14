"""Context-bound control intents only. No utterances, disclosure scoring or generated speech."""
import hashlib
import json

from .core import ProtocolError, Session
from .preview import CONVERSATION_NOTICES, conversation_notice

INTENTS = {"STOP", "PAUSE", "RESUME", "SKIP", "REPEAT", "HINT", "WAIT", "NO_RECALL", "CLARIFY", "PRIVACY", "UNKNOWN"}
NOTICE_IDS = {"UNRECOGNIZED", "UNAVAILABLE", "STALE_REQUEST", "WAITING", "REPEAT_OR_SKIP", "DEVELOPMENT_PRIVACY", "HINT_UNAVAILABLE", "NO_QUESTION", "ALREADY_STOPPED"}


def route_request(session: Session, request: dict) -> dict:
    request_id, intent = request["request_id"], request["intent"]
    digest = hashlib.sha256(json.dumps(request, sort_keys=True).encode()).hexdigest()
    previous = session.control_requests.get(request_id)
    if previous:
        if previous[0] != digest:
            raise ProtocolError("Request ID was reused with different fields.")
        return {**previous[1], "duplicate": True}
    if len(session.control_requests) >= 10000:
        raise ProtocolError("Development request limit reached.")
    if request["source"] == "safety" and intent != "STOP":
        raise ProtocolError("Only STOP may bypass the recognizer.")
    if request["source"] in {"unavailable", "unrecognized"} and intent != "UNKNOWN":
        raise ProtocolError("Unavailable recognition cannot authorize an action.")
    context = session.context()
    result = {"request_id": request_id, "status": "applied", "duplicate": False}

    def notice(notice_id):
        result["status"] = "notice"
        result["notice_id"] = notice_id
        session.command("COMPANION_NOTICE", notice_id=notice_id, request_id=request_id)
        if (session.conversation_enabled and notice_id in CONVERSATION_NOTICES
                and context['question'] and context['view']=='checkpoint' and not session.delivery and not session.audio_active and not session.paused):
            session.deliver('COMPANION_CUE',context['stage_id'],checkpoint_id=context['checkpoint_id'],line_id=context['line_id'],
                            conversation_notice=True,**conversation_notice(notice_id))
            result['status']='applied'

    if session.stopped:
        result.update(status="already_stopped", notice_id="ALREADY_STOPPED")
    elif intent == "STOP" and request["source"] == "safety":
        session.stop()  # Explicit stop is never withheld for stale context or NLU outage.
    elif intent == "UNKNOWN" or request["confidence"] < 0.8:
        notice("UNAVAILABLE" if request["source"] == "unavailable" else "UNRECOGNIZED")
    elif intent == "STOP":
        session.stop()
    elif not session.started:
        notice("UNAVAILABLE")
    elif intent == "PAUSE":
        if not session.paused:
            session.paused = True
            session.command("PAUSE_GAME")
    elif request["context_id"] != context["context_id"]:
        notice("STALE_REQUEST")
    elif intent == "RESUME":
        if session.paused and session.pause_id:
            session.command("RESUME_PLAY", pause_id=session.pause_id)
            # Wait for Godot's GAME_RESUMED acknowledgement before output resumes.
        else:
            notice("UNAVAILABLE")
    elif intent == "WAIT":
        notice("WAITING")  # No auto-answer, timeout or question advancement.
    elif intent == "PRIVACY":
        notice("DEVELOPMENT_PRIVACY")
    elif intent == "CLARIFY":
        notice("REPEAT_OR_SKIP")  # No invented/rephrased research question.
        if session.conversation_enabled and context['question'] and context['view']=='checkpoint' and not session.paused:
            session.command('COMPANION_CHECKPOINT_ACTION',checkpoint_id=context['checkpoint_id'],line_id=context['line_id'],action='repeat',request_id=request_id)
    elif session.paused:
        notice("UNAVAILABLE")
    elif intent == "HINT":
        if context["view"] == "puzzle" and context["puzzle_active"]:
            session.command("REQUEST_HINT", stage_id=context["stage_id"], request_id=request_id)
        else:
            notice("HINT_UNAVAILABLE")
    elif intent in {"SKIP", "REPEAT", "NO_RECALL"}:
        if context["view"] == "checkpoint" and context["question"]:
            session.command("COMPANION_CHECKPOINT_ACTION", checkpoint_id=context["checkpoint_id"],
                            line_id=context["line_id"], action=intent.lower(), request_id=request_id)
        else:
            notice("NO_QUESTION")
    session.context()
    session.control_requests[request_id] = (digest, dict(result))
    return result
