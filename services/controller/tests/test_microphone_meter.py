from array import array
import math
import unittest
from fastapi.testclient import TestClient
from echo_controller.app import create_app
from echo_controller.core import Session
from echo_controller.speech_worker import input_level,MicrophoneCapture


class MicrophoneMeterTests(unittest.TestCase):
    def test_real_pcm_levels_distinguish_silence_and_volume_without_retaining_audio(self):
        self.assertEqual(input_level(bytes(640)),0.)
        quiet=array('h',[int(1000*math.sin(i*.2)) for i in range(320)]).tobytes()
        loud=array('h',[int(12000*math.sin(i*.2)) for i in range(320)]).tobytes()
        self.assertGreater(input_level(loud),input_level(quiet))
        self.assertLessEqual(input_level(loud),1.)
        capture=MicrophoneCapture()
        capture._measure(loud)
        level,sequence,at=capture.meter_snapshot()
        self.assertGreater(level,.1)
        self.assertEqual(sequence,1)
        self.assertGreater(at,0)
        self.assertEqual(capture.buffer,bytearray())

    def test_meter_expires_and_cannot_survive_processing_or_wrong_capture(self):
        s=Session('control',speech_enabled=True)
        s.started=True
        clock=[10.]
        s.speech.clock=lambda:clock[0]
        s.speech.start(s,'a'*24)
        s.speech.update_meter('wrong',.8,1)
        self.assertFalse(s.speech.meter_state()['live'])
        s.speech.update_meter('a'*24,.8,1)
        self.assertTrue(s.speech.meter_state()['live'])
        s.speech.update_meter('a'*24,.2,1)
        self.assertEqual(s.speech.meter_state()['level'],.8)
        clock[0]+=.7
        self.assertFalse(s.speech.meter_state()['live'])
        s.speech.update_meter('a'*24,.4,2)
        s.speech.job['phase']='processing'
        self.assertFalse(s.speech.meter_state()['live'])

    def test_meter_is_role_bound_transient_and_not_a_command_history(self):
        app=create_app()
        client=TestClient(app)
        cfg=client.post('/session/start',json={'speech':True}).json()
        s=app.state.sessions[cfg['session_id']]
        s.started=True
        s.speech.start(s,'a'*24)
        poll={'session_id':cfg['session_id'],'worker_id':'meter-worker-123456'}
        role={'X-Echo-Speech-Token':cfg['speech_token']}
        client.post('/speech/poll',json=poll,headers=role)
        body={**poll,'capture_id':'a'*24,'level':.7,'sequence':1}
        self.assertEqual(client.post('/speech/level',json=body,headers={'X-Echo-Speech-Token':cfg['token']}).status_code,401)
        count=len(s.commands)
        self.assertEqual(client.post('/speech/level',json=body,headers=role).status_code,200)
        self.assertEqual(len(s.commands),count)
        response=client.get('/game/commands',params={'session_id':cfg['session_id']},headers={'X-Echo-Session-Token':cfg['token']}).json()
        self.assertTrue(response['microphone']['live'])
        self.assertEqual(response['microphone']['level'],.7)
        self.assertEqual(client.post('/speech/level',json={**body,'level':2.},headers=role).status_code,422)
        s.speech.cancel()
        self.assertFalse(s.speech.meter_state()['live'])


if __name__=='__main__':unittest.main()
