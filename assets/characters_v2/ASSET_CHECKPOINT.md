# V2 character asset checkpoint

This checkpoint makes36 already-uploaded original image objects reachable. It does not add a main scene, gameplay coordinator, font, harbor/cabin geometry, remaining NPC busts or the full graphical runtime. The existing core project does not acquire a dependency on missing files.

## Included, complete subsets

- Protagonist: four bottoms (`trousers`, `culottes`, `long_skirt`, `short_skirt`), each with idle plus down/right/up walking atlases and matching top masks:32 PNGs
- Three companions: one four-direction idle/blink atlas each:3 PNGs. NPC movement is not claimed
- Protagonist bust: one transparent three-expression sheet:1 PNG. Other characters' busts are not included in this checkpoint
- Shared world/wardrobe color shaders and the separate bust shader; their in-repository includes are complete

`checkpoint_manifest.json` binds exact sizes, PNG dimensions, SHA-256 and Git blob SHA-1. `python3 tests/content/validate_asset_checkpoint.py` validates every byte digest and PNG chunk CRC without third-party dependencies. These file checks are not visual/GUI proof; current tested gameplay and source-publication status remain in AI_BOARD.

## Runtime contract

Pixel frames are80×80, with feet at[40,75] and effective character height about64 pixels. Idle sheets are160×320, two columns(open/blink) and four rows(down,left,right,up); neutral2.6s and blink0.12s. Walking sheets are480×80, six poses, about8fps. Left walking temporarily flips right, including asymmetric pouch/hair ornaments; it is not independently drawn leftward motion. NPCs remain stationary with directional idle.

One top shape uses `coat_color`0=blue,1=indigo,2=green,3=cream. Four bottom shapes and four top colors yield16 immediately usable combinations in the integrated game, not16 separately recolored source images. Exact masks prevent skin, gold, leather and bottom cloth being broadly tinted. The shared shader source preserves the world/wardrobe ramp; bust recoloring has its own source-blue luminance ramp.

The included bust sheet is1774×887; its three expression regions use fractional width1774/3, not a silently cropped integer frame. It is a new original generated illustration, not a commercial-game image or a crop from the concept lineup.

## Provenance and limits

All four characters are original fictional adults. The design follows the author's approved original concept; no real person's identity is represented. Runtime image artwork was created/edited with OpenAI image generation, then technically registered, nearest-neighbor resampled, packed and masked. Source and color details are in CHARACTER_V2_PROVENANCE.md. Authoring prompts/records and packaging scripts accompany this checkpoint; high-resolution authoring inputs and diagnostic previews are separate working assets, not required runtime files.

SO2R reference images were observed for composition/pixel-language research only and are not included. No commercial-game pixels, textures, models, logos or audio are bundled. This document does not grant an open-source license or guarantee exclusive copyright. It does not claim final visual approval, Windows runtime testing or complete graphical source publication.
