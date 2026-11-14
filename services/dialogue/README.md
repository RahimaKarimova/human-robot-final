# Offline CPU conversation extension

This optional environment runs the six planned-question acknowledgements. Rasa controls the question schedule, commands and authored answer categories. Qwen3-0.6B extracts a short topic only when the answer does not confidently match a category; authored templates turn a grounded topic into an acknowledgement. Unclear answers request repair. This cannot cover every possible utterance or guarantee correct speech recognition. It is not open-ended chat and has no game-control tools.

Fixed Ryan recordings play immediately without a model. Novel acknowledgements stream using Pocket TTS's public Marius voice on CPU. Short names use CPU Kokoro am_puck; these voices can sound different. No Ryan voice cloning is used. GPU Qwen TTS belongs solely to the author's `services/expressive` environment and is not a recipient requirement.

## Provision once, run offline

Create a project-local Python 3.12 environment here; install `requirements.txt` using pip (on Windows the CPU wheels above avoid compiler/CUDA installation). `requirements-lock.txt` records the complete tested environment. On macOS install the matching CPU packages for that platform; Windows virtual environments cannot be copied to a Mac. Mac execution of this new extension has not been verified.

Download the official Qwen/Qwen3-0.6B-GGUF file `Qwen3-0.6B-Q8_0.gguf` to `tools/dialogue/qwen3-0.6b/`. This is the only response-model size used at runtime. Larger models in authoring experiments are not required.

Before running the CPU voice, set `HF_HOME` to the absolute project path `tools/narration/pocket-cache`. Load Pocket TTS 4.0.1's default English model and its public `marius` preset once while provisioning. This caches the public `kyutai/pocket-tts-without-voice-cloning` English weights, tokenizer and Marius embedding. No gated cloning model, account or API key is required. For fully offline distribution, include this cache with its snapshot/blob structure preserved. The production worker sets `HF_HUB_OFFLINE=1`, disables implicit tokens and loads only these cached files.

The other optional speech, Rasa and controller environments still need their documented models. The ordinary Godot game works without any of these environments. A game-only ZIP does not automatically include this controller setup.

## Validation and limits

From the project root, run `services/controller/.venv/Scripts/python.exe dev/check_cpu_conversation.py`. It uses synthetic answers for all six questions and checks streamed CPU audio; it opens no microphone or robot. Its report is `artifacts/expressive-voice/offline-cpu-check.json`. End-to-end recognition and response latency varies by CPU and utterance length; first audio timing alone is not total conversation latency.

Startup preloads local models and can take substantially longer than a warm reply, particularly when other applications use memory. Unknown answers are not silently acknowledged if the topic extractor fails. Live generated text and audio remain in process/session memory; session stop clears personalized controller command text. No answer transcript/audio files or cloud calls are created by these workers.

Sources: https://huggingface.co/Qwen/Qwen3-0.6B-GGUF ; https://github.com/abetlen/llama-cpp-python ; https://github.com/kyutai-labs/pocket-tts . Model and package licenses remain applicable when distributing their weights.
