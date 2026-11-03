@tool
extends StaticBody3D

## Size of the whole map in meters (it's square)
@export var size := 400.0
## Ground detail. Higher = smoother hills, slower to build
@export var resolution := 512
## Width of the flat-ish valley floor
@export var floor_width := 30.0
## How far the slopes stretch before reaching the hilltops
@export var slope_width := 50.0
## How tall the hills on each side get
@export var hill_height := 30.0
## Small random lumps so nothing is perfectly smooth
@export var bump_height := 2.0
## Change this for a differently shaped valley
@export var map_seed := 1
@export var ground_material: Material

@export_group("River")
## Width of the river's flat bed, down the middle of the valley floor
@export var river_width := 8.0
## How far the muddy banks slope up on each side of the bed
@export var bank_width := 2.5
## How far the riverbed sinks below the valley floor
@export var river_depth := 1.5
## Height of the water surface (the valley floor is around 0)
@export var water_level := -0.4
## Leave empty to use a plain see-through blue
@export var water_material: Material

@export_group("Lake")
## How far down the valley the river pools into a lake
@export var lake_z := 90.0
## Radius of the open water
@export var lake_radius := 28.0
## How far the sloping shore reaches past the water's edge
@export var lake_shore := 10.0
## How deep the lake is in the middle, below the water surface
@export var lake_depth := 3.0

@export_group("Side Valley")
## Where along the main valley the side valley branches off
@export var side_valley_z := -60.0
## Width of the side valley's floor
@export var side_floor_width := 14.0
## How quickly the side valley's floor climbs as it heads into the hills
@export var side_rise := 0.08

@export_group("Mountains")
## How tall the mountains at the map's edge get, on top of the normal hills
@export var mountain_height := 60.0
## How far in from the edge the mountains start rising
@export var mountain_width := 40.0
## Width of the gorge floor where the river cuts through the mountains
@export var gorge_width := 18.0
## How far the gorge's sloping walls reach out on each side before they're full mountain
@export var gorge_wall := 45.0

@export_group("Trees")
@export var tree_scene: PackedScene
@export var tree_count := 600

@export_group("")
## Tick this in the Inspector to rebuild after changing settings
@export var rebuild := false:
	set(value):
		if value and is_inside_tree():
			generate()

## How far the scenery carries on past the invisible walls. You can't walk there,
## but it means the mountains look solid from every side, even from outside the map.
const OUTSIDE_MARGIN := 40.0
## How far the cliff around the outside of the scenery drops
const SKIRT_BOTTOM := -60.0

var noise := FastNoiseLite.new()
var _lake_center := Vector2.ZERO
var _side_start_x := 0.0


func _ready() -> void:
	generate()


# The valley floor winds gently from side to side
func valley_center(z: float) -> float:
	var center := sin(z * 0.02) * 15.0
	# Past the north and south walls, the river gorges bend sharply away, so looking
	# down a gorge you see rock walls instead of the end of the world
	var beyond := absf(z) - size * 0.5
	if beyond > 0.0:
		center -= beyond * beyond * 0.03 * signf(z)
	return center


# The side valley heads off toward +x, angling away down the map as it goes
func side_valley_center(x: float) -> float:
	var along := x - _side_start_x
	return side_valley_z - along * 0.6 + sin(along * 0.03) * 8.0


# How far up the main valley's slopes a spot is: 0 on the floor, 1 at the hilltops.
# The floor widens into a round basin around the lake.
func _main_slope(x: float, z: float) -> float:
	var lake_distance := Vector2(x, z).distance_to(_lake_center)
	var basin := 1.0 - smoothstep(lake_radius, lake_radius + slope_width, lake_distance)
	var half_floor := floor_width * 0.5 + basin * (lake_radius + lake_shore)
	return clampf((absf(x - valley_center(z)) - half_floor) / slope_width, 0.0, 1.0)


# Same idea for the side valley. It only exists on the +x side of where it branches off.
func _side_slope(x: float, z: float) -> float:
	if x <= _side_start_x:
		return 1.0
	# 0.857 corrects for the valley running at an angle, so its width stays true
	var distance := absf(z - side_valley_center(x)) * 0.857
	return clampf((distance - side_floor_width * 0.5) / (slope_width * 0.7), 0.0, 1.0)


# How much mountain there is at a spot: 0 everywhere except the last stretch of map,
# rising to 1 right at the edge. The river runs north-south (along z), so the north
# and south ranges each have a gorge cut through them for it.
func _mountains(x: float, z: float) -> float:
	var half := size / 2.0
	var east_west := 1.0 - smoothstep(0.0, mountain_width, half - absf(x))
	var north_south := 1.0 - smoothstep(0.0, mountain_width, half - absf(z))
	var gorge := smoothstep(gorge_width * 0.5, gorge_width * 0.5 + gorge_wall, absf(x - valley_center(z)))
	return maxf(east_west, north_south * gorge)


# How high the ground is at any spot on the map
func get_height(x: float, z: float) -> float:
	var t := _main_slope(x, z)
	var height := smoothstep(0.0, 1.0, t) * hill_height

	# The side valley: wherever it cuts lower than the main valley's hills, it wins
	var side_t := _side_slope(x, z)
	if side_t < 1.0:
		var floor_height := clampf((x - _side_start_x) * side_rise, 0.0, hill_height * 0.7)
		var side_height := floor_height + smoothstep(0.0, 1.0, side_t) * (hill_height - floor_height)
		if side_height < height:
			height = side_height
			t = side_t

	# The mountains around the edge, with extra-big lumps so they look rugged
	var mountains := _mountains(x, z)
	height += mountains * mountain_height
	height += noise.get_noise_2d(x * 2.0, z * 2.0) * mountains * mountain_height * 0.15
	t = maxf(t, mountains)

	# The riverbed: 1 on the flat bed, easing to 0 at the top of the banks
	var distance_from_center := absf(x - valley_center(z))
	var river := 1.0 - smoothstep(river_width * 0.5, river_width * 0.5 + bank_width, distance_from_center)
	height -= river * river_depth
	# Lumps: small on the valley floor, bigger up on the hills, none in the riverbed
	height += noise.get_noise_2d(x, z) * bump_height * (0.3 + t) * (1.0 - river)

	# The lake: a bowl where the river pools, deepest in the middle, with a sloping shore
	var lake_distance := Vector2(x, z).distance_to(_lake_center)
	if lake_distance < lake_radius + lake_shore:
		var bottom := water_level - 0.3 - lake_depth * smoothstep(0.0, 1.0, 1.0 - lake_distance / lake_radius)
		height = lerpf(bottom, height, smoothstep(lake_radius, lake_radius + lake_shore, lake_distance))
	return height


# True on the valley floors, lake shore, riverbanks and bare mountain peaks: places trees shouldn't grow
func is_open_ground(x: float, z: float) -> bool:
	return _mountains(x, z) > 0.6 \
		or _main_slope(x, z) < 0.08 \
		or _side_slope(x, z) < 0.08 \
		or Vector2(x, z).distance_to(_lake_center) < lake_radius + lake_shore + 3.0


func generate() -> void:
	noise.seed = map_seed
	noise.frequency = 0.02
	_lake_center = Vector2(valley_center(lake_z), lake_z)
	_side_start_x = valley_center(side_valley_z)

	# Clear out the old valley before building a new one
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var step := size / resolution
	var half := size / 2.0
	# The grid covers the map plus the scenery past the walls
	var margin_cells := ceili(OUTSIDE_MARGIN / step)
	var cells := resolution + margin_cells * 2
	var points := cells + 1
	var extent := half + margin_cells * step

	# Work out the height of every point on the grid
	var heights := PackedFloat32Array()
	heights.resize(points * points)
	for zi in points:
		for xi in points:
			heights[zi * points + xi] = get_height(-extent + xi * step, -extent + zi * step)

	# Build the visible ground from those heights. Filling in big arrays like this
	# is much faster than adding one point at a time, which matters on a big map.
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(points * points)
	normals.resize(points * points)
	uvs.resize(points * points)
	for zi in points:
		for xi in points:
			var i := zi * points + xi
			var x := -extent + xi * step
			var z := -extent + zi * step
			vertices[i] = Vector3(x, heights[i], z)
			uvs[i] = Vector2(x, z) * 0.1
			# Which way the ground faces, worked out from how steeply it slopes to its neighbors
			var left: float = heights[i - 1] if xi > 0 else heights[i]
			var right: float = heights[i + 1] if xi < cells else heights[i]
			var back: float = heights[i - points] if zi > 0 else heights[i]
			var front: float = heights[i + points] if zi < cells else heights[i]
			normals[i] = Vector3(left - right, 2.0 * step, back - front).normalized()

	var indices := PackedInt32Array()
	indices.resize(cells * cells * 6)
	var n := 0
	for zi in cells:
		for xi in cells:
			var i := zi * points + xi
			indices[n] = i
			indices[n + 1] = i + 1
			indices[n + 2] = i + points
			indices[n + 3] = i + 1
			indices[n + 4] = i + points + 1
			indices[n + 5] = i + points
			n += 6

	var ground := MeshInstance3D.new()
	ground.mesh = _make_mesh(vertices, normals, uvs, indices)
	ground.material_override = ground_material
	add_child(ground)

	# A cliff around the outside edge of the scenery, so from outside the map
	# it looks like a solid block of land instead of a paper-thin sheet
	var skirt := MeshInstance3D.new()
	skirt.mesh = _make_skirt(heights, points, step, extent)
	skirt.material_override = ground_material
	add_child(skirt)

	# Build the solid ground you walk on, using the same heights
	var shape := HeightMapShape3D.new()
	shape.map_width = points
	shape.map_depth = points
	shape.map_data = heights
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.scale = Vector3(step, 1.0, step)
	add_child(collision)

	# Invisible walls just past each edge of the map, far too tall to climb over
	for side in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var box := BoxShape3D.new()
		if side.x != 0.0:
			box.size = Vector3(2.0, 400.0, size + 4.0)
		else:
			box.size = Vector3(size + 4.0, 400.0, 2.0)
		var wall := CollisionShape3D.new()
		wall.shape = box
		wall.position = side * (half + 1.0) + Vector3.UP * 100.0
		add_child(wall)

	# Water: one flat sheet over every bit of riverbed and lake that dips below the
	# water level, so the river flows into the lake without any seams
	var water_vertices := PackedVector3Array()
	var water_normals := PackedVector3Array()
	var water_uvs := PackedVector2Array()
	var water_indices := PackedInt32Array()
	var wet_reach := river_width * 0.5 + bank_width + step
	for zi in cells:
		for xi in cells:
			var i := zi * points + xi
			var lowest := minf(minf(heights[i], heights[i + 1]), minf(heights[i + points], heights[i + points + 1]))
			if lowest >= water_level:
				continue
			var x := -extent + xi * step
			var z := -extent + zi * step
			# Only the river and lake, not every little dip in the valley floor
			var in_river := absf(x - valley_center(z)) < wet_reach
			var in_lake := Vector2(x, z).distance_to(_lake_center) < lake_radius + lake_shore
			if not in_river and not in_lake:
				continue
			var v := water_vertices.size()
			for corner in [Vector2(0, 0), Vector2(step, 0), Vector2(0, step), Vector2(step, step)]:
				water_vertices.append(Vector3(x + corner.x, water_level, z + corner.y))
				water_normals.append(Vector3.UP)
				water_uvs.append(Vector2(x + corner.x, z + corner.y) * 0.1)
			water_indices.append_array([v, v + 1, v + 2, v + 1, v + 3, v + 2])

	if not water_vertices.is_empty():
		var water := MeshInstance3D.new()
		water.mesh = _make_mesh(water_vertices, water_normals, water_uvs, water_indices)
		water.material_override = water_material if water_material else _default_water()
		add_child(water)

	# Scatter trees on the slopes, keeping the valley floors, riverbanks and lakeshore open
	if tree_scene:
		var rng := RandomNumberGenerator.new()
		rng.seed = map_seed
		var placed := 0
		var tries := 0
		while placed < tree_count and tries < tree_count * 10:
			tries += 1
			var x := rng.randf_range(-half + 5.0, half - 5.0)
			var z := rng.randf_range(-half + 5.0, half - 5.0)
			if is_open_ground(x, z):
				continue
			var tree := tree_scene.instantiate()
			tree.position = Vector3(x, get_height(x, z) - 0.2, z)
			tree.rotation.y = rng.randf() * TAU
			tree.scale = Vector3.ONE * rng.randf_range(0.8, 1.4)
			add_child(tree)
			placed += 1


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


# Builds the outer cliff: a wall hanging down from every point along the grid's edge
func _make_skirt(heights: PackedFloat32Array, points: int, step: float, extent: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	# Each side: where its first point is in the grid, which way to walk along it, and which way it faces
	var sides := [
		[0, 1, Vector3.FORWARD],                           # north edge, walking along x
		[(points - 1) * points, 1, Vector3.BACK],          # south edge, walking along x
		[0, points, Vector3.LEFT],                         # west edge, walking along z
		[points - 1, points, Vector3.RIGHT],               # east edge, walking along z
	]
	for side in sides:
		var start: int = side[0]
		var stride: int = side[1]
		var outward: Vector3 = side[2]
		for k in points - 1:
			var a := start + k * stride
			var b := a + stride
			# Turn grid numbers back into positions (dividing by points gives the row)
			@warning_ignore("integer_division")
			var top_a := Vector3(-extent + (a % points) * step, heights[a], -extent + (a / points) * step)
			@warning_ignore("integer_division")
			var top_b := Vector3(-extent + (b % points) * step, heights[b], -extent + (b / points) * step)
			var corners := [top_a, top_b, Vector3(top_b.x, SKIRT_BOTTOM, top_b.z), Vector3(top_a.x, SKIRT_BOTTOM, top_a.z)]
			var v := vertices.size()
			for corner in corners:
				vertices.append(corner)
				normals.append(outward)
				uvs.append(Vector2(corner.x + corner.z, corner.y) * 0.1)
			# Godot only draws a triangle from its front, so wind each one to face outward
			var facing: Vector3 = (corners[2] - corners[0]).cross(corners[1] - corners[0])
			if facing.dot(outward) > 0.0:
				indices.append_array([v, v + 1, v + 2, v, v + 2, v + 3])
			else:
				indices.append_array([v, v + 2, v + 1, v, v + 3, v + 2])
	return _make_mesh(vertices, normals, uvs, indices)


# Clear blue-green water you can see the riverbed through
func _default_water() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.42, 0.5, 0.7)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.metallic = 0.3
	material.roughness = 0.08
	# Visible from underneath too, if you wade in and look up
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
