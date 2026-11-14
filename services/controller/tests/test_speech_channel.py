import unittest
from fastapi.testclient import TestClient
from echo_controller.app import create_app
from echo_controller.core import Session
from echo_controller.speech_worker import SpeechWorker, MAX_BYTES


class SpeechChannelTests(unittest.TestCase):
    def test_cancelled_unadopted_robot_line_releases_microphone_gate(self):
        session=Session('humour',preview_enabled=True,output='reachy_control_simulator',speech_enabled=True)
        session.started=True
        session.game_view='explore'
        session.deliver('SHOW_DIALOGUE','library',checkpoint_id='library_welcome',line_id='WELCOME',
                        audio_id='companion_welcome',motion_id='WAVE',text='fixed',question=False)
        utterance=session.robot.job['utterance_id']
        session.cancel_delivery()
        session.speech.start(session,'before-stop')
        self.assertIsNone(session.speech.job)  # Cannot listen until the worker stops.
        session.robot.finish(session,utterance,'cancelled')
        self.assertFalse(session.delivery)
        session.speech.start(session,'after-stop')
        self.assertEqual(session.speech.job['capture_id'],'after-stop')

    def setUp(self):
        self.session = Session("control",speech_enabled=True)
        self.session.started = True
        self.session.game_view = "explore"
        self.channel = self.session.speech
        self.clock = [0.0]
        self.channel.clock = lambda:self.clock[0]

    def test_no_capture_without_request_and_audio_blocks_listening(self):
        self.assertIsNone(self.channel.poll(self.session,"worker")["job"])
        self.session.audio_active = True
        self.channel.start(self.session,"1"*24)
        self.assertIsNone(self.channel.job)
        self.assertEqual(self.session.commands[-1]["command"]["status"],"UNAVAILABLE")

    def test_cancelled_or_stale_capture_cannot_execute_a_command(self):
        self.channel.start(self.session,"1"*24)
        self.channel.cancel()
        self.channel.finish(self.session,dict(capture_id="1"*24,intent="PAUSE",confidence=1.0,source="rasa"))
        self.assertFalse(self.session.paused)
        self.channel.start(self.session,"2"*24)
        self.session.game_view = "journal"
        self.channel.poll(self.session,"worker")
        self.channel.finish(self.session,dict(capture_id="2"*24,intent="PAUSE",confidence=1.0,source="rasa"))
        self.assertFalse(self.session.paused)

    def test_worker_failure_releases_pending_capture_without_answer_inference(self):
        self.channel.start(self.session,"1"*24)
        self.clock[0]=4.1
        self.channel.expire(self.session)
        self.assertIsNone(self.channel.job)
        self.assertEqual(self.session.commands[-1]["command"]["status"],"UNAVAILABLE")

    def test_closed_input_processing_has_a_bounded_decode_lease(self):
        self.channel.start(self.session,"1"*24)
        self.channel.job['automatic']=True
        self.channel.job["phase"]="processing"
        self.channel.last_seen=0.0
        self.clock[0]=3.0
        self.channel.expire(self.session)
        self.assertIsNotNone(self.channel.job)
        self.clock[0]=12.0
        self.channel.expire(self.session)
        self.assertIsNotNone(self.channel.job)
        self.clock[0]=30.1
        self.channel.expire(self.session)
        self.assertIsNone(self.channel.job)

    def test_final_decode_has_a_full_budget_after_a_long_spoken_turn(self):
        self.channel.start(self.session,'1'*24,automatic=True)
        self.channel.job['phase']='processing'
        self.channel.job['processing_at']=29.
        self.channel.last_seen=29.
        self.clock[0]=56.
        self.channel.expire(self.session)
        self.assertIsNotNone(self.channel.job)
        self.clock[0]=59.1
        self.channel.expire(self.session)
        self.assertIsNone(self.channel.job)

    def test_late_release_cannot_undo_cancellation_or_processing(self):
        self.channel.start(self.session,"1"*24)
        self.channel.release("1"*24,True)
        self.channel.release("1"*24,False)
        self.assertEqual(self.channel.job["phase"],"cancel")
        self.channel.finish(self.session,dict(capture_id="1"*24,intent="PAUSE",confidence=1.0,source="rasa"))
        self.assertFalse(self.session.paused)
        self.channel.start(self.session,"2"*24)
        self.channel.job["phase"]="processing"
        self.channel.release("2"*24,False)
        self.assertEqual(self.channel.job["phase"],"processing")

    def test_result_before_explicit_release_never_executes(self):
        self.channel.start(self.session,"1"*24)
        self.channel.finish(self.session,dict(capture_id="1"*24,intent="PAUSE",confidence=1.0,source="rasa"))
        self.assertFalse(self.session.paused)

    def test_reply_requires_explicit_reply_mode_and_current_question(self):
        from echo_controller.core import Checkpoint
        self.session.game_view="checkpoint"
        self.session.checkpoints["library_before"]=Checkpoint("library","before",["G1"],waiting=True)
        self.channel.start(self.session,"1"*24,"control")
        self.channel.release("1"*24)
        self.channel.finish(self.session,dict(capture_id="1"*24,intent="REPLY",confidence=1.0,source="reply"))
        self.assertNotIn("COMPANION_CHECKPOINT_ACTION",[item["command"]["type"] for item in self.session.commands])
        self.channel.start(self.session,"2"*24,"reply")
        self.channel.release("2"*24)
        self.channel.finish(self.session,dict(capture_id="2"*24,intent="REPLY",confidence=1.0,source="reply"))
        actions=[item["command"] for item in self.session.commands if item["command"]["type"]=="COMPANION_CHECKPOINT_ACTION"]
        self.assertEqual(len(actions),1)
        self.assertEqual(actions[0]["action"],"ack")

    def test_role_tokens_and_raw_text_rejection(self):
        client=TestClient(create_app())
        config=client.post("/session/start",json={"speech":True}).json()
        body=dict(session_id=config["session_id"],worker_id="speech-worker-123456")
        self.assertEqual(client.post("/speech/poll",json=body,headers={"X-Echo-Speech-Token":config["token"]}).status_code,401)
        headers={"X-Echo-Speech-Token":config["speech_token"]}
        self.assertEqual(client.post("/speech/poll",json=body,headers=headers).status_code,200)
        response=client.post("/speech/result",json={**body,"capture_id":"1"*24,"intent":"UNKNOWN","confidence":0.0,"source":"unrecognized","text":"PRIVATE-SENTINEL"},headers=headers)
        self.assertEqual(response.status_code,422)
        self.assertNotIn("PRIVATE-SENTINEL",response.text)


class SpeechWorkerTests(unittest.TestCase):
    def setUp(self):
        self.opened=0
        self.discarded=0
        self.decoded=0
        owner=self
        class Capture:
            full=False
            def __init__(self,_device): pass
            def open(self): owner.opened+=1
            def take(self): return b"synthetic"
            def discard(self): owner.discarded+=1
        class Recognizer:
            def controls(self,_pcm):
                owner.decoded+=1
                return "PAUSE",1.0,"rasa"
        self.state=dict(stopped=False,job=None)
        self.results=[]
        def exchange(route,data):
            if route.endswith("result"):
                self.results.append(data)
                self.state["job"]=None
            return self.state
        self.worker=SpeechWorker({},Recognizer(),Capture,exchange=exchange)

    def test_device_without_samples_still_closes_after_wall_clock_limit(self):
        clock=[0.0]
        self.worker.clock=lambda:clock[0]
        self.state["job"]=dict(capture_id="1"*24,phase="listen")
        self.worker.step()
        clock[0]=8.1
        self.worker.step()
        self.assertEqual(self.discarded,1)
        self.assertEqual(self.decoded,0)

    def test_idle_never_opens_microphone_and_cancel_does_not_decode(self):
        self.worker.step()
        self.assertEqual(self.opened,0)
        self.state["job"]=dict(capture_id="1"*24,phase="listen")
        self.worker.step()
        self.assertEqual(self.opened,1)
        self.state["job"]["phase"]="cancel"
        self.worker.step()
        self.assertEqual(self.decoded,0)
        self.assertEqual(self.discarded,1)

    def test_network_loss_closes_capture_before_retry(self):
        self.state["job"]=dict(capture_id="1"*24,phase="listen")
        self.worker.step()
        self.worker.exchange=lambda *_:(_ for _ in ()).throw(ConnectionError())
        self.worker.step()
        self.assertEqual(self.discarded,1)
        self.assertEqual(self.worker.pending_result["source"],"unavailable")

    def test_release_routes_only_structured_metadata(self):
        self.state["job"]=dict(capture_id="1"*24,phase="listen")
        self.worker.step()
        self.state["job"]["phase"]="finish"
        self.worker.step()
        self.worker.step()
        self.assertEqual(self.decoded,1)
        self.assertEqual(set(self.results[0]),{"capture_id","intent","confidence","source"})

    def test_overflow_never_decodes_a_partial_command(self):
        self.state["job"]=dict(capture_id="1"*24,phase="listen")
        self.worker.step()
        self.worker.capture.full=True
        self.worker.step()
        self.assertEqual(self.decoded,0)
        self.assertEqual(self.discarded,1)

    def test_release_before_capture_never_opens_input(self):
        self.state["job"]=dict(capture_id="1"*24,phase="finish")
        self.worker.step()
        self.assertEqual(self.opened,0)
        self.assertEqual(self.decoded,0)
