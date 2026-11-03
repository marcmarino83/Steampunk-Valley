@tool
extends StaticBody3D

## A grayscale heightmap: black is the lowest ground, white the highest
@export_file("*.png") var heightmap_path := "res://heightmap.png"
## The real-world elevation of pure black in the heightmap, in meters
@export var min_elevation := 42.0
## The real-world elevation of pure white in the heightmap, in meters
@export var max_elevation := 224.0
## Width of the world in meters, west to east. North to south follows the image's shape.
@export var world_size := 1500.0
## Stretches the hills taller. 1 = true to life, 2 = twice as tall.
@export var height_scale := 2.0
## The real-world elevation the water rises to, in meters. Anything lower is underwater.
@export var water_level := 63.0
## How much to smooth away the little stair-steps from the image (0 = none)
@export_range(0, 8) var smoothing := 3
@export var ground_material: Material
## Leave empty to use a plain see-through blue
@export var water_material: Material

@export_group("Chunks")
## Roughly how big each square piece of terrain is, in meters
@export var chunk_size := 64.0
## How many grid squares across each chunk. 32 squares in 64 m = a point every 2 m.
@export var chunk_cells := 32

@export_group("Trees")
@export var tree_scene: PackedScene
@export var tree_count := 4000
## Trees won't grow on ground steeper than this, in degrees
@export_range(0.0, 90.0) var max_tree_slope := 42.0
## Change this for a different layout of trees
@export var map_seed := 1

@export_group("")
## The player, who gets put on dry ground near the middle of the map when the game starts
@export var player_path: NodePath = ^"../Player"
## Tick this in the Inspector to rebuild after changing settings
@export var rebuild := false:
	set(value):
		if value and is_inside_tree():
			generate()

# The smoothed height of every grid point, in game meters above the lowest ground.
# Stored row by row, west to east, starting from the north edge.
var _heights := PackedFloat32Array()
var _points_x := 0
var _points_z := 0
var _chunks_x := 0
var _chunks_z := 0
# Meters between grid points, west-east and north-south
var _cell_x := 1.0
var _cell_z := 1.0
var _width := 0.0
var _depth := 0.0


func _ready() -> void:
	generate()
	if not Engine.is_editor_hint():
		_place_player()


## How high the water surface sits, in game meters
func water_height() -> float:
	return (water_level - min_elevation) * height_scale


## How high the ground is at any spot on the map, blending smoothly between grid points
func get_height(x: float, z: float) -> float:
	var gx := clampf((x + _width * 0.5) / _cell_x, 0.0, _points_x - 1.001)
	var gz := clampf((z + _depth * 0.5) / _cell_z, 0.0, _points_z - 1.001)
	var xi := int(gx)
	var zi := int(gz)
	var i := zi * _points_x + xi
	var north := lerpf(_heights[i], _heights[i + 1], gx - xi)
	var south := lerpf(_heights[i + _points_x], _heights[i + _points_x + 1], gx - xi)
	return lerpf(north, south, gz - zi)


## Which way the ground faces at a spot (straight up = flat). Quicker than get_slope().
func get_normal(x: float, z: float) -> Vector3:
	var gx := clampi(roundi((x + _width * 0.5) / _cell_x), 0, _points_x - 1)
	var gz := clampi(roundi((z + _depth * 0.5) / _cell_z), 0, _points_z - 1)
	return _normal_at(gx, gz)


## The whole map as a rectangle, seen from above (x, z)
func map_rect() -> Rect2:
	return Rect2(-_width * 0.5, -_depth * 0.5, _width, _depth)


## Which chunk a spot is in
func chunk_at(x: float, z: float) -> Vector2i:
	return Vector2i(floori((x + _width * 0.5) / (chunk_cells * _cell_x)), floori((z + _depth * 0.5) / (chunk_cells * _cell_z)))


func has_chunk(chunk: Vector2i) -> bool:
	return chunk.x >= 0 and chunk.y >= 0 and chunk.x < _chunks_x and chunk.y < _chunks_z


## The area a chunk covers, seen from above (x, z)
func chunk_rect(chunk: Vector2i) -> Rect2:
	var size := Vector2(chunk_cells * _cell_x, chunk_cells * _cell_z)
	return Rect2(Vector2(-_width * 0.5, -_depth * 0.5) + Vector2(chunk) * size, size)


## How steep the ground is at a spot, in degrees (0 = flat)
func get_slope(x: float, z: float) -> float:
	var dx := (get_height(x + 1.0, z) - get_height(x - 1.0, z)) / 2.0
	var dz := (get_height(x, z + 1.0) - get_height(x, z - 1.0)) / 2.0
	return rad_to_deg(atan(sqrt(dx * dx + dz * dz)))


## The nearest spot to `near` (an x, z position) that's dry and fairly flat
func find_dry_spot(near: Vector2) -> Vector2:
	var dry_above := water_height() + 1.0
	# Search in growing circles, 4 m apart
	for ring in 300:
		var radius := ring * 4.0
		var steps := maxi(1, int(TAU * radius / 4.0))
		for s in steps:
			var angle := TAU * s / steps
			var spot := near + Vector2(cos(angle), sin(angle)) * radius
			if get_height(spot.x, spot.y) > dry_above and get_slope(spot.x, spot.y) < 15.0:
				return spot
	return near


func generate() -> void:
	# Clear out the old terrain before building a new one
	for child in get_children():
		remove_child(child)
		child.queue_free()

	if not _load_heights():
		return
	# Let the ground's paint know where the water is, for the muddy shoreline
	if ground_material is ShaderMaterial:
		ground_material.set_shader_parameter("water_height", water_height())
	for cz in _chunks_z:
		for cx in _chunks_x:
			_build_chunk(cx, cz)
	_build_skirt()
	_build_water()
	_build_walls()
	_scatter_trees()

	# Grass, ferns and boulders
	var foliage = preload("res://foliage.gd").new()
	foliage.name = "Foliage"
	foliage.valley = self
	add_child(foliage)
	foliage.build_rocks(ground_material)


# Reads the heightmap into _heights. Returns false if the image couldn't be loaded.
func _load_heights() -> bool:
	var texture := load(heightmap_path) as Texture2D
	if texture == null:
		push_error("Valley: couldn't load the heightmap at %s" % heightmap_path)
		return false
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()

	# Work out the world's shape, and how many chunks fit across it
	_width = world_size
	_depth = world_size * image.get_height() / float(image.get_width())
	_chunks_x = maxi(1, roundi(_width / chunk_size))
	_chunks_z = maxi(1, roundi(_depth / chunk_size))
	_points_x = _chunks_x * chunk_cells + 1
	_points_z = _chunks_z * chunk_cells + 1
	_cell_x = _width / (_points_x - 1)
	_cell_z = _depth / (_points_z - 1)

	# The image only has 256 shades of gray, which makes the ground rise in little steps.
	# Switching to decimal numbers first means resizing and smoothing can blend between shades.
	image.convert(Image.FORMAT_RF)
	image.resize(_points_x, _points_z, Image.INTERPOLATE_CUBIC)
	var brightness := image.get_data().to_float32_array()
	for pass_number in 2:
		brightness = _blur(brightness, _points_x, _points_z, smoothing)

	# Brightness 0 to 1 becomes height above the lowest ground, stretched by height_scale
	var full_height := (max_elevation - min_elevation) * height_scale
	_heights.resize(brightness.size())
	for i in brightness.size():
		_heights[i] = brightness[i] * full_height
	return true


# Softens a grid of numbers by averaging each one with its neighbors within `radius`.
# Keeps a running total as it slides along, so it's quick even with a big radius.
func _blur(values: PackedFloat32Array, width: int, height: int, radius: int) -> PackedFloat32Array:
	if radius <= 0:
		return values
	var across := PackedFloat32Array()
	across.resize(values.size())
	var window := 2 * radius + 1
	# Along each row
	for z in height:
		var row := z * width
		var total := 0.0
		for k in range(-radius, radius + 1):
			total += values[row + clampi(k, 0, width - 1)]
		for x in width:
			across[row + x] = total / window
			total += values[row + mini(x + radius + 1, width - 1)] - values[row + maxi(x - radius, 0)]
	# Then down each column
	var result := PackedFloat32Array()
	result.resize(values.size())
	for x in width:
		var total := 0.0
		for k in range(-radius, radius + 1):
			total += across[clampi(k, 0, height - 1) * width + x]
		for z in height:
			result[z * width + x] = total / window
			total += across[mini(z + radius + 1, height - 1) * width + x] - across[maxi(z - radius, 0) * width + x]
	return result


# Which way the ground faces at a grid point, from how steeply it slopes to its neighbors
func _normal_at(gx: int, gz: int) -> Vector3:
	var row := gz * _points_x
	var west := _heights[row + maxi(gx - 1, 0)]
	var east := _heights[row + mini(gx + 1, _points_x - 1)]
	var north := _heights[maxi(gz - 1, 0) * _points_x + gx]
	var south := _heights[mini(gz + 1, _points_z - 1) * _points_x + gx]
	return Vector3((west - east) / (2.0 * _cell_x), 1.0, (north - south) / (2.0 * _cell_z)).normalized()


# One square piece of terrain: its own visible mesh and its own solid collision.
# Splitting the world up like this lets Godot skip drawing (and checking collisions with)
# pieces that are off-screen or far away, so it stays fast as the world grows.
func _build_chunk(cx: int, cz: int) -> void:
	var n := chunk_cells + 1
	var first_x := cx * chunk_cells
	var first_z := cz * chunk_cells
	var corner := Vector3(-_width * 0.5 + first_x * _cell_x, 0.0, -_depth * 0.5 + first_z * _cell_z)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var chunk_heights := PackedFloat32Array()
	vertices.resize(n * n)
	normals.resize(n * n)
	uvs.resize(n * n)
	chunk_heights.resize(n * n)
	for j in n:
		for k in n:
			var i := j * n + k
			var gx := first_x + k
			var gz := first_z + j
			var h := _heights[gz * _points_x + gx]
			chunk_heights[i] = h
			vertices[i] = Vector3(k * _cell_x, h, j * _cell_z)
			uvs[i] = Vector2(corner.x + k * _cell_x, corner.z + j * _cell_z) * 0.1
			# Normals come from the whole map, so lighting matches across chunk edges
			normals[i] = _normal_at(gx, gz)

	var indices := PackedInt32Array()
	indices.resize(chunk_cells * chunk_cells * 6)
	var m := 0
	for j in chunk_cells:
		for k in chunk_cells:
			var i := j * n + k
			indices[m] = i
			indices[m + 1] = i + 1
			indices[m + 2] = i + n
			indices[m + 3] = i + 1
			indices[m + 4] = i + n + 1
			indices[m + 5] = i + n
			m += 6

	var chunk := StaticBody3D.new()
	chunk.name = "Chunk_%d_%d" % [cx, cz]
	chunk.position = corner
	add_child(chunk)

	var mesh := MeshInstance3D.new()
	mesh.mesh = _make_mesh(vertices, normals, uvs, indices)
	mesh.material_override = ground_material
	chunk.add_child(mesh)

	# A heightmap collision shape is centered on itself, so put it in the middle of the chunk
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	shape.map_data = chunk_heights
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(chunk_cells * _cell_x * 0.5, 0.0, chunk_cells * _cell_z * 0.5)
	collision.scale = Vector3(_cell_x, 1.0, _cell_z)
	chunk.add_child(collision)


# A cliff hanging down around the outside of the map, so from outside it looks like a
# solid block of land. (Godot only draws a triangle from its front, so without this the
# map's edge would look paper-thin from some angles.)
func _build_skirt() -> void:
	var bottom := -20.0
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	# Each side: first grid point, step to the next one, how many steps, and which way it faces
	var sides := [
		[0, 1, _points_x - 1, Vector3.FORWARD],                            # north edge
		[(_points_z - 1) * _points_x, 1, _points_x - 1, Vector3.BACK],    # south edge
		[0, _points_x, _points_z - 1, Vector3.LEFT],                       # west edge
		[_points_x - 1, _points_x, _points_z - 1, Vector3.RIGHT],          # east edge
	]
	for side in sides:
		var start: int = side[0]
		var stride: int = side[1]
		var count: int = side[2]
		var outward: Vector3 = side[3]
		for k in count:
			var a := start + k * stride
			var b := a + stride
			var top_a := _grid_position(a)
			var top_b := _grid_position(b)
			var corners := [top_a, top_b, Vector3(top_b.x, bottom, top_b.z), Vector3(top_a.x, bottom, top_a.z)]
			var v := vertices.size()
			for c in corners:
				vertices.append(c)
				normals.append(outward)
				uvs.append(Vector2(c.x + c.z, c.y) * 0.1)
			# Wind each triangle so its front faces outward
			var facing: Vector3 = (corners[2] - corners[0]).cross(corners[1] - corners[0])
			if facing.dot(outward) > 0.0:
				indices.append_array([v, v + 1, v + 2, v, v + 2, v + 3])
			else:
				indices.append_array([v, v + 2, v + 1, v, v + 3, v + 2])

	var skirt := MeshInstance3D.new()
	skirt.name = "Skirt"
	skirt.mesh = _make_mesh(vertices, normals, uvs, indices)
	skirt.material_override = ground_material
	add_child(skirt)


# Where a grid point (counted row by row) sits in the world
func _grid_position(index: int) -> Vector3:
	var gx := index % _points_x
	@warning_ignore("integer_division")
	var gz := index / _points_x
	return Vector3(-_width * 0.5 + gx * _cell_x, _heights[index], -_depth * 0.5 + gz * _cell_z)


# One flat sheet of water across the whole map. Wherever the ground dips below it,
# you see water, so rivers, ponds and lakes fill in by themselves.
func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(_width, _depth)
	var water := MeshInstance3D.new()
	water.name = "Water"
	water.mesh = plane
	water.position.y = water_height()
	water.material_override = water_material if water_material else _default_water()
	add_child(water)


# Invisible walls just past each edge of the map, far too tall to climb over
func _build_walls() -> void:
	var highest := 0.0
	for h in _heights:
		highest = maxf(highest, h)
	var wall_height := highest + 200.0
	for side in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var box := BoxShape3D.new()
		if side.x != 0.0:
			box.size = Vector3(2.0, wall_height, _depth + 4.0)
		else:
			box.size = Vector3(_width + 4.0, wall_height, 2.0)
		var wall := CollisionShape3D.new()
		wall.shape = box
		wall.position = Vector3(side.x * (_width * 0.5 + 1.0), wall_height * 0.5 - 50.0, side.z * (_depth * 0.5 + 1.0))
		add_child(wall)


# Scatter trees anywhere that's dry and not too steep
func _scatter_trees() -> void:
	if not tree_scene:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	var dry_above := water_height() + 0.5
	# Trees grow in woods and stands, with open clearings between
	var forest := FastNoiseLite.new()
	forest.seed = map_seed
	forest.frequency = 0.006
	var placed := 0
	var tries := 0
	while placed < tree_count and tries < tree_count * 20:
		tries += 1
		var x := rng.randf_range(-_width * 0.5 + 5.0, _width * 0.5 - 5.0)
		var z := rng.randf_range(-_depth * 0.5 + 5.0, _depth * 0.5 - 5.0)
		if rng.randf() > smoothstep(-0.15, 0.35, forest.get_noise_2d(x, z)) + 0.03:
			continue
		var h := get_height(x, z)
		if h < dry_above or get_slope(x, z) > max_tree_slope:
			continue
		var tree := tree_scene.instantiate()
		tree.position = Vector3(x, h - 0.2, z)
		tree.rotation.y = rng.randf() * TAU
		tree.scale = Vector3.ONE * rng.randf_range(0.8, 1.4)
		add_child(tree)
		placed += 1


# Puts the player on dry, fairly flat ground as close to the middle of the map as possible
func _place_player() -> void:
	var player := get_node_or_null(player_path) as Node3D
	if player == null:
		return
	var spot := find_dry_spot(Vector2.ZERO)
	# The player's middle is 1 m above their feet; start them a little above the ground
	player.global_position = Vector3(spot.x, get_height(spot.x, spot.y) + 1.5, spot.y)


func _make_mesh(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# Water that's clear in the shallows and darker the deeper it gets, with drifting ripples
func _default_water() -> ShaderMaterial:
	var ripple_noise := FastNoiseLite.new()
	ripple_noise.frequency = 0.02
	var ripples := NoiseTexture2D.new()
	ripples.width = 512
	ripples.height = 512
	ripples.seamless = true
	ripples.as_normal_map = true
	ripples.bump_strength = 6.0
	ripples.noise = ripple_noise
	var material := ShaderMaterial.new()
	material.shader = preload("res://water.gdshader")
	material.set_shader_parameter("ripples", ripples)
	return material
