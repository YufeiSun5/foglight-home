#!/usr/bin/env python3
"""Validate the complete character-only checkpoint; no image-library dependency."""
from pathlib import Path
import hashlib
import json
import struct
import zlib

ROOT = Path(__file__).resolve().parents[2]
manifest = json.loads((ROOT / "assets/characters_v2/checkpoint_manifest.json").read_text())
images = manifest["images"]
assert len(images) == 36 and len({image["path"] for image in images}) == 36
for record in images:
    path = ROOT / record["path"]
    assert path.resolve().is_relative_to(ROOT.resolve()) and not path.is_symlink()
    data = path.read_bytes()
    assert len(data) == record["bytes"], path
    assert hashlib.sha256(data).hexdigest() == record["sha256"], path
    assert hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest() == record["git_blob_sha1"], path
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path
    dimensions = struct.unpack(">IIBB", data[16:26])
    assert dimensions == (record["width"], record["height"], record["bit_depth"], record["color_type"]), path
    assert dimensions[2:] == (8, 6), path
    cursor = 8
    kinds = []
    while cursor < len(data):
        assert cursor + 12 <= len(data), path
        length = struct.unpack(">I", data[cursor:cursor + 4])[0]
        end = cursor + length + 12
        assert end <= len(data), path
        kind = data[cursor + 4:cursor + 8]
        payload = data[cursor + 8:end - 4]
        checksum = struct.unpack(">I", data[end - 4:end])[0]
        assert zlib.crc32(kind + payload) & 0xffffffff == checksum, path
        kinds.append(kind)
        cursor = end
    assert cursor == len(data) and kinds[0] == b"IHDR" and kinds[-1] == b"IEND" and b"IDAT" in kinds, path
    if "characters_v2" in record["path"]:
        expected = (480, 80) if "/walk_" in record["path"] else (160, 320)
        assert dimensions[:2] == expected, path
    else:
        assert record["path"] == "assets/characters/cen_xingyao/portrait.png" and dimensions[:2] == (1774, 887)
for name in ("palette_world.gdshader", "palette_preview.gdshader"):
    source = (ROOT / "assets/characters_v2" / name).read_text()
    assert '#include "res://assets/characters_v2/palette_shared.gdshaderinc"' in source
assert (ROOT / "assets/characters_v2/palette_shared.gdshaderinc").is_file()
print("ASSET CHECKPOINT:36 PNGs; exact byte digests, dimensions, RGBA8, chunk CRCs and complete shader includes passed")
