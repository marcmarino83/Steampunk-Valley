@tool
extends StaticBody3D

## Size of the whole map in meters (it's square)
@export var size := 200.0
## Ground detail. Higher = smoother hills, slower to build
@export var resolution := 128
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
## Width of the river's flat bed, down the middle of the valley floor
@export var river_width := 8.0
## How far the muddy banks slope up on each side of the bed
@export var bank_width := 2.5
## How far the riverbed sinks below the valley floor
@export var river_depth := 1.5
## Height of the water surface (the valley floor is around 0)
@export var water_level := -0.4
@export var ground_material: Material
## Leave empty to use a plain see-through blue
@export var water_material: Material
@export var tree_scene: PackedScene
@export var tree_count := 150
## Tick this in the Inspector to rebuild after changing settings
@export var rebuild := false:
	set(value):
		if value and is_inside_tree():
			generate()

var noise := FastNoiseLite.new()


func _ready() -> void:
	generate()


# The valley floor winds gently from side to side
func valley_center(z: float) -> float:
	return sin(z * 0.02) * 15.0


# How high the ground is at any spot on the map
func get_height(x: float, z: float) -> float:
	var distance_from_center := absf(x - valley_center(z))
	var t := clampf((distance_from_center - floor_width * 0.5) / slope_width, 0.0, 1.0)
	var height := smoothstep(0.0, 1.0, t) * hill_height
	# The riverbed: 1 on the flat bed, easing to 0 at the top of the banks
	var river := 1.0 - smoothstep(river_width * 0.5, river_width * 0.5 + bank_width, distance_from_center)
	height -= river * river_depth
	# Lumps: small on the valley floor, bigger up on the hills, none in the riverbed
	height += noise.get_noise_2d(x, z) * bump_height * (0.3 + t) * (1.0 - river)
	return height


func generate() -> void:
	noise.seed = map_seed
	noise.frequency = 0.02

	# Clear out the old valley before building a new one
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var points := resolution + 1
	var step := size / resolution
	var half := size / 2.0

	# Work out the height of every point on the grid
	var heights := PackedFloat32Array()
	heights.resize(points * points)
	for zi in points:
		for xi in points:
			heights[zi * points + xi] = get_height(-half + xi * step, -half + zi * step)

	# Build the visible ground from those heights
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for zi in points:
		for xi in points:
			st.set_uv(Vector2(xi, zi) / resolution * 20.0)
			st.add_vertex(Vector3(-half + xi * step, heights[zi * points + xi], -half + zi * step))
	for zi in resolution:
		for xi in resolution:
			var i := zi * points + xi
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + points)
			st.add_index(i + 1)
			st.add_index(i + points + 1)
			st.add_index(i + points)
	st.generate_normals()

	var ground := MeshInstance3D.new()
	ground.mesh = st.commit()
	ground.material_override = ground_material
	add_child(ground)

	# Build the solid ground you walk on, using the same heights
	var shape := HeightMapShape3D.new()
	shape.map_width = points
	shape.map_depth = points
	shape.map_data = heights
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.scale = Vector3(step, 1.0, step)
	add_child(collision)

	# Lay a flat water ribbon along the river, tucked under the banks at its edges
	var water_half_width := river_width * 0.5 + bank_width
	var water := SurfaceTool.new()
	water.begin(Mesh.PRIMITIVE_TRIANGLES)
	for zi in points:
		var z := -half + zi * step
		var center := valley_center(z)
		water.set_uv(Vector2(0, zi * 0.2))
		water.add_vertex(Vector3(center - water_half_width, water_level, z))
		water.set_uv(Vector2(1, zi * 0.2))
		water.add_vertex(Vector3(center + water_half_width, water_level, z))
	for zi in resolution:
		var i := zi * 2
		water.add_index(i)
		water.add_index(i + 1)
		water.add_index(i + 2)
		water.add_index(i + 1)
		water.add_index(i + 3)
		water.add_index(i + 2)
	water.generate_normals()

	var river_surface := MeshInstance3D.new()
	river_surface.mesh = water.commit()
	river_surface.material_override = water_material if water_material else _default_water()
	add_child(river_surface)

	# Scatter trees on the slopes, keeping the valley floor open
	if tree_scene:
		var rng := RandomNumberGenerator.new()
		rng.seed = map_seed
		var placed := 0
		var tries := 0
		while placed < tree_count and tries < tree_count * 10:
			tries += 1
			var x := rng.randf_range(-half + 5.0, half - 5.0)
			var z := rng.randf_range(-half + 5.0, half - 5.0)
			if absf(x - valley_center(z)) < floor_width * 0.5 + 4.0:
				continue
			var tree := tree_scene.instantiate()
			tree.position = Vector3(x, get_height(x, z) - 0.2, z)
			tree.rotation.y = rng.randf() * TAU
			tree.scale = Vector3.ONE * rng.randf_range(0.8, 1.4)
			add_child(tree)
			placed += 1


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
