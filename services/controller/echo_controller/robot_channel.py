"""Single-worker, output-only bridge. Monotonic leases never imply spoken completion."""
import secrets
import time

from .core import ProtocolError


class RobotChannel:
    def __init__(self, mode, clock=time.monotonic):
        self.mode, self.clock = mode, clock
        self.token = secrets.token_urlsafe(32)
        self.worker_id = ""
        self.worker_seen = self.game_seen = None
        self.job = None

    def offer(self, command):
        if self.job is not None:
            raise ProtocolError("Previous robot output has not stopped.")
        self.job = {**command, "ready": False, "cancel": False, "finished": False, "offered_at": self.clock()}

    def cancel(self):
        if self.job:
            self.job["cancel"] = True

    def finish(self, session, utterance_id, completion):
        job = self.job
        if not job or job["utterance_id"] != utterance_id or job["finished"]:
            return  # Late/duplicate completion cannot advance a new turn.
        if completion == "audio_completed" and self.mode not in {"reachy_lite", "reachy_wireless"}:
            raise ProtocolError("Simulator cannot attest physical playback.")
        if completion == "simulated_completed" and self.mode not in {"bridge_simulator", "reachy_mujoco", "reachy_control_simulator"}:
            raise ProtocolError("Hardware cannot report simulated completion.")
        if completion in {"audio_completed", "simulated_completed"} and (not job["ready"] or job["cancel"]):
            raise ProtocolError("Output is not eligible for natural completion.")
        job["finished"] = True
        if session.delivery.get("utterance_id") == utterance_id:
            if completion == "cancelled" and job["cancel"]:
                # A fast UI bypass can precede SHOW_DIALOGUE. In that case the
                # game never adopted this utterance and cannot acknowledge its
                # result. The owning worker has now confirmed output stopped.
                session.delivery.clear()
            else:
                session.delivery["robot_completion"] = completion
        if not session.stopped:
            session.command("COMPANION_OUTPUT_RESULT", checkpoint_id=job.get("checkpoint_id", ""),
                            stage_id=job["stage_id"], utterance_id=utterance_id, completion=completion)
        self.job = None

    def expire(self, session):
        if not self.job:
            return
        now = self.clock()
        if self.worker_seen is None:
            timed_out = now - self.job["offered_at"] > 4
        else:
            timed_out = now - self.worker_seen > 2
        if self.game_seen is not None and now - self.game_seen > 2:
            self.cancel()  # Worker must stop output before returning a cancellation.
        if timed_out:
            self.finish(session, self.job["utterance_id"], "technical_failure")

    def poll(self, session, worker_id):
        if self.worker_id and self.worker_id != worker_id:
            raise ProtocolError("A worker already owns this session. Start a fresh session.")
        self.worker_id, self.worker_seen = worker_id, self.clock()
        self.expire(session)
        job = self.job
        state = "stopped" if session.stopped else "idle"
        result = {"state": state, "mode": self.mode, "job": None}
        result["idle_allowed"] = bool(not job and not session.stopped and not session.paused and not session.audio_active
                                      and self.game_seen is not None and self.clock()-self.game_seen < 2)
        result["idle_motion"] = "LISTEN" if session.context()["question"] else "IDLE"
        if job:
            result["state"] = "cancel" if session.stopped or job["cancel"] else "pause" if session.paused or session.audio_active else "play"
            if job["ready"] or result["state"] == "cancel":
                result["job"] = {key: job[key] for key in ("utterance_id", "audio_id", "motion_id", "stage_id")}
                if job.get('speech_text'):
                    result['job']['speech_text']=job['speech_text']
                if job.get('generated_reply'):result['job']['generated_reply']=True
        return result
