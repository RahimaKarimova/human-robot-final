"""Offline voice helper. Input text and generated audio stay in memory."""
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
VOICE_ID = 'af_bella'
VOICE_PROFILE = 'friendly_v2'


def load_voice():
    import onnxruntime as rt
    from kokoro_onnx import Kokoro
    options = rt.SessionOptions()
    options.intra_op_num_threads = 4
    options.inter_op_num_threads = 1
    folder = ROOT / 'tools/narration/kokoro'
    session = rt.InferenceSession(str(folder/'kokoro-v1.0.onnx'), sess_options=options,
                                providers=['CPUExecutionProvider'])
    return Kokoro.from_session(session, str(folder/'voices-v1.0.bin'))


def render(voice, text, length_scale=1.0, voice_id=VOICE_ID):
    import numpy as np
    if voice_id not in {'af_heart','af_bella','am_puck'}:
        raise ValueError('Unsupported companion voice.')
    samples, rate = voice.create(text, voice=voice_id, speed=1.0/length_scale, lang='en-us')
    return (np.clip(samples, -1, 1)*32767).astype('<i2').tobytes(), int(rate)


def name_worker():
    import base64
    import contextlib
    protocol=sys.stdout
    def send(body):
        protocol.write('ECHO_NAME '+json.dumps(body)+'\n');protocol.flush()
    with contextlib.redirect_stdout(sys.stderr):
        voice=load_voice()
        render(voice,'Hello!',voice_id='am_puck')
    send({'kind':'ready'})
    for line in sys.stdin.buffer:
        try:
            body=json.loads(line)
            name=body['name']
            if not isinstance(name,str) or not 1<=len(name)<=32 or not all(c.isalpha() or c in " '-" for c in name):
                raise ValueError('Invalid nickname.')
            with contextlib.redirect_stdout(sys.stderr):
                pcm,rate=render(voice,name+'!',.97,voice_id='am_puck')
            if rate!=24000:raise ValueError('Unexpected rate.')
            send({'kind':'audio','pcm':base64.b64encode(pcm).decode('ascii')})
        except Exception:send({'kind':'error'})


if __name__ == '__main__' and '--name-worker' in sys.argv:
    name_worker()
elif __name__ == '__main__':
    request = json.loads(sys.stdin.buffer.read(4096))
    text = request['text']
    if not isinstance(text, str) or not 1 <= len(text) <= 220 or '\n' in text or '\0' in text:
        raise ValueError('Unsupported voice input.')
    pcm, rate = render(load_voice(), text, request.get('length_scale', 1.0))
    if rate != 24000:
        raise ValueError('Unexpected voice sample rate.')
    sys.stdout.buffer.write(pcm)
