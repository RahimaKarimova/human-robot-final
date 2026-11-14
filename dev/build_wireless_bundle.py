"""Package only fixed robot-worker source/assets, without sessions, dependencies or private data."""
from pathlib import Path
import json
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def build(destination=None):
    destination=Path(destination or ROOT / "build/EchoIsland-Wireless-Agent.zip")
    files=list((ROOT/"services/controller/echo_controller").glob("*.py"))
    files+=list((ROOT/"services/protocol").glob("*.json"))
    manifest=json.loads((ROOT/'assets/audio/manifest.json').read_text(encoding='utf-8-sig'))
    for key,entry in manifest.items():
        if key.startswith('companion_'):
            path=(ROOT/entry['path'].removeprefix('res://')).resolve()
            if not path.is_relative_to(ROOT/'assets/audio/companion'):raise ValueError('Invalid fixed voice asset.')
            files.append(path)
    files += [ROOT/path for path in ("Launch-Wireless-Agent.sh","data/game.json","assets/audio/manifest.json","docs/WIRELESS.md","docs/AUDIO.md","ASSET_CREDITS.md")]
    destination.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(destination,"w",zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(files):
            if not path.is_file() or not path.resolve().is_relative_to(ROOT):
                raise ValueError("Invalid agent package source.")
            archive.write(path,"EchoIsland-Agent/"+path.relative_to(ROOT).as_posix())
    return destination


if __name__ == "__main__":
    print(build())
