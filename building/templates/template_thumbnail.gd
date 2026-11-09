class_name TemplateThumbnail
extends Node
## Renders a template's picture for the build menu: the whole building fully built (see
## TemplateLook), seen from a front three-quarter view a little above, in low golden-hour sun
## with a cool sky fill and a rim of light from behind, tightly framed on a clear background.
## Takes a few frames; needs a screen (in a headless run there's no picture).

const SIZE := 512
const SAVED_SIZE := 256
## From the building's front (+Z, as for every piece) and right, a little above
const VIEW := Vector3(0.75, 0.5, 1.0)
## How much of the picture the building fills
const FILL := 0.94


## The picture (SAVED_SIZE square), or null without a screen
static func render(host: Node, registry: PieceRegistry, template: BuildingTemplate) -> Image:
	if DisplayServer.get_name() == "headless":
		return null
	var renderer := TemplateThumbnail.new()
	host.add_child(renderer)
	var image: Image = await renderer._render(registry, template)
	renderer.queue_free()
	return image


func _render(registry: PieceRegistry, template: BuildingTemplate) -> Image:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var view := VIEW.normalized()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.6, 0.66)
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)
	# Golden-hour sun: low, warm, from the front left
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.72, 0.45)
	sun.light_energy = 1.9
	sun.shadow_enabled = true
	viewport.add_child(sun)
	sun.look_at_from_position(Vector3(-1.0, 0.45, 0.8), Vector3.ZERO, Vector3.UP)
	# Cool sky fill from the right
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.68, 0.76, 1.0)
	fill.light_energy = 0.4
	viewport.add_child(fill)
	fill.look_at_from_position(Vector3(1.2, 0.6, -0.3), Vector3.ZERO, Vector3.UP)
	# Rim from behind, so the roofline stands out
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(1.0, 0.85, 0.65)
	rim.light_energy = 0.9
	viewport.add_child(rim)
	rim.look_at_from_position(-view * 2.0 + Vector3.UP, Vector3.ZERO, Vector3.UP)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	viewport.add_child(camera)
	var look := TemplateLook.build(registry, template)
	viewport.add_child(look)
	await get_tree().process_frame
	# Frame the building's box: only the close-up looks count (the far-off plain boxes are hidden)
	var box := AABB()
	var first := true
	for found in look.find_children("*", "MeshInstance3D", true, false):
		var mesh_look := found as MeshInstance3D
		if mesh_look.visibility_range_begin > 0.0 or mesh_look.mesh == null:
			continue
		var part := mesh_look.global_transform * mesh_look.get_aabb()
		box = part if first else box.merge(part)
		first = false
	var centre := box.get_center()
	camera.global_position = centre + view * (box.size.length() * 2.0 + 4.0)
	camera.look_at(centre, Vector3.UP)
	camera.far = box.size.length() * 4.0 + 20.0
	# Tight framing: the building's real outline on screen (its corners), centred
	var right := camera.global_basis.x
	var up := camera.global_basis.y
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for i in 8:
		var corner := box.get_endpoint(i) - centre
		var on_screen := Vector2(corner.dot(right), corner.dot(up))
		low = low.min(on_screen)
		high = high.max(on_screen)
	var middle := (low + high) / 2.0
	camera.global_position += right * middle.x + up * middle.y
	camera.size = maxf(high.x - low.x, high.y - low.y) / FILL
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	image.resize(SAVED_SIZE, SAVED_SIZE, Image.INTERPOLATE_LANCZOS)
	return image
