@tool
extends Node3D
## The wreck of the Brass Lark, the refugee airship the player arrives on.
##
## The valley picks a flat, dry spot for it, clears the trees around it, and calls settle()
## to set each piece down on the ground. Every direct child of this node counts as one
## piece: its height in this scene is how far above (or below, if negative) the ground it sits.

## How far around the wreck to keep clear of trees and boulders, in meters
@export var clear_radius := 45.0
## How much deeper than its layout the wreck sinks into the ground, in meters
@export var dig_in := 0.3

# The rigging: each rope runs from one point to the next (in this scene's own coordinates),
# sagging by the given amount in the middle. "rope" is hemp, "cable" is thin iron wire.
# Lines whose points all sit at ground height are ropes trailing loose in the mud.
const RIGGING := [
	# Still tied between the gondola's rail and the envelope
	{"points": [Vector3(-3.9, 4.0, -3), Vector3(-8.5, 7.0, -2)], "sag": 0.4, "kind": "rope"},
	{"points": [Vector3(-3.9, 4.0, 1), Vector3(-8.0, 8.3, 4)], "sag": 0.6, "kind": "rope"},
	{"points": [Vector3(-3.9, 4.0, 5), Vector3(-7.8, 9.2, 10)], "sag": 0.8, "kind": "rope"},
	{"points": [Vector3(1.9, 5.4, -1), Vector3(-10.5, 9.2, 2)], "sag": 0.4, "kind": "rope"},
	{"points": [Vector3(-3.9, 4.0, -6), Vector3(-6.5, 3.8, -9)], "sag": 0.3, "kind": "rope"},
	{"points": [Vector3(2.5, 3.5, 13), Vector3(-6.8, 8.0, 14)], "sag": 1.2, "kind": "rope"},
	# Torn loose: hanging from the envelope and trailing off across the ground
	{"points": [Vector3(-6.4, 7.5, 16), Vector3(-1.5, 0.06, 19)], "sag": 2.0, "kind": "rope"},
	{"points": [Vector3(-1.5, 0.06, 19), Vector3(3, 0.06, 22), Vector3(6, 0.06, 20.5)], "sag": 0.0, "kind": "rope"},
	{"points": [Vector3(-3.9, 4.0, -5), Vector3(-4.2, 0.06, -6.5)], "sag": 0.5, "kind": "rope"},
	{"points": [Vector3(-4.2, 0.06, -6.5), Vector3(-3.6, 0.06, -9.5), Vector3(-1.8, 0.06, -11)], "sag": 0.0, "kind": "rope"},
	{"points": [Vector3(6.5, 0.06, 21), Vector3(9.5, 0.06, 23.5), Vector3(10, 0.06, 26)], "sag": 0.0, "kind": "rope"},
	# Snapped iron cables, dangling with nothing on the end
	{"points": [Vector3(-6.2, 6.5, 0), Vector3(-4.8, 2.2, 0.8)], "sag": 0.15, "kind": "cable"},
	{"points": [Vector3(-5.6, 4.6, 8), Vector3(-4.6, 1.0, 7.4)], "sag": 0.1, "kind": "cable"},
	{"points": [Vector3(-7.5, 9.5, 20), Vector3(-5.8, 4.5, 21)], "sag": 0.2, "kind": "cable"},
]

## How many crows circle over the wreck
@export var crow_count := 6

@onready var smoke_vent: Node3D = $Engine/SmokeVent

var _ember_light: OmniLight3D
# Each crow: [the bird, how far out it circles, how high, how fast, where on the circle it started]
var _crows := []


func _ready() -> void:
	_make_smoke()
	_make_embers()
	_make_crows()
	_make_rigging()


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	# The embers' glow flickers like the campfire's
	if _ember_light:
		_ember_light.light_energy = 1.1 + (sin(t * 11.0) + sin(t * 6.7)) * 0.25

	# Crows wheel slowly overhead, bobbing up and down and flapping now and then
	for crow in _crows:
		var bird: Node3D = crow[0]
		var angle: float = crow[4] + t * crow[3]
		var radius: float = crow[1] + sin(t * 0.3 + crow[4]) * 3.0
		bird.position = Vector3(cos(angle) * radius, crow[2] + sin(t * 0.7 + crow[4]) * 1.5, sin(angle) * radius)
		# Face the way it's flying (around the circle)
		bird.rotation.y = PI - angle if crow[3] > 0.0 else -angle
		# Mostly gliding, with bursts of flapping
		var flapping := maxf(sin(t * 0.9 + crow[4] * 3.0), 0.0)
		bird.scale.y = 1.0 + sin(t * 14.0 + crow[4]) * 0.9 * flapping


## Sets every piece of the wreck down on the valley's ground. The ship's own parts (hulls,
## envelope, engine, crates, rigging...) sink an extra `dig_in` meters, so it looks like it
## plowed into the ground; salvage piles and the player's start point sit right on top.
func settle(valley) -> void:
	for child in get_children():
		var piece := child as Node3D
		# The flatten marker reshapes the ground itself, so it stays put
		if piece == null or piece.is_in_group("terrain_modifiers"):
			continue
		# Remember the height it was given in the scene, so settling twice doesn't stack up
		if not piece.has_meta("ground_offset"):
			piece.set_meta("ground_offset", piece.position.y)
		var offset := float(piece.get_meta("ground_offset"))
		if not (piece.has_method("gather") or piece is Marker3D):
			offset -= dig_in
		var spot := piece.global_position
		spot.y = valley.get_height(spot.x, spot.z) + offset
		piece.global_position = spot


## Where the player starts: just beside the wreck
func spawn_point() -> Vector3:
	return $PlayerSpawn.global_position


## What the player is facing when they start: the intact half of the hull
func spawn_look_target() -> Vector3:
	return $HullIntact.global_position


## Where the ground is scorched black: around the broken boiler
func scorch_point() -> Vector2:
	var boiler: Vector3 = $Engine.global_position
	return Vector2(boiler.x, boiler.z)


# Builds every rope and cable in RIGGING out of short straight pieces that follow a sag
func _make_rigging() -> void:
	if has_node("Rigging"):
		return
	var rigging := Node3D.new()
	rigging.name = "Rigging"
	add_child(rigging)

	var rope_look := StandardMaterial3D.new()
	rope_look.albedo_color = Color(0.42, 0.35, 0.24)
	rope_look.roughness = 1.0
	var cable_look := StandardMaterial3D.new()
	cable_look.albedo_color = Color(0.12, 0.11, 0.1)
	cable_look.metallic = 0.7
	cable_look.roughness = 0.5
	var rope_piece := CylinderMesh.new()
	rope_piece.top_radius = 0.035
	rope_piece.bottom_radius = 0.035
	rope_piece.height = 1.0
	rope_piece.radial_segments = 5
	rope_piece.rings = 1
	rope_piece.material = rope_look
	var cable_piece := rope_piece.duplicate() as CylinderMesh
	cable_piece.top_radius = 0.02
	cable_piece.bottom_radius = 0.02
	cable_piece.material = cable_look

	for line in RIGGING:
		var points: Array = line["points"]
		var piece: Mesh = cable_piece if line["kind"] == "cable" else rope_piece
		for i in points.size() - 1:
			# Each span between two points droops in a gentle curve, made of 8 straight bits
			var start: Vector3 = points[i]
			var end: Vector3 = points[i + 1]
			var steps := 8 if line["sag"] > 0.0 else 1
			var previous := start
			for s in range(1, steps + 1):
				var t := float(s) / steps
				var next := start.lerp(end, t) - Vector3(0, line["sag"] * 4.0 * t * (1.0 - t), 0)
				rigging.add_child(_rope_segment(previous, next, piece))
				previous = next


# One straight bit of rope from a to b: a thin cylinder stretched and turned to fit
func _rope_segment(a: Vector3, b: Vector3, piece: Mesh) -> MeshInstance3D:
	var along := b - a
	var up := along.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var segment := MeshInstance3D.new()
	segment.mesh = piece
	segment.transform = Transform3D(Basis(side, up * along.length(), side.cross(up)), (a + b) * 0.5)
	return segment


# Thin grey smoke curling up from the broken engine and drifting off on the breeze
func _make_smoke() -> void:
	if smoke_vent.has_node("Smoke"):
		return
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = 0.2
	motion.direction = Vector3.UP
	motion.spread = 10.0
	motion.initial_velocity_min = 0.6
	motion.initial_velocity_max = 1.0
	# Pushed upward and sideways, as if by warm air and a light breeze
	motion.gravity = Vector3(0.22, 0.3, 0.08)
	motion.damping_min = 0.05
	motion.damping_max = 0.1
	motion.angle_min = -180.0
	motion.angle_max = 180.0
	motion.scale_min = 0.7
	motion.scale_max = 1.1
	# Each puff swells as it rises...
	var grow := Curve.new()
	grow.max_value = 4.0
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 3.5))
	var grow_texture := CurveTexture.new()
	grow_texture.curve = grow
	motion.scale_curve = grow_texture
	# ...and fades in, then thins away to nothing
	var fade := Gradient.new()
	fade.set_color(0, Color(0.3, 0.29, 0.28, 0.0))
	fade.set_color(1, Color(0.6, 0.6, 0.6, 0.0))
	fade.add_point(0.12, Color(0.28, 0.27, 0.26, 0.5))
	fade.add_point(0.55, Color(0.45, 0.44, 0.43, 0.22))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	motion.color_ramp = fade_texture

	var puff := QuadMesh.new()
	puff.size = Vector2(1.0, 1.0)
	var look := StandardMaterial3D.new()
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.vertex_color_use_as_albedo = true
	look.albedo_texture = _soft_dot()
	look.roughness = 1.0
	puff.material = look

	var smoke := GPUParticles3D.new()
	smoke.name = "Smoke"
	smoke.amount = 40
	smoke.lifetime = 9.0
	# Start the game already smoking instead of with a first puff
	smoke.preprocess = 9.0
	smoke.process_material = motion
	smoke.draw_pass_1 = puff
	smoke.visibility_aabb = AABB(Vector3(-10, -2, -10), Vector3(20, 32, 20))
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke_vent.add_child(smoke)


# Glowing sparks drifting up from the engine, plus a faint orange light that flickers
func _make_embers() -> void:
	if smoke_vent.has_node("Embers"):
		return
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents = Vector3(0.9, 0.3, 0.9)
	motion.direction = Vector3.UP
	motion.spread = 30.0
	motion.initial_velocity_min = 0.3
	motion.initial_velocity_max = 1.2
	motion.gravity = Vector3(0.1, 0.5, 0.0)
	motion.turbulence_enabled = true
	motion.turbulence_noise_strength = 0.6
	motion.scale_min = 0.6
	motion.scale_max = 1.4
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.7, 0.3, 1.0))
	fade.set_color(1, Color(0.6, 0.1, 0.0, 0.0))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	motion.color_ramp = fade_texture

	var spark := QuadMesh.new()
	spark.size = Vector2(0.05, 0.05)
	var look := StandardMaterial3D.new()
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.vertex_color_use_as_albedo = true
	look.albedo_texture = _soft_dot()
	# Brighter than white, so the glow effect makes them shine
	look.albedo_color = Color(3.0, 2.0, 1.2)
	spark.material = look

	var embers := GPUParticles3D.new()
	embers.name = "Embers"
	embers.amount = 26
	embers.lifetime = 2.2
	embers.preprocess = 2.0
	embers.process_material = motion
	embers.draw_pass_1 = spark
	embers.position = Vector3(0, -1.2, 0)
	embers.visibility_aabb = AABB(Vector3(-4, -2, -4), Vector3(8, 8, 8))
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke_vent.add_child(embers)

	_ember_light = OmniLight3D.new()
	_ember_light.name = "EmberLight"
	_ember_light.light_color = Color(1.0, 0.5, 0.2)
	_ember_light.omni_range = 5.0
	_ember_light.position = Vector3(0, -1.0, 0)
	smoke_vent.add_child(_ember_light)


# A handful of black birds, each just a pair of swept-back wings
func _make_crows() -> void:
	if has_node("Crows"):
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Body in the middle, wing tips out to each side and slightly raised, pointing back
	for side in [-1.0, 1.0]:
		st.add_vertex(Vector3(0, 0, -0.25))
		st.add_vertex(Vector3(side * 0.55, 0.08, 0.15))
		st.add_vertex(Vector3(0, 0, 0.2))
	var wings := st.commit()
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.03, 0.03, 0.035)
	black.cull_mode = BaseMaterial3D.CULL_DISABLED
	black.roughness = 0.8

	var flock := Node3D.new()
	flock.name = "Crows"
	add_child(flock)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in crow_count:
		var bird := MeshInstance3D.new()
		bird.mesh = wings
		bird.material_override = black
		bird.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flock.add_child(bird)
		var direction := 1.0 if rng.randf() > 0.3 else -1.0
		_crows.append([bird, rng.randf_range(10.0, 22.0), rng.randf_range(20.0, 30.0), rng.randf_range(0.12, 0.22) * direction, rng.randf() * TAU])


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
