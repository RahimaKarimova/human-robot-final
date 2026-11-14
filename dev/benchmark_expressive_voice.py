"""Benchmark the compatible CUDA-graph path with public fixed text only."""
import json
import os
from pathlib import Path
import time
import wave

ROOT=Path(__file__).resolve().parents[1]
os.environ['HF_HUB_OFFLINE']='1'
os.environ['TRANSFORMERS_OFFLINE']='1'
os.environ['HF_HUB_DISABLE_TELEMETRY']='1'


def main():
    import numpy as np
    import torch
    from faster_qwen3_tts import FasterQwen3TTS
    torch.set_num_threads(4)
    print('Loading CUDA-graph voice benchmark.',flush=True)
    model=FasterQwen3TTS.from_pretrained(str(ROOT/'tools/narration/qwen3-customvoice'),
                                      device='cuda',dtype=torch.bfloat16,attn_implementation='sdpa',max_seq_len=1024)
    folder=ROOT/'artifacts/expressive-voice'
    results=[]
    for index in range(2):
        torch.manual_seed(57)
        started=time.monotonic()
        with torch.inference_mode():
            audio,rate=model.generate_custom_voice(text="You did it! We found the emerald! That's brilliant teamwork!",
                language='English',speaker='Ryan',instruct='Speak with genuine delight, smiling warmly. Celebrate with a friend. Use lively natural pitch variation and an enthusiastic finish. Keep every word clear.',max_new_tokens=300)
        pcm=np.asarray(audio[0])
        assert np.isfinite(pcm).all() and 1<len(pcm)/rate<25
        seconds=round(time.monotonic()-started,2)
        with wave.open(str(folder/('fast_cheer_'+str(index)+'.wav')),'wb') as output:
            output.setnchannels(1);output.setsampwidth(2);output.setframerate(rate)
            output.writeframes((np.clip(pcm,-1,1)*32767).astype('<i2').tobytes())
        results.append({'run':index,'generation_seconds':seconds,'audio_seconds':round(len(pcm)/rate,2),'sample_rate':rate})
        print(results[-1],flush=True)
    (folder/'fast-benchmark.json').write_text(json.dumps(results,indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':main()
