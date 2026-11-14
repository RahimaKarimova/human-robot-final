"""Local output-only speech. Personalised audio exists only in memory."""
import json
import os
from pathlib import Path
import subprocess
import wave

ROOT=Path(__file__).resolve().parents[3]


def recorded_with_name(text,audio_id,name_voice):
    """Only the short name is synthesized; the emotional delivery is a recording."""
    manifest=json.loads((ROOT/'assets/audio/manifest.json').read_text(encoding='utf-8-sig'))
    entry=manifest[audio_id]
    name,separator,body=text.partition('! ')
    if not separator or body!=entry['text']:
        raise ValueError('Personalised speech does not match its fixed recording.')
    path=(ROOT/entry['path'].removeprefix('res://')).resolve()
    if not path.is_relative_to(ROOT/'assets/audio/companion'):raise ValueError('Invalid fixed voice path.')
    with wave.open(str(path)) as source:
        if source.getframerate()!=24000 or source.getsampwidth()!=2 or source.getnchannels()!=1:
            raise ValueError('Invalid fixed voice audio.')
        fixed=source.readframes(source.getnframes())
    # The fixed line still plays if optional name pronunciation is unavailable.
    try:prefix=name_voice.pronounce(name)+bytes(24000*2//10) if name_voice else b''
    except Exception:prefix=b''  # A missing optional name must never swallow the sentence.
    return prefix+fixed,24000


def delivery_profile(audio_id):
    if 'success' in audio_id or audio_id.endswith('ending'):
        return .94,.28
    if any(key in audio_id for key in ('worry','difficulty','privacy','repair')):
        return 1.03,.3
    if 'reply_' in audio_id or audio_id.endswith('welcome'):
        return .97,.25
    return 1.0,.28


def synthesise_memory(text,audio_id):
    if not isinstance(text,str) or not 1<=len(text)<=220 or '\0' in text or '\n' in text:
        raise ValueError('Unsupported personalised speech.')
    relative='Scripts/python.exe' if os.name=='nt' else 'bin/python'
    engine=Path(os.environ.get('ECHO_VOICE_PYTHON',str(ROOT/'services/speech/.venv'/relative)))
    helper=Path(__file__).with_name('kokoro_voice.py')
    rate=24000
    speed,_=delivery_profile(audio_id)
    try:
        result=subprocess.run([str(engine),str(helper)],
                              input=json.dumps({'text':text,'length_scale':speed}).encode('utf-8'),
                              stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,
                              cwd=ROOT,check=True,timeout=30)
    except Exception:
        raise RuntimeError('Local personalised speech could not be prepared.') from None
    if not result.stdout or len(result.stdout)>rate*2*30:
        raise RuntimeError('Local personalised speech duration was invalid.')
    return result.stdout,int(rate)
