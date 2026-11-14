import os
import unittest

from echo_controller.companion_gateway import BANK, RasaParser, classify_control


@unittest.skipUnless(os.environ.get("ECHO_TEST_RASA") == "1", "Start the local Rasa model and set ECHO_TEST_RASA=1 for live NLU checks.")
class LiveRasaTests(unittest.TestCase):
    def test_all_83_synthetic_phrases_with_the_real_model(self):
        parser = RasaParser()
        for expected, phrases in BANK.items():
            for phrase in phrases:
                with self.subTest(intent=expected, phrase=phrase):
                    intent, confidence = parser.parse(phrase)
                    self.assertEqual(intent, expected)
                    self.assertGreaterEqual(confidence, 0.8)

    def test_live_gateway_accepts_commands_and_rejects_negations(self):
        parser = RasaParser()
        for phrase in ("PAUSE!", "give me a hint", "repeat that please", "i would rather skip", "i cannot think of anything"):
            self.assertNotEqual(classify_control(phrase, parser)[0], "UNKNOWN")
        for phrase in ("no not really", "please do not stop", "i stopped reading that book", "do not skip"):
            self.assertEqual(classify_control(phrase, parser)[0], "UNKNOWN")
