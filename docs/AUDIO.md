# Offline game audio

The game plays bundled WAV files through Godot's `AudioStreamPlayer`. It does not call a TTS service, run a voice model, record a microphone or start an external process. The standalone authoring binaries and models under ignored `tools/narration/` are not runtime dependencies and are not exported.

## Fixed synthetic voices and attribution

Narration uses the `en_GB-alba-medium` Piper voice distributed by Michael Hansen / Rhasspy. The source corpus is **Alba speech corpus**, Cassia Valentini-Botinhao and Junichi Yamagishi (2019), University of Edinburgh, [DOI 10.7488/ds/2506](https://doi.org/10.7488/ds/2506). The [model card](https://huggingface.co/rhasspy/piper-voices/blob/main/en/en_GB/alba/medium/MODEL_CARD) lists [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) for its dataset. The generated game narration contains the supplied story letters plus original welcome/ending text, not excerpts from the training corpus.

The character clips (greeting, task, wrong attempt and success per NPC) use `en_GB-vctk-medium`, also distributed by Michael Hansen / Rhasspy. Its source is **CSTR VCTK Corpus: English Multi-speaker Corpus for CSTR Voice Cloning Toolkit (version 0.92)**, Junichi Yamagishi, Christophe Veaux and Kirsten MacDonald (2019), University of Edinburgh / CSTR, [DOI 10.7488/ds/2645](https://doi.org/10.7488/ds/2645). Its [model card](https://huggingface.co/rhasspy/piper-voices/blob/main/en/en_GB/vctk/medium/MODEL_CARD) lists [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

| Fictional character | VCTK speaker | Model numeric ID |
|---|---|---|
| Elara | p225 | 107 |
| Milo | p226 | 95 |
| Nia | p228 | 90 |
| Ori | p227 | 82 |

These are fixed synthetic game voices, not attempts to impersonate a public figure. No participant speech was used. Both model cards describe fine-tuning from a Lessac base voice; no Lessac dataset, recordings or model is included in this game. Keep this attribution with copies of the audio. No source corpus or model weights are redistributed with the playable project.

The optional standalone generation tool is the MIT-licensed [archived Rhasspy Piper release 2023.11.14-2](https://github.com/rhasspy/piper/releases/tag/2023.11.14-2), with its bundled third-party notices; it stays in ignored `tools/`, outside the export. The game only needs the resulting WAV assets. Piper and model licences should be reviewed separately if redistributing those authoring tools themselves.

## Reproduction

`dev/Bake-Narration.ps1` accepts paths to the standalone Piper executable, Alba model and VCTK greeting model. The optional tool/model files must already be present. It renders fixed texts from `data/game.json` and `data/presentation.json`, then writes `assets/audio/manifest.json`. That manifest records each source text, asset path and voice. Automated tests compare all four narration source texts to their displayed letters.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File dev/Bake-Narration.ps1
```

Narrator length scale is 1.06 with 0.3 seconds of sentence silence. Fixed per-character length scales in `data/presentation.json` are Elara 1.10, Milo 1.00, Nia 1.02 and Ori 1.16. These vary the characters' pacing, not experimental conditions. Noise scale is 0.5 and width noise is 0.65. Reimport WAV assets in Godot **after generation finishes**. Do not change the spoken source without updating the corresponding visible captions. All character dialogue is authored game content; nothing is generated live.

Original music, nature ambience and the gift chime are generated entirely in GDScript:

```text
godot --headless --path . --script res://dev/bake_soundscape.gd
```

The score is a 51.2-second soft harp/pad composition; ambience is a 25.6-second surf/wind/bird loop. These are original synthesised assets. Music and ambience have independent controls and duck under voice playback. All audio pauses with the game and stops immediately on session termination.

## Validation limits

Optional Reachy laptop rehearsal clips under `assets/audio/companion/` use Piper's **en_US-ljspeech-high**, a single US English female voice, replacing the earlier VCTK speaker 93 after unclear-pronunciation feedback. Both H1 variants and all companion lines share this voice, natural pitch, length scale 1.1 and 0.4-second sentence breaks. Its [official model card](https://huggingface.co/rhasspy/piper-voices/blob/main/en/en_US/ljspeech/high/MODEL_CARD) lists the [LJ Speech dataset](https://keithito.com/LJ-Speech-Dataset/) as public domain and credits training instructions by Bryce Beattie. The training corpus contains readings by Linda Johnson of public-domain books; no player recording is involved. Model weights stay in ignored authoring tools and are not exported.

Rebuild fixed clips with `services/controller/.venv/Scripts/python.exe dev/bake_companion.py`; it is an authoring tool, not a runtime service. The welcome and congratulations are labelled proposed additions; H1/G1 and shared hints/acknowledgements follow the supplied/game catalogues. These are laptop recordings for a mock adapter, not proof of Reachy speaker quality or physical gestures. Rendered automated tests mute output before applying accelerated playback so their test audio never comes through the user's speakers.

Tests verify nonempty clips, source-text consistency, real playback completion, narration lock, pause/resume, speech ducking and safe stop. These do not substitute for listening to pronunciation and relative loudness on the target speakers/headphones. Neural speech can still contain pronunciation or prosody artefacts. No claim of human voice acting is made.

## Optional Reachy companion voice

The separate local controller uses Kokoro af_bella for Reachy, with friendly_v2 pacing: quicker greetings/celebrations and gentler reassurance. This affects companion speech only. All 54 authored clips are cached WAVs; nickname lines use bounded memory-only local synthesis. Audition alternatives at artifacts/voice-preview/index.html. The Godot-only game remains independent of the optional controller. See CONVERSATION.md for setup and privacy.
