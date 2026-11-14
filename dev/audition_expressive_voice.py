"""Audition genuine style-conditioned TTS using fixed, public example lines."""
import html
import json
import os
from pathlib import Path
import time
import wave

ROOT=Path(__file__).resolve().parents[1]
os.environ.setdefault('HF_HOME',str(ROOT/'tools/narration/hf-cache'))
os.environ['HF_HUB_OFFLINE']='1'
os.environ['TRANSFORMERS_OFFLINE']='1'
os.environ['HF_HUB_DISABLE_TELEMETRY']='1'


def main():
    import numpy as np
    import torch
    from qwen_tts import Qwen3TTSModel
    if not torch.cuda.is_available():
        raise RuntimeError('The expressive audition requires the prepared local CUDA environment.')
    torch.set_num_threads(4)
    folder=ROOT/'artifacts/expressive-voice'
    folder.mkdir(parents=True,exist_ok=True)
    model=Qwen3TTSModel.from_pretrained(str(ROOT/'tools/narration/qwen3-customvoice'),
                                     device_map='cuda:0',dtype=torch.bfloat16,attn_implementation='sdpa')
    celebration="You did it! We found the emerald! That's brilliant teamwork!"
    joke="I tried Milo's clock puzzle too. I put the gears in backwards. I was hoping that would give us more time!"
    cases=[
        ('ryan_neutral','Ryan: neutral comparison','Ryan',celebration,'Speak clearly in a calm, neutral, matter-of-fact tone.'),
        ('ryan_cheer','Ryan: cheerful celebration','Ryan',celebration,'Speak with genuine delight and happy excitement, smiling warmly. Celebrate with a friend. Use lively natural pitch variation and an enthusiastic finish. Keep the words clear; do not shout.'),
        ('ryan_joke','Ryan: playful clock joke','Ryan',joke,'Tell a silly joke to a friend with a smile in your voice. Playfully admit your mistake, briefly pause, then deliver the last sentence with amused surprise and a light chuckle. Speak conversationally and clearly, not like an announcer.'),
        ('aiden_cheer','Aiden: cheerful alternative','Aiden',celebration,'Speak with genuine delight and happy excitement, smiling warmly. Celebrate with a friend. Use lively natural pitch variation and an enthusiastic finish. Keep the words clear; do not shout.'),
    ]
    cards=[]; manifest=[]
    for key,label,speaker,text,direction in cases:
        started=time.monotonic()
        torch.manual_seed(57)
        with torch.inference_mode():
            audio,rate=model.generate_custom_voice(text=text,language='English',speaker=speaker,instruct=direction,max_new_tokens=600)
        pcm=np.clip(np.asarray(audio[0]),-1,1)
        if not np.isfinite(pcm).all() or not 1<len(pcm)/rate<35:
            raise RuntimeError('Invalid audition audio.')
        destination=folder/(key+'.wav')
        with wave.open(str(destination),'wb') as output:
            output.setnchannels(1);output.setsampwidth(2);output.setframerate(rate)
            output.writeframes((pcm*32767).astype('<i2').tobytes())
        manifest.append(dict(id=key,speaker=speaker,text=text,instruct=direction,seconds=round(len(pcm)/rate,2),generation_seconds=round(time.monotonic()-started,2)))
        cards.append('<section><h2>'+html.escape(label)+'</h2><p>'+html.escape(text)+'</p><audio controls preload="none" src="'+key+'.wav"></audio></section>')
        print('Rendered',key,'in',manifest[-1]['generation_seconds'],'seconds',flush=True)
        page='<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Reachy emotional voice audition</title><style>body{font:18px system-ui;background:#102e36;color:#edf9f6;max-width:800px;margin:40px auto;padding:24px}section{background:#20434a;border-radius:16px;padding:22px;margin:22px 0}p{line-height:1.6}audio{width:100%}</style><h1>Can you hear the emotion?</h1><p>The first two recordings use exactly the same words and the same speaker. Only the delivery instruction changes. The game still uses its previous voice until this audition is evaluated.</p>'+''.join(cards)+'</html>'
        (folder/'index.html').write_text(page,encoding='utf-8')
        (folder/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':main()
