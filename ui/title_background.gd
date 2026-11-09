class_name TitleBackground
extends Control
## The title screen's painting (assets/ui/title_background.jpg: a refugee on a ridge, the cabin, the
## crashed airship and the ruined capital), always filling the screen: scaled to cover it,
## cropping a little off the edges on screens that aren't 16:9 rather than showing bars. On narrow
## screens it's shifted so the refugee stays clear of the menu (`keep_clear`).
##
## It drifts very slowly: over about DRIFT_SECONDS it zooms in a little (about the refugee) and
## pans slightly, then eases back, over and over. Understated living details sit on the painting,
## in its own pixels, so they drift with it: smoke from the cabin chimney and the airship wreck, a
## fog band drifting across the valley, the cabin window flickering warmly, and a faint pulse in the
## castle's golden glow.

const ART := "res://assets/ui/title_background.jpg"
## The painting's size in pixels, and where things are in it
const ART_SIZE := Vector2(1376, 768)
const REFUGEE := Vector2(405, 500)
const REFUGEE_HALF_WIDTH := 30.0
const CHIMNEY := Vector2(638, 416)
const WRECK_SMOKE := [Vector2(852, 510), Vector2(934, 492), Vector2(1012, 478)]
const WINDOW := Vector2(718, 497)
const CASTLE_GLOW := Vector2(962, 196)
const FOG_BAND := Rect2(0, 455, 1376, 190)
## The drift: how long zooming in takes (easing back takes as long), how far it zooms, and how far
## it pans (screen pixels)
const DRIFT_SECONDS := 60.0
const DRIFT_ZOOM := 0.06
const DRIFT_PAN := Vector2(-16, -7)

## Screen x (from the left) the refugee must stay to the right of (the menu's right edge plus room)
var keep_clear := 0.0

var _painting: Control
var _window_glow: Sprite2D
var _castle_glow: Sprite2D
var _time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.05, 0.07)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	_painting = Control.new()
	_painting.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_painting.size = ART_SIZE
	add_child(_painting)
	var art := TextureRect.new()
	art.texture = load(ART)
	art.size = ART_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_painting.add_child(art)
	_add_fog()
	_painting.add_child(_smoke(CHIMNEY, 16, Color(0.8, 0.8, 0.83), 1.0))
	for spot in WRECK_SMOKE:
		_painting.add_child(_smoke(spot, 10, Color(0.86, 0.86, 0.88), 0.75))
	_window_glow = _glow(WINDOW, 30.0, Color(1.0, 0.7, 0.36))
	_castle_glow = _glow(CASTLE_GLOW, 110.0, Color(1.0, 0.8, 0.38))


func _process(delta: float) -> void:
	_time += delta
	_place_painting()
	# The window's warm light flickers a little, like a fire inside
	var flicker := sin(_time * 7.3) * 0.5 + sin(_time * 3.1 + 1.7) * 0.3 + sin(_time * 13.0) * 0.2
	_window_glow.modulate.a = 0.42 + flicker * 0.12
	# The castle's golden glow breathes, slowly
	_castle_glow.modulate.a = 0.16 + 0.1 * (0.5 + 0.5 * sin(_time * 0.8))


# Covers the screen (cropping evenly, but keeping the refugee clear of the menu), then zooms about
# the refugee and pans by the drift
func _place_painting() -> void:
	var screen := size
	var cover := maxf(screen.x / ART_SIZE.x, screen.y / ART_SIZE.y)
	var offset := (screen - ART_SIZE * cover) / 2.0
	# Narrow screens crop the sides: shift right (never past the painting's left edge) so the
	# refugee stays to the right of the menu
	var refugee_left := offset.x + (REFUGEE.x - REFUGEE_HALF_WIDTH) * cover
	if refugee_left < keep_clear:
		offset.x = minf(offset.x + keep_clear - refugee_left, 0.0)
	# The drift: 0 to 1 and back, easing at both ends
	var k := 0.5 - 0.5 * cos(TAU * _time / (DRIFT_SECONDS * 2.0))
	var zoom := cover * (1.0 + DRIFT_ZOOM * k)
	var pivot := offset + REFUGEE * cover
	var at := pivot - REFUGEE * zoom + DRIFT_PAN * k
	# Always covering the screen
	at.x = clampf(at.x, screen.x - ART_SIZE.x * zoom, 0.0)
	at.y = clampf(at.y, screen.y - ART_SIZE.y * zoom, 0.0)
	_painting.position = at
	_painting.scale = Vector2(zoom, zoom)


# The fog band: faint drifting noise across the valley floor
func _add_fog() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.006
	noise.fractal_octaves = 3
	var texture := NoiseTexture2D.new()
	texture.width = 512
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	var material := ShaderMaterial.new()
	material.shader = load("res://ui/title_fog.gdshader")
	material.set_shader_parameter("noise_tex", texture)
	var fog := ColorRect.new()
	fog.material = material
	fog.position = FOG_BAND.position
	fog.size = FOG_BAND.size
	fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_painting.add_child(fog)


# A thin column of smoke rising and fading from a spot (in the painting's pixels)
func _smoke(spot: Vector2, amount: int, color: Color, size_factor: float) -> CPUParticles2D:
	var smoke := CPUParticles2D.new()
	smoke.position = spot
	smoke.amount = amount
	smoke.lifetime = 9.0
	smoke.preprocess = 9.0
	smoke.local_coords = true
	smoke.texture = _soft_dot()
	smoke.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 2.5
	smoke.direction = Vector2(-0.12, -1.0)
	smoke.spread = 7.0
	smoke.initial_velocity_min = 6.0
	smoke.initial_velocity_max = 10.0
	smoke.gravity = Vector2(-1.2, -0.8)
	smoke.damping_min = 0.2
	smoke.damping_max = 0.5
	smoke.angle_min = -180.0
	smoke.angle_max = 180.0
	smoke.scale_amount_min = 0.13 * size_factor
	smoke.scale_amount_max = 0.19 * size_factor
	var grow := Curve.new()
	grow.max_value = 3.0
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 2.4))
	smoke.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(color, 0.0))
	fade.set_color(1, Color(color, 0.0))
	fade.add_point(0.12, Color(color, 0.2))
	fade.add_point(0.55, Color(color, 0.1))
	smoke.color_ramp = fade
	return smoke


# A soft additive glow over a spot (in the painting's pixels), `width` pixels across
func _glow(spot: Vector2, width: float, color: Color) -> Sprite2D:
	var glow := Sprite2D.new()
	glow.texture = _soft_dot()
	glow.position = spot
	glow.scale = Vector2.ONE * width / 64.0
	glow.modulate = color
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = add
	_painting.add_child(glow)
	return glow


static var _dot: GradientTexture2D


static func _soft_dot() -> GradientTexture2D:
	if _dot == null:
		var edge := Gradient.new()
		edge.set_color(0, Color(1, 1, 1, 1))
		edge.set_color(1, Color(1, 1, 1, 0))
		_dot = GradientTexture2D.new()
		_dot.gradient = edge
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(1.0, 0.5)
		_dot.width = 64
		_dot.height = 64
	return _dot
