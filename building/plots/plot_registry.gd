class_name PlotRegistry
extends Node
## Every plot in the world: makes and removes them, decides which plot owns each piece and piece
## of furniture, checks each plot's requirements, and saves them.
##
## Ownership: a building piece, furniture item, or workbench, chest or campfire placed with its
## middle inside a plot belongs to it; inside two overlapping plots, to the one whose middle is
## nearest you. A new or enlarged plot also takes in anything inside it that no plot owns yet.
## Pieces keep their plot's id (BuildPiece.owner_plot); the workbench, chest and campfire keep it
## as metadata (OWNER_META). Only a plot's own things count toward its requirements.
##
## Requirements are checked again (on the next physics frame, so new pieces' collision is ready)
## whenever something is placed, removed, moved or resized, and every few seconds anyway.

## Marks a workbench, chest or campfire with the plot that owns it
const OWNER_META := &"owner_plot"
## How often every plot is checked again even if nothing changed (doors, loads...)
const RECHECK_SECONDS := 2.0
## How far above a furniture item a roof can be
const ROOF_REACH := 14.0

## Where plots are added (the world), and the pieces they own
var world: Node
var pieces: PieceRegistry

# id -> Plot
var _plots := {}
var _next_id := 1
var _dirty := 0
var _recheck_in := 0.0
var _view := false
# A buildable's resource path -> its name, for the workbench, chest and campfire
var _names := {}


func _ready() -> void:
	add_to_group("saveable")
	add_to_group("plot_registry")


## A new plot. A loaded one keeps its id and name; a new one gets the next id and a name of its own.
func create(type: PlotType, where: Transform3D, plot_size: Vector2, plot_name := "", id := "") -> Plot:
	var plot := Plot.new()
	plot.setup(type, plot_size)
	if id.is_empty():
		id = "plot_%d" % _next_id
	_next_id = maxi(_next_id, int(id.trim_prefix("plot_")) + 1)
	plot.plot_id = id
	plot.name = id
	world.add_child(plot)
	plot.global_transform = where
	plot.rename(plot_name if not plot_name.is_empty() else _free_name(type.display_name))
	plot.set_view(_view)
	plot.rebuild()
	_plots[id] = plot
	mark_dirty()
	return plot


## Removes just the plot: everything it owned stays standing, owned by no plot
func remove_plot(plot: Plot) -> void:
	for item in owned_items(plot):
		set_plot_of(item, "")
	_plots.erase(plot.plot_id)
	plot.queue_free()
	mark_dirty()


func find(id: String) -> Plot:
	var plot = _plots.get(id)
	return plot if is_instance_valid(plot) else null


func all_plots() -> Array:
	return _plots.values().filter(func(p): return is_instance_valid(p))


## Which plot something placed at this spot belongs to: the plot it's inside, or of two or more
## overlapping ones the one whose middle is nearest `viewer`; empty if it's in none
func owner_for(spot: Vector3, viewer: Vector3) -> String:
	var best: Plot = null
	var best_distance := INF
	for plot in all_plots():
		if not plot.contains(spot):
			continue
		var distance: float = plot.global_position.distance_to(viewer)
		if distance < best_distance:
			best = plot
			best_distance = distance
	return best.plot_id if best else ""


## Every piece, furniture item, workbench, chest and campfire the plot owns
func owned_items(plot: Plot) -> Array:
	var found := pieces.pieces_owned_by(plot.plot_id)
	for building in _buildings():
		if building.get_meta(OWNER_META, "") == plot.plot_id:
			found.append(building)
	return found


## Every piece and building, owned or not
func all_items() -> Array:
	return pieces.all_pieces() + _buildings()


## The plot that owns something (empty for none)
func plot_of(item: Node) -> String:
	if item is BuildPiece:
		return item.owner_plot
	return str(item.get_meta(OWNER_META, ""))


func set_plot_of(item: Node, id: String) -> void:
	if item is BuildPiece:
		item.owner_plot = id
	elif id.is_empty():
		item.remove_meta(OWNER_META)
	else:
		item.set_meta(OWNER_META, id)
	mark_dirty()


## The middle of something, for deciding which plot it's in
func center_of(item: Node3D) -> Vector3:
	return item.center() if item is BuildPiece else item.global_position


## What something is called, for counting it toward requirements ("Bed", "Workbench")
func name_of(item: Node) -> String:
	if item is BuildPiece:
		return item.display_name()
	var path := str(item.get_meta(BuildPlacer.BUILDABLE_META, ""))
	if not _names.has(path):
		var buildable := load(path) as Buildable if not path.is_empty() else null
		_names[path] = buildable.display_name if buildable else ""
	return _names[path]


## Takes in everything inside the plot that no plot owns yet
func adopt(plot: Plot) -> void:
	for item in all_items():
		if plot_of(item).is_empty() and plot.contains(center_of(item)):
			set_plot_of(item, plot.plot_id)


## Asks for every plot's requirements to be checked again soon
func mark_dirty() -> void:
	_dirty = 2


## Plot view on or off: every plot's outline and label show, or nothing does
func set_view(shown: bool) -> void:
	if shown == _view:
		return
	_view = shown
	for plot in all_plots():
		plot.set_view(shown)


func is_view_on() -> bool:
	return _view


func _physics_process(delta: float) -> void:
	_recheck_in -= delta
	if _dirty > 0:
		# Wait a physics frame, so pieces placed or moved just now are where the rays can find them
		_dirty -= 1
		if _dirty == 0:
			_check_all()
	elif _recheck_in <= 0.0:
		_check_all()


func _check_all() -> void:
	_recheck_in = RECHECK_SECONDS
	for plot in all_plots():
		check(plot)


## Works out the plot's checklist, whether it's working, and how many settlers it holds
func check(plot: Plot) -> void:
	var type := plot.plot_type
	var items := owned_items(plot)
	var counts := {}
	for item in items:
		var item_name := name_of(item)
		counts[item_name] = int(counts.get(item_name, 0)) + 1
	var lines := []
	for need in type.furniture:
		var have := 0
		for item_name in need.get("items", []):
			have += int(counts.get(str(item_name), 0))
		var wanted := int(need.get("count", 1))
		lines.append({"text": "%s %d/%d" % [need.get("label", ""), have, wanted], "ok": have >= wanted, "short": str(need.get("label", "")).to_lower()})
	if type.needs_door:
		var doors := items.filter(func(item): return item is BuildPiece and item.is_door()).size()
		lines.append({"text": "Door %d/1" % mini(doors, 1), "ok": doors > 0, "short": "door"})
	if type.needs_roof:
		var required := type.required_items()
		var furniture := items.filter(func(item): return required.has(name_of(item)))
		var open := furniture.filter(func(item): return not _roofed(item, plot.plot_id))
		if furniture.is_empty():
			lines.append({"text": "Roofed (nothing to check yet)", "ok": false, "short": "roof"})
		elif open.is_empty():
			lines.append({"text": "Roofed", "ok": true})
		else:
			var what := name_of(open[0])
			if open.size() > 1:
				what += " and %d more" % (open.size() - 1)
			lines.append({"text": "Roofed (%s %s not under a roof)" % [what, "is" if open.size() == 1 else "are"], "ok": false, "short": "roof"})
	plot.checklist = lines
	plot.working = lines.all(func(line): return line["ok"])
	plot.capacity = int(counts.get(type.houses_per, 0)) if not type.houses_per.is_empty() else 0
	var short: PackedStringArray = []
	for line in lines:
		if not line["ok"]:
			short.append(line.get("short", ""))
	plot.missing = short
	plot.update_label()


# True if a roof (or a floor above) belonging to the plot is over this item, like standing under
# a roof counts as shelter: a ray straight up from just above its foot, passing through anything
# that isn't the plot's own roof or floor
func _roofed(item: Node3D, plot_id: String) -> bool:
	var space := item.get_world_3d().direct_space_state
	var from := item.global_position + Vector3.UP * 0.3
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * ROOF_REACH)
	var skip: Array[RID] = []
	if item is CollisionObject3D:
		skip.append(item.get_rid())
	for i in 10:
		query.exclude = skip
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return false
		var other: Object = hit["collider"]
		if other is BuildPiece and (other.is_roof() or other.is_floor()) and other.owner_plot == plot_id:
			return true
		skip.append(hit["rid"])
	return false


func _buildings() -> Array:
	return get_tree().get_nodes_in_group("buildings").filter(func(b): return is_instance_valid(b) and not b.is_queued_for_deletion())


# "House", or "House 2" if there's already a House
func _free_name(base: String) -> String:
	var taken := {}
	for plot in all_plots():
		taken[plot.plot_name] = true
	if not taken.has(base):
		return base
	var n := 2
	while taken.has("%s %d" % [base, n]):
		n += 1
	return "%s %d" % [base, n]


func save_key() -> String:
	return "plots"


# After the buildings and pieces, whose owners are saved with them
func save_priority() -> int:
	return 32


func save_data() -> Dictionary:
	return {"next_id": _next_id, "list": all_plots().map(func(p): return p.save_data())}


func load_data(data: Dictionary) -> void:
	for plot in all_plots():
		plot.queue_free()
	_plots.clear()
	_next_id = int(data.get("next_id", 1))
	for entry in data.get("list", []):
		var type := load(str(entry.get("type", ""))) as PlotType
		if type == null:
			continue
		var saved_size: Array = entry.get("size", [type.min_size.x, type.min_size.y])
		var where := Transform3D(Basis(Vector3.UP, float(entry.get("turn", 0.0))), SaveGame.to_vector(entry.get("position")))
		create(type, where, Vector2(float(saved_size[0]), float(saved_size[1])), str(entry.get("name", "")), str(entry.get("id", "")))
