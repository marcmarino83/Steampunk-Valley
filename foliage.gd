@tool
extends Node3D
## Grass, ferns and boulders. The valley creates this and tells it about itself.
##
## Boulders are scattered once over the whole map. Grass and ferns are far too many to
## make everywhere at once, so they're only grown in the chunks near the camera,
## and cleared away again once you've walked off.

## How far from you grass is drawn, in meters
@export var grass_distance := 80.0
## Grass clumps per square meter, where it grows thickest
@export var grass_density := 2.5
## Ferns per square meter
@export var fern_density := 0.05
## How many boulders to scatter over the whole map
@export var rock_count := 4000

const PLANT_SHADER = preload("res://plant.gdshader")

## The valley this grows on. Set before adding this to the scene.
var valley

var _grass_mesh: ArrayMesh
var _fern_mesh: ArrayMesh
var _plant_material: ShaderMaterial
# Which chunks have plants right now: chunk (x, z) -> the node holding them
var _patches := {}
var _patch_noise := FastNoiseLite.new()


func _ready() -> void:
	_grass_mesh = _make_grass_clump()
	_fern_mesh = _make_fern()
	_plant_material = ShaderMaterial.new()
	_plant_material.shader = PLANT_SHADER
	_patch_noise.frequency = 0.035


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or valley == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var here := Vector2(camera.global_position.x, camera.global_position.z)
	var center: Vector2i = valley.chunk_at(here.x, here.y)

	# Grow the nearest chunk that needs plants. Just one per frame, so walking around stays smooth.
	var best := Vector2i.ZERO
	var best_distance := INF
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var chunk := center + Vector2i(dx, dz)
			if _patches.has(chunk) or not valley.has_chunk(chunk):
				continue
			var distance := _distance_to_chunk(chunk, here)
			if distance < grass_distance and distance < best_distance:
				best = chunk
				best_distance = distance
	if best_distance < INF:
		_patches[best] = _grow_patch(best)

	# Clear away chunks you've left well behind
	for chunk in _patches.keys():
		if _distance_to_chunk(chunk, here) > grass_distance + 60.0:
			_patches[chunk].queue_free()
			_patches.erase(chunk)


func _distance_to_chunk(chunk: Vector2i, here: Vector2) -> float:
	var rect: Rect2 = valley.chunk_rect(chunk)
	var nearest := Vector2(clampf(here.x, rect.position.x, rect.end.x), clampf(here.y, rect.position.y, rect.end.y))
	return nearest.distance_to(here)


# Scatters grass and ferns over one chunk
func _grow_patch(chunk: Vector2i) -> Node3D:
	var rect: Rect2 = valley.chunk_rect(chunk)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chunk)
	var dry_above: float = valley.water_height() + 0.15

	var grass_spots: Array[Transform3D] = []
	var grass_tints: Array[Color] = []
	for i in int(rect.get_area() * grass_density):
		var x := rect.position.x + rng.randf() * rect.size.x
		var z := rect.position.y + rng.randf() * rect.size.y
		var h: float = valley.get_height(x, z)
		# Not underwater, not on ground steep enough to be bare rock, and not under the wreck
		if h < dry_above or valley.get_normal(x, z).y < 0.72 or valley.is_near_crash_site(x, z, 0.5):
			continue
		# Leave a little clear ground around trees and resources, so things you can gather stand out
		if valley.is_spot_taken(x, z, 1.2) or valley.trail_amount(x, z) > 0.35 or valley.is_cleared(x, z, "plants"):
			continue
		# Thick in some places, thin in others
		if rng.randf() > smoothstep(-0.8, 0.1, _patch_noise.get_noise_2d(x, z)):
			continue
		var size := rng.randf_range(0.6, 1.3)
		grass_spots.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size), Vector3(x, h - 0.05, z)))
		var shade := rng.randf_range(0.8, 1.15)
		grass_tints.append(Color(shade * rng.randf_range(0.95, 1.1), shade, shade * 0.85))

	var fern_spots: Array[Transform3D] = []
	var fern_tints: Array[Color] = []
	for i in int(rect.get_area() * fern_density):
		var x := rect.position.x + rng.randf() * rect.size.x
		var z := rect.position.y + rng.randf() * rect.size.y
		var h: float = valley.get_height(x, z)
		if h < dry_above or valley.get_normal(x, z).y < 0.7 or valley.is_near_crash_site(x, z, 0.5) or valley.is_spot_taken(x, z, 1.2) or valley.trail_amount(x, z) > 0.2 or valley.is_on_trail(x, z, 0.0) or valley.is_cleared(x, z, "plants"):
			continue
		var size := rng.randf_range(0.7, 1.4)
		fern_spots.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size), Vector3(x, h - 0.05, z)))
		var shade := rng.randf_range(0.5, 0.75)
		fern_tints.append(Color(shade * 0.8, shade * 1.1, shade * 0.6))

	var patch := Node3D.new()
	patch.add_child(_make_scatter(_grass_mesh, grass_spots, grass_tints, _plant_material, false, grass_distance))
	patch.add_child(_make_scatter(_fern_mesh, fern_spots, fern_tints, _plant_material, true, grass_distance))
	add_child(patch)
	return patch


## Scatters boulders over the whole map, mostly on steep slopes where the ground turns rocky
func build_rocks(material: Material) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = valley.map_seed + 99
	var bounds: Rect2 = valley.map_rect()
	var spots: Array[Transform3D] = []
	var tints: Array[Color] = []
	var tries := 0
	while spots.size() < rock_count and tries < rock_count * 20:
		tries += 1
		var x := bounds.position.x + rng.randf() * bounds.size.x
		var z := bounds.position.y + rng.randf() * bounds.size.y
		var steepness: float = 1.0 - valley.get_normal(x, z).y
		# A few anywhere, lots where it's steep
		if rng.randf() > 0.03 + smoothstep(0.1, 0.35, steepness) * 0.9 or valley.is_near_crash_site(x, z) or valley.is_on_trail(x, z, 1.0) or valley.is_cleared(x, z, "rocks"):
			continue
		# Lots of small rocks, a few big ones
		var size := pow(rng.randf(), 1.6) * 4.0 + 0.5
		var shape := Vector3(rng.randf_range(0.8, 1.5), rng.randf_range(0.45, 0.85), rng.randf_range(0.8, 1.5)) * size
		var turn := Basis.from_euler(Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3)))
		var h: float = valley.get_height(x, z)
		# Sink them partway into the ground so they look settled, not dropped
		spots.append(Transform3D(turn * Basis.from_scale(shape), Vector3(x, h - shape.y * 0.3, z)))
		tints.append(Color.WHITE)

	var rocks := _make_scatter(_make_rock(), spots, tints, material, true, 700.0)
	rocks.name = "Rocks"
	add_child(rocks)


# One draw call for thousands of copies of the same mesh ("MultiMesh")
func _make_scatter(mesh: Mesh, spots: Array[Transform3D], tints: Array[Color], material: Material, shadows: bool, view_distance: float) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = spots.size()
	for i in spots.size():
		multimesh.set_instance_transform(i, spots[i])
		multimesh.set_instance_color(i, tints[i])
	var scatter := MultiMeshInstance3D.new()
	scatter.multimesh = multimesh
	scatter.material_override = material
	scatter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Fade out at a distance instead of popping
	scatter.visibility_range_end = view_distance
	scatter.visibility_range_end_margin = 10.0
	scatter.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return scatter


# A clump of grass: a handful of thin, curved blades leaning different ways
func _make_grass_clump() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for blade in 12:
		var angle := rng.randf() * TAU
		var root := Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.0, 0.35)
		var facing := rng.randf() * TAU
		var side := Vector3(cos(facing), 0.0, sin(facing)) * 0.035
		var lean := Vector3(-sin(facing), 0.0, cos(facing)) * rng.randf_range(0.05, 0.28)
		var height := rng.randf_range(0.3, 0.75)
		var middle := root + lean * 0.35 + Vector3.UP * height * 0.55
		var tip := root + lean + Vector3.UP * height
		_add_triangle(st, [root - side, root + side, middle + side * 0.7], [0.0, 0.0, 0.55])
		_add_triangle(st, [root - side, middle + side * 0.7, middle - side * 0.7], [0.0, 0.55, 0.55])
		_add_triangle(st, [middle - side * 0.7, middle + side * 0.7, tip], [0.55, 0.55, 1.0])
	return st.commit()


# A fern: long fronds arching out from the middle, wide at the base and narrowing to a point
func _make_fern() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for frond in 7:
		var angle := TAU * frond / 7.0 + rng.randf_range(-0.2, 0.2)
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var across := Vector3(-out.z, 0.0, out.x)
		var length := rng.randf_range(0.6, 1.0)
		var previous := []
		for step in 6:
			var t := step / 5.0
			var spine := out * length * t + Vector3.UP * sin(t * PI * 0.8) * 0.5 * length
			var width := 0.17 * length * (1.0 - t * 0.85)
			var edge := [spine - across * width, spine + across * width, t]
			if step > 0:
				_add_triangle(st, [previous[0], previous[1], edge[1]], [previous[2], previous[2], t])
				_add_triangle(st, [previous[0], edge[1], edge[0]], [previous[2], t, t])
			previous = edge
	return st.commit()


# Plants are lit as if they face straight up, so they match the ground instead of flickering
func _add_triangle(st: SurfaceTool, points: Array, heights: Array) -> void:
	for i in 3:
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.0, heights[i]))
		st.add_vertex(points[i])


# A lumpy, flat-bottomed boulder: a ball pushed in and out by a noise pattern, with flat faces
func _make_rock() -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 10
	sphere.rings = 6
	var arrays := sphere.get_mesh_arrays()
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var order: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var noise := FastNoiseLite.new()
	noise.seed = 3
	noise.frequency = 0.9
	for i in points.size():
		var p := points[i] * (1.0 + noise.get_noise_3dv(points[i]) * 0.5)
		if p.y < -0.15:
			p.y = -0.15 + (p.y + 0.15) * 0.25
		points[i] = p
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in order:
		st.add_vertex(points[i])
	st.generate_normals()
	return st.commit()
