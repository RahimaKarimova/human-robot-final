import math
from types import SimpleNamespace
import unittest
from unittest.mock import patch, MagicMock

from fastapi.testclient import TestClient
from echo_controller.app import create_app
from echo_controller.core import ProtocolError, Session
from echo_controller.robot_output import SimulatedOutput, antenna_target, clip, MOTIONS, ReachyLiteOutput, ReachyWirelessOutput, ReachyMujocoOutput, ReachyControlSimulatorOutput
from echo_controller.robot_worker import Worker


class Clock:
    value = 0.0
    def __call__(self): return self.value
    def advance(self, seconds): self.value += seconds


class RobotChannelTests(unittest.TestCase):
    def setUp(self):
        self.session = Session("humour", preview_enabled=True, output="bridge_simulator")
        self.clock = Clock()
        self.session.robot.clock = self.clock
        self.session.deliver("SHOW_DIALOGUE", "library", checkpoint_id="library_welcome", line_id="WELCOME",
                             audio_id="companion_welcome", motion_id="WAVE", text="fixed", question=False)
        self.job = self.session.robot.job
        self.id = self.job["utterance_id"]

    def test_output_waits_for_game_ready_and_one_worker_owns_session(self):
        self.assertIsNone(self.session.robot.poll(self.session, "worker-a")["job"])
        self.job["ready"] = True
        self.assertEqual(self.session.robot.poll(self.session, "worker-a")["job"]["utterance_id"], self.id)
        with self.assertRaises(ProtocolError): self.session.robot.poll(self.session, "worker-b")

    def test_simulator_cannot_claim_audio_completion(self):
        self.job["ready"] = True
        with self.assertRaises(ProtocolError): self.session.robot.finish(self.session, self.id, "audio_completed")
        self.session.robot.finish(self.session, self.id, "simulated_completed")
        self.assertEqual(self.session.commands[-1]["command"]["completion"], "simulated_completed")
        self.assertTrue(self.session.delivery)  # Game must still acknowledge the result.

    def test_pause_stop_and_game_poll_lease_cancel_output(self):
        self.job["ready"] = True
        self.session.paused = True
        self.assertEqual(self.session.robot.poll(self.session, "worker-a")["state"], "pause")
        self.session.paused = False
        self.session.robot.game_seen = self.clock()
        self.clock.advance(2.1)
        self.assertEqual(self.session.robot.poll(self.session, "worker-a")["state"], "cancel")
        self.session.stop()
        self.assertEqual(self.session.robot.poll(self.session, "worker-a")["state"], "stopped" if not self.session.robot.job else "cancel")
        self.session.robot.finish(self.session, self.id, "cancelled")
        self.assertEqual(self.session.commands[-1]["command"]["type"], "SESSION_STOP")

    def test_worker_timeout_is_failure_never_spoken_completion(self):
        self.clock.advance(self.session.robot.INITIAL_WORKER_GRACE + 0.1)
        self.session.robot.expire(self.session)
        self.assertIsNone(self.session.robot.job)
        self.assertEqual(self.session.commands[-1]["command"]["completion"], "technical_failure")

    def test_late_result_cannot_finish_another_utterance(self):
        count = len(self.session.commands)
        self.session.robot.finish(self.session, "stale", "cancelled")
        self.assertEqual(len(self.session.commands), count)
        self.assertEqual(self.session.robot.job["utterance_id"], self.id)


class WorkerTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.output = SimulatedOutput(self.clock)
        self.job = {"utterance_id": "one", "audio_id": "companion_welcome", "motion_id": "WAVE", "stage_id": "library"}
        self.state = {"state": "play", "mode": "bridge_simulator", "job": self.job}
        self.results = []
        def exchange(route, data):
            if route.endswith("result"):
                self.results.append(data.copy())
                self.state["job"] = None
                return {"accepted": True}
            return self.state
        self.worker = Worker({"output": "bridge_simulator"}, self.output, exchange, clock=self.clock)

    def test_healthy_heartbeat_with_missing_eos_times_out_as_failure(self):
        self.output.tick = lambda: False
        self.worker.step()
        self.clock.advance(60)
        self.worker.step()
        self.assertEqual(self.worker.pending_result["completion"], "technical_failure")
        self.assertFalse(self.output.running)

    def test_paused_time_is_not_a_playback_failure_deadline(self):
        self.output.tick = lambda: False
        self.worker.step()
        self.state["state"] = "pause"
        self.worker.step()
        self.clock.advance(60)
        self.worker.step()
        self.state["state"] = "play"
        self.worker.step()
        self.assertIsNotNone(self.worker.active)
        self.assertIsNone(self.worker.pending_result)

    def test_driver_error_during_cancel_cannot_crash_cleanup(self):
        self.worker.step()
        self.output.cancel = lambda: (_ for _ in ()).throw(RuntimeError())
        self.state["state"] = "cancel"
        self.assertTrue(self.worker.step())
        self.assertIsNone(self.worker.active)
        self.assertEqual(self.worker.pending_result["completion"], "technical_failure")

    def test_pause_preserves_progress_and_completion_is_explicitly_simulated(self):
        self.worker.step()
        self.clock.advance(1)
        self.state["state"] = "pause"
        self.worker.step()
        progress = self.output.elapsed
        self.clock.advance(20)
        self.worker.step()
        self.assertEqual(self.output.elapsed, progress)
        self.assertEqual(self.results, [])
        self.state["state"] = "play"
        self.worker.step()
        self.clock.advance(20)
        self.worker.step()
        self.worker.step()
        self.assertEqual(self.results[0]["completion"], "simulated_completed")

    def test_cancel_stops_without_replaying_the_same_job(self):
        self.worker.step()
        self.state["state"] = "cancel"
        self.worker.step()
        self.assertFalse(self.output.running)
        self.worker.step()
        self.assertEqual(self.results[0]["completion"], "cancelled")
        self.state.update(state="play", job=self.job)
        self.worker.step()
        self.assertFalse(self.output.running)
        self.assertEqual(self.worker.pending_result["completion"], "technical_failure")

    def test_network_loss_stops_locally_before_retrying(self):
        self.worker.step()
        self.worker.exchange = lambda *_args: (_ for _ in ()).throw(ConnectionError())
        self.worker.step()
        self.assertFalse(self.output.running)
        self.assertEqual(self.worker.pending_result["completion"], "technical_failure")

    def test_missing_asset_cannot_become_a_successful_job(self):
        self.job["audio_id"] = "../../untrusted.wav"
        self.worker.step()
        self.assertFalse(self.output.running)
        self.assertEqual(self.worker.pending_result["completion"], "technical_failure")

    def test_motion_profiles_are_small_smooth_and_condition_independent(self):
        baseline = [0.3, -0.2]
        for motion, (_, _, duration) in MOTIONS.items():
            self.assertEqual(antenna_target(motion, 0, baseline), baseline)
            self.assertEqual(antenna_target(motion, duration, baseline), baseline)
            for step in range(101):
                pose = antenna_target(motion, duration * step / 100, baseline)
                self.assertLessEqual(max(abs(a-b) for a,b in zip(pose, baseline)), math.radians(9))


class RobotApiTests(unittest.TestCase):
    def test_game_cannot_fabricate_success_before_worker_completion(self):
        client = TestClient(create_app())
        config = client.post("/session/start", json={"preview":True,"output":"bridge_simulator"}).json()
        headers = {"X-Echo-Session-Token":config["token"]}
        event = {"version":1,"session_id":config["session_id"],"event_id":"ready","stage_id":"library","event_type":"SESSION_READY","payload":{}}
        self.assertEqual(client.post("/game/event",json=event,headers=headers).status_code,200)
        session = client.app.state.sessions[config["session_id"]]
        session.deliver("SHOW_DIALOGUE","library",checkpoint_id="library_welcome",line_id="WELCOME",audio_id="companion_welcome",motion_id="WAVE",text="fixed",question=False)
        event.update(event_id="forged",event_type="COMPANION_PLAYBACK_COMPLETED",payload={"utterance_id":session.delivery["utterance_id"],"completion":"simulated_completed"})
        self.assertEqual(client.post("/game/event",json=event,headers=headers).status_code,409)
        self.assertIsNotNone(session.robot.job)

    def test_robot_credentials_cannot_post_game_events_and_game_token_cannot_drive_output(self):
        client = TestClient(create_app())
        config = client.post("/session/start", json={"preview": True, "output": "bridge_simulator"}).json()
        poll = {"session_id": config["session_id"], "worker_id": "test-worker-123456"}
        self.assertEqual(client.post("/robot/poll", json=poll, headers={"X-Echo-Robot-Token": config["token"]}).status_code, 401)
        self.assertEqual(client.post("/robot/poll", json=poll, headers={"X-Echo-Robot-Token": config["robot_token"]}).status_code, 200)
        event = {"version":1,"session_id":config["session_id"],"event_id":"test-1","stage_id":"library","event_type":"SESSION_READY","payload":{}}
        self.assertEqual(client.post("/game/event", json=event, headers={"X-Echo-Session-Token": config["robot_token"]}).status_code,401)
        event["payload"] = {"text": "PRIVATE-SENTINEL"}
        response = client.post("/game/event", json=event, headers={"X-Echo-Session-Token":config["token"]})
        self.assertEqual(response.status_code,409)
        self.assertNotIn("PRIVATE-SENTINEL", response.text)

    def test_external_output_requires_explicit_preview(self):
        self.assertEqual(TestClient(create_app()).post("/session/start", json={"output":"bridge_simulator"}).status_code,422)


class LiteOutputTests(unittest.TestCase):
    def test_control_simulator_requires_running_mock_and_matching_sdk(self):
        import json
        cases = [({}, False),
                 ({"state":"running","simulation_enabled":False,"mockup_sim_enabled":False,"version":"1.14.0"}, False),
                 ({"state":"running","mockup_sim_enabled":True,"version":"1.12.0"}, False),
                 ({"state":"stopped","mockup_sim_enabled":True,"version":"1.14.0"}, False),
                 ({"state":"running","mockup_sim_enabled":True,"version":"1.14.0"}, True)]
        for status, accepted in cases:
            with self.subTest(status=status):
                opener=MagicMock()
                opener.open.return_value.__enter__.return_value.read.return_value=json.dumps(status).encode()
                with patch("urllib.request.build_opener",return_value=opener), patch("importlib.metadata.version",return_value="1.14.0"):
                    output=object.__new__(ReachyControlSimulatorOutput)
                    if accepted:
                        output._validate_speaker("unused")
                    else:
                        with self.assertRaises(RuntimeError): output._validate_speaker("unused")

    def test_official_simulator_guard_rejects_hardware_and_mockup(self):
        import json
        for status in ({"simulation_enabled":False},{"simulation_enabled":True,"mockup_sim_enabled":True},{}):
            opener=MagicMock()
            opener.open.return_value.__enter__.return_value.read.return_value=json.dumps(status).encode()
            with patch("urllib.request.build_opener",return_value=opener):
                with self.assertRaises(RuntimeError):
                    object.__new__(ReachyMujocoOutput)._validate_speaker("unused")

    def test_official_simulator_guard_accepts_only_mujoco_status(self):
        opener=MagicMock()
        opener.open.return_value.__enter__.return_value.read.return_value=b'{"simulation_enabled":true,"mockup_sim_enabled":false}'
        with patch("urllib.request.build_opener",return_value=opener):
            object.__new__(ReachyMujocoOutput)._validate_speaker("unused")

    def test_wireless_backend_refuses_non_robot_platform_before_sdk_import(self):
        with patch("echo_controller.robot_output.sys.platform","win32"):
            with self.assertRaises(RuntimeError): ReachyWirelessOutput()

    def test_wireless_sink_is_the_explicit_robot_alsa_alias(self):
        output=object.__new__(ReachyWirelessOutput)
        properties={}
        element=SimpleNamespace(set_property=lambda key,value:properties.update({key:value}))
        requested=[]
        output.Gst=SimpleNamespace(ElementFactory=SimpleNamespace(make=lambda kind,name:requested.append(kind) or element))
        self.assertIs(output._make_sink(),element)
        self.assertEqual(requested,["alsasink"])
        self.assertEqual(properties,{"device":"reachymini_audio_sink"})

    def test_wireless_uses_common_physical_completion_contract(self):
        session=Session("control",preview_enabled=True,output="reachy_wireless")
        session.deliver("SHOW_DIALOGUE","library",audio_id="companion_welcome",motion_id="WAVE",text="fixed",question=False)
        session.robot.job["ready"]=True
        session.robot.finish(session,session.delivery["utterance_id"],"audio_completed")
        self.assertEqual(session.commands[-1]["command"]["completion"],"audio_completed")

    def test_wrong_or_default_speaker_is_rejected_before_sdk_import(self):
        for name in (None, "", "Default", "Laptop Speakers"):
            with self.assertRaises(ValueError): ReachyLiteOutput(name)

    def test_audio_completion_requires_real_eos_and_pause_freezes_gestures(self):
        # Verify output lifecycle without importing an SDK or touching hardware.
        output = object.__new__(ReachyLiteOutput)
        output.Gst = SimpleNamespace(MessageType=SimpleNamespace(ERROR=1, EOS=2), State=SimpleNamespace(NULL=0,PAUSED=1,PLAYING=2),StateChangeReturn=SimpleNamespace(FAILURE=-1))
        messages = []
        output.pipeline = SimpleNamespace(get_bus=lambda:SimpleNamespace(pop_filtered=lambda *_:messages.pop(0) if messages else None),set_state=lambda _:0)
        output.paused, output.gestures, output.elapsed, output.last, output.audio_done = False, False, 0.0, 1.0, False
        with patch("echo_controller.robot_output.time.monotonic", return_value=1000):
            self.assertFalse(output.tick())  # Even far beyond duration, elapsed time is not audio completion.
            messages.append(SimpleNamespace(type=2))
            self.assertTrue(output.tick())
        output.cancel()
        self.assertIsNone(output.pipeline)
