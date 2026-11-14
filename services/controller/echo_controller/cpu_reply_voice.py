"""CPU-only streaming voice for bounded personalized acknowledgements."""
import base64
import json
import os
from pathlib import Path
import queue
import subprocess
import sys
import threading
import uuid

ROOT=Path(__file__).resolve().parents[3]


class CpuReplyVoice:
    def __init__(self):
        relative='Scripts/python.exe' if os.name=='nt' else 'bin/python'
        self.messages=queue.Queue(maxsize=64);self.active_id=''
        self.process=subprocess.Popen([str(ROOT/'services/dialogue/.venv'/relative),'-u',str(Path(__file__)),'--worker'],cwd=ROOT,
            stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
        threading.Thread(target=self._read,daemon=True).start()
        try:
            if self.messages.get(timeout=90).get('kind')!='ready':raise RuntimeError('Voice unavailable.')
        except Exception:
            self.close();raise RuntimeError('CPU reply voice could not initialize.') from None

    def _read(self):
        try:
            for line in self.process.stdout:
                if line.startswith(b'ECHO_CPU '):self.messages.put(json.loads(line[9:]))
        except Exception:pass
        self.messages.put({'kind':'error'})

    def start(self,text):
        if not isinstance(text,str) or not 1<=len(text)<=220 or '\0' in text or '\n' in text:raise ValueError('Invalid reply text.')
        self.active_id=uuid.uuid4().hex
        self.process.stdin.write((json.dumps({'id':self.active_id,'text':text})+'\n').encode('utf-8'));self.process.stdin.flush()

    def poll(self):
        try:body=self.messages.get_nowait()
        except queue.Empty:return None
        if body.get('id') and body['id']!=self.active_id:return None
        if body.get('kind')=='error':raise RuntimeError('CPU reply speech failed.')
        if body.get('id')!=self.active_id:return None
        if body['kind']=='done':return 'done',b'',24000
        pcm=base64.b64decode(body['pcm'],validate=True)
        if body.get('rate')!=24000 or not pcm or len(pcm)>24000*2*5:raise RuntimeError('Invalid CPU audio.')
        return 'audio',pcm,24000

    def close(self):
        if self.process and self.process.poll() is None:
            self.process.terminate()
            try:self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:self.process.kill()
        self.process=None;self.active_id=''


def worker():
    import contextlib
    output=sys.stdout
    def send(body):output.write('ECHO_CPU '+json.dumps(body)+'\n');output.flush()
    os.environ['HF_HOME']=str(ROOT/'tools/narration/pocket-cache')
    os.environ['HF_HUB_OFFLINE']='1';os.environ['HF_HUB_DISABLE_IMPLICIT_TOKEN']='1'
    os.environ['HF_HUB_DISABLE_TELEMETRY']='1'
    with contextlib.redirect_stdout(sys.stderr):
        import numpy as np
        import torch
        from pocket_tts import TTSModel
        torch.set_num_threads(2)
        model=TTSModel.load_model()
        if any(p.device.type!='cpu' for p in model.parameters()):raise RuntimeError('CPU voice required.')
        state=model.get_state_for_audio_prompt('marius')
        # Pay first-inference cost before advertising readiness, not during a reply.
        for _ in model.generate_audio_stream(state,'Hello.'):pass
        if torch.cuda.is_initialized():raise RuntimeError('Unexpected GPU initialization.')
    send({'kind':'ready'})
    for line in sys.stdin.buffer:
        request_id=''
        try:
            if len(line)>2048:raise ValueError('Oversized speech request.')
            body=json.loads(line);request_id=body['id'];text=body['text']
            if not isinstance(text,str) or not 1<=len(text)<=220 or '\0' in text or '\n' in text:raise ValueError('Invalid text.')
            duration=0.
            with contextlib.redirect_stdout(sys.stderr):
                for audio in model.generate_audio_stream(state,text):
                    samples=audio.detach().cpu().numpy()
                    if not len(samples):continue
                    duration+=len(samples)/model.sample_rate
                    if duration>30 or not np.isfinite(samples).all():raise ValueError('Invalid reply audio.')
                    pcm=(np.clip(samples,-1,1)*32767).astype('<i2').tobytes()
                    send({'kind':'audio','id':request_id,'rate':model.sample_rate,'pcm':base64.b64encode(pcm).decode('ascii')})
            send({'kind':'done','id':request_id})
        except Exception:send({'kind':'error','id':request_id})


if __name__=='__main__' and '--worker' in sys.argv:worker()
