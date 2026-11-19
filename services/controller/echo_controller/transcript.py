"""Opt-in, researcher-only conversation transcript.

One Markdown file (transcripts/conversations.md, git-ignored) collects every
session. Each game session gets a new participant ID (P001, P002, ...) and a
section with both sides of the conversation in order. Nothing here is sent to
the game; only the launcher console prints the ID. Enable it only when players
have agreed to their words being recorded.
"""
import re
import threading
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_PATH = ROOT / "transcripts" / "conversations.md"
_FILE_LOCK = threading.Lock()
_ID_PATTERN = re.compile(r"^## Participant P(\d+)\b", re.MULTILINE)
HEADER = ("# Echo Island conversation transcripts\n\n"
          "Private researcher log. Not shown in the game and excluded from Git.\n")


def _clean(text):
    return " ".join(str(text).split())


class TranscriptLog:
    def __init__(self, condition, output, path=DEFAULT_PATH):
        self.path = Path(path)
        self.closed = False
        self.logged_captures = set()
        with _FILE_LOCK:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            existing = self.path.read_text(encoding="utf-8") if self.path.exists() else ""
            numbers = [int(n) for n in _ID_PATTERN.findall(existing)]
            self.participant_id = f"P{(max(numbers) + 1) if numbers else 1:03d}"
            started = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            jokes = "on" if condition == "humour" else "off"
            section = (f"\n## Participant {self.participant_id}\n\n"
                       f"- Started: {started}\n- Jokes: {jokes}\n- Robot output: {output}\n\n")
            with self.path.open("a", encoding="utf-8") as handle:
                if not existing:
                    handle.write(HEADER)
                handle.write(section)

    def _append(self, line):
        if self.closed:
            return
        with _FILE_LOCK, self.path.open("a", encoding="utf-8") as handle:
            handle.write(line)

    def robot(self, text, label=""):
        text = _clean(text)
        if text:
            tag = f" _({label})_" if label else ""
            self._append(f"- `{datetime.now():%H:%M:%S}` **Reachy**{tag}: {text}\n")

    def person(self, capture_id, text):
        text = _clean(text)
        if text and capture_id not in self.logged_captures:
            self.logged_captures.add(capture_id)
            self._append(f"- `{datetime.now():%H:%M:%S}` **{self.participant_id}**: {text}\n")

    def close(self):
        if not self.closed:
            self._append(f"\n_Session ended {datetime.now():%Y-%m-%d %H:%M:%S}._\n")
            self.closed = True
