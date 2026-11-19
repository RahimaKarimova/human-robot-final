"""Offline push-to-talk command recognition. Input and transcripts stay transient in RAM."""
import argparse
import json
import os
from pathlib import Path
import threading
import time
import uuid
import wave
import math
from array import array
import sys
from urllib.request import Request, build_opener, ProxyHandler

from .companion_gateway import local_url, NoRedirect, classify_control, RasaParser
from .companion_gateway import normalize,PHRASES
from .reply_understanding import extract_nickname

SAMPLE_RATE = 16000
MAX_BYTES = SAMPLE_RATE * 2 * 8
MAX_REPLY_BYTES = SAMPLE_RATE * 2 * 180  # Long free answers (3 min); commands stay 8 s.
REPLY_SECONDS = 179.5  # Held-B answer limit, just under the 3 min buffer.


def input_level(pcm):
    samples=array('h',bytes(pcm))
    if sys.byteorder!='little': samples.byteswap()
    if not samples: return 0.
    rms=math.sqrt(sum(float(value)*value for value in samples)/len(samples))/32768.
    return max(0.,min(1.,(20*math.log10(max(rms,1e-6))+55)/55))


class MicrophoneCapture:
    max_bytes = MAX_BYTES
    def __init__(self, device=None):
        self.device = device
        self.stream = None
        self.buffer = bytearray()
        self.lock = threading.Lock()
        self.full = False
        self.meter_level=0.
        self.meter_sequence=0
        self.meter_at=0.
        self.preview_enabled=False
        self.preview_buffer=bytearray()

    def _measure(self,data):
        self.meter_level=input_level(data)
        self.meter_sequence+=1
        self.meter_at=time.monotonic()
        if self.preview_enabled:
            self.preview_buffer.extend(bytes(data))
            # Partial captions may lag; never discard a valid final answer merely
            # because the optional preview decoder is busy.
            del self.preview_buffer[:-SAMPLE_RATE*2*12]

    def take_preview(self):
        with self.lock:
            pcm=bytes(self.preview_buffer)
            self.preview_buffer.clear()
        return pcm

    def meter_snapshot(self):
        with self.lock:
            return self.meter_level,self.meter_sequence,self.meter_at

    def open(self):
        import sounddevice as sd
        def callback(data, _frames, _timing, status):
            with self.lock:
                if status:
                    self.full = True
                    return
                self._measure(data)
                available = self.max_bytes - len(self.buffer)
                self.buffer.extend(bytes(data)[:available])
                self.full = self.full or len(self.buffer) >= self.max_bytes
        self.stream = sd.RawInputStream(samplerate=SAMPLE_RATE, blocksize=800, device=self.device,
                                       dtype="int16", channels=1, callback=callback)
        self.stream.start()

    def close(self):
        self.meter_level,self.meter_at=0.,0.
        if self.stream is not None:
            stream,self.stream=self.stream,None
            try:
                stream.abort()
            except Exception:
                pass
            try:
                stream.close()
            except Exception:
                pass

    def take(self):
        self.close()
        with self.lock:
            data = bytes(self.buffer)
            self.buffer.clear()
            self.preview_buffer.clear()
        return data

    def discard(self):
        self.close()
        with self.lock:
            self.buffer.clear()
            self.preview_buffer.clear()


class AutomaticCapture(MicrophoneCapture):
    """Question-only capture, closed before STT; VAD never implies an answer."""
    def __init__(self,device=None):
        super().__init__(device)
        from .voice_turn import VoiceTurn
        self.turn=VoiceTurn()
        self.done=False

    def open(self):
        import sounddevice as sd
        def callback(data,_frames,_timing,status):
            with self.lock:
                if status:
                    self.full=True
                    return
                self._measure(data)
                state=self.turn.feed(bytes(data))
                self.done=state=='complete'
                self.full=self.full or state=='too_long'
        self.stream=sd.RawInputStream(samplerate=SAMPLE_RATE,blocksize=320,device=self.device,
                                     dtype='int16',channels=1,callback=callback)
        self.stream.start()

    def take(self):
        self.close()
        with self.lock:
            self.preview_buffer.clear()
            return self.turn.take()

    def discard(self):
        super().discard()
        with self.lock:
            self.turn.discard()


class LiveDecoder:
    def __init__(self,model):
        from vosk import KaldiRecognizer
        self.decoder=KaldiRecognizer(model,SAMPLE_RATE)
        self.stable=''

    def feed(self,pcm):
        if self.decoder.AcceptWaveform(pcm):
            self.stable=(self.stable+' '+json.loads(self.decoder.Result()).get('text','')).strip()
        partial=json.loads(self.decoder.PartialResult()).get('partial','')
        return (self.stable+' '+partial).strip()[-400:]


def whisper_samples(pcm):
    """Conservative gain for quiet speech; never amplify near-silence."""
    import numpy as np
    samples=np.frombuffer(pcm,dtype='<i2').astype(np.float32)/32768.
    if not len(samples): return samples
    rms=float(np.sqrt(np.mean(samples*samples)))
    peak=float(np.max(np.abs(samples)))
    if rms>=.001 and peak>0:
        samples*=max(1.,min(4.,.08/rms,.98/peak))
    return samples


CHUNK_SECONDS = 20  # Transcribe long held-B answers in pieces while people talk.


def quiet_cut(pcm, search_seconds=4, window_ms=100):
    """Byte offset of the quietest moment in the last few seconds, so a piece
    boundary falls between words rather than inside one."""
    import numpy as np
    samples=np.frombuffer(pcm,dtype='<i2').astype(np.float32)
    window=SAMPLE_RATE*window_ms//1000
    start=max(0,len(samples)-SAMPLE_RATE*search_seconds)
    best,best_energy=len(samples),None
    for offset in range(start,len(samples)-window+1,window//2):
        energy=float(np.mean(samples[offset:offset+window]**2))
        if best_energy is None or energy<best_energy:
            best,best_energy=offset+window//2,energy
    return best*2


class WhisperLiveDecoder:
    """Bounded rolling preview, decoded outside the capture polling loop."""
    def __init__(self,model):
        self.model=model
        self.audio=bytearray()

    def feed(self,pcm):
        import numpy as np
        self.audio.extend(pcm)
        del self.audio[:-SAMPLE_RATE*2*12]
        samples=whisper_samples(bytes(self.audio))
        if len(samples)<SAMPLE_RATE*1.2 or float(np.sqrt(np.mean(samples*samples)))<.001:
            return ''
        segments,_=self.model.transcribe(samples,language='en',beam_size=1,temperature=0.0,
                                        condition_on_previous_text=False,vad_filter=False)
        return ' '.join(s.text.strip() for s in segments if s.avg_logprob>-1.0 and s.no_speech_prob<.6)[-400:]


class OfflineRecognizer:
    def __init__(self, path, parser=None, dialogue=None,final_model=None,preview_model=None,responder=None):
        from vosk import Model, SetLogLevel
        SetLogLevel(-1)
        if not (Path(path) / "am/final.mdl").is_file():
            raise ValueError("Install the local English recognition model first.")
        self.model = Model(str(path))
        self.parser = parser or RasaParser()
        self.dialogue = dialogue
        self.responder=responder
        self.final_model=None
        self.preview_model=None
        self.last_text=''
        self.reply_kind='DEFAULT'
        self.nickname=''
        self.reply_text=''
        if final_model:
            from faster_whisper import WhisperModel
            self.final_model=WhisperModel(str(final_model),device='cpu',compute_type='int8',cpu_threads=4,local_files_only=True)
        if preview_model:
            from faster_whisper import WhisperModel
            self.preview_model=WhisperModel(str(preview_model),device='cpu',compute_type='int8',cpu_threads=2,local_files_only=True)

    def stream(self):
        if self.preview_model:
            return WhisperLiveDecoder(self.preview_model)
        return LiveDecoder(self.model)

    def transcribe_chunk(self, pcm):
        """Accurate (final-model) transcription of one piece of audio.

        Returns (text, [(avg_logprob, no_speech_prob), ...]). Used for chunks
        transcribed while a long answer is still being spoken, and for the tail.
        """
        import numpy as np
        samples=whisper_samples(pcm)
        if not len(samples) or float(np.sqrt(np.mean(samples*samples)))<.001:
            return '',[]
        segments,_=self.final_model.transcribe(samples,language='en',beam_size=5,temperature=0.0,condition_on_previous_text=False,
                                             vad_filter=False,no_speech_threshold=.6)
        segments=list(segments)
        return (' '.join(segment.text.strip() for segment in segments).strip(),
                [(segment.avg_logprob,segment.no_speech_prob) for segment in segments])

    def controls(self, pcm, reply=False,question_id='',pretranscribed=None):
        from vosk import KaldiRecognizer
        self.last_text,self.reply_kind,self.nickname='','DEFAULT',''
        self.reply_text=''
        if not pcm or len(pcm) > (MAX_REPLY_BYTES if reply else MAX_BYTES):
            return "UNKNOWN", 0.0, "unrecognized"
        if getattr(self,'final_model',None):
            # pretranscribed = (text, stats, bytes_done): pieces already transcribed
            # while the person was still talking; only the remaining tail is left.
            prefix,stats,done=pretranscribed or ('',[],0)
            tail_text,tail_stats=self.transcribe_chunk(pcm[done:]) if len(pcm)>done else ('',[])
            stats=list(stats)+tail_stats
            text=' '.join(part for part in (prefix,tail_text) if part).strip()[:4000]
            if not text:
                return 'UNKNOWN',0.,'unrecognized'
            confident=bool(stats and sum(item[0] for item in stats)/len(stats)>-1.1
                           and min(item[1] for item in stats)<.6)
        else:
            recognizer = KaldiRecognizer(self.model, SAMPLE_RATE)
            recognizer.SetWords(True)
            recognizer.AcceptWaveform(pcm)
            result = json.loads(recognizer.FinalResult())
            words = result.get("result", [])
            text=result.get('text','')[:4000]
            confident=bool(words and min(word.get('conf',0.) for word in words)>=.8
                           and sum(word.get('conf',0.) for word in words)/len(words)>=.9)
        self.last_text=text
        # Full-vocabulary recognition, then whole-phrase allowlisting. A constrained
        # grammar could force a personal answer/negation into the nearest command.
        if not confident:
            if self.dialogue:
                self.dialogue.decide('UNKNOWN')
            return "UNKNOWN", 0.0, "unrecognized"
        if self.dialogue and normalize(text) in PHRASES:
            intent=PHRASES[normalize(text)]
            if intent!='STOP': self.dialogue.decide(intent)
            return intent,1.,'safety' if intent=='STOP' else 'rasa'
        outcome=classify_control(text, self.parser)
        if reply and outcome[0] == "UNKNOWN" and outcome[2] == "unrecognized":
            if self.dialogue:
                if question_id=='NAME':
                    self.nickname=extract_nickname(text)
                    if self.nickname:
                        self.dialogue.decide('NAME_GIVEN')
                        self.reply_kind='NAME_GIVEN'
                    else:
                        self.dialogue.decide('REPLY')
                else:
                    self.reply_kind=self.dialogue.understand(text,question_id)
                    if self.reply_kind=='DEFAULT' and self.responder:
                        self.reply_text=self.responder.respond(question_id,text)
                        # If no grounded reply can be generated (long, multi-part answers),
                        # still accept the answer: Reachy gives its warm general
                        # acknowledgement instead of ignoring what the person said.
            return "REPLY",1.0,"reply"  # Bound reply mode; only intent markers enter Core.
        if self.dialogue and outcome[0] not in {'UNKNOWN','STOP'}:
            self.dialogue.decide(outcome[0])
        return outcome


class SpeechWorker:
    def __init__(self, config, recognizer, capture_factory=MicrophoneCapture, device=None, exchange=None, clock=time.monotonic,automatic_factory=AutomaticCapture):
        self.config, self.recognizer = config, recognizer
        self.capture_factory, self.device = capture_factory, device
        self.worker_id = uuid.uuid4().hex
        self.capture = None
        self.capture_id = ""
        self.seen = set()
        self.pending_result = None
        self.reply = False
        self.clock, self.capture_started = clock, 0.0
        self.exchange = exchange or self._exchange
        self.automatic_factory=automatic_factory
        self.automatic=False
        self.last_meter_sent=0.
        self.live_decoder=None
        self.live_future=None
        self.live_loading=False
        self.caption_pool=None
        from concurrent.futures import ThreadPoolExecutor
        self.chunk_pool=ThreadPoolExecutor(max_workers=1)  # Long-answer pieces, transcribed while talking.
        self.chunker=None
        self.question_id=''
        self.caption_revision=0
        self.last_caption=''
        self.last_caption_at=0.

    def caption(self,text,final=False):
        self.caption_revision+=1
        self.exchange('/speech/caption',dict(capture_id=self.capture_id,text=text[:4000],revision=self.caption_revision,final=final))
        self.last_caption=text
        self.last_caption_at=self.clock()

    def _exchange(self, route, payload):
        request = Request(local_url(self.config["url"]) + route,
            data=json.dumps({"session_id":self.config["session_id"], "worker_id":self.worker_id, **payload}).encode(),
            headers={"Content-Type":"application/json", "X-Echo-Speech-Token":self.config["speech_token"]})
        with build_opener(ProxyHandler({}), NoRedirect()).open(request, timeout=0.8) as response:
            data = response.read(65537)
        if len(data) > 65536:
            raise ValueError("Speech response limit exceeded.")
        return json.loads(data)

    def _chunk_step(self):
        """While a long answer is spoken, transcribe finished ~20 s pieces in the
        background so only a short tail is left when the key is released."""
        chunker=self.chunker
        if chunker['future'] is not None:
            if not chunker['future'].done():
                return
            self._chunk_collect()
            if self.chunker is None:
                return
        with self.capture.lock:
            length=len(self.capture.buffer)
            if length-chunker['done']<SAMPLE_RATE*2*CHUNK_SECONDS:
                return
            region=bytes(self.capture.buffer[chunker['done']:length])
        cut=quiet_cut(region)
        if cut<SAMPLE_RATE*2:
            return
        chunker['cut']=chunker['done']+cut
        chunker['future']=self.chunk_pool.submit(self.recognizer.transcribe_chunk,region[:cut])

    def _chunk_collect(self):
        chunker=self.chunker
        try:
            text,stats=chunker['future'].result()
        except Exception:
            self.chunker=None  # Fall back to transcribing the whole answer at the end.
            return
        chunker['future']=None
        if text:
            chunker['texts'].append(text)
        chunker['stats']+=stats
        chunker['done']=chunker['cut']

    def _chunks_done(self):
        chunker=getattr(self,'chunker',None)
        if not chunker:
            self.chunker=None
            return None
        if chunker['future'] is not None:
            self._chunk_collect()  # Waits for the piece being transcribed right now.
            chunker=self.chunker
        self.chunker=None
        if not chunker:
            return None
        return ' '.join(chunker['texts']),chunker['stats'],chunker['done']

    def discard(self):
        self.chunker=None
        self.live_decoder=None
        if self.live_future:
            self.live_future.cancel()
            self.live_future=None
        if self.capture is not None:
            self.capture.discard()
            self.capture = None

    def finish(self, recognize):
        outcome = ("UNKNOWN", 0.0, "unrecognized")
        if os.environ.get("ECHO_ROBOT_DEBUG") == "1":  # Bench diagnostics: timing only, never words.
            held=self.clock()-getattr(self,'capture_started',self.clock())
            print(f"[speech-worker {time.strftime('%H:%M:%S')}] finish recognize={recognize} reply={self.reply} "
                  f"held={held:.1f}s full={getattr(self.capture,'full',None)}",file=sys.stderr,flush=True)
        if recognize and self.capture is not None:
            pcm = self.capture.take()
            self.capture = None
            self.live_decoder=None
            if self.live_future:
                self.live_future.cancel()
                self.live_future=None
            try:
                self.exchange("/speech/processing",{"capture_id":self.capture_id})
                if self.config.get('conversation',False):
                    outcome=self.recognizer.controls(pcm,reply=self.reply,question_id=self.question_id,
                                                     pretranscribed=self._chunks_done())
                    self.caption(self.recognizer.last_text,final=True)
                else:
                    outcome = self.recognizer.controls(pcm, reply=True) if self.reply else self.recognizer.controls(pcm)
            finally:
                pcm = None
        else:
            self.discard()
        self.pending_result = dict(capture_id=self.capture_id, intent=outcome[0], confidence=outcome[1], source=outcome[2])
        if self.automatic:
            self.pending_result['speech_detected']=recognize
        if recognize and self.config.get('conversation',False):
            self.pending_result['reply_kind']=self.recognizer.reply_kind
            self.pending_result['nickname']=self.recognizer.nickname
            if getattr(self.recognizer,'reply_text',''):
                self.pending_result['reply_text']=self.recognizer.reply_text

    def step(self):
        try:
            if self.pending_result:
                self.exchange("/speech/result", self.pending_result)
                self.pending_result = None
                self.capture_id = ""
            state = self.exchange("/speech/poll", {})
            job = state.get("job")
            if self.capture and (not job or job["capture_id"] != self.capture_id):
                self.discard()
            if state["stopped"]:
                self.discard()
                return False
            if job:
                if job["capture_id"] != self.capture_id:
                    self.capture_id = job["capture_id"]
                    self.reply = job.get("purpose") == "reply"
                    self.automatic=job.get('automatic',False) and self.config.get('conversation',False)
                    self.question_id=job.get('question_id','')
                    self.caption_revision=0
                    self.last_caption=''
                    self.live_decoder=None
                    if self.config.get('conversation',False):
                        from concurrent.futures import ThreadPoolExecutor
                        if self.caption_pool is None:
                            self.caption_pool=ThreadPoolExecutor(max_workers=1)
                        self.live_loading=True
                        self.live_future=self.caption_pool.submit(self.recognizer.stream)
                    if self.capture_id in self.seen:
                        self.finish(False)
                        return True
                    self.seen.add(self.capture_id)
                    if job["phase"] == "listen":
                        self.capture = (self.automatic_factory if self.automatic else self.capture_factory)(self.device)
                        self.capture.reply_mode = self.reply
                        if self.reply and not self.automatic:
                            # Held-B answers can be long; commands (V) stay short.
                            self.capture.max_bytes = MAX_REPLY_BYTES
                        self.capture.preview_enabled=self.config.get('conversation',False)
                        self.capture.open()
                        self.capture_started = self.clock()
                        self.chunker=None
                        if (self.reply and not self.automatic and self.config.get('conversation',False)
                                and getattr(self.recognizer,'final_model',None) and hasattr(self.capture,'buffer')):
                            self.chunker={'texts':[],'stats':[],'done':0,'cut':0,'future':None}
                        self.exchange("/speech/started", {"capture_id":self.capture_id})
                if self.capture and job['phase']=='listen' and self.live_future and self.live_future.done():
                    result=self.live_future.result()
                    self.live_future=None
                    if self.live_loading:
                        self.live_decoder=result
                        self.live_loading=False
                    elif result!=self.last_caption:
                        self.caption(result)
                if self.capture and job['phase']=='listen' and self.live_decoder and not self.live_future and self.clock()-self.last_caption_at>=.8 and hasattr(self.capture,'take_preview'):
                    preview=self.capture.take_preview()
                    if preview:
                        self.live_future=self.caption_pool.submit(self.live_decoder.feed,preview)
                if self.capture and job['phase']=='listen' and getattr(self,'chunker',None):
                    self._chunk_step()
                if job["phase"] == "cancel":
                    self.finish(False)
                elif (self.capture and self.reply and not self.automatic
                      and (self.capture.full or self.clock() - self.capture_started >= REPLY_SECONDS)):
                    self.finish(True)  # A long held-B answer is submitted at the limit, not discarded.
                elif (self.capture and not (self.reply and not self.automatic)
                      and (self.capture.full or self.clock() - self.capture_started >= (45.0 if self.automatic else 8.0))):
                    self.finish(False)  # Never interpret a truncated/overflowed control phrase.
                elif self.capture and self.automatic and self.capture.done:
                    self.exchange('/speech/end-turn',{'capture_id':self.capture_id})
                    self.finish(True)
                elif job["phase"] == "finish":
                    self.finish(True)
                if self.capture and job['phase']=='listen' and hasattr(self.capture,'meter_snapshot'):
                    now=self.clock()
                    level,sequence,measured_at=self.capture.meter_snapshot()
                    if sequence>0 and 0<=time.monotonic()-measured_at<.3 and now-self.last_meter_sent>=.12:
                        self.exchange('/speech/level',{'capture_id':self.capture_id,'level':level,'sequence':sequence})
                        self.last_meter_sent=now
            return True
        except Exception as error:
            # Never print exception values: drivers/recognizers can include device
            # or transcript text. Close the device before any reconnect attempt.
            if getattr(self,'synthetic_diagnostics',False) or os.environ.get("ECHO_ROBOT_DEBUG") == "1":
                import traceback
                frame=traceback.extract_tb(error.__traceback__)[-1]
                print('Synthetic speech failure:',type(error).__name__,Path(frame.filename).name,frame.lineno,flush=True)
            self.discard()
            if self.capture_id:
                self.pending_result = dict(capture_id=self.capture_id,intent="UNKNOWN",confidence=0.0,source="unavailable")
            return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--device", type=int)
    parser.add_argument("--test-fixture", type=Path, help="Synthetic 16 kHz mono PCM WAV test input; opens no microphone")
    parser.add_argument('--conversation-test-branches',action='store_true')
    parser.add_argument('--rasa-url',default='http://127.0.0.1:5006')
    args = parser.parse_args()
    if args.conversation_test_branches and not args.test_fixture:
        parser.error('Conversation branch fixtures require synthetic input.')
    try:
        config = json.loads(args.config.read_text(encoding="utf-8-sig"))
        local_url(config["url"])
        if config.get('conversation',False):
            from .conversation import RasaConversation
            speech_root=Path(__file__).resolve().parents[3]/'tools/speech'
            final_model=speech_root/'whisper-small.en'
            preview_model=speech_root/'whisper-base.en'
            if not (final_model/'model.bin').is_file():
                raise ValueError('Install the local small.en model for conversation mode.')
            from .offline_reply import OfflineReply
            recognizer=OfflineRecognizer(args.model,parser=RasaParser(args.rasa_url),dialogue=RasaConversation(args.rasa_url),final_model=final_model,preview_model=preview_model,responder=OfflineReply())
        else:
            recognizer = OfflineRecognizer(args.model)
    except Exception:
        raise SystemExit("Speech controls could not initialize. Check the local model and speech session configuration.")
    factory = MicrophoneCapture
    if args.test_fixture:
        class FixtureCapture:
            full = False
            def __init__(self, _device): pass
            def open(self): pass
            def discard(self): pass
            def take(self):
                path=args.test_fixture.parent / "story.wav" if getattr(self,"reply_mode",False) else args.test_fixture
                with wave.open(str(path)) as audio:
                    if audio.getframerate()!=SAMPLE_RATE or audio.getnchannels()!=1 or audio.getsampwidth()!=2:
                        raise ValueError("Test fixture must be mono 16 kHz PCM16.")
                    return audio.readframes(SAMPLE_RATE * 8)
        factory = FixtureCapture
        print("SYNTHETIC SPEECH TEST INPUT. No microphone is opened.", flush=True)
    elif config.get('conversation',False):
        print('PLANNED CONVERSATION. Microphone opens after a ready question and closes before decoding. No audio/transcript files are written.',flush=True)
    else:
        print("OFFLINE PUSH-TO-TALK CONTROLS. Hold V in the game. Microphone stays closed while idle. No audio/transcript files are written.", flush=True)
    automatic_factory=AutomaticCapture
    if args.test_fixture:
        fixture_count=[0]
        class AutomaticFixture(AutomaticCapture):
            @property
            def done(self):
                return self._done and time.monotonic()>=getattr(self,'ready_at',0.)

            @done.setter
            def done(self,value):
                self._done=value

            def open(self):
                # Actual WebRTC endpointing on a public synthetic WAV; no device.
                sequence=['story','privacy','wait','repeat','dislike_books'] if args.conversation_test_branches else ['story']
                key=sequence[min(fixture_count[0],len(sequence)-1)]
                fixture_count[0]+=1
                path=args.test_fixture.parent/(key+'.wav')
                with wave.open(str(path)) as audio:
                    pcm=audio.readframes(SAMPLE_RATE*30)
                self.turn.feed(pcm+bytes(SAMPLE_RATE*2*2))
                if self.preview_enabled:
                    self.preview_buffer.extend(pcm)
                self.done=self.turn.state=='complete'
                self.ready_at=time.monotonic()+.8
                self.full=self.turn.state!='complete'
        automatic_factory=AutomaticFixture
    worker = SpeechWorker(config, recognizer, capture_factory=factory, device=args.device,automatic_factory=automatic_factory)
    worker.synthetic_diagnostics=bool(args.test_fixture)
    try:
        while worker.step():
            time.sleep(0.05)
    except KeyboardInterrupt:
        pass
    finally:
        worker.discard()
        if getattr(recognizer,'responder',None):recognizer.responder.close()
        if worker.caption_pool:
            worker.caption_pool.shutdown(wait=False,cancel_futures=True)


if __name__ == "__main__":
    main()
