"""Create public synthetic ASR test fixtures, never participant recordings."""
import audioop
from pathlib import Path
import subprocess
import wave

root = Path(__file__).resolve().parents[1]
folder = root / "tools/speech/fixtures"
folder.mkdir(parents=True, exist_ok=True)
engine = root / "tools/narration/engine/piper/piper.exe"
model = root / "tools/narration/en_US-ljspeech-high.onnx"
for key, text in {"pause":"I need a break", "repeat":"repeat the question", "hint":"give me a hint", "skip":"skip the question", "stop":"stop the session", "negation":"please do not stop", "story":"I enjoy stories about exploring islands", "privacy":"are you recording", "wait":"give me a moment", "name":"My name is Alex", "dislike_books":"I do not like books"}.items():
    if (folder/(key+'.wav')).is_file():
        continue
    source = folder / (key + "-source.wav")
    subprocess.run([str(engine),"--model",str(model),"--output_file",str(source),"--quiet"], input=(text+"\n").encode(),check=True,cwd=engine.parent)
    with wave.open(str(source)) as audio:
        pcm, _ = audioop.ratecv(audio.readframes(audio.getnframes()), 2, 1, audio.getframerate(), 16000, None)
    with wave.open(str(folder / (key+".wav")),"wb") as audio:
        audio.setparams((1,2,16000,0,"NONE","not compressed"))
        audio.writeframes(bytes(16000)+pcm+bytes(16000))
    print("Created synthetic fixture:",key)
