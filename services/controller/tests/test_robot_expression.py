import math
import unittest
from unittest.mock import MagicMock

from echo_controller.robot_expression import expression_pose, approach, rhythm_at, voice_rhythm
from echo_controller.robot_output import clip, ReachyLiteOutput, ReachyMujocoOutput
from echo_controller.core import Session
from echo_controller.robot_worker import Worker


class ExpressionTests(unittest.TestCase):
    def test_speech_keeps_moving_after_original_short_gesture(self):
        poses = [expression_pose('NOD', t, 9., .7)[0] for t in (4.,4.2,4.4)]
        self.assertGreater(max(abs(poses[0][i]-p[i]) for p in poses[1:] for i in range(2)), .05)
        self.assertEqual(expression_pose('NOD',9.,9.,.7)[0], [0.,0.])

    def test_reactions_are_distinct_bounded_and_cheer_is_more_visible(self):
        poses = {motion: expression_pose(motion, .9, 8., .4) for motion in ('WAVE','LISTEN','NOD','POINT','CELEBRATE')}
        self.assertEqual(len({tuple(p[0]) for p in poses.values()}), 5)
        for motion in poses:
            for frame in range(300):
                antennas, xyz, rpy = expression_pose(motion, frame/30., 10., .8)
                self.assertLessEqual(max(map(abs,antennas)), math.radians(40))
                self.assertLessEqual(max(map(abs,rpy)), math.radians(10))
                self.assertLessEqual(max(map(abs,xyz)), .005)
        self.assertGreater(max(map(abs,poses['CELEBRATE'][0])),max(map(abs,poses['NOD'][0])))

    def test_measured_pose_approaches_targets_without_large_time_jump(self):
        current = [3.,-3.]
        target = approach(current,[0.,0.],1.,30.)
        self.assertAlmostEqual(target[0],2.9)
        self.assertAlmostEqual(target[1],-2.9)
        self.assertEqual(approach(current,[0.,0.],1.,0.),current)

    def test_fixed_wav_rhythm_has_speech_and_silence_and_ends(self):
        path,_ = clip('companion_welcome')
        levels = voice_rhythm(str(path))
        self.assertGreater(max(levels), .5)
        self.assertLess(min(levels), .05)
        self.assertEqual(rhythm_at(levels,1000.),0.)

    def test_idle_stops_for_pause_narration_stale_game_and_stop(self):
        session = Session('humour',preview_enabled=True,output='reachy_control_simulator')
        robot = session.robot
        robot.game_seen = robot.clock()
        self.assertTrue(robot.poll(session,'test')['idle_allowed'])
        session.paused=True
        self.assertFalse(robot.poll(session,'test')['idle_allowed'])
        session.paused=False
        session.audio_active=True
        self.assertFalse(robot.poll(session,'test')['idle_allowed'])
        session.audio_active=False
        robot.game_seen=robot.clock()-3
        self.assertFalse(robot.poll(session,'test')['idle_allowed'])
        robot.game_seen=robot.clock()
        session.stop()
        self.assertFalse(robot.poll(session,'test')['idle_allowed'])

    def test_worker_disables_idle_on_connection_failure_and_terminal_stop(self):
        output=MagicMock()
        state={'mode':'reachy_control_simulator','state':'idle','job':None,'idle_allowed':True,'idle_motion':'LISTEN'}
        worker=Worker({'output':'reachy_control_simulator'},output,exchange=lambda *_:state)
        worker.step()
        output.idle_tick.assert_called_with('LISTEN')
        worker.exchange=MagicMock(side_effect=ConnectionError)
        worker.step()
        output.idle_tick.assert_called_with(None)
        worker.exchange=lambda *_:{**state,'state':'stopped','idle_allowed':False}
        self.assertFalse(worker.step())
        output.idle_tick.assert_called_with(None)

    def test_large_expressions_are_simulation_only(self):
        self.assertFalse(ReachyLiteOutput.expressive_simulation)
        self.assertTrue(ReachyMujocoOutput.expressive_simulation)


if __name__ == '__main__':
    unittest.main()
