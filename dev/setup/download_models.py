"""Download the local speech, dialogue and voice models for a new laptop.

Run with the speech environment's Python (it has huggingface_hub). Each step
is skipped when its files are already present, so the script can be re-run
after an interrupted download, or after copying a tools/ folder over.
"""
import argparse
import shutil
import sys
import urllib.request
import zipfile
from pathlib import Path

from huggingface_hub import hf_hub_download, snapshot_download

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools"
VOSK_URL = "https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip"
KOKORO_URL = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/"
# Robot moves the game plays: laugh/enthusiastic emotions and the final dance
# with its music. The sounds are read from the default Hugging Face cache.
REACHY_DATASETS = ("pollen-robotics/reachy-mini-emotions-library",
                   "pollen-robotics/reachy-mini-dances-library",
                   "Anne-Charlotte/music")


def say(text):
    print(text, flush=True)


def fetch(url, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    partial = target.with_name(target.name + ".part")
    say(f"  downloading {url}")
    with urllib.request.urlopen(url, timeout=60) as response, partial.open("wb") as handle:
        shutil.copyfileobj(response, handle, length=1 << 20)
    partial.replace(target)


def whisper():
    for size in ("base.en", "small.en"):
        folder = TOOLS / "speech" / f"whisper-{size}"
        if (folder / "model.bin").exists():
            say(f"- Whisper {size}: already present")
            continue
        say(f"- Whisper {size}")
        snapshot_download(f"Systran/faster-whisper-{size}", local_dir=folder)


def vosk():
    folder = TOOLS / "speech" / "vosk-model-small-en-us-0.15"
    if (folder / "am" / "final.mdl").exists():
        say("- Vosk: already present")
        return
    say("- Vosk")
    archive = TOOLS / "speech" / "vosk-model-small-en-us-0.15.zip"
    if not archive.exists():
        fetch(VOSK_URL, archive)
    with zipfile.ZipFile(archive) as zipped:
        zipped.extractall(TOOLS / "speech")


def qwen():
    target = TOOLS / "dialogue" / "qwen3-0.6b" / "Qwen3-0.6B-Q8_0.gguf"
    if target.exists():
        say("- Qwen3 0.6B: already present")
        return
    say("- Qwen3 0.6B (topic finder)")
    hf_hub_download("Qwen/Qwen3-0.6B-GGUF", "Qwen3-0.6B-Q8_0.gguf", local_dir=target.parent)


def kokoro():
    folder = TOOLS / "narration" / "kokoro"
    for name in ("kokoro-v1.0.onnx", "voices-v1.0.bin"):
        if (folder / name).exists():
            say(f"- Kokoro {name}: already present")
        else:
            say(f"- Kokoro {name} (name voice)")
            fetch(KOKORO_URL + name, folder / name)


def reachy_moves():
    for repo in REACHY_DATASETS:
        say(f"- Reachy moves: {repo}")
        snapshot_download(repo, repo_type="dataset")


STEPS = {"whisper": whisper, "vosk": vosk, "qwen": qwen, "kokoro": kokoro, "reachy": reachy_moves}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("steps", nargs="*", help="any of: " + ", ".join(STEPS))
    steps = parser.parse_args().steps or list(STEPS)
    unknown = [name for name in steps if name not in STEPS]
    if unknown:
        parser.error("unknown step: " + ", ".join(unknown))
    for name in steps:
        STEPS[name]()
    say("Models ready.")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:  # Show a short reason; the setup script stops.
        print(f"Download failed: {error}", file=sys.stderr)
        sys.exit(1)
