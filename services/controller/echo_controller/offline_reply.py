"""Local CPU reply worker; no network, disk transcript or game-control tools."""
import json
import os
from pathlib import Path
import queue
import subprocess
import sys
import threading

ROOT=Path(__file__).resolve().parents[3]


class OfflineReply:
    def __init__(self):
        relative='Scripts/python.exe' if os.name=='nt' else 'bin/python'
        self.messages=queue.Queue(maxsize=4)
        self.process=subprocess.Popen([str(ROOT/'services/dialogue/.venv'/relative),'-u',str(Path(__file__)),'--worker'],
            cwd=ROOT,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
        threading.Thread(target=self._read,daemon=True).start()
        try:
            if self.messages.get(timeout=50).get('kind')!='ready':raise RuntimeError('Unavailable local responder.')
        except Exception:
            self.close();raise RuntimeError('Offline CPU responder could not initialize.') from None

    def _read(self):
        try:
            for line in self.process.stdout:
                if line.startswith(b'ECHO_REPLY '):self.messages.put(json.loads(line[11:]))
        except Exception:pass
        self.messages.put({'kind':'error'})

    def respond(self,question_id,text):
        self.process.stdin.write((json.dumps({'question_id':question_id,'answer':text[:400]})+'\n').encode('utf-8'));self.process.stdin.flush()
        result=self.messages.get(timeout=12)
        if result.get('kind')!='reply':return ''
        return result.get('text','')[:220]

    def close(self):
        if self.process and self.process.poll() is None:
            self.process.terminate()
            try:self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:self.process.kill()
        self.process=None


def worker():
    import contextlib
    output=sys.stdout
    def send(body):output.write('ECHO_REPLY '+json.dumps(body)+'\n');output.flush()
    with contextlib.redirect_stdout(sys.stderr):
        sys.path.insert(0,str(ROOT/'services/dialogue'))
        from topic_responder import TopicResponder
        model=TopicResponder()
        model.respond('G1','I enjoy books about gardens.')
    send({'kind':'ready'})
    for line in sys.stdin.buffer:
        try:
            if len(line)>4096:raise ValueError('Oversized reply request.')
            data=json.loads(line)
            with contextlib.redirect_stdout(sys.stderr):text=model.respond(data['question_id'],data['answer'])
            send({'kind':'reply','text':text})
        except Exception:send({'kind':'reply','text':''})


if __name__=='__main__' and '--worker' in sys.argv:worker()
