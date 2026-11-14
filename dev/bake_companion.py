"""Author fixed companion clips with the project-local offline Kokoro voice."""
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "services/controller"))
from echo_controller.preview import all_clips, DRAFT
from echo_controller.local_voice import delivery_profile
from echo_controller.kokoro_voice import load_voice, render, VOICE_ID, VOICE_PROFILE
import wave


def main():
    entries = all_clips()
    manifest_path = ROOT / "assets/audio/manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    voice = load_voice()
    for entry in entries:
        key = entry["audio_id"]
        speed,_=delivery_profile(key)
        joke = next((item for name,item in DRAFT.get('joke_delivery',{}).items() if key=='companion_'+name.lower()+'_humour'),None)
        profile = 'joke_setup_punchline_v1' if joke else VOICE_PROFILE
        destination = ROOT / "assets/audio/companion" / (key + ".wav")
        if destination.is_file() and manifest.get(key, {}).get("text") == entry["text"] and manifest.get(key, {}).get("voice") == 'kokoro-'+VOICE_ID and manifest.get(key,{}).get('delivery_profile')==profile:
            manifest[key]['provenance']=entry['provenance']
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
        if joke:
            setup,rate=render(voice,joke['setup'],1.0)
            punchline,punch_rate=render(voice,joke['punchline'],1.02)
            if punch_rate!=rate: raise ValueError('Mismatched joke audio rates.')
            pcm=setup+bytes(int(rate*joke['pause_ms']/1000)*2)+punchline
        else:
            pcm, rate = render(voice, entry['text'], speed)
        temporary=destination.with_suffix('.render.wav')
        with wave.open(str(temporary), 'wb') as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(rate)
            output.writeframes(pcm)
        temporary.replace(destination)
        manifest[key] = {"path": "res://" + destination.relative_to(ROOT).as_posix(), "text": entry["text"],
                         "voice": 'kokoro-'+VOICE_ID, "length_scale": speed,'delivery_profile':profile, "provenance": entry["provenance"]}
        print("Rendered", key, flush=True)
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
