"""Warm CPU-only name pronunciation; fixed expressive speech stays prerecorded."""
import base64
import json
import os
from pathlib import Path
import queue
import subprocess
import threading

ROOT=Path(__file__).resolve().parents[3]


class CpuNameVoice:
    def __init__(self):
        relative='Scripts/python.exe' if os.name=='nt' else 'bin/python'
        python=ROOT/'services/speech/.venv'/relative
        helper=Path(__file__).with_name('kokoro_voice.py')
        self.messages=queue.Queue(maxsize=4)
        self.process=subprocess.Popen([str(python),'-u',str(helper),'--name-worker'],cwd=ROOT,
            stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
        self.reader=threading.Thread(target=self._read,daemon=True);self.reader.start()
        try:
            if self.messages.get(timeout=35).get('kind')!='ready':raise RuntimeError('Name voice unavailable.')
        except Exception:
            self.close();raise RuntimeError('CPU name voice could not initialize.') from None
        self.cache={}

    def _read(self):
        try:
            for line in self.process.stdout:
                if line.startswith(b'ECHO_NAME '):self.messages.put(json.loads(line[10:]))
        except Exception:pass
        self.messages.put({'kind':'error'})

    def pronounce(self,name):
        from .reply_understanding import extract_nickname
        if extract_nickname(name)!=name:raise ValueError('Invalid session nickname.')
        if name in self.cache:return self.cache[name]
        self.process.stdin.write((json.dumps({'name':name})+'\n').encode('utf-8'));self.process.stdin.flush()
        body=self.messages.get(timeout=10)
        if body.get('kind')!='audio':raise RuntimeError('CPU name voice failed.')
        pcm=base64.b64decode(body['pcm'],validate=True)
        if not pcm or len(pcm)>24000*2*6:raise RuntimeError('Invalid CPU name audio.')
        self.cache.clear();self.cache[name]=pcm
        return pcm

    def close(self):
        if self.process and self.process.poll() is None:
            self.process.terminate()
            try:self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:self.process.kill()
        self.process=None
        if hasattr(self,'cache'):self.cache.clear()
