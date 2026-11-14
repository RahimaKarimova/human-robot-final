import unittest
import json
import wave
from fastapi.testclient import TestClient
from echo_controller.app import create_app
from echo_controller.preview import GAME, DRAFT, ROOT, ADDITIONS, script, hint, all_clips, schedule
from echo_controller.core import Session


class PreviewTests(unittest.TestCase):
    def start(self, condition="humour", output="laptop"):
        self.client = TestClient(create_app())
        config = self.client.post("/session/start", json={"condition": condition, "preview": True, "output":output}).json()
        self.session = self.client.app.state.sessions[config["session_id"]]
        self.headers = {"X-Echo-Session-Token": config["token"]}
        self.number = 0
        self.event("SESSION_READY")

    def event(self, kind, **payload):
        self.number += 1
        result = self.client.post("/game/event", headers=self.headers, json={
            "version": 1, "session_id": self.session.session_id, "event_id": f"preview-{self.number}",
            "stage_id": "library", "event_type": kind, "payload": payload})
        self.assertEqual(result.status_code, 200, result.text)

    def request(self, phase):
        self.event("CONVERSATION_CHECKPOINT_REQUESTED", checkpoint_id="library_" + phase, phase=phase)

    def line(self):
        return self.session.commands[-1]["command"]

    def finish_audio(self):
        self.event("COMPANION_PLAYBACK_COMPLETED", utterance_id=self.line()["utterance_id"], completion="audio_completed")

    def resolve(self, status="ACKNOWLEDGED"):
        command = self.line()
        self.event("CHECKPOINT_ITEM_COMPLETED", checkpoint_id=command["checkpoint_id"],
                   line_id=command["line_id"], status=status, mock=True)

    def letter(self):
        self.event("LETTER_NARRATION_COMPLETED", letter_id="L1", completion="audio_completed", replay=False)

    def test_welcome_finishes_without_asking_for_a_name(self):
        self.start()
        self.event("GAME_AUDIO_STATE_CHANGED", active=True)
        self.request("welcome")
        self.assertEqual(self.session.commands, [])
        self.event("GAME_AUDIO_STATE_CHANGED", active=False)
        self.assertEqual(self.line()["line_id"], "WELCOME")
        self.finish_audio()
        self.resolve()
        self.assertEqual(self.line()["type"], "RESUME_GAME")
        self.assertEqual(schedule('library','welcome'),['WELCOME'])
        self.assertFalse(self.session.nickname)

    def test_jokes_off_omits_h1_and_keeps_the_same_question_and_ack(self):
        scripts = []
        for condition in ("control", "humour"):
            self.start(condition)
            self.letter()
            self.request("before")
            if condition=='humour':
                self.assertEqual(self.line()["text"], DRAFT["condition_overrides"]["H1"][condition])
                self.finish_audio()
                self.resolve()
            else:
                self.assertFalse(any(c['command'].get('line_id')=='H1' for c in self.session.commands))
            self.assertEqual(self.line()["line_id"], "G1")
            scripts.append((self.line()["motion_id"], self.line()["text"], self.line()["audio_id"]))
            self.finish_audio()
            self.assertEqual(self.line()["line_id"], "G1")
            self.resolve("SKIPPED")
            self.assertEqual(self.line()["text"], GAME["skip_acknowledgement"])
            self.finish_audio()
            self.resolve()
            self.assertEqual(self.line()["type"], "RESUME_GAME")
        self.assertEqual(scripts[0], scripts[1])

    def test_jokes_off_is_the_same_campaign_with_only_joke_lines_removed(self):
        jokes=set(DRAFT['condition_overrides'])
        for stage in GAME['stages']:
            phases=['ending'] if stage['id']=='cave' else ['entry','before','after']
            if stage['id']=='library':phases=['welcome']+phases
            for phase in phases:
                on=schedule(stage['id'],phase,'humour')
                off=schedule(stage['id'],phase,'control')
                self.assertEqual(off,[line for line in on if line not in jokes])
                for line in off:
                    self.assertEqual(script(line,'humour'),script(line,'control'))

    def test_repeats_never_add_humour_and_question_repeats_are_exact(self):
        self.start("humour")
        self.letter()
        self.request("before")
        command = self.line()
        self.event("MOCK_REPEAT_REQUESTED", checkpoint_id="library_before", line_id="H1")
        self.assertEqual(self.line(), command)
        self.finish_audio()
        self.resolve()
        question = self.line()
        self.event("MOCK_REPEAT_REQUESTED", checkpoint_id="library_before", line_id="G1")
        self.assertEqual(self.line()["utterance_id"], question["utterance_id"])
        self.finish_audio()
        self.assertEqual(self.line()["text"], question["text"])
        self.assertNotEqual(self.line()["utterance_id"], question["utterance_id"])
        self.assertEqual(sum(c["command"].get("line_id") == "H1" for c in self.session.commands), 1)

    def test_no_acknowledgement_before_playback_completion(self):
        self.start()
        self.request("welcome")
        command = self.line()
        self.number += 1
        result = self.client.post("/game/event", headers=self.headers, json={
            "version": 1, "session_id": self.session.session_id, "event_id": f"early-{self.number}",
            "stage_id": "library", "event_type": "CHECKPOINT_ITEM_COMPLETED", "payload": {
                "checkpoint_id": command["checkpoint_id"], "line_id": command["line_id"],
                "status": "ACKNOWLEDGED", "mock": True}})
        self.assertEqual(result.status_code, 409)
        self.assertEqual(self.session.checkpoints["library_welcome"].index, 0)

    def test_hints_are_shared_and_deferred_behind_game_audio(self):
        for condition in ("control", "humour"):
            self.start(condition)
            self.event("GAME_AUDIO_STATE_CHANGED", active=True)
            for level in (1, 2, 3):
                self.event("HINT_REQUESTED", level=level)
            self.assertEqual(self.session.commands, [])
            self.event("GAME_AUDIO_STATE_CHANGED", active=False)
            self.assertEqual(self.line()["text"], GAME["stages"][0]["hints"][2])
            self.finish_audio()
            self.assertFalse(self.session.delivery)

    def test_success_and_failure_bypass_release_reward_without_answers(self):
        self.start()
        self.letter()
        self.request("after")
        self.assertEqual(self.line()["line_id"], "LIBRARY_SUCCESS")
        self.assertEqual(self.line()["motion_id"], "CELEBRATE")
        self.event("MOCK_CHECKPOINT_BYPASSED", checkpoint_id="library_after")
        self.assertTrue(self.session.delivery)
        self.assertEqual(self.line()["line_id"], "LIBRARY_SUCCESS")
        self.finish_audio()
        self.assertEqual(self.line()["type"], "RESUME_GAME")
        self.assertFalse(self.session.delivery)

    def test_stop_is_terminal_during_speech(self):
        self.start()
        self.request("welcome")
        self.session.stop()
        self.assertFalse(self.session.delivery)
        count = len(self.session.commands)
        self.session.drain()
        self.assertEqual(len(self.session.commands), count)
        self.assertEqual(self.line()["type"], "SESSION_STOP")
        self.event("COMPANION_PLAYBACK_COMPLETED", utterance_id="late-playback", completion="cancelled")
        self.event("GAME_AUDIO_STATE_CHANGED", active=False)
        self.assertEqual(len(self.session.commands), count)
        self.assertTrue(self.session.stopped)

    def test_fast_bypass_before_ui_adoption_finishes_the_offered_robot_line(self):
        self.start(output='bridge_simulator')
        self.request('welcome')
        utterance=self.line()['utterance_id']
        self.event('MOCK_CHECKPOINT_BYPASSED',checkpoint_id='library_welcome')
        self.assertTrue(self.session.robot.job['ready'])
        self.assertFalse(self.session.robot.job['cancel'])
        self.assertTrue(self.session.delivery)
        self.session.robot.finish(self.session,utterance,'simulated_completed')
        self.event('COMPANION_PLAYBACK_COMPLETED',utterance_id=utterance,completion='simulated_completed')
        self.assertEqual(self.line()['type'],'RESUME_GAME')
        self.assertFalse(self.session.after_speech_event)

    def test_panel_cancel_cannot_truncate_robot_and_stop_clears_queued_navigation(self):
        self.start(output='bridge_simulator')
        self.request('welcome')
        utterance=self.line()['utterance_id']
        self.event('COMPANION_CANCEL_REQUESTED',utterance_id=utterance)
        self.assertFalse(self.session.robot.job['cancel'])
        self.event('MOCK_CHECKPOINT_BYPASSED',checkpoint_id='library_welcome')
        self.assertTrue(self.session.after_speech_event)
        self.session.stop()
        self.assertFalse(self.session.after_speech_event)
        self.assertTrue(self.session.robot.job['cancel'])

    def test_repeated_clicks_queue_one_action_without_skipping_the_next_line(self):
        self.start()
        self.letter(); self.request('before')
        self.finish_audio(); self.resolve()
        original=self.line()['utterance_id']
        self.event('MOCK_REPEAT_REQUESTED',checkpoint_id='library_before',line_id='G1')
        self.event('CHECKPOINT_ITEM_COMPLETED',checkpoint_id='library_before',line_id='G1',status='SKIPPED',mock=True)
        self.finish_audio()
        repeated=self.line()['utterance_id']
        self.assertEqual(self.line()['line_id'],'G1')
        self.assertNotEqual(original,repeated)
        self.event('COMPANION_PLAYBACK_COMPLETED',utterance_id=original,completion='audio_completed')
        self.assertEqual(self.line()['utterance_id'],repeated)

    def test_all_fixed_voice_assets_match_script_text_and_share_voice(self):
        manifest = json.loads((ROOT / "assets/audio/manifest.json").read_text(encoding="utf-8-sig"))
        entries = all_clips()
        for entry in entries:
            clip = manifest[entry["audio_id"]]
            self.assertEqual(clip["text"], entry["text"])
            self.assertEqual(clip["voice"], "qwen3-tts-ryan")
            self.assertEqual(clip.get('delivery_profile'),'qwen3_emotion_v1')
            self.assertIn(clip.get('emotion'),{'warm','curious','playful','celebrate','gentle','neutral'})
            if entry['audio_id'].endswith('_humour'): self.assertEqual(clip['emotion'],'playful')
            if 'success' in entry['audio_id']: self.assertEqual(clip['emotion'],'celebrate')
            with wave.open(str(ROOT / clip["path"].removeprefix("res://"))) as audio:
                self.assertEqual(audio.getnchannels(), 1)
                self.assertGreater(audio.getnframes() / audio.getframerate(), 1)

    def test_complete_campaign_script_order_variants_outcomes_and_ending(self):
        for condition in ("control", "humour"):
            session = Session(condition, preview_enabled=True)
            number = 0
            observed = []
            def send(kind, stage="library", **payload):
                nonlocal number
                number += 1
                session.accept(dict(version=1, session_id=session.session_id, event_id=f"campaign-{number}",
                                    stage_id=stage, event_type=kind, payload=payload))
            send("SESSION_READY")
            for stage, phases in (("library", ["welcome", "entry", "before", "after"]),
                                  ("workshop", ["entry", "before", "after"]),
                                  ("market", ["entry", "before", "after"]),
                                  ("temple", ["entry", "before", "after"]), ("cave", ["ending"])):
                session.narrator_ready.add(stage)
                for phase in phases:
                    key = stage + "_" + phase
                    send("CONVERSATION_CHECKPOINT_REQUESTED", stage, checkpoint_id=key, phase=phase)
                    for index, line in enumerate(schedule(stage, phase, condition)):
                        command = session.commands[-1]["command"]
                        self.assertEqual(command["line_id"], line)
                        observed.append(line)
                        if line in DRAFT["condition_overrides"]:
                            self.assertEqual(command["text"], DRAFT["condition_overrides"][line][condition])
                            count = len(session.commands)
                            send("MOCK_REPEAT_REQUESTED", stage, checkpoint_id=key, line_id=line)
                            self.assertEqual(len(session.commands), count)
                        send("COMPANION_PLAYBACK_COMPLETED", stage, utterance_id=command["utterance_id"], completion="audio_completed")
                        status = "SKIPPED" if line in {"P1", "G2"} else "NO_RECALL" if line == "P2" else "ACKNOWLEDGED"
                        send("CHECKPOINT_ITEM_COMPLETED", stage, checkpoint_id=key, line_id=line, status=status, mock=True)
                    self.assertEqual(session.commands[-1]["command"]["type"], "RESUME_GAME")
            self.assertEqual([key for key in observed if key.startswith("H")], ["H1", "H2", "H3", "H4"] if condition=='humour' else [])
            self.assertEqual(observed[-1], "ENDING")
