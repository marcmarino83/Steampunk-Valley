@tool
class_name Forest
extends RefCounted
## The valley's trees: planting the forest and the few special trees when the valley is built,
## the tree line, and a felled tree growing back (stump, sapling, full tree), saved with the
## valley's other changes. The valley owns one (see valley.gd, which keeps the Trees settings in
## its inspector and thin forwards for what other code calls). Chopping, the felling animation
## and the wood a tree gives are the tree's own (see tree.gd).
##
## Planting is placed the same way every time from the map seed, and in the same order as
## everything the valley scatters after it, so changing the order or the random draws here moves
## every tree, rock and pickup in the valley.

## How far through the regrowing time a felled tree's stump grows a sapling
const SAPLING_AT := 0.4

## The valley it plants in (its settings, ground queries and the spots taken)
var valley: Node


## True above the tree line, where no trees are scattered. It wanders 10 m up and down. Based on
## the ground without ridges, like everything scattered.
func is_above_tree_line(x: float, z: float) -> bool:
	var ground: float = valley._height_in(valley._unridged, x, z)
	return ground > valley.tree_line + valley._forest.get_noise_2d(x * 0.7, z * 0.7) * 10.0


# ---- Planting ----

## Scatters trees anywhere that's dry and not too steep
func scatter_trees() -> void:
	var forest_trees: Array[PackedScene] = valley.forest_trees
	var young_trees: Array[PackedScene] = valley.young_trees
	var tree_scene: PackedScene = valley.tree_scene
	var tree_count: int = valley.tree_count
	var width: float = valley._width
	var depth: float = valley._depth
	var using_pack := not forest_trees.is_empty() or not young_trees.is_empty()
	if not using_pack and not tree_scene:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = valley.map_seed
	var dry_above: float = valley.water_height() + 0.5
	var placed := 0
	var tries := 0
	while placed < tree_count and tries < tree_count * 20:
		tries += 1
		var x := rng.randf_range(-width * 0.5 + 5.0, width * 0.5 - 5.0)
		var z := rng.randf_range(-depth * 0.5 + 5.0, depth * 0.5 - 5.0)
		# Trees grow in woods and stands, with open clearings between
		if rng.randf() > smoothstep(-0.15, 0.35, valley._forest.get_noise_2d(x, z)) + 0.03:
			continue
		var h: float = valley.get_height(x, z)
		if h < dry_above or valley.get_slope(x, z) > valley.max_tree_slope \
				or valley.is_near_crash_site(x, z) or valley.is_on_trail(x, z, 2.0) \
				or valley.is_cleared(x, z, "trees") or valley.is_erased(x, z) \
				or valley.is_near_placed(x, z, 3.0):
			continue
		var tree: Node3D
		if using_pack:
			# Mostly full-grown trees, with some young ones among them
			var young: bool = not young_trees.is_empty() \
					and (forest_trees.is_empty() or rng.randf() < valley.young_tree_share)
			var pool: Array[PackedScene] = young_trees if young else forest_trees
			tree = pool[rng.randi() % pool.size()].instantiate()
			var variation: float = valley.tree_size_variation
			var size := rng.randf_range(1.0 - variation, 1.0 + variation)
			tree.scale = Vector3.ONE * size
			tree.position = Vector3(x, tree_ground(x, z, tree, size), z)
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
			valley.add_child(tree)
		valley._remember_spot(Vector2(x, z), valley._taken_spots)
		valley._remember_spot(Vector2(x, z), valley._tree_spots)
		placed += 1


## The few special trees, placed after the forest so its layout stays the same: tall Douglas
## firs on the hilltops, where they stand out, and willows right at the water's edge
func scatter_feature_trees() -> void:
	var width: float = valley._width
	var depth: float = valley._depth
	var rng := RandomNumberGenerator.new()
	rng.seed = valley.map_seed + 101
	var water: float = valley.water_height()
	var fir := _optional_scene(valley.landmark_fir_scene)
	var fir_count: int = valley.landmark_fir_count
	if fir and fir_count > 0:
		# Try spots all over, scored by how far they rise above the ground 40 m around them,
		# and a little by how high they are; then take the best, well apart from each other
		var spots := []
		for i in 3000:
			var x := rng.randf_range(-width * 0.5 + 20.0, width * 0.5 - 20.0)
			var z := rng.randf_range(-depth * 0.5 + 20.0, depth * 0.5 - 20.0)
			var h: float = valley.get_height(x, z)
			if h < water + 3.0 or not _feature_spot_ok(x, z, 25.0):
				continue
			var around := 0.0
			for k in 8:
				var p := Vector2(x, z) + Vector2.from_angle(TAU * k / 8.0) * 40.0
				around += valley.get_height(p.x, p.y)
			spots.append([h - around / 8.0 + (h - water) * 0.1, Vector2(x, z)])
		spots.sort_custom(func(a, b): return a[0] > b[0])
		var placed: Array[Vector2] = []
		for s in spots:
			if placed.size() >= fir_count:
				break
			var spot: Vector2 = s[1]
			if placed.any(func(other): return other.distance_to(spot) < 150.0) \
					or valley._distance_to_nearest(spot, valley._tree_spots, 3.0) < 3.0:
				continue
			_plant_tree(fir, spot, rng)
			placed.append(spot)
	var willow := _optional_scene(valley.willow_scene)
	var willow_count: int = valley.willow_count
	if willow and willow_count > 0:
		var placed: Array[Vector2] = []
		var tries := 0
		while placed.size() < willow_count and tries < 20000:
			tries += 1
			var spot := Vector2(rng.randf_range(-width * 0.5 + 10.0, width * 0.5 - 10.0),
					rng.randf_range(-depth * 0.5 + 10.0, depth * 0.5 - 10.0))
			# Dry ground only just above the water, with the water a few meters off
			var h: float = valley.get_height(spot.x, spot.y)
			if h < water + 0.3 or h > water + 1.8 or not _feature_spot_ok(spot.x, spot.y, 20.0) \
					or not valley._water_nearby(spot.x, spot.y, 5.0):
				continue
			if placed.any(func(other): return other.distance_to(spot) < 30.0) \
					or valley._distance_to_nearest(spot, valley._tree_spots, 2.5) < 2.5:
				continue
			_plant_tree(willow, spot, rng)
			placed.append(spot)


## How high to stand a tree from the pine pack: on the lowest ground around its trunk (so no
## roots hang in the air on the downhill side of a slope), then sunk a little further so the
## root flare goes into the earth. Big trees sink about 0.3-0.5 m; small trees and saplings
## only a few centimeters, so they don't disappear.
func tree_ground(x: float, z: float, tree: Node, size: float) -> float:
	var tall: float = tree.get("tree_height") if tree.get("tree_height") != null else 8.0
	var trunk: float = tree.get("trunk_radius") if tree.get("trunk_radius") != null else 0.3
	tall *= size
	trunk *= size
	# The root flare spreads out to a few times the trunk's radius
	var reach := maxf(trunk * 3.0, 0.15)
	var lowest: float = valley.get_height(x, z)
	for k in 8:
		var p := Vector2(x, z) + Vector2.from_angle(TAU * k / 8.0) * reach
		lowest = minf(lowest, valley.get_height(p.x, p.y))
	var sink := clampf(tall * 0.025, 0.03, 0.5)
	return lowest - sink


# The scene at this path, or null if there isn't one (like a paid model left out of the
# repository)
static func _optional_scene(path: String) -> PackedScene:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as PackedScene


# True if a special tree may grow here: gentle enough ground, clear of the wreck, the trails
# and any Clear Zone
func _feature_spot_ok(x: float, z: float, max_slope: float) -> bool:
	return valley.get_slope(x, z) <= max_slope and not is_above_tree_line(x, z) \
			and not valley.is_near_crash_site(x, z) and not valley.is_on_trail(x, z, 3.0) \
			and not valley.is_cleared(x, z, "trees") and not valley.is_erased(x, z) \
			and not valley.is_near_placed(x, z, 4.0)


# Stands one tree at this spot, sized and turned at random like the rest of the forest
func _plant_tree(scene: PackedScene, spot: Vector2, rng: RandomNumberGenerator) -> void:
	var tree: Node3D = scene.instantiate()
	var variation: float = valley.tree_size_variation
	var size := rng.randf_range(1.0 - variation, 1.0 + variation)
	tree.scale = Vector3.ONE * size
	tree.position = Vector3(spot.x, tree_ground(spot.x, spot.y, tree, size), spot.y)
	tree.rotation.y = rng.randf() * TAU
	valley.add_child(tree)
	valley._remember_spot(spot, valley._taken_spots)
	valley._remember_spot(spot, valley._tree_spots)


# ---- Growing back ----

## A tree has been felled: it's a stump, which grows a sapling partway through the valley's Tree
## Regrow Days, then a full tree (booked with the respawner, which waits for the player to be
## away). `changes` is the valley's saved changes (id -> state).
func felled(tree: Node3D, changes: Dictionary, respawner: Node) -> void:
	var id: String = valley.id_of(tree)
	changes[id] = tree.save_state()
	var days: float = valley.tree_regrow_days
	if days > 0.0 and respawner:
		respawner.schedule(days * SAPLING_AT, tree.global_position, "sapling", id)
		respawner.schedule(days, tree.global_position, "tree", id)


## A regrowth booking came due ("sapling" or "tree"): the tree grows to that stage, and the
## valley's saved changes follow
func grow(kind: String, tree: Node, id: String, changes: Dictionary) -> void:
	match kind:
		"sapling":
			tree.set_stage("sapling")
			changes[id] = "sapling"
		"tree":
			tree.set_stage("full")
			changes.erase(id)


## A felled tree's trunk section was cut or its stump cleared: the valley's saved changes follow
## (unless it's already growing back)
func changed(tree: Node3D, changes: Dictionary) -> void:
	var id: String = valley.id_of(tree)
	if str(changes.get(id, "")).begins_with("felled:"):
		changes[id] = tree.save_state()


## True for the states a tree is saved in: felled (what's left of it), an older save's "stump",
## or "sapling"
static func is_tree_state(state: String) -> bool:
	return state.begins_with("felled:") or state == "stump" or state == "sapling"


## Loading a save: a tree set to its saved state
static func restore(tree: Node, state: String) -> void:
	if state.begins_with("felled:"):
		tree.restore_state(state)
	else:
		tree.set_stage(state)
