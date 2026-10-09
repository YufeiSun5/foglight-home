# PBR sourcing handoff: blocked downloads

No external texture is currently installed. Do not treat this list as an asset inventory or include its nonexistent file paths in a scene.

## Official provenance checked on 2026-10-09

- Poly Haven asset license: https://polyhaven.com/license. Official policy confirms its asset files are CC0 and permits commercial use and redistribution. This does not cover the surrounding website copy or logos.
- Creative Commons legal code: https://creativecommons.org/publicdomain/zero/1.0/legalcode.en. License body is archived as CC0-1.0.txt.
- ambientCG official license was also checked: https://docs.ambientcg.com/license/. Its downloadable assets are CC0 1.0 Universal. No ambientCG files were acquired.

Four candidates with albedo/diffuse, GL normal and roughness offered on official pages:
- Wood Table 001: https://polyhaven.com/a/wood_table_001 — 1.5 m tall, 1K/2K offered. Smooth, fine brown grain. Chosen over heavily cracked candidates; would need higher roughness and subtle ageing, not black crevice contrast.
- Beige Wall 002: https://polyhaven.com/a/beige_wall_002 — 3 m tall, 1K/2K offered. Fine rough plaster.
- Sandy Gravel: https://polyhaven.com/a/sandy_gravel — 2.1 m wide, 1K/2K offered. Light sand/stone path.
- Rock Boulder Dry: https://polyhaven.com/a/rock_boulder_dry — 1.8 m tall, 1K/2K offered. Pale sandy-grey stone.

## Import contract after a real download

Diffuse/albedo uses sRGB; GL normal and roughness are non-colour linear data. GL means tangent-space +Y, not DirectX -Y. Keep roughness as roughness, not gloss. Metalness is zero for these four surfaces. Do not multiply baked AO heavily into albedo. Source dimensions specify the labelled axis only; verify the downloaded image aspect ratio before deriving the other axis. Hue, grain orientation and seam severity require pixel inspection after download. No downloaded-file hash can be supplied until bytes exist.

Suggested first pass: 1K each, no packed ARM dependency and no displacement geometry. Retain source JPEG bytes and their SHA256 values in a completed manifest. The teal roof remains original board geometry and original material.

## Verified blocker

See connection_checks.json for the exact targets and outcomes. Three official hosts timed out through curl; a normal sandbox-escalated retry also timed out. The web tool could read the official pages but could not provide local binary texture files. This branch stopped promptly rather than substituting previews or claiming successful downloads.
