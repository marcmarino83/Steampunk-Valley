class_name FireEffects
extends RefCounted
## Fire and smoke made from particles, for fires built into pieces (the fireplace and its chimney).
##
##   make_fire(size): a layered flame: wide orange-red licks round a tight yellow-white core,
##     flickering as they rise and burn out, with a few sparks drifting up. `size` scales it
##     (1 = a hearth about half a meter across). Glows on its own (unshaded, added on top).
##   make_smoke(): soft light grey smoke that's lit by the scene (it takes the sun and sky light
##     from behind as well as in front, so it never goes dark), widening and fading as it rises.


static func make_fire(size := 1.0) -> Node3D:
	var fire := Node3D.new()
	fire.name = "Fire"
	# The outer flames: orange licks that rise, sway and burn out red
	fire.add_child(_flames("Licks", size, 0.13, 0.42, 0.55, 22,
			[Color(1.0, 0.62, 0.22, 0.0), Color(1.0, 0.5, 0.12, 0.55), Color(0.9, 0.26, 0.04, 0.4), Color(0.5, 0.06, 0.0, 0.0)],
			Color(1.3, 0.95, 0.6), Vector2(0.13, 0.34)))
	# The core: smaller, brighter, yellow-white, low in the fire
	fire.add_child(_flames("Core", size, 0.07, 0.25, 0.35, 14,
			[Color(1.0, 0.95, 0.7, 0.0), Color(1.0, 0.86, 0.5, 0.6), Color(1.0, 0.66, 0.22, 0.4), Color(1.0, 0.45, 0.1, 0.0)],
			Color(1.5, 1.2, 0.8), Vector2(0.09, 0.2)))
	fire.add_child(_embers(size))
	return fire


# One layer of flame: glowing blobs rising from a small disc, swelling then shrinking
static func _flames(layer: String, size: float, radius: float, speed: float, life: float, amount: int, colors: Array, glow: Color, blob_size: Vector2) -> GPUParticles3D:
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = radius * size
	motion.direction = Vector3.UP
	motion.spread = 10.0
	motion.initial_velocity_min = speed * size * 0.8
	motion.initial_velocity_max = speed * size * 1.3
	motion.gravity = Vector3(0.0, 0.8 * size, 0.0)
	# A little sideways sway, so the flame flickers rather than streams
	motion.turbulence_enabled = true
	motion.turbulence_noise_strength = 0.4
	motion.turbulence_noise_scale = 2.5
	motion.turbulence_influence_min = 0.05
	motion.turbulence_influence_max = 0.15
	motion.angle_min = -180.0
	motion.angle_max = 180.0
	motion.scale_min = 0.75
	motion.scale_max = 1.25
	var shape := Curve.new()
	shape.add_point(Vector2(0.0, 0.55))
	shape.add_point(Vector2(0.25, 1.0))
	shape.add_point(Vector2(1.0, 0.1))
	var shape_texture := CurveTexture.new()
	shape_texture.curve = shape
	motion.scale_curve = shape_texture
	var burn := Gradient.new()
	burn.set_color(0, colors[0])
	burn.set_color(1, colors[3])
	burn.add_point(0.12, colors[1])
	burn.add_point(0.55, colors[2])
	var burn_texture := GradientTexture1D.new()
	burn_texture.gradient = burn
	motion.color_ramp = burn_texture
	var blob := QuadMesh.new()
	blob.size = blob_size * size
	var look := StandardMaterial3D.new()
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.vertex_color_use_as_albedo = true
	look.albedo_texture = soft_dot()
	look.albedo_color = glow
	blob.material = look
	var flames := GPUParticles3D.new()
	flames.name = layer
	flames.amount = amount
	flames.lifetime = life
	flames.local_coords = true
	flames.process_material = motion
	flames.draw_pass_1 = blob
	flames.visibility_aabb = AABB(Vector3(-1, -0.3, -1) * size, Vector3(2, 2, 2) * size)
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return flames


# A few sparks drifting up out of the fire and winking out
static func _embers(size: float) -> GPUParticles3D:
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = 0.1 * size
	motion.direction = Vector3.UP
	motion.spread = 20.0
	motion.initial_velocity_min = 0.4 * size
	motion.initial_velocity_max = 0.9 * size
	motion.gravity = Vector3(0.02, 0.3, 0.0)
	motion.turbulence_enabled = true
	motion.turbulence_noise_strength = 0.6
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.8, 0.4, 1.0))
	fade.set_color(1, Color(0.7, 0.15, 0.0, 0.0))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	motion.color_ramp = fade_texture
	var spark := QuadMesh.new()
	spark.size = Vector2(0.025, 0.025) * size
	var look := StandardMaterial3D.new()
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.vertex_color_use_as_albedo = true
	look.albedo_texture = soft_dot()
	look.albedo_color = Color(3.0, 2.0, 1.2)
	spark.material = look
	var embers := GPUParticles3D.new()
	embers.name = "Embers"
	embers.amount = 6
	embers.lifetime = 1.6
	embers.process_material = motion
	embers.draw_pass_1 = spark
	embers.position = Vector3(0, 0.12 * size, 0)
	embers.visibility_aabb = AABB(Vector3(-2, -0.5, -2), Vector3(4, 4, 4))
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return embers


static func make_smoke() -> GPUParticles3D:
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = 0.08
	motion.direction = Vector3.UP
	motion.spread = 8.0
	motion.initial_velocity_min = 0.45
	motion.initial_velocity_max = 0.7
	# Rising, slowing and drifting slightly with a light breeze
	motion.gravity = Vector3(0.12, 0.05, 0.04)
	motion.damping_min = 0.05
	motion.damping_max = 0.1
	motion.angle_min = -180.0
	motion.angle_max = 180.0
	motion.angular_velocity_min = -12.0
	motion.angular_velocity_max = 12.0
	var grow := Curve.new()
	grow.max_value = 5.0
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 4.0))
	var grow_texture := CurveTexture.new()
	grow_texture.curve = grow
	motion.scale_curve = grow_texture
	var fade := Gradient.new()
	fade.set_color(0, Color(0.82, 0.81, 0.8, 0.0))
	fade.set_color(1, Color(0.92, 0.92, 0.92, 0.0))
	fade.add_point(0.08, Color(0.8, 0.79, 0.78, 0.42))
	fade.add_point(0.5, Color(0.86, 0.86, 0.86, 0.22))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	motion.color_ramp = fade_texture
	var puff := QuadMesh.new()
	puff.size = Vector2(0.5, 0.5)
	var look := StandardMaterial3D.new()
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.vertex_color_use_as_albedo = true
	look.albedo_texture = soft_dot()
	look.roughness = 1.0
	look.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# Light passes through it, so it's lit from behind as well as in front and never goes dark
	look.backlight_enabled = true
	look.backlight = Color(0.75, 0.75, 0.75)
	look.disable_receive_shadows = true
	puff.material = look
	var smoke := GPUParticles3D.new()
	smoke.name = "Smoke"
	smoke.amount = 34
	smoke.lifetime = 6.5
	smoke.process_material = motion
	smoke.draw_pass_1 = puff
	smoke.visibility_aabb = AABB(Vector3(-5, -1, -5), Vector3(10, 11, 10))
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return smoke


## A small round blob that's solid in the middle and fades out at the edges
static func soft_dot() -> GradientTexture2D:
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
