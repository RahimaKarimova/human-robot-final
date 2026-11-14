"""Build public, synthetic control examples; never learns from player responses."""
import json
from pathlib import Path

root = Path(__file__).resolve().parent
phrases = json.loads((root.parent / "protocol/control_phrases.json").read_text(encoding="utf-8"))
lines = ['version: "3.1"', "nlu:"]
for intent, examples in phrases.items():
    lines += [f"- intent: {intent.lower()}", "  examples: |"]
    lines += [f"    - {example}" for example in examples]
(root / "data").mkdir(exist_ok=True)
(root / "data/nlu.yml").write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"Generated {sum(map(len, phrases.values()))} synthetic control examples.")
