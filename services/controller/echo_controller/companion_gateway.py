"""Ephemeral command gateway for a future STT stream or explicit typed development input.

Only whole, public control phrases reach Rasa's stateless /model/parse endpoint.
Arbitrary answers never leave this function and never enter the controller API.
"""
import argparse
import json
import math
import re
import unicodedata
import uuid
from pathlib import Path
from urllib.parse import urlencode, urlsplit
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener

BANK = json.loads((Path(__file__).resolve().parents[2] / "protocol/control_phrases.json").read_text(encoding="utf-8"))
PHRASES = {phrase: intent for intent, phrases in BANK.items() for phrase in phrases}


def normalize(text: str) -> str:
    value = unicodedata.normalize("NFKC", text).casefold().replace("’", "'").strip()
    return " ".join(re.sub(r"[.!?,;:]+$", "", value).split())


def local_url(value: str) -> str:
    parts = urlsplit(value)
    if (parts.scheme != "http" or parts.hostname not in {"127.0.0.1", "localhost"}
            or not parts.port or parts.path not in {"", "/"} or parts.query or parts.fragment
            or parts.username or parts.password):
        raise ValueError("Only an explicit loopback service URL is supported.")
    return value.rstrip("/")


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *_args, **_kwargs):
        return None


def exchange(url, payload=None, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["X-Echo-Session-Token"] = token
    request = Request(url, data=None if payload is None else json.dumps(payload).encode(), headers=headers)
    with build_opener(ProxyHandler({}), NoRedirect()).open(request, timeout=2) as response:
        raw = response.read(65537)
    if len(raw) > 65536:
        raise ValueError("Service response exceeded the development limit.")
    return json.loads(raw)


class RasaParser:
    def __init__(self, url="http://127.0.0.1:5005"):
        self.url = local_url(url)

    def parse(self, phrase):
        result = exchange(self.url + "/model/parse", {"text": phrase})
        intent = result.get("intent", {})
        name, confidence = intent.get("name"), intent.get("confidence")
        if not isinstance(name, str) or not isinstance(confidence, (float, int)) or not math.isfinite(confidence):
            raise ValueError("Recognizer response is unavailable.")
        return name.upper(), float(confidence)


# Natural rewordings ("could you please repeat the question?") are decided by
# Rasa. Its conversation model is trained on these commands AND on the answer
# categories, so it separates "I love science books" (an answer) from "can we
# skip this one" (a command). Only confident command intents are accepted, and
# ending the session needs extra certainty.
REWORD_CONFIDENCE = 0.8
STOP_CONFIDENCE = 0.95
# "don't skip", "please do not stop", "no need to repeat", "never pause": a negation
# shortly before the command word flips its meaning, whatever the model says.
NEGATED_COMMAND = re.compile(
    r"\b(?:don'?t|do not|not|never|no need to|no)\b(?:\s+\w+){0,2}?\s+"
    r"(?:stop|skip|pause|repeat|hint|quit|end|resume|continue|wait)", re.IGNORECASE)
# Short yes/no/filler replies are answers, never commands.
FILLERS = {"yes", "yeah", "yep", "no", "nope", "ok", "okay", "sure", "maybe", "hmm", "no, not really", "not really"}


def _reworded_control(phrase, parser):
    if not phrase or len(phrase.split()) > 15 or phrase in FILLERS or NEGATED_COMMAND.search(phrase):
        return None
    try:
        name, confidence = parser.parse(phrase)
    except Exception:
        return None
    if name not in BANK or not REWORD_CONFIDENCE <= confidence <= 1:
        return None
    if name == "STOP" and confidence < STOP_CONFIDENCE:
        return None
    return name, confidence, "rasa"


def classify_control(text, parser):
    """No raw utterance is included in the result, exception messages or controller payload."""
    if not isinstance(text, str) or len(text) > 500:
        return "UNKNOWN", 0.0, "unrecognized"
    phrase = normalize(text)
    expected = PHRASES.get(phrase)
    if expected == "STOP":
        return "STOP", 1.0, "safety"  # Explicit stop survives an NLU outage.
    if expected is None:
        return _reworded_control(phrase, parser) or ("UNKNOWN", 0.0, "unrecognized")
    try:
        name, confidence = parser.parse(phrase)
    except Exception:
        return "UNKNOWN", 0.0, "unavailable"
    if name != expected or not 0.8 <= confidence <= 1:
        return "UNKNOWN", 0.0, "rasa"
    return name, confidence, "rasa"


class CommandGateway:
    def __init__(self, config, parser=None):
        self.url = local_url(config["url"])
        self.session_id = config["session_id"]
        self.token = config["token"]
        self.parser = parser or RasaParser()

    def dispatch(self, text, request_id=None):
        # Capture context before recognition so a delayed skip cannot affect the next question.
        context = exchange(self.url + "/companion/context?" + urlencode({"session_id": self.session_id}), token=self.token)
        intent, confidence, source = classify_control(text, self.parser)
        return exchange(self.url + "/companion/request", {
            "session_id": self.session_id, "request_id": request_id or uuid.uuid4().hex,
            "context_id": context["context_id"], "intent": intent, "confidence": confidence, "source": source,
        }, self.token)


def main():
    cli = argparse.ArgumentParser(description="Typed development control input; no microphone or answers collected.")
    cli.add_argument("--config", type=Path)
    cli.add_argument("--rasa-url", default="http://127.0.0.1:5005")
    cli.add_argument("--control", choices=[intent.lower() for intent in BANK], help="Send one public synthetic control phrase, then exit.")
    args = cli.parse_args()
    try:
        path = args.config
        if path is None:
            files = list((Path(__file__).resolve().parents[3] / "tools/runtime").glob("*.session.json"))
            if len(files) != 1:
                raise ValueError("Run one controller game, or specify its session configuration with --config.")
            path = files[0]
        gateway = CommandGateway(json.loads(path.read_text(encoding="utf-8-sig")), RasaParser(args.rasa_url))
    except Exception:
        print("No usable local session. Start Play-Controller.ps1 first; specify --config if several games are running.")
        return 1
    if args.control:
        try:
            result = gateway.dispatch(BANK[args.control.upper()][0])
            print(result["status"] + (": " + result["notice_id"] if "notice_id" in result else ""))
            return 0
        except Exception:
            print("Control request was not delivered. Use the game's controls.")
            return 1
    print("DEVELOPMENT CONTROL INPUT — type controls such as pause, resume, repeat or skip. Ctrl+C exits this terminal.")
    print("No microphone is active. Do not type personal answers; unknown input is discarded.")
    while True:
        try:
            text = input("control> ")
            result = gateway.dispatch(text)
            text = None
            print(result["status"] + (": " + result["notice_id"] if "notice_id" in result else ""))
        except (EOFError, KeyboardInterrupt):
            print("\nControl terminal closed; the game has its own Pause/Stop buttons.")
            return 0
        except Exception:
            print("Request not delivered. Use the game's controls and check the local services.")
        finally:
            text = None


if __name__ == "__main__":
    raise SystemExit(main())
