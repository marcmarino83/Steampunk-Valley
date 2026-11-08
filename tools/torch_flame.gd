extends Node3D
## The burning end of a held torch: a small flickering flame, a few embers drifting off, and a
## warm light. Sits at the top of the wrapped end (see held_effect on tools/torch.tres).

## How bright the light is on average, and how far it reaches
@export var light_energy := 1.6
@export var light_range := 9.0

var _flame_motion: ParticleProcessMaterial
var _light: OmniLight3D


func _ready() -> void:
	add_child(_make_flame())
	add_child(_make_embers())
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.65, 0.35)
	_light.omni_range = light_range
	_light.position = Vector3(0.0, 0.06, 0.0)
	add_child(_light)


func _process(_delta: float) -> void:
	# Flicker: wobbles at different speeds, so it never looks regular
	var t := Time.get_ticks_msec() * 0.001
	var flicker := sin(t * 11.0) * 0.5 + sin(t * 17.3) * 0.3 + sin(t * 4.1) * 0.2
	_light.light_energy = light_energy + flicker * 0.3
	# The flame moves with the torch, but always rises straight up, however the torch is tilted
	_flame_motion.gravity = global_basis.orthonormalized().inverse() * Vector3(0.0, 1.2, 0.0)
	_flame_motion.direction = (global_basis.orthonormalized().inverse() * Vector3.UP).normalized()


# Little licks of flame: soft glowing blobs that rise, shrink and burn out from yellow-white
# through orange to red, added on top of what's behind them so they glow
func _make_flame() -> GPUParticles3D:
	_flame_motion = ParticleProcessMaterial.new()
	_flame_motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_flame_motion.emission_sphere_radius = 0.025
	_flame_motion.direction = Vector3.UP
	_flame_motion.spread = 10.0
	_flame_motion.initial_velocity_min = 0.15
	_flame_motion.initial_velocity_max = 0.3
	_flame_motion.gravity = Vector3(0.0, 1.2, 0.0)
	_flame_motion.angle_min = -180.0
	_flame_motion.angle_max = 180.0
	_flame_motion.scale_min = 0.8
	_flame_motion.scale_max = 1.2
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 0.7))
	shrink.add_point(Vector2(0.25, 1.0))
	shrink.add_point(Vector2(1.0, 0.1))
	var shrink_texture := CurveTexture.new()
	shrink_texture.curve = shrink
	_flame_motion.scale_curve = shrink_texture
	var burn := Gradient.new()
	burn.set_color(0, Color(1.0, 0.9, 0.6, 0.0))
	burn.set_color(1, Color(0.7, 0.08, 0.0, 0.0))
	burn.add_point(0.1, Color(1.0, 0.8, 0.35, 0.9))
	burn.add_point(0.5, Color(1.0, 0.42, 0.08, 0.7))
	var burn_texture := GradientTexture1D.new()
	burn_texture.gradient = burn
	_flame_motion.color_ramp = burn_texture

	var blob := QuadMesh.new()
	blob.size = Vector2(0.07, 0.09)
	var look := _glow_material()
	look.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	look.albedo_color = Color(2.2, 1.6, 1.1)
	blob.material = look

	var flame := GPUParticles3D.new()
	flame.name = "Flame"
	flame.amount = 24
	flame.lifetime = 0.4
	flame.local_coords = true
	flame.process_material = _flame_motion
	flame.draw_pass_1 = blob
	flame.visibility_aabb = AABB(Vector3(-0.3, -0.2, -0.3), Vector3(0.6, 0.6, 0.6))
	return flame


# A few sparks breaking off and drifting away into the air, left behind as you move
func _make_embers() -> GPUParticles3D:
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = 0.03
	motion.direction = Vector3.UP
	motion.spread = 30.0
	motion.initial_velocity_min = 0.2
	motion.initial_velocity_max = 0.5
	motion.gravity = Vector3(0.03, 0.35, 0.0)
	motion.turbulence_enabled = true
	motion.turbulence_noise_strength = 0.3
	motion.scale_min = 0.6
	motion.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.75, 0.35, 1.0))
	fade.set_color(1, Color(0.6, 0.1, 0.0, 0.0))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	motion.color_ramp = fade_texture

	var spark := QuadMesh.new()
	spark.size = Vector2(0.012, 0.012)
	var look := _glow_material()
	look.albedo_color = Color(3.0, 2.0, 1.2)
	spark.material = look

	var embers := GPUParticles3D.new()
	embers.name = "Embers"
	embers.amount = 6
	embers.lifetime = 1.4
	embers.local_coords = false
	embers.process_material = motion
	embers.draw_pass_1 = spark
	embers.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 4, 4))
	return embers


func _glow_material() -> StandardMaterial3D:
	var edge := Gradient.new()
	edge.set_color(0, Color(1, 1, 1, 1))
	edge.set_color(1, Color(1, 1, 1, 0))
	var dot := GradientTexture2D.new()
	dot.gradient = edge
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	dot.width = 32
	dot.height = 32
	var look := StandardMaterial3D.new()
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.vertex_color_use_as_albedo = true
	look.albedo_texture = dot
	return look
