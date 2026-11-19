"""Output-only devices, fixed clips and bounded in-memory nickname speech."""
import json
import math
from pathlib import Path
import threading
import time
import sys
import wave
from .robot_expression import voice_rhythm, rhythm_at, expression_pose, approach, rhythm_pcm

ROOT = Path(__file__).resolve().parents[3]
MANIFEST = json.loads((ROOT / "assets/audio/manifest.json").read_text(encoding="utf-8-sig"))
MOTIONS = {"WAVE": (8, -8, 2.0), "NOD": (5, 5, 1.2), "LISTEN": (0, 0, 0.4),
           "POINT": (0, 7, 1.2), "CELEBRATE": (9, 9, 2.4)}


def clip(audio_id):
    if not isinstance(audio_id, str) or not audio_id.startswith("companion_") or audio_id not in MANIFEST:
        raise ValueError("Unknown fixed companion clip.")
    path = (ROOT / MANIFEST[audio_id]["path"].removeprefix("res://")).resolve()
    if not path.is_relative_to((ROOT / "assets/audio/companion").resolve()):
        raise ValueError("Clip is outside the companion asset directory.")
    with wave.open(str(path)) as audio:
        if audio.getsampwidth() != 2 or audio.getnchannels() != 1 or audio.getnframes() <= 0:
            raise ValueError("Unsupported companion audio format.")
        duration = audio.getnframes() / audio.getframerate()
    return path, duration


def antenna_target(motion, elapsed, baseline):
    """Small, smooth deviations from the measured starting pose; no head/body moves."""
    right, left, duration = MOTIONS[motion]
    phase = min(1.0, max(0.0, elapsed / duration))
    envelope = math.sin(math.pi * phase) ** 2
    wave_value = math.sin(phase * math.tau * (2 if motion in {"WAVE", "CELEBRATE"} else 1))
    return [baseline[0] + math.radians(right) * envelope * wave_value,
            baseline[1] + math.radians(left) * envelope * wave_value]


class SimulatedOutput:
    """Silent software fake. Completion is explicitly simulated, never physical audio."""
    completion = "simulated_completed"

    def __init__(self, clock=time.monotonic, speed=1.0):
        self.clock, self.speed = clock, speed
        self.running = False
        self.paused = False
        self.elapsed = 0.0
        self.last = clock()
        self.last_target = [0.0, 0.0]

    def start(self, job):
        _, duration = clip(job["audio_id"])
        self.motion = job["motion_id"]
        self.duration = max(duration, MOTIONS[self.motion][2])
        self.elapsed, self.last = 0.0, self.clock()
        self.running, self.paused = True, False

    def set_paused(self, paused):
        self.tick()
        self.paused = paused

    def tick(self):
        now = self.clock()
        if self.running and not self.paused:
            self.elapsed += max(0, now - self.last) * self.speed
            self.last_target = antenna_target(self.motion, self.elapsed, [0, 0])
        self.last = now
        return self.running and not self.paused and self.elapsed >= self.duration

    def cancel(self):
        self.running = False

    def close(self):
        self.cancel()


class ReachyLiteOutput:
    """Prepared SDK + GStreamer output-only implementation; physical verification pending.

    Explicit USB speaker selection is mandatory. There is no default-speaker fallback.
    SDK imports are lazy, so simulator/offline play never needs this dependency.
    """
    completion = "audio_completed"
    daemon_port = 8000
    # 1.12.0: project-local SDK/daemon. 1.14.0: the Reachy Mini Control app's
    # daemon, so the app can stay open while the game drives the robot.
    supported_sdk_versions = {"1.12.0", "1.14.0"}
    expressive_simulation = False

    def __init__(self, speaker_name, gestures=False):
        self._validate_speaker(speaker_name)
        from importlib.metadata import version
        if version("reachy-mini") not in self.supported_sdk_versions:
            raise RuntimeError("Unsupported Reachy Mini SDK version. Verify daemon compatibility first.")
        from reachy_mini import ReachyMini
        self.mini = ReachyMini(connection_mode="localhost_only", spawn_daemon=False,
                              port=self.daemon_port, media_backend="no_media", timeout=2.0, log_level="ERROR", automatic_body_yaw=False)
        self.pipeline = None
        self.tts_future=None
        self.tts_pool=None
        self.name_voice=None
        self.reply_voice=None
        self.streaming_reply=False
        self.preparing=False
        self.gestures = gestures
        self.paused = False
        self.elapsed = 0.0
        self.last = time.monotonic()
        try:
            # Import after the SDK initializes its bundled GStreamer environment.
            import gi
            gi.require_version("Gst", "1.0")
            from gi.repository import Gst
            self.Gst = Gst
            Gst.init(None)
            self._select_device(speaker_name)
            if MANIFEST.get('companion_welcome',{}).get('voice','').startswith('qwen3-tts-'):
                from .cpu_name_voice import CpuNameVoice
                try:self.name_voice=CpuNameVoice()
                except Exception:self.name_voice=None
                from .cpu_reply_voice import CpuReplyVoice
                try:self.reply_voice=CpuReplyVoice()
                except Exception:self.reply_voice=None
        except Exception:
            self.close()
            raise

    def _validate_speaker(self, speaker_name):
        if not speaker_name or not any(word in speaker_name.casefold() for word in ("reachy", "respeaker")):
            raise ValueError("Select the exact Reachy/ReSpeaker output device name.")
        self._check_physical_daemon()

    def _check_physical_daemon(self):
        """Require a running physical daemon whose version matches this worker's SDK."""
        from importlib.metadata import version
        from urllib.request import build_opener, ProxyHandler
        from .companion_gateway import NoRedirect
        with build_opener(ProxyHandler({}), NoRedirect()).open(
                f"http://127.0.0.1:{self.daemon_port}/api/daemon/status", timeout=2) as response:
            raw = response.read(65537)
        if len(raw) > 65536:
            raise RuntimeError("Daemon status response exceeded limit.")
        status = json.loads(raw)
        if status.get("state") != "running":
            raise RuntimeError("The Reachy daemon is not running.")
        if status.get("simulation_enabled") is True or status.get("mockup_sim_enabled") is True:
            raise RuntimeError("A physical Lite daemon is required; simulation daemons are refused.")
        if status.get("version") != version("reachy-mini"):
            raise RuntimeError("Daemon and worker SDK versions must match.")

    def _select_device(self, speaker_name):
        monitor = self.Gst.DeviceMonitor.new()
        monitor.add_filter("Audio/Sink", None)
        if not monitor.start():
            raise RuntimeError("Audio output discovery is unavailable.")
        try:
            matches = [device for device in monitor.get_devices() if device.get_display_name() == speaker_name]
            if len(matches) != 1:
                raise RuntimeError("Select exactly one available Reachy output device.")
            self.device = matches[0]
        finally:
            monitor.stop()

    def _make_sink(self):
        return self.device.create_element("robot_speaker")

    def start(self, job):
        self.cancel()
        path, self.voice_duration = clip(job["audio_id"])
        self.motion = job["motion_id"]
        self.elapsed, self.last = 0.0, time.monotonic()
        self.audio_done, self.paused = False, False
        if self.expressive_simulation:
            self.rhythm = voice_rhythm(str(path))
            self.expression_duration = max(self.voice_duration, MOTIONS[self.motion][2])
        if self.gestures:
            self.baseline = list(self.mini.get_present_antenna_joint_positions())
            if len(self.baseline) != 2 or not all(math.isfinite(x) for x in self.baseline):
                raise RuntimeError("Antenna pose is unavailable.")
        if job.get('generated_reply'):
            if not self.reply_voice:raise RuntimeError('CPU personalized voice is unavailable.')
            self.reply_voice.start(job['speech_text'])
            self.streaming_reply=True;self.stream_pcm=bytearray();self.stream_source=None
            self.stream_done=False;self.stream_started=time.monotonic();self.preparing=True
            return
        if job.get('speech_text'):
            from concurrent.futures import ThreadPoolExecutor
            from .local_voice import synthesise_memory
            from .local_voice import recorded_with_name
            if self.tts_pool is None:
                self.tts_pool=ThreadPoolExecutor(max_workers=1)
            if MANIFEST[job['audio_id']].get('voice','').startswith('qwen3-tts-'):
                self.tts_future=self.tts_pool.submit(recorded_with_name,job['speech_text'],job['audio_id'],self.name_voice)
            else:
                self.tts_future=self.tts_pool.submit(synthesise_memory,job['speech_text'],job['audio_id'])
            self.preparing=True
            return
        Gst = self.Gst
        self.pipeline = Gst.Pipeline.new("echo_companion_output")
        source = Gst.ElementFactory.make("filesrc", "source")
        parser = Gst.ElementFactory.make("wavparse", "parser")
        convert = Gst.ElementFactory.make("audioconvert", "convert")
        resample = Gst.ElementFactory.make("audioresample", "resample")
        sink = self._make_sink()
        elements = [source, parser, convert, resample, sink]
        if getattr(self,"mute_audio",False):
            volume=Gst.ElementFactory.make("volume","simulation_test_mute")
            if volume is None:
                raise RuntimeError("Test muting element is unavailable.")
            volume.set_property("volume",0.0)
            elements.insert(-1,volume)
        if any(element is None for element in elements):
            raise RuntimeError("Required audio output elements are missing.")
        source.set_property("location", str(path))
        for element in elements:
            self.pipeline.add(element)
        for first, second in zip(elements, elements[1:]):
            if not first.link(second):
                raise RuntimeError("Could not link robot audio output.")
        if self.pipeline.set_state(Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE:
            raise RuntimeError("Robot speaker could not start.")

    def set_paused(self, paused):
        if self.paused == paused:
            return
        if paused and getattr(self,'preparing',False):
            self.paused=True
            self.last=time.monotonic()
            return
        self.tick()
        self.paused = paused
        self.last = time.monotonic()
        if self.pipeline:
            state = self.Gst.State.PAUSED if paused else self.Gst.State.PLAYING
            if self.pipeline.set_state(state) == self.Gst.StateChangeReturn.FAILURE:
                raise RuntimeError("Robot audio pause/resume failed.")

    def tick(self):
        if getattr(self,'streaming_reply',False) and not self.paused:
            if not self.stream_done:
                for _ in range(8):
                    item=self.reply_voice.poll()
                    if item is None:break
                    kind,pcm,rate=item
                    if kind=='done':
                        self.stream_done=True
                        if self.pipeline is None:
                            if not self.stream_pcm:raise RuntimeError('CPU voice returned empty audio.')
                            self.preparing=False
                            self._start_pcm(bytes(self.stream_pcm),rate,streaming=True)
                        if self.stream_source:self.stream_source.emit('end-of-stream')
                        break
                    self.stream_pcm.extend(pcm)
                    if self.pipeline is None:
                        # Start with a short buffer, rather than waiting for all speech.
                        if len(self.stream_pcm)<rate*2*.24:continue
                        self.preparing=False
                        self._start_pcm(bytes(self.stream_pcm),rate,streaming=True)
                    else:self._push_pcm(pcm,rate)
                    self.voice_duration=len(self.stream_pcm)/(rate*2)
                    if self.expressive_simulation:
                        self.rhythm=rhythm_pcm(bytes(self.stream_pcm),rate)
                        self.expression_duration=max(self.voice_duration+.3,MOTIONS[self.motion][2])
            if self.pipeline is None and time.monotonic()-self.stream_started>15:
                raise RuntimeError('CPU voice produced no playable audio.')
            if not self.stream_done and time.monotonic()-self.stream_started>45:
                raise RuntimeError('CPU voice generation exceeded its bound.')
        future=getattr(self,'tts_future',None)
        if future is not None:
            if self.paused or not future.done():
                return False
            pcm,rate=future.result()
            self.tts_future=None
            self.preparing=False
            self._start_pcm(pcm,rate)
        if self.pipeline is None:
            return False
        now = time.monotonic()
        if not self.paused:
            self.elapsed += max(0, now - self.last)
        self.last = now
        message = self.pipeline.get_bus().pop_filtered(self.Gst.MessageType.ERROR | self.Gst.MessageType.EOS)
        if message:
            if message.type == self.Gst.MessageType.ERROR:
                raise RuntimeError("Robot speaker playback failed.")
            self.audio_done = True  # Actual end-of-stream, not estimated clip length.
        if self.gestures and not self.paused:
            if self.expressive_simulation:
                self._animate(self.motion, self.elapsed, self.expression_duration, rhythm_at(self.rhythm, self.elapsed))
            else:
                target = antenna_target(self.motion, self.elapsed, self.baseline)
                self.mini.set_target_antenna_joint_positions(target)
        return not self.paused and self.audio_done and (not self.gestures or self.elapsed >= MOTIONS[self.motion][2])

    def cancel(self):
        self.streaming_reply=False
        self.stream_pcm=bytearray()
        future=getattr(self,'tts_future',None)
        if future is not None:
            future.cancel()
        self.tts_future=None
        self.preparing=False
        if self.pipeline is not None:
            pipeline,self.pipeline = self.pipeline,None
            pipeline.set_state(self.Gst.State.NULL)
        # No new movement commands. Never disable gravity support or issue a sleep pose.

    def close(self):
        self.cancel()
        if getattr(self,'name_voice',None):
            self.name_voice.close();self.name_voice=None
        if getattr(self,'reply_voice',None):
            self.reply_voice.close();self.reply_voice=None
        if getattr(self,'tts_pool',None) is not None:
            self.tts_pool.shutdown(wait=False,cancel_futures=True)
            self.tts_pool=None
        if getattr(self, "mini", None) is not None:
            self.mini.__exit__(None, None, None)
            self.mini = None

    def _start_pcm(self,pcm,rate,streaming=False):
        Gst=self.Gst
        self.voice_duration=len(pcm)/(rate*2)
        self.elapsed,self.last=0.,time.monotonic()
        if self.expressive_simulation:
            self.rhythm=rhythm_pcm(pcm,rate)
            self.expression_duration=max(self.voice_duration,MOTIONS[self.motion][2])
        self.pipeline=Gst.Pipeline.new('echo_personalised_output')
        source=Gst.ElementFactory.make('appsrc','memory_voice')
        source.set_property('caps',Gst.Caps.from_string(f'audio/x-raw,format=S16LE,layout=interleaved,channels=1,rate={rate}'))
        source.set_property('format',Gst.Format.TIME)
        elements=[source,Gst.ElementFactory.make('audioconvert','convert'),Gst.ElementFactory.make('audioresample','resample')]
        if getattr(self,'mute_audio',False):
            volume=Gst.ElementFactory.make('volume','test_mute')
            volume.set_property('volume',0.)
            elements.append(volume)
        elements.append(self._make_sink())
        for element in elements: self.pipeline.add(element)
        for first,second in zip(elements,elements[1:]):
            if not first.link(second): raise RuntimeError('Personalised audio pipeline could not link.')
        self.stream_source=source;self.pcm_frames=0
        self._push_pcm(pcm,rate)
        if not streaming:source.emit('end-of-stream')
        if self.pipeline.set_state(Gst.State.PLAYING)==Gst.StateChangeReturn.FAILURE:
            raise RuntimeError('Personalised audio could not start.')

    def _push_pcm(self,pcm,rate):
        buffer=self.Gst.Buffer.new_allocate(None,len(pcm),None)
        buffer.fill(0,pcm)
        buffer.pts=buffer.dts=int(self.pcm_frames/rate*self.Gst.SECOND)
        buffer.duration=int(len(pcm)/(rate*2)*self.Gst.SECOND)
        self.pcm_frames+=len(pcm)//2
        self.stream_source.emit('push-buffer',buffer)

    def idle_tick(self, motion):
        pass  # Physical idle/head movement needs device calibration first.


class ReachyWirelessOutput(ReachyLiteOutput):
    """Run on the Wireless robot itself; control travels through an SSH reverse tunnel.

    Uses the robot's explicit ALSA speaker and real local EOS. It never plays
    through a Windows default device or mistakes WebRTC enqueueing for completion.
    """
    def __init__(self, gestures=False):
        super().__init__("reachymini_audio_sink", gestures)

    def _validate_speaker(self, _speaker_name):
        if sys.platform != "linux":
            raise RuntimeError("Wireless output worker must run on the robot's Linux host.")
        configs = [Path.home() / ".asoundrc", Path("/etc/asound.conf")]
        if not any(path.is_file() and "reachymini_audio_sink" in path.read_text(errors="replace") for path in configs):
            raise RuntimeError("The robot's reachymini_audio_sink ALSA alias is not configured.")

    def _select_device(self, _speaker_name):
        pass  # Hardware is selected by the explicit ALSA alias in _make_sink.

    def _make_sink(self):
        sink = self.Gst.ElementFactory.make("alsasink", "robot_speaker")
        if sink is None:
            raise RuntimeError("ALSA GStreamer output is unavailable on this robot.")
        sink.set_property("device", "reachymini_audio_sink")
        return sink


class ReachyMujocoOutput(ReachyLiteOutput):
    """Official SDK/MuJoCo target, with laptop output-only sound. Never hardware."""
    completion = "simulated_completed"
    expressive_simulation = True

    def __init__(self, port=8000, mute_audio=False):
        if not isinstance(port,int) or not 1024 <= port <= 65535:
            raise ValueError("Invalid official simulator port.")
        self.daemon_port,self.mute_audio=port,mute_audio
        super().__init__("mujoco-laptop-output", gestures=True)

    def _animate(self, motion, elapsed, duration=0., voice=0.):
        from scipy.spatial.transform import Rotation
        from reachy_mini.utils import create_head_pose
        now = time.monotonic()
        if not hasattr(self, "expression_last"):
            self.expression_antennas = list(self.mini.get_present_antenna_joint_positions())
            pose = self.mini.get_current_head_pose()
            self.expression_xyz = list(pose[:3, 3])
            self.expression_rpy = list(Rotation.from_matrix(pose[:3,:3]).as_euler('xyz'))
            self.expression_last = now - .02
        delta = now - self.expression_last
        self.expression_last = now
        antennas, xyz, rpy = expression_pose(motion, elapsed, duration, voice)
        self.expression_antennas = approach(self.expression_antennas, antennas, math.radians(75), delta)
        self.expression_xyz = approach(self.expression_xyz, xyz, .035, delta)
        self.expression_rpy = approach(self.expression_rpy, rpy, math.radians(30), delta)
        self.mini.set_target_antenna_joint_positions(self.expression_antennas)
        self.mini.set_target_head_pose(create_head_pose(
            x=self.expression_xyz[0], y=self.expression_xyz[1], z=self.expression_xyz[2],
            roll=self.expression_rpy[0], pitch=self.expression_rpy[1], yaw=self.expression_rpy[2], degrees=False))

    def idle_tick(self, motion):
        now = time.monotonic()
        if motion is None:
            self.idle_last = now
            # Resume from the last held pose without catching up paused time.
            if hasattr(self, "expression_last"):
                self.expression_last = now
            return
        if self.pipeline is not None:
            return
        self.idle_elapsed = getattr(self, "idle_elapsed", 0.) + max(0., min(.1, now-getattr(self, "idle_last", now)))
        self.idle_last = now
        self._animate(motion, self.idle_elapsed)

    def _validate_speaker(self, _speaker_name):
        from urllib.request import build_opener, ProxyHandler
        from .companion_gateway import NoRedirect
        with build_opener(ProxyHandler({}),NoRedirect()).open(f"http://127.0.0.1:{self.daemon_port}/api/daemon/status",timeout=2) as response:
            raw=response.read(65537)
        if len(raw)>65536:
            raise RuntimeError("Simulator status response exceeded limit.")
        status=json.loads(raw)
        if status.get("simulation_enabled") is not True or status.get("mockup_sim_enabled") is True:
            raise RuntimeError("Official MuJoCo mode is required. Refusing physical or lightweight-mock daemon.")

    def _select_device(self, _speaker_name):
        pass

    def _make_sink(self):
        # In this explicitly selected simulation route, sound intentionally goes
        # to the PC. The real robot routes still require explicit robot devices.
        sink=self.Gst.ElementFactory.make("autoaudiosink","simulation_laptop_speaker")
        if sink is None:
            raise RuntimeError("Laptop simulation audio output is unavailable.")
        return sink


def move_sound(dataset, name):
    """The .ogg that comes with an official recorded move (laugh, cheer, song), if
    the daemon has it in the local Hugging Face cache."""
    import os
    hub = Path(os.environ.get("HF_HUB_CACHE") or Path(os.environ.get("HF_HOME", Path.home() / ".cache/huggingface")) / "hub")
    folder = hub / ("datasets--" + dataset.replace("/", "--")) / "snapshots"
    matches = sorted(folder.glob(f"*/**/{name}.ogg")) if folder.is_dir() else []
    return matches[-1] if matches else None


class MovePlayer(threading.Thread):
    """Plays official recorded moves on its own thread, so the worker loop (which
    must poll the controller at least every 2 s) never waits on the daemon.

    The daemon plays the motion; this worker plays the move's own sound file on
    Reachy's speaker at the same moment (no slow speaker handover to the daemon).
    stop() is non-blocking.
    """
    def __init__(self, daemon, moves, sound_datasets, play_sound=None, find_sound=move_sound, poll=.4):
        super().__init__(daemon=True)
        self.daemon_call, self.moves, self.sound_datasets, self.poll = daemon, list(moves), sound_datasets, poll
        self.play_sound, self.find_sound = play_sound, find_sound
        self.stopping = threading.Event()

    def stop(self):
        self.stopping.set()

    def run(self):
        from urllib.parse import quote
        sound = None
        try:
            for dataset, name in self.moves:
                if self.stopping.is_set():
                    break
                self.daemon_call("POST", f"/api/move/play/recorded-move-dataset/{quote(dataset, safe='')}/{name}", timeout=15)
                # Long recorded moves (song dances) can take seconds to load before
                # they start: wait until the move is really running (up to 10 s)...
                started_at = time.monotonic()
                while not self.stopping.is_set() and time.monotonic() - started_at < 10:
                    try:
                        if self.daemon_call("GET", "/api/move/running", timeout=5):
                            break
                    except Exception:
                        pass
                    self.stopping.wait(.1)
                # ...start its sound together with the motion...
                if dataset in self.sound_datasets and self.play_sound and not self.stopping.is_set():
                    try:
                        path = self.find_sound(dataset, name)
                        sound = self.play_sound(path) if path else None
                    except Exception:
                        sound = None  # The move still runs, just silently.
                # ...then wait until it ends.
                misses = 0
                while not self.stopping.is_set():
                    try:
                        if not self.daemon_call("GET", "/api/move/running", timeout=5):
                            break
                        misses = 0
                    except Exception:
                        misses += 1
                        if misses >= 5:
                            break
                    self.stopping.wait(self.poll)
                if sound is not None:
                    try:
                        sound.stop()
                    except Exception:
                        pass
                    sound = None
            if self.stopping.is_set():
                try:
                    self.daemon_call("POST", "/api/move/stop", timeout=5)
                except Exception:
                    pass
        except Exception:
            pass  # A failed celebration never affects speech or the game.
        finally:
            if sound is not None:
                try:
                    sound.stop()
                except Exception:
                    pass


class ReachyLiteExpressiveOutput(ReachyLiteOutput):
    """Physical Lite USB output with the livelier expression set used in simulation.

    Real speaker and EOS completion as ReachyLiteOutput, plus idle sway, listening
    tilt, voice-paced speech motion and cheers. Amplitudes stay small (head about
    9 degrees, 5 mm lift; antennas 40 degrees) and every target is speed-limited.
    Idle motion stops during pause, narration, cancellation and stop.
    """
    expressive_simulation = True  # Enables the shared expression path in tick().
    motion_dropouts = 0
    # Official Pollen moves played by the daemon right after a line finishes:
    # the enthusiastic emotion after every gem cheer, and a dance for the treasure.
    # Idle motion is held while a move runs.
    DANCE_DATASET = "pollen-robotics/reachy-mini-dances-library"
    EMOTION_DATASET = "pollen-robotics/reachy-mini-emotions-library"
    MUSIC_DATASET = "Anne-Charlotte/music"  # Song dances shown in the Control app.
    GEM_CELEBRATION = ((EMOTION_DATASET, "enthusiastic1"),)
    MOVES_AFTER_LINE = {
        "companion_library_success": GEM_CELEBRATION,
        "companion_workshop_success": GEM_CELEBRATION,
        "companion_market_success": GEM_CELEBRATION,
        "companion_temple_success": GEM_CELEBRATION,
        # Treasure: the Reachy Mini Control app's Katy Perry "Fireworks" song dance.
        "companion_ending": ((MUSIC_DATASET, "katy-perry-fireworks"),),
    }
    # Moves that are part of a line: Reachy laughs after each joke punchline (humour
    # condition only), and the line counts as finished only after the laugh, so the
    # next line never talks over it.
    LAUGH = ((EMOTION_DATASET, "laughing1"),)
    MOVES_WITHIN_LINE = dict.fromkeys(("companion_h1_humour", "companion_h2_humour",
                                       "companion_h3_humour", "companion_h4_humour"), LAUGH)
    SOUND_DATASETS = {EMOTION_DATASET, MUSIC_DATASET}  # Their sounds play via the daemon.
    moves_pending = ()
    within_pending = ()
    within_active = False
    move_player = None

    def start(self, job):
        self._stop_moves()  # A new line always wins over a background celebration.
        self.within_active = False
        super().start(job)  # Calls cancel() first, which clears pending moves...
        audio_id = job.get("audio_id")  # ...so plan this line's moves afterwards.
        self.moves_pending = self.MOVES_AFTER_LINE.get(audio_id, ())
        self.within_pending = self.MOVES_WITHIN_LINE.get(audio_id, ())

    def tick(self):
        if self.within_active:
            if self.paused or self._moves_running():
                return False
            self.within_active = False
            return True
        done = super().tick()
        if done and self.within_pending:
            if self.pipeline is not None:  # Free the speaker so the laugh sound can play.
                pipeline, self.pipeline = self.pipeline, None
                pipeline.set_state(self.Gst.State.NULL)
            self._start_moves(self.within_pending)
            self.within_pending, self.within_active = (), True
            self.voice_duration = getattr(self, "voice_duration", 0.) + 20.  # Worker time budget.
            return False
        if done and self.moves_pending:
            self._start_moves(self.moves_pending)
            self.moves_pending = ()
        return done

    def cancel(self):
        self.moves_pending = self.within_pending = ()  # Skipped lines get no move.
        if self.within_active:  # Skip/stop during a laugh stops the laugh too.
            self.within_active = False
            self._stop_moves()
        super().cancel()

    def _start_moves(self, moves):
        self._stop_moves()
        self.move_player = MovePlayer(self._daemon, moves, self.SOUND_DATASETS, play_sound=self._play_sound)
        self.move_player.start()

    def _play_sound(self, path):
        """Play a move's sound file on Reachy's speaker (same device as its voice)."""
        player = self.Gst.ElementFactory.make("playbin", "move_sound")
        if player is None:
            return None
        player.set_property("uri", Path(path).resolve().as_uri())
        player.set_property("audio-sink", self._make_sink())
        fake = self.Gst.ElementFactory.make("fakesink", "no_video")
        if fake is not None:
            player.set_property("video-sink", fake)
        if player.set_state(self.Gst.State.PLAYING) == self.Gst.StateChangeReturn.FAILURE:
            player.set_state(self.Gst.State.NULL)
            return None

        class Sound:
            def stop(_self):
                player.set_state(self.Gst.State.NULL)
        return Sound()

    def _moves_running(self):
        return self.move_player is not None and self.move_player.is_alive()

    def _stop_moves(self):
        if self.move_player is not None:
            self.move_player.stop()  # Non-blocking; the player cleans up by itself.

    def idle_tick(self, motion):
        if self._moves_running():
            return  # Hold idle motion while a celebration plays.
        if self.move_player is not None:
            self.move_player = None
            # Re-read the real pose before idle motion continues after a move.
            for name in ("expression_last", "idle_last"):
                if hasattr(self, name):
                    delattr(self, name)
        ReachyMujocoOutput.idle_tick(self, motion)

    def _daemon(self, method, path, timeout=2):
        from urllib.request import Request, build_opener, ProxyHandler
        from .companion_gateway import NoRedirect
        request = Request(f"http://127.0.0.1:{self.daemon_port}{path}", method=method,
                          data=b"" if method == "POST" else None)
        with build_opener(ProxyHandler({}), NoRedirect()).open(request, timeout=timeout) as response:
            return json.loads(response.read(65537) or b"null")

    def _animate(self, *args, **kwargs):
        # The SDK marks its link "lost" after any 1 s gap in daemon messages and
        # recovers by itself; CPU load from speech recognition can cause such a
        # gap. Motion is decorative, so skip that frame instead of failing speech.
        try:
            ReachyMujocoOutput._animate(self, *args, **kwargs)
        except ConnectionError:
            self.motion_dropouts += 1

    def __init__(self, speaker_name):
        super().__init__(speaker_name, gestures=True)


class ReachyControlSimulatorOutput(ReachyMujocoOutput):
    """Official Control app's lightweight simulator, through its real SDK daemon."""
    supported_sdk_versions = {"1.14.0"}

    def _validate_speaker(self, _speaker_name):
        from urllib.request import build_opener, ProxyHandler
        from .companion_gateway import NoRedirect
        with build_opener(ProxyHandler({}), NoRedirect()).open(
                f"http://127.0.0.1:{self.daemon_port}/api/daemon/status", timeout=2) as response:
            raw = response.read(65537)
        if len(raw) > 65536:
            raise RuntimeError("Simulator status response exceeded limit.")
        status = json.loads(raw)
        if status.get("mockup_sim_enabled") is not True or status.get("state") != "running":
            raise RuntimeError("A running Control app mock simulator is required. Physical daemons are refused.")
        from importlib.metadata import version
        if status.get("version") != version("reachy-mini"):
            raise RuntimeError("Control app daemon and worker SDK versions must match.")
