extends RefCounted
## Authored pixel polygons, modular costume, and keyframes. No reference image crops.
const Rules = preload("res://src/domain/story_rules.gd")
static var cache: Dictionary = {}
static func palette(who: String, outfit: Dictionary) -> Dictionary:
	var c = {"ink": Color("182331"), "skin": Color("d6ae8e"), "skin_light": Color("f3d5b1"), "skin_shadow": Color("b57c68"), "hair": Color("292a31"), "hair_light": Color("50505a"), "cloth": Color("708ba9"), "gold": Color("c3a469"), "shirt": Color("e3dbc6"), "pants": Color("39404d")}
	if who == "xu": c.hair = Color("6b4936"); c.hair_light = Color("a27b51"); c.cloth = Color("658c7c"); c.pants = Color("665142")
	elif who == "qi": c.cloth = Color("9c5359"); c.shirt = Color("d5c8b8"); c.pants = Color("303039")
	elif who == "shen": c.cloth = Color("3c526b"); c.pants = Color("3b3b42"); c.skin = Color("c59c7b")
	else:
		c.cloth = Color(Rules.COLORS.get(outfit.get("color", "blue"), "708ba9"))
		if outfit.get("top") == "tunic": c.shirt = c.cloth.lightened(0.4)
	return c
static func rect(im: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for iy in range(maxi(0, y), mini(im.get_height(), y + h)):
		for ix in range(maxi(0, x), mini(im.get_width(), x + w)): im.set_pixel(ix, iy, c)
static func poly(im: Image, points: Array, c: Color, shift: Vector2i = Vector2i.ZERO) -> void:
	var ps: PackedVector2Array = []
	for p in points: ps.append(Vector2(p[0] + shift.x, p[1] + shift.y))
	var minx = im.get_width(); var miny = im.get_height(); var maxx = 0; var maxy = 0
	for p in ps: minx = mini(minx, int(p.x)); maxx = maxi(maxx, int(p.x)); miny = mini(miny, int(p.y)); maxy = maxi(maxy, int(p.y))
	for y in range(maxi(0, miny), mini(im.get_height(), maxy + 1)):
		for x in range(maxi(0, minx), mini(im.get_width(), maxx + 1)):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), ps): im.set_pixel(x, y, c)
static func sprite(who: String, outfit: Dictionary, direction: int, action: String, frame: int) -> Texture2D:
	var key = JSON.stringify([who, outfit, direction, action, frame])
	if cache.has(key): return cache[key]
	var im = Image.create(64, 96, false, Image.FORMAT_RGBA8)
	var c = palette(who, outfit)
	var bob = 1 if frame % 2 == 1 else 0
	var stride = [0, 3, 0, -3][frame % 4] if action == "walk" else 0
	var side = direction == 2 or direction == 3
	var back = direction == 1
	var dx = -3 if direction == 2 else (3 if direction == 3 else 0)
	var short_coat: bool = outfit.get("coat", "short") == "short" or who == "xu"
	var has_coat: bool = outfit.get("coat", "short") != "none" or who != "star"
	var bottom: String = outfit.get("bottom", "work") if who == "star" else "work"
	# Boots, articulated legs, trousers / four skirt cuts.
	rect(im, 20 - stride / 2, 79 - absi(stride), 10, 11, c.ink)
	rect(im, 34 + stride / 2, 80 - absi(stride), 11, 10, c.ink)
	rect(im, 20 - stride / 2, 79 - absi(stride), 8, 7, c.pants.darkened(0.25))
	rect(im, 35 + stride / 2, 80 - absi(stride), 8, 7, c.pants.darkened(0.25))
	if bottom in ["work", "wide"]:
		poly(im, [[21, 55], [44, 55], [45 + stride / 2, 80 - absi(stride)], [33 + stride / 2, 80 - absi(stride)], [32, 63], [29 - stride / 2, 80], [18 - stride / 2, 80]], c.ink)
		rect(im, 21 - stride / 2, 58, 9 if bottom == "work" else 12, 21 - absi(stride), c.pants)
		rect(im, 34 + stride / 2, 58, 9 if bottom == "work" else 12, 21 - absi(stride), c.pants.lightened(0.12))
		rect(im, 23, 60, 5, 2, c.gold.darkened(0.2))
	else:
		var length = 79 if bottom == "long_skirt" else (68 if bottom == "pleated" else 73)
		poly(im, [[21, 54], [43, 54], [49, length], [15, length]], c.ink)
		poly(im, [[22, 56], [42, 56], [46, length - 2], [18, length - 2]], c.cloth.darkened(0.25))
		for x in [22, 29, 36, 42]: rect(im, x, 58, 2, length - 60, c.cloth)
		if bottom == "culottes": rect(im, 31, 60, 2, 13, c.ink)
	# Coat tails; gold hems visibly move with stride.
	if has_coat and not short_coat:
		poly(im, [[16, 37], [26, 44], [24 + stride / 2, 81], [13, 77], [15, 56]], c.cloth.darkened(0.2))
		poly(im, [[38, 42], [48, 38], [52, 76], [41 - stride / 2, 81]], c.cloth)
		rect(im, 16, 75, 7, 2, c.gold); rect(im, 42, 76, 6, 2, c.gold)
	poly(im, [[22, 31], [41, 31], [47, 39], [43, 57], [21, 57], [16, 39]], c.ink, Vector2i(0, bob))
	poly(im, [[24, 33], [39, 33], [43, 42], [42, 54], [22, 54], [20, 41]], c.shirt, Vector2i(0, bob))
	if has_coat:
		poly(im, [[22, 32], [29, 37], [26, 55], [20, 59 if short_coat else 67], [16, 40]], c.cloth, Vector2i(0, bob))
		poly(im, [[38, 32], [46, 38], [47, 57 if short_coat else 67], [38, 56], [35, 38]], c.cloth.lightened(0.09), Vector2i(0, bob))
		rect(im, 24, 37 + bob, 2, 14, c.gold); rect(im, 38, 39 + bob, 2, 13, c.gold)
	# Arms: alternating hand positions and a three-pose deliberate interaction.
	var hand_y = 52 + stride / 2
	rect(im, 14, 37 + bob, 7, 16 + stride / 2, c.cloth if has_coat else c.shirt)
	rect(im, 15, hand_y, 5, 5, c.skin)
	var raised = action == "interact" and frame % 3 != 0
	rect(im, 44, 37 + bob, 6, 17 - stride / 2 if not raised else 9, c.cloth if has_coat else c.shirt)
	rect(im, 45, 53 - stride / 2 if not raised else 31 + frame, 5, 5, c.skin_light)
	rect(im, 23, 54 + bob, 18, 3, c.ink); rect(im, 30, 54 + bob, 4, 3, c.gold)
	# Satchel, apron or red cape are distinct from animation/costume layers.
	if who == "star":
		for y in range(35, 61): rect(im, 40 - (y - 35) / 3, y + bob, 2, 1, c.pants)
		rect(im, 39, 50 + bob, 11, 13, c.ink); rect(im, 40, 51 + bob, 9, 10, Color("725541")); rect(im, 42, 54 + bob, 4, 2, c.gold)
	elif who == "xu":
		rect(im, 24, 40 + bob, 17, 22, c.cloth.darkened(0.15)); rect(im, 26, 52 + bob, 13, 5, c.pants); rect(im, 28, 49 + bob, 2, 9, c.gold)
	elif who == "qi": poly(im, [[18, 30], [43, 30], [49, 52], [36, 47], [27, 43], [14, 47]], c.cloth.darkened(0.1), Vector2i(0, bob))
	# Head, asymmetrical hair, facial direction and blinks.
	poly(im, [[22, 7], [34, 5], [44, 11], [44, 24], [38, 33], [27, 34], [19, 27], [18, 16]], c.ink, Vector2i(dx, bob))
	poly(im, [[23, 13], [39, 12], [43, 19], [40, 28], [34, 32], [26, 28], [22, 22]], c.skin, Vector2i(dx, bob))
	poly(im, [[27, 15], [39, 14], [40, 22], [35, 29], [28, 27]], c.skin_light, Vector2i(dx, bob))
	poly(im, [[19, 18], [18, 10], [23, 7], [22, 4], [30, 6], [35, 3], [44, 10], [45, 17], [41, 21], [38, 13], [30, 16], [27, 12], [24, 21]], c.hair, Vector2i(dx, bob))
	rect(im, 25 + dx, 10 + bob, 11, 2, c.hair_light)
	if who == "qi": poly(im, [[40, 8], [47, 7], [51, 13], [49 + stride / 2, 34], [43, 44], [45, 24]], c.hair, Vector2i(0, bob)); rect(im, 45, 10 + bob, 3, 2, c.gold)
	if who == "xu": rect(im, 20 + dx, 17 + bob, 3, 7, c.gold)
	if back:
		poly(im, [[21, 11], [40, 10], [43, 26], [37, 33], [26, 32], [21, 27]], c.hair, Vector2i(dx, bob))
	elif side:
		rect(im, 25 + dx if direction == 2 else 39, 20 + bob, 2, 2, c.ink)
		rect(im, 21 if direction == 2 else 43, 23 + bob, 3, 2, c.skin_light)
	else:
		rect(im, 27, 20 + bob, 3, 2 if frame % 4 != 3 else 1, c.ink); rect(im, 37, 20 + bob, 3, 2 if frame % 4 != 3 else 1, c.ink)
		rect(im, 33, 27 + bob, 4, 1, c.skin_shadow)
	if who == "shen" and not back: rect(im, 30 + dx, 29 + bob, 8, 2, c.hair_light)
	var tex = ImageTexture.create_from_image(im)
	cache[key] = tex
	return tex

static func portrait(who: String, outfit: Dictionary, expression: String = "calm", blink: bool = false) -> Texture2D:
	var key = JSON.stringify(["portrait", who, outfit, expression, blink])
	if cache.has(key): return cache[key]
	var im = Image.create(160, 192, false, Image.FORMAT_RGBA8)
	var c = palette(who, outfit)
	var male = who == "shen"
	var coat = outfit.get("coat", "short") != "none" or who != "star"
	# Hair behind the neck, shoulders, neckline and selected outerwear.
	if who == "qi": poly(im, [[94, 17], [119, 14], [139, 34], [132, 120], [118, 156], [109, 67]], c.hair); poly(im, [[121, 29], [126, 38], [117, 148], [108, 156]], c.cloth)
	elif who == "xu": poly(im, [[39, 28], [106, 24], [123, 53], [117, 95], [102, 116], [40, 105], [25, 76]], c.hair)
	poly(im, [[53, 100], [99, 100], [119, 116], [147, 135], [154, 192], [8, 192], [14, 138], [41, 117]], c.ink)
	poly(im, [[58, 91], [94, 90], [100, 116], [81, 131], [57, 114]], c.skin_shadow)
	poly(im, [[61, 93], [92, 92], [93, 110], [78, 120], [62, 110]], c.skin)
	poly(im, [[54, 116], [76, 128], [102, 114], [133, 136], [139, 192], [24, 192], [29, 137]], c.shirt)
	poly(im, [[55, 116], [74, 125], [62, 145], [43, 124]], c.shirt.lightened(0.08))
	poly(im, [[80, 126], [101, 115], [116, 127], [95, 145]], c.shirt.darkened(0.25))
	for y in [148, 163, 178]: rect(im, 76, y, 3, 3, c.gold.darkened(0.4))
	if coat:
		poly(im, [[41, 112], [59, 119], [54, 158], [58, 192], [11, 192], [17, 139]], c.cloth.darkened(0.17))
		poly(im, [[99, 115], [126, 127], [144, 144], [153, 192], [100, 192], [99, 157]], c.cloth)
		poly(im, [[39, 112], [55, 115], [66, 145], [51, 138], [44, 158]], c.cloth.lightened(0.25))
		poly(im, [[98, 112], [119, 126], [105, 145], [109, 158], [92, 145]], c.cloth.lightened(0.13))
		for y in range(144, 190, 13):
			rect(im, 43, y, 3, 5, c.gold); rect(im, 111, y + 3, 3, 5, c.gold)
		if outfit.get("coat") == "long" and who == "star": poly(im, [[20, 133], [42, 146], [37, 192], [12, 192]], c.cloth.lightened(0.2))
	# Personal details.
	if who == "star":
		poly(im, [[121, 126], [129, 131], [63, 192], [56, 192]], Color("65513e")); rect(im, 105, 158, 15, 12, c.gold.darkened(0.3)); rect(im, 108, 160, 9, 7, c.ink)
	elif who == "xu":
		poly(im, [[42, 130], [51, 132], [56, 165], [111, 165], [117, 134], [126, 138], [132, 192], [34, 192]], c.cloth.darkened(0.2)); rect(im, 57, 162, 52, 30, c.pants); rect(im, 69, 159, 5, 24, c.gold)
	elif who == "qi":
		poly(im, [[41, 105], [63, 111], [76, 129], [126, 114], [146, 137], [133, 177], [94, 148], [73, 143], [28, 165]], c.cloth.darkened(0.08)); rect(im, 100, 131, 11, 8, c.gold); rect(im, 103, 133, 5, 4, c.ink)
	elif who == "shen": poly(im, [[58, 113], [77, 128], [101, 115], [110, 132], [89, 153], [59, 141]], c.cloth.darkened(0.24))
	# Angular adult facial silhouette and skin planes.
	poly(im, [[47, 25], [94, 19], [116, 38], [112, 76], [99, 98], [78, 108], [55, 95], [40, 72], [38, 46]], c.ink)
	poly(im, [[47, 35], [91, 29], [108, 44], [107, 73], [97, 91], [77, 101], [57, 91], [44, 71], [42, 49]], c.skin)
	poly(im, [[62, 37], [88, 33], [101, 45], [99, 72], [90, 91], [75, 98], [63, 87], [57, 66]], c.skin_light)
	poly(im, [[43, 60], [53, 66], [61, 85], [77, 99], [61, 93], [45, 74]], c.skin_shadow)
	poly(im, [[84, 62], [91, 72], [85, 77], [81, 75]], c.skin_shadow)
	rect(im, 84, 67, 3, 8, c.skin.lightened(0.09))
	# Eyes, brows, mouth: calm / smile / wary / hurt / angry + blink.
	var brow = -2 if expression == "wary" else (2 if expression == "angry" else 0)
	poly(im, [[55, 53 + brow], [65, 51], [71, 54], [56, 56 + brow]], c.hair)
	poly(im, [[86, 52], [97, 53 + brow], [99, 56 + brow], [86, 55]], c.hair)
	if blink:
		rect(im, 56, 61, 15, 2, c.ink); rect(im, 87, 61, 13, 2, c.ink)
	else:
		poly(im, [[54, 60], [61, 57], [69, 58], [72, 61], [67, 65], [58, 64]], Color("e8e1cc"))
		poly(im, [[85, 60], [91, 57], [98, 59], [101, 62], [96, 65], [87, 64]], Color("e8e1cc"))
		rect(im, 64, 58, 5, 7, Color("67766e") if who == "star" else Color("6e5a3b")); rect(im, 93, 58, 4, 7, Color("6e5a3b"))
		rect(im, 66, 59, 2, 5, c.ink); rect(im, 94, 59, 2, 5, c.ink); rect(im, 64, 58, 2, 2, c.skin_light); rect(im, 93, 58, 1, 2, c.skin_light)
		rect(im, 55, 58, 15, 1, c.ink); rect(im, 87, 58, 12, 1, c.ink)
	if expression == "smile":
		poly(im, [[72, 84], [91, 82], [85, 89], [78, 90]], c.skin_shadow); rect(im, 76, 85, 10, 2, c.shirt)
	elif expression == "hurt": poly(im, [[72, 87], [79, 83], [90, 87]], c.skin_shadow)
	else: poly(im, [[71, 83], [81, 82], [90, 84], [82, 86], [75, 85]], c.skin_shadow)
	if male:
		poly(im, [[57, 82], [64, 90], [79, 96], [94, 85], [93, 95], [78, 104], [61, 96]], c.hair_light.darkened(0.1)); rect(im, 72, 80, 14, 2, c.hair_light)
	# Hairstyle stays distinct; main character's early short cut respects script.
	poly(im, [[36, 47], [37, 28], [48, 20], [44, 12], [64, 17], [77, 9], [91, 17], [108, 20], [116, 34], [116, 59], [105, 66], [103, 38], [87, 43], [84, 29], [68, 42], [66, 30], [53, 47], [50, 66], [42, 59]], c.hair)
	poly(im, [[44, 28], [60, 22], [67, 21], [55, 34], [42, 43]], c.hair_light)
	poly(im, [[75, 20], [88, 19], [99, 27], [87, 28], [78, 37]], c.hair_light)
	if who == "xu":
		poly(im, [[45, 27], [51, 23], [56, 30], [47, 38], [41, 48]], c.gold); rect(im, 43, 54, 3, 12, c.gold)
	elif who == "qi":
		rect(im, 103, 23, 10, 4, c.gold); rect(im, 107, 59, 3, 9, c.gold)
	elif who == "star": rect(im, 41, 47, 4, 12, c.cloth.lightened(0.3))
	var tex = ImageTexture.create_from_image(im)
	cache[key] = tex
	return tex
