import unittest
from unittest.mock import patch,MagicMock
from fastapi.testclient import TestClient
from echo_controller.app import create_app
from echo_controller.core import Session,Checkpoint
from echo_controller.reply_understanding import extract_nickname,book_negation
from echo_controller.preview import script
from echo_controller.robot_output import ReachyLiteOutput
from echo_controller.speech_worker import SpeechWorker,MicrophoneCapture,SAMPLE_RATE
from concurrent.futures import Future


class PersonalisedConversationTests(unittest.TestCase):
    def test_slow_partial_decoder_does_not_block_capture_heartbeats(self):
        calls=[]
        job=dict(capture_id='a'*24,purpose='reply',automatic=True,question_id='G1',phase='listen')
        def exchange(route,payload):
            calls.append(route)
            return {'stopped':False,'job':job} if route=='/speech/poll' else {}
        capture=MagicMock()
        capture.full=False
        capture.done=False
        capture.take_preview.return_value=b'preview'
        capture.meter_snapshot.return_value=(0.,0,0.)
        loading,decoding=Future(),Future()
        worker=SpeechWorker({'conversation':True},MagicMock(),exchange=exchange,automatic_factory=lambda _:capture)
        worker.caption_pool=MagicMock()
        worker.caption_pool.submit.side_effect=[loading,decoding]
        self.assertTrue(worker.step())
        self.assertTrue(worker.step())
        self.assertEqual(calls.count('/speech/poll'),2)
        loading.set_result(MagicMock())
        self.assertTrue(worker.step())
        self.assertTrue(worker.step())
        self.assertEqual(calls.count('/speech/poll'),4)
        worker.discard()
        self.assertTrue(decoding.cancelled())

    def test_preview_backlog_is_bounded_without_discarding_the_final_answer(self):
        capture=MicrophoneCapture()
        capture.preview_enabled=True
        capture._measure(bytes(SAMPLE_RATE*2*15))
        self.assertEqual(len(capture.preview_buffer),SAMPLE_RATE*2*12)
        self.assertFalse(capture.full)

    def test_name_extraction_does_not_treat_ordinary_answers_or_commands_as_names(self):
        self.assertEqual(extract_nickname('My name is Alex.'),'Alex')
        self.assertEqual(extract_nickname('you can call me Merve'),'Merve')
        self.assertEqual(extract_nickname('John Smith'),'John Smith')
        for text in ["I don't know",'skip','I enjoy stories about exploring islands','<script>']:
            self.assertEqual(extract_nickname(text),'')

    def test_negative_book_preferences_cannot_become_positive_responses(self):
        self.assertTrue(book_negation("I don't like books"))
        self.assertTrue(book_negation('I do not enjoy reading'))
        self.assertFalse(book_negation('I like books'))
        self.assertFalse(book_negation("I don't like fantasy books but I love mysteries"))
        response=script('G1_ACK','control',reply_kind='BOOKS_DISLIKE')
        self.assertIn('Not a book fan',response['text'])
        self.assertNotEqual(response['audio_id'],script('G1_ACK','control')['audio_id'])
        self.assertNotIn('Not a book fan',script('P3_ACK','control',reply_kind='BOOKS_DISLIKE')['text'])

    def test_name_is_used_in_greeting_and_ending_and_forgotten_on_stop(self):
        greeting=script('NAME_ACK','humour',nickname='Alex')
        self.assertIn('Alex',greeting['speech_text'])
        self.assertIn('Alex',script('ENDING','humour',nickname='Alex')['speech_text'])
        s=Session('humour',nickname='Alex')
        s.stop()
        self.assertEqual(s.nickname,'')

    def test_live_captions_are_capture_bound_transient_and_not_command_history(self):
        s=Session('humour',speech_enabled=True,conversation_enabled=True)
        s.started=True
        s.speech.clock=lambda:10.
        s.speech.start(s,'a'*24)
        count=len(s.commands)
        s.speech.update_caption(s,'wrong','private synthetic words',1,False)
        self.assertFalse(s.speech.caption_state(s))
        s.speech.update_caption(s,'a'*24,'synthetic answer',1,False)
        self.assertEqual(s.speech.caption_state(s)['text'],'synthetic answer')
        self.assertEqual(len(s.commands),count)
        s.speech.update_caption(s,'a'*24,'wrong old revision',1,False)
        self.assertEqual(s.speech.caption_state(s)['text'],'synthetic answer')
        s.speech.clock=lambda:26.
        self.assertFalse(s.speech.caption_state(s))
        s.speech.cancel()
        self.assertFalse(s.speech.caption_state(s))

    def test_only_current_name_question_can_set_session_nickname(self):
        s=Session('humour',preview_enabled=True,speech_enabled=True,conversation_enabled=True)
        s.started=True
        s.game_view='checkpoint'
        s.checkpoints['library_welcome']=Checkpoint('library','welcome',['NAME'],waiting=True)
        s.speech.start(s,'a'*24,'reply')
        s.speech.release('a'*24)
        s.speech.finish(s,dict(capture_id='a'*24,intent='REPLY',confidence=1.,source='reply',nickname='Alex',reply_kind='NAME_GIVEN'))
        self.assertEqual(s.nickname,'Alex')

    def test_synthesis_never_starts_playback_while_paused_or_after_cancel(self):
        output=object.__new__(ReachyLiteOutput)
        output.pipeline=None
        output.paused=False
        output.preparing=True
        output.tts_future=MagicMock()
        output.tts_future.done.return_value=True
        output._start_pcm=MagicMock()
        output.set_paused(True)
        self.assertFalse(output.tick())
        output._start_pcm.assert_not_called()
        output.cancel()
        self.assertFalse(output.tick())
        output._start_pcm.assert_not_called()

    def test_caption_role_endpoint_does_not_accept_game_token(self):
        app=create_app(); client=TestClient(app)
        cfg=client.post('/session/start',json={'speech':True,'preview':True,'conversation':True}).json()
        body=dict(session_id=cfg['session_id'],worker_id='caption-worker-123456',capture_id='a'*24,text='synthetic test',revision=1)
        result=client.post('/speech/caption',json=body,headers={'X-Echo-Speech-Token':cfg['token']})
        self.assertEqual(result.status_code,401)


if __name__=='__main__':unittest.main()
