class_name SettlerManager
extends Node
## Every settler: arrivals, homes and jobs, and saving them. Also owns the settlers' navigation
## (SettlementNav).
##
## Arrival (for now, until quests bring refugees): each morning, if a working House has a free bed,
## one refugee arrives, walking in from the direction of the nearest edge of the valley, and moves
## into that House. At most one a day. "A refugee named Name has arrived." In debug builds, F9
## brings one at once, a few steps in front of the player (see the player).
##
## Homes: a House holds one settler per bed (its capacity); each resident sleeps in a bed of their
## own (the House's beds in the order they were built, residents in the order they arrived).
## Jobs: each workplace plot type takes PlotType.workers settlers (1 for the Forager's, Woodcutter's
## and Stone Gatherer's Huts). Only working plots with a free place can be picked.

## A refugee arrived (the player shows the message)
signal arrived(settler: Settler)
## Something the player should hear about (a chest full at dawn, a settler hungry or leaving)
signal notice(text: String)

## Dawn (the sun's clock): the day's output is made and arrivals come. Dusk: settlers eat.
## How far from the House arrivals start, and how far away those who leave walk before vanishing.
const ARRIVAL_TIME := 0.27
const DUSK_TIME := 0.74
const ARRIVAL_DISTANCE := 56.0
const LEAVE_SECONDS := 60.0

const FIRST_NAMES := ["Ada", "Bram", "Corin", "Della", "Edda", "Finn", "Greta", "Hollis", "Ines", "Jory",
		"Kasia", "Lorne", "Mira", "Nils", "Orla", "Piet", "Rosa", "Silas", "Tamsin", "Ulric", "Vera",
		"Wren", "Yusuf", "Zora", "Alder", "Bettany", "Cass", "Dorian", "Elsie", "Hamish", "Ivo", "Lark",
		"Marta", "Odo", "Pell", "Runa", "Sef", "Tobin", "Una", "Agnes", "Basil", "Calla", "Emeric", "Fen"]
const LAST_NAMES := ["Ashdown", "Brack", "Cobb", "Dunmore", "Ellery", "Fenwick", "Garrow", "Hale", "Ivers",
		"Kettle", "Lowe", "Marsh", "Nettle", "Oakes", "Penhallow", "Quarry", "Rook", "Sallow", "Thorne",
		"Vane", "Whitlock", "Yarrow", "Coppersmith", "Tinley", "Holloway", "Mabry", "Stroud", "Wick"]

## The world settlers walk in, and the plots they live and work in
var world: Node
var plots: PlotRegistry
var nav: SettlementNav
## The daily output and meals
var economy: SettlementEconomy

var _settlers: Array = []
var _next_id := 1
# The last day (the sun's day count) whose dawn and dusk have been handled (-1: not yet known)
var _last_dawn_day := -1
var _last_dusk_day := -1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("saveable")
	add_to_group("settler_manager")
	_rng.randomize()
	nav = SettlementNav.new()
	nav.plots = plots
	nav.settlers = self
	add_child(nav)
	economy = SettlementEconomy.new()
	economy.manager = self
	economy.notice.connect(func(text): notice.emit(text))
	add_child(economy)


func all_settlers() -> Array:
	_settlers = _settlers.filter(func(s): return is_instance_valid(s) and not s.is_queued_for_deletion())
	return _settlers


func plot(id: String) -> Plot:
	return plots.find(id) if not id.is_empty() and plots else null


## The settlers living in a House, in the order they arrived
func residents(house: Plot) -> Array:
	return all_settlers().filter(func(s): return s.home_id == house.plot_id)


## The settlers working at a workplace
func workers(workplace: Plot) -> Array:
	return all_settlers().filter(func(s): return s.job_id == workplace.plot_id)


## True for a House (it holds settlers), and for a workplace (it takes workers)
static func is_house(p: Plot) -> bool:
	return not p.plot_type.houses_per.is_empty()


static func is_workplace(p: Plot) -> bool:
	return p.plot_type.workers > 0


## Working Houses with a free bed
func free_homes() -> Array[Plot]:
	var found: Array[Plot] = []
	for p in plots.all_plots():
		if is_house(p) and p.working and residents(p).size() < p.capacity:
			found.append(p)
	return found


## Working workplaces with a free place
func free_jobs() -> Array[Plot]:
	var found: Array[Plot] = []
	for p in plots.all_plots():
		if is_workplace(p) and p.working and workers(p).size() < p.plot_type.workers:
			found.append(p)
	return found


func assign_home(settler: Settler, house: Plot) -> void:
	settler.home_id = house.plot_id if house else ""


func assign_job(settler: Settler, workplace: Plot) -> void:
	settler.job_id = workplace.plot_id if workplace else ""


## The bed a settler sleeps in: their House's beds in the order they were built, one per resident
## in the order they arrived; null if there's no bed for them
func bed_for(settler: Settler) -> BuildPiece:
	var house := plot(settler.home_id)
	if house == null:
		return null
	var beds: Array = plots.owned_items(house).filter(func(item): return item is BuildPiece and plots.name_of(item) == house.plot_type.houses_per)
	beds.sort_custom(func(a, b): return a.piece_id < b.piece_id)
	var index := residents(house).find(settler)
	return beds[index] if index >= 0 and index < beds.size() else null


## The furniture a workplace's worker works at (the first one it owns), or null
func work_furniture(workplace: Plot) -> Node3D:
	var wanted := workplace.plot_type.work_at
	for item in plots.owned_items(workplace):
		if plots.name_of(item) == wanted:
			return item
	return null


## The nearest campfire or fireplace, or null
func nearest_fire(spot: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for fire in get_tree().get_nodes_in_group("campfires"):
		var node := fire as Node3D
		if node == null or node.is_queued_for_deletion():
			continue
		var distance := node.global_position.distance_to(spot)
		if distance < best_distance:
			best = node
			best_distance = distance
	return best


## Doors within reach of a spot
func doors_near(spot: Vector3, reach: float) -> Array:
	var found := []
	for piece in plots.pieces.pieces_near(spot, reach):
		if piece.is_door():
			found.append(piece)
	return found


## True if the player or any settler (standing) is this close to a spot
func anyone_near(spot: Vector3, reach: float) -> bool:
	for settler in all_settlers():
		if not settler.is_sleeping() and settler.global_position.distance_to(spot) < reach:
			return true
	var player := get_tree().get_first_node_in_group("player") as Node3D
	return player != null and player.global_position.distance_to(spot) < reach


# ---- Arrivals ----

func _process(_delta: float) -> void:
	var sun = get_tree().get_first_node_in_group("sun")
	if sun == null:
		return
	var t: float = sun.time_of_day
	var today: int = sun.day
	# On a new game or an older save, start counting from today without running anything
	if _last_dawn_day < 0:
		_last_dawn_day = today if t >= ARRIVAL_TIME else today - 1
		_last_dusk_day = today if t >= DUSK_TIME else today - 1
	if t >= ARRIVAL_TIME and _last_dawn_day < today:
		_last_dawn_day = today
		economy.dawn()
		_morning_arrival()
	if t >= DUSK_TIME and _last_dusk_day < today:
		_last_dusk_day = today
		economy.dusk()
	_forget_missing_plots()
	_see_off_leavers()


## Debug (F10): jumps to the next dawn, having tonight's meal first if it hasn't happened yet; the
## day's output and any arrival follow at once
func skip_to_dawn() -> void:
	var sun = get_tree().get_first_node_in_group("sun")
	if sun == null:
		return
	var t: float = sun.time_of_day
	if t >= ARRIVAL_TIME:
		if _last_dusk_day < sun.day:
			_last_dusk_day = sun.day
			economy.dusk()
		sun.day += 1
	sun.time_of_day = ARRIVAL_TIME + 0.001


## A settler leaves for good (three hungry days): they give up their home and job and walk off
## toward the valley's edge, vanishing after a while
func send_away(settler: Settler) -> void:
	settler.home_id = ""
	settler.job_id = ""
	var away := settler.global_position + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized() * ARRIVAL_DISTANCE
	var valley = get_tree().get_first_node_in_group("valley")
	if valley:
		var map: Rect2 = valley.map_rect()
		var local := Vector2(settler.global_position.x - valley.global_position.x, settler.global_position.z - valley.global_position.z)
		var gaps := {Vector3.LEFT: local.x - map.position.x, Vector3.RIGHT: map.end.x - local.x,
				Vector3.FORWARD: local.y - map.position.y, Vector3.BACK: map.end.y - local.y}
		var nearest := INF
		for side in gaps:
			if gaps[side] < nearest:
				nearest = gaps[side]
				away = settler.global_position + side * ARRIVAL_DISTANCE
	settler.leave(away)


# Those leaving vanish once they're well on their way
func _see_off_leavers() -> void:
	for settler in all_settlers():
		if settler.leaving and (settler.leave_time > LEAVE_SECONDS or settler.global_position.distance_to(settler.leave_to) < 3.0):
			_settlers.erase(settler)
			settler.queue_free()


# Each morning: a refugee comes if a working House has a free bed
func _morning_arrival() -> void:
	var homes := free_homes()
	if homes.is_empty():
		return
	var house: Plot = homes[0]
	var settler := spawn(_arrival_spot(house), house)
	arrived.emit(settler)


## Brings a refugee at once, a few steps in front of the player (the debug key, F9)
func spawn_debug(player: Node3D) -> Settler:
	var ahead := -player.global_basis.z
	ahead.y = 0.0
	var spot := player.global_position + ahead.normalized() * 3.0
	spot.y = Plot.ground_at(player, spot.x, spot.z)
	var homes := free_homes()
	var settler := spawn(spot, homes[0] if not homes.is_empty() else null)
	arrived.emit(settler)
	return settler


## A new settler with a name and look of their own, standing at a spot
func spawn(spot: Vector3, house: Plot) -> Settler:
	var settler := Settler.new()
	settler.settler_id = "settler_%d" % _next_id
	_next_id += 1
	settler.settler_name = _free_name()
	settler.look = Settler.make_look(_rng.randi())
	settler.home_id = house.plot_id if house else ""
	_add(settler, spot, _rng.randf() * TAU)
	return settler


func _add(settler: Settler, spot: Vector3, turn: float) -> void:
	settler.manager = self
	settler.name = settler.settler_id
	world.add_child(settler)
	settler.global_position = standing_spot(spot)
	settler.rotation.y = turn
	_settlers.append(settler)


## A spot to stand at: on the floor or ground found under a point (looking from a little above it,
## so a settler never starts inside the ground and falls through)
func standing_spot(spot: Vector3) -> Vector3:
	var ground := Plot.ground_at(world, spot.x, spot.z) if world is Node3D else spot.y
	var from := Vector3(spot.x, maxf(spot.y, ground) + 1.2, spot.z)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 6.0, 1)
	var hit := (world as Node3D).get_world_3d().direct_space_state.intersect_ray(query) if world is Node3D else {}
	var y: float = hit["position"].y if not hit.is_empty() else maxf(spot.y, ground)
	return Vector3(spot.x, maxf(y, ground) + 0.05, spot.z)


# Where an arrival starts: ARRIVAL_DISTANCE from the House toward the nearest edge of the valley,
# on dry ground (turning a little either way if that's water)
func _arrival_spot(house: Plot) -> Vector3:
	var valley = get_tree().get_first_node_in_group("valley")
	var home := house.global_position
	var toward := Vector3.FORWARD
	if valley:
		var map: Rect2 = valley.map_rect()
		var local := Vector2(home.x - valley.global_position.x, home.z - valley.global_position.z)
		var gaps := {Vector3.LEFT: local.x - map.position.x, Vector3.RIGHT: map.end.x - local.x,
				Vector3.FORWARD: local.y - map.position.y, Vector3.BACK: map.end.y - local.y}
		var nearest := INF
		for side in gaps:
			if gaps[side] < nearest:
				nearest = gaps[side]
				toward = side
		var water: float = valley.global_position.y + valley.water_height()
		for i in 12:
			var turn := floorf((i + 1) / 2.0) * (0.35 if i % 2 == 0 else -0.35)
			var dir := toward.rotated(Vector3.UP, turn)
			var spot := home + dir * ARRIVAL_DISTANCE
			spot.y = Plot.ground_at(house, spot.x, spot.z)
			if spot.y > water + 0.3 and valley.get_slope(spot.x - valley.global_position.x, spot.z - valley.global_position.z) < 25.0:
				return spot
	var fallback := home + toward * 12.0
	fallback.y = Plot.ground_at(house, fallback.x, fallback.z)
	return fallback


func _free_name() -> String:
	var taken := {}
	for settler in all_settlers():
		taken[settler.settler_name] = true
	for i in 50:
		var candidate := "%s %s" % [FIRST_NAMES[_rng.randi() % FIRST_NAMES.size()], LAST_NAMES[_rng.randi() % LAST_NAMES.size()]]
		if not taken.has(candidate):
			return candidate
	return "%s %d" % [FIRST_NAMES[0], _next_id]


# A plot that's gone takes its residents' home and its worker's job with it
func _forget_missing_plots() -> void:
	for settler in all_settlers():
		if not settler.home_id.is_empty() and plot(settler.home_id) == null:
			settler.home_id = ""
		if not settler.job_id.is_empty() and plot(settler.job_id) == null:
			settler.job_id = ""


# ---- Saving ----

func save_key() -> String:
	return "settlers"


# After the plots, which homes and jobs refer to
func save_priority() -> int:
	return 40


func save_data() -> Dictionary:
	var staying := all_settlers().filter(func(s): return not s.leaving)
	return {"next_id": _next_id, "last_dawn_day": _last_dawn_day, "last_dusk_day": _last_dusk_day, "list": staying.map(func(s): return s.save_data())}


func load_data(data: Dictionary) -> void:
	for settler in all_settlers():
		settler.queue_free()
	_settlers.clear()
	_next_id = int(data.get("next_id", 1))
	_last_dawn_day = int(data.get("last_dawn_day", -1))
	_last_dusk_day = int(data.get("last_dusk_day", -1))
	for entry in data.get("list", []):
		var settler := Settler.new()
		settler.settler_id = str(entry.get("id", "settler_%d" % _next_id))
		settler.settler_name = str(entry.get("name", _free_name()))
		var saved_look = entry.get("look", {})
		settler.look = saved_look if saved_look is Dictionary and not saved_look.is_empty() else Settler.make_look(hash(settler.settler_id))
		settler.home_id = str(entry.get("home", ""))
		settler.job_id = str(entry.get("job", ""))
		settler.hungry_days = int(entry.get("hungry_days", 0))
		_add(settler, SaveGame.to_vector(entry.get("position")), float(entry.get("turn", 0.0)))
		_next_id = maxi(_next_id, int(settler.settler_id.trim_prefix("settler_")) + 1)
