extends RefCounted
## Read-only scene capability / coordinate mapping boundary, injected by bootstrap.
## Never clamp, rewrite, or migrate a saved logical anchor here.
## resolve_snapshot returns {ok, mapping_id, scene_id, logical_anchor:[x,z],
## visual_anchor:[x,z], transformed:bool}. The mapping must be explicit and stable.
## Returning ok does NOT assert that the scene is loaded or visually accepted.
## GameFlow exposes a transition token; the world must prepare the target, then
## report scene_ready only after its required resources and collision are stable.
## On cancel/failure, redraw the unchanged authoritative snapshot.
func resolve_snapshot(_snapshot: Dictionary) -> Dictionary:
	return {"ok": false, "error": "此场景尚未接入，已保留原位置"}

## Optional reverse mapping for actual movement. A presentation fallback without
## an unambiguous inverse must refuse this, keeping the original saved anchor.
func logical_position(_scene_id: String, _visual_position: Array, _mapping_id: String) -> Dictionary:
	return {"ok": false, "error": "此画面位置尚未建立可逆存档映射"}

## Optional encounter resources must also be checked before a departure save.
## Successful resolution starts the same scene_ready / cancellation handshake.
func resolve_expedition(_expedition: Dictionary) -> Dictionary:
	return {"ok": false, "error": "短途场景尚未接入，可继续自由探索"}
