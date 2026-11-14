"""Check CPU-only personalized speech using a public synthetic voice reference."""
import json
import os
from pathlib import Path
import time
import wave

ROOT=Path(__file__).resolve().parents[1]
os.environ['HF_HOME']=str(ROOT/'tools/narration/pocket-cache')
os.environ['HF_HUB_DISABLE_IMPLICIT_TOKEN']='1'
os.environ['HF_HUB_DISABLE_TELEMETRY']='1'


def main():
    import numpy as np
    import torch
    from pocket_tts import TTSModel,export_model_state
    torch.set_num_threads(2)
    print('Loading CPU-only voice model.',flush=True)
    model=TTSModel.load_model()
    assert all(p.device.type=='cpu' for p in model.parameters())
    print('Model is on CPU. Using the public Marius preset; no gated cloning weights.',flush=True)
    state=model.get_state_for_audio_prompt('marius')
    export_model_state(state,str(ROOT/'artifacts/expressive-voice/marius-pocket.safetensors'))
    started=time.monotonic(); first=None; chunks=[]
    for audio in model.generate_audio_stream(state,'Lovely to meet you, Alex!'):
        samples=audio.detach().cpu().numpy()
        if len(samples):
            if first is None:first=time.monotonic()-started
            chunks.append(samples)
    pcm=np.concatenate(chunks)
    with wave.open(str(ROOT/'artifacts/expressive-voice/cpu_name.wav'),'wb') as output:
        output.setnchannels(1);output.setsampwidth(2);output.setframerate(model.sample_rate)
        output.writeframes((np.clip(pcm,-1,1)*32767).astype('<i2').tobytes())
    result={'device':'cpu','threads':2,'first_audio_seconds':round(first,3),'total_seconds':round(time.monotonic()-started,3),'audio_seconds':round(len(pcm)/model.sample_rate,3),'cuda_initialized':torch.cuda.is_initialized()}
    assert not result['cuda_initialized']
    (ROOT/'artifacts/expressive-voice/cpu-benchmark.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(result,flush=True)


if __name__=='__main__':main()
