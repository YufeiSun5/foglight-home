"""Reject duplicate JSON IDs before parsing can erase them (stdlib only)."""
import json
from pathlib import Path


def unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


root = Path(__file__).resolve().parents[2]
for path in sorted((root / "content").rglob("*.json")):
    json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique)
    print(f"PASS: {path.relative_to(root)} duplicate keys / JSON")
try:
    json.loads('{"g1":1,"g1":2}', object_pairs_hook=unique)
except ValueError:
    print("PASS: duplicate-key negative fixture rejected")
else:
    raise AssertionError("duplicate JSON keys were not rejected")
