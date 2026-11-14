from pathlib import Path
import sys
import unittest
import wave

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT/'services/controller'))
from echo_controller.voice_turn import VoiceTurn, FRAME_BYTES


class VoiceTurnTests(unittest.TestCase):
    def test_real_webrtc_silence_never_counts_as_an_answer(self):
        turn=VoiceTurn()
        for _ in range(1000):
            self.assertEqual(turn.feed(bytes(FRAME_BYTES)), 'waiting')
        self.assertEqual(len(turn.audio),0)
        self.assertLessEqual(len(turn.pre_roll),15)

    def test_real_webrtc_segments_synthetic_speech_without_a_microphone(self):
        with wave.open(str(ROOT/'tools/speech/fixtures/story.wav')) as source:
            self.assertEqual(source.getframerate(),16000)
            pcm=source.readframes(source.getnframes())
        turn=VoiceTurn()
        state='waiting'
        for offset in range(0,len(pcm),FRAME_BYTES):
            state=turn.feed(pcm[offset:offset+FRAME_BYTES])
            if state=='complete': break
        for _ in range(80):
            if state=='complete': break
            state=turn.feed(bytes(FRAME_BYTES))
        self.assertEqual(state,'complete')
        self.assertGreater(len(turn.take()),FRAME_BYTES*8)
        self.assertEqual(turn.audio,bytearray())
        self.assertEqual(turn.state,'consumed')

    def test_pauses_inside_speech_do_not_complete_a_turn(self):
        turn=VoiceTurn(classifier=lambda frame: bool(frame[0]))
        speech=b'\1'*FRAME_BYTES
        for _ in range(15): turn.feed(speech)
        for _ in range(20): self.assertEqual(turn.feed(bytes(FRAME_BYTES)),'speaking')
        turn.feed(speech)
        for _ in range(49): self.assertEqual(turn.feed(bytes(FRAME_BYTES)),'speaking')
        self.assertEqual(turn.feed(bytes(FRAME_BYTES)),'complete')

    def test_overlong_speech_and_cancel_discard_all_buffers(self):
        turn=VoiceTurn(max_speech_seconds=2,classifier=lambda _:True)
        for _ in range(101): turn.feed(b'\1'*FRAME_BYTES)
        self.assertEqual(turn.state,'too_long')
        self.assertEqual(len(turn.audio),0)
        with self.assertRaises(RuntimeError): turn.take()
        turn.reset()
        turn.feed(b'\1'*(FRAME_BYTES+7))
        turn.discard()
        self.assertEqual(len(turn.pending)+len(turn.audio)+len(turn.pre_roll),0)

    def test_partial_frames_and_duplicate_completion_are_safe(self):
        turn=VoiceTurn(classifier=lambda frame: bool(frame[0]))
        for _ in range(20):
            turn.feed(b'\1'*123)
            turn.feed(b'\1'*(FRAME_BYTES-123))
        for _ in range(60): turn.feed(bytes(FRAME_BYTES))
        self.assertEqual(turn.state,'complete')
        original=turn.take()
        self.assertTrue(original)
        self.assertEqual(turn.feed(b'\1'*FRAME_BYTES),'consumed')
        with self.assertRaises(RuntimeError): turn.take()


if __name__=='__main__': unittest.main()
