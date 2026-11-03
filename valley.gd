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
## Change this for a different layout of trees and resources
@export var map_seed := 1

@export_group("Resources")
## How many of each resource to scatter over the map. 0 turns that kind off.
## Each kind has its own scene, so a real model can replace the placeholder later.
@export var stone_scene: PackedScene = preload("res://stone.tscn")
## Gray boulders: everywhere, more on steep slopes
@export var stone_count := 450
@export var fiber_scene: PackedScene = preload("res://plant_fiber.tscn")
## Tall grass and reed clumps, in meadows and along the water's edge
@export var fiber_count := 320
@export var stick_scene: PackedScene = preload("res://sticks.tscn")
## Little piles of fallen branches on the forest floor
@export var stick_count := 350
@export var copper_scene: PackedScene = preload("res://copper_ore.tscn")
## Green- and orange-flecked rock on the hillsides
@export var copper_count := 130
@export var tin_scene: PackedScene = preload("res://tin_ore.tscn")
## Pale, silver-flecked rock on the hillsides, often near copper
@export var tin_count := 120
@export var mushroom_scene: PackedScene = preload("res://mushrooms.tscn")
## Small clusters on the forest floor, close to trees
@export var mushroom_count := 180
@export var herb_scene: PackedScene = preload("res://herbs.tscn")
## Leafy plants along the water's edge
@export var herb_count := 150
@export var berry_scene: PackedScene = preload("res://berry_bush.tscn")
## Bushes at the edges of woods and out in meadows
@export var berry_count := 120
## Nothing gets scattered closer than this to the crash site (its own salvage is already there)
@export var crash_site_gap := 20.0

@export_group("Underground")
## Hidden deposits buried in clusters under the hillsides. They can't be seen or dug
## until a dowsing rod reveals them.
@export var iron_seam_scene: PackedScene = preload("res://iron_seam.tscn")
@export var iron_seam_count := 70
@export var coal_seam_scene: PackedScene = preload("res://coal_seam.tscn")
@export var coal_seam_count := 80

@export_group("")
## The player, who starts beside the crash site (or on dry ground near the middle, if there isn't one)
@export var player_path: NodePath = ^"../Player"
## The wreck the player arrives in. The valley finds a flat, dry spot for it and clears the trees.
@export var crash_site_path: NodePath = ^"../CrashSite"
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
# Where the crash site is (x, z), and how much ground around it is kept clear. 0 = no crash site.
var _crash_center := Vector2.ZERO
var _crash_radius := 0.0
# Where the boiler lies (x, z), for the scorch mark around it
var _scorch_center := Vector2.ZERO
# The pattern that decides where woods grow thick and where clearings open up
var _forest := FastNoiseLite.new()
# The highest ground on the map, in game meters
var _highest := 1.0
# Where things have been scattered, sorted into squares of the map so nearby ones are
# quick to find: one record for everything (so nothing lands on top of anything else)
# and one for trees alone (so mushrooms can find them)
const SPOT_SQUARE := 4.0
var _taken_spots := {}
var _tree_spots := {}
# Copper outcrops (so tin can grow near them) and buried deposits (kept apart from each other)
var _copper_spots := {}
var _deposit_spots := {}


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
	# Find the crash site's spot first, so trees and boulders can keep clear of it
	_place_crash_site()
	# Let the ground's paint know where the water is, for the muddy shoreline,
	# and where the ship came down, for the churned mud and puddles
	if ground_material is ShaderMaterial:
		ground_material.set_shader_parameter("water_height", water_height())
		ground_material.set_shader_parameter("mud_center", _crash_center)
		ground_material.set_shader_parameter("mud_radius", _crash_radius * 0.75)
		ground_material.set_shader_parameter("scorch_center", _scorch_center)
		ground_material.set_shader_parameter("scorch_radius", 8.5 if _crash_radius > 0.0 else 0.0)
	for cz in _chunks_z:
		for cx in _chunks_x:
			_build_chunk(cx, cz)
	_build_skirt()
	_build_water()
	_build_walls()
	_forest.seed = map_seed
	_forest.frequency = 0.006
	_taken_spots.clear()
	_tree_spots.clear()
	_copper_spots.clear()
	_deposit_spots.clear()
	_scatter_trees()
	_scatter_resources()
	_bury_deposits()

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
	_highest = maxf(highest, 1.0)
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
	var placed := 0
	var tries := 0
	while placed < tree_count and tries < tree_count * 20:
		tries += 1
		var x := rng.randf_range(-_width * 0.5 + 5.0, _width * 0.5 - 5.0)
		var z := rng.randf_range(-_depth * 0.5 + 5.0, _depth * 0.5 - 5.0)
		# Trees grow in woods and stands, with open clearings between
		if rng.randf() > smoothstep(-0.15, 0.35, _forest.get_noise_2d(x, z)) + 0.03:
			continue
		var h := get_height(x, z)
		if h < dry_above or get_slope(x, z) > max_tree_slope or is_near_crash_site(x, z):
			continue
		var tree := tree_scene.instantiate()
		tree.position = Vector3(x, h - 0.2, z)
		tree.rotation.y = rng.randf() * TAU
		tree.scale = Vector3.ONE * rng.randf_range(0.8, 1.4)
		add_child(tree)
		_remember_spot(Vector2(x, z), _taken_spots)
		_remember_spot(Vector2(x, z), _tree_spots)
		placed += 1


# Every kind of resource, with where it likes to grow:
#   scene, count, how far apart (m), how big a clump pattern (smaller = bigger clumps),
#   how clumpy (0 = spread evenly, 1 = only in tight clusters), size range,
#   how much it leans to match the slope (0 = stands upright like a plant, 0.6 = settles
#   partway like a rock, 1 = lies flat along the ground like fallen sticks), its "likes this
#   spot" check, and how far it spreads from its middle (m, before resizing), which decides
#   how deep to sink it
func _resource_kinds() -> Array:
	# Copper goes before tin, so tin can look for copper to grow near
	return [
		[stone_scene, stone_count, 3.0, 0.02, 0.25, Vector2(0.6, 1.6), 0.6, _likes_stone, 0.75],
		[fiber_scene, fiber_count, 2.0, 0.03, 0.4, Vector2(1.2, 1.6), 0.0, _likes_fiber, 0.3],
		[stick_scene, stick_count, 2.0, 0.03, 0.3, Vector2(1.2, 1.6), 1.0, _likes_sticks, 0.4],
		[copper_scene, copper_count, 3.0, 0.012, 0.55, Vector2(0.7, 1.2), 0.6, _likes_copper, 0.7],
		[tin_scene, tin_count, 3.0, 0.012, 0.55, Vector2(0.7, 1.2), 0.6, _likes_tin, 0.7],
		[mushroom_scene, mushroom_count, 1.5, 0.03, 0.5, Vector2(1.7, 2.3), 0.0, _likes_mushrooms, 0.2],
		[herb_scene, herb_count, 1.5, 0.04, 0.45, Vector2(1.5, 2.0), 0.0, _likes_herbs, 0.2],
		[berry_scene, berry_count, 3.0, 0.025, 0.4, Vector2(0.8, 1.2), 0.0, _likes_berries, 0.7],
	]


# Scatters every kind of resource. Each kind has its own random numbers and its own
# clump pattern, both worked out from the map seed, so the same seed gives the same valley.
func _scatter_resources() -> void:
	var kinds := _resource_kinds()
	var water := water_height()
	for k in kinds.size():
		var scene: PackedScene = kinds[k][0]
		var count: int = kinds[k][1]
		if scene == null or count <= 0:
			continue
		var spacing: float = kinds[k][2]
		var clumpiness: float = kinds[k][4]
		var sizes: Vector2 = kinds[k][5]
		var lean: float = kinds[k][6]
		var likes: Callable = kinds[k][7]
		var footprint: float = kinds[k][8]
		var rng := RandomNumberGenerator.new()
		rng.seed = map_seed * 1000 + k
		var clumps := FastNoiseLite.new()
		clumps.seed = map_seed * 1000 + k
		clumps.frequency = kinds[k][3]

		var placed := 0
		var tries := 0
		while placed < count and tries < count * 400:
			tries += 1
			var x := rng.randf_range(-_width * 0.5 + 6.0, _width * 0.5 - 6.0)
			var z := rng.randf_range(-_depth * 0.5 + 6.0, _depth * 0.5 - 6.0)
			var spot := Vector2(x, z)
			if _crash_radius > 0.0 and spot.distance_to(_crash_center) < crash_site_gap:
				continue
			var h := get_height(x, z)
			# Never underwater (herbs check how close to the water they are themselves)
			if h < water + 0.2:
				continue
			# Clumpy kinds only grow where their pattern is high; even kinds grow almost anywhere
			var clump := smoothstep(lerpf(-1.0, 0.25, clumpiness), lerpf(-0.6, 0.5, clumpiness), clumps.get_noise_2d(x, z))
			if rng.randf() > clump:
				continue
			var slope := get_slope(x, z)
			if rng.randf() > likes.call(x, z, h - water, slope):
				continue
			if _distance_to_nearest(spot, _taken_spots, spacing) < spacing:
				continue

			var item := scene.instantiate()
			var size := rng.randf_range(sizes.x, sizes.y)
			var turn := Basis(Vector3.UP, rng.randf() * TAU)
			if lean > 0.0:
				# Rocks settle partway into the slope; fallen sticks lie along it
				var settle := Quaternion(Vector3.UP, Vector3.UP.slerp(get_normal(x, z), lean))
				turn = Basis(settle) * turn
			item.transform = Transform3D(turn.scaled(Vector3.ONE * size), Vector3.ZERO)
			# Sink it so its downhill edge still touches the ground on a slope (never floating),
			# by just enough for its own width: a boulder needs much more than a mushroom.
			# Things that lean with the slope already follow it partway, so they need less again.
			var uncovered_slope := slope * (1.0 - lean * 0.67)
			var reach := footprint * size
			var sink := 0.07 + reach * 0.08 + tan(deg_to_rad(minf(uncovered_slope, 60.0))) * reach
			item.position = Vector3(x, h - sink, z)
			add_child(item)
			_remember_spot(spot, _taken_spots)
			if scene == copper_scene:
				_remember_spot(spot, _copper_spots)
			placed += 1


# Buries iron and coal deposits in clusters under the hillsides. They're kept in their own
# record, not the shared one, so the grass doesn't leave a tell-tale bare patch over them.
func _bury_deposits() -> void:
	var water := water_height()
	var seams := [[iron_seam_scene, iron_seam_count, _likes_iron], [coal_seam_scene, coal_seam_count, _likes_coal]]
	for s in seams.size():
		var scene: PackedScene = seams[s][0]
		var count: int = seams[s][1]
		var likes: Callable = seams[s][2]
		if scene == null or count <= 0:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = map_seed * 2000 + s
		var clumps := FastNoiseLite.new()
		clumps.seed = map_seed * 2000 + s
		clumps.frequency = 0.012
		var placed := 0
		var tries := 0
		while placed < count and tries < count * 400:
			tries += 1
			var x := rng.randf_range(-_width * 0.5 + 6.0, _width * 0.5 - 6.0)
			var z := rng.randf_range(-_depth * 0.5 + 6.0, _depth * 0.5 - 6.0)
			var spot := Vector2(x, z)
			if _crash_radius > 0.0 and spot.distance_to(_crash_center) < crash_site_gap:
				continue
			var h := get_height(x, z)
			if h < water + 0.5:
				continue
			# Seams run in clusters: only where this kind's pattern is high
			if rng.randf() > smoothstep(0.15, 0.45, clumps.get_noise_2d(x, z)):
				continue
			var slope := get_slope(x, z)
			# Dig spots need ground you can stand and dig on
			if slope > 38.0 or rng.randf() > likes.call(x, z, h - water, slope):
				continue
			if _distance_to_nearest(spot, _deposit_spots, 8.0) < 8.0 or _distance_to_nearest(spot, _taken_spots, 2.5) < 2.5:
				continue
			var deposit := scene.instantiate()
			deposit.rotation.y = rng.randf() * TAU
			deposit.position = Vector3(x, h - 0.05 - tan(deg_to_rad(slope)) * 0.9, z)
			add_child(deposit)
			_remember_spot(spot, _deposit_spots)
			placed += 1


# Each "likes" check gives a chance from 0 (never here) to 1 (loves it here).
# above_water is how high the spot is above the water, in meters; slope is in degrees.

func _likes_stone(_x: float, _z: float, _above_water: float, slope: float) -> float:
	return (0.25 + 0.75 * smoothstep(8.0, 35.0, slope)) * (1.0 - smoothstep(55.0, 65.0, slope))


func _likes_fiber(x: float, z: float, above_water: float, slope: float) -> float:
	# Open meadows, and the grassy banks right by the water
	var meadow := 1.0 - smoothstep(0.1, 0.35, _forest.get_noise_2d(x, z))
	var bank := 0.0
	if above_water < 4.0 and _water_nearby(x, z, 12.0):
		bank = 1.0
	return maxf(meadow, bank) * (1.0 - smoothstep(18.0, 28.0, slope))


func _likes_sticks(x: float, z: float, _above_water: float, slope: float) -> float:
	# Under the trees, where branches fall
	var tree := _distance_to_nearest(Vector2(x, z), _tree_spots, 8.0)
	if tree < 1.0 or tree > 7.0:
		return 0.0
	return 1.0 - smoothstep(28.0, 38.0, slope)


func _likes_copper(_x: float, _z: float, above_water: float, slope: float) -> float:
	# On the hillsides: up off the valley floor, but no longer only near the tops
	var hillside := smoothstep(0.12, 0.3, above_water / _highest)
	return hillside * smoothstep(10.0, 22.0, slope) * (1.0 - smoothstep(50.0, 60.0, slope))


func _likes_tin(x: float, z: float, above_water: float, slope: float) -> float:
	# The same hillsides as copper, and much more likely close to a copper outcrop
	var hillside := smoothstep(0.12, 0.3, above_water / _highest)
	var copper_close := _distance_to_nearest(Vector2(x, z), _copper_spots, 30.0) < 30.0
	return hillside * smoothstep(10.0, 22.0, slope) * (1.0 - smoothstep(50.0, 60.0, slope)) \
		* (1.0 if copper_close else 0.3)


func _likes_iron(_x: float, _z: float, above_water: float, slope: float) -> float:
	var hillside := smoothstep(0.08, 0.25, above_water / _highest)
	return smoothstep(10.0, 24.0, slope) * hillside


func _likes_coal(_x: float, _z: float, above_water: float, slope: float) -> float:
	var lower_hills := 1.0 - smoothstep(0.45, 0.65, above_water / _highest)
	return smoothstep(8.0, 20.0, slope) * lower_hills


func _likes_mushrooms(x: float, z: float, _above_water: float, slope: float) -> float:
	# In the shade near a tree, but not right up against its trunk
	var tree := _distance_to_nearest(Vector2(x, z), _tree_spots, 6.0)
	if tree < 1.2 or tree > 5.0:
		return 0.0
	return 1.0 - smoothstep(20.0, 30.0, slope)


func _likes_herbs(x: float, z: float, above_water: float, slope: float) -> float:
	# Just above the waterline, on gentle banks, with actual water a few steps away
	var low_enough := smoothstep(0.2, 0.5, above_water) * (1.0 - smoothstep(3.0, 5.0, above_water))
	if low_enough <= 0.0 or not _water_nearby(x, z, 14.0):
		return 0.0
	return low_enough * (1.0 - smoothstep(15.0, 25.0, slope))


# True if any ground within `reach` meters dips below the water
func _water_nearby(x: float, z: float, reach: float) -> bool:
	var water := water_height()
	for ring in [reach * 0.35, reach * 0.7, reach]:
		for k in 10:
			var p: Vector2 = Vector2(x, z) + Vector2.from_angle(TAU * k / 10.0) * ring
			if get_height(p.x, p.y) < water:
				return true
	return false


func _likes_berries(x: float, z: float, _above_water: float, slope: float) -> float:
	# Out in the meadows and along the edges of woods, but not deep in the forest
	var woods := _forest.get_noise_2d(x, z)
	return (1.0 - smoothstep(0.25, 0.45, woods)) * (1.0 - smoothstep(14.0, 22.0, slope))


## True if a tree or resource stands within `radius` meters of this spot
func is_spot_taken(x: float, z: float, radius: float) -> bool:
	return _distance_to_nearest(Vector2(x, z), _taken_spots, radius) < radius


# Notes down that something now stands at this spot
func _remember_spot(spot: Vector2, record: Dictionary) -> void:
	var square := Vector2i(floori(spot.x / SPOT_SQUARE), floori(spot.y / SPOT_SQUARE))
	if not record.has(square):
		record[square] = []
	record[square].append(spot)


# How far it is to the nearest thing in the record, looking no further than `reach`
# (anything beyond that comes back as INF, meaning "nothing close")
func _distance_to_nearest(spot: Vector2, record: Dictionary, reach: float) -> float:
	var nearest := INF
	var square := Vector2i(floori(spot.x / SPOT_SQUARE), floori(spot.y / SPOT_SQUARE))
	var squares_out := ceili(reach / SPOT_SQUARE)
	for dz in range(-squares_out, squares_out + 1):
		for dx in range(-squares_out, squares_out + 1):
			for other in record.get(square + Vector2i(dx, dz), []):
				nearest = minf(nearest, spot.distance_to(other))
	return nearest if nearest <= reach else INF


## True within the cleared ground around the crash site. `fraction` shrinks the area,
## e.g. 0.5 for just the middle, where the wreck itself lies.
func is_near_crash_site(x: float, z: float, fraction := 1.0) -> bool:
	return _crash_radius > 0.0 and Vector2(x, z).distance_to(_crash_center) < _crash_radius * fraction


# Moves the crash site to a good spot. Once the game is running, also sets every piece
# of the wreck down on the ground. (In the editor it's only moved, so the scene's own
# layout isn't overwritten.)
func _place_crash_site() -> void:
	_crash_radius = 0.0
	var site = get_node_or_null(crash_site_path)
	if site == null:
		return
	var spot := _find_crash_spot()
	_crash_center = spot
	_crash_radius = site.clear_radius
	# The ship plowed the ground flat where it came down
	_level_ground(spot, _crash_radius * 0.6, _crash_radius * 1.1)
	site.global_position = Vector3(spot.x, get_height(spot.x, spot.y), spot.y)
	_scorch_center = site.scorch_point()
	if not Engine.is_editor_hint():
		site.settle(self)


# Looks near the middle of the map for a big, flat, dry stretch of valley floor,
# well away from the water
func _find_crash_spot() -> Vector2:
	var dry_above := water_height() + 1.5
	var best := Vector2.ZERO
	var best_score := INF
	for xi in range(-30, 31):
		for zi in range(-30, 31):
			var center := Vector2(xi, zi) * 10.0
			if center.length() > 300.0:
				continue
			var h := get_height(center.x, center.y)
			if h < dry_above + 1.5:
				continue
			# Dry ground all around it, at least 45 m out in every direction
			var dry := true
			for ring in [15.0, 30.0, 45.0]:
				for k in 12:
					var p: Vector2 = center + Vector2.from_angle(TAU * k / 12.0) * ring
					if get_height(p.x, p.y) < dry_above:
						dry = false
						break
				if not dry:
					break
			if not dry:
				continue
			# How bumpy the ground is under the whole wreck, about 42 m across
			var lowest := INF
			var highest := -INF
			for gx in range(-3, 4):
				for gz in range(-3, 4):
					var g := get_height(center.x + gx * 7.0, center.y + gz * 7.0)
					lowest = minf(lowest, g)
					highest = maxf(highest, g)
			# The ground gets leveled under the wreck anyway, so being near the middle
			# matters as much as being flat; and it should be down on the valley floor
			var score := (highest - lowest) * 0.4 + center.length() * 0.04 + (h - dry_above) * 0.05
			if score < best_score:
				best_score = score
				best = center
	return best


# Flattens the ground to its average height within `flat_radius` of `center`, then blends
# smoothly back into the natural slope by `blend_radius`. Changes the heights themselves,
# so the mesh, collision, trees and grass all follow.
func _level_ground(center: Vector2, flat_radius: float, blend_radius: float) -> void:
	var total := 0.0
	var samples := 0
	for k in 24:
		for r in [0.0, flat_radius * 0.5, flat_radius]:
			var p: Vector2 = center + Vector2.from_angle(TAU * k / 24.0) * r
			total += get_height(p.x, p.y)
			samples += 1
	var flat_height := total / samples

	var first_x := maxi(0, floori((center.x - blend_radius + _width * 0.5) / _cell_x))
	var last_x := mini(_points_x - 1, ceili((center.x + blend_radius + _width * 0.5) / _cell_x))
	var first_z := maxi(0, floori((center.y - blend_radius + _depth * 0.5) / _cell_z))
	var last_z := mini(_points_z - 1, ceili((center.y + blend_radius + _depth * 0.5) / _cell_z))
	for gz in range(first_z, last_z + 1):
		for gx in range(first_x, last_x + 1):
			var spot := Vector2(-_width * 0.5 + gx * _cell_x, -_depth * 0.5 + gz * _cell_z)
			var how_flat := 1.0 - smoothstep(flat_radius, blend_radius, spot.distance_to(center))
			var i := gz * _points_x + gx
			_heights[i] = lerpf(_heights[i], flat_height, how_flat)


# Puts the player beside the crash site, facing the wreck. With no crash site, it uses
# dry, fairly flat ground as close to the middle of the map as possible.
func _place_player() -> void:
	var player := get_node_or_null(player_path) as Node3D
	if player == null:
		return
	var site = get_node_or_null(crash_site_path)
	if site and _crash_radius > 0.0:
		var start: Vector3 = site.spawn_point()
		# The player's middle is 1 m above their feet; start them a little above the ground
		player.global_position = Vector3(start.x, get_height(start.x, start.z) + 1.5, start.z)
		var toward: Vector3 = site.spawn_look_target() - player.global_position
		player.rotation.y = atan2(-toward.x, -toward.z)
		return
	var spot := find_dry_spot(Vector2.ZERO)
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
