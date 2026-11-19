"""Short recruitment clip: Reachy is sad nobody plays, then promises to dance.

Not part of the game. Two steps:

  1. Record Reachy's two lines once (needs the GPU voice environment):
       services/expressive/.venv/Scripts/python.exe dev/recruit_video.py --bake
  2. Perform on the robot (Reachy Mini Control running, game closed):
       services/controller/.venv/Scripts/python.exe dev/recruit_video.py --play

The performance: Reachy droops sadly (sad emotion, silent) while saying its sad
line. A countdown gives time to start filming.
"""
import argparse
import json
import subprocess
import time
import wave
from pathlib import Path
from urllib.parse import quote
from urllib.request import ProxyHandler, Request, build_opener

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts" / "recruit-video"
DAEMON = "http://127.0.0.1:8000"
GST = ROOT / "services/robot/.venv/Scripts/gst-launch-1.0.exe"
SPEAKER = "Echo Cancelling Speakerphone (Reachy Mini Audio)"
EMOTIONS = "pollen-robotics/reachy-mini-emotions-library"
DANCES = "pollen-robotics/reachy-mini-dances-library"

LINES = {
    "sad": ("Why doesn't anyone want to play with me? I've been waiting here all day...",
            "Speak like a small, lonely robot who feels left out and is close to tears. Soft, slow and sad, "
            "with a little sniffle and a shaky voice. Sincere and sweet, not dramatic or angry. Keep every word clear."),
    "hopeful": ("Please come and play my treasure game. If you play with me... I'll dance for you!",
                "Speak like a hopeful, sweet little robot asking a friend to play. Start softly and pleading, then "
                "brighten into happy excitement on the final promise to dance. Smile in your voice. Keep every word clear."),
}
SAD_MOVE = (EMOTIONS, "sad2")
DANCE_MOVES = ((DANCES, "groovy_sway_and_roll"), (DANCES, "side_to_side_sway"), (EMOTIONS, "enthusiastic1"))


def bake():
    import os
    import sys
    import numpy as np
    import torch
    os.environ.setdefault("HF_HUB_OFFLINE", "1")
    sys.path.insert(0, str(ROOT / "services/expressive"))
    from profiles import CONFIG
    from faster_qwen3_tts import FasterQwen3TTS
    OUT.mkdir(parents=True, exist_ok=True)
    model = FasterQwen3TTS.from_pretrained(str(ROOT / "tools/narration/qwen3-customvoice"), device="cuda",
                                           dtype=torch.bfloat16, attn_implementation="sdpa", max_seq_len=1024)
    for key, (text, direction) in LINES.items():
        torch.manual_seed(57)
        with torch.inference_mode():
            audio, rate = model.generate_custom_voice(text=text, language="English", speaker=CONFIG["speaker"],
                                                      instruct=direction, max_new_tokens=450)
        samples = np.clip(np.asarray(audio[0]), -1, 1)
        with wave.open(str(OUT / f"{key}.wav"), "wb") as output:
            output.setnchannels(1); output.setsampwidth(2); output.setframerate(rate)
            output.writeframes((samples * 32767).astype("<i2").tobytes())
        print(f"Recorded {key}.wav ({len(samples) / rate:.1f}s)")


def daemon(method, path, timeout=15):
    request = Request(DAEMON + path, method=method, data=b"" if method == "POST" else None)
    with build_opener(ProxyHandler({})).open(request, timeout=timeout) as response:
        return json.loads(response.read() or b"null")


def play_move(dataset, name):
    daemon("POST", f"/api/move/play/recorded-move-dataset/{quote(dataset, safe='')}/{name}")
    time.sleep(1)
    while daemon("GET", "/api/move/running", timeout=5):
        time.sleep(.3)


def say(key):
    path = OUT / f"{key}.wav"
    subprocess.run([str(GST), "-q", "filesrc", f"location={path.as_posix()}", "!", "wavparse", "!", "audioconvert",
                    "!", "audioresample", "!", "wasapi2sink", f"device={speaker_id()}"], check=True)


def speaker_id():
    monitor = subprocess.run([str(GST.with_name("gst-device-monitor-1.0.exe")), "Audio/Sink"],
                             capture_output=True, text=True, errors="replace").stdout
    block = monitor.split(f"name  : {SPEAKER}", 1)[1]
    return block.split("wasapi2sink device='", 1)[1].split("'", 1)[0]


def play():
    status = daemon("GET", "/api/daemon/status", timeout=5)
    if status.get("state") == "error":
        # The motor link sometimes drops (loose power/USB); reconnect once automatically.
        print("Reconnecting to the robot...", flush=True)
        daemon("POST", "/api/daemon/restart", timeout=30)
        for _ in range(40):
            time.sleep(1)
            status = daemon("GET", "/api/daemon/status", timeout=5)
            if status.get("state") in {"running", "error"}:
                break
    if status.get("state") != "running":
        raise SystemExit("The robot is not ready. Check its power and USB cable, then try again.")
    if daemon("GET", "/api/motors/status", timeout=5).get("mode") != "enabled":
        daemon("POST", "/api/motors/set_mode/enabled")
    daemon("POST", "/api/move/play/wake_up")
    time.sleep(4)
    for second in range(5, 0, -1):
        print(f"Start filming! {second}...", flush=True)
        time.sleep(1)
    print("ACTION", flush=True)
    # Sad body language while speaking: the daemon plays the sad emotion silently
    # (speaker stays with us), and Reachy says its line at the same time.
    try:
        daemon("POST", "/api/media/release")
    except Exception:
        pass
    daemon("POST", f"/api/move/play/recorded-move-dataset/{quote(SAD_MOVE[0], safe='')}/{SAD_MOVE[1]}")
    time.sleep(.6)
    say("sad")
    while daemon("GET", "/api/move/running", timeout=5):
        time.sleep(.3)
    print("CUT - done!", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--bake", action="store_true", help="Record Reachy's two lines (GPU).")
    group.add_argument("--play", action="store_true", help="Perform the clip on the robot.")
    args = parser.parse_args()
    bake() if args.bake else play()
