"""Measure first playable audio, not just full-clip generation time."""
import json
import os
from pathlib import Path
import time

ROOT=Path(__file__).resolve().parents[1]
os.environ['HF_HUB_OFFLINE']='1'
os.environ['TRANSFORMERS_OFFLINE']='1'
os.environ['HF_HUB_DISABLE_TELEMETRY']='1'


def main():
    import numpy as np
    import torch
    from faster_qwen3_tts import FasterQwen3TTS
    torch.set_num_threads(4)
    print('Loading streaming benchmark.',flush=True)
    model=FasterQwen3TTS.from_pretrained(str(ROOT/'tools/narration/qwen3-customvoice'),
        device='cuda',dtype=torch.bfloat16,attn_implementation='sdpa',max_seq_len=1024)
    with torch.inference_mode():
        model.generate_custom_voice(text='Hello there!',language='English',speaker='Ryan',max_new_tokens=80)
    results=[]
    for chunk_size in (4,8):
        started=time.monotonic(); first=None; chunks=[]; times=[]
        with torch.inference_mode():
            stream=model.generate_custom_voice_streaming(
                text="You did it! We found the emerald! That's brilliant teamwork!",language='English',speaker='Ryan',
                instruct='Speak with genuine delight and cheerful excitement. Smile warmly and celebrate with a friend.',
                chunk_size=chunk_size,max_new_tokens=300)
            for pcm,rate,_ in stream:
                if len(pcm):
                    now=time.monotonic()-started
                    if first is None: first=now
                    chunks.append(np.asarray(pcm));times.append(now)
        assert first is not None and chunks
        # Simulate playback started with a small buffer, and check that production
        # keeps up rather than claiming that one early chunk makes it usable.
        buffer=.2; consumed=0.; max_late=0.
        for pcm,arrived in zip(chunks,times):
            available_at=first+buffer+consumed
            max_late=max(max_late,arrived-available_at)
            consumed+=len(pcm)/rate
        result=dict(chunk_size=chunk_size,first_audio_seconds=round(first,3),total_generation_seconds=round(time.monotonic()-started,3),
                    audio_seconds=round(consumed,3),chunks=len(chunks),late_seconds_with_200ms_buffer=round(max_late,3))
        results.append(result);print(result,flush=True)
    (ROOT/'artifacts/expressive-voice/streaming-benchmark.json').write_text(json.dumps(results,indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':main()
