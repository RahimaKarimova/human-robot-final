# Expressive voice audition

This isolated authoring environment tests Qwen3-TTS 1.7B CustomVoice, the speech-model family documented by the current Reachy conversation backend. It is separate from the game, controller, Rasa and speech-recognition environments. It does not start a microphone, camera, live chat or physical robot connection.

This GPU environment is authoring-only. Neutral and cheerful audition samples use the same words and speaker, allowing the user to judge actual style control. Prepared WAVs are published by dev/bake_expressive_companion.py; recipient playback needs no GPU, Qwen package, model weights or cloud service.

Personal names use the existing CPU-only Kokoro environment and a warm name-only helper. The short name word can sound different from the recorded Ryan voice. It is cached only for the session. The expressive sentence itself is always a recording. If the optional name helper is unavailable, the fixed recording still plays.

Pocket TTS was also tested on CPU with its public Marius preset. It now voices novel acknowledgements in the optional offline conversation extension, using the CPU-only services/dialogue environment. See that directory's README and artifacts/expressive-voice/offline-cpu-check.json. It is not required for standalone game playback. Its gated voice-cloning weights were not accessed, and no account/login was added.

Install the CUDA 12.8 PyTorch 2.10 wheels from the official PyTorch index, then install qwen-tts 0.1.1 in this environment. The public model is downloaded under tools/narration/qwen3-customvoice and loaded locally. Use dev/audition_expressive_voice.py with this environment's Python. No runtime API key or upload is needed.

Sources: https://github.com/QwenLM/Qwen3-TTS and https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice (Apache 2.0). Speech-model family comparison: https://github.com/huggingface/speech-to-speech. Matching the current documented model family does not establish the exact settings of the user's conversation app.
