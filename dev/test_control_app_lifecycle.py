"""Exercise SDK/audio lifecycle on the explicitly selected Control app mock simulator only."""
import argparse
from importlib.metadata import version
import json
from pathlib import Path
import sys
import time

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"services/controller"))
from echo_controller.robot_output import ReachyControlSimulatorOutput

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("--port",type=int,choices=(8000,),required=True)
args=parser.parse_args()
result={"sdk":version("reachy-mini"),"backend":"official_control_mockup","port":args.port,"checks":{}}
output=ReachyControlSimulatorOutput(args.port,mute_audio=True)
try:
    targets=[]
    send=output.mini.set_target_antenna_joint_positions
    def send_counted(pose):
        targets.append(list(pose))
        send(pose)
    output.mini.set_target_antenna_joint_positions=send_counted
    job=dict(audio_id="companion_welcome",motion_id="WAVE")
    output.start(job)
    baseline=list(output.baseline)
    movement=0.0
    start=time.monotonic()
    while time.monotonic()-start<0.8:
        output.tick()
        observed=output.mini.get_present_antenna_joint_positions()
        movement=max(movement,max(abs(a-b) for a,b in zip(baseline,observed)))
        time.sleep(.04)
    result["max_measured_antenna_excursion_radians"]=movement
    result["checks"]["measured_simulated_motion"]=movement>.015
    output.set_paused(True)
    elapsed=output.elapsed
    count=len(targets)
    start=time.monotonic()
    while time.monotonic()-start<.5:
        output.tick()
        time.sleep(.04)
    state=output.pipeline.get_state(output.Gst.SECOND).state
    result["checks"]["native_audio_paused"]=state==output.Gst.State.PAUSED
    result["checks"]["scheduler_paused"]=abs(output.elapsed-elapsed)<1e-6
    result["checks"]["no_sdk_targets_while_paused"]=len(targets)==count
    output.set_paused(False)
    deadline=time.monotonic()+20
    finished=False
    while time.monotonic()<deadline:
        if output.tick():
            finished=True
            break
        time.sleep(.04)
    result["checks"]["resume_to_real_eos"]=finished
    output.start(job)
    output.tick()
    output.cancel()
    count=len(targets)
    result["checks"]["cancel_removes_audio_pipeline"]=output.pipeline is None
    output.tick()
    result["checks"]["no_sdk_targets_after_cancel"]=len(targets)==count
finally:
    output.close()
folder=ROOT/"artifacts/official-reachy"
folder.mkdir(parents=True,exist_ok=True)
(folder/"control-app-lifecycle.json").write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")
print(json.dumps(result,indent=2))
assert all(result["checks"].values()),"Control app SDK lifecycle check failed"
