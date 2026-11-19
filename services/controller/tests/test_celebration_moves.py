import threading
import time
import unittest
from unittest.mock import patch

from echo_controller.robot_output import MovePlayer, ReachyLiteExpressiveOutput, ReachyLiteOutput


class FakeDaemon:
    """Records calls; a move 'runs' for a few polls. Optional slowness per path."""
    def __init__(self, polls_running=2, slow=None):
        self.calls, self.polls_left, self.polls_running = [], 0, polls_running
        self.slow = slow or {}
        self.lock = threading.Lock()

    def __call__(self, method, path, **_):
        for key, seconds in self.slow.items():
            if key in path:
                time.sleep(seconds)
        with self.lock:
            self.calls.append((method, path))
            if method == "POST" and "/recorded-move-dataset/" in path:
                self.polls_left = self.polls_running
                return {"uuid": "x"}
            if method == "GET" and path.endswith("/running"):
                if self.polls_left:
                    self.polls_left -= 1
                    return [{"uuid": "x"}]
                return []
        return {}

    def posts(self):
        return [path.rsplit("/", 1)[-1] for method, path in self.calls if method == "POST"]


class FakeSounds:
    def __init__(self):
        self.started, self.stopped = [], 0

    def __call__(self, path):
        self.started.append(str(path))
        sounds = self

        class Handle:
            def stop(self):
                sounds.stopped += 1
        return Handle()


def make_output(daemon):
    out = object.__new__(ReachyLiteExpressiveOutput)
    out.pipeline, out.paused, out.voice_duration, out._daemon = None, False, 6., daemon
    out.sounds = out._play_sound = FakeSounds()
    return out


def fast_player(daemon, moves, sounds=None):
    return MovePlayer(daemon, moves, ReachyLiteExpressiveOutput.SOUND_DATASETS, play_sound=sounds,
                      find_sound=lambda dataset, name: f"{name}.ogg", poll=.01)


class MovePlayerTests(unittest.TestCase):
    def test_sound_move_plays_its_own_sound_with_the_motion_no_speaker_handover(self):
        daemon, sounds = FakeDaemon(), FakeSounds()
        player = fast_player(daemon, ReachyLiteExpressiveOutput.LAUGH, sounds)
        player.start(); player.join(10)
        self.assertEqual(daemon.posts(), ["laughing1"])
        self.assertEqual((sounds.started, sounds.stopped), (["laughing1.ogg"], 1))

    def test_stop_ends_move_and_its_music(self):
        daemon, sounds = FakeDaemon(polls_running=10_000), FakeSounds()
        player = fast_player(daemon, ReachyLiteExpressiveOutput.MOVES_AFTER_LINE["companion_ending"], sounds)
        player.start(); time.sleep(.2); player.stop(); player.join(10)
        self.assertFalse(player.is_alive())
        self.assertEqual(daemon.posts(), ["katy-perry-fireworks", "stop"])
        self.assertEqual((sounds.started, sounds.stopped), (["katy-perry-fireworks.ogg"], 1))

    def test_slow_loading_dance_keeps_music_until_it_really_ends(self):
        # The daemon reports nothing running for the first polls while a song
        # dance loads; the player must wait for the start, not stop the music.
        class SlowStart(FakeDaemon):
            def __call__(self, method, path, **kw):
                if method == "GET" and path.endswith("/running") and self.loading > 0:
                    self.loading -= 1
                    return []
                return super().__call__(method, path, **kw)
        daemon, sounds = SlowStart(polls_running=5), FakeSounds()
        daemon.loading = 4
        player = fast_player(daemon, ReachyLiteExpressiveOutput.MOVES_AFTER_LINE["companion_ending"], sounds)
        player.start(); player.join(10)
        running_polls = [c for c in daemon.calls if c[1].endswith("/running")]
        self.assertEqual(daemon.loading, 0)                      # waited through the loading...
        self.assertGreaterEqual(len(running_polls), 5 + 1)       # ...and through the whole dance
        self.assertEqual((sounds.started, sounds.stopped), (["katy-perry-fireworks.ogg"], 1))

    def test_dance_moves_without_sound_play_no_sound(self):
        daemon, sounds = FakeDaemon(), FakeSounds()
        player = fast_player(daemon, (("pollen-robotics/reachy-mini-dances-library", "yeah_nod"),), sounds)
        player.start(); player.join(10)
        self.assertEqual(sounds.started, [])


class CelebrationPlanTests(unittest.TestCase):
    def test_real_start_keeps_laugh_gem_and_dance_plans(self):
        cases = {"companion_h2_humour": ("within_pending", "laughing1"),
                 "companion_market_success": ("moves_pending", "enthusiastic1"),
                 "companion_ending": ("moves_pending", "katy-perry-fireworks")}
        for audio_id, (attribute, move) in cases.items():
            out = make_output(FakeDaemon())
            with patch.object(ReachyLiteOutput, "start", lambda self, job: self.cancel()):
                out.start({"audio_id": audio_id, "motion_id": "NOD"})
            self.assertEqual(getattr(out, attribute)[0][1], move, audio_id)

    def test_plain_joke_and_other_lines_get_no_moves(self):
        for audio_id in ("companion_h1_control", "companion_g1"):
            out = make_output(FakeDaemon())
            with patch.object(ReachyLiteOutput, "start", lambda self, job: self.cancel()):
                out.start({"audio_id": audio_id, "motion_id": "NOD"})
            self.assertEqual((out.moves_pending, out.within_pending), ((), ()), audio_id)


class LaughWithinLineTests(unittest.TestCase):
    def run_joke(self, daemon, limit=15):
        out = make_output(daemon)
        out.within_pending = ReachyLiteExpressiveOutput.LAUGH
        results, slowest = [], 0.
        with patch.object(ReachyLiteOutput, "tick", return_value=True):
            deadline = time.monotonic() + limit
            while time.monotonic() < deadline:
                started = time.monotonic()
                result = out.tick()
                slowest = max(slowest, time.monotonic() - started)
                results.append(result)
                if result:
                    break
                time.sleep(.02)
        return out, results, slowest

    def test_joke_line_completes_only_after_the_laugh(self):
        daemon = FakeDaemon()
        out, results, _ = self.run_joke(daemon)
        self.assertFalse(results[0])
        self.assertTrue(results[-1])
        out.move_player.join(5)
        self.assertEqual(daemon.posts(), ["laughing1"])
        self.assertTrue(out.sounds.started[0].endswith("laughing1.ogg"))
        self.assertGreater(out.voice_duration, 20.)

    def test_slow_daemon_never_blocks_the_worker_loop(self):
        daemon = FakeDaemon(slow={"/recorded-move-dataset/": 3, "/running": 1.5})
        _, results, slowest = self.run_joke(daemon, limit=20)
        self.assertTrue(results[-1])
        self.assertLess(slowest, .2)  # The controller needs a poll every 2 s.

    def test_new_line_stops_running_celebration(self):
        daemon = FakeDaemon(polls_running=10_000)
        out = make_output(daemon)
        out._start_moves(ReachyLiteExpressiveOutput.GEM_CELEBRATION)
        time.sleep(.3)
        started = time.monotonic()
        with patch.object(ReachyLiteOutput, "start", lambda self, job: self.cancel()):
            out.start({"audio_id": "companion_g2", "motion_id": "NOD"})
        self.assertLess(time.monotonic() - started, .2)
        out.move_player.join(10)
        self.assertEqual(daemon.posts()[-1], "stop")


if __name__ == "__main__":
    unittest.main()
