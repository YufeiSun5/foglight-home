#!/usr/bin/env python3
"""Offline coverage/license/appearance contract checks for the UI assets."""
import hashlib
import json
from pathlib import Path
from fontTools.ttLib import TTFont
ROOT = Path(__file__).resolve().parents[2]
font_path = ROOT / 'assets/fonts/FoglightUI-SC.otf'
font = TTFont(font_path)
cmap = font.getBestCmap()
checks = 0
for directory in ('content', 'src/app', 'src/domain', 'src/adapters', 'src/presentation', 'src/bootstrap'):
    for path in (ROOT / directory).rglob('*'):
        if path.suffix not in ('.gd', '.json'): continue
        for char in path.read_text():
            if ord(char) < 32: continue
            assert ord(char) in cmap, f'{path.relative_to(ROOT)} lacks U+{ord(char):04X}: {char}'
        checks += 1
for char in (' ', '\u00a0', '\u3000', '●', '○'):
    assert ord(char) in cmap
    checks += 1
license_text = (ROOT / 'assets/fonts/OFL-1.1.txt').read_text()
assert len(license_text) > 3800 and 'PERMISSION & CONDITIONS' in license_text and 'TERMINATION' in license_text and 'DISCLAIMER' in license_text
assert 'Adobe' in license_text and '2014-2021' in license_text
assert font['name'].getDebugName(1) == 'Foglight UI SC'
meta = json.loads((ROOT / 'assets/fonts/font_provenance.json').read_text())
assert meta['subset_sha256'] == hashlib.sha256(font_path.read_bytes()).hexdigest()
checks += 4
manifest = json.loads((ROOT / 'assets/characters_v2/cen_xingyao/outfits/wardrobe_manifest.json').read_text())
assert manifest['coat_colors'] == {'blue': 0, 'indigo': 1, 'green': 2, 'cream': 3}
assert manifest['combinations'] == 16
for bottom in manifest['bottoms']:
    for resource in ('idle.png', 'idle_topmask.png'):
        assert (ROOT / 'assets/characters_v2/cen_xingyao/outfits' / bottom / resource).exists()
        checks += 1
checks += 2
print(f'UI ASSETS: {checks} checks; 0 failures')
