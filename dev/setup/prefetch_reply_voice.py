"""Download the CPU reply voice (pocket-tts 'marius') into tools/narration/pocket-cache.

Run with the dialogue environment's Python. At play time the voice loads
offline from this folder (see echo_controller/cpu_reply_voice.py).
"""
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
os.environ["HF_HOME"] = str(ROOT / "tools/narration/pocket-cache")
os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"

from pocket_tts import TTSModel  # noqa: E402

model = TTSModel.load_model()
state = model.get_state_for_audio_prompt("marius")
for _ in model.generate_audio_stream(state, "Hello."):
    pass
print("Reply voice ready.")
