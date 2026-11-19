import tempfile
import unittest
from pathlib import Path

from echo_controller.core import Session
from echo_controller.transcript import TranscriptLog


class TranscriptTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.path = Path(self.dir.name) / "conversations.md"

    def tearDown(self):
        self.dir.cleanup()

    def test_each_session_gets_next_participant_id_in_one_file(self):
        first = TranscriptLog("control", "reachy_lite", self.path)
        first.close()
        second = TranscriptLog("humour", "reachy_lite", self.path)
        self.assertEqual((first.participant_id, second.participant_id), ("P001", "P002"))
        text = self.path.read_text(encoding="utf-8")
        self.assertEqual(text.count("# Echo Island conversation transcripts"), 1)
        self.assertIn("## Participant P001", text)
        self.assertIn("## Participant P002", text)
        self.assertIn("- Jokes: on", text)

    def test_both_sides_are_recorded_in_order_once(self):
        session = Session("control", preview_enabled=True, speech_enabled=True, conversation_enabled=True)
        session.transcript = TranscriptLog("control", "laptop", self.path)
        session.deliver("SHOW_DIALOGUE", "library", line_id="G1", text="What kind of books do you enjoy?")
        session.speech.job = {"capture_id": "c1", "phase": "processing", "context_id": session.context()["context_id"]}
        session.speech.update_caption(session, "c1", "I love  science books", 1, True)
        session.speech.update_caption(session, "c1", "I love science books", 2, True)
        session.stop()
        session.transcript.robot("after stop is ignored")
        text = self.path.read_text(encoding="utf-8")
        reachy, person = text.index("**Reachy** _(G1)_: What kind of books"), text.index("**P001**: I love science books")
        self.assertLess(reachy, person)
        self.assertEqual(text.count("I love science books"), 1)
        self.assertIn("_Session ended", text)
        self.assertNotIn("after stop", text)

    def test_off_by_default(self):
        session = Session("control", preview_enabled=True, speech_enabled=True, conversation_enabled=True)
        self.assertIsNone(session.transcript)


if __name__ == "__main__":
    unittest.main()
