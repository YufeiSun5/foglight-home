#!/usr/bin/env python3
"""Build a renamed, offline Noto CJK SC subset from the installed Debian font.
The subset intentionally includes whitespace, Latin keys, UI, approved content and
application status messages. No network fetch or new runtime dependency is used.
"""
import hashlib
import json
from pathlib import Path
from fontTools import subset
from fontTools.ttLib import TTCollection

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc')
LICENSE_SOURCE = Path('/usr/share/doc/fonts-noto-cjk/copyright')
DEST = ROOT / 'assets/fonts'
font = TTCollection(SOURCE).fonts[2]
assert font['name'].getDebugName(1) == 'Noto Sans CJK SC'
copyright_notice = font['name'].getDebugName(0)
license_notice = font['name'].getDebugName(13)
assert 'SIL Open Font License, Version 1.1' in license_notice
text = ''.join(chr(codepoint) for codepoint in range(32, 127)) + '\u00a0\u3000●○'
for directory in ('content', 'src/app', 'src/domain', 'src/adapters', 'src/presentation', 'src/bootstrap'):
    for path in sorted((ROOT / directory).rglob('*')):
        if path.suffix in ('.gd', '.json'): text += path.read_text(encoding='utf-8')
codepoints = sorted(set(map(ord, text)))
source_cmap = font.getBestCmap()
missing = [codepoint for codepoint in codepoints if codepoint >= 32 and codepoint not in source_cmap]
assert not missing, missing
options = subset.Options()
options.name_IDs = ['*']
options.name_legacy = True
options.name_languages = ['*']
worker = subset.Subsetter(options=options)
worker.populate(unicodes=codepoints)
worker.subset(font)
# Subsetting is a modification. Avoid presenting the derived family as Noto.
for record in font['name'].names:
    names = {1: 'Foglight UI SC', 2: 'Regular', 3: 'FoglightUISubsetSC-Regular-1',
             4: 'Foglight UI SC Regular', 6: 'FoglightUI-SC-Regular',
             16: 'Foglight UI SC', 17: 'Regular'}
    if record.nameID in names:
        record.string = names[record.nameID].encode(record.getEncoding())
if 'CFF ' in font:
    font['CFF '].cff.fontNames = ['FoglightUI-SC-Regular']
    top = font['CFF '].cff.topDictIndex[0]
    top.FamilyName = 'Foglight UI SC'
    top.FullName = 'Foglight UI SC Regular'
DEST.mkdir(exist_ok=True)
output = DEST / 'FoglightUI-SC.otf'
font.save(output)
packaging = LICENSE_SOURCE.read_text()
license_text = packaging.rsplit('\nLicense: SIL-1.1\n', 1)[1].split('\nLicense: GPL-3+', 1)[0]
license_text = '\n'.join('' if line.strip() == '.' else line.removeprefix(' ') for line in license_text.splitlines())
(DEST / 'OFL-1.1.txt').write_text(copyright_notice + '\n\n' + license_text.strip() + '\n')
provenance = {'family': 'Foglight UI SC', 'derived_from': 'Noto Sans CJK SC Regular',
    'source': str(SOURCE), 'installed_package': 'fonts-noto-cjk',
    'upstream': 'https://github.com/notofonts/noto-cjk',
    'source_sha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
    'subset_sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
    'copyright': copyright_notice, 'license': 'SIL Open Font License 1.1',
    'license_file': 'OFL-1.1.txt', 'modification': 'Simplified Chinese face extracted, subset to project text, family renamed.',
    'coverage_count': len(font.getBestCmap()), 'build': 'python3 tests/ui/build_ui_font.py',
    'redistribution': 'Bundle OFL-1.1.txt; do not sell font by itself. No project license is granted by this font license.'}
(DEST / 'font_provenance.json').write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + '\n')
print(f'FONT: {len(font.getBestCmap())} glyph mappings; {output.stat().st_size} bytes; coverage verified')
