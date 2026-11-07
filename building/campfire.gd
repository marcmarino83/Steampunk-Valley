class_name Campfire
extends StaticBody3D
## A campfire. It's built already laid with some fuel but unlit. Light it with a handful of
## plant fiber as tinder, then keep it going by feeding it: sticks burn quickly, wood lasts
## longer, and coal lasts longest and burns hottest, warming you from further away.

## Seconds of fuel the fire is built with, ready to light
@export var starting_fuel := 120.0
## Seconds each piece of fuel adds
@export var stick_burn := 20.0
@export var wood_burn := 75.0
@export var coal_burn := 150.0
## The most fuel the fire can hold at once, in seconds
@export var max_fuel := 600.0
## How close you need to be to feel the heat, normally and while coal is burning
@export var warmth_radius := 6.0
@export var coal_warmth_radius := 10.0

## Fuel, in the order E reaches for it: wood first, then sticks, and coal last,
## since it's precious once the forge needs it
const FUELS := [["Wood", "wood_burn"], ["Sticks", "stick_burn"], ["Coal", "coal_burn"]]

@onready var light: OmniLight3D = $Light

# The fire's particles: flames, rising embers and a thin column of smoke
var _flames: GPUParticles3D
var _embers: GPUParticles3D
var _smoke: GPUParticles3D

## Seconds of burning left in the fire (lit or not)
var fuel := 0.0
## True once it's been lit, until the fuel runs out
var lit := false
# Seconds of that fuel that's coal, burning hot
var _coal_left := 0.0


func _ready() -> void:
	add_to_group("campfires")
	fuel = starting_fuel
	_flames = _make_flames()
	_embers = _make_embers()
	_smoke = _make_smoke()
	for effect in [_flames, _embers, _smoke]:
		effect.emitting = false
		add_child(effect)


func is_lit() -> bool:
	return lit


## How close you need to be to feel the heat right now
func heat_radius() -> float:
	return coal_warmth_radius if _coal_left > 0.0 else warmth_radius


func can_interact() -> bool:
	return true


func get_prompt() -> String:
	if lit:
		var piece := _next_fuel(null)
		var line := "Add fuel (Wood, Sticks or Coal)" if piece.is_empty() else "Add %s (+%s)" % [piece[0], _clock(get(piece[1]))]
		return "%s\nBurning%s: %s" % [line, " hot" if _coal_left > 0.0 else "", _clock(fuel)]
	if fuel <= 0.0:
		return "Add fuel (Wood, Sticks or Coal)"
	return "Light fire (1 Plant Fiber)"


func interact(player) -> void:
	# A laid but unlit fire: light it with tinder
	if not lit and fuel > 0.0:
		if player.remove_item("Plant Fiber", 1):
			lit = true
		else:
			player.flash("You need Plant Fiber to light the fire")
		return

	# Otherwise, feed it
	var piece := _next_fuel(player)
	if piece.is_empty():
		player.flash("You have nothing to burn. Sticks, Wood or Coal will do")
		return
	var seconds: float = get(piece[1])
	if fuel + seconds > max_fuel:
		player.flash("The fire can't take any more yet")
		return
	player.remove_item(piece[0], 1)
	fuel += seconds
	if piece[0] == "Coal":
		_coal_left += seconds


# Which fuel E would use: the first one in FUELS that the player is carrying.
# With no player given, it asks the player currently looking at the fire.
func _next_fuel(player) -> Array:
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	if player == null:
		return []
	for piece in FUELS:
		if player.inventory.get(piece[0], 0) > 0:
			return piece
	return []


# 150 seconds -> "2:30"
func _clock(seconds: float) -> String:
	var whole := ceili(seconds)
	@warning_ignore("integer_division")
	var minutes := whole / 60
	return "%d:%02d" % [minutes, whole % 60]


func _process(delta: float) -> void:
	if lit:
		fuel = maxf(fuel - delta, 0.0)
		_coal_left = minf(maxf(_coal_left - delta, 0.0), fuel)
		if fuel <= 0.0:
			lit = false
	# Particles stop making new flames when the fire goes out, so the last ones die away naturally
	for effect in [_flames, _embers, _smoke]:
		if effect.emitting != lit:
			effect.emitting = lit
	light.visible = lit

	if lit:
		# Flicker: two wobbles at different speeds so it never looks regular.
		# Coal burns bigger and brighter, and lights up further.
		var hot := _coal_left > 0.0
		var t := Time.get_ticks_msec() * 0.001
		var flicker := sin(t * 13.0) * 0.5 + sin(t * 7.3) * 0.5
		light.light_energy = (3.2 if hot else 2.0) + flicker * 0.4
		light.omni_range = 13.0 if hot else 9.0
		_flames.scale = Vector3.ONE * (1.35 if hot else 1.0)


# Licks of flame among the logs: soft glowing blobs that rise quickly, shrink and burn out from
# yellow-white through orange to red. They're added on top of what's behind them, so they glow.
func _make_flames() -> GPUParticles3D:
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = 0.14
	motion.direction = Vector3.UP
	motion.spread = 12.0
	motion.initial_velocity_min = 0.5
	motion.initial_velocity_max = 0.9
	motion.gravity = Vector3(0.0, 0.9, 0.0)
	motion.angle_min = -180.0
	motion.angle_max = 180.0
	motion.scale_min = 0.8
	motion.scale_max = 1.3
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 0.6))
	shrink.add_point(Vector2(0.25, 1.0))
	shrink.add_point(Vector2(1.0, 0.15))
	var shrink_texture := CurveTexture.new()
	shrink_texture.curve = shrink
	motion.scale_curve = shrink_texture
	var burn := Gradient.new()
	burn.set_color(0, Color(1.0, 0.9, 0.55, 0.0))
	burn.set_color(1, Color(0.7, 0.08, 0.0, 0.0))
	burn.add_point(0.12, Color(1.0, 0.75, 0.3, 0.9))
	burn.add_point(0.5, Color(1.0, 0.4, 0.08, 0.7))
	var burn_texture := GradientTexture1D.new()
	burn_texture.gradient = burn
	motion.color_ramp = burn_texture

	var blob := QuadMesh.new()
	blob.size = Vector2(0.32, 0.42)
	var look := StandardMaterial3D.new()
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.vertex_color_use_as_albedo = true
	look.albedo_texture = _soft_dot()
	# Brighter than white, so the glow effect makes them shine
	look.albedo_color = Color(2.2, 1.6, 1.1)
	blob.material = look

	var flames := GPUParticles3D.new()
	flames.name = "Flames"
	flames.amount = 32
	flames.lifetime = 0.7
	flames.local_coords = true
	flames.process_material = motion
	flames.draw_pass_1 = blob
	flames.position = Vector3(0.0, 0.12, -0.03)
	flames.visibility_aabb = AABB(Vector3(-1, -0.5, -1), Vector3(2, 2.5, 2))
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return flames


# A few sparks drifting up out of the fire and winking out
func _make_embers() -> GPUParticles3D:
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = 0.18
	motion.direction = Vector3.UP
	motion.spread = 25.0
	motion.initial_velocity_min = 0.6
	motion.initial_velocity_max = 1.4
	motion.gravity = Vector3(0.05, 0.4, 0.0)
	motion.turbulence_enabled = true
	motion.turbulence_noise_strength = 0.5
	motion.scale_min = 0.6
	motion.scale_max = 1.3
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.75, 0.35, 1.0))
	fade.set_color(1, Color(0.6, 0.1, 0.0, 0.0))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	motion.color_ramp = fade_texture

	var spark := QuadMesh.new()
	spark.size = Vector2(0.04, 0.04)
	var look := StandardMaterial3D.new()
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.vertex_color_use_as_albedo = true
	look.albedo_texture = _soft_dot()
	look.albedo_color = Color(3.0, 2.0, 1.2)
	spark.material = look

	var embers := GPUParticles3D.new()
	embers.name = "Embers"
	embers.amount = 8
	embers.lifetime = 2.2
	embers.process_material = motion
	embers.draw_pass_1 = spark
	embers.position = Vector3(0.0, 0.25, -0.03)
	embers.visibility_aabb = AABB(Vector3(-2, -0.5, -2), Vector3(4, 5, 4))
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return embers


# A thin grey column of smoke, rising from above the flames and slowly spreading as it drifts off
func _make_smoke() -> GPUParticles3D:
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = 0.06
	motion.direction = Vector3.UP
	motion.spread = 5.0
	motion.initial_velocity_min = 0.5
	motion.initial_velocity_max = 0.7
	# Rising on the fire's heat, and leaning slightly with a light breeze
	motion.gravity = Vector3(0.06, 0.15, 0.02)
	motion.angle_min = -180.0
	motion.angle_max = 180.0
	var grow := Curve.new()
	grow.max_value = 3.0
	grow.add_point(Vector2(0.0, 0.3))
	grow.add_point(Vector2(1.0, 2.2))
	var grow_texture := CurveTexture.new()
	grow_texture.curve = grow
	motion.scale_curve = grow_texture
	var fade := Gradient.new()
	fade.set_color(0, Color(0.3, 0.29, 0.28, 0.0))
	fade.set_color(1, Color(0.6, 0.6, 0.6, 0.0))
	fade.add_point(0.15, Color(0.3, 0.29, 0.28, 0.35))
	fade.add_point(0.6, Color(0.45, 0.44, 0.43, 0.15))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	motion.color_ramp = fade_texture

	var puff := QuadMesh.new()
	puff.size = Vector2(0.4, 0.4)
	var look := StandardMaterial3D.new()
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.vertex_color_use_as_albedo = true
	look.albedo_texture = _soft_dot()
	look.roughness = 1.0
	puff.material = look

	var smoke := GPUParticles3D.new()
	smoke.name = "Smoke"
	smoke.amount = 18
	smoke.lifetime = 5.0
	smoke.process_material = motion
	smoke.draw_pass_1 = puff
	smoke.position = Vector3(0.0, 0.75, -0.03)
	smoke.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 9, 8))
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return smoke


# A small round blob that's solid in the middle and fades out at the edges
func _soft_dot() -> GradientTexture2D:
	var edge := Gradient.new()
	edge.set_color(0, Color(1, 1, 1, 1))
	edge.set_color(1, Color(1, 1, 1, 0))
	var dot := GradientTexture2D.new()
	dot.gradient = edge
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	dot.width = 64
	dot.height = 64
	return dot
