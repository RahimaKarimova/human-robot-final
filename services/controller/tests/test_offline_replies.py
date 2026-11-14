import unittest
from unittest.mock import MagicMock
from echo_controller.core import Session,Checkpoint
from echo_controller.preview import script
from echo_controller.reply_understanding import REPLIES
from echo_controller.companion_gateway import PHRASES,normalize
from echo_controller.robot_output import ReachyLiteOutput


class OfflineReplyTests(unittest.TestCase):
    def test_specialized_book_categories_are_bound_to_library(self):
        for kind in ['BOOKS_SCIENCE','BOOKS_HISTORY','BOOKS_DISLIKE']:
            self.assertEqual(REPLIES[kind]['questions'],['G1'])
            self.assertEqual(script('G1_ACK','humour',reply_kind=kind)['text'],REPLIES[kind]['response'])
            self.assertNotEqual(script('P1_ACK','humour',reply_kind=kind)['text'],REPLIES[kind]['response'])

    def test_support_requests_do_not_become_personal_answers(self):
        for phrase in ['What did you say?','I missed that','Repeat please']:
            self.assertEqual(PHRASES[normalize(phrase)],'REPEAT')
        for phrase in ["I didn't get that",'I do not understand','Explain that']:
            self.assertEqual(PHRASES[normalize(phrase)],'CLARIFY')

    def test_generated_reply_does_not_override_skip(self):
        response=script('G1_ACK','humour',reply_text='You enjoy baking.')
        self.assertTrue(response['generated_reply'])
        self.assertEqual(response['speech_text'],'You enjoy baking.')
        self.assertFalse(script('G1_ACK','humour',skipped=True,reply_text='You enjoy baking.').get('generated_reply',False))

    def test_generated_text_is_cleared_on_stop(self):
        s=Session('humour');s.reply_texts['G1']='Synthetic preference'
        s.command('COMPANION_CUE',generated_reply=True,text='Synthetic preference',speech_text='Synthetic preference')
        s.stop()
        self.assertFalse(s.reply_texts)
        self.assertNotIn('Synthetic preference',str(s.commands))

    def test_stale_reply_cannot_set_text(self):
        s=Session('humour',preview_enabled=True,speech_enabled=True,conversation_enabled=True)
        s.started=True;s.game_view='checkpoint'
        s.checkpoints['library_before']=Checkpoint('library','before',['G1'],waiting=True)
        s.speech.start(s,'a'*24,'reply');s.speech.release('a'*24)
        s.speech.finish(s,dict(capture_id='b'*24,intent='REPLY',confidence=1.,source='reply',reply_text='Wrong context'))
        self.assertFalse(s.reply_texts)

    def test_current_reply_can_set_session_only_text(self):
        s=Session('humour',preview_enabled=True,speech_enabled=True,conversation_enabled=True)
        s.started=True;s.game_view='checkpoint'
        s.checkpoints['library_before']=Checkpoint('library','before',['G1'],waiting=True)
        s.speech.start(s,'a'*24,'reply');s.speech.release('a'*24)
        s.speech.finish(s,dict(capture_id='a'*24,intent='REPLY',confidence=1.,source='reply',reply_text='You enjoy baking.'))
        self.assertEqual(s.reply_texts,{'G1':'You enjoy baking.'})

    def test_short_stream_tail_starts_and_finishes(self):
        output=object.__new__(ReachyLiteOutput)
        output.pipeline=None;output.paused=False;output.streaming_reply=True;output.stream_done=False
        output.stream_pcm=bytearray(b'\0'*200);output.stream_source=None;output.preparing=True
        output.stream_started=__import__('time').monotonic();output.tts_future=None
        output.reply_voice=MagicMock();output.reply_voice.poll.return_value=('done',b'',24000)
        output._start_pcm=MagicMock()
        self.assertFalse(output.tick())
        output._start_pcm.assert_called_once_with(bytes(200),24000,streaming=True)
        self.assertTrue(output.stream_done);self.assertFalse(output.preparing)
