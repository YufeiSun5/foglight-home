#!/usr/bin/env python3
"""Reassemble exact original GLBs from ordinary Git binary parts; no network."""
from pathlib import Path
import hashlib, json
root = Path(__file__).resolve().parent
def checked_path(relative):
    candidate = (root / relative).resolve()
    if Path(relative).is_absolute() or not candidate.is_relative_to(root):
        raise ValueError("Unsafe manifest path")
    return candidate
for item in json.loads((root / "asset-parts/manifest.json").read_text()):
    payload = b"".join(checked_path(part).read_bytes() for part in item["parts"])
    assert len(payload) == item["bytes"], item["target"]
    assert hashlib.sha256(payload).hexdigest() == item["sha256"], item["target"]
    target = checked_path(item["target"])
    if target.exists():
        assert target.read_bytes() == payload, "Existing asset differs; refusing overwrite: " + item["target"]
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(payload)
    print("Verified:", item["target"])
