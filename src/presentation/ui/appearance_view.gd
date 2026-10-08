extends RefCounted
## Presentation-only resource mapping. Color IDs match wardrobe_manifest.json.
const COAT_INDEX = {"blue": 0, "indigo": 1, "green": 2, "cream": 3}
const PORTRAIT = preload("res://assets/characters/cen_xingyao/portrait.png")
const PORTRAIT_SHADER = preload("res://assets/characters/palette_portrait.gdshader")
const PREVIEW_SHADER = preload("res://assets/characters_v2/palette_preview.gdshader")
const OUTFITS = {
	"trousers": [preload("res://assets/characters_v2/cen_xingyao/outfits/trousers/idle.png"), preload("res://assets/characters_v2/cen_xingyao/outfits/trousers/idle_topmask.png")],
	"culottes": [preload("res://assets/characters_v2/cen_xingyao/outfits/culottes/idle.png"), preload("res://assets/characters_v2/cen_xingyao/outfits/culottes/idle_topmask.png")],
	"long_skirt": [preload("res://assets/characters_v2/cen_xingyao/outfits/long_skirt/idle.png"), preload("res://assets/characters_v2/cen_xingyao/outfits/long_skirt/idle_topmask.png")],
	"short_skirt": [preload("res://assets/characters_v2/cen_xingyao/outfits/short_skirt/idle.png"), preload("res://assets/characters_v2/cen_xingyao/outfits/short_skirt/idle_topmask.png")]
}
const NPCS = {
	"shen": preload("res://assets/characters_v2/npcs/shen_yanzhou/idle.png"),
	"xu": preload("res://assets/characters_v2/npcs/xu_zhiwei/idle.png"),
	"qi": preload("res://assets/characters_v2/npcs/qi_lan/idle.png")
}

static func atlas(texture: Texture2D, region: Rect2) -> AtlasTexture:
	var result = AtlasTexture.new()
	result.atlas = texture
	result.region = region
	result.filter_clip = true
	return result

static func image_rect() -> TextureRect:
	var result = TextureRect.new()
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

static func portrait(speaker: String, expression: String, appearance: Dictionary) -> TextureRect:
	var result = image_rect()
	result.name = "SpeakerPortrait"
	result.set_meta("speaker_id", speaker)
	if speaker == "star":
		var column = 1 if expression == "smile" else (2 if expression in ["hurt", "wary"] else 0)
		var width = PORTRAIT.get_width() / 3.0
		result.texture = atlas(PORTRAIT, Rect2(column * width, 0, width, PORTRAIT.get_height()))
		var tint = ShaderMaterial.new()
		tint.shader = PORTRAIT_SHADER
		tint.set_shader_parameter("coat_color", COAT_INDEX.get(appearance.get("coat_color", "blue"), 0))
		result.material = tint
		result.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		result.set_meta("art_kind", "existing_protagonist_portrait")
		result.set_meta("coat_color", appearance.get("coat_color", "blue"))
	elif NPCS.has(speaker):
		# Existing 80px idle sprite, deliberately not presented as a finished portrait.
		result.texture = atlas(NPCS[speaker], Rect2(0, 0, 80, 80))
		result.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		result.set_meta("art_kind", "npc_idle_placeholder")
	else:
		result.set_meta("art_kind", "text_only")
	return result

static func wardrobe(appearance: Dictionary) -> TextureRect:
	var result = image_rect()
	result.name = "WardrobeFullBody"
	var bottom: String = appearance.get("bottom_id", "trousers")
	if not OUTFITS.has(bottom): bottom = "trousers"
	result.texture = atlas(OUTFITS[bottom][0], Rect2(0, 0, 80, 80))
	result.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var tint = ShaderMaterial.new()
	tint.shader = PREVIEW_SHADER
	tint.set_shader_parameter("top_mask", OUTFITS[bottom][1])
	tint.set_shader_parameter("coat_color", COAT_INDEX.get(appearance.get("coat_color", "blue"), 0))
	result.material = tint
	result.set_meta("coat_color", appearance.get("coat_color", "blue"))
	result.set_meta("bottom_id", bottom)
	return result
