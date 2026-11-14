"""Muted official Control simulator test; synthetic reply, no microphone."""
from pathlib import Path
import sys
import time
import json

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'services/controller'))
from echo_controller.robot_output import ReachyControlSimulatorOutput

def main():
    output=ReachyControlSimulatorOutput(port=8008,mute_audio=True)
    try:
        assert output.reply_voice,'CPU reply voice failed initialization'
        job={'audio_id':'companion_ack','motion_id':'NOD','generated_reply':True,
             'speech_text':'You enjoy science books. Milo has a workshop full of discoveries.'}
        started=time.monotonic();output.start(job);paused=False;resumed=False;audio_start=None
        while time.monotonic()-started<55:
            complete=output.tick()
            if output.pipeline is not None and audio_start is None:audio_start=time.monotonic()
            if audio_start and not paused and time.monotonic()-audio_start>.6:
                output.set_paused(True);held=output.elapsed
                for _ in range(10):
                    assert not output.tick();time.sleep(.05)
                assert abs(output.elapsed-held)<.02,'Paused speech advanced'
                output.set_paused(False);paused=True;resumed=True
            if complete:break
            time.sleep(.02)
        else:raise AssertionError('No actual audio EOS')
        assert resumed and output.stream_done and output.audio_done
        result={'official_simulator_port':8008,'muted':True,'actual_eos':True,'pause_resume':True,
                'first_playback_seconds':round(audio_start-started,3),'audio_seconds':round(output.voice_duration,2),'microphone_opened':False}
        (ROOT/'artifacts/expressive-voice/cpu-simulator-check.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
        print(json.dumps(result))
    finally:output.close()

if __name__=='__main__':main()
