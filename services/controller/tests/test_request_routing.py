import unittest
from unittest.mock import Mock

from fastapi.testclient import TestClient

from echo_controller.app import create_app
from echo_controller.companion_gateway import BANK, RasaParser, classify_control, local_url


class RequestRoutingTests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(create_app())
        self.config = self.client.post("/session/start", json={"mode": "mock", "condition": "control"}).json()
        self.headers = {"X-Echo-Session-Token": self.config["token"]}
        self.number = 0
        self.event("SESSION_READY")

    def event(self, kind, **payload):
        self.number += 1
        response = self.client.post("/game/event", json={"version": 1, "session_id": self.config["session_id"], "event_id": f"event-{self.number}", "stage_id": "library", "event_type": kind, "payload": payload}, headers=self.headers)
        self.assertEqual(response.status_code, 200, response.text)

    def context(self):
        response = self.client.get("/companion/context", params={"session_id": self.config["session_id"]}, headers=self.headers)
        self.assertEqual(response.status_code, 200)
        return response.json()

    def commands(self):
        return self.client.get("/game/commands", params={"session_id": self.config["session_id"]}, headers=self.headers).json()["commands"]

    def request(self, intent, *, context=None, request_id=None, source="manual", confidence=1.0):
        self.number += 1
        body = {"session_id": self.config["session_id"], "request_id": request_id or f"request-{self.number}", "context_id": context or self.context()["context_id"], "intent": intent, "confidence": confidence, "source": source}
        return self.client.post("/companion/request", json=body, headers=self.headers)

    def question(self):
        self.event("LETTER_OPENED", letter_id="L1")
        self.event("LETTER_NARRATION_COMPLETED", letter_id="L1", completion="audio_completed", replay=False)
        self.event("CONVERSATION_CHECKPOINT_REQUESTED", checkpoint_id="library_before", phase="before")
        self.event("CHECKPOINT_ITEM_COMPLETED", checkpoint_id="library_before", line_id="H1", status="ACKNOWLEDGED", mock=True)
        self.event("GAME_CONTEXT_CHANGED", view="checkpoint", puzzle_active=False, pause_id="")

    def test_pause_and_explicit_resume_with_pause_identity(self):
        self.event("GAME_CONTEXT_CHANGED", view="explore", puzzle_active=False, pause_id="")
        self.assertEqual(self.request("PAUSE").json()["status"], "applied")
        self.assertEqual(self.commands()[-1]["command"]["type"], "PAUSE_GAME")
        self.event("PAUSE_REQUESTED")
        self.event("GAME_CONTEXT_CHANGED", view="explore", puzzle_active=False, pause_id="1234567890abcdef")
        self.request("RESUME")
        command = self.commands()[-1]["command"]
        self.assertEqual(command["type"], "RESUME_PLAY")
        self.assertEqual(command["pause_id"], "1234567890abcdef")
        self.assertTrue(self.context()["paused"])
        self.event("GAME_RESUMED")
        self.assertFalse(self.context()["paused"])

    def test_resume_cannot_use_an_old_pause_context(self):
        self.event("PAUSE_REQUESTED")
        self.event("GAME_CONTEXT_CHANGED", view="explore", puzzle_active=False, pause_id="1234567890abcdef")
        old = self.context()["context_id"]
        self.event("GAME_RESUMED")
        self.event("PAUSE_REQUESTED")
        self.event("GAME_CONTEXT_CHANGED", view="explore", puzzle_active=False, pause_id="abcdef1234567890")
        self.assertEqual(self.request("RESUME", context=old).json()["notice_id"], "STALE_REQUEST")
        self.assertNotIn("RESUME_PLAY", [item["command"]["type"] for item in self.commands()])

    def test_skip_and_no_recall_need_game_acknowledgement(self):
        for intent in ("SKIP", "NO_RECALL"):
            with self.subTest(intent=intent):
                self.setUp()
                self.question()
                self.assertEqual(self.request(intent).json()["status"], "applied")
                command = self.commands()[-1]["command"]
                self.assertEqual(command["type"], "COMPANION_CHECKPOINT_ACTION")
                self.assertEqual(command["action"], intent.lower())
                self.assertEqual(command["line_id"], "G1")
                self.assertEqual(self.context()["line_id"], "G1")

    def test_repeat_only_targets_current_question_not_a_humour_line(self):
        self.event("LETTER_NARRATION_COMPLETED", letter_id="L1", completion="audio_completed", replay=False)
        self.event("CONVERSATION_CHECKPOINT_REQUESTED", checkpoint_id="library_before", phase="before")
        self.event("GAME_CONTEXT_CHANGED", view="checkpoint", puzzle_active=False, pause_id="")
        self.assertEqual(self.request("REPEAT").json()["notice_id"], "NO_QUESTION")
        self.event("CHECKPOINT_ITEM_COMPLETED", checkpoint_id="library_before", line_id="H1", status="ACKNOWLEDGED", mock=True)
        self.request("REPEAT")
        self.assertEqual(self.commands()[-1]["command"]["action"], "repeat")
        self.assertEqual(self.context()["line_id"], "G1")

    def test_late_skip_does_not_skip_a_different_turn(self):
        self.question()
        old = self.context()["context_id"]
        self.event("CHECKPOINT_ITEM_COMPLETED", checkpoint_id="library_before", line_id="G1", status="SKIPPED", mock=True)
        self.assertEqual(self.request("SKIP", context=old).json()["notice_id"], "STALE_REQUEST")

    def test_hint_is_restricted_to_an_active_puzzle(self):
        self.question()
        self.assertEqual(self.request("HINT").json()["notice_id"], "HINT_UNAVAILABLE")
        self.event("GAME_CONTEXT_CHANGED", view="puzzle", puzzle_active=True, pause_id="")
        self.request("HINT")
        self.assertEqual(self.commands()[-1]["command"]["type"], "REQUEST_HINT")

    def test_wait_privacy_clarify_unknown_do_not_advance(self):
        self.question()
        for intent in ("WAIT", "PRIVACY", "CLARIFY", "UNKNOWN"):
            self.assertEqual(self.request(intent).json()["status"], "notice")
            self.assertEqual(self.context()["line_id"], "G1")

    def test_duplicate_and_conflicting_requests(self):
        context = self.context()["context_id"]
        first = self.request("PAUSE", context=context, request_id="same").json()
        count = len(self.commands())
        second = self.request("PAUSE", context=context, request_id="same").json()
        self.assertFalse(first["duplicate"])
        self.assertTrue(second["duplicate"])
        self.assertEqual(len(self.commands()), count)
        self.assertEqual(self.request("STOP", context=context, request_id="same").status_code, 409)

    def test_explicit_safety_stop_survives_stale_context(self):
        self.request("STOP", source="safety", context="stale")
        self.assertTrue(self.context()["stopped"])
        count = len(self.commands())
        self.request("STOP", source="safety")
        self.assertEqual(len(self.commands()), count)

    def test_only_stop_is_actionable_before_game_begin(self):
        from echo_controller.core import Session
        from echo_controller.request_routing import route_request
        session = Session("control")
        for number, intent in enumerate(("PAUSE", "STOP")):
            result = route_request(session, {"request_id": f"prestart-{number}", "context_id": session.context()["context_id"], "intent": intent, "confidence": 1.0, "source": "manual"})
            self.assertEqual(result["status"], "notice" if intent == "PAUSE" else "applied")
        self.assertTrue(session.stopped)

    def test_low_confidence_never_authorizes_skip_or_stop(self):
        self.question()
        for intent in ("SKIP", "STOP", "PAUSE"):
            self.assertEqual(self.request(intent, source="rasa", confidence=0.2).json()["notice_id"], "UNRECOGNIZED")
        self.assertFalse(self.context()["stopped"])

    def test_raw_text_rejected_and_not_echoed(self):
        response = self.client.post("/companion/request", json={"text": "PRIVATE-SENTINEL"}, headers=self.headers)
        self.assertEqual(response.status_code, 422)
        self.assertNotIn("PRIVATE-SENTINEL", response.text)

    def test_new_endpoints_require_session_token(self):
        self.assertEqual(self.client.get("/companion/context", params={"session_id": self.config["session_id"]}).status_code, 401)
        body = {"session_id": self.config["session_id"], "request_id": "no-token", "context_id": "", "intent": "STOP", "confidence": 1.0, "source": "manual"}
        self.assertEqual(self.client.post("/companion/request", json=body).status_code, 401)


class GatewayTests(unittest.TestCase):
    def test_all_public_examples_have_the_expected_mapping(self):
        for intent, examples in BANK.items():
            for example in examples:
                parser = Mock()
                parser.parse.return_value = (intent, 1.0)
                actual, _, _ = classify_control(example, parser)
                self.assertEqual(actual, intent)

    def test_personal_answers_and_negated_commands_never_reach_rasa(self):
        parser = Mock()
        for text in ("No, not really", "please do not stop", "I stopped reading that book", "I worry about PRIVATE-SENTINEL", "don't skip the question", "I need help with my family", "yes", ""):
            self.assertEqual(classify_control(text, parser)[0], "UNKNOWN")
        parser.parse.assert_not_called()

    def test_case_and_punctuation_normalize(self):
        parser = Mock()
        parser.parse.return_value = ("PAUSE", 1.0)
        self.assertEqual(classify_control("  PAUSE!!!  ", parser)[0], "PAUSE")

    def test_outage_and_wrong_intent_do_not_fallback_to_guesses(self):
        parser = Mock()
        parser.parse.side_effect = RuntimeError("PRIVATE-SENTINEL")
        self.assertEqual(classify_control("pause", parser), ("UNKNOWN", 0.0, "unavailable"))
        self.assertEqual(classify_control("stop", parser), ("STOP", 1.0, "safety"))
        parser.parse.side_effect = None
        parser.parse.return_value = ("SKIP", 1.0)
        self.assertEqual(classify_control("pause", parser)[0], "UNKNOWN")

    def test_non_loopback_or_credential_urls_are_rejected(self):
        for url in ("https://example.com", "http://127.0.0.1:5005/elsewhere", "http://user:secret@localhost:5005", "http://localhost:5005?token=secret"):
            with self.assertRaises(ValueError):
                local_url(url)
