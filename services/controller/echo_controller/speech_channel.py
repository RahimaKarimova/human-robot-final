"""Capture-bound speech controls and transient, session-only live captions."""
import os
import secrets
import sys
import time

DEBUG = os.environ.get("ECHO_ROBOT_DEBUG") == "1"


def debug(message):
    if DEBUG:  # Opt-in bench diagnostics: statuses and reasons only, never speech text.
        print(f"[speech {time.strftime('%H:%M:%S')}] {message}", file=sys.stderr, flush=True)

from .core import ProtocolError
from .request_routing import route_request


class SpeechChannel:
    def __init__(self, clock=time.monotonic):
        self.clock = clock
        self.token = secrets.token_urlsafe(32)
        self.worker_id = ""
        self.last_seen = None
        self.job = None
        self.auto_after = 0.
        self.repairs = {}
        self.meter = None
        self.caption = None

    def update_caption(self,session,capture_id,text,revision,final):
        if (not session.conversation_enabled or not self.job or self.job['capture_id']!=capture_id
                or self.job['phase'] not in {'listen','finish','processing'} or session.paused
                or session.context()['context_id']!=self.job['context_id']):
            return
        if self.caption and revision<=self.caption['revision']:
            return
        self.caption=dict(capture_id=capture_id,text=' '.join(text.split())[:4000],revision=revision,final=final,at=self.clock())
        if final and session.transcript:
            session.transcript.person(capture_id, self.caption['text'])

    def caption_state(self,session):
        if not self.caption or session.stopped or self.clock()-self.caption['at']>15:
            return {}
        return {key:self.caption[key] for key in ('capture_id','text','revision','final')}

    def update_meter(self,capture_id,level,sequence):
        if not self.job or self.job['capture_id']!=capture_id or self.job['phase']!='listen':
            return
        if self.meter and sequence<=self.meter['sequence']:
            return
        self.meter=dict(capture_id=capture_id,level=level,sequence=sequence,at=self.clock())

    def meter_state(self):
        live=bool(self.job and self.job['phase']=='listen' and self.meter
                  and self.meter['capture_id']==self.job['capture_id'] and self.clock()-self.meter['at']<.6)
        return {'capture_id':self.job['capture_id'] if self.job else '',
                'level':self.meter['level'] if live else 0.,'sequence':self.meter['sequence'] if live else 0,'live':live}

    def status(self, session, capture_id, status):
        debug(f"status {status} purpose={self.job and self.job.get('purpose')} phase={self.job and self.job.get('phase')}")
        if not session.stopped:
            session.command("VOICE_CONTROL_STATUS", capture_id=capture_id, status=status,
                            automatic=bool(self.job and self.job.get("automatic")))

    def start(self, session, capture_id, purpose="control", automatic=False):
        if self.job or session.audio_active or session.delivery or session.stopped or not session.started:
            self.status(session, capture_id, "UNAVAILABLE")
            return
        context=session.context()
        if purpose == "reply" and (not context["question"] or context["view"] != "checkpoint" or session.paused):
            self.status(session, capture_id, "UNAVAILABLE")
            return
        self.job = dict(capture_id=capture_id, context_id=context["context_id"], purpose=purpose, phase="listen", started=self.clock(),automatic=automatic,
                        signature=session.context_signature)
        debug(f"start purpose={purpose} automatic={automatic}")
        self.meter=None
        self.caption=None
        self.status(session, capture_id, "STARTING")

    def release(self, capture_id, cancel=False):
        if self.job and self.job["capture_id"] == capture_id:
            if self.job["phase"] == "cancel":
                return
            if cancel:
                self.job["phase"] = "cancel"
            elif self.job["phase"] == "listen":
                self.job["phase"] = "finish"

    def cancel(self):
        self.meter=None
        self.caption=None
        if self.job:
            self.job["phase"] = "cancel"

    def expire(self, session):
        if not self.job:
            return
        now = self.clock()
        lease=(200 if self.job.get("purpose")=="reply" and not self.job.get("automatic") else 30) if self.job["phase"] == "processing" else 2
        reply=self.job.get('purpose')=='reply' and not self.job.get('automatic')
        maximum=(200 if reply else 30) if self.job['phase']=='processing' else 200 if reply else 55 if self.job.get('automatic') else 20
        started=self.job.get('processing_at',self.job['started']) if self.job['phase']=='processing' else self.job['started']
        if now - started > maximum or (self.last_seen is not None and now - self.last_seen > lease) or (self.last_seen is None and now - self.job["started"] > 4):
            debug(f"expired: phase={self.job['phase']} age={now-started:.1f}s last_seen_gap="
                  f"{(now-self.last_seen) if self.last_seen is not None else None}")
            self.status(session, self.job["capture_id"], "UNAVAILABLE")
            self.job = None
            self.meter=None
            session.drain()

    def poll(self, session, worker_id):
        if self.worker_id and self.worker_id != worker_id:
            raise ProtocolError("A speech worker already owns this session.")
        self.worker_id, self.last_seen = worker_id, self.clock()
        self.expire(session)
        if self.job and (session.stopped or (session.audio_active and self.job["phase"] == "listen")
                         or session.context()["context_id"] != self.job["context_id"]):
            if self.job["phase"] != "cancel":
                debug(f"cancel: stopped={session.stopped} audio_active={session.audio_active} "
                      f"context now={session.context_signature} at_start={self.job.get('signature')}")
            self.cancel()
        now=self.clock()
        game_alive=session.last_game_poll is not None and 0<=now-session.last_game_poll<2
        if self.job and self.job.get("automatic") and (session.paused or not game_alive):
            self.cancel()
        context=session.context()
        if (session.conversation_enabled and not session.push_to_talk and not self.job and not session.stopped and session.started
                and not session.paused and not session.audio_active and not session.delivery
                and not (session.robot and session.robot.job) and game_alive and now>=self.auto_after
                and context["question"] and context["view"]=="checkpoint"):
            self.start(session,secrets.token_hex(12),'reply',automatic=True)
        return {"stopped": session.stopped, "job": None if not self.job else
                {**{key:self.job[key] for key in ("capture_id", "phase", "purpose")},"automatic":self.job.get("automatic",False),
                 'question_id':session.context()['line_id']}}

    def finish(self, session, body):
        if not self.job or body["capture_id"] != self.job["capture_id"]:
            return
        job, self.job = self.job, None
        self.meter=None
        self.auto_after=self.clock()+1.
        if session.stopped:
            return
        if job["phase"] == "cancel":
            self.caption=None
            self.status(session, body["capture_id"], "CANCELLED")
        elif (job.get('automatic') and body['intent']=='UNKNOWN' and body['source']=='unrecognized'
              and not body.get('speech_detected',False)):
            self.status(session,body['capture_id'],'IDLE')  # Silence is not an answer or an error.
        elif job["phase"] not in {"finish", "processing"}:
            self.status(session, body["capture_id"], "NO_COMMAND")
        elif (job.get('automatic') and body['intent']=='UNKNOWN' and body['source']=='unrecognized'
              and body.get('speech_detected',False)):
            context=session.context()
            key=(context['checkpoint_id'],context['line_id'])
            if (context['context_id']==job['context_id'] and context['question'] and context['view']=='checkpoint'
                    and not session.paused and not self.repairs.get(key)):
                self.repairs[key]=True
                session.command('COMPANION_CHECKPOINT_ACTION',checkpoint_id=key[0],line_id=key[1],action='repeat',request_id='speech-'+body['capture_id'])
            elif (context['context_id']==job['context_id'] and context['question'] and context['view']=='checkpoint'
                  and not session.paused and not session.delivery):
                from .preview import conversation_notice
                session.deliver('COMPANION_CUE',context['stage_id'],checkpoint_id=key[0],line_id=key[1],
                                conversation_notice=True,**conversation_notice('REPAIR'))
            self.status(session,body['capture_id'],'NO_COMMAND')
        elif (not job.get('automatic') and job['purpose']=='reply' and body['intent']=='UNKNOWN'
              and body['source'] in {'unrecognized','unavailable'}):
            # Held-B answer with nothing recognized (too quiet, noise, released too
            # early): Reachy says its default "didn't quite catch that" line so the
            # player knows to try again. Silence still never counts as an answer.
            context=session.context()
            if (context['context_id']==job['context_id'] and context['question'] and context['view']=='checkpoint'
                    and not session.paused and not session.delivery):
                from .preview import conversation_notice
                session.deliver('COMPANION_CUE',context['stage_id'],checkpoint_id=context['checkpoint_id'],
                                line_id=context['line_id'],conversation_notice=True,**conversation_notice('REPAIR'))
            self.status(session,body['capture_id'],'NO_COMMAND')
        elif body["intent"] == "REPLY":
            context=session.context()
            allowed=job["purpose"] == "reply" and body["source"] == "reply" and body["confidence"] >= 0.9 and context["context_id"] == job["context_id"] and context["question"] and context["view"] == "checkpoint" and not session.paused and not session.delivery
            if allowed:
                from .reply_understanding import REPLIES
                kind=body.get('reply_kind','DEFAULT')
                reply_text=body.get('reply_text','').strip()
                if reply_text and len(reply_text)<=220 and '\n' not in reply_text and context['line_id'] in {'G1','G2','G3','P1','P2','P3'}:
                    session.reply_texts[context['line_id']]=reply_text
                if kind in REPLIES and context['line_id'] in REPLIES[kind]['questions']:
                    session.reply_kinds[context['line_id']]=kind
                if context['line_id']=='NAME' and body.get('nickname'):
                    from .reply_understanding import extract_nickname
                    session.nickname=extract_nickname(body['nickname'])
                session.command("COMPANION_CHECKPOINT_ACTION",checkpoint_id=context["checkpoint_id"],line_id=context["line_id"],action="ack",request_id="speech-"+body["capture_id"])
            self.status(session,body["capture_id"],"SENT" if allowed else "NO_COMMAND")
        else:
            result = route_request(session, {"session_id":session.session_id, "request_id":"speech-" + body["capture_id"],
                "context_id":job["context_id"], "intent":body["intent"], "confidence":body["confidence"], "source":body["source"]})
            self.status(session, body["capture_id"], "SENT" if result["status"] == "applied" else "NO_COMMAND")
        session.drain()
