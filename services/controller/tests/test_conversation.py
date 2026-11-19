import unittest
from unittest.mock import patch,MagicMock
from types import SimpleNamespace
from fastapi.testclient import TestClient
from echo_controller.app import create_app
from echo_controller.core import Session,Checkpoint
from echo_controller.conversation import RasaConversation,INTENTS


class ConversationTests(unittest.TestCase):
    def session(self):
        session=Session('humour',preview_enabled=True,speech_enabled=True,conversation_enabled=True)
        session.started=True
        session.game_view='checkpoint'
        session.checkpoints['library_before']=Checkpoint('library','before',['G1'],waiting=True)
        session.speech.clock=lambda:10.
        session.last_game_poll=10.
        return session

    def test_automatic_turn_only_opens_after_audio_and_at_a_question(self):
        s=self.session()
        s.audio_active=True
        self.assertIsNone(s.speech.poll(s,'worker')['job'])
        s.audio_active=False
        s.delivery={'utterance_id':'output'}
        self.assertIsNone(s.speech.poll(s,'worker')['job'])
        s.delivery.clear()
        job=s.speech.poll(s,'worker')['job']
        self.assertTrue(job['automatic'])
        self.assertEqual(job['purpose'],'reply')
        s.speech.job=None
        s.game_view='explore'
        self.assertIsNone(s.speech.poll(s,'worker')['job'])

    def test_push_to_talk_never_opens_automatic_turn_but_allows_held_reply(self):
        s=self.session()
        s.push_to_talk=True
        self.assertIsNone(s.speech.poll(s,'worker')['job'])
        s.speech.start(s,'held-b','reply')
        job=s.speech.poll(s,'worker')['job']
        self.assertFalse(job['automatic'])
        self.assertEqual(job['purpose'],'reply')

    def test_automatic_turn_cancels_on_pause_or_lost_game_heartbeat(self):
        for paused,seen in ((True,10.),(False,0.)):
            s=self.session()
            s.speech.poll(s,'worker')
            s.paused,s.last_game_poll=paused,seen
            self.assertEqual(s.speech.poll(s,'worker')['job']['phase'],'cancel')

    def test_normal_reply_requires_finished_turn_and_same_question(self):
        s=self.session()
        job=s.speech.poll(s,'worker')['job']
        body=dict(capture_id=job['capture_id'],intent='REPLY',confidence=1.,source='reply')
        s.speech.finish(s,body)
        self.assertFalse(any(c['command']['type']=='COMPANION_CHECKPOINT_ACTION' for c in s.commands))
        s.speech.auto_after=0
        job=s.speech.poll(s,'worker')['job']
        s.speech.release(job['capture_id'])
        s.speech.finish(s,{**body,'capture_id':job['capture_id']})
        self.assertTrue(any(c['command'].get('action')=='ack' for c in s.commands))

    def test_silence_never_replies_and_unclear_speech_repeats_only_once(self):
        s=self.session()
        for heard in (False,True,True):
            s.speech.auto_after=0
            job=s.speech.poll(s,'worker')['job']
            s.speech.release(job['capture_id'])
            s.speech.finish(s,dict(capture_id=job['capture_id'],intent='UNKNOWN',confidence=0.,source='unrecognized',speech_detected=heard))
        actions=[c['command'] for c in s.commands if c['command']['type']=='COMPANION_CHECKPOINT_ACTION']
        self.assertEqual([c['action'] for c in actions],['repeat'])

    def test_held_b_with_nothing_recognized_gets_default_try_again_line_not_an_answer(self):
        for source in ('unrecognized','unavailable'):
            s=self.session()
            s.push_to_talk=True
            s.speech.start(s,'c'*24,'reply')
            s.speech.release('c'*24)
            s.speech.finish(s,dict(capture_id='c'*24,intent='UNKNOWN',confidence=0.,source=source))
            cues=[c['command'] for c in s.commands if c['command']['type']=='COMPANION_CUE']
            self.assertEqual(len(cues),1,source)
            self.assertIn("didn't quite catch that",cues[0]['text'])
            acks=[c['command'] for c in s.commands if c['command']['type']=='COMPANION_CHECKPOINT_ACTION']
            self.assertEqual(acks,[])  # Nothing heard never counts as an answer.

    def test_game_audio_cancels_open_microphone_but_never_a_captured_answer(self):
        s=self.session()
        s.push_to_talk=True
        s.speech.start(s,'d'*24,'reply')
        s.speech.release('d'*24)                 # B released: answer captured.
        s.speech.job['phase']='processing'       # The worker is transcribing it.
        s.audio_active=True                      # e.g. an NPC greeting starts.
        s.speech.poll(s,'worker')
        self.assertEqual(s.speech.job['phase'],'processing')
        s2=self.session()
        s2.push_to_talk=True
        s2.speech.start(s2,'e'*24,'reply')       # Still listening (B held).
        s2.audio_active=True
        s2.speech.poll(s2,'worker')
        self.assertEqual(s2.speech.job['phase'],'cancel')

    def test_rasa_core_receives_only_fixed_intent_labels(self):
        with patch('echo_controller.conversation.exchange',return_value=[{'text':'REPLY'}]) as send:
            self.assertEqual(RasaConversation(sender='opaque').decide('REPLY'),'REPLY')
            self.assertEqual(send.call_args.args[1],{'sender':'opaque','message':'/reply_given'})
        with self.assertRaises(ValueError):RasaConversation().decide('private arbitrary answer')
        with patch('echo_controller.conversation.exchange',return_value=[{'text':'invented response'}]):
            with self.assertRaises(ValueError):RasaConversation().decide('REPLY')

    def test_no_automatic_capture_without_explicit_conversation_mode(self):
        s=self.session()
        s.conversation_enabled=False
        self.assertIsNone(s.speech.poll(s,'worker')['job'])

    def test_spoken_stop_survives_rasa_dialogue_outage(self):
        from echo_controller.speech_worker import OfflineRecognizer
        decoder=MagicMock()
        decoder.FinalResult.return_value='{"text":"stop the session","result":[{"conf":1.0}]}'
        fake_vosk=SimpleNamespace(KaldiRecognizer=lambda *_:decoder)
        recognizer=object.__new__(OfflineRecognizer)
        recognizer.model=object()
        recognizer.parser=MagicMock()
        recognizer.dialogue=MagicMock()
        recognizer.dialogue.decide.side_effect=ConnectionError
        with patch.dict('sys.modules',{'vosk':fake_vosk}):
            self.assertEqual(recognizer.controls(b'\0\0'*320,reply=True),('STOP',1.0,'safety'))
        recognizer.dialogue.decide.assert_not_called()

    def test_role_bound_automatic_endpoint_must_finish_before_processing(self):
        app=create_app()
        client=TestClient(app)
        cfg=client.post('/session/start',json={'preview':True,'speech':True,'conversation':True}).json()
        s=app.state.sessions[cfg['session_id']]
        s.started=True
        s.game_view='checkpoint'
        s.checkpoints['library_before']=Checkpoint('library','before',['G1'],waiting=True)
        client.get('/game/commands',params={'session_id':cfg['session_id']},headers={'X-Echo-Session-Token':cfg['token']})
        role={'X-Echo-Speech-Token':cfg['speech_token']}
        poll={'session_id':cfg['session_id'],'worker_id':'conversation-worker-1234'}
        job=client.post('/speech/poll',json=poll,headers=role).json()['job']
        body={**poll,'capture_id':job['capture_id']}
        self.assertEqual(client.post('/speech/end-turn',json=body,headers={'X-Echo-Speech-Token':cfg['token']}).status_code,401)
        client.post('/speech/processing',json=body,headers=role)
        self.assertEqual(s.speech.job['phase'],'listen')
        client.post('/speech/end-turn',json=body,headers=role)
        self.assertEqual(s.speech.job['phase'],'finish')
        client.post('/speech/processing',json=body,headers=role)
        self.assertEqual(s.speech.job['phase'],'processing')
        client.post('/speech/result',json={**body,'intent':'REPLY','confidence':1.0,'source':'reply','speech_detected':True},headers=role)
        self.assertTrue(any(c['command'].get('action')=='ack' for c in s.commands))

    def test_automatic_endpoint_cannot_release_manual_push_to_talk(self):
        app=create_app()
        client=TestClient(app)
        cfg=client.post('/session/start',json={'speech':True}).json()
        s=app.state.sessions[cfg['session_id']]
        s.started=True
        s.game_view='explore'
        s.speech.start(s,'a'*24)
        role={'X-Echo-Speech-Token':cfg['speech_token']}
        poll={'session_id':cfg['session_id'],'worker_id':'conversation-worker-1234'}
        client.post('/speech/poll',json=poll,headers=role)
        client.post('/speech/end-turn',json={**poll,'capture_id':'a'*24},headers=role)
        self.assertEqual(s.speech.job['phase'],'listen')


if __name__=='__main__':unittest.main()
