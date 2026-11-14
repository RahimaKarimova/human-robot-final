"""Measure expressions against the official Control app mock simulator only."""
import json
from pathlib import Path
import sys
import time

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'services/controller'))
from echo_controller.robot_output import ReachyControlSimulatorOutput

output=ReachyControlSimulatorOutput(mute_audio=True)
checks={}
measurements={}
try:
    commands=[]
    antenna_send=output.mini.set_target_antenna_joint_positions
    head_send=output.mini.set_target_head_pose
    def send_antennas(pose):
        commands.append('antenna')
        antenna_send(pose)
    def send_head(pose):
        commands.append('head')
        head_send(pose)
    output.mini.set_target_antenna_joint_positions=send_antennas
    output.mini.set_target_head_pose=send_head

    # Wake the simulation smoothly from its initial parked pose.
    end=time.monotonic()+5
    while time.monotonic()<end:
        output.idle_tick('IDLE')
        time.sleep(.04)
    idle=[]
    heads=[]
    end=time.monotonic()+4
    while time.monotonic()<end:
        output.idle_tick('IDLE')
        idle.append(list(output.mini.get_present_antenna_joint_positions()))
        heads.append(float(output.mini.get_current_head_pose()[0,1]))
        time.sleep(.04)
    def excursion(samples):
        return max(max(p[i] for p in samples)-min(p[i] for p in samples) for i in range(2))
    measurements['idle_excursion_radians']=excursion(idle)
    checks['idle_has_measured_movement']=excursion(idle)>.01
    checks['head_commands_sent_through_sdk']='head' in commands
    measurements['head_rotation_matrix_excursion']=max(heads)-min(heads)
    checks['head_motion_observed_in_sdk_state']=max(heads)-min(heads)>.005
    count=len(commands)
    for _ in range(8):
        output.idle_tick(None)
        time.sleep(.03)
    checks['disabled_idle_sends_no_targets']=len(commands)==count

    output.start({'audio_id':'companion_welcome','motion_id':'NOD'})
    late=[]
    completed=False
    end=time.monotonic()+25
    while time.monotonic()<end:
        completed=output.tick()
        if output.elapsed>3:
            late.append(list(output.mini.get_present_antenna_joint_positions()))
        if completed: break
        time.sleep(.04)
    checks['speech_finishes_on_real_eos']=completed and output.audio_done
    measurements['late_speech_excursion_radians']=excursion(late) if late else 0
    checks['speech_moves_after_three_seconds']=len(late)>3 and excursion(late)>.02
    output.cancel()

    output.start({'audio_id':'companion_library_success','motion_id':'CELEBRATE'})
    cheer=[]
    end=time.monotonic()+2
    while time.monotonic()<end:
        output.tick()
        cheer.append(list(output.mini.get_present_antenna_joint_positions()))
        time.sleep(.04)
    measurements['cheer_peak_radians']=max(abs(v) for p in cheer for v in p)
    checks['cheer_is_visibly_perked']=measurements['cheer_peak_radians']>.3
    output.set_paused(True)
    count=len(commands)
    for _ in range(8):
        output.tick()
        time.sleep(.03)
    checks['pause_freezes_head_and_antennas']=len(commands)==count
    output.set_paused(False)
    output.tick()
    checks['resume_restarts_motion']=len(commands)>count
    output.cancel()
    count=len(commands)
    output.tick()
    checks['cancel_sends_no_late_targets']=len(commands)==count
finally:
    output.close()

result={'sdk':'1.14.0','backend':'official_control_mockup','checks':checks,'measurements':measurements}
folder=ROOT/'artifacts/official-reachy'
folder.mkdir(parents=True,exist_ok=True)
(folder/'expressions.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
assert all(checks.values()),'An expressive SDK check failed'
