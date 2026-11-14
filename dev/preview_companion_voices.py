"""Render public audition lines; never record a microphone or personal answers."""
from pathlib import Path
import sys
import wave

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'services/controller'))
from echo_controller.kokoro_voice import load_voice,render

def main():
    folder=ROOT/'artifacts/voice-preview'
    folder.mkdir(parents=True,exist_ok=True)
    voice=load_voice()
    text="Hi there! I'm Reachy, your island adventure buddy. You found another gemstone! Brilliant work! Ready to explore together?"
    cards=[]
    for key,label in [('af_bella','Bella — new default'),('af_heart','Heart — previous voice'),('am_puck','Puck — masculine alternative')]:
        pcm,rate=render(voice,text,.96,voice_id=key)
        with wave.open(str(folder/(key+'.wav')),'wb') as output:
            output.setnchannels(1);output.setsampwidth(2);output.setframerate(rate);output.writeframes(pcm)
        cards.append(f'<section><h2>{label}</h2><audio controls preload="none" src="{key}.wav"></audio></section>')
        print('Rendered audition:',key,flush=True)
    html='''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Reachy voice auditions</title><style>body{font:18px system-ui;background:#102e36;color:#edf9f6;max-width:780px;margin:48px auto;padding:24px}section{padding:20px;margin:20px 0;background:#20434a;border-radius:16px}audio{width:100%}p{line-height:1.6}h2{font-size:22px}</style><h1>Choose Reachy's voice</h1><p>Play each sample to compare. Bella is the new game default, with quicker greetings and celebrations and gentler pacing for reassurance. These are synthetic audition lines; the game keeps its existing dialogue.</p>'''+''.join(cards)+'<p>All samples run offline. No microphone is used.</p></html>'
    (folder/'index.html').write_text(html,encoding='utf-8')

if __name__=='__main__':main()
