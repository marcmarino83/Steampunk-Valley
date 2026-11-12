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
## When a plot turns working, `became_working` is sent (the player flashes a message).
##
## Requirements are checked again (on the next physics frame, so new pieces' collision is ready)
## whenever something is placed, removed, moved or resized, and every few seconds anyway.

## A plot that wasn't working now is (not sent for the first check after loading or placing)
signal became_working(plot: Plot)
## Something about the plots worth telling the player (an old plot converted or dropped on loading)
signal notice(text: String)

## The Stone Gatherer's Hut is gone: stone, copper and tin come from the Forager's Hut now. A save's
## old Stone Gatherer's Hut becomes a Forager's Hut if it meets one's requirements, or is dropped
## (its pieces stay standing, owned by no plot); see load_data and _settle_old_plots.
const OLD_STONE_HUT := "res://buildables/plots/stone_gatherers_hut.tres"
const OLD_STONE_HUT_NAME := "Stone Gatherer's Hut"
const GATHERERS_HUT := "res://buildables/plots/foragers_hut.tres"

## Marks a workbench, chest or campfire with the plot that owns it
const OWNER_META := &"owner_plot"
## How often every plot is checked again even if nothing changed (doors, loads...)
const RECHECK_SECONDS := 2.0
## How far above a furniture item a roof can be
const ROOF_REACH := 14.0

## Where plots are added (the world), and the pieces they own
var world: Node
var pieces: PieceRegistry
## The settlement's shared town storage, held by the working Storehouses (see TownStorage)
var town: TownStorage

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
	town = TownStorage.new()
	town.name = "TownStorage"
	town.plots = self
	add_child(town)


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


## Removes just the plot: everything it owned stays standing, owned by no plot. Its ghosts (a
## template's pieces not built yet) go with it.
func remove_plot(plot: Plot) -> void:
	for ghost in ghosts_of(plot):
		remove_ghost(ghost)
	for item in owned_items(plot):
		set_plot_of(item, "")
	_plots.erase(plot.plot_id)
	plot.queue_free()
	mark_dirty()
	# A removed Storehouse's share moves to the rest of town storage, or drops by where it stood
	if plot.plot_type.town_storage_slots > 0:
		town.reconcile(plot.global_position)


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


## Every built piece, furniture item, workbench, chest and campfire the plot owns; with
## `with_ghosts`, its ghosts too (a placed template's pieces not built yet), as for moving it
func owned_items(plot: Plot, with_ghosts := false) -> Array:
	var found := pieces.pieces_owned_by(plot.plot_id)
	if not with_ghosts:
		found = found.filter(func(p): return not p.is_ghost())
	for building in _buildings():
		if building.get_meta(OWNER_META, "") == plot.plot_id:
			found.append(building)
	if with_ghosts:
		for ghost in ghost_buildings():
			if ghost.get_meta(OWNER_META, "") == plot.plot_id:
				found.append(ghost)
	return found


## The plot's ghosts: pieces, furniture and buildings of a placed template still to be built
func ghosts_of(plot: Plot) -> Array:
	var found := pieces.pieces_owned_by(plot.plot_id).filter(func(p): return p.is_ghost())
	for ghost in ghost_buildings():
		if ghost.get_meta(OWNER_META, "") == plot.plot_id:
			found.append(ghost)
	return found


## How far along its building is: {"done": built pieces and buildings, "total": those plus ghosts}
func build_progress(plot: Plot) -> Dictionary:
	var ghosts := ghosts_of(plot).size()
	var built := owned_items(plot).size()
	return {"done": built, "total": built + ghosts}


## What it would take to build every ghost left in the plot (each one's first way of paying)
func materials_needed(plot: Plot) -> Dictionary:
	var needed := {}
	for ghost in ghosts_of(plot):
		var buildable: Buildable = ghost.buildable
		if buildable == null or buildable.costs.is_empty():
			continue
		var cost: Dictionary = buildable.costs[0]
		for item in cost:
			needed[item] = int(needed.get(item, 0)) + int(cost[item])
	return needed


## Takes a ghost away (free: nothing was paid for it)
func remove_ghost(ghost: Node3D) -> void:
	if ghost is BuildPiece:
		pieces.remove(ghost)
	elif is_instance_valid(ghost):
		ghost.remove_from_group("ghost_buildings")
		ghost.queue_free()
	mark_dirty()


## Every ghost workbench, chest and campfire (see GhostBuilding)
func ghost_buildings() -> Array:
	return get_tree().get_nodes_in_group("ghost_buildings").filter(func(b): return is_instance_valid(b) and not b.is_queued_for_deletion())


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
	var timing := SpikeLog.begin()
	_recheck_in = RECHECK_SECONDS
	for plot in all_plots():
		check(plot)
	# A Storehouse that stopped working or lost a shelf: what no longer fits drops by it
	town.reconcile()
	SpikeLog.end("plot checklists", timing)


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
	var was_working := plot.working
	plot.checklist = lines
	plot.working = lines.all(func(line): return line["ok"])
	plot.capacity = int(counts.get(type.houses_per, 0)) if not type.houses_per.is_empty() else 0
	var short: PackedStringArray = []
	for line in lines:
		if not line["ok"]:
			short.append(line.get("short", ""))
	plot.missing = short
	plot.update_status()
	if plot.checked and not was_working and plot.working:
		became_working.emit(plot)
	plot.checked = true
	# A working plot of a type counts toward unlocks ("Plot:Storehouse" unlocks the Village Center)
	if plot.working:
		var player = get_tree().get_first_node_in_group("player")
		if player and player.has_method("has_done") and not player.has_done("Plot", type.display_name):
			player.report_progress("Plot", type.display_name)


## The working plots of a type (by its display name)
func working_of(type_name: String) -> Array:
	return all_plots().filter(func(p): return p.working and p.plot_type.display_name == type_name)


## Every plot of a type, working or not (by its display name)
func plots_of(type_name: String) -> Array:
	return all_plots().filter(func(p): return p.plot_type.display_name == type_name)


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
	# Town storage saves with the Storehouse plots, each with its share of the pool
	var shares := town.shares()
	var list := []
	for plot in all_plots():
		var entry: Dictionary = plot.save_data()
		if shares.has(plot.plot_id) and not (shares[plot.plot_id] as Dictionary).is_empty():
			entry["town_storage"] = shares[plot.plot_id]
		list.append(entry)
	var data := {"next_id": _next_id, "list": list}
	# Should there be stock but no Storehouse at all (it can't normally happen), it's kept here
	if shares.is_empty() and not town.contents.is_empty():
		data["town_storage"] = town.contents.duplicate()
	return data


func load_data(data: Dictionary) -> void:
	for plot in all_plots():
		plot.queue_free()
	_plots.clear()
	_next_id = int(data.get("next_id", 1))
	town.clear()
	town.load_share(data.get("town_storage", {}))
	var converting: Array = []
	for entry in data.get("list", []):
		town.load_share(entry.get("town_storage", {}))
		var type_path := str(entry.get("type", ""))
		var old_stone_hut := type_path == OLD_STONE_HUT
		if old_stone_hut:
			type_path = GATHERERS_HUT
		# (a plot type that no longer exists is left out, without an error)
		if not ResourceLoader.exists(type_path):
			print("PlotRegistry: left out %s, its type %s no longer exists" % [entry.get("name", "a plot"), type_path])
			continue
		var type := load(type_path) as PlotType
		if type == null:
			continue
		var saved_size: Array = entry.get("size", [type.min_size.x, type.min_size.y])
		var where := Transform3D(Basis(Vector3.UP, float(entry.get("turn", 0.0))), SaveGame.to_vector(entry.get("position")))
		var plot_name := str(entry.get("name", ""))
		var plot := create(type, where, Vector2(float(saved_size[0]), float(saved_size[1])), plot_name, str(entry.get("id", "")))
		if old_stone_hut:
			converting.append({"plot": plot, "name": plot_name})
			continue
		# The slider percentages, if they're for the same items the type shares out now (older saves
		# of the Forager's Hut had no stone, copper or tin: they start from the type's split)
		plot.housing = "player" if str(entry.get("housing", "villager")) == "player" else "villager"
		var saved_shares: Dictionary = entry.get("production", {})
		var same_items := saved_shares.size() == type.split_output.size() and saved_shares.keys().all(func(item): return type.split_output.has(str(item)))
		if same_items:
			for item in saved_shares:
				plot.production[str(item)] = int(saved_shares[item])
	if not converting.is_empty():
		_settle_old_plots.call_deferred(converting)


# Old Stone Gatherer's Huts from a save, made Forager's Huts on loading: once their pieces are solid
# (a couple of physics frames), each that meets a Forager's Hut's requirements stays one (renamed
# if it still had the old type's name), and each that doesn't is dropped, its pieces left standing
# owned by no plot. Either way the player is told which.
func _settle_old_plots(converting: Array) -> void:
	for i in 3:
		await get_tree().physics_frame
	for entry in converting:
		var plot: Plot = entry["plot"]
		if not is_instance_valid(plot):
			continue
		var old_name: String = entry["name"]
		check(plot)
		if plot.working:
			if old_name.is_empty() or old_name.begins_with(OLD_STONE_HUT_NAME):
				plot.rename(_free_name(plot.plot_type.display_name))
			var text := "%s (a %s) is now %s, a %s: stone, copper and tin come from there now" % [old_name, OLD_STONE_HUT_NAME, plot.plot_name, plot.plot_type.display_name]
			print("PlotRegistry: " + text)
			notice.emit(text)
		else:
			var text := "%s (a %s) was removed: that building is gone, and it didn't meet a %s's needs (missing %s). Its pieces still stand" % [old_name, OLD_STONE_HUT_NAME, plot.plot_type.display_name, ", ".join(plot.missing)]
			print("PlotRegistry: " + text)
			notice.emit(text)
			remove_plot(plot)
