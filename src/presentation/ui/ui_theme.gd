extends RefCounted
const INK = Color("eff0e8")
const MUTED = Color("bacacb")
const GOLD = Color("e5c78a")
const DEEP = Color("101d28")
const FONT = preload("res://assets/fonts/FoglightUI-SC.otf")

static func box(color: Color, border: Color, width: int = 1, padding: int = 14) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(3)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

static func make() -> Theme:
	var result = Theme.new()
	result.default_font = FONT
	result.default_font_size = 20
	for type in ["Label", "Button", "RichTextLabel"]:
		result.set_color("font_color", type, INK)
	result.set_constant("separation", "VBoxContainer", 8)
	result.set_constant("separation", "HBoxContainer", 10)
	result.set_constant("line_spacing", "RichTextLabel", 5)
	result.set_stylebox("panel", "PanelContainer", box(Color(0.045, 0.085, 0.12, 0.97), Color("799591")))
	result.set_stylebox("normal", "Button", box(Color("162d3b"), Color("49616c")))
	result.set_stylebox("hover", "Button", box(Color("29434c"), GOLD))
	result.set_stylebox("pressed", "Button", box(Color("36585b"), GOLD, 2))
	result.set_stylebox("disabled", "Button", box(Color("17272f"), Color("344850")))
	var focus = box(Color(0, 0, 0, 0), GOLD, 2)
	result.set_stylebox("focus", "Button", focus)
	result.set_color("font_hover_color", "Button", Color.WHITE)
	result.set_color("font_focus_color", "Button", Color.WHITE)
	result.set_color("font_disabled_color", "Button", Color("70858c"))
	return result
