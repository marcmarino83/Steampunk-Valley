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
## between distances, the template preview's glow overlay, the grey ghost (and the brighter
## targeted one), the see-through placing preview and the red take-down glow.

## Shapes covering every kind of piece surface (wood, roof, beam, post, stone) and a door
const SHAPES := ["wall", "floor", "roof", "beam_1", "pillar_wood", "foundation_stone", "door"]
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
		var look: GeometryInstance3D = looks[i]
		var col := i % across - across / 2.0
		var row := i / across - across / 2.0
		var spot := camera.global_position + ahead * 3.0 + right * col * cell + up * row * cell
		add_child(look)
		look.global_transform = Transform3D(camera.global_basis.scaled(Vector3.ONE * cell * 0.25), spot)
	SpikeLog.end("shader warm-up set up", timing)
	for i in FRAMES:
		await get_tree().process_frame
	queue_free()


func _looks(registry: PieceRegistry) -> Array:
	var looks: Array = []
	var template_glow := ShaderMaterial.new()
	template_glow.shader = BuildPiece.GHOST_SHADER
	var placing := StandardMaterial3D.new()
	placing.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	placing.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	placing.cull_mode = BaseMaterial3D.CULL_DISABLED
	var take_down := placing.duplicate()
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
			# About 3 m away with its range ending near there, so it's caught partway through fading
			# out (two, as the fade runs either just before or just after the end distance)
			for end in [2.0, 4.0]:
				var fading := _look(mesh, own, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
				fading.visibility_range_end = end
				fading.visibility_range_end_margin = 2.0
				fading.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				looks.append(fading)
			var previewed := _look(mesh, own, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			previewed.material_overlay = template_glow
			looks.append(previewed)
			for ghost in [BuildPiece.ghost_material(false), BuildPiece.ghost_material(true), placing, take_down]:
				looks.append(_look(mesh, ghost, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF))
		# Furniture and anything else drawn with the plain painted colours
		looks.append(_look(meshes[0], registry.wood_material(), GeometryInstance3D.SHADOW_CASTING_SETTING_ON))
	return looks


static func _look(mesh: Mesh, material: Material, shadows: GeometryInstance3D.ShadowCastingSetting) -> MeshInstance3D:
	var look := MeshInstance3D.new()
	look.mesh = mesh
	look.material_override = material
	look.cast_shadow = shadows
	return look
