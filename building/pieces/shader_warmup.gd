class_name ShaderWarmup
extends Node3D
## Draws every look a building piece can have once, for a few frames, just in front of the camera
## and under a dark "getting ready" cover, when a world opens. The graphics card compiles each
## shader the first time something is drawn with it, which froze the game for a moment the first
## time a template was previewed or a piece was ghosted; doing it here, while the cover's up, means
## those first times are already over.
##
## Each look is drawn the way the game draws it (the same meshes, so the same vertex layout; the same
## shaders and settings): plain, close-up and simplified looks with their shadows, a look fading
## between distances, the template preview's glow overlay, the placement preview's and the ghosts'
## tints and outlines (PreviewLook) and the red take-down glow. The hybrid walls' baked far looks are
## prepared under the same cover (see _prepare_walls).

## Shapes covering every kind of piece surface (wood, roof, beam, post, stone) and a door
const SHAPES := ["wall", "floor", "roof", "beam_2", "pillar_wood", "foundation_stone", "door"]
## How many frames the looks stay drawn
const FRAMES := 6

var _cover: CanvasLayer


## Starts the warm-up (it removes itself when done)
static func run(parent: Node, registry: PieceRegistry) -> void:
	if DisplayServer.get_name() == "headless" or registry == null:
		return
	var warmup := ShaderWarmup.new()
	parent.add_child(warmup)
	warmup._start(registry)


func _start(registry: PieceRegistry) -> void:
	var timing := SpikeLog.begin()
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		queue_free()
		return
	_cover = CanvasLayer.new()
	_cover.layer = 120
	var dark := ColorRect.new()
	dark.color = Color(0.06, 0.05, 0.04)
	dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.add_child(dark)
	var words := Label.new()
	words.text = "Getting the valley ready…"
	words.set_anchors_preset(Control.PRESET_CENTER)
	words.grow_horizontal = Control.GROW_DIRECTION_BOTH
	words.grow_vertical = Control.GROW_DIRECTION_BOTH
	words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dark.add_child(words)
	add_child(_cover)

	var looks := _looks(registry)
	# A small grid, 3 m in front of the camera, each look shrunk to fit its square
	var ahead := -camera.global_basis.z
	var right := camera.global_basis.x
	var up := camera.global_basis.y
	var across := ceili(sqrt(float(looks.size())))
	var cell := 0.25
	for i in looks.size():
		var look: Node3D = looks[i]
		var col := i % across - across / 2.0
		var row := i / across - across / 2.0
		var spot := camera.global_position + ahead * 3.0 + right * col * cell + up * row * cell
		add_child(look)
		look.global_transform = Transform3D(camera.global_basis.scaled(Vector3.ONE * cell * 0.25), spot)
	SpikeLog.end("shader warm-up set up", timing)
	for i in FRAMES:
		await get_tree().process_frame
	await _prepare_walls(registry, words)
	queue_free()


## Every hybrid wall's far look made while the cover's up (see WallBaker): one shape a frame, read
## from the bake cache or queued to bake, then the cover waits for the baking to finish (only on the
## first run, or after the look code changes), counting down the shapes left
const BAKE_WAIT_LIMIT := 120.0


func _prepare_walls(registry: PieceRegistry, words: Label) -> void:
	var baker := registry.baker
	# (the player stays where they are while the cover's up: it can be several seconds)
	var player := get_tree().get_first_node_in_group("player")
	var held := {}
	if player:
		held = {"physics": player.is_physics_processing(), "input": player.is_processing_input(), "unhandled": player.is_processing_unhandled_input()}
		player.set_physics_process(false)
		player.set_process_input(false)
		player.set_process_unhandled_input(false)
	for shape in WallBaker.all_shapes():
		baker.far_material(shape, 0)
		await get_tree().process_frame
	var started := Time.get_ticks_msec()
	while not baker.is_idle() and Time.get_ticks_msec() - started < BAKE_WAIT_LIMIT * 1000.0:
		words.text = "Getting the valley ready…\nPreparing walls: %d left" % baker.remaining()
		await get_tree().process_frame
	if is_instance_valid(player):
		player.set_physics_process(held["physics"])
		player.set_process_input(held["input"])
		player.set_process_unhandled_input(held["unhandled"])


func _looks(registry: PieceRegistry) -> Array:
	var looks: Array = []
	var template_glow := ShaderMaterial.new()
	template_glow.shader = BuildPiece.GHOST_SHADER
	var take_down := StandardMaterial3D.new()
	take_down.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	take_down.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	take_down.cull_mode = BaseMaterial3D.CULL_DISABLED
	for shape in SHAPES:
		var meshes: Array = [registry.shape_of(shape).get("mesh")]
		var detail := registry.detail_mesh(shape, 0)
		var mid := registry.mid_mesh(shape, 0)
		for key in ["mesh", "door_mesh"]:
			meshes.append(detail.get(key))
			meshes.append(mid.get(key))
		var surface := registry.material_for(shape)
		for i in meshes.size():
			var mesh: Mesh = meshes[i]
			if mesh == null:
				continue
			# The plain box uses the surface material; the close-up and simplified looks the detail one
			var own: Material = surface if i == 0 else registry.detail_material()
			looks.append(_look(mesh, own, GeometryInstance3D.SHADOW_CASTING_SETTING_ON))
			looks.append(_look(mesh, own, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY))
			# Its own look, and with the template preview's glow over it
			looks.append_array(_with_fades(mesh, own, null))
			looks.append_array(_with_fades(mesh, own, template_glow))
			# The placement preview's and the ghosts' tint and outline over its own look (see
			# PreviewLook), and the red take-down glow
			for state in PreviewLook.State.values():
				looks.append_array(_with_fades(mesh, own, PreviewLook.overlay(state)))
			looks.append_array(_with_fades(mesh, take_down, null))
		# Furniture and anything else drawn with the plain painted colours
		looks.append(_look(meshes[0], registry.wood_material(), GeometryInstance3D.SHADOW_CASTING_SETTING_ON))
	looks.append_array(_template_extras(template_glow))
	return looks


# A look drawn plainly, and caught partway through fading out: about 3 m away with its range ending
# near there (two, as the fade runs either just before or just after the end distance)
static func _with_fades(mesh: Mesh, material: Material, overlay: Material) -> Array:
	var looks: Array = []
	for end in [0.0, 2.0, 4.0]:
		var look := _look(mesh, material, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		look.material_overlay = overlay
		if end > 0.0:
			look.visibility_range_end = end
			look.visibility_range_end_margin = 2.0
			look.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		looks.append(look)
	return looks


# The rest of what a template preview draws: the plot outline on the ground (see Plot.setup and
# Plot.rebuild), its floating name and size, and the workbenches, chests and campfires templates
# hold, plain (as laid-out ghosts) and with the glow over them
static func _template_extras(template_glow: Material) -> Array:
	var looks: Array = []
	var outline_look := StandardMaterial3D.new()
	outline_look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline_look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outline_look.cull_mode = BaseMaterial3D.CULL_DISABLED
	outline_look.vertex_color_use_as_albedo = true
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in [Vector3(-1, -1, 0), Vector3(1, -1, 0), Vector3(1, 1, 0), Vector3(-1, -1, 0), Vector3(1, 1, 0), Vector3(-1, 1, 0)]:
		st.set_color(Color(1, 1, 1, 0.5))
		st.add_vertex(p)
	looks.append(_look(st.commit(), outline_look, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF))
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.font_size = 30
	label.outline_size = 9
	label.outline_modulate = Color(0.08, 0.05, 0.03, 0.9)
	label.text = "Plot · 8 × 8 m"
	looks.append(label)
	var seen := {}
	for template in BuildingTemplate.load_all():
		for item in (template as BuildingTemplate).items:
			var buildable: Buildable = item["buildable"]
			if buildable is PieceBuildable or buildable == null or seen.has(buildable.resource_path):
				continue
			seen[buildable.resource_path] = true
			# Its own look, with the glow over it, and as a ghost
			for way in 3:
				var building := TemplateLook.building_look(buildable)
				for found in building.find_children("*", "GeometryInstance3D", true, false):
					if way == 1:
						(found as GeometryInstance3D).material_overlay = template_glow
					elif way == 2:
						(found as GeometryInstance3D).material_overlay = PreviewLook.overlay(PreviewLook.State.GHOST_FADE)
				looks.append(building)
	return looks


static func _look(mesh: Mesh, material: Material, shadows: GeometryInstance3D.ShadowCastingSetting) -> MeshInstance3D:
	var look := MeshInstance3D.new()
	look.mesh = mesh
	look.material_override = material
	look.cast_shadow = shadows
	return look
