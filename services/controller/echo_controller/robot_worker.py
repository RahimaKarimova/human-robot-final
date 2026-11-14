"""Poll a session-owned output job. Never consumes answers or microphone audio."""
import argparse
import json
import time
import uuid
from pathlib import Path
from urllib.request import Request, ProxyHandler, build_opener

from .companion_gateway import local_url, NoRedirect
from .robot_output import SimulatedOutput, ReachyLiteOutput, ReachyWirelessOutput, ReachyMujocoOutput, ReachyControlSimulatorOutput, clip, MOTIONS


class Worker:
    def __init__(self, config, output, exchange=None, clock=time.monotonic):
        self.config, self.output = config, output
        self.worker_id = uuid.uuid4().hex
        self.active = None
        self.seen = set()
        self.pending_result = None
        self.exchange = exchange or self._exchange
        self.clock = clock
        self.play_elapsed = 0.0
        self.last_tick = clock()
        self.was_playing = False

    def cancel_output(self):
        try:
            self.output.cancel()
            return True
        except Exception:
            return False

    def _exchange(self, route, payload):
        data = {"session_id": self.config["session_id"], "worker_id": self.worker_id, **payload}
        request = Request(local_url(self.config["url"]) + route, data=json.dumps(data).encode(),
                          headers={"Content-Type": "application/json", "X-Echo-Robot-Token": self.config["robot_token"]})
        with build_opener(ProxyHandler({}), NoRedirect()).open(request, timeout=0.8) as response:
            raw = response.read(65537)
        if len(raw) > 65536:
            raise ValueError("Bridge response limit exceeded.")
        return json.loads(raw)

    def finish(self, completion):
        if self.active:
            self.pending_result = {"utterance_id": self.active["utterance_id"], "completion": completion}
            self.active = None
            if not self.cancel_output():
                self.pending_result["completion"] = "technical_failure"

    def step(self):
        try:
            if self.pending_result:
                self.exchange("/robot/result", self.pending_result)
                self.pending_result = None
            state = self.exchange("/robot/poll", {})
            if state["mode"] != self.config["output"]:
                raise ValueError("Output mode does not match session.")
            job = state.get("job")
            if self.active and (not job or job["utterance_id"] != self.active["utterance_id"] or state["state"] in {"cancel", "stopped"}):
                self.finish("cancelled")
            if job and state["state"] == "cancel" and not self.active:
                if self.pending_result is None:
                    self.pending_result = {"utterance_id": job["utterance_id"], "completion": "cancelled"}
            elif job and state["state"] == "play" and not self.active and not self.pending_result:
                if job["utterance_id"] not in self.seen:
                    self.seen.add(job["utterance_id"])
                    self.active = job
                    _, audio_duration = clip(job["audio_id"])
                    self.play_budget = max(audio_duration, MOTIONS[job["motion_id"]][2]) + 5.0
                    self.play_elapsed, self.last_tick, self.was_playing = 0.0, self.clock(), False
                    self.output.start(job)
                else:
                    self.pending_result = {"utterance_id": job["utterance_id"], "completion": "technical_failure"}
            if self.active:
                now = self.clock()
                playing = state["state"] == "play"
                if playing and self.was_playing:
                    self.play_elapsed += max(0.0, now - self.last_tick)
                self.last_tick, self.was_playing = now, playing
                if getattr(self.output,'preparing',False):
                    self.play_elapsed=0.
                    self.was_playing=False
                    if self.play_budget<20.: self.play_budget=20.
                elif hasattr(self.output,'voice_duration'):
                    self.play_budget=max(self.output.voice_duration,MOTIONS[self.active['motion_id']][2])+5.
                if getattr(self.output,'streaming_reply',False) and not getattr(self.output,'stream_done',False):
                    self.play_budget=max(self.play_budget,50.)
                self.output.set_paused(state["state"] == "pause")
                if self.output.tick():
                    self.finish(self.output.completion)
                elif playing and self.play_elapsed > self.play_budget:
                    self.finish("technical_failure")  # Timeout is failure, never proof of speech.
            if not self.active and not self.pending_result:
                idle = getattr(self.output, "idle_tick", None)
                if idle:
                    idle(state.get("idle_motion", "IDLE") if state.get("idle_allowed", False) else None)
            return state["state"] != "stopped" or self.pending_result is not None
        except Exception:
            # On a controller or device failure, stop locally before reconnecting.
            self.finish("technical_failure")
            self.cancel_output()
            idle = getattr(self.output, "idle_tick", None)
            if idle:
                idle(None)
            return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--speaker-name")
    parser.add_argument("--gestures", action="store_true")
    parser.add_argument("--simulator-speed", type=float, default=1.0)
    parser.add_argument("--simulator-port",type=int,default=8000)
    parser.add_argument("--mute-simulator-audio",action="store_true")
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding="utf-8-sig"))
    local_url(config["url"])
    if config["output"] == "bridge_simulator":
        if not 0.25 <= args.simulator_speed <= 8:
            parser.error("Simulator speed must be between 0.25 and 8.")
        output = SimulatedOutput(speed=args.simulator_speed)
        print("SILENT ROBOT BRIDGE SIMULATOR. No SDK, devices or physical playback.", flush=True)
    elif config["output"] == "reachy_lite":
        try:
            output = ReachyLiteOutput(args.speaker_name, args.gestures)
        except Exception:
            raise SystemExit("Robot output could not start. Check the SDK, Lite daemon and exact USB speaker name. No fallback was selected.")
    elif config["output"] == "reachy_wireless":
        try:
            output = ReachyWirelessOutput(args.gestures)
        except Exception:
            raise SystemExit("Wireless output could not start. Run this worker on the robot with the matching SDK, local daemon and configured ALSA speaker. No fallback was selected.")
    elif config["output"] == "reachy_mujoco":
        try:
            output = ReachyMujocoOutput(args.simulator_port,args.mute_simulator_audio)
        except Exception:
            raise SystemExit("Official MuJoCo output could not start. Start the SDK daemon with --sim; physical and mockup daemons are refused.")
    elif config["output"] == "reachy_control_simulator":
        try:
            output = ReachyControlSimulatorOutput(args.simulator_port, args.mute_simulator_audio)
        except Exception:
            raise SystemExit("Control app simulator could not connect. Start its local mock simulator first. Physical daemons are refused.")
    else:
        raise SystemExit("Unsupported output mode.")
    worker = Worker(config, output)
    try:
        while worker.step():
            time.sleep(0.05)
    except KeyboardInterrupt:
        pass
    finally:
        output.close()


if __name__ == "__main__":
    main()
