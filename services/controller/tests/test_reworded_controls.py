import unittest

from echo_controller.companion_gateway import classify_control


class FakeParser:
    def __init__(self, name, confidence):
        self.result = (name, confidence)

    def parse(self, phrase):
        return self.result


class RewordedControlTests(unittest.TestCase):
    def test_confident_rasa_command_is_accepted_for_unlisted_wording(self):
        result = classify_control("Could you maybe ask me that once more?", FakeParser("REPEAT", 0.93))
        self.assertEqual(result, ("REPEAT", 0.93, "rasa"))

    def test_answers_and_low_confidence_stay_answers(self):
        self.assertEqual(classify_control("I love science books", FakeParser("ANSWER_SCIENCE", 0.97))[0], "UNKNOWN")
        self.assertEqual(classify_control("ask me something else", FakeParser("REPEAT", 0.6))[0], "UNKNOWN")

    def test_stop_needs_exact_phrase_or_very_confident_rasa(self):
        self.assertEqual(classify_control("could we finish here", FakeParser("STOP", 0.9))[0], "UNKNOWN")
        self.assertEqual(classify_control("could we finish here", FakeParser("STOP", 0.97))[0], "STOP")
        self.assertEqual(classify_control("stop", FakeParser("UNKNOWN", 0.1))[0], "STOP")


if __name__ == "__main__":
    unittest.main()
