# Cloud story/state checkpoint — 2026-10-06

This independently tested milestone contains the 75-node chapter, transactional state, immediately available wardrobe combinations, and versioned save system. It is not a playable or visually approved build. The graphical harbor and character presentation remain in development.

Development and all checks for this milestone ran only on dot's Linux cloud computer, using Godot 4.6.3. No user device is needed. Narrative and architectural decisions follow the current project documents. Reviewed code from `wip/mac-handoff-20261006` was selectively reused; its rejected graphical scene was not adopted.

## Run checks

From the repository root with Godot 4.6.3 installed:

```
godot --headless --path . --script tests/content/validate_content.gd
godot --headless --path . --script tests/domain/run_tests.gd
godot --headless --path . --script tests/integration/run_save_recovery.gd
python3 tests/content/check_json.py
python3 tools/check_boundaries.py
```

The tests cover content references and effects, 27 expression-choice paths through chapter completion, all 16 outfits at game start, free conversations and exact interrupted-story restoration, duplicate commands, stale callbacks, isolated views, transaction rollback, schema migration, corruption recovery, unknown-version preservation, and injected interruption points.

The synchronous save adapter flushes, validates, and renames files. This is not a promise of power-loss durability on every filesystem. Windows behavior, interactive UI, audio playback, renderer performance, and graphical quality are not verified by these tests.

The optional roguelite excursion is not implemented in this checkpoint. It is not a requirement for the main story, relationships, or outfits.
