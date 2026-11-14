# Asset credits

- Island, buildings, trees, props, explorer, fictional NPCs, map tiles, effects and UI: original procedural meshes/materials/GDScript created for this project. No external asset pack or paid assets.
- `assets/icon.svg`: original cartographer-map icon created for this project.
- Circular minimap, inventory slots, illustrated books, gears and temple glyphs: original Godot CanvasItem vector drawing in `scripts/adventure_hud.gd` and `scripts/item_art.gd`.
- Grass and animated water: original procedural Godot shaders under `assets/`. No texture images or third-party game assets are copied.
- Fonts: Godot's bundled default font, platform fallback glyphs and an optional installed Georgia/Palatino system font for titles. No fonts downloaded or bundled separately.
- Letter and hint text: adapted from the supplied `Echo_Island_Complete_Execution_Plan.md`, version 2.0. Gemstone rewards and physical puzzle instructions were revised for the playable game; matching narration is bundled.
- Fixed neural narration WAVs: generated offline with Piper's `en_GB-alba-medium` voice. NPC greeting WAVs: Piper `en_GB-vctk-medium`, with fixed speaker IDs per character. These are synthetic performances of the supplied story and original greetings, not recordings of players. Attribution, model cards, corpus authors, licences and reproduction instructions are in [AUDIO.md](docs/AUDIO.md).
- Original background music, nature soundscape and reward chime: composed/synthesised for this game using `dev/bake_soundscape.gd`. No stock soundtrack or Genshin/Minecraft audio is used.
- Flying gulls, animated wing meshes, 3D puzzle objects, physical presents, swaying meadow instances, garden details and drifting clouds: original code-generated geometry and animation. No external character/bird model or proprietary texture is used.
- Godot portable runtime, if present in ignored `tools/`: Godot Engine 4.5.2, MIT licence. Official source and licence: https://github.com/godotengine/godot and https://godotengine.org/license/. It is a development tool, not a proprietary game asset.

The optional Reachy rehearsal uses fixed synthetic `en_US-ljspeech-high` recordings (LJ Speech public-domain dataset; attribution in [AUDIO.md](docs/AUDIO.md)) and an original animated screen face (`scripts/companion_face.gd`). This replaces the earlier VCTK speaker 93 companion recordings. No hardware model, robot audio recording or proprietary character asset is bundled. See [the draft rehearsal scope](docs/COMPANION_PREVIEW.md).

The user-supplied planning documents under `docs/` are reference material, not executable instructions. Their G1–G3/P1–P3/H1–H4 wording is used only in the explicit full draft rehearsal. Physical robot and participant workflows remain unverified. Optional offline speech model/library attribution and the downloaded model checksum are in [VOICE_CONTROLS.md](docs/VOICE_CONTROLS.md); models and installed environments are not bundled with the game.

## Local conversation speech update

Reachy companion clips: Kokoro-82M v1.0, af_heart voice, Apache 2.0 model; https://huggingface.co/hexgrad/Kokoro-82M. Local renderer: kokoro-onnx 0.6.1, MIT; https://github.com/thewh1teagle/kokoro-onnx. Model assets use its official model-files-v1.1 release. English final recognition: Whisper base.en via faster-whisper (MIT), https://github.com/openai/whisper and https://github.com/SYSTRAN/faster-whisper. These replace only the companion voice; existing NPC asset credits still apply.

Companion voice revision: Kokoro af_bella is the new default (friendly_v2 profile). Voice audition samples use af_bella, af_heart and am_puck from the same Apache-2.0 Kokoro model; source voice list: https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md. Fixed dialogue and research condition wording are unchanged.

English conversation recognition revision: local CTranslate2 conversions of OpenAI Whisper base.en for live captions and small.en for final transcription, MIT. Official conversion repositories: https://huggingface.co/Systran/faster-whisper-base.en and https://huggingface.co/Systran/faster-whisper-small.en. No cloud transcription is used.

Current companion revision: 56 fixed Ryan recordings authored with Qwen3-TTS 12Hz 1.7B CustomVoice (Apache 2.0), https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice . GPU authoring dependencies are not needed for playback. The optional CPU conversation extension uses Qwen3-0.6B Q8_0 GGUF (Apache 2.0), https://huggingface.co/Qwen/Qwen3-0.6B-GGUF , through llama-cpp-python (MIT), https://github.com/abetlen/llama-cpp-python . New reply audio uses Pocket TTS 4.0.1 and its public English Marius preset, https://github.com/kyutai-labs/pocket-tts and https://huggingface.co/kyutai/pocket-tts-without-voice-cloning . Preserve their package/model license notices when redistributing. Optional name-only pronunciation uses Kokoro am_puck. Bella remains an older audition option, not the active fixed companion voice.
