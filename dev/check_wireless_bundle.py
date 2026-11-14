"""Check a distribution of fixed worker source/assets without touching a robot."""
import json
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parents[1]
with zipfile.ZipFile(root / "build/EchoIsland-Wireless-Agent.zip") as archive:
    names = archive.namelist()
    assert archive.testzip() is None, "Corrupt ZIP entry"
    assert all(name.startswith("EchoIsland-Agent/") and ".." not in Path(name).parts for name in names), "Unsafe archive path"
    assert not any(any(part in name for part in (".session.json", ".robot.json", ".speech.json", ".venv/", "__pycache__", "recordings/", "transcripts/")) for name in names), "Non-distributable content"
    manifest = json.loads(archive.read("EchoIsland-Agent/assets/audio/manifest.json"))
    expected = {"EchoIsland-Agent/" + item["path"].removeprefix("res://") for key,item in manifest.items() if key.startswith("companion_")}
    actual = {name for name in names if name.endswith(".wav")}
    assert actual == expected, "Companion WAVs do not match the manifest"
    assert "EchoIsland-Agent/Launch-Wireless-Agent.sh" in names, "Missing launch wrapper"
    for name in names:
        if name.endswith(".py"):
            compile(archive.read(name), name, "exec")
print(f"WIRELESS PACKAGE: PASS ({len(names)} files, {len(actual)} fixed voice clips; no session capabilities)")
