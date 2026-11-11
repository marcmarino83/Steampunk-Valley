@tool
extends StaticBody3D

## A grayscale heightmap: black is the lowest ground, white the highest
@export_file("*.png") var heightmap_path := "res://world/heightmap.png"
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
## The old single placeholder pine: only used if both lists below are empty
@export var tree_scene: PackedScene
## Full-grown forest trees (12-20 m), picked at random for each tree placed
@export var forest_trees: Array[PackedScene] = [
	preload("res://assets/trees/pine_pack/scenes/pine_large_1.tscn"),
	preload("res://assets/trees/pine_pack/scenes/pine_large_2.tscn"),
	preload("res://assets/trees/pine_pack/scenes/pine_large_3.tscn"),
	preload("res://assets/trees/pine_pack/scenes/pine_big_1.tscn"),
	preload("res://assets/trees/pine_pack/scenes/pine_big_2.tscn"),
	preload("res://assets/trees/pine_pack/scenes/pine_big_3.tscn"),
	preload("res://assets/trees/pine_pack/scenes/pine_medium_1.tscn"),
	preload("res://assets/trees/pine_pack/scenes/pine_medium_2.tscn"),
	preload("res://assets/trees/pine_pack/scenes/pine_medium_3.tscn"),
]
## Young trees and saplings (1.5-5 m), mixed in among the forest
@export var young_trees: Array[PackedScene] = [
	preload("res://assets/trees/pine_pack/scenes/pine_small_1.tscn"),
	preload("res://assets/trees/pine_pack/scenes/pine_small_2.tscn"),
	preload("res://assets/trees/pine_pack/scenes/pine_small_3.tscn"),
	preload("res://assets/trees/pine_pack/scenes/pine_sapling_1.tscn"),
	preload("res://assets/trees/pine_pack/scenes/pine_sapling_2.tscn"),
	preload("res://assets/trees/pine_pack/scenes/pine_sapling_3.tscn"),
]
## How many of the trees placed are young ones (0.25 = one in four)
@export_range(0.0, 1.0, 0.01) var young_tree_share := 0.25
## Each tree is scaled randomly by up to this much either way, so no two look the same
@export_range(0.0, 0.5, 0.01) var tree_size_variation := 0.12
@export var tree_count := 4000
## Trees won't grow on ground steeper than this, in degrees
@export_range(0.0, 90.0) var max_tree_slope := 42.0
## A few big trees with places of their own, set among the forest. Their scenes come from a
## paid model pack that isn't in the repository, so any that are missing are just left out.
## Tall Douglas firs (about 28 m) on the hilltops, standing out as landmarks:
@export_file("*.tscn") var landmark_fir_scene := "res://assets/trees/douglasfir/scenes/douglasfir_1.tscn"
@export var landmark_fir_count := 8
## Willows (about 12 m) at the water's edge:
@export_file("*.tscn") var willow_scene := "res://assets/trees/willow/scenes/willow.tscn"
@export var willow_count := 10
## Change this for a different layout of trees and resources
@export var map_seed := 1

@export_group("Resources")
## How many of each resource to scatter over the map. 0 turns that kind off.
## Each kind has its own scene, so a real model can replace the placeholder later.
@export var stone_scene: PackedScene = preload("res://world/stone.tscn")
## Loose stones: everywhere, more on steep slopes
@export var stone_count := 675
@export var fiber_scene: PackedScene = preload("res://world/plant_fiber.tscn")
## Tall grass and reed clumps, in meadows and along the water's edge
@export var fiber_count := 480
@export var stick_scene: PackedScene = preload("res://world/sticks.tscn")
## Little piles of fallen branches on the forest floor
@export var stick_count := 525
@export var copper_scene: PackedScene = preload("res://world/copper_ore.tscn")
## Green- and orange-flecked rock on the hillsides
@export var copper_count := 130
@export var tin_scene: PackedScene = preload("res://world/tin_ore.tscn")
## Pale, silver-flecked rock on the hillsides, often near copper
@export var tin_count := 120
@export var mushroom_scene: PackedScene = preload("res://world/mushrooms.tscn")
## Small clusters on the forest floor, close to trees
@export var mushroom_count := 180
@export var herb_scene: PackedScene = preload("res://world/herbs.tscn")
## Leafy plants along the water's edge
@export var herb_count := 150
@export var berry_scene: PackedScene = preload("res://world/berry_bush.tscn")
## Bushes at the edges of woods and out in meadows
@export var berry_count := 150
## Nothing gets scattered closer than this to the crash site (its own salvage is already there)
@export var crash_site_gap := 20.0
## A few of each laid out near where the player starts, beside the wreck: enough to craft the
## hammer and the axe straight away. (How many piles of each.)
@export var starter_stone := 2
@export var starter_sticks := 3
@export var starter_fiber := 3

@export_group("Respawning")
## How long until gathered things come back, in in-game days (one day is a day and its night;
## how long that is depends on the sun's Day Minutes and Night Minutes). 0 means never.
@export var plant_fiber_respawn_days := 0.5
@export var sticks_respawn_days := 1.0
@export var stone_respawn_days := 2.0
## Picked berry bushes stay, bare, until their berries grow back
@export var berries_regrow_days := 1.0
## A felled tree's stump grows a sapling partway through, then a full tree
@export var tree_regrow_days := 3.0
## Mined boulders, scattered or placed by hand
@export var boulder_respawn_days := 3.0
## Nothing comes back while the player is closer than this (meters) or looking at the spot
@export var respawn_min_distance := 30.0

@export_group("Underground")
## Hidden deposits buried in clusters under the hillsides. They can't be seen or dug
## until a dowsing rod reveals them. None are buried while IronTier.ENABLED is false.
@export var iron_seam_scene: PackedScene = preload("res://iron_tier/iron_seam.tscn")
@export var iron_seam_count := 70
@export var coal_seam_scene: PackedScene = preload("res://iron_tier/coal_seam.tscn")
@export var coal_seam_count := 80

@export_group("Tall peaks")
## Ridges and gullies are carved into ground above this height, in meters (0 depth = none)...
@export var ridges_from := 120.0
## ...reaching full depth by this height
@export var ridges_full := 155.0
## How deep the ridges and gullies are at full depth, in meters
@export var ridge_depth := 26.0
## Roughly how far apart the ridges are, in meters
@export var ridge_spacing := 55.0
## No trees are scattered above this height, give or take 10 m so the tree line isn't straight.
## Trees placed by hand with the Object Painter can still go anywhere.
@export var tree_line := 125.0

@export_group("Ground materials")
## Which texture set (from assets/textures, as "folder/name") the ground uses for each job.
## Leave one empty, or name a set that isn't there, and that job is simply skipped.
## Mossy forest floor under the trees:
@export var forest_floor_set := "forest_floor/Ground037"
## Trail surfaces (the editor's Terrain Paths and the dirt paths painted in the game): plain worn
## earth (the old sandy pebble set, gravel_path/Ground049C, stood out too much)...
@export var path_set := "soil/Ground109"
## ...with a few loose stones in small clusters down the middle
@export var gravel_set := "gravel_path/Ground108"
## Light, dry soil: worn, sunny slopes and ridges, bare patches in the meadows, and the
## frayed edges of trails
@export var light_soil_set := "soil/Ground109"
## Dark, damp soil: where grass gives way to rock, in hollows and gullies, above the shore,
## and in patches along trail edges
@export var dark_soil_set := "soil/Ground048"
## Plain rock, between the others on the mountains (shown with its moss muted):
@export var rock_set := "rock_cliff/Rock051"
## Mossy rock, on moderately steep and shaded slopes:
@export var mossy_rock_set := "rock_cliff/Rock051"
## Sheer cliff rock, on the steepest faces:
@export var cliff_rock_set := "rock_cliff/Rock022"
## Scree, at the foot of steep slopes and down the gullies:
@export var scree_set := "rock_cliff/Rocks011"
## How many meters each set repeats over, and its color tint. Sets not listed repeat every
## 3 m (4 m for rock), slightly darkened.
const SET_LOOKS := {
	"forest_floor/Ground037": [3.0, Color(0.5, 0.52, 0.4)],
	"gravel_path/Ground108": [2.5, Color(0.92, 0.86, 0.78)],
	"gravel_path/Ground049C": [3.0, Color(0.86, 0.82, 0.76)],
	"soil/Ground109": [3.5, Color(0.82, 0.8, 0.72)],
	"soil/Ground048": [2.5, Color(0.85, 0.8, 0.76)],
	"rock_cliff/Rock051": [4.0, Color(0.66, 0.64, 0.6)],
	"rock_cliff/Rock022": [6.0, Color(0.74, 0.72, 0.69)],
	"rock_cliff/Rocks011": [2.5, Color(0.82, 0.8, 0.76)],
}

@export_group("Ground sculpt")
## Where the Sculpt Brush's shaping is kept. It's made the first time you sculpt, saved each
## time you finish a stroke, and survives every rebuild.
@export_file("*.res") var ground_sculpt_path := "res://world/terrain_sculpt.res"

@export_group("Ground paint")
## Where the Texture Brush's painting is kept. It's made the first time you paint, saved
## each time you finish a stroke, and survives every rebuild.
@export_file("*.res") var ground_paint_path := "res://world/terrain_paint.res"
## How many meters each painted pixel covers (smaller = finer painting, bigger file)
const PAINT_TEXEL := 1.0

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
## Editor planning view: tint the ground green where the player can walk, yellow near the
## limit, and red where it's too steep to climb. Never shows in the game.
@export var show_slope_view := false:
	set(value):
		show_slope_view = value
		_update_slope_view()
## Show terrain modifier markers in the editor. Unticking hides them all (they still shape
## the ground); they never show in the game either way.
@export var show_modifier_markers := true:
	set(value):
		show_modifier_markers = value
		if is_inside_tree():
			for modifier in get_tree().get_nodes_in_group("terrain_modifiers"):
				modifier.refresh_rings()
			for zone in get_tree().get_nodes_in_group("clear_zones"):
				zone.refresh_rings()

# The smoothed height of every grid point, in game meters above the lowest ground.
# Stored row by row, west to east, starting from the north edge.
var _heights := PackedFloat32Array()
# The same heights straight from the heightmap, before any terrain modifiers, so one
# marker's patch can be redone without rebuilding the whole valley
var _base_heights := PackedFloat32Array()
# How worn each grid point is by trails (0 = grass, 255 = bare dirt), handed to the ground's
# paint as a texture so trails show up in both the editor and the game
var _trail_mask := PackedByteArray()
# Where trails run (1 = on a trail), so trees, rocks and plants are kept off them
var _trail_cover := PackedByteArray()
# The Clear Zones in the world, gathered at the start of each build
var _clear_zones: Array = []
# For each trail (by instance id), the ground just before it shaped it
var _trail_ground := {}
# How ragged the trail's edge is at each grid point (its Edge Noise, 0-255), and where its
# Edge Grass is on (1), so grass grows in tufts along the edges and a few patches on it
var _trail_noise := PackedByteArray()
var _trail_grass := PackedByteArray()
# How much forest floor covers each grid point (0-255), from the trees standing near it
var _forest_floor := PackedByteArray()
# The ground's paint, as one picture handed to the ground material: trail wear, trail edge
# noise and forest floor, in red, green and blue (see terrain.gdshader)
var _ground_image: Image
var _ground_texture: ImageTexture
# The ground material the terrain is actually drawn with: a copy of Ground Material, so the
# pictures the valley makes for it (which change on every rebuild) are never saved into
# terrain_material.tres
var _ground: Material
# What's been painted with the Texture Brush (loaded from Ground Paint Path), and the
# pictures made from it for the ground material
var _paint: Resource
var _paint_textures: Array[ImageTexture] = []
# Spots where objects were rubbed out with the Object Painter (so scattered trees, rocks and
# resources don't come back there), sorted into squares of the map: each is (x, z, radius)
const ERASE_SQUARE := 8.0
var _erased := {}
# Objects placed by hand with the Object Painter, so the scattering leaves room around them
var _placed_spots := {}
# Big placed objects that keep scattered things away: x, z and how far (meters)
var _placed_clears: Array[Vector3] = []
# The ground as it'd be without the tall peaks' ridges. Things are scattered using this, then
# lifted onto the ridges, so the ridges don't reshuffle the forest and resources below them.
var _unridged := PackedFloat32Array()
var _ridge_cuts := PackedFloat32Array()
var _ridge_key := ""
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


const TerrainModifierScript = preload("res://world/terrain_modifier.gd")
# Marks a resource that's seated on the ground by _settle_on_ground(), with what that needs
const SETTLE_META := &"settle_on_ground"
# Marks a Clear Zone that sits under a placed building
const BUILDING_META := &"under_building"
# How many points around a resource's footprint to check the ground at, on each of two rings
const SETTLE_SAMPLES := 12

# How far the Sculpt Brush has moved each grid point (empty until there's any sculpting), and
# the ground just before that was added, so the brush can work out where the ground is
# without any trails on it
var _sculpt_deltas := PackedFloat32Array()
var _pre_sculpt := PackedFloat32Array()
# The stroke in progress: the sculpting and the heights as they were before it, and the patch
# of map (x, z) it has touched. Nothing in progress when the area is empty.
var _stroke_deltas := PackedFloat32Array()
var _stroke_heights := PackedFloat32Array()
var _stroke_area := Rect2()
var _in_stroke := false
const TerrainSculptScript = preload("res://world/terrain_sculpt.gd")

# The heights from before a modifier started moving, while the ground is showing a quick
# preview of where it's going. Empty when there's no preview.
var _preview_start := PackedFloat32Array()
var _last_preview_at := 0
## At most this often the ground follows a moving modifier, in milliseconds
const PREVIEW_EVERY := 40

## The dirt paths the player has painted in the game with the hammer (see PaintedPaths); none in
## the editor
var painted_paths: PaintedPaths

# Counts rebuild requests, so a burst of them (like dragging a marker) only rebuilds once
var _rebuild_ticket := 0
# The patch of map (x, z) waiting to be rebuilt, gathered from every request in that burst
var _dirty_area := Rect2()


func _enter_tree() -> void:
	# So terrain modifiers can find the valley and ask it to rebuild
	add_to_group("valley")


func _ready() -> void:
	generate()
	if not Engine.is_editor_hint():
		painted_paths = PaintedPaths.new()
		painted_paths.name = "PaintedPaths"
		painted_paths.valley = self
		add_child(painted_paths)
		painted_paths.setup(map_rect(), _ground)
		_place_player()
		var respawner := Respawner.new()
		respawner.name = "Respawner"
		respawner.min_distance = respawn_min_distance
		respawner.handler = _on_respawn_due
		add_child(respawner)
		add_to_group("saveable")


# ---- What's been gathered, felled and mined, and bringing it back ----
#
# Everything scattered is placed the same way every time from the map seed, so a save only needs
# what's changed since: which things are gone, bare, felled or mined (by id), and where respawned
# pickups ended up. The respawner keeps when each comes back.

# Labels each scattered thing with an id that's the same every time the valley is built
const ID_META := &"save_id"
# How far through the regrowing time a felled tree's stump grows a sapling
const TREE_SAPLING_AT := 0.4

# Scattered things by id
var _by_id := {}
# How to put each scattered pickup back: id -> {"scene": path, "settle": Dictionary, "spot": Vector3}
var _pickup_specs := {}
# id -> what's happened to it: "gone" (a pickup), "empty" (a berry bush), "stump" or "sapling"
# (a tree), "mined" (a boulder; scattered ones are "rock:<number>")
var _changes := {}
# Respawned pickups that came back somewhere else: id -> [x, z]
var _moved := {}


## The id of something in the world: its label if the valley scattered it, otherwise its path
## from here (for things placed by hand in the world scene, which are always in the same place)
func id_of(node: Node) -> String:
	if node.has_meta(ID_META):
		return node.get_meta(ID_META)
	return "path:" + str(get_path_to(node))


func _node_for(id: String) -> Node:
	if id.begins_with("path:"):
		return get_node_or_null(NodePath(id.substr(5)))
	var node = _by_id.get(id)
	return node if is_instance_valid(node) else null


# Numbers everything scattered, in the order it was made (the same order every time)
func _assign_ids() -> void:
	_by_id.clear()
	_pickup_specs.clear()
	var count := 0
	for child in get_children():
		if not child.has_method("gather"):
			continue
		var id := "n%d" % count
		count += 1
		child.set_meta(ID_META, id)
		_by_id[id] = child
		if child.has_meta(SETTLE_META):
			_pickup_specs[id] = {"scene": child.scene_file_path, "settle": child.get_meta(SETTLE_META), "spot": child.position}


func _respawner() -> Node:
	return get_node_or_null("Respawner")


## A scattered pickup has been gathered up: it's gone, and comes back after its kind's respawn time
func pickup_gathered(item: Node3D) -> void:
	var id := id_of(item)
	var days := respawn_days_for(item.get("resource_name"))
	if not _pickup_specs.has(id) or days <= 0.0 or _respawner() == null:
		return
	_changes[id] = "gone"
	_respawner().schedule(days, item.global_position, "pickup", id)


## A berry bush has been picked clean; its berries grow back
func bush_emptied(bush: Node3D) -> void:
	var id := id_of(bush)
	_changes[id] = "empty"
	if berries_regrow_days > 0.0 and _respawner():
		_respawner().schedule(berries_regrow_days, bush.global_position, "berries", id)


## A tree has been felled; its stump grows a sapling, then a full tree
func tree_felled(tree: Node3D) -> void:
	var id := id_of(tree)
	_changes[id] = "stump"
	if tree_regrow_days > 0.0 and _respawner():
		_respawner().schedule(tree_regrow_days * TREE_SAPLING_AT, tree.global_position, "sapling", id)
		_respawner().schedule(tree_regrow_days, tree.global_position, "tree", id)


## A boulder placed by hand has been mined out; it comes back
func rock_mined(rock: Node3D) -> void:
	var id := id_of(rock)
	_changes[id] = "mined"
	if boulder_respawn_days > 0.0 and _respawner():
		_respawner().schedule(boulder_respawn_days, rock.global_position, "rock", id)


## One of the scattered rocks has been mined out; it comes back
func scattered_rock_mined(index: int, where: Vector3) -> void:
	_changes["rock:%d" % index] = "mined"
	if boulder_respawn_days > 0.0 and _respawner():
		_respawner().schedule(boulder_respawn_days, where, "scattered_rock", str(index))


# A booking came due and the player is away: bring that thing back
func _on_respawn_due(kind: String, id: String) -> void:
	if kind == "scattered_rock":
		var foliage = get_node_or_null("Foliage")
		if foliage and foliage.restore_rock(int(id)):
			_changes.erase("rock:" + id)
		return
	if kind == "pickup":
		_respawn_pickup(id)
		return
	var node := _node_for(id)
	if node == null:
		return
	match kind:
		"berries":
			node.regrow()
			_changes.erase(id)
		"sapling":
			node.set_stage("sapling")
			_changes[id] = "sapling"
		"tree":
			node.set_stage("full")
			_changes.erase(id)
		"rock":
			if node.come_back():
				_changes.erase(id)


## How many in-game days until a gathered pickup of this kind comes back (0 = never)
func respawn_days_for(resource: String) -> float:
	match resource:
		"Plant Fiber":
			return plant_fiber_respawn_days
		"Sticks":
			return sticks_respawn_days
		"Stone":
			return stone_respawn_days
	return 0.0


# Puts a gathered pickup back: at its old spot if that's still good, or a good one close by
# (dry, off trails, clear of buildings), seated on the ground as before, with the same id
func _respawn_pickup(id: String) -> void:
	if not _pickup_specs.has(id):
		return
	var spec: Dictionary = _pickup_specs[id]
	var spot: Vector3 = spec["spot"]
	var water := water_height()
	var radius: float = spec["settle"]["radius"]
	for attempt in 24:
		var x := spot.x
		var z := spot.z
		if attempt > 0:
			var nudge := Vector2.from_angle(randf() * TAU) * randf_range(1.0, 5.0)
			x += nudge.x
			z += nudge.y
		if get_height(x, z) < water + 0.2 or is_on_trail(x, z, 1.0) or is_under_building(x, z, radius):
			continue
		var item: Node3D = (load(spec["scene"]) as PackedScene).instantiate()
		item.position = Vector3(x, get_height(x, z), z)
		item.set_meta(SETTLE_META, spec["settle"])
		item.set_meta(ID_META, id)
		_settle_on_ground(item)
		add_child(item)
		_by_id[id] = item
		_changes.erase(id)
		if attempt == 0:
			_moved.erase(id)
		else:
			_moved[id] = [x, z]
		return
	# Nowhere good nearby right now: try again a little later
	if _respawner():
		_respawner().schedule(0.1, to_global(spot), "pickup", id)


func save_key() -> String:
	return "world"


func save_priority() -> int:
	return 10


func save_data() -> Dictionary:
	return {"changes": _changes.duplicate(), "moved": _moved.duplicate(true)}


func load_data(data: Dictionary) -> void:
	_changes = Dictionary(data.get("changes", {})).duplicate()
	_moved = Dictionary(data.get("moved", {})).duplicate(true)
	var foliage = get_node_or_null("Foliage")
	for id in _moved:
		var node := _node_for(id) as Node3D
		var spot: Array = _moved[id]
		if node and spot.size() >= 2:
			node.position = Vector3(float(spot[0]), 0.0, float(spot[1]))
			_settle_on_ground(node)
	for id in _changes:
		var state: String = _changes[id]
		if id.begins_with("rock:"):
			if foliage:
				foliage.set_rock_mined(int(id.substr(5)))
			continue
		var node := _node_for(id)
		if node == null:
			continue
		match state:
			"gone":
				remove_child(node)
				node.queue_free()
				_by_id.erase(id)
			"empty":
				node.set_empty()
			"stump", "sapling":
				node.set_stage(state)
			"mined":
				node.set_mined()


## True if a placed building's footprint (its Clear Zone) reaches within `margin` of (x, z)
func is_under_building(x: float, z: float, margin := 0.0) -> bool:
	for zone in _clear_zones:
		if is_instance_valid(zone) and zone.is_inside_tree() and zone.has_meta(BUILDING_META):
			var middle := Vector2(zone.global_position.x, zone.global_position.z)
			if Vector2(x, z).distance_to(middle) < zone.radius + margin:
				return true
	return false


## In the editor: rebuild the terrain shortly after the last change (a terrain modifier was
## moved or adjusted). Waiting a moment means dragging a marker doesn't rebuild every frame.
func request_rebuild() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	_dirty_area = Rect2()
	_rebuild_ticket += 1
	var ticket := _rebuild_ticket
	get_tree().create_timer(0.5).timeout.connect(func():
		if ticket == _rebuild_ticket and is_inside_tree():
			generate())


## In the editor: rebuild just one patch of the map (x, z) shortly after the last request.
## Terrain modifiers call this when they're moved or adjusted, so only the chunks they touch
## are redone and the change shows up quickly.
func request_rebuild_area(area: Rect2) -> void:
	if not Engine.is_editor_hint() or not is_inside_tree() or not area.has_area():
		return
	_dirty_area = area if not _dirty_area.has_area() else _dirty_area.merge(area)
	_rebuild_ticket += 1
	var ticket := _rebuild_ticket
	get_tree().create_timer(0.15).timeout.connect(func():
		if ticket == _rebuild_ticket and is_inside_tree():
			var patch := _dirty_area
			_dirty_area = Rect2()
			_end_preview()
			_rebuild_area(patch))


## How high the water surface sits, in game meters
func water_height() -> float:
	return (water_level - min_elevation) * height_scale


## How high the ground is for a trail's own points: the heightmap plus every other modifier,
## but not that trail itself (or any trail it's shaped together with). Falls back to the
## finished ground for a trail that hasn't been built yet.
func ground_height_for(trail: Node, x: float, z: float) -> float:
	var ground: PackedFloat32Array = _trail_ground.get(trail.get_instance_id(), _heights)
	if ground.size() != _heights.size():
		ground = _heights
	return _height_in(ground, x, z)


## True once the heights have been read, so get_height() has something to answer with
func has_heights() -> bool:
	return not _heights.is_empty()


## How high the ground is at any spot on the map, blending smoothly between grid points
func get_height(x: float, z: float) -> float:
	return _height_in(_heights, x, z)


# The same, but reading from any set of heights (like a copy from before a change)
func _height_in(values: PackedFloat32Array, x: float, z: float) -> float:
	var gx := clampf((x + _width * 0.5) / _cell_x, 0.0, _points_x - 1.001)
	var gz := clampf((z + _depth * 0.5) / _cell_z, 0.0, _points_z - 1.001)
	var xi := int(gx)
	var zi := int(gz)
	var i := zi * _points_x + xi
	var north := lerpf(values[i], values[i + 1], gx - xi)
	var south := lerpf(values[i + _points_x], values[i + _points_x + 1], gx - xi)
	return lerpf(north, south, gz - zi)


## How high the drawn ground is at a spot: exactly on its triangles, which split each grid
## cell from its north-east corner to its south-west one (see _chunk_mesh). On steep, folded
## ground this can differ a fair bit from get_height(), which blends the four corners.
func get_surface_height(x: float, z: float) -> float:
	var gx := clampf((x + _width * 0.5) / _cell_x, 0.0, _points_x - 1.001)
	var gz := clampf((z + _depth * 0.5) / _cell_z, 0.0, _points_z - 1.001)
	var xi := int(gx)
	var zi := int(gz)
	var fx := gx - xi
	var fz := gz - zi
	var i := zi * _points_x + xi
	var north_west := _heights[i]
	var north_east := _heights[i + 1]
	var south_west := _heights[i + _points_x]
	if fx + fz <= 1.0:
		return north_west + (north_east - north_west) * fx + (south_west - north_west) * fz
	var south_east := _heights[i + _points_x + 1]
	return south_east + (south_west - south_east) * (1.0 - fx) + (north_east - south_east) * (1.0 - fz)


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
		# (painted paths are the player's, and stay)
		if child == painted_paths:
			continue
		remove_child(child)
		child.queue_free()

	if not _load_heights():
		return
	_ground = ground_material.duplicate() if ground_material else null
	_apply_texture_sets()
	if painted_paths:
		painted_paths.setup(map_rect(), _ground)
	_base_heights = _heights.duplicate()
	_preview_start = PackedFloat32Array()
	for layer in [_trail_mask, _trail_cover, _trail_noise, _trail_grass, _forest_floor]:
		layer.resize(_heights.size())
		layer.fill(0)
	_trail_ground.clear()
	_load_sculpt()
	# Reshape the ground with any terrain modifiers, before anything is built on it
	_apply_modifiers()
	_unridged = _heights.duplicate()
	if _add_peak_ridges():
		_heights = _base_heights.duplicate()
		for layer in [_trail_mask, _trail_cover, _trail_noise, _trail_grass]:
			layer.fill(0)
		_trail_ground.clear()
		_apply_modifiers()
	_update_ground_texture()
	_update_flow_map()
	_load_paint()
	# Set the crash site and other hand-placed things down on the final ground, and note
	# where the wreck is so trees and boulders can keep clear of it
	_place_crash_site()
	_snap_hand_placed()
	# Let the ground's paint know where the water is, for the muddy shoreline,
	# and where the ship came down, for the churned mud and puddles
	_update_slope_view()
	if _ground is ShaderMaterial:
		_ground.set_shader_parameter("water_height", water_height())
		_ground.set_shader_parameter("mud_center", _crash_center)
		_ground.set_shader_parameter("mud_radius", _crash_radius * 0.75)
		_ground.set_shader_parameter("scorch_center", _scorch_center)
		_ground.set_shader_parameter("scorch_radius", 8.5 if _crash_radius > 0.0 else 0.0)
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
	# Clear zones are looked up once here, since every tree, rock and plant checks them
	_clear_zones = get_tree().get_nodes_in_group("clear_zones")
	# So is where objects were rubbed out or placed by hand with the Object Painter
	_gather_painted_objects()
	var final_heights := _heights
	_heights = _unridged
	_scatter_trees()
	_scatter_feature_trees()
	_scatter_resources()
	_scatter_starter_kit()
	_bury_deposits()

	# Grass, ferns and boulders
	var foliage = preload("res://world/foliage.gd").new()
	foliage.name = "Foliage"
	foliage.valley = self
	add_child(foliage)
	foliage.build_rocks(_ground)
	_heights = final_heights
	_lift_onto_ridges()
	_assign_ids()
	# Mossy forest floor under all the trees, scattered and placed alike
	refresh_forest_floor()
	_refresh_marker_rings(map_rect())


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
	var chunk_heights := PackedFloat32Array()
	chunk_heights.resize(n * n)
	for j in n:
		for k in n:
			chunk_heights[j * n + k] = _heights[(first_z + j) * _points_x + first_x + k]

	var chunk := StaticBody3D.new()
	chunk.name = "Chunk_%d_%d" % [cx, cz]
	chunk.position = corner
	# So placing a building can tell the ground from things standing on it
	chunk.add_to_group("terrain_ground")
	add_child(chunk)

	var mesh := MeshInstance3D.new()
	mesh.mesh = _chunk_mesh(cx, cz)
	mesh.material_override = _ground
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


# One chunk's ground, from the heights as they are right now
func _chunk_mesh(cx: int, cz: int) -> ArrayMesh:
	var n := chunk_cells + 1
	var first_x := cx * chunk_cells
	var first_z := cz * chunk_cells
	var corner := Vector3(-_width * 0.5 + first_x * _cell_x, 0.0, -_depth * 0.5 + first_z * _cell_z)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(n * n)
	normals.resize(n * n)
	uvs.resize(n * n)
	for j in n:
		for k in n:
			var i := j * n + k
			var gx := first_x + k
			var gz := first_z + j
			var h := _heights[gz * _points_x + gx]
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
	return _make_mesh(vertices, normals, uvs, indices)


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
	skirt.material_override = _ground
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


# Carves ridges and gullies into the tall peaks, in the ground everything else builds on: gullies
# are cut where water would drain, so they run downhill and branch into each other, leaving
# sharp ridges between them. It fades in with height, so nothing changes below Ridges From.
# True if it changed anything. Worked out once, then kept until the settings change.
func _add_peak_ridges() -> bool:
	if ridge_depth <= 0.0:
		return false
	var key := "%s %s %s %s %s %s" % [heightmap_path, map_seed, ridges_from, ridges_full, ridge_depth, ridge_spacing]
	if _ridge_key != key or _ridge_cuts.size() != _base_heights.size():
		_ridge_cuts = _work_out_ridges()
		_ridge_key = key
	var changed := false
	for i in _base_heights.size():
		if _ridge_cuts[i] != 0.0:
			_base_heights[i] += _ridge_cuts[i]
			changed = true
	return changed


func _work_out_ridges() -> PackedFloat32Array:
	var count := _base_heights.size()
	var cuts := PackedFloat32Array()
	cuts.resize(count)
	# The slopes are too even to drain anywhere interesting by themselves, so a rumpled pattern
	# is laid over them, and the water gathers in its folds
	var rumple := FastNoiseLite.new()
	rumple.seed = map_seed + 31
	rumple.noise_type = FastNoiseLite.TYPE_PERLIN
	rumple.frequency = 1.0 / maxf(ridge_spacing, 8.0)
	rumple.fractal_type = FastNoiseLite.FRACTAL_FBM
	rumple.fractal_octaves = 4
	rumple.domain_warp_enabled = true
	rumple.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	rumple.domain_warp_amplitude = ridge_spacing * 0.4
	rumple.domain_warp_frequency = 0.5 / maxf(ridge_spacing, 8.0)
	var levels := PackedFloat32Array()
	levels.resize(count)
	var flow := PackedFloat32Array()
	flow.resize(count)
	# Only ground near or above the ridges matters
	var floor_level := ridges_from - 25.0
	var order := PackedInt32Array()
	var lowest := INF
	var highest := -INF
	for gz in _points_z:
		for gx in _points_x:
			var i := gz * _points_x + gx
			levels[i] = _base_heights[i]
			if _base_heights[i] < floor_level:
				continue
			levels[i] += rumple.get_noise_2d(-_width * 0.5 + gx * _cell_x, -_depth * 0.5 + gz * _cell_z) * ridge_depth * 0.9
			flow[i] = 1.0
			lowest = minf(lowest, levels[i])
			highest = maxf(highest, levels[i])
			order.append(i)
	if order.is_empty():
		return cuts
	# Highest first, without a full sort: into bins a tenth of a meter tall
	var bins := int((highest - lowest) / 0.1) + 1
	var starts := PackedInt32Array()
	starts.resize(bins + 1)
	for i in order:
		starts[bins - int((levels[i] - lowest) / 0.1)] += 1
	for b in bins:
		starts[b + 1] += starts[b]
	var sorted := PackedInt32Array()
	sorted.resize(order.size())
	for i in order:
		var b := bins - 1 - int((levels[i] - lowest) / 0.1)
		sorted[starts[b]] = i
		starts[b] += 1
	for i in sorted:
		var gx := i % _points_x
		var gz := i / _points_x
		var low_level := levels[i]
		var low := -1
		for dz in range(maxi(gz - 1, 0), mini(gz + 2, _points_z)):
			for dx in range(maxi(gx - 1, 0), mini(gx + 2, _points_x)):
				var other := dz * _points_x + dx
				if levels[other] < low_level:
					low_level = levels[other]
					low = other
		if low >= 0:
			flow[low] += flow[i]
	# The more water, the deeper the cut, by how many doublings it's collected. The rumple stays
	# too, so the ridges between the gullies stand up. Softened a little, so a cut's sides slope.
	var carve := PackedFloat32Array()
	carve.resize(count)
	for i in sorted:
		carve[i] = minf(log(flow[i]) / log(2.0) / 9.0, 1.0)
	carve = _blur(carve, _points_x, _points_z, 1)
	for gz in _points_z:
		for gx in _points_x:
			var i := gz * _points_x + gx
			var amount := smoothstep(ridges_from, ridges_full, _base_heights[i])
			if amount > 0.0:
				var fold := rumple.get_noise_2d(-_width * 0.5 + gx * _cell_x, -_depth * 0.5 + gz * _cell_z)
				cuts[i] = (fold * 0.8 - carve[i] + 0.25) * ridge_depth * amount
	return cuts

# Moves what was scattered on the ground without ridges up or down onto the ridges
func _lift_onto_ridges() -> void:
	for child in get_children():
		var thing := child as Node3D
		if thing == null or not thing.has_method("gather"):
			continue
		if thing.has_meta(SETTLE_META):
			_settle_on_ground(thing)
			continue
		var p := thing.position
		thing.position.y += _height_in(_heights, p.x, p.z) - _height_in(_unridged, p.x, p.z)
	var foliage := get_node_or_null("Foliage")
	if foliage:
		for i in foliage.scattered_rock_count():
			var place: Transform3D = foliage.rock_transform(i)
			var change := _height_in(_heights, place.origin.x, place.origin.z) - _height_in(_unridged, place.origin.x, place.origin.z)
			if absf(change) > 0.0:
				place.origin.y += change
				foliage.set_rock_transform(i, place)


## True above the tree line, where no trees are scattered. It wanders 10 m up and down. Based on
## the ground without ridges, like everything scattered.
func is_above_tree_line(x: float, z: float) -> bool:
	return _height_in(_unridged, x, z) > tree_line + _forest.get_noise_2d(x * 0.7, z * 0.7) * 10.0


# Scatter trees anywhere that's dry and not too steep
func _scatter_trees() -> void:
	var using_pack := not forest_trees.is_empty() or not young_trees.is_empty()
	if not using_pack and not tree_scene:
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
		if h < dry_above or get_slope(x, z) > max_tree_slope or is_near_crash_site(x, z) or is_on_trail(x, z, 2.0) or is_cleared(x, z, "trees") or is_erased(x, z) or is_near_placed(x, z, 3.0):
			continue
		var tree: Node3D
		if using_pack:
			# Mostly full-grown trees, with some young ones among them
			var young := not young_trees.is_empty() and (forest_trees.is_empty() or rng.randf() < young_tree_share)
			var pool: Array[PackedScene] = young_trees if young else forest_trees
			tree = pool[rng.randi() % pool.size()].instantiate()
			var size := rng.randf_range(1.0 - tree_size_variation, 1.0 + tree_size_variation)
			tree.scale = Vector3.ONE * size
			tree.position = Vector3(x, _tree_ground(x, z, tree, size), z)
		else:
			tree = tree_scene.instantiate()
			tree.scale = Vector3.ONE * rng.randf_range(0.8, 1.4)
			tree.position = Vector3(x, h - 0.2, z)
		tree.rotation.y = rng.randf() * TAU
		# Above the tree line this tree just isn't planted. It still counts and keeps its spot,
		# so everything scattered below stays exactly where it was.
		if is_above_tree_line(x, z):
			tree.free()
		else:
			add_child(tree)
		_remember_spot(Vector2(x, z), _taken_spots)
		_remember_spot(Vector2(x, z), _tree_spots)
		placed += 1


# The few special trees, placed after the forest so its layout stays the same: tall Douglas
# firs on the hilltops, where they stand out, and willows right at the water's edge
func _scatter_feature_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed + 101
	var water := water_height()
	var fir := _optional_scene(landmark_fir_scene)
	if fir and landmark_fir_count > 0:
		# Try spots all over, scored by how far they rise above the ground 40 m around them,
		# and a little by how high they are; then take the best, well apart from each other
		var spots := []
		for i in 3000:
			var x := rng.randf_range(-_width * 0.5 + 20.0, _width * 0.5 - 20.0)
			var z := rng.randf_range(-_depth * 0.5 + 20.0, _depth * 0.5 - 20.0)
			var h := get_height(x, z)
			if h < water + 3.0 or not _feature_spot_ok(x, z, 25.0):
				continue
			var around := 0.0
			for k in 8:
				var p := Vector2(x, z) + Vector2.from_angle(TAU * k / 8.0) * 40.0
				around += get_height(p.x, p.y)
			spots.append([h - around / 8.0 + (h - water) * 0.1, Vector2(x, z)])
		spots.sort_custom(func(a, b): return a[0] > b[0])
		var placed: Array[Vector2] = []
		for s in spots:
			if placed.size() >= landmark_fir_count:
				break
			var spot: Vector2 = s[1]
			if placed.any(func(other): return other.distance_to(spot) < 150.0) or _distance_to_nearest(spot, _tree_spots, 3.0) < 3.0:
				continue
			_plant_tree(fir, spot, rng)
			placed.append(spot)
	var willow := _optional_scene(willow_scene)
	if willow and willow_count > 0:
		var placed: Array[Vector2] = []
		var tries := 0
		while placed.size() < willow_count and tries < 20000:
			tries += 1
			var spot := Vector2(rng.randf_range(-_width * 0.5 + 10.0, _width * 0.5 - 10.0), rng.randf_range(-_depth * 0.5 + 10.0, _depth * 0.5 - 10.0))
			# Dry ground only just above the water, with the water a few meters off
			var h := get_height(spot.x, spot.y)
			if h < water + 0.3 or h > water + 1.8 or not _feature_spot_ok(spot.x, spot.y, 20.0) or not _water_nearby(spot.x, spot.y, 5.0):
				continue
			if placed.any(func(other): return other.distance_to(spot) < 30.0) or _distance_to_nearest(spot, _tree_spots, 2.5) < 2.5:
				continue
			_plant_tree(willow, spot, rng)
			placed.append(spot)


# The scene at this path, or null if there isn't one (like a paid model left out of the repository)
func _optional_scene(path: String) -> PackedScene:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as PackedScene


# True if a special tree may grow here: gentle enough ground, clear of the wreck, the trails
# and any Clear Zone
func _feature_spot_ok(x: float, z: float, max_slope: float) -> bool:
	return get_slope(x, z) <= max_slope and not is_above_tree_line(x, z) and not is_near_crash_site(x, z) and not is_on_trail(x, z, 3.0) and not is_cleared(x, z, "trees") and not is_erased(x, z) and not is_near_placed(x, z, 4.0)


# Stands one tree at this spot, sized and turned at random like the rest of the forest
func _plant_tree(scene: PackedScene, spot: Vector2, rng: RandomNumberGenerator) -> void:
	var tree: Node3D = scene.instantiate()
	var size := rng.randf_range(1.0 - tree_size_variation, 1.0 + tree_size_variation)
	tree.scale = Vector3.ONE * size
	tree.position = Vector3(spot.x, _tree_ground(spot.x, spot.y, tree, size), spot.y)
	tree.rotation.y = rng.randf() * TAU
	add_child(tree)
	_remember_spot(spot, _taken_spots)
	_remember_spot(spot, _tree_spots)


# How high to stand a tree from the pine pack: on the lowest ground around its trunk (so no
# roots hang in the air on the downhill side of a slope), then sunk a little further so the
# root flare goes into the earth. Big trees sink about 0.3-0.5 m; small trees and saplings
# only a few centimeters, so they don't disappear.
func _tree_ground(x: float, z: float, tree: Node, size: float) -> float:
	var tall: float = tree.get("tree_height") if tree.get("tree_height") != null else 8.0
	var trunk: float = tree.get("trunk_radius") if tree.get("trunk_radius") != null else 0.3
	tall *= size
	trunk *= size
	# The root flare spreads out to a few times the trunk's radius
	var reach := maxf(trunk * 3.0, 0.15)
	var lowest := get_height(x, z)
	for k in 8:
		var p := Vector2(x, z) + Vector2.from_angle(TAU * k / 8.0) * reach
		lowest = minf(lowest, get_height(p.x, p.y))
	var sink := clampf(tall * 0.025, 0.03, 0.5)
	return lowest - sink


# Every kind of resource, with where it likes to grow:
#   scene, count, how far apart (m), how big a clump pattern (smaller = bigger clumps),
#   how clumpy (0 = spread evenly, 1 = only in tight clusters), size range,
#   how much it leans to match the slope (0 = stands upright like a plant, 0.6 = settles
#   partway like a rock, 1 = lies flat along the ground like fallen sticks), its "likes this
#   spot" check, and how far it spreads from its middle (m, before resizing), which decides
#   how deep to sink it. Kinds with one more value, how far to press into the ground (m, before
#   resizing), are seated properly against the ground around them: see _settle_on_ground().
func _resource_kinds() -> Array:
	# Copper goes before tin, so tin can look for copper to grow near
	return [
		[stone_scene, stone_count, 3.0, 0.02, 0.25, Vector2(0.85, 1.15), 0.85, _likes_stone, 0.36, 0.04],
		# Plant fiber: seated over its soil ball (0.27 m across the middle), so only that is buried and
		# the leaves stand clear; it leans most of the way with the slope so the uphill leaves don't sink
		[fiber_scene, fiber_count, 2.0, 0.03, 0.4, Vector2(0.85, 1.15), 0.8, _likes_fiber, 0.27, 0.01],
		[stick_scene, stick_count, 2.0, 0.03, 0.3, Vector2(0.85, 1.15), 1.0, _likes_sticks, 0.59, 0.01],
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
			if (_crash_radius > 0.0 and spot.distance_to(_crash_center) < crash_site_gap) or is_on_trail(x, z, 1.0) or is_cleared(x, z, "resources") or is_erased(x, z):
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
			if kinds[k].size() > 9:
				_place_seated(item, kinds[k], x, z, size, turn)
				placed += 1
				continue
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


# Puts down one resource of a kind that's seated on the ground (one with a press value in
# _resource_kinds()), at this spot, size and turn, and notes the spot as taken
func _place_seated(item: Node3D, kind: Array, x: float, z: float, size: float, turn: Basis) -> void:
	item.position = Vector3(x, get_height(x, z), z)
	item.set_meta(SETTLE_META, {"turn": turn, "size": size, "lean": kind[6], "radius": kind[8] * size, "press": kind[9] * size})
	_settle_on_ground(item)
	add_child(item)
	_remember_spot(Vector2(x, z), _taken_spots)


# Lays out a few stones, sticks and plant fiber near where the player starts, on the side of the
# start point away from the wreck. Same placement rules as everywhere else (dry ground, seated,
# off trails, not on top of anything), with its own random numbers from the map seed.
func _scatter_starter_kit() -> void:
	var site = get_node_or_null(crash_site_path)
	if site == null or _crash_radius <= 0.0:
		return
	var start: Vector3 = to_local(site.spawn_point())
	var start_spot := Vector2(start.x, start.z)
	var away := start_spot - _crash_center
	away = away.normalized() if away.length() > 0.1 else Vector2.RIGHT
	var water := water_height()
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed * 3000 + 7
	var kinds := _resource_kinds()
	for wanted in [[stone_scene, starter_stone], [stick_scene, starter_sticks], [fiber_scene, starter_fiber]]:
		var kind: Array = []
		for row in kinds:
			if row[0] == wanted[0] and row.size() > 9:
				kind = row
		if kind.is_empty():
			continue
		var placed := 0
		var tries := 0
		while placed < wanted[1] and tries < 300:
			tries += 1
			# Somewhere 4 to 12 m from the start point, out on the side away from the wreck
			var angle := away.angle() + rng.randf_range(-1.4, 1.4)
			var spot := start_spot + Vector2.from_angle(angle) * rng.randf_range(4.0, 12.0)
			var h := get_height(spot.x, spot.y)
			if h < water + 0.2 or get_slope(spot.x, spot.y) > 25.0 or is_on_trail(spot.x, spot.y, 1.0):
				continue
			if _distance_to_nearest(spot, _taken_spots, 1.8) < 1.8:
				continue
			var size := rng.randf_range(kind[5].x, kind[5].y)
			_place_seated(wanted[0].instantiate(), kind, spot.x, spot.y, size, Basis(Vector3.UP, rng.randf() * TAU))
			placed += 1


## Adds a Clear Zone while the game is running (one goes under each building that's placed):
## regrows the grass and ferns around it so they keep out, and if it clears rocks, takes away the
## scattered boulders and the small decorations painted by hand (ones with nothing solid to them)
## inside it
func add_clear_zone(zone: Node3D) -> void:
	var timing := SpikeLog.begin()
	_add_clear_zone(zone)
	SpikeLog.end("clear zone added (grass kept out from under a floor)", timing)


func _add_clear_zone(zone: Node3D) -> void:
	if not _clear_zones.has(zone):
		_clear_zones.append(zone)
	var reach: float = zone.radius
	var middle := Vector2(zone.global_position.x, zone.global_position.z)
	var foliage = get_node_or_null("Foliage")
	if foliage and zone.clear_plants:
		# The grass and ferns already there inside it just go (no regrowing the whole patch)
		foliage.hide_plants_in(middle, reach)
	if not zone.clear_rocks:
		return
	if foliage:
		foliage.hide_rocks_in(middle, reach)
	for holder in get_tree().get_nodes_in_group("placed_objects"):
		for decoration in holder.find_children("*", "Node3D", true, false):
			if decoration.get_parent() == holder or decoration.get_parent().get_parent() != holder:
				continue
			if decoration is PhysicsBody3D or not decoration.visible:
				continue
			if Vector2(decoration.global_position.x, decoration.global_position.z).distance_to(middle) < reach:
				decoration.visible = false


## Takes a Clear Zone away while the game is running (a floor piece was taken down): the grass
## and ferns grow back over it. Call this before freeing the zone.
func remove_clear_zone(zone: Node3D) -> void:
	_clear_zones.erase(zone)
	var foliage = get_node_or_null("Foliage")
	if foliage and zone.clear_plants:
		var reach: float = zone.radius
		var middle := Vector2(zone.global_position.x, zone.global_position.z)
		foliage.regrow_plants_in(Rect2(middle.x - reach, middle.y - reach, reach * 2.0, reach * 2.0))


# Seats a resource on the ground around it: tilts it with the slope as far as its lean says, then
# lowers it until no part of its footprint hangs over the ground, and presses it in a little.
func _settle_on_ground(item: Node3D) -> void:
	var settle: Dictionary = item.get_meta(SETTLE_META)
	var x := item.position.x
	var z := item.position.z
	var radius: float = settle["radius"]
	# The slope across the whole footprint, not just one grid point
	var east := get_surface_height(x + radius, z) - get_surface_height(x - radius, z)
	var south := get_surface_height(x, z + radius) - get_surface_height(x, z - radius)
	var ground_up := Vector3(-east, 2.0 * radius, -south).normalized()
	var up := Vector3.UP.slerp(ground_up, settle["lean"]).normalized()
	var turn: Basis = settle["turn"]
	item.basis = (Basis(Quaternion(Vector3.UP, up)) * turn).scaled(Vector3.ONE * settle["size"])
	# The tilted underside at an offset (dx, dz) sits (up.x * dx + up.z * dz) / up.y lower than
	# its middle. Raise or lower the middle until the underside touches the ground at its lowest
	# point: around two rings, and at every grid corner under the footprint, since the ground's
	# triangles can only bend there.
	var offsets: Array[Vector2] = [Vector2.ZERO]
	for ring: float in [0.5, 1.0]:
		for i in SETTLE_SAMPLES:
			var angle := TAU * i / SETTLE_SAMPLES
			offsets.append(Vector2(cos(angle), sin(angle)) * radius * ring)
	var first := Vector2i(floori((x - radius + _width * 0.5) / _cell_x), floori((z - radius + _depth * 0.5) / _cell_z))
	var last := Vector2i(ceili((x + radius + _width * 0.5) / _cell_x), ceili((z + radius + _depth * 0.5) / _cell_z))
	for gz in range(first.y, last.y + 1):
		for gx in range(first.x, last.x + 1):
			var corner := Vector2(-_width * 0.5 + gx * _cell_x - x, -_depth * 0.5 + gz * _cell_z - z)
			if corner.length() <= radius:
				offsets.append(corner)
	var seat := INF
	for offset in offsets:
		seat = minf(seat, get_surface_height(x + offset.x, z + offset.y) + (up.x * offset.x + up.z * offset.y) / up.y)
	item.position.y = seat - settle["press"]


# Buries iron and coal deposits in clusters under the hillsides. They're kept in their own
# record, not the shared one, so the grass doesn't leave a tell-tale bare patch over them.
func _bury_deposits() -> void:
	if not IronTier.ENABLED:
		return
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
			if (_crash_radius > 0.0 and spot.distance_to(_crash_center) < crash_site_gap) or is_on_trail(x, z, 1.5) or is_cleared(x, z, "resources"):
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


# Applies every TerrainModifier in the world to the heights, in scene order. With a patch
# given (grid columns and rows), only the ground inside it is changed.
func _apply_modifiers(patch := Rect2i()) -> void:
	# Trails listed one after another are shaped together, so where they meet or cross the
	# ground stays smooth instead of one trail's cut being stacked on top of another's
	var trails: Array = []
	# Sculpting goes on just before the first trail, so trails cut through sculpted ground
	var sculpted := false
	for modifier in get_tree().get_nodes_in_group("terrain_modifiers"):
		if not modifier.is_inside_tree():
			continue
		if modifier.has_method("trail_points"):
			if not sculpted:
				_apply_sculpt(patch)
				sculpted = true
			trails.append(modifier)
			continue
		_apply_trails(trails, patch)
		trails.clear()
		_apply_modifier(modifier, patch)
	if not sculpted:
		_apply_sculpt(patch)
	_apply_trails(trails, patch)


# Shapes a group of trails at once. Each one works from the same ground (as it was before
# any of them), and wherever two overlap, the lower result wins. Lower is also smoother here:
# trails only cut down along their length, so the deeper cut is the one meeting the gentler grade.
func _apply_trails(trails: Array, patch: Rect2i) -> void:
	if trails.is_empty():
		return
	var ground := _heights.duplicate()
	# Remember the ground each trail starts from, so its points can sit on it (without the
	# trail's own cut moving them)
	for trail in trails:
		_trail_ground[trail.get_instance_id()] = ground
	var shapes := _trail_shapes(trails, patch, ground, PackedFloat32Array())
	if shapes.is_empty():
		return
	_blend_trails(shapes, ground)
	# Where trails meet, run them all once more, each easing down (within its own Max Slope)
	# to the ground the others left along its line, so one trail doesn't drop sharply into
	# another's cut
	if shapes.size() > 1:
		var joined := _heights.duplicate()
		_heights = ground.duplicate()
		_blend_trails(_trail_shapes(trails, patch, ground, joined), ground)


func _trail_shapes(trails: Array, patch: Rect2i, ground: PackedFloat32Array, joined: PackedFloat32Array) -> Array:
	var shapes: Array = []
	for trail in trails:
		var shape := _trail_shape(trail, patch, ground, joined)
		if not shape.is_empty():
			shapes.append(shape)
	return shapes


func _blend_trails(shapes: Array, ground: PackedFloat32Array) -> void:
	var cover := Rect2i(shapes[0]["cells"])
	for shape in shapes:
		cover = cover.merge(shape["cells"])

	# Each spot near a trail heads toward a blend of the trails' surfaces. Each trail counts
	# by how strongly it covers the spot, and much less if another trail there is lower, so
	# where both are at full strength the lower one wins, and nothing jumps or forms a ridge.
	var softness := 0.4
	for gz in range(cover.position.y, cover.end.y):
		for gx in range(cover.position.x, cover.end.x):
			var surfaces := PackedFloat32Array()
			var weights := PackedFloat32Array()
			for shape in shapes:
				var cells: Rect2i = shape["cells"]
				if not cells.has_point(Vector2i(gx, gz)):
					continue
				var j := (gz - cells.position.y) * cells.size.x + (gx - cells.position.x)
				var w: float = shape["weight"][j]
				if w > 0.0:
					surfaces.append(shape["surface"][j])
					weights.append(w)
			if weights.is_empty():
				continue
			var strongest := 0.0
			var total := 0.0
			var blended := 0.0
			for p in weights.size():
				var counts := weights[p]
				for q in weights.size():
					if q != p and surfaces[p] > surfaces[q]:
						counts *= exp(-(surfaces[p] - surfaces[q]) * weights[q] / softness)
				total += counts
				blended += counts * surfaces[p]
				strongest = maxf(strongest, weights[p])
			var i := gz * _points_x + gx
			_heights[i] = lerpf(ground[i], blended / total, strongest)


# The grid points (columns, rows) covering a patch of map (x, z), clipped to the map
func _grid_patch(area: Rect2) -> Rect2i:
	var first_x := maxi(0, floori((area.position.x + _width * 0.5) / _cell_x))
	var last_x := mini(_points_x - 1, ceili((area.end.x + _width * 0.5) / _cell_x))
	var first_z := maxi(0, floori((area.position.y + _depth * 0.5) / _cell_z))
	var last_z := mini(_points_z - 1, ceili((area.end.y + _depth * 0.5) / _cell_z))
	# Entirely off the map: an empty patch, not a negative one
	if last_x < first_x or last_z < first_z:
		return Rect2i()
	return Rect2i(first_x, first_z, last_x - first_x + 1, last_z - first_z + 1)


func _apply_modifier(modifier, patch := Rect2i()) -> void:
	# Trails (TerrainPath) have their own way of shaping the ground
	if modifier.has_method("trail_points"):
		_apply_trails([modifier], patch)
		return
	var center := Vector2(modifier.global_position.x, modifier.global_position.z)
	var reach: float = modifier.radius
	var mode: int = modifier.mode
	var cells := _grid_patch(modifier.area())
	if patch.has_area():
		cells = cells.intersection(patch)
	if not cells.has_area():
		return
	var first_x := cells.position.x
	var last_x := cells.end.x - 1
	var first_z := cells.position.y
	var last_z := cells.end.y - 1

	# Flatten levels to the marker's own height, or to the average of the ground there
	var level: float = modifier.global_position.y
	if mode == TerrainModifierScript.Mode.FLATTEN and modifier.level_to_ground:
		var core := maxf(reach * (1.0 - modifier.falloff), reach * 0.3)
		var total := 0.0
		var samples := 0
		for k in 24:
			for r in [0.0, core * 0.5, core]:
				var p: Vector2 = center + Vector2.from_angle(TAU * k / 24.0) * r
				total += get_height(p.x, p.y)
				samples += 1
		level = total / samples
	# Raise/Lower moves the ground by how far the marker is above or below it at its middle,
	# keeping the ground's own bumps, so at full strength its middle reaches the marker
	var lift := 0.0
	if mode == TerrainModifierScript.Mode.RAISE_LOWER:
		lift = modifier.global_position.y - get_height(center.x, center.y)
	# Squash shrinks the ground's height above a base: either a level set by hand, or
	# (automatically) the ground on the outer ring, measured in every direction. Following
	# the ring like that means a hill on a slope squashes toward its own hillside, with no
	# trench around it, and the edge stays exactly where it was.
	var ring := PackedFloat32Array()
	if mode == TerrainModifierScript.Mode.SQUASH and modifier.auto_base:
		ring.resize(64)
		for k in 64:
			var p: Vector2 = center + Vector2.from_angle(TAU * k / 64.0) * reach
			ring[k] = get_height(p.x, p.y)
	# Smoothing averages each spot with its neighbors as they were before this modifier.
	# Bigger markers average over a wider area, so they soften bigger bumps.
	var before := _heights.duplicate() if mode == TerrainModifierScript.Mode.SMOOTH else PackedFloat32Array()
	var smooth_cells := clampi(int(reach / (_cell_x * 3.0)), 2, 10)

	for gz in range(first_z, last_z + 1):
		for gx in range(first_x, last_x + 1):
			var spot := Vector2(-_width * 0.5 + gx * _cell_x, -_depth * 0.5 + gz * _cell_z)
			var weight: float = modifier.weight_at(spot.distance_to(center))
			if weight <= 0.0:
				continue
			var i := gz * _points_x + gx
			match mode:
				TerrainModifierScript.Mode.RAISE_LOWER:
					_heights[i] += lift * weight
				TerrainModifierScript.Mode.FLATTEN:
					_heights[i] = lerpf(_heights[i], level, weight)
				TerrainModifierScript.Mode.SMOOTH:
					_heights[i] = lerpf(_heights[i], _neighbor_average(before, gx, gz, smooth_cells), weight)
				TerrainModifierScript.Mode.SQUASH:
					var base: float = modifier.base_height
					if not ring.is_empty():
						# The ring's height in this spot's direction, blended between samples
						var turn := fposmod((spot - center).angle() / TAU, 1.0) * 64.0
						var k := int(turn) % 64
						base = lerpf(ring[k], ring[(k + 1) % 64], turn - int(turn))
					# Scale the height above the base: a peak gets shorter but keeps its rounded shape
					if _heights[i] > base:
						_heights[i] = base + (_heights[i] - base) * (1.0 - modifier.amount * weight)


# Works out how a trail wants to shape the ground: a gentle height for every point along it
# (following the ground, evened out, and never steeper than the trail's Max Slope), and for
# each bit of ground nearby, the trail's surface there and how strongly the trail covers it
# (1 across the trail, fading to 0 at the edge). Also marks the trail's dirt and footprint.
# Returns {"cells", "surface", "weight"}, or nothing if the trail doesn't reach the patch.
func _trail_shape(path, patch: Rect2i, ground: PackedFloat32Array, joined: PackedFloat32Array) -> Dictionary:
	var points: PackedVector3Array = path.trail_points()
	if points.size() < 2:
		return {}
	var cells := _grid_patch(path.area())
	if patch.has_area():
		cells = cells.intersection(patch)
	if not cells.has_area():
		return {}
	var half: float = path.width * 0.5
	var reach: float = half + path.edge_blend
	# Kept clear of trees and the like: the width plus Clear Margin, and never less than the
	# worn dirt, so nothing ever stands on the trail's surface
	var clear_reach: float = half + path.clear_margin
	# The gravel surface covers the walkable width and fades out over Texture Blend Width
	var blend_width: float = path.texture_blend_width
	if path.dirt_texture:
		clear_reach = maxf(clear_reach, half + minf(blend_width, 2.0))
	var outer := maxf(reach, clear_reach)

	# 1. How high the ground is along the trail, and how far along each point is
	var count := points.size()
	var along := PackedFloat32Array()
	var profile := PackedFloat32Array()
	along.resize(count)
	profile.resize(count)
	for i in count:
		profile[i] = _height_in(ground, points[i].x, points[i].z)
		if i > 0:
			along[i] = along[i - 1] + Vector2(points[i].x, points[i].z).distance_to(Vector2(points[i - 1].x, points[i - 1].z))
	# The ground right on the center line, before the trail changes it
	var natural := profile.duplicate()
	# 2. Even out the ups and downs: average each point with its neighbors along the trail.
	# Smoothness 0 looks a couple of meters each way, 1 looks about 25 m each way.
	var spacing := maxf(along[count - 1] / (count - 1), 0.1)
	profile = _smooth_line(profile, maxi(1, int(lerpf(2.0, 25.0, path.smoothness) / spacing)))
	# Where other trails have already cut lower along this line, meet them there
	if not joined.is_empty():
		for i in count:
			profile[i] = minf(profile[i], _height_in(joined, points[i].x, points[i].z))
	# 3. Never steeper than Max Slope: where it would be, the trail cuts in or builds up
	_limit_grade(profile, along, tan(deg_to_rad(path.max_slope)))

	# 4. For every bit of ground near the trail, find the closest point on it...
	var size := cells.size
	var closest := PackedFloat32Array()
	var level := PackedFloat32Array()
	var center_ground := PackedFloat32Array()
	closest.resize(size.x * size.y)
	level.resize(size.x * size.y)
	center_ground.resize(size.x * size.y)
	closest.fill(INF)
	for s in count - 1:
		var a := Vector2(points[s].x, points[s].z)
		var b := Vector2(points[s + 1].x, points[s + 1].z)
		var length_squared := a.distance_squared_to(b)
		var nearby := _grid_patch(Rect2(a, Vector2.ZERO).expand(b).grow(outer)).intersection(cells)
		for gz in range(nearby.position.y, nearby.end.y):
			for gx in range(nearby.position.x, nearby.end.x):
				var spot := Vector2(-_width * 0.5 + gx * _cell_x, -_depth * 0.5 + gz * _cell_z)
				var t := 0.0 if length_squared < 0.0001 else clampf((spot - a).dot(b - a) / length_squared, 0.0, 1.0)
				var distance := spot.distance_to(a.lerp(b, t))
				var j := (gz - cells.position.y) * size.x + (gx - cells.position.x)
				if distance < closest[j]:
					closest[j] = distance
					level[j] = lerpf(profile[s], profile[s + 1], t)
					center_ground[j] = lerpf(natural[s], natural[s + 1], t)
	# ...and bring it to the trail's height: fully across the trail, fading over the edges.
	# Cross Slope decides how level it is side to side: at 1 it's flat across (cut into the
	# uphill side, built up on the downhill side); at 0 it keeps the hillside's own tilt.
	var keep_tilt: float = 1.0 - path.cross_slope
	# The trail's surface covers the walkable part and fades out over Texture Blend Width,
	# with an edge as ragged as its Edge Noise (worked out in the ground material)
	var dirt_reach: float = half + blend_width
	var noise := int(clampf(path.edge_noise, 0.0, 1.0) * 255.0)
	var surfaces := PackedFloat32Array()
	var weights := PackedFloat32Array()
	surfaces.resize(size.x * size.y)
	weights.resize(size.x * size.y)
	for gz in range(cells.position.y, cells.end.y):
		for gx in range(cells.position.x, cells.end.x):
			var j := (gz - cells.position.y) * size.x + (gx - cells.position.x)
			if closest[j] >= outer:
				continue
			var i := gz * _points_x + gx
			# The trail's footprint, kept clear of trees, rocks and plants
			if path.clear_objects and closest[j] < clear_reach:
				_trail_cover[i] = 1
			if closest[j] >= reach:
				continue
			weights[j] = 1.0 if closest[j] <= half else 1.0 - smoothstep(half, reach, closest[j])
			surfaces[j] = level[j] + (ground[i] - center_ground[j]) * keep_tilt
			if path.dirt_texture and closest[j] < dirt_reach:
				var worn := 1.0 - smoothstep(half - blend_width * 0.3, dirt_reach, closest[j])
				_trail_mask[i] = maxi(_trail_mask[i], int(worn * 255.0))
				_trail_noise[i] = maxi(_trail_noise[i], noise)
			# Grass tufts along the edges (and a few patches on the trail), if it wants them
			if path.edge_grass and closest[j] < dirt_reach + 1.0:
				_trail_grass[i] = 1
	return {"cells": cells, "surface": surfaces, "weight": weights}


# Averages each value with `reach` neighbors on each side (fewer near the ends)
func _smooth_line(values: PackedFloat32Array, reach: int) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(values.size())
	for i in values.size():
		var total := 0.0
		var n := 0
		for k in range(maxi(i - reach, 0), mini(i + reach, values.size() - 1) + 1):
			total += values[k]
			n += 1
		result[i] = total / n
	return result


# Keeps a line of heights from ever climbing or dropping faster than `grade` (rise per meter)
# by cutting down wherever it's too steep: each point ends up no higher than any other point
# on the trail plus the climb allowed between them. The trail never builds up above the
# ground, so its ends stay exactly where the ground is (like the edge of a flattened area).
# A pass each way means it works whichever end of the trail is higher.
func _limit_grade(heights: PackedFloat32Array, along: PackedFloat32Array, grade: float) -> void:
	for i in range(1, heights.size()):
		heights[i] = minf(heights[i], heights[i - 1] + grade * (along[i] - along[i - 1]))
	for i in range(heights.size() - 2, -1, -1):
		heights[i] = minf(heights[i], heights[i + 1] + grade * (along[i + 1] - along[i]))


# Redoes one patch of the map after a terrain modifier changed: resets the heights there to
# the original heightmap, re-applies every modifier, rebuilds just the chunks that patch
# touches, and moves everything standing in it up or down to the new ground.
# The patch needed to redo an area properly. Modifiers that read the ground at their middle
# are redone whole. So are trails, if asked for, since a trail's heights depend on its length.
func _with_whole_edits(area: Rect2, with_trails: bool) -> Rect2:
	# Each one joins once at most, so this always finishes: rounding can leave a merged area never
	# quite enclosing what it was merged with
	var joined := {}
	var grew := true
	while grew:
		grew = false
		for modifier in get_tree().get_nodes_in_group("terrain_modifiers"):
			if joined.has(modifier):
				continue
			var whole: bool = with_trails if modifier.has_method("trail_points") else modifier.reads_ground()
			if whole and modifier.area().intersects(area):
				joined[modifier] = true
				if not area.encloses(modifier.area()):
					area = area.merge(modifier.area())
					grew = true
	return area


## In the editor: the ground follows a modifier as it moves. This redoes only the patch it
## touches and redraws those chunks' meshes; the proper rebuild that request_rebuild_area
## schedules brings trails, collision and everything on the ground up to date when it stops.
func preview_area(area: Rect2) -> void:
	if not Engine.is_editor_hint() or not is_inside_tree() or not has_heights() or _in_stroke:
		return
	var now := Time.get_ticks_msec()
	if now - _last_preview_at < PREVIEW_EVERY:
		return
	_last_preview_at = now
	show_preview(area)


## Shows the ground as it'll be in a patch, without yet moving what stands on it
func show_preview(area: Rect2) -> void:
	if _preview_start.is_empty():
		_preview_start = _heights.duplicate()
	var grown := _with_whole_edits(area, false)
	var patch := _grid_patch(grown.grow(maxf(_cell_x, _cell_z) * 2.0))
	if not patch.has_area():
		return
	for gz in range(patch.position.y, patch.end.y):
		for gx in range(patch.position.x, patch.end.x):
			var i := gz * _points_x + gx
			_heights[i] = _base_heights[i]
			_trail_mask[i] = 0
			_trail_cover[i] = 0
			_trail_noise[i] = 0
			_trail_grass[i] = 0
	_apply_modifiers(patch)
	_redraw_chunks(grown)
	_refresh_marker_rings(grown)


## Back to the heights from before the preview, so the proper rebuild can see how far things
## need to move
func _end_preview() -> void:
	if not _preview_start.is_empty():
		_heights = _preview_start
		_preview_start = PackedFloat32Array()


## The ground as a new modifier would find it: with the modifiers before it, but no sculpting
## or trails, which go on after. A marker put at this height starts level with it.
func modifier_ground_at(x: float, z: float) -> float:
	return _height_in(_pre_sculpt, x, z) if _pre_sculpt.size() == _heights.size() else get_height(x, z)


func _rebuild_area(area: Rect2) -> void:
	if _base_heights.size() != _heights.size() or _heights.is_empty():
		generate()
		return
	area = _with_whole_edits(area, true)
	# A little extra margin, so the ground's lighting stays seamless at the patch's edges
	var patch := _grid_patch(area.grow(maxf(_cell_x, _cell_z) * 2.0))
	if not patch.has_area():
		return
	var before := _heights.duplicate()
	for gz in range(patch.position.y, patch.end.y):
		for gx in range(patch.position.x, patch.end.x):
			var i := gz * _points_x + gx
			_heights[i] = _base_heights[i]
			_trail_mask[i] = 0
			_trail_cover[i] = 0
			_trail_noise[i] = 0
			_trail_grass[i] = 0
	_apply_modifiers(patch)
	_update_ground_texture()

	# Rebuild every chunk the patch overlaps
	var first := chunk_at(area.position.x, area.position.y) - Vector2i.ONE
	var last := chunk_at(area.end.x, area.end.y) + Vector2i.ONE
	for cz in range(maxi(first.y, 0), mini(last.y, _chunks_z - 1) + 1):
		for cx in range(maxi(first.x, 0), mini(last.x, _chunks_x - 1) + 1):
			if not chunk_rect(Vector2i(cx, cz)).grow(1.0).intersects(area):
				continue
			var old := get_node_or_null("Chunk_%d_%d" % [cx, cz])
			if old:
				remove_child(old)
				old.queue_free()
			_build_chunk(cx, cz)

	# Trees, resources and buried deposits in the patch move with the ground under them
	var region := area.grow(1.0)
	for child in get_children():
		# Only things that stand on the ground (not the water, walls or chunks themselves)
		var thing := child as Node3D
		if thing == null or not thing.has_method("gather"):
			continue
		var spot := Vector2(thing.position.x, thing.position.z)
		if region.has_point(spot):
			# A trail now runs here: clear it away (a full rebuild will place things afresh)
			var margin := 2.0 if thing.get("resource_name") == "Wood" else 1.0
			if is_on_trail(spot.x, spot.y, margin) and not thing.is_in_group("hidden_deposits"):
				thing.queue_free()
				continue
			if thing.has_meta(SETTLE_META):
				_settle_on_ground(thing)
				continue
			thing.position.y += get_height(spot.x, spot.y) - _height_in(before, spot.x, spot.y)
	# ...and so do the boulders
	var foliage := get_node_or_null("Foliage")
	if foliage:
		for i in foliage.scattered_rock_count():
			var place: Transform3D = foliage.rock_transform(i)
			var spot := Vector2(place.origin.x, place.origin.z)
			if region.has_point(spot):
				# Boulders a trail now runs over shrink away to nothing
				if is_on_trail(spot.x, spot.y, 1.0):
					place = place.scaled_local(Vector3.ZERO)
				place.origin.y += get_height(spot.x, spot.y) - _height_in(before, spot.x, spot.y)
				foliage.set_rock_transform(i, place)

	_place_crash_site()
	_snap_hand_placed()
	# Trees a trail cleared away take their forest floor with them
	refresh_forest_floor()
	_update_flow_map()
	_refresh_marker_rings(area)


## The Clear Zones keeping grass and ferns out that reach into this area (x, z), as plain circles
## (x, z, radius): a snapshot the grass can be worked out from away from the main thread
func plant_clear_circles(area: Rect2) -> PackedVector3Array:
	var circles := PackedVector3Array()
	for zone in _clear_zones:
		if not is_instance_valid(zone) or not zone.is_inside_tree() or not zone.clear_plants:
			continue
		var r: float = zone.radius
		var p: Vector3 = zone.global_position
		if area.grow(r).has_point(Vector2(p.x, p.z)):
			circles.append(Vector3(p.x, p.z, r))
	return circles


## The big placed objects' cleared circles (see is_under_placed) reaching into this area: a snapshot
func placed_clears_in(area: Rect2) -> PackedVector3Array:
	var found := PackedVector3Array()
	for mark: Vector3 in _placed_clears:
		if area.grow(mark.z).has_point(Vector2(mark.x, mark.y)):
			found.append(mark)
	return found


## The taken spots (see is_spot_taken) in this area and `margin` around it: a snapshot, filed the
## same way, for _distance_to_nearest
func taken_spots_in(area: Rect2, margin: float) -> Dictionary:
	var found := {}
	var low := Vector2i(floori((area.position.x - margin) / SPOT_SQUARE), floori((area.position.y - margin) / SPOT_SQUARE))
	var high := Vector2i(floori((area.end.x + margin) / SPOT_SQUARE), floori((area.end.y + margin) / SPOT_SQUARE))
	for z in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var square := Vector2i(x, z)
			if _taken_spots.has(square):
				found[square] = (_taken_spots[square] as Array).duplicate()
	return found


## How near the nearest spot in a snapshot record is (see taken_spots_in), up to `reach`
func distance_in_record(spot: Vector2, record: Dictionary, reach: float) -> float:
	return _distance_to_nearest(spot, record, reach)


## True if a Clear Zone covering this spot keeps out `what`: "trees", "resources", "rocks" or "plants"
func is_cleared(x: float, z: float, what: String) -> bool:
	for zone in _clear_zones:
		if is_instance_valid(zone) and zone.is_inside_tree() and zone.get("clear_" + what) and zone.covers(x, z):
			return true
	return false


## True if a spot is on a trail, or within `margin` meters of one
func is_on_trail(x: float, z: float, margin := 0.0) -> bool:
	if _trail_cover.is_empty():
		return false
	var cells := ceili(margin / minf(_cell_x, _cell_z))
	var gx := roundi((x + _width * 0.5) / _cell_x)
	var gz := roundi((z + _depth * 0.5) / _cell_z)
	for dz in range(-cells, cells + 1):
		for dx in range(-cells, cells + 1):
			var cx := clampi(gx + dx, 0, _points_x - 1)
			var cz := clampi(gz + dz, 0, _points_z - 1)
			if _trail_cover[cz * _points_x + cx] > 0:
				return true
	return false


## How worn by trails the ground is at a spot: 0 = untouched grass, 1 = bare trail.
## Blended between the grid points around it, so it fades smoothly across a trail's edge.
func trail_amount(x: float, z: float) -> float:
	return _sample_layer(_trail_mask, x, z)


## How much painted dirt path (see PaintedPaths) there is at a spot: 0 = none, 1 = bare path
func painted_path_amount(x: float, z: float) -> float:
	return painted_paths.amount_at(x, z) if painted_paths else 0.0


## The painted paths reaching into this area (x, z), as a snapshot a worker thread can read
## with PaintedPaths.sample_snapshot
func painted_path_snapshot(area: Rect2) -> Dictionary:
	return painted_paths.snapshot(area) if painted_paths else {"origin": Vector2.ZERO, "tiles": {}}


## True if the trail here has Edge Grass on: grass grows in tufts along its edges, and in a
## few patches on the trail itself
func trail_edge_grass(x: float, z: float) -> bool:
	if _trail_grass.is_empty():
		return false
	var gx := clampi(roundi((x + _width * 0.5) / _cell_x), 0, _points_x - 1)
	var gz := clampi(roundi((z + _depth * 0.5) / _cell_z), 0, _points_z - 1)
	return _trail_grass[gz * _points_x + gx] > 0


# One of the byte-per-grid-point layers at a spot (0 to 1), blended between grid points
func _sample_layer(layer: PackedByteArray, x: float, z: float) -> float:
	if layer.size() != _points_x * _points_z or layer.is_empty():
		return 0.0
	var fx := clampf((x + _width * 0.5) / _cell_x, 0.0, _points_x - 1.001)
	var fz := clampf((z + _depth * 0.5) / _cell_z, 0.0, _points_z - 1.001)
	var gx := int(fx)
	var gz := int(fz)
	var tx := fx - gx
	var tz := fz - gz
	var i := gz * _points_x + gx
	var top := lerpf(layer[i], layer[i + 1], tx)
	var bottom := lerpf(layer[i + _points_x], layer[i + _points_x + 1], tx)
	return lerpf(top, bottom, tz) / 255.0


# Works out where water would drain across the ground, for the ground's paint: each spot passes
# everything it collects to its lowest neighbor, highest ground first, so the numbers build up
# along real gullies. A little noise on the heights lets them branch and wander. Done at half
# the grid's detail, which is plenty for this and much quicker.
func _update_flow_map() -> void:
	if not _ground is ShaderMaterial or _heights.is_empty():
		return
	var w := (_points_x + 1) / 2
	var h := (_points_z + 1) / 2
	var noise := FastNoiseLite.new()
	noise.seed = map_seed + 7
	noise.frequency = 0.03
	var levels := PackedFloat32Array()
	levels.resize(w * h)
	var lowest := INF
	var highest := -INF
	for z in h:
		for x in w:
			var level := _heights[(z * 2) * _points_x + x * 2] + noise.get_noise_2d(x * 4.0, z * 4.0) * 2.5
			levels[z * w + x] = level
			lowest = minf(lowest, level)
			highest = maxf(highest, level)
	# Highest first, without a full sort: into bins a quarter of a meter tall
	var bins := int((highest - lowest) / 0.25) + 1
	var counts := PackedInt32Array()
	counts.resize(bins + 1)
	for level in levels:
		counts[bins - 1 - int((level - lowest) / 0.25) + 1] += 1
	for b in bins:
		counts[b + 1] += counts[b]
	var order := PackedInt32Array()
	order.resize(w * h)
	for i in levels.size():
		var b := bins - 1 - int((levels[i] - lowest) / 0.25)
		order[counts[b]] = i
		counts[b] += 1
	var flow := PackedFloat32Array()
	flow.resize(w * h)
	flow.fill(1.0)
	var water := water_height()
	for i in order:
		if levels[i] < water:
			continue
		var x := i % w
		var z := i / w
		var low_level := levels[i]
		var low := -1
		for dz in range(maxi(z - 1, 0), mini(z + 2, h)):
			for dx in range(maxi(x - 1, 0), mini(x + 2, w)):
				var other := dz * w + dx
				if levels[other] < low_level:
					low_level = levels[other]
					low = other
		if low >= 0:
			flow[low] += flow[i]
	# Stored by how many doublings it's collected, since big rivers would swamp small gullies,
	# then blurred: a smooth hillside sheds many thin parallel trickles, which would show as
	# stripes, while a real gully collects enough to stay strong through the blur
	var amounts := PackedFloat32Array()
	amounts.resize(w * h)
	for i in flow.size():
		amounts[i] = log(flow[i]) / log(2.0) * 28.0
	amounts = _blur(amounts, w, h, 3)
	var bytes := PackedByteArray()
	bytes.resize(w * h)
	for i in amounts.size():
		bytes[i] = mini(int(amounts[i]), 255)
	var image := Image.create_from_data(w, h, false, Image.FORMAT_R8, bytes)
	var texture := _ground.get_shader_parameter("flow_map") as ImageTexture
	if texture and texture.get_width() == w and texture.get_height() == h:
		texture.update(image)
	else:
		_ground.set_shader_parameter("flow_map", ImageTexture.create_from_image(image))


# Hands the ground's maps to its material: trail wear, how ragged each trail's edge is,
# forest floor and the ground's height (for finding the foot of steep slopes and gullies,
# where scree gathers), one pixel per grid point each
func _update_ground_texture() -> void:
	if not _ground is ShaderMaterial or _trail_mask.size() != _points_x * _points_z:
		return
	var heights := Image.create_from_data(_points_x, _points_z, false, Image.FORMAT_RF, _heights.to_byte_array())
	for layer in [["ground_map", _trail_mask], ["edge_map", _trail_noise], ["forest_map", _forest_floor], ["height_map", heights]]:
		var image: Image = layer[1] if layer[1] is Image else Image.create_from_data(_points_x, _points_z, false, Image.FORMAT_R8, layer[1])
		var texture := _ground.get_shader_parameter(layer[0]) as ImageTexture
		if texture and texture.get_width() == _points_x and texture.get_height() == _points_z:
			texture.update(image)
		else:
			_ground.set_shader_parameter(layer[0], ImageTexture.create_from_image(image))
	_ground.set_shader_parameter("ground_map_info", Vector4(-_width * 0.5, -_depth * 0.5, _cell_x, _cell_z))


# Switches the ground's slope tint on or off. It uses the player's own climbing limit, and
# is always off once the game is running.
func _update_slope_view() -> void:
	if not _ground is ShaderMaterial:
		return
	var limit := 45.0
	var player: CharacterBody3D = null
	if is_inside_tree():
		player = get_node_or_null(player_path) as CharacterBody3D
	if player:
		limit = rad_to_deg(player.floor_max_angle)
	_ground.set_shader_parameter("walk_limit_degrees", limit)
	_ground.set_shader_parameter("slope_view", show_slope_view and Engine.is_editor_hint())


# ---- Forest floor ----

## Works out where the forest floor covers the ground, from every tree standing (scattered
## or placed by hand): a soft patch under each one, about as wide as its crown, adding up
## where trees stand together, so the woods are carpeted and a lone tree only has a little
func refresh_forest_floor() -> void:
	if _forest_floor.size() != _points_x * _points_z:
		return
	_forest_floor.fill(0)
	var trees: Array = []
	for child in get_children():
		if child.get("resource_name") == "Wood" and not child.is_queued_for_deletion():
			trees.append(child)
	for placed in get_tree().get_nodes_in_group("placed_objects"):
		if placed.get("resource_name") == "Wood":
			trees.append(placed)
	for tree: Node3D in trees:
		var tall: float = tree.get("tree_height") if tree.get("tree_height") != null else 8.0
		var reach := clampf(tall * tree.scale.x * 0.3, 2.5, 8.0)
		var at := Vector2(tree.global_position.x, tree.global_position.z)
		var cells := _grid_patch(Rect2(at, Vector2.ZERO).grow(reach))
		for gz in range(cells.position.y, cells.end.y):
			for gx in range(cells.position.x, cells.end.x):
				var spot := Vector2(-_width * 0.5 + gx * _cell_x, -_depth * 0.5 + gz * _cell_z)
				var d := spot.distance_to(at)
				if d < reach:
					var i := gz * _points_x + gx
					_forest_floor[i] = mini(_forest_floor[i] + int((1.0 - d / reach) * 140.0) + 15, 255)
	_update_ground_texture()


# ---- Texture sets: the ground's textured materials ----

## Where the ground's texture sets live. Every *_Color image in a folder under here (with its
## NormalGL, Roughness, Displacement and AmbientOcclusion beside it, sharing its name) is one
## set: it can be painted with the Texture Brush, and used by the automatic ground below.
const TEXTURE_FOLDER := "res://assets/textures"
## The most texture sets the ground material holds
const MAX_TEXTURE_SETS := 16
# How each kind of map in a set is named, and the format every set's maps are kept in (so
# they can share one texture array): VRAM compressed, 2048 pixels, with mipmaps
const SET_MAPS := ["Color", "NormalGL", "Roughness", "AmbientOcclusion", "Displacement"]
const SET_UNIFORMS := ["set_albedo", "set_normal", "set_roughness", "set_ao", "set_height"]
const SET_SIZE := 2048

# The sets found and the arrays made from them, kept between rebuilds (making them reads
# every texture, which takes a moment): {"key", "sets", "arrays", "has_ao"}
static var _set_cache := {}


## Every texture set in assets/textures: [{id ("folder/name"), name (for people), color (path
## to its Color image)}], sorted by id. A folder with one set is named after the folder;
## with several, each is named after the folder and the set.
func texture_sets() -> Array:
	var found := []
	for folder in DirAccess.get_directories_at(TEXTURE_FOLDER):
		var sets := []
		for file in DirAccess.get_files_at(TEXTURE_FOLDER.path_join(folder)):
			var ext := file.get_extension().to_lower()
			if ext in ["jpg", "jpeg", "png", "webp"] and file.get_basename().ends_with("_Color"):
				sets.append(file)
		sets.sort()
		for file: String in sets:
			var prefix := file.get_basename().trim_suffix("_Color")
			var short := prefix.trim_suffix("_2K-JPG").trim_suffix("_1K-JPG").trim_suffix("_4K-JPG").trim_suffix("_2K-PNG")
			var title := folder.capitalize() if sets.size() == 1 else "%s (%s)" % [folder.capitalize(), short]
			found.append({"id": folder + "/" + short, "name": title, "color": TEXTURE_FOLDER.path_join(folder).path_join(file), "prefix": TEXTURE_FOLDER.path_join(folder).path_join(prefix), "folder": folder})
	found.sort_custom(func(a, b): return a["id"] < b["id"])
	return found.slice(0, MAX_TEXTURE_SETS)


## The materials the Texture Brush can paint: grass and dirt (the plain ground colors), then
## every texture set. [{id, name, color (a Color, or a path to the set's Color image)}]
func paint_materials() -> Array:
	var materials := [
		{"id": "grass", "name": "Grass", "color": Color(0.22, 0.29, 0.1)},
		{"id": "dirt", "name": "Dirt", "color": Color(0.28, 0.24, 0.17)},
	]
	for set in texture_sets():
		materials.append({"id": set["id"], "name": set["name"], "color": set["color"]})
	return materials


# Gathers every texture set into texture arrays for the ground material, and tells it which
# set does which job. The arrays are made once and reused until the sets change.
func _apply_texture_sets() -> void:
	if not _ground is ShaderMaterial:
		return
	var sets := texture_sets()
	var key := ""
	for set in sets:
		key += set["id"] + ";"
	if _set_cache.get("key", "") != key:
		_set_cache = _build_set_arrays(sets, key)
	var usable: Array = _set_cache["sets"]
	for m in SET_UNIFORMS.size():
		_ground.set_shader_parameter(SET_UNIFORMS[m], _set_cache["arrays"][m])
	var scales := PackedFloat32Array()
	var tints := PackedVector4Array()
	var has_ao := PackedFloat32Array()
	scales.resize(MAX_TEXTURE_SETS)
	tints.resize(MAX_TEXTURE_SETS)
	has_ao.resize(MAX_TEXTURE_SETS)
	for i in usable.size():
		var look: Array = SET_LOOKS.get(usable[i]["id"], [])
		var rocky: bool = usable[i]["folder"].to_lower().contains("rock") or usable[i]["folder"].to_lower().contains("cliff") or usable[i]["folder"].to_lower().contains("scree")
		scales[i] = look[0] if not look.is_empty() else (4.0 if rocky else 3.0)
		var tint: Color = look[1] if not look.is_empty() else Color(0.85, 0.84, 0.8)
		# The tint's alpha marks rock, which wraps round steep ground from three sides
		tints[i] = Vector4(tint.r, tint.g, tint.b, 1.0 if rocky else 0.0)
		has_ao[i] = 1.0 if _set_cache["has_ao"][i] else 0.0
	_ground.set_shader_parameter("set_scale", scales)
	_ground.set_shader_parameter("set_tint", tints)
	_ground.set_shader_parameter("set_has_ao", has_ao)
	for job in [["forest_set", forest_floor_set], ["gravel_set", gravel_set], ["path_set", path_set], ["light_soil_set", light_soil_set], ["dark_soil_set", dark_soil_set], ["rock_set", rock_set],
			["mossy_rock_set", mossy_rock_set], ["cliff_rock_set", cliff_rock_set], ["scree_set", scree_set]]:
		_ground.set_shader_parameter(job[0], _set_index(job[1]))


# The layer a set is in (by id), or -1 if there's no such set
func _set_index(id: String) -> int:
	var usable: Array = _set_cache.get("sets", [])
	for i in usable.size():
		if usable[i]["id"] == id:
			return i
	return -1


func _build_set_arrays(sets: Array, key: String) -> Dictionary:
	var usable := []
	var has_ao := []
	var layers := []
	for m in SET_MAPS.size():
		layers.append([])
	for set in sets:
		var images := []
		var ok := true
		for m in SET_MAPS.size():
			var image := _set_image(set["prefix"], SET_MAPS[m], m == 1)
			# A set without an AO map borrows a plain white one (and the material knows to
			# ignore it); every other map has to be there
			if image == null and m == 3:
				image = null
			elif image == null:
				push_warning("Valley: texture set %s has no %s map, so it's left out" % [set["id"], SET_MAPS[m]])
				ok = false
				break
			images.append(image)
		if not ok:
			continue
		usable.append(set)
		has_ao.append(images[3] != null)
		for m in SET_MAPS.size():
			layers[m].append(images[m])
	# Sets without an AO map share the first one there is (it's ignored for them)
	var spare_ao: Image = null
	for image in layers[3]:
		if image:
			spare_ao = image
			break
	if spare_ao == null and not layers[2].is_empty():
		spare_ao = layers[2][0]
	for i in layers[3].size():
		if layers[3][i] == null:
			layers[3][i] = spare_ao
	var arrays := []
	for m in SET_MAPS.size():
		var array := Texture2DArray.new()
		if not layers[m].is_empty():
			var err := array.create_from_images(layers[m])
			if err != OK:
				push_error("Valley: couldn't put the texture sets' %s maps together (%s)" % [SET_MAPS[m], error_string(err)])
		arrays.append(array)
	return {"key": key, "sets": usable, "arrays": arrays, "has_ao": has_ao}


# One map of a texture set, in the shared format (VRAM compressed, SET_SIZE pixels, with
# mipmaps), or null if it isn't there or can't be made to match
func _set_image(prefix: String, kind: String, normal: bool) -> Image:
	var path := ""
	for ext in ["jpg", "jpeg", "png", "webp"]:
		if ResourceLoader.exists("%s_%s.%s" % [prefix, kind, ext]):
			path = "%s_%s.%s" % [prefix, kind, ext]
			break
	if path == "":
		return null
	var texture := load(path) as Texture2D
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null:
		return null
	var want := Image.FORMAT_RGTC_RG if normal else Image.FORMAT_DXT1
	if image.get_format() == want and image.get_width() == SET_SIZE and image.get_height() == SET_SIZE and image.has_mipmaps():
		return image
	# Imported some other way (a new set with Godot's default import settings): bring it to the
	# shared format here. Setting its import to VRAM Compressed, 2048 max (and Normal Map on for
	# NormalGL) makes this unnecessary and loading faster.
	image = image.duplicate()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	if image.get_size() != Vector2i(SET_SIZE, SET_SIZE):
		image.resize(SET_SIZE, SET_SIZE, Image.INTERPOLATE_CUBIC)
	image.generate_mipmaps()
	image.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_NORMAL if normal else Image.COMPRESS_SOURCE_GENERIC)
	if image.get_format() != want:
		push_warning("Valley: couldn't bring %s to the shared texture format; set its import to VRAM Compressed" % path)
		return null
	return image


# ---- The Sculpt Brush's shaping ----

# Loads what's been sculpted (if anything). A file made for a different size of map is ignored.
func _load_sculpt() -> void:
	_sculpt_deltas = PackedFloat32Array()
	if ground_sculpt_path == "" or not ResourceLoader.exists(ground_sculpt_path):
		return
	var saved: Resource = ResourceLoader.load(ground_sculpt_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if saved == null or saved.points_x != _points_x or saved.points_z != _points_z:
		push_warning("Valley: %s doesn't match this map's size, so it's left out" % ground_sculpt_path)
		return
	_sculpt_deltas = saved.deltas


# Adds the sculpting onto the ground, noting the ground as it was just before
func _apply_sculpt(patch: Rect2i) -> void:
	if _pre_sculpt.size() != _heights.size():
		_pre_sculpt = _heights.duplicate()
	var cells := patch if patch.has_area() else Rect2i(0, 0, _points_x, _points_z)
	var has_sculpt := _sculpt_deltas.size() == _heights.size()
	for gz in range(cells.position.y, cells.end.y):
		for gx in range(cells.position.x, cells.end.x):
			var i := gz * _points_x + gx
			_pre_sculpt[i] = _heights[i]
			if has_sculpt:
				_heights[i] += _sculpt_deltas[i]


## Starts a stroke: remembers how things are, for undo, and for putting everything standing
## on the ground right afterwards
func begin_sculpt() -> void:
	if _sculpt_deltas.size() != _heights.size():
		_stroke_deltas = PackedFloat32Array()
		_sculpt_deltas.resize(_heights.size())
		_sculpt_deltas.fill(0.0)
	else:
		_stroke_deltas = _sculpt_deltas.duplicate()
	_stroke_heights = _heights.duplicate()
	_stroke_area = Rect2()
	_in_stroke = true


## One dab of the Sculpt Brush. "Lift" moves the ground by `amount` meters; "Smooth", "Flatten"
## and "Erase" close that share of the gap (0-1) to their goal: the ground around it, the
## height `level`, and the ground without any sculpting. `falloff` is how much of the radius
## fades softly to nothing at the edge. Only the chunks it touches are redrawn.
func sculpt_dab(kind: String, center: Vector2, radius: float, amount: float, falloff: float, level = 0.0) -> void:
	var area := Rect2(center, Vector2.ZERO).grow(radius)
	var cells := _grid_patch(area)
	if not cells.has_area() or not _in_stroke:
		return
	var before := _heights.duplicate() if kind == "Smooth" else PackedFloat32Array()
	var reach := clampi(int(radius / (_cell_x * 3.0)), 1, 4)
	var soft_from := radius * (1.0 - clampf(falloff, 0.0, 1.0))
	for gz in range(cells.position.y, cells.end.y):
		for gx in range(cells.position.x, cells.end.x):
			var spot := Vector2(-_width * 0.5 + gx * _cell_x, -_depth * 0.5 + gz * _cell_z)
			var d := spot.distance_to(center)
			if d >= radius:
				continue
			var weight := 1.0 if d <= soft_from else 1.0 - smoothstep(soft_from, radius, d)
			var i := gz * _points_x + gx
			var change := 0.0
			match kind:
				"Lift":
					change = amount * weight
				"Smooth":
					change = (_neighbor_average(before, gx, gz, reach) - before[i]) * amount * weight
				"Flatten":
					change = (float(level) - (_pre_sculpt[i] + _sculpt_deltas[i])) * amount * weight
				"Erase":
					change = -_sculpt_deltas[i] * amount * weight
			_sculpt_deltas[i] += change
			_heights[i] += change
	_show_stroke(area)


## Makes a smooth slope from one spot to another (their heights included), `radius` meters to
## each side, fading at the edges by `falloff`
func sculpt_ramp(a: Vector3, b: Vector3, radius: float, falloff: float) -> void:
	var from := Vector2(a.x, a.z)
	var to := Vector2(b.x, b.z)
	var area := Rect2(from, Vector2.ZERO).expand(to).grow(radius)
	var cells := _grid_patch(area)
	if not cells.has_area() or not _in_stroke:
		return
	var length_squared := from.distance_squared_to(to)
	var soft_from := radius * (1.0 - clampf(falloff, 0.0, 1.0))
	for gz in range(cells.position.y, cells.end.y):
		for gx in range(cells.position.x, cells.end.x):
			var spot := Vector2(-_width * 0.5 + gx * _cell_x, -_depth * 0.5 + gz * _cell_z)
			var t := clampf((spot - from).dot(to - from) / length_squared, 0.0, 1.0)
			var d := spot.distance_to(from.lerp(to, t))
			if d >= radius:
				continue
			var weight := 1.0 if d <= soft_from else 1.0 - smoothstep(soft_from, radius, d)
			var i := gz * _points_x + gx
			# Mostly an even slope, easing a little into and out of its ends
			var height := lerpf(a.y, b.y, lerpf(t, smoothstep(0.0, 1.0, t), 0.5))
			var change := (height - (_pre_sculpt[i] + _sculpt_deltas[i])) * weight
			_sculpt_deltas[i] += change
			_heights[i] += change
	_show_stroke(area)


# Redraws the chunks a dab touched. Just their meshes: collision, trails and everything
# standing on the ground wait for the end of the stroke.
func _show_stroke(area: Rect2) -> void:
	_stroke_area = area if not _stroke_area.has_area() else _stroke_area.merge(area)
	_redraw_chunks(area)


func _redraw_chunks(area: Rect2) -> void:
	# (one cell further: a chunk's edge lighting depends on the ground just past it)
	var margin := area.grow(maxf(_cell_x, _cell_z))
	var first := chunk_at(margin.position.x, margin.position.y)
	var last := chunk_at(margin.end.x, margin.end.y)
	for cz in range(maxi(first.y, 0), mini(last.y, _chunks_z - 1) + 1):
		for cx in range(maxi(first.x, 0), mini(last.x, _chunks_x - 1) + 1):
			var chunk := get_node_or_null("Chunk_%d_%d" % [cx, cz])
			if chunk:
				(chunk.get_child(0) as MeshInstance3D).mesh = _chunk_mesh(cx, cz)


## Ends a stroke: saves the sculpting, then the ground and everything on it catch up. Returns
## what undo needs (empty if the stroke touched nothing).
func end_sculpt() -> Dictionary:
	if not _in_stroke:
		return {}
	_in_stroke = false
	if not _stroke_area.has_area():
		return {}
	var stroke := {"before": _stroke_deltas, "after": _sculpt_deltas.duplicate(), "area": _stroke_area}
	_save_sculpt()
	# Back to how the heights were, so the rebuild sees how far things need to move
	_heights = _stroke_heights
	_rebuild_area(_stroke_area)
	return stroke


## Calls off a stroke, putting everything back
func cancel_sculpt() -> void:
	if not _in_stroke:
		return
	_in_stroke = false
	_sculpt_deltas = _stroke_deltas
	if _stroke_area.has_area():
		_heights = _stroke_heights
		_rebuild_area(_stroke_area)


## Puts the sculpting back to a saved state (for undo and redo), and rebuilds that patch
func restore_sculpt(deltas: PackedFloat32Array, area: Rect2) -> void:
	_sculpt_deltas = deltas.duplicate()
	_save_sculpt()
	_rebuild_area(area)


func _save_sculpt() -> void:
	if ground_sculpt_path == "":
		return
	if _sculpt_deltas.is_empty():
		if FileAccess.file_exists(ground_sculpt_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(ground_sculpt_path))
		return
	var saved: Resource = TerrainSculptScript.new()
	saved.points_x = _points_x
	saved.points_z = _points_z
	saved.deltas = _sculpt_deltas
	var err := ResourceSaver.save(saved, ground_sculpt_path, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_error("Valley: couldn't save the ground sculpting to %s (%s)" % [ground_sculpt_path, error_string(err)])


# ---- The Texture Brush's painting ----

const TerrainPaintScript = preload("res://world/terrain_paint.gd")
## How many materials can be painted at once (each takes one channel of the paint maps)
const PAINT_CHANNELS := 12


# Loads what's been painted (if anything) and hands it to the ground material
func _load_paint() -> void:
	_paint = null
	if ground_paint_path != "" and ResourceLoader.exists(ground_paint_path):
		_paint = ResourceLoader.load(ground_paint_path, "", ResourceLoader.CACHE_MODE_REPLACE)
		_upgrade_paint()
	_paint_textures.clear()
	_upload_paint()


# Paint saved before the brush could paint any texture set kept grass, dirt, forest floor and
# gravel in one picture and rock in another: move them into the channels, unchanged
func _upgrade_paint() -> void:
	if _paint == null or not _paint.maps.is_empty() or _paint.image_a == null:
		return
	var b: Image = _paint.image_b
	var second := Image.create_empty(_paint.image_a.get_width(), _paint.image_a.get_height(), false, Image.FORMAT_RGBA8)
	if b:
		for y in b.get_height():
			for x in b.get_width():
				var rock := b.get_pixel(x, y).r
				if rock > 0.0:
					second.set_pixel(x, y, Color(rock, 0, 0, 0))
	var a: Image = _paint.image_a.duplicate()
	a.convert(Image.FORMAT_RGBA8)
	var maps: Array[Image] = [a, second, Image.create_empty(a.get_width(), a.get_height(), false, Image.FORMAT_RGBA8)]
	_paint.maps = maps
	_paint.layers = PackedStringArray(["grass", "dirt", "forest_floor/Ground037", "gravel_path/Ground108", "rock_cliff/Rock051"])
	_paint.image_a = null
	_paint.image_b = null


# Makes an empty painting covering the whole map, ready for the first stroke
func _new_paint() -> void:
	_paint = TerrainPaintScript.new()
	var size := Vector2i(ceili(_width / PAINT_TEXEL), ceili(_depth / PAINT_TEXEL))
	var maps: Array[Image] = []
	_paint.maps = maps
	for i in PAINT_CHANNELS / 4:
		_paint.maps.append(Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8))
	_paint.layers = PackedStringArray()
	_paint.origin = map_rect().position
	_paint.texel = PAINT_TEXEL


func _upload_paint() -> void:
	if not _ground is ShaderMaterial:
		return
	if _paint == null or _paint.maps.size() < PAINT_CHANNELS / 4:
		_ground.set_shader_parameter("paint_info", Vector4(0, 0, 1, 0))
		return
	for i in PAINT_CHANNELS / 4:
		var image: Image = _paint.maps[i]
		if i < _paint_textures.size() and _paint_textures[i].get_size() == Vector2(image.get_size()):
			_paint_textures[i].update(image)
		else:
			if i < _paint_textures.size():
				_paint_textures[i] = ImageTexture.create_from_image(image)
			else:
				_paint_textures.append(ImageTexture.create_from_image(image))
			_ground.set_shader_parameter("paint_%d" % i, _paint_textures[i])
	# Which material each channel holds
	var channels := PackedInt32Array()
	channels.resize(PAINT_CHANNELS)
	channels.fill(-3)
	for c in mini(_paint.layers.size(), PAINT_CHANNELS):
		match _paint.layers[c]:
			"grass":
				channels[c] = -1
			"dirt":
				channels[c] = -2
			var id:
				channels[c] = _set_index(id)
				if channels[c] < 0:
					channels[c] = -3
	_ground.set_shader_parameter("paint_channel", channels)
	_ground.set_shader_parameter("paint_info", Vector4(_paint.origin.x, _paint.origin.y, _paint.texel, 1.0))


## Paints one dab of a material (an id from paint_materials()) onto the ground, or with
## `erase` rubs the painting out back to the automatic coloring. `strength` is how much one
## dab lays on (0-1), and `falloff` how much of the radius fades softly to nothing at the
## edge (0 = hard edge, 1 = soft all the way from the middle). Returns false if the material
## couldn't be painted (all channels are in use by other materials).
func paint_ground(center: Vector2, radius: float, strength: float, falloff: float, material: String, erase := false) -> bool:
	if _paint == null:
		if erase:
			return true
		_new_paint()
	var channel := -1
	if not erase:
		channel = _paint.layers.find(material)
		if channel < 0:
			if _paint.layers.size() >= PAINT_CHANNELS:
				return false
			var layers: PackedStringArray = _paint.layers
			layers.append(material)
			_paint.layers = layers
			channel = layers.size() - 1
	var maps: Array = _paint.maps
	var texel: float = _paint.texel
	var origin: Vector2 = _paint.origin
	var size: Vector2i = maps[0].get_size()
	var first := Vector2i(((center - origin - Vector2.ONE * radius) / texel).floor()).clamp(Vector2i.ZERO, size - Vector2i.ONE)
	var last := Vector2i(((center - origin + Vector2.ONE * radius) / texel).ceil()).clamp(Vector2i.ZERO, size - Vector2i.ONE)
	var soft_from := radius * (1.0 - clampf(falloff, 0.0, 1.0))
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var spot := origin + (Vector2(x, y) + Vector2(0.5, 0.5)) * texel
			var d := spot.distance_to(center)
			if d > radius:
				continue
			var amount := strength * (1.0 if d <= soft_from else 1.0 - smoothstep(soft_from, radius, d))
			if amount <= 0.0:
				continue
			# Laying one material on thins all the others by the same amount, so together
			# they never add up to more than the whole ground
			for m in maps.size():
				var image: Image = maps[m]
				var c := image.get_pixel(x, y)
				for k in 4:
					if m * 4 + k == channel:
						c[k] += (1.0 - c[k]) * amount
					else:
						c[k] *= 1.0 - amount
				image.set_pixel(x, y, c)
	_upload_paint()
	return true


## Saves the painting to Ground Paint Path (the Texture Brush does this after each stroke)
func save_paint() -> void:
	if _paint and ground_paint_path != "":
		var err := ResourceSaver.save(_paint, ground_paint_path, ResourceSaver.FLAG_COMPRESS)
		if err != OK:
			push_error("Valley: couldn't save the ground paint to %s (%s)" % [ground_paint_path, error_string(err)])


## A copy of the painting as it is now (for undo), or an empty array if nothing's painted
func paint_snapshot() -> Array:
	if _paint == null:
		return []
	var maps := []
	for image: Image in _paint.maps:
		maps.append(image.duplicate())
	return [maps, _paint.layers.duplicate()]


## Puts back a painting from paint_snapshot() (for undo and redo), and saves it
func restore_paint(snapshot: Array) -> void:
	if snapshot.is_empty():
		_paint = null
		if ground_paint_path != "" and FileAccess.file_exists(ground_paint_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(ground_paint_path))
		_upload_paint()
		return
	if _paint == null:
		_new_paint()
	var maps: Array[Image] = []
	for image: Image in snapshot[0]:
		maps.append(image.duplicate())
	_paint.maps = maps
	_paint.layers = snapshot[1].duplicate()
	_paint_textures.clear()
	_upload_paint()
	save_paint()


# ---- Objects placed and rubbed out with the Object Painter ----

# Notes where objects have been placed by hand (so scattering leaves room around them) and
# where they've been rubbed out (so scattered ones don't come back there)
func _gather_painted_objects() -> void:
	_erased.clear()
	_placed_spots.clear()
	_placed_clears.clear()
	for holder in get_tree().get_nodes_in_group("object_erasers"):
		for mark: Vector3 in holder.get("erased"):
			_remember_erasure(mark)
	for placed in get_tree().get_nodes_in_group("placed_objects"):
		var thing := placed as Node3D
		if thing:
			var spot := Vector2(thing.global_position.x, thing.global_position.z)
			_remember_spot(spot, _placed_spots)
			_remember_spot(spot, _taken_spots)
			# Big objects keep the forest out from around them, so nothing grows through them
			var clear := float(thing.get_meta("placed_clear", 0.0))
			if clear > 0.0:
				_remember_erasure(Vector3(spot.x, spot.y, clear))
				_placed_clears.append(Vector3(spot.x, spot.y, clear))


func _remember_erasure(mark: Vector3) -> void:
	var first := Vector2i(floori((mark.x - mark.z) / ERASE_SQUARE), floori((mark.y - mark.z) / ERASE_SQUARE))
	var last := Vector2i(floori((mark.x + mark.z) / ERASE_SQUARE), floori((mark.y + mark.z) / ERASE_SQUARE))
	for sz in range(first.y, last.y + 1):
		for sx in range(first.x, last.x + 1):
			var square := Vector2i(sx, sz)
			if not _erased.has(square):
				_erased[square] = []
			_erased[square].append(mark)


## True if objects were rubbed out at this spot with the Object Painter's eraser: no tree,
## rock or resource is scattered there
func is_erased(x: float, z: float) -> bool:
	for mark: Vector3 in _erased.get(Vector2i(floori(x / ERASE_SQUARE), floori(z / ERASE_SQUARE)), []):
		if Vector2(x, z).distance_to(Vector2(mark.x, mark.y)) < mark.z:
			return true
	return false


## True if this spot is under a big placed object (a rock outcrop or a landmark), where even
## grass and ferns don't grow
func is_under_placed(x: float, z: float) -> bool:
	for mark: Vector3 in _placed_clears:
		if Vector2(x, z).distance_to(Vector2(mark.x, mark.y)) < mark.z:
			return true
	return false


## True if something was placed by hand within `radius` of this spot
func is_near_placed(x: float, z: float, radius: float) -> bool:
	return _distance_to_nearest(Vector2(x, z), _placed_spots, radius) < radius


## Where a ray (like one from the mouse in the 3D view) first meets the ground, or null if
## it never does (looking at the sky)
func ground_under_ray(from: Vector3, direction: Vector3):
	if not has_heights():
		return null
	var previous := from
	for i in 3000:
		var here := from + direction * 2.0 * i
		if here.y <= get_height(here.x, here.z):
			# Narrow it down between the last point above ground and this one
			var above := previous
			var below := here
			for k in 12:
				var middle := (above + below) * 0.5
				if middle.y > get_height(middle.x, middle.z):
					above = middle
				else:
					below = middle
			return Vector3(below.x, get_height(below.x, below.z), below.z)
		previous = here
	return null


## How high to stand a tree (scaled by `size`) so its roots go into the ground, the same way
## the scattered trees are set down: on the lowest ground around its trunk, sunk a little
func tree_ground_height(x: float, z: float, tree: Node, size: float) -> float:
	return _tree_ground(x, z, tree, size)


## Rubs out the scattered trees, rocks and resources within `radius` of a spot (the eraser
## also records the spot, so they stay gone after a rebuild). Hidden deposits are left alone.
func erase_scattered(center: Vector2, radius: float) -> int:
	_remember_erasure(Vector3(center.x, center.y, radius))
	var removed := 0
	for child in get_children():
		var thing := child as Node3D
		if thing == null or not thing.has_method("gather") or thing.is_in_group("hidden_deposits") or thing.is_queued_for_deletion():
			continue
		if Vector2(thing.position.x, thing.position.z).distance_to(center) < radius:
			thing.queue_free()
			removed += 1
	var foliage := get_node_or_null("Foliage")
	if foliage:
		for i in foliage.scattered_rock_count():
			var place: Transform3D = foliage.rock_transform(i)
			if place.basis.get_scale().x > 0.0 and Vector2(place.origin.x, place.origin.z).distance_to(center) < radius:
				foliage.set_rock_transform(i, place.scaled_local(Vector3.ZERO))
				removed += 1
	return removed


# Redraws the rings of any terrain modifier markers inside this patch of map, so they hug
# the new ground
func _refresh_marker_rings(area: Rect2) -> void:
	if not Engine.is_editor_hint():
		return
	for modifier in get_tree().get_nodes_in_group("terrain_modifiers"):
		if modifier.is_inside_tree() and modifier.area().intersects(area):
			modifier.refresh_rings()
	for zone in get_tree().get_nodes_in_group("clear_zones"):
		if zone.is_inside_tree():
			zone.refresh_rings()


# The average height of the grid points within `cells` of this one
func _neighbor_average(values: PackedFloat32Array, gx: int, gz: int, cells: int) -> float:
	var total := 0.0
	var count := 0
	for dz in range(-cells, cells + 1):
		for dx in range(-cells, cells + 1):
			var x := clampi(gx + dx, 0, _points_x - 1)
			var z := clampi(gz + dz, 0, _points_z - 1)
			total += values[z * _points_x + x]
			count += 1
	return total / count


# Sets the crash site down where it's been placed (only its height changes), and notes
# where it is. Once the game is running, also sets every piece of the wreck down on the
# ground. (In the editor only the whole site is moved, so the scene's own layout isn't
# overwritten.)
func _place_crash_site() -> void:
	_crash_radius = 0.0
	var site = get_node_or_null(crash_site_path)
	if site == null:
		return
	var spot := Vector2(site.global_position.x, site.global_position.z)
	_crash_center = spot
	_crash_radius = site.clear_radius
	_set_height(site, get_height(spot.x, spot.y))
	_scorch_center = site.scorch_point()
	if not Engine.is_editor_hint():
		site.settle(self)


# Snaps everything in the "snap_to_ground" group onto the ground, keeping where it is on
# the map. Give a node a "ground_offset" metadata value to set it that far above (or, if
# negative, below) the surface.
func _snap_hand_placed() -> void:
	for node in get_tree().get_nodes_in_group("snap_to_ground"):
		var thing := node as Node3D
		if thing == null or is_ancestor_of(thing):
			continue
		var spot := thing.global_position
		_set_height(thing, get_height(spot.x, spot.z) + float(thing.get_meta("ground_offset", 0.0)))


# Moves something up or down to `height`, but only if it's actually off. (Moving things
# in the editor makes their terrain modifiers ask for a rebuild, so this avoids a loop.)
func _set_height(thing: Node3D, height: float) -> void:
	if absf(thing.global_position.y - height) > 0.01:
		var spot := thing.global_position
		spot.y = height
		thing.global_position = spot


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
	material.shader = preload("res://world/water.gdshader")
	material.set_shader_parameter("ripples", ripples)
	return material
