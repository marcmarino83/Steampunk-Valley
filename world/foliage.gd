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

const PLANT_SHADER = preload("res://world/plant.gdshader")
## The render layer grass, ferns and scattered rocks are drawn on (layer 2). Cameras and the sun
## see every layer; a fireplace's light leaves this one out of its shadows (a patch of grass or a
## region of rocks is one big object, so a small light's shadow would draw all of it six times).
const FOLIAGE_LAYER := 1 << 1
## Size of the grid squares scattered rocks are filed under, so looking for one only checks nearby
const ROCK_CELL_SIZE := 16.0
## The rock mesh's rough radius, before each rock's own size
const ROCK_RADIUS := 0.55
## The most hits a big scattered rock takes, and how much it shrinks with each one
const ROCK_MOST_HITS := 6
const ROCK_HIT_SHRINK := 0.9

## The valley this grows on. Set before adding this to the scene.
var valley

var _grass_mesh: ArrayMesh
var _fern_mesh: ArrayMesh
var _plant_material: ShaderMaterial
# Which chunks have plants right now: chunk (x, z) -> the node holding them
var _patches := {}
var _patch_noise := FastNoiseLite.new()
# The scattered rocks: drawn in one MultiMesh per ROCK_REGION square of map (so Godot only draws,
# and casts shadows from, the squares in view, not all of them every time). Each rock keeps its
# index over the whole map (saves and mining use it): which square's MultiMesh it's in and where.
# Then, for mining, which ones are in each grid square, and hits left on any that have been started.
const ROCK_REGION := 128.0
var _rock_parts: Array[MultiMesh] = []
var _rock_part_of := PackedInt32Array()
var _rock_slot_of := PackedInt32Array()
var _rock_cells := {}
var _rock_hits := {}
# Rocks being mined or mined out: how each one stood before the first hit, to come back to
var _rock_whole := {}
# Rocks taken away because a building went up over them; these never come back
var _rock_buried := {}


func _ready() -> void:
	_grass_mesh = _make_grass_clump()
	_fern_mesh = _make_fern()
	_plant_material = ShaderMaterial.new()
	_plant_material.shader = PLANT_SHADER
	_patch_noise.frequency = 0.035


# Grass and ferns are worked out a patch (one terrain chunk) at a time on a worker thread, from a
# snapshot of what keeps them out there, and swapped in when ready, so growing a patch never holds
# up a frame: patches being worked out (chunk -> task id), what they came to (chunk -> the grass's
# and ferns' MultiMesh buffers; a mutex guards it), the buffers of the patches shown (to hide
# plants under a new floor at once), and patches to work out again (a floor came down there: the
# old patch stays until the new one is in)
const MAX_PATCH_TASKS := 2
var _pending := {}
var _done := {}
var _done_lock := Mutex.new()
var _patch_buffers := {}
var _stale := {}


func _exit_tree() -> void:
	# A patch still being worked out mustn't outlive this node
	for chunk in _pending:
		WorkerThreadPool.wait_for_task_completion(_pending[chunk])
	_pending.clear()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or valley == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var here := Vector2(camera.global_position.x, camera.global_position.z)
	var center: Vector2i = valley.chunk_at(here.x, here.y)
	_take_finished(here)

	# Start working out the nearest chunk that needs plants (or needs them again)
	if _pending.size() < MAX_PATCH_TASKS:
		var best := Vector2i.ZERO
		var best_distance := INF
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				var chunk := center + Vector2i(dx, dz)
				if (_patches.has(chunk) and not _stale.has(chunk)) or _pending.has(chunk) or not valley.has_chunk(chunk):
					continue
				var distance := _distance_to_chunk(chunk, here)
				if distance < grass_distance and distance < best_distance:
					best = chunk
					best_distance = distance
		if best_distance < INF:
			var timing := SpikeLog.begin()
			_start_patch(best)
			SpikeLog.end("grass and ferns: patch started (snapshot)", timing)

	# Clear away chunks you've left well behind
	for chunk in _patches.keys():
		if _distance_to_chunk(chunk, here) > grass_distance + 60.0:
			_patches[chunk].queue_free()
			_patches.erase(chunk)
			_patch_buffers.erase(chunk)
			_stale.erase(chunk)


## Works out the grass and ferns of every chunk that overlaps this area (x, z) again, keeping out
## of any Clear Zone added or taken away since; the old ones stay until the new ones are ready
func regrow_plants_in(area: Rect2) -> void:
	for chunk in _patches.keys() + _pending.keys():
		if valley.chunk_rect(chunk).intersects(area):
			_stale[chunk] = true


## Takes away the grass and ferns already growing within `reach` of a spot (x, z) at once (a floor
## went down there), without working the patch out again
func hide_plants_in(middle: Vector2, reach: float) -> void:
	var timing := SpikeLog.begin()
	for chunk in _patches.keys():
		if not valley.chunk_rect(chunk).grow(reach).has_point(middle):
			continue
		var patch: Node3D = _patches[chunk]
		var buffers: Dictionary = _patch_buffers.get(chunk, {})
		for i in 2:
			var key := "grass" if i == 0 else "fern"
			var buffer: PackedFloat32Array = buffers.get(key, PackedFloat32Array())
			var changed := false
			for j in range(0, buffer.size(), 16):
				var dx := buffer[j + 3] - middle.x
				var dz := buffer[j + 11] - middle.y
				if dx * dx + dz * dz < reach * reach and buffer[j + 5] != 0.0:
					for k in [0, 1, 2, 4, 5, 6, 8, 9, 10]:
						buffer[j + k] = 0.0
					changed = true
			if changed and patch.get_child_count() > i:
				buffers[key] = buffer
				((patch.get_child(i) as MultiMeshInstance3D).multimesh as MultiMesh).buffer = buffer
	# A patch being worked out from before the floor went down: work it out again
	for chunk in _pending.keys():
		if valley.chunk_rect(chunk).grow(reach).has_point(middle):
			_stale[chunk] = true
	SpikeLog.end("grass and ferns hidden under a new floor", timing)


## Takes away the grass and ferns already growing on painted path within this area (x, z) at once
## (a path is being painted there), without working the patches out again. A patch still being
## worked out is worked out again, with the path.
func hide_plants_on_paths(area: Rect2) -> void:
	var timing := SpikeLog.begin()
	for chunk in _patches.keys():
		if not valley.chunk_rect(chunk).intersects(area):
			continue
		var patch: Node3D = _patches[chunk]
		var buffers: Dictionary = _patch_buffers.get(chunk, {})
		for i in 2:
			var key := "grass" if i == 0 else "fern"
			var limit := PaintedPaths.PLANTS_GONE_AT if i == 0 else PaintedPaths.FERNS_GONE_AT
			var buffer: PackedFloat32Array = buffers.get(key, PackedFloat32Array())
			# (taken out while it changes, so writing to it doesn't copy it each time)
			buffers.erase(key)
			var changed := false
			var x0 := area.position.x
			var x1 := area.end.x
			var z0 := area.position.y
			var z1 := area.end.y
			for j in range(0, buffer.size(), 16):
				var x := buffer[j + 3]
				var z := buffer[j + 11]
				if x < x0 or x > x1 or z < z0 or z > z1 or buffer[j + 5] == 0.0:
					continue
				if valley.painted_path_amount(x, z) > limit:
					for k in [0, 1, 2, 4, 5, 6, 8, 9, 10]:
						buffer[j + k] = 0.0
					changed = true
			buffers[key] = buffer
			if changed and patch.get_child_count() > i:
				((patch.get_child(i) as MultiMeshInstance3D).multimesh as MultiMesh).buffer = buffer
	for chunk in _pending.keys():
		if valley.chunk_rect(chunk).intersects(area):
			_stale[chunk] = true
	SpikeLog.end("grass and ferns hidden on a painted path", timing)


func _distance_to_chunk(chunk: Vector2i, here: Vector2) -> float:
	var rect: Rect2 = valley.chunk_rect(chunk)
	var nearest := Vector2(clampf(here.x, rect.position.x, rect.end.x), clampf(here.y, rect.position.y, rect.end.y))
	return nearest.distance_to(here)


# Hands a chunk to a worker thread, with a snapshot of what keeps plants out there
func _start_patch(chunk: Vector2i) -> void:
	_stale.erase(chunk)
	var rect: Rect2 = valley.chunk_rect(chunk)
	var snapshot := {
		"chunk": chunk, "rect": rect, "dry_above": valley.water_height() + 0.15,
		"clear": valley.plant_clear_circles(rect), "placed": valley.placed_clears_in(rect),
		"taken": valley.taken_spots_in(rect, 1.5),
		"paths": valley.painted_path_snapshot(rect),
	}
	_pending[chunk] = WorkerThreadPool.add_task(_work_out_patch.bind(snapshot))


# Swaps in a patch whose working out has finished (one a frame), unless it was asked for again
# meanwhile, or you've walked well away from it
func _take_finished(here: Vector2) -> void:
	for chunk in _pending.keys():
		var task: int = _pending[chunk]
		if not WorkerThreadPool.is_task_completed(task):
			continue
		WorkerThreadPool.wait_for_task_completion(task)
		_pending.erase(chunk)
		_done_lock.lock()
		var result: Dictionary = _done.get(chunk, {})
		_done.erase(chunk)
		_done_lock.unlock()
		if result.is_empty() or (_stale.has(chunk) and _patches.has(chunk)) or _distance_to_chunk(chunk, here) > grass_distance + 60.0:
			continue
		var timing := SpikeLog.begin()
		var patch := Node3D.new()
		patch.add_child(_scatter_from(_grass_mesh, result["grass"], false))
		patch.add_child(_scatter_from(_fern_mesh, result["fern"], true))
		add_child(patch)
		if _patches.has(chunk):
			_patches[chunk].queue_free()
		_patches[chunk] = patch
		_patch_buffers[chunk] = result
		SpikeLog.end("grass and ferns: patch swapped in", timing)
		return


# A finished patch's plants as one MultiMesh, set in one go from its buffer (16 floats each: the
# transform's three rows, then the tint)
func _scatter_from(mesh: Mesh, buffer: PackedFloat32Array, shadows: bool) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = buffer.size() / 16
	if not buffer.is_empty():
		multimesh.buffer = buffer
	var scatter := MultiMeshInstance3D.new()
	scatter.multimesh = multimesh
	scatter.material_override = _plant_material
	scatter.layers = FOLIAGE_LAYER
	scatter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scatter.visibility_range_end = grass_distance
	scatter.visibility_range_end_margin = 10.0
	scatter.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return scatter


# One plant's transform and tint, onto a MultiMesh buffer
static func _push(buffer: PackedFloat32Array, t: Transform3D, tint: Color) -> void:
	buffer.append_array([t.basis.x.x, t.basis.y.x, t.basis.z.x, t.origin.x, t.basis.x.y, t.basis.y.y, t.basis.z.y, t.origin.y,
		t.basis.x.z, t.basis.y.z, t.basis.z.z, t.origin.z, tint.r, tint.g, tint.b, tint.a])


# True if a spot is inside one of these circles (x, z, radius)
static func _in_circles(x: float, z: float, circles: PackedVector3Array) -> bool:
	for c in circles:
		if (x - c.x) * (x - c.x) + (z - c.y) * (z - c.y) < c.z * c.z:
			return true
	return false


# On a worker thread: scatters grass and ferns over one chunk, from the snapshot (the ground's
# heights, slopes and trails are only read); the result goes into _done for _take_finished
func _work_out_patch(snapshot: Dictionary) -> void:
	var chunk: Vector2i = snapshot["chunk"]
	var rect: Rect2 = snapshot["rect"]
	var clear: PackedVector3Array = snapshot["clear"]
	var placed: PackedVector3Array = snapshot["placed"]
	var taken: Dictionary = snapshot["taken"]
	# Painted dirt paths: no grass or ferns on them
	var paths: Dictionary = snapshot["paths"]
	var any_paths := not (paths["tiles"] as Dictionary).is_empty() or (paths.has("path_tiles") and not (paths["path_tiles"]["tiles"] as Dictionary).is_empty())
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chunk)
	var dry_above: float = snapshot["dry_above"]

	var grass := PackedFloat32Array()
	for i in int(rect.get_area() * grass_density):
		var x := rect.position.x + rng.randf() * rect.size.x
		var z := rect.position.y + rng.randf() * rect.size.y
		var h: float = valley.get_height(x, z)
		# Not underwater, not on ground steep enough to be bare rock, and not under the wreck
		if h < dry_above or valley.get_normal(x, z).y < 0.72 or valley.is_near_crash_site(x, z, 0.5):
			continue
		# Leave a little clear ground around trees and resources, so things you can gather stand out
		if valley.distance_in_record(Vector2(x, z), taken, 1.2) < 1.2 or _in_circles(x, z, clear) or _in_circles(x, z, placed):
			continue
		if any_paths and PaintedPaths.sample_snapshot(paths, x, z) > PaintedPaths.PLANTS_GONE_AT:
			continue
		var patchiness: float = _patch_noise.get_noise_2d(x, z)
		# Off trails, except where a trail has Edge Grass: tufts along its frayed edges, and
		# here and there a patch on the trail itself
		var worn: float = valley.trail_amount(x, z)
		var tuft := false
		if worn > 0.35:
			if not valley.trail_edge_grass(x, z):
				continue
			if worn < 0.75:
				tuft = rng.randf() < 0.7
			else:
				tuft = patchiness > 0.35 and rng.randf() < 0.25
			if not tuft:
				continue
		# Thick in some places, thin in others
		elif rng.randf() > smoothstep(-0.8, 0.1, patchiness):
			continue
		var size := rng.randf_range(0.8, 1.4) if tuft else rng.randf_range(0.6, 1.3)
		var spot := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size), Vector3(x, h - 0.05, z))
		var shade := rng.randf_range(0.8, 1.15)
		_push(grass, spot, Color(shade * rng.randf_range(0.95, 1.1), shade, shade * 0.85))
		# Edge tufts grow thick: a second clump right beside the first
		if tuft and worn < 0.75:
			var near := Vector3(x + rng.randf_range(-0.3, 0.3), 0.0, z + rng.randf_range(-0.3, 0.3))
			near.y = valley.get_height(near.x, near.z) - 0.05
			_push(grass, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size * 0.8), near), Color(shade, shade * 1.05, shade * 0.8))

	var fern := PackedFloat32Array()
	for i in int(rect.get_area() * fern_density):
		var x := rect.position.x + rng.randf() * rect.size.x
		var z := rect.position.y + rng.randf() * rect.size.y
		var h: float = valley.get_height(x, z)
		if h < dry_above or valley.get_normal(x, z).y < 0.7 or valley.is_near_crash_site(x, z, 0.5) or valley.distance_in_record(Vector2(x, z), taken, 1.2) < 1.2 or valley.trail_amount(x, z) > 0.2 or valley.is_on_trail(x, z, 0.0) or _in_circles(x, z, clear) or _in_circles(x, z, placed):
			continue
		if any_paths and PaintedPaths.sample_snapshot(paths, x, z) > PaintedPaths.FERNS_GONE_AT:
			continue
		var size := rng.randf_range(0.7, 1.4)
		var spot := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size), Vector3(x, h - 0.05, z))
		var shade := rng.randf_range(0.5, 0.75)
		_push(fern, spot, Color(shade * 0.8, shade * 1.1, shade * 0.6))

	_done_lock.lock()
	_done[chunk] = {"grass": grass, "fern": fern}
	_done_lock.unlock()


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
		if rng.randf() > 0.03 + smoothstep(0.1, 0.35, steepness) * 0.9 or valley.is_near_crash_site(x, z) or valley.is_on_trail(x, z, 1.0) or valley.is_cleared(x, z, "rocks") or valley.is_erased(x, z):
			continue
		# Lots of small rocks, a few big ones
		var size := pow(rng.randf(), 1.6) * 4.0 + 0.5
		var shape := Vector3(rng.randf_range(0.8, 1.5), rng.randf_range(0.45, 0.85), rng.randf_range(0.8, 1.5)) * size
		var turn := Basis.from_euler(Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3)))
		var h: float = valley.get_height(x, z)
		# Sink them partway into the ground so they look settled, not dropped
		spots.append(Transform3D(turn * Basis.from_scale(shape), Vector3(x, h - shape.y * 0.3, z)))
		tints.append(Color.WHITE)

	# One MultiMesh per square of map
	var rock_mesh := _make_rock()
	var regions := {}
	_rock_part_of.resize(spots.size())
	_rock_slot_of.resize(spots.size())
	for i in spots.size():
		var region := Vector2i(floori(spots[i].origin.x / ROCK_REGION), floori(spots[i].origin.z / ROCK_REGION))
		if not regions.has(region):
			regions[region] = []
		var members: Array = regions[region]
		_rock_slot_of[i] = members.size()
		members.append(i)
	var rocks := Node3D.new()
	rocks.name = "Rocks"
	add_child(rocks)
	_rock_parts.clear()
	for region in regions:
		var members: Array = regions[region]
		var part_spots: Array[Transform3D] = []
		var part_tints: Array[Color] = []
		for i in members:
			part_spots.append(spots[i])
			part_tints.append(tints[i])
			_rock_part_of[i] = _rock_parts.size()
		var part := _make_scatter(rock_mesh, part_spots, part_tints, material, true, 700.0)
		part.name = "Rocks_%d_%d" % [region.x, region.y]
		rocks.add_child(part)
		_rock_parts.append(part.multimesh)
	if not Engine.is_editor_hint():
		for i in spots.size():
			var cell := _rock_cell(spots[i].origin)
			if not _rock_cells.has(cell):
				_rock_cells[cell] = PackedInt32Array()
			_rock_cells[cell].append(i)


## How many scattered rocks there are over the whole map
func scattered_rock_count() -> int:
	return _rock_part_of.size()


## Where scattered rock `index` stands (a scale of zero: mined out or taken away)
func rock_transform(index: int) -> Transform3D:
	return _rock_parts[_rock_part_of[index]].get_instance_transform(_rock_slot_of[index])


## Moves, shrinks or hides (scale zero) scattered rock `index`
func set_rock_transform(index: int, place: Transform3D) -> void:
	_rock_parts[_rock_part_of[index]].set_instance_transform(_rock_slot_of[index], place)


## A scattered rock you're looking at, for a pickaxe. They have no collision (there are thousands
## and you can walk through them), so this checks the line of sight against each one nearby.
## Returns something E can use, or null.
func rock_on_line(from: Vector3, to: Vector3) -> RockTarget:
	if _rock_parts.is_empty():
		return null
	var center := _rock_cell(from)
	var best := -1
	var best_along := INF
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var cell := center + Vector2i(dx, dz)
			if not _rock_cells.has(cell):
				continue
			for i in _rock_cells[cell]:
				var along := _line_hits_rock(i, from, to)
				if along < best_along:
					best = i
					best_along = along
	if best < 0:
		return null
	return RockTarget.new(self, best)


## Chips at a scattered rock, which shrinks with each hit and then is gone
func mine_rock(index: int) -> void:
	var place := rock_transform(index)
	if not _rock_hits.has(index):
		_rock_hits[index] = mini(2 + int(place.basis.get_scale().x), ROCK_MOST_HITS)
		_rock_whole[index] = place
	_rock_hits[index] -= 1
	if _rock_hits[index] <= 0:
		_rock_hits.erase(index)
		set_rock_transform(index, place.scaled_local(Vector3.ZERO))
		# It comes back whole after the Valley's Boulder Respawn Days
		valley.scattered_rock_mined(index, to_global(place.origin))
	else:
		set_rock_transform(index, place.scaled_local(Vector3.ONE * ROCK_HIT_SHRINK))


## A mined-out rock back as it was, unless a building now stands over it. True if it came back.
func restore_rock(index: int) -> bool:
	if _rock_parts.is_empty() or not _rock_whole.has(index):
		return false
	var place: Transform3D = _rock_whole[index]
	if _rock_buried.has(index) or valley.is_under_building(place.origin.x, place.origin.z):
		return false
	_rock_whole.erase(index)
	set_rock_transform(index, place)
	return true


## A scattered rock, mined out (used when loading a save)
func set_rock_mined(index: int) -> void:
	if _rock_parts.is_empty() or index < 0 or index >= scattered_rock_count():
		return
	var place := rock_transform(index)
	if not _rock_whole.has(index):
		_rock_whole[index] = place
	_rock_hits.erase(index)
	set_rock_transform(index, place.scaled_local(Vector3.ZERO))


## Takes away the scattered rocks whose middle is within `reach` of a spot (x, z): a building has
## gone up over them. They don't come back.
func hide_rocks_in(middle: Vector2, reach: float) -> void:
	if _rock_parts.is_empty():
		return
	var center := _rock_cell(Vector3(middle.x, 0.0, middle.y))
	var cells := ceili(reach / ROCK_CELL_SIZE) + 1
	for dz in range(-cells, cells + 1):
		for dx in range(-cells, cells + 1):
			for i in _rock_cells.get(center + Vector2i(dx, dz), PackedInt32Array()):
				var place := rock_transform(i)
				if Vector2(place.origin.x, place.origin.z).distance_to(middle) < reach:
					_rock_buried[i] = true
					set_rock_transform(i, place.scaled_local(Vector3.ZERO))


## True if a scattered rock (still standing) pokes into this box, in world space. Building pieces
## can't go through them.
func rock_in_box(box: AABB) -> bool:
	if _rock_parts.is_empty():
		return false
	var low := _rock_cell(box.position)
	var high := _rock_cell(box.end)
	for cz in range(low.y - 1, high.y + 2):
		for cx in range(low.x - 1, high.x + 2):
			for i in _rock_cells.get(Vector2i(cx, cz), PackedInt32Array()):
				var place := rock_transform(i)
				var size := place.basis.get_scale()
				if is_zero_approx(size.x):
					continue
				var middle := to_global(place.origin)
				var nearest := middle.clamp(box.position, box.end)
				# Most of a rock's outline is a bit inside its rough radius
				if nearest.distance_to(middle) < ROCK_RADIUS * maxf(size.x, maxf(size.y, size.z)) * 0.8:
					return true
	return false


func _rock_cell(spot: Vector3) -> Vector2i:
	return Vector2i(floori(spot.x / ROCK_CELL_SIZE), floori(spot.z / ROCK_CELL_SIZE))


# How far along the line (0 to 1) it meets this rock, or INF if it doesn't. The rock is squashed
# and turned, so the line is moved into the rock's own space, where it's a simple ball.
func _line_hits_rock(index: int, from: Vector3, to: Vector3) -> float:
	var place := rock_transform(index)
	if is_zero_approx(place.basis.get_scale().x):
		return INF
	var inverse := place.affine_inverse()
	var start := inverse * from
	var direction := inverse * to - start
	var a := direction.dot(direction)
	var b := start.dot(direction)
	var c := start.dot(start) - ROCK_RADIUS * ROCK_RADIUS
	var under_root := b * b - a * c
	if under_root < 0.0:
		return INF
	var along := (-b - sqrt(under_root)) / a
	return along if along >= 0.0 and along <= 1.0 else INF


## A scattered rock, in the form E expects of anything you can use
class RockTarget extends RefCounted:
	var _foliage
	var _index: int

	func _init(foliage, index: int) -> void:
		_foliage = foliage
		_index = index

	func can_interact() -> bool:
		return true

	func get_prompt() -> String:
		return "Mine Rock"

	func interact(player) -> void:
		if not player.swing_tool():
			return
		_foliage.mine_rock(_index)
		player.gathered("Stone", MineableRock.STONE_PER_HIT)


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
	# On its own render layer, so small lights can leave it out of their shadows (see FOLIAGE_LAYER)
	scatter.layers = FOLIAGE_LAYER
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
