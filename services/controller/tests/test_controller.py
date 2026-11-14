import copy
import unittest

from fastapi.testclient import TestClient

from echo_controller.app import create_app
from echo_controller.core import STAGES


class ControllerTests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(create_app())
        self.sequence = 0
        self.start()

    def start(self, condition="control"):
        result = self.client.post("/session/start", json={"condition": condition, "mode": "mock"})
        self.assertEqual(result.status_code, 200)
        self.config = result.json()
        self.headers = {"X-Echo-Session-Token": self.config["token"]}
        self.send("SESSION_READY")

    def event(self, kind, stage="library", **payload):
        self.sequence += 1
        return {"version": 1, "session_id": self.config["session_id"],
                "event_id": f"test-{self.sequence}", "stage_id": stage, "event_type": kind, "payload": payload}

    def post(self, event):
        return self.client.post("/game/event", json=event, headers=self.headers)

    def send(self, kind, stage="library", **payload):
        response = self.post(self.event(kind, stage, **payload))
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def commands(self, after=0):
        response = self.client.get("/game/commands", params={"session_id": self.config["session_id"], "after": after}, headers=self.headers)
        self.assertEqual(response.status_code, 200)
        return response.json()["commands"]

    def ready_letter(self, stage="library"):
        letter = STAGES[stage]["letter_id"]
        self.send("LETTER_OPENED", stage, letter_id=letter)
        self.send("LETTER_NARRATION_COMPLETED", stage, letter_id=letter, completion="explicit_skip_or_caption_ack", replay=False)

    def request(self, stage="library", phase="before"):
        self.send("CONVERSATION_CHECKPOINT_REQUESTED", stage, checkpoint_id=stage + "_" + phase, phase=phase)

    def test_narrator_and_game_audio_gate(self):
        self.send("LETTER_OPENED", letter_id="L1")
        self.send("GAME_AUDIO_STATE_CHANGED", active=True)
        self.request()
        self.assertEqual(self.commands(), [])
        self.send("LETTER_NARRATION_COMPLETED", letter_id="L1", completion="audio_completed", replay=False)
        self.assertEqual(self.commands(), [])
        self.send("GAME_AUDIO_STATE_CHANGED", active=False)
        self.assertEqual(self.commands()[0]["command"]["line_id"], "H1")

    def test_checkpoint_after_narration_is_not_lost(self):
        self.ready_letter()
        self.request()
        self.assertEqual(len(self.commands()), 1)

    def test_retries_and_conflicting_duplicate(self):
        self.ready_letter()
        event = self.event("CONVERSATION_CHECKPOINT_REQUESTED", checkpoint_id="library_before", phase="before")
        self.assertFalse(self.post(event).json()["duplicate"])
        self.assertTrue(self.post(event).json()["duplicate"])
        changed = copy.deepcopy(event)
        changed["payload"] = {"checkpoint_id": "library_after", "phase": "after"}
        self.assertEqual(self.post(changed).status_code, 409)
        self.assertEqual(len(self.commands()), 1)

    def test_repeated_checkpoint_under_new_id_is_idempotent(self):
        self.ready_letter()
        self.request()
        self.request()
        self.assertEqual(len(self.commands()), 1)

    def test_repeat_has_same_text_and_does_not_advance(self):
        self.ready_letter()
        self.request()
        self.send("MOCK_REPEAT_REQUESTED", checkpoint_id="library_before", line_id="H1")
        commands = self.commands()
        self.assertEqual(commands[0]["command"]["text"], commands[1]["command"]["text"])
        self.assertEqual(commands[1]["command"]["line_id"], "H1")

    def test_pause_defers_commands(self):
        self.ready_letter()
        self.send("PAUSE_REQUESTED")
        self.request()
        self.assertEqual(self.commands(), [])
        self.send("GAME_RESUMED")
        self.assertEqual(len(self.commands()), 1)

    def test_stop_is_terminal_and_idempotent(self):
        response = self.client.post("/session/stop", params={"session_id": self.config["session_id"]}, headers=self.headers)
        self.assertEqual(response.status_code, 200)
        self.client.post("/session/stop", params={"session_id": self.config["session_id"]}, headers=self.headers)
        self.assertEqual([item["command"]["type"] for item in self.commands()], ["SESSION_STOP"])
        self.send("SESSION_TERMINATED")
        self.assertEqual(len(self.commands()), 1)
        self.assertEqual(self.post(self.event("GAME_RESUMED")).status_code, 409)

    def test_no_raw_answer_or_condition_fields_accepted(self):
        for field in ("text", "answer", "transcript", "audio", "condition"):
            event = self.event("HINT_REQUESTED", **{field: "PRIVATE-SENTINEL"})
            response = self.post(event)
            self.assertEqual(response.status_code, 409)
            self.assertNotIn("PRIVATE-SENTINEL", response.text)
        event = self.event("SESSION_READY")
        event["condition"] = "PRIVATE-SENTINEL"
        response = self.post(event)
        self.assertEqual(response.status_code, 422)
        self.assertNotIn("PRIVATE-SENTINEL", response.text)

    def test_missing_and_wrong_tokens_are_rejected(self):
        event = self.event("TUTORIAL_COMPLETED")
        self.assertEqual(self.client.post("/game/event", json=event).status_code, 401)
        self.assertEqual(self.client.post("/game/event", json=event, headers={"X-Echo-Session-Token": "wrong"}).status_code, 401)

    def test_metadata_ids_cannot_carry_arbitrary_utterances(self):
        for event in (
            self.event("NPC_REACHED", npc_id="PRIVATE-SENTINEL"),
            self.event("PUZZLE_SOLVED", puzzle_id="PRIVATE-SENTINEL"),
            self.event("GEM_COLLECTED", gem_id="PRIVATE-SENTINEL", count=1),
            self.event("LETTER_NARRATION_COMPLETED", letter_id="L1", completion="PRIVATE-SENTINEL", replay=False),
        ):
            response = self.post(event)
            self.assertEqual(response.status_code, 409)
            self.assertNotIn("PRIVATE-SENTINEL", response.text)

    def test_malformed_phase_letter_and_status_are_rejected(self):
        for event in (
            self.event("CONVERSATION_CHECKPOINT_REQUESTED", checkpoint_id="library_before", phase="after"),
            self.event("LETTER_OPENED", letter_id="L2"),
            self.event("CHECKPOINT_ITEM_COMPLETED", checkpoint_id="library_before", line_id="H1", status="FREE_TEXT", mock=True),
        ):
            self.assertEqual(self.post(event).status_code, 409)

    def test_foreign_origin_host_and_oversized_body_are_rejected(self):
        self.assertEqual(self.client.get("/health", headers={"Origin": "https://example.com"}).status_code, 403)
        self.assertEqual(self.client.get("/health", headers={"Host": "example.com"}).status_code, 403)
        self.assertEqual(self.client.post("/game/event", content="x" * 8193).status_code, 413)

    def test_health_and_commands_do_not_disclose_assignment(self):
        self.assertNotIn("condition", self.config)
        health = self.client.get("/health").json()
        self.assertEqual(health["robot"], "not_connected")
        self.assertFalse(health["retains_answers"])
        self.assertFalse(health["retains_audio"])
        self.assertNotIn("condition", health)

    def test_only_one_mock_line_active_at_a_time(self):
        self.ready_letter()
        self.request()
        self.request("market", "entry")
        self.assertEqual(len(self.commands()), 1)

    def test_bypass_before_narration_never_emits_late_questions(self):
        self.request()
        self.send("MOCK_CHECKPOINT_BYPASSED", checkpoint_id="library_before")
        self.ready_letter()
        self.assertEqual([item["command"]["type"] for item in self.commands()], ["RESUME_GAME"])

    def test_all_stages_all_optional_outcomes_both_assignments(self):
        traces = []
        for condition in ("control", "humour"):
            self.start(condition)
            for stage, data in STAGES.items():
                if stage == "cave":
                    continue
                for phase in ("entry", "before", "after"):
                    if phase == "before":
                        self.ready_letter(stage)
                    self.request(stage, phase)
                    for line in data[phase]:
                        current = self.commands()[-1]["command"]
                        self.assertEqual(current["line_id"], line)
                        status = ("ACKNOWLEDGED", "SKIPPED", "NO_RECALL", "TECHNICAL_FAILURE")[self.sequence % 4]
                        self.send("CHECKPOINT_ITEM_COMPLETED", stage, checkpoint_id=stage + "_" + phase, line_id=line, status=status, mock=True)
                    self.assertEqual(self.commands()[-1]["command"]["type"], "RESUME_GAME")
            traces.append([{key: value for key, value in item["command"].items() if key not in {"command_id", "session_id"}} for item in self.commands()])
        self.assertEqual(traces[0], traces[1])


if __name__ == "__main__":
    unittest.main()
