"""Actual offline model tests using public synthetic fixtures only, no devices."""
import sys
from pathlib import Path
import unittest
import wave

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT / "services/controller"))
from echo_controller.speech_worker import OfflineRecognizer, MAX_BYTES
from echo_controller.companion_gateway import PHRASES, normalize


class SyntheticParser:
    def parse(self, phrase):
        return PHRASES.get(normalize(phrase),"UNKNOWN"),1.0


class OfflineAsrTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.recognizer = OfflineRecognizer(ROOT / "tools/speech/vosk-model-small-en-us-0.15",SyntheticParser())

    def test_public_commands_through_actual_offline_recognizer(self):
        accepted=0
        for key,intent in {"pause":"PAUSE","repeat":"REPEAT","hint":"HINT","skip":"SKIP","stop":"STOP"}.items():
            with self.subTest(fixture=key):
                with wave.open(str(ROOT / "tools/speech/fixtures" / (key+".wav"))) as audio:
                    pcm=audio.readframes(128000)
                outcome=self.recognizer.controls(pcm)[0]
                self.assertIn(outcome,{intent,"UNKNOWN"})
                accepted += int(outcome == intent)
        self.assertGreaterEqual(accepted,3,"Synthetic command smoke test must recognize most fixtures without inventing another intent")

    def test_negation_and_unrelated_speech_do_not_become_commands(self):
        for key in ("negation","story"):
            with wave.open(str(ROOT / "tools/speech/fixtures" / (key+".wav"))) as audio:
                pcm=audio.readframes(128000)
            self.assertEqual(self.recognizer.controls(pcm)[0],"UNKNOWN")

    def test_silence_and_oversized_capture_never_infer_an_answer(self):
        for pcm in (b"",bytes(32000),bytes(MAX_BYTES+2)):
            self.assertEqual(self.recognizer.controls(pcm)[0],"UNKNOWN")

    def test_explicit_reply_mode_submits_only_completion(self):
        with wave.open(str(ROOT / "tools/speech/fixtures/story.wav")) as audio:
            pcm=audio.readframes(128000)
        self.assertEqual(self.recognizer.controls(pcm,reply=True),("REPLY",1.0,"reply"))
        self.assertEqual(self.recognizer.controls(bytes(32000),reply=True)[0],"UNKNOWN")
