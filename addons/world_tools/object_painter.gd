@tool
extends RefCounted
## The Object Painter: places trees, rocks and bushes on the ground in the 3D view.
##   click             place one object exactly there
##   drag              paint many, over Brush Radius, about Density per 100 square meters
##   Alt + click/drag  rub out placed objects, and the valley's own scattered trees, rocks
##                     and resources (they stay gone after a rebuild)
##   drag an object    move a placed one along the ground (hold Shift for fine moves)
##
## The palette is built from the scenes in assets/: anything under a folder named trees,
## rocks or bushes shows up in that category (trees must be .tscn scenes, so they have the
## choppable tree script; rocks and bushes can be plain models too).
## Each kind is set down by its own rules: trees stand upright with their roots sunk in;
## rocks tilt to the slope, sink 20-40% into the ground and vary in size and turn; small
## stones come in clusters; bushes lean a little with the slope.

const CATEGORIES := ["Trees", "Rocks", "Bushes"]
const MODEL_TYPES := ["glb", "gltf", "fbx", "obj", "blend"]
## How close (on the ground, in meters, beyond its own size) the mouse must be to grab a
## placed object
const GRAB_MARGIN := 0.6
## Holding Shift while moving an object moves it at this fraction of the mouse's speed
const PRECISION := 0.25

var undo_redo: EditorUndoRedoManager
## The scene being painted; empty means the one open in the editor (a test sets its own)
var scene_root: Node
## Called whenever the 3D view's overlay needs redrawing
var redraw: Callable

## The palette: category -> [{path, name, local_only}]
var palette := {}
## Which palette entries are picked to paint with (one is chosen at random for each object)
var selected: Array[String] = []
var category := "Trees"
var radius := 6.0
## Objects per 100 square meters, when painting by dragging
var density := 2.0

var _sizes := {}
var _rng := RandomNumberGenerator.new()
# The stroke in progress: "" (none), "paint", "erase" or "move"
var _stroke := ""
var _placed_in_stroke: Array[Node3D] = []
var _removed_in_stroke: Array = []
var _erased_before := PackedVector3Array()
var _last_dab := Vector3.INF
var _moved_far := false
var _press_at := Vector3.ZERO
# Moving: the object, where it started (transform), the mouse's last ground spot, and where
# the object is now
var _moving: Node3D
var _move_from := Transform3D()
var _last_hit = null
var _move_to := Vector3.ZERO
var _hover: Node3D
var _cursor = null
var _alt := false
## A message for the panel (like why nothing was placed)
var status := ""


# ---- The palette ----

## Finds every placeable scene under res://assets, sorted into Trees, Rocks and Bushes
func scan_palette() -> void:
	palette.clear()
	for c in CATEGORIES:
		palette[c] = []
	var ignored := _git_ignored_folders()
	_scan_folder("res://assets", "", ignored)
	for c in CATEGORIES:
		palette[c].sort_custom(func(a, b): return a["name"] < b["name"])
	# Drop picks that no longer exist
	var still: Array[String] = []
	for path in selected:
		if ResourceLoader.exists(path):
			still.append(path)
	selected = still


func _scan_folder(folder: String, found_category: String, ignored: Array) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for sub in dir.get_directories():
		if sub.begins_with("."):
			continue
		var c := found_category
		for name in CATEGORIES:
			if sub.to_lower() == name.to_lower():
				c = name
		_scan_folder(folder.path_join(sub), c, ignored)
	if found_category == "":
		return
	for file in dir.get_files():
		var ext := file.get_extension().to_lower()
		# Trees have to be scenes with the tree script (so they can be chopped); rocks and
		# bushes can be plain models as well
		if ext != "tscn" and not (found_category != "Trees" and ext in MODEL_TYPES):
			continue
		var path := folder.path_join(file)
		var local_only := false
		for prefix in ignored:
			if path.begins_with(prefix):
				local_only = true
		palette[found_category].append({"path": path, "name": file.get_basename().replace("_", " ").capitalize(), "local_only": local_only})


# Folders the project's .gitignore keeps out of git (like paid model packs): objects from
# there are marked "local only", since a world that uses them won't open on another computer
func _git_ignored_folders() -> Array:
	var prefixes := []
	var file := FileAccess.open("res://.gitignore", FileAccess.READ)
	if file == null:
		return prefixes
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.begins_with("/") and line.ends_with("/"):
			prefixes.append("res:/" + line)
	return prefixes


# ---- Input from the 3D view ----

## Handles a mouse or key event in the 3D view. Returns true if it used it.
func handle_input(camera: Camera3D, event: InputEvent, valley) -> bool:
	if valley == null or not valley.has_heights():
		return false
	if event is InputEventMouse:
		_alt = event.alt_pressed
		_cursor = valley.ground_under_ray(camera.project_ray_origin(event.position), camera.project_ray_normal(event.position))
	if event is InputEventMouseMotion:
		if _stroke == "move":
			_move_with_mouse(valley, event.shift_pressed)
		elif _stroke != "":
			if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
				finish_stroke(valley)
			elif _cursor != null:
				_continue_stroke(valley)
		else:
			_hover = _object_near(_cursor) if _cursor != null else null
		redraw.call()
		return _stroke != ""
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _cursor == null:
				return true
			_start_stroke(valley, event.alt_pressed)
		else:
			finish_stroke(valley)
		redraw.call()
		return true
	if _stroke != "" and ((event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT) or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE)):
		cancel_stroke(valley)
		redraw.call()
		return true
	return false


func _start_stroke(valley, erase: bool) -> void:
	status = ""
	_placed_in_stroke.clear()
	_removed_in_stroke.clear()
	_moved_far = false
	_press_at = _cursor
	_last_dab = _cursor
	if erase:
		_stroke = "erase"
		var holder := _objects_node(false)
		_erased_before = PackedVector3Array(holder.get("erased")).duplicate() if holder else PackedVector3Array()
		_erase_at(valley, _cursor)
		return
	# Pressing on a placed object picks it up to move it
	var grabbed := _object_near(_cursor)
	if grabbed:
		_stroke = "move"
		_moving = grabbed
		_move_from = grabbed.global_transform
		_last_hit = _cursor
		_move_to = Vector3(grabbed.global_position.x, 0, grabbed.global_position.z)
		if scene_root == null:
			var selection := EditorInterface.get_selection()
			selection.clear()
			selection.add_node(grabbed)
		return
	_stroke = "paint"
	# A click places exactly one object, right where it was clicked
	_place_one(valley, Vector2(_cursor.x, _cursor.z), true)


func _continue_stroke(valley) -> void:
	var spot: Vector3 = _cursor
	var step := maxf(radius * 0.5, 0.5)
	if _stroke == "erase":
		if spot.distance_to(_last_dab) >= maxf(radius * 0.3, 0.3):
			_erase_at(valley, spot)
			_last_dab = spot
		return
	# A drag only starts painting once the mouse has really moved, so a click stays one object
	if not _moved_far and spot.distance_to(_press_at) < maxf(radius * 0.25, 0.5):
		return
	_moved_far = true
	if spot.distance_to(_last_dab) < step:
		return
	_last_dab = spot
	# Each dab covers the circle's worth of ground the brush has moved over since the last
	var attempts := maxi(1, roundi(density * (2.0 * radius * step) / 100.0))
	for i in attempts:
		var offset := Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * radius
		_place_one(valley, Vector2(spot.x, spot.z) + offset, false)


## Ends the stroke: records everything it did as one step for Ctrl+Z
func finish_stroke(valley) -> void:
	var root := _root()
	match _stroke:
		"paint":
			if not _placed_in_stroke.is_empty():
				# (no undo history when the painter is driven by a test, outside the editor)
				if undo_redo:
					undo_redo.create_action("Paint %d object%s" % [_placed_in_stroke.size(), "" if _placed_in_stroke.size() == 1 else "s"])
					for node in _placed_in_stroke:
						var parent := node.get_parent()
						undo_redo.add_do_method(parent, "add_child", node, true)
						undo_redo.add_do_method(node, "set_owner", root)
						undo_redo.add_do_reference(node)
						undo_redo.add_undo_method(parent, "remove_child", node)
					undo_redo.add_do_method(valley, "refresh_forest_floor")
					undo_redo.add_undo_method(valley, "refresh_forest_floor")
					undo_redo.commit_action(false)
				valley.refresh_forest_floor()
		"erase":
			var holder := _objects_node(false)
			if holder and (PackedVector3Array(holder.get("erased")).size() != _erased_before.size() or not _removed_in_stroke.is_empty()):
				# (no undo history when the painter is driven by a test, outside the editor)
				if undo_redo:
					undo_redo.create_action("Erase objects")
					for entry in _removed_in_stroke:
						var node: Node3D = entry[0]
						var parent: Node = entry[1]
						undo_redo.add_do_method(parent, "remove_child", node)
						undo_redo.add_undo_method(parent, "add_child", node, true)
						undo_redo.add_undo_method(parent, "move_child", node, entry[2])
						undo_redo.add_undo_method(node, "set_owner", root)
						undo_redo.add_undo_reference(node)
					undo_redo.add_do_property(holder, "erased", PackedVector3Array(holder.get("erased")).duplicate())
					undo_redo.add_undo_property(holder, "erased", _erased_before)
					undo_redo.add_do_method(valley, "refresh_forest_floor")
					# Scattered things that were rubbed out come back with a rebuild
					undo_redo.add_undo_method(valley, "request_rebuild")
					undo_redo.commit_action(false)
				else:
					for entry in _removed_in_stroke:
						entry[0].queue_free()
				valley.refresh_forest_floor()
		"move":
			if _moving and is_instance_valid(_moving):
				# (no undo history when the painter is driven by a test, outside the editor)
				if undo_redo:
					undo_redo.create_action("Move %s" % _moving.name)
					undo_redo.add_do_property(_moving, "global_transform", _moving.global_transform)
					undo_redo.add_undo_property(_moving, "global_transform", _move_from)
					undo_redo.add_do_method(valley, "refresh_forest_floor")
					undo_redo.add_undo_method(valley, "refresh_forest_floor")
					undo_redo.commit_action(false)
				valley.refresh_forest_floor()
	_stroke = ""
	_moving = null
	_placed_in_stroke.clear()
	_removed_in_stroke.clear()


## Right-click or Esc mid-stroke: put everything back as it was
func cancel_stroke(valley) -> void:
	match _stroke:
		"paint":
			for node in _placed_in_stroke:
				node.get_parent().remove_child(node)
				node.queue_free()
		"move":
			if _moving and is_instance_valid(_moving):
				_moving.global_transform = _move_from
		"erase":
			var root := _root()
			for entry in _removed_in_stroke:
				entry[1].add_child(entry[0], true)
				entry[1].move_child(entry[0], entry[2])
				entry[0].owner = root
			var holder := _objects_node(false)
			if holder:
				holder.set("erased", _erased_before)
			valley.request_rebuild()
	_stroke = ""
	_moving = null
	_placed_in_stroke.clear()
	_removed_in_stroke.clear()


# ---- Placing ----

# Sets down one object from the picked palette entries at a spot (x, z), following its
# category's rules. With `exact`, it goes right there even if something is close by.
func _place_one(valley, spot: Vector2, exact: bool) -> void:
	if selected.is_empty():
		status = "Pick something in the palette first."
		return
	var path: String = selected[_rng.randi() % selected.size()]
	var scene := load(path) as PackedScene
	if scene == null:
		status = "Couldn't load %s." % path
		return
	var size_info: Dictionary = _size_of(path)
	var kind := _category_of(path)
	var map: Rect2 = valley.map_rect().grow(-1.0)
	if not map.has_point(spot) or valley.get_height(spot.x, spot.y) < valley.water_height() + 0.1:
		return
	var footprint: float = size_info["radius"]
	if not exact and _too_close(spot, footprint):
		return
	var stones: bool = kind == "Rocks" and (path.get_file().to_lower().contains("stone") or path.get_file().to_lower().contains("pebble") or size_info["height"] < 0.5)
	if stones:
		# Small stones come in a cluster: a few more scattered close around the first
		var count := _rng.randi_range(3, 7)
		for i in count:
			var at := spot if i == 0 else spot + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.25, 1.2)
			_set_down(valley, scene, path, kind, at, _rng.randf_range(0.5, 1.2), size_info)
		return
	var size := 1.0
	match kind:
		"Trees":
			var variation: float = valley.tree_size_variation
			size = _rng.randf_range(1.0 - variation, 1.0 + variation)
		"Rocks":
			size = _rng.randf_range(0.6, 1.5)
		"Bushes":
			size = _rng.randf_range(0.8, 1.25)
	_set_down(valley, scene, path, kind, spot, size, size_info)


func _set_down(valley, scene: PackedScene, path: String, kind: String, spot: Vector2, size: float, size_info: Dictionary) -> void:
	var holder := _category_node(kind)
	if holder == null:
		return
	var node := scene.instantiate() as Node3D
	if node == null:
		return
	var yaw := _rng.randf() * TAU
	node.set_meta("placed_category", kind)
	node.set_meta("placed_size", size)
	node.set_meta("placed_yaw", yaw)
	node.set_meta("placed_footprint", size_info["radius"] * size)
	# How far into the ground it sinks: trees by their roots (worked out on the ground below),
	# rocks 20-40% of their height, bushes just a little
	var sink := 0.0
	match kind:
		"Rocks":
			sink = size_info["height"] * size * _rng.randf_range(0.2, 0.4)
		"Bushes":
			sink = size_info["height"] * size * 0.05
	node.set_meta("placed_sink", sink)
	holder.add_child(node, true)
	node.owner = _root()
	node.add_to_group("snap_to_ground", true)
	node.add_to_group("placed_objects", true)
	_settle(valley, node, Vector3(spot.x, 0, spot.y))
	if path in _local_paths():
		status = "%s is local only (its folder is kept out of git), so the world won't open fully on another computer." % path.get_file()
	_placed_in_stroke.append(node)


# Stands a placed object at a spot by its category's rules, and notes how far above or below
# the ground it is, so rebuilds keep it there
func _settle(valley, node: Node3D, spot: Vector3) -> void:
	var kind: String = node.get_meta("placed_category", "Bushes")
	var size: float = node.get_meta("placed_size", 1.0)
	var yaw: float = node.get_meta("placed_yaw", 0.0)
	var ground: float = valley.get_height(spot.x, spot.z)
	var turn := Basis(Vector3.UP, yaw)
	var height := ground
	match kind:
		"Trees":
			# Upright, roots sunk in like the scattered trees
			height = valley.tree_ground_height(spot.x, spot.z, node, size)
		"Rocks":
			# Settled flat against the slope
			turn = Basis(Quaternion(Vector3.UP, valley.get_normal(spot.x, spot.z))) * turn
			height = ground - float(node.get_meta("placed_sink", 0.0))
		_:
			turn = Basis(Quaternion(Vector3.UP, Vector3.UP.slerp(valley.get_normal(spot.x, spot.z), 0.3))) * turn
			height = ground - float(node.get_meta("placed_sink", 0.0))
	node.global_transform = Transform3D(turn.scaled(Vector3.ONE * size), Vector3(spot.x, height, spot.z))
	node.set_meta("ground_offset", height - ground)


func _too_close(spot: Vector2, footprint: float) -> bool:
	for node in _root().get_tree().get_nodes_in_group("placed_objects"):
		var other := node as Node3D
		if other and Vector2(other.global_position.x, other.global_position.z).distance_to(spot) < footprint + float(other.get_meta("placed_footprint", 0.5)):
			return true
	return false


# How big a palette object is: its height, and the radius of its footprint (meters, unscaled)
func _size_of(path: String) -> Dictionary:
	if _sizes.has(path):
		return _sizes[path]
	var info := {"height": 1.0, "radius": 0.5}
	var scene := load(path) as PackedScene
	if scene:
		var node := scene.instantiate()
		var box := AABB()
		var first := true
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			if not (mi as MeshInstance3D).mesh:
				continue
			# Only the nearest version of the model counts (not far-away billboards)
			if mi.visibility_range_begin > 0.0:
				continue
			var xf := Transform3D.IDENTITY
			var n: Node = mi
			while n and n != node:
				if n is Node3D:
					xf = n.transform * xf
				n = n.get_parent()
			var b: AABB = xf * mi.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		node.free()
		if not first:
			info["height"] = box.size.y
			# Trees take up the room of their trunk and a little more, not their whole crown
			info["radius"] = clampf(maxf(box.size.x, box.size.z) * (0.12 if _category_of(path) == "Trees" else 0.45), 0.15, 4.0)
	_sizes[path] = info
	return info


func _category_of(path: String) -> String:
	for c in palette:
		for entry in palette[c]:
			if entry["path"] == path:
				return c
	return category


func _local_paths() -> Array:
	var paths := []
	for c in palette:
		for entry in palette[c]:
			if entry["local_only"]:
				paths.append(entry["path"])
	return paths


# ---- Erasing ----

func _erase_at(valley, spot: Vector3) -> void:
	var center := Vector2(spot.x, spot.z)
	# Placed objects in the circle are taken away (Ctrl+Z puts them back)...
	for node in _root().get_tree().get_nodes_in_group("placed_objects"):
		var thing := node as Node3D
		if thing == null or not thing.is_inside_tree():
			continue
		if Vector2(thing.global_position.x, thing.global_position.z).distance_to(center) < radius:
			var parent := thing.get_parent()
			_removed_in_stroke.append([thing, parent, thing.get_index()])
			parent.remove_child(thing)
	# ...and so are the valley's own scattered ones, with the spot remembered so they don't
	# grow back on the next rebuild
	var holder := _objects_node(true)
	if holder == null:
		return
	var marks: PackedVector3Array = holder.get("erased")
	marks.append(Vector3(center.x, center.y, radius))
	holder.set("erased", marks)
	valley.erase_scattered(center, radius)


# ---- Moving ----

func _move_with_mouse(valley, precise: bool) -> void:
	if _moving == null or not is_instance_valid(_moving) or _cursor == null:
		return
	var hit: Vector3 = _cursor
	if precise and _last_hit != null:
		var moved: Vector3 = hit - _last_hit
		_move_to += Vector3(moved.x, 0, moved.z) * PRECISION
	else:
		_move_to = Vector3(hit.x, 0, hit.z)
	_last_hit = hit
	var bounds: Rect2 = valley.map_rect().grow(-1.0)
	_move_to.x = clampf(_move_to.x, bounds.position.x, bounds.end.x)
	_move_to.z = clampf(_move_to.z, bounds.position.y, bounds.end.y)
	if _moving.has_meta("placed_category"):
		_settle(valley, _moving, _move_to)
	else:
		var offset := float(_moving.get_meta("ground_offset", 0.0))
		_moving.global_position = Vector3(_move_to.x, valley.get_height(_move_to.x, _move_to.z) + offset, _move_to.z)


# The placed object whose footprint the spot is in (or close to), if any
func _object_near(spot) -> Node3D:
	if spot == null:
		return null
	var best: Node3D = null
	var best_distance := INF
	for node in _root().get_tree().get_nodes_in_group("placed_objects"):
		var thing := node as Node3D
		if thing == null or not thing.is_inside_tree():
			continue
		var d := Vector2(thing.global_position.x, thing.global_position.z).distance_to(Vector2(spot.x, spot.z))
		if d < float(thing.get_meta("placed_footprint", 0.5)) + GRAB_MARGIN and d < best_distance:
			best = thing
			best_distance = d
	return best


# ---- Where placed things go in the world scene ----

# TerrainEdits/Objects (with the eraser's record), made if it isn't there yet
func _objects_node(make: bool) -> Node3D:
	var root := _root()
	if root == null:
		return null
	var edits := root.get_node_or_null("TerrainEdits")
	if edits == null:
		if not make:
			return null
		edits = Node3D.new()
		edits.name = "TerrainEdits"
		root.add_child(edits, true)
		edits.owner = root
	var holder := edits.get_node_or_null("Objects") as Node3D
	if holder == null and make:
		holder = Node3D.new()
		holder.name = "Objects"
		holder.set_script(load("res://placed_objects.gd"))
		edits.add_child(holder, true)
		holder.owner = root
		if scene_root == null:
			EditorInterface.mark_scene_as_unsaved()
	return holder


# TerrainEdits/Objects/<kind>, made if it isn't there yet
func _category_node(kind: String) -> Node3D:
	var holder := _objects_node(true)
	if holder == null:
		return null
	var group := holder.get_node_or_null(kind) as Node3D
	if group == null:
		group = Node3D.new()
		group.name = kind
		holder.add_child(group, true)
		group.owner = _root()
	return group


# ---- Drawing in the 3D view ----

## Draws the brush circle on the ground, the object under the mouse, and the controls hint
func draw(overlay: Control, camera: Camera3D, valley) -> void:
	if valley == null:
		return
	if _hover and is_instance_valid(_hover) and _stroke == "":
		_ring(overlay, camera, valley, _hover.global_position, float(_hover.get_meta("placed_footprint", 0.5)) + 0.3, Color(1.0, 0.85, 0.35), 3.0)
	if _stroke == "move" and _moving and is_instance_valid(_moving):
		_ring(overlay, camera, valley, _moving.global_position, float(_moving.get_meta("placed_footprint", 0.5)) + 0.3, Color(1.0, 0.95, 0.6), 3.5)
	elif _cursor != null:
		var erasing := _alt or _stroke == "erase"
		_ring(overlay, camera, valley, _cursor, radius, Color(1.0, 0.35, 0.3) if erasing else Color(0.55, 0.95, 0.55), 2.0)
	_hint(overlay, [
		"Object Painter: %s" % category,
		"Click: place one   Drag: paint many",
		"Alt + click / drag: erase",
		"Drag a placed object: move it (Shift: fine)",
		"Right-click while dragging: cancel",
	])


static func _ring(overlay: Control, camera: Camera3D, valley, center: Vector3, r: float, color: Color, width: float) -> void:
	var line := PackedVector2Array()
	for k in 49:
		var p := Vector2(center.x, center.z) + Vector2.from_angle(TAU * k / 48.0) * r
		var world := Vector3(p.x, valley.get_height(p.x, p.y) + 0.1, p.y)
		if camera.is_position_behind(world):
			if line.size() >= 2:
				overlay.draw_polyline(line, color, width, true)
			line.clear()
			continue
		line.append(camera.unproject_position(world))
	if line.size() >= 2:
		overlay.draw_polyline(line, color, width, true)


static func _hint(overlay: Control, lines: Array) -> void:
	var font := overlay.get_theme_default_font()
	var box := Rect2(12, overlay.size.y - 18 * lines.size() - 22, 330, 18 * lines.size() + 12)
	overlay.draw_rect(box, Color(0, 0, 0, 0.55))
	for i in lines.size():
		var color := Color(1.0, 0.8, 0.4) if i == 0 else Color(0.92, 0.92, 0.92)
		overlay.draw_string(font, Vector2(box.position.x + 10, box.position.y + 20 + i * 18), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)


func _root() -> Node:
	return scene_root if scene_root else EditorInterface.get_edited_scene_root()
