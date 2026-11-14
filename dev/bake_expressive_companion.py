"""Prepare expressive fixed WAVs here; recipients never need this GPU environment."""
import copy
import hashlib
import json
import os
import shutil
from pathlib import Path
import sys
import time
import wave

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'services/controller'))
sys.path.insert(0,str(ROOT/'services/expressive'))
os.environ['HF_HUB_OFFLINE']='1'
os.environ['TRANSFORMERS_OFFLINE']='1'
os.environ['HF_HUB_DISABLE_TELEMETRY']='1'
from echo_controller import preview
from profiles import CONFIG,performance


def main():
    import numpy as np
    import torch
    from faster_qwen3_tts import FasterQwen3TTS
    proposal=json.loads((ROOT/'services/expressive/jokes_proposal.json').read_text(encoding='utf-8'))
    draft=copy.deepcopy(preview.DRAFT)
    for key in ('H1','H2','H3','H4'):
        item=proposal[key]
        draft['condition_overrides'][key]={c:item['setup']+' '+item[c] for c in ('humour','control')}
        draft['joke_delivery'][key]={'setup':item['setup'],'punchline':item['humour'],'pause_ms':350}
    draft['revision_note']='User requested contextual jokes, expressive recordings and short fictional Reachy self-introductions before the six questions. Core question wording, IDs and schedule retained. Development draft, not participant-approved research wording.'
    preview.DRAFT.clear();preview.DRAFT.update(draft)
    entries=preview.all_clips()
    fingerprint=hashlib.sha256(json.dumps([CONFIG,entries],sort_keys=True).encode()).hexdigest()[:10]
    folder=ROOT/'assets/audio/companion'/('qwen_'+CONFIG['speaker'].lower()+'_'+fingerprint)
    folder.mkdir(parents=True,exist_ok=True)
    report_path=folder/'authoring.json'
    report=json.loads(report_path.read_text(encoding='utf-8')) if report_path.is_file() else {}
    model=None
    manifest_path=ROOT/'assets/audio/manifest.json'
    manifest=json.loads(manifest_path.read_text(encoding='utf-8-sig'))
    torch.set_num_threads(4)
    for entry in entries:
        key=entry['audio_id']; role,direction=performance(key)
        destination=folder/(key+'.wav')
        previous=manifest.get(key,{})
        if ((not destination.is_file() or report.get(key,{}).get('text')!=entry['text']) and previous.get('text')==entry['text']
                and previous.get('voice')=='qwen3-tts-'+CONFIG['speaker'].lower()
                and previous.get('delivery_profile')=='qwen3_emotion_v1' and previous.get('emotion')==role):
            source=(ROOT/previous['path'].removeprefix('res://')).resolve()
            if not source.is_relative_to(ROOT/'assets/audio/companion'):raise ValueError('Invalid cached voice path.')
            if source!=destination:shutil.copyfile(source,destination)
            report[key]={'text':entry['text'],'speaker':CONFIG['speaker'],'emotion':role,'instruct':direction}
        if not destination.is_file() or report.get(key,{}).get('text')!=entry['text']:
            if model is None:
                model=FasterQwen3TTS.from_pretrained(str(ROOT/'tools/narration/qwen3-customvoice'),
                    device='cuda',dtype=torch.bfloat16,attn_implementation='sdpa',max_seq_len=1024)
            started=time.monotonic();torch.manual_seed(57)
            with torch.inference_mode():
                audio,rate=model.generate_custom_voice(text=entry['text'],language='English',speaker=CONFIG['speaker'],instruct=direction,max_new_tokens=450)
            samples=np.asarray(audio[0])
            if not np.isfinite(samples).all() or not 1<len(samples)/rate<35 or rate!=24000:
                raise RuntimeError('Invalid prepared voice asset: '+key)
            temporary=destination.with_suffix('.render.wav')
            with wave.open(str(temporary),'wb') as output:
                output.setnchannels(1);output.setsampwidth(2);output.setframerate(rate)
                output.writeframes((np.clip(samples,-1,1)*32767).astype('<i2').tobytes())
            temporary.replace(destination)
            report[key]={'text':entry['text'],'speaker':CONFIG['speaker'],'emotion':role,'instruct':direction,'seconds':round(len(samples)/rate,2)}
            report_path.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
            print('Prepared',key,role,round(time.monotonic()-started,2),'seconds',flush=True)
        manifest[key]={'path':'res://'+destination.relative_to(ROOT).as_posix(),'text':entry['text'],
            'voice':'qwen3-tts-'+CONFIG['speaker'].lower(),'delivery_profile':'qwen3_emotion_v1','emotion':role,
            'provenance':'user_requested_simple_joke_revision' if key.startswith(('companion_h1_','companion_h2_','companion_h3_','companion_h4_')) else entry['provenance']}
    # Publish only after every recording exists. Existing sessions keep their old
    # paths, so preparing a new voice cannot overwrite the audio they are using.
    report_path.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    temporary=manifest_path.with_suffix('.prepared.json')
    temporary.write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    (ROOT/'services/protocol/draft_dialogue.json').write_text(json.dumps(draft,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    temporary.replace(manifest_path)
    print('Published all',len(entries),'expressive recordings. Playback requires no GPU.',flush=True)


if __name__=='__main__':main()
