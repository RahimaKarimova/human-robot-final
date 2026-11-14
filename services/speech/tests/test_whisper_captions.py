"""Caption processing regressions using synthetic PCM, never a microphone."""
from pathlib import Path
from types import SimpleNamespace
import sys
import unittest
import numpy as np

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'services/controller'))
from echo_controller.speech_worker import whisper_samples,WhisperLiveDecoder,OfflineRecognizer,SAMPLE_RATE


class WhisperCaptionTests(unittest.TestCase):
    def test_quiet_speech_gain_stays_bounded_and_silence_stays_silent(self):
        quiet=(np.sin(np.arange(16000)*.04)*150).astype('<i2')
        result=whisper_samples(quiet.tobytes())
        self.assertGreater(float(np.max(np.abs(result))),150/32768.)
        self.assertLessEqual(float(np.max(np.abs(result))),600/32768.+1e-6)
        self.assertFalse(np.any(whisper_samples(bytes(32000))))
        loud=(np.sin(np.arange(16000)*.04)*32000).astype('<i2')
        self.assertLessEqual(float(np.max(np.abs(whisper_samples(loud.tobytes())))),1.)

    def test_preview_is_bounded_and_revises_the_actual_words_without_answer_prompts(self):
        class Model:
            def transcribe(self,samples,**options):
                self.length=len(samples); self.options=options
                return iter([SimpleNamespace(text='I do not like books.',avg_logprob=-.2,no_speech_prob=.01)]),None
        model=Model(); decoder=WhisperLiveDecoder(model)
        pcm=(np.sin(np.arange(SAMPLE_RATE*15)*.1)*2000).astype('<i2').tobytes()
        self.assertEqual(decoder.feed(pcm),'I do not like books.')
        self.assertEqual(model.length,SAMPLE_RATE*12)
        self.assertNotIn('initial_prompt',model.options)
        self.assertEqual(model.options['language'],'en')

    def test_silence_never_invokes_the_model_or_becomes_a_reply(self):
        class Model:
            def transcribe(self,*args,**kwargs): raise AssertionError('Silence reached model')
        decoder=WhisperLiveDecoder(Model())
        self.assertEqual(decoder.feed(bytes(SAMPLE_RATE*2)),'')
        recognizer=object.__new__(OfflineRecognizer)
        recognizer.final_model=Model()
        self.assertEqual(recognizer.controls(bytes(SAMPLE_RATE*2),reply=True),('UNKNOWN',0.,'unrecognized'))


if __name__=='__main__': unittest.main()
