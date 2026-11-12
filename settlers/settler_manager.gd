class_name SettlerManager
extends Node
## Every settler: arrivals, homes and jobs, and saving them. Also owns the settlers' navigation
## (SettlementNav).
##
## Quest villagers: the first two settlers will come from the castle quest. Until that quest exists,
## a stand-in brings them: each morning, while fewer than two have come, if a working villager House
## has a free bed, one refugee walks in from the nearest edge of the valley and moves into it, with
## the permanent quest flag (see Settler.quest). "A refugee named Name has arrived."
##
## Visitors: every other settler is recruited from visitors. While the village has a working Village
## Center, a visitor arrives every VISIT_GAP_DAYS in-game days (by day), at most MAX_VISITORS at a
## time, walking in from the valley's edge; the bell rings as they reach the Bell Mast. They linger
## around it for STAY_DAYS, then walk away and vanish unless recruited (see recruit). They need no bed
## or food. The console's spawn_visitor brings one at once.
##
## Homes: a House set to villager housing holds one settler per bed (its capacity); a Player home is
## never assigned. Settlers only ever get a home by being given one (recruited into it, or assigned in
## their panel), and sleep only in a bed of their own House (its beds in the order they were built,
## residents in the order they arrived), never any other open bed.
## Jobs: each workplace plot type takes PlotType.workers settlers (1 for the Forager's and
## Woodcutter's Huts). Only working plots with a free place can be picked.

## Arrivals (and the console's spawn_settler and spawn_visitor) appear on the visible ground, never
## under it, in water, at the wreck, in a landmark or inside a building: see find_safe_spot. Every
## attempt is written to the console output.

## A refugee arrived (the player shows the message)
signal arrived(settler: Settler)
## A visitor reached the Village Center (the bell has rung), or one was recruited
signal visitor_arrived(visitor: Settler)
signal recruited(settler: Settler)
## Something the player should hear about (a chest full at dawn, a settler hungry or leaving)
signal notice(text: String)

## Dawn (the sun's clock): the day's output is made and arrivals come. Dusk: settlers eat.
## How far from the House arrivals start, and how far away those who leave walk before vanishing.
const ARRIVAL_TIME := 0.27
const DUSK_TIME := 0.74
const ARRIVAL_DISTANCE := 56.0
const LEAVE_SECONDS := 60.0
## How many quest villagers come (from the castle quest, for now the stand-in arrivals)
const QUEST_VILLAGERS := 2
## Visitors: days between arrivals, most at a time, days each lingers, and when it's day enough for
## one to arrive or walk off (the sun's clock). The bell rings when one comes within BELL_REACH of
## the mast, or after BELL_LATE seconds on the way.
const VISIT_GAP_DAYS := Vector2(2.0, 4.0)
const MAX_VISITORS := 3
const STAY_DAYS := Vector2(1.0, 2.0)
const VISIT_DAY := Vector2(0.27, 0.7)
const BELL_REACH := 10.0
const BELL_LATE := 75.0
const BELL_SOUND := "res://assets/village_center/bell_mast/bell_ring.wav"
## A line of background for each visitor, picked at random
const BACKGROUNDS := [
	"A cooper from the lowland towns. The barrel works closed and the road was all that was left.",
	"Walked three weeks from the coast after the harbour cranes stopped turning.",
	"Used to stoke boilers on a river barge until it ran aground for good.",
	"A hedge-school teacher whose village emptied out one family at a time.",
	"Mended clocks in the city. Says the valley ticks slower, and likes it.",
	"Followed the smoke of your chimneys from the far ridge.",
	"A shepherd whose flock was sold off to pay the toll-keepers.",
	"Ran messages for the airship yards before the yards fell silent.",
	"Grew up in a mining camp and knows a good seam when they see one.",
	"Left the city with a satchel of seeds and no plan beyond planting them.",
	"A tinker who has fixed kettles in every village from here to the sea.",
	"Heard the bell from the pass and came down to see who rang it.",
	"Lost a farm to the floods and has been walking ever since.",
	"Worked the looms in a mill town until the mill burned.",
	"Says they were a cook in a great house. Their hands say so too.",
	"Traded furs up and down the valley road, until the traders stopped coming.",
]

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
# Visitors (not settlers yet), when the next one comes (the sun's day count plus time of day; -1:
# not planned, no working Village Center), and how many quest villagers have come
var _visitors: Array = []
var _next_visit_at := -1.0
var _quest_arrivals := 0
var _visit_check_in := 0.0


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


## Working villager Houses with a free bed (never a Player home)
func free_homes() -> Array[Plot]:
	var found: Array[Plot] = []
	for p in plots.all_plots():
		if is_house(p) and p.is_villager_housing() and p.working and residents(p).size() < p.capacity:
			found.append(p)
	return found


## Every visitor at the Village Center (not settlers yet)
func all_visitors() -> Array:
	_visitors = _visitors.filter(func(s): return is_instance_valid(s) and not s.is_queued_for_deletion())
	return _visitors


## The visitors still lingering (not walking off)
func staying_visitors() -> Array:
	return all_visitors().filter(func(v): return not v.leaving)


## The working Village Center (a plot that draws visitors), or null
func village_center() -> Plot:
	if plots == null:
		return null
	for p in plots.all_plots():
		if p.plot_type.draws_visitors and p.working:
			return p
	return null


## The Bell Mast visitors linger around (the working Village Center's), or null
func visitor_mast() -> Node3D:
	var center := village_center()
	return work_furniture(center) if center else null


## A house plot set to Player home: whoever lived there moves out (a Player home is never assigned)
func set_housing(house: Plot, mode: String) -> void:
	house.housing = mode
	if mode == "player":
		for settler in residents(house):
			settler.home_id = ""
			notice.emit("%s moved out of %s: it's your home now." % [settler.settler_name, house.plot_name])


## Working workplaces with a free place
func free_jobs() -> Array[Plot]:
	var found: Array[Plot] = []
	for p in plots.all_plots():
		if is_workplace(p) and p.working and workers(p).size() < p.plot_type.workers:
			found.append(p)
	return found


func assign_home(settler: Settler, house: Plot) -> void:
	if house and not house.is_villager_housing():
		return
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
		if piece.is_door() and not piece.is_ghost():
			found.append(piece)
	return found


## True if the player or any settler or visitor (standing) is this close to a spot
func anyone_near(spot: Vector3, reach: float) -> bool:
	for settler in all_settlers() + all_visitors():
		if not settler.is_sleeping() and settler.global_position.distance_to(spot) < reach:
			return true
	var player := get_tree().get_first_node_in_group("player") as Node3D
	return player != null and player.global_position.distance_to(spot) < reach


# ---- Arrivals ----

func _process(delta: float) -> void:
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
		_dawn()
	if t >= DUSK_TIME and _last_dusk_day < today:
		_last_dusk_day = today
		var timing := SpikeLog.begin()
		economy.dusk()
		SpikeLog.end("dusk (meals)", timing)
	_visit_check_in -= delta
	if _visit_check_in <= 0.0:
		_visit_check_in = 1.0
		_tend_visitors()
	_forget_missing_plots()
	_see_off_leavers()


func _dawn() -> void:
	var timing := SpikeLog.begin()
	economy.dawn()
	_quest_arrival()
	SpikeLog.end("dawn (day's output, arrivals)", timing)
	SpikeLog.note("dawn")


## Now on the sun's clock: its day count plus the time of day (-1 with no sun)
func now() -> float:
	var sun = get_tree().get_first_node_in_group("sun")
	return float(sun.day) + float(sun.time_of_day) if sun else -1.0


## Debug (console "skip_days"): jumps ahead this many mornings, each night's meal, dawn, and the
## visitors' comings and goings handled on the way, as if the days had passed
func skip_days(days: int) -> void:
	var sun = get_tree().get_first_node_in_group("sun")
	if sun == null:
		return
	for i in maxi(days, 0):
		skip_to_dawn()
		_last_dawn_day = sun.day
		_dawn()
		_tend_visitors()


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


# Those leaving vanish once they're well on their way (settlers who left, and visitors who moved on)
func _see_off_leavers() -> void:
	for settler in all_settlers():
		if settler.leaving and (settler.leave_time > LEAVE_SECONDS or settler.global_position.distance_to(settler.leave_to) < 3.0):
			_settlers.erase(settler)
			settler.queue_free()
	for visitor in all_visitors():
		if visitor.leaving and (visitor.leave_time > LEAVE_SECONDS or visitor.global_position.distance_to(visitor.leave_to) < 3.0):
			_visitors.erase(visitor)
			visitor.queue_free()


# The stand-in for the castle quest: each morning, while fewer than QUEST_VILLAGERS have come, a
# refugee comes if a working villager House has a free bed, moves into it, and is a quest villager
# for good. Every attempt is written to the console output (why nobody came, or where they were
# placed and why other spots were turned down).
func _quest_arrival() -> void:
	if _quest_arrivals >= QUEST_VILLAGERS:
		return
	var sun = get_tree().get_first_node_in_group("sun")
	print("[Settlers] Dawn, day %d: checking for a quest villager (%d of %d came so far)" % [sun.day if sun else -1, _quest_arrivals, QUEST_VILLAGERS])
	var homes := free_homes()
	if homes.is_empty():
		var houses := plots.all_plots().filter(func(p): return is_house(p)) if plots else []
		if houses.is_empty():
			print("[Settlers]   nobody arrives: there's no House plot")
		for p in houses:
			var why := "it's a Player home"
			if p.is_villager_housing():
				why = "it isn't working (its checklist isn't met)" if not p.working else "no free bed (%d residents, %d beds)" % [residents(p).size(), p.capacity]
			print("[Settlers]   nobody arrives at %s (%s): %s" % [p.plot_name, p.plot_id, why])
		return
	var house: Plot = homes[0]
	var found := find_safe_spot(_arrival_spot(house), "arrival for %s" % house.plot_name)
	if found.is_empty():
		# Nowhere safe out toward the valley's edge: try by the House itself
		found = find_safe_spot(house.global_position, "arrival beside %s" % house.plot_name)
	if found.is_empty():
		print("[Settlers]   nobody arrives today: no safe spot found (see above); trying again tomorrow")
		return
	var settler := spawn(found["spot"], house)
	settler.quest = true
	_quest_arrivals += 1
	print("[Settlers]   %s (quest villager) arrived at %s, heading for %s" % [settler.settler_name, (found["spot"] as Vector3).snapped(Vector3.ONE * 0.1), house.plot_name])
	arrived.emit(settler)


## Brings a refugee at once, a few steps in front of the player (the console's spawn_settler, and
## F8), `sideways` meters to the right of straight ahead, placed as safely as a dawn arrival (see
## find_safe_spot), with no home or job. Null if there's nowhere safe nearby.
func spawn_debug(player: Node3D, sideways := 0.0) -> Settler:
	var ahead := -player.global_basis.z
	ahead.y = 0.0
	var right := player.global_basis.x
	right.y = 0.0
	var spot := player.global_position + ahead.normalized() * 3.0 + right.normalized() * sideways
	var found := find_safe_spot(spot, "spawn_settler")
	if found.is_empty():
		print("[Settlers]   spawn_settler: no safe spot near the player (see above)")
		return null
	var settler := spawn(found["spot"], null)
	print("[Settlers]   %s brought in at %s" % [settler.settler_name, (found["spot"] as Vector3).snapped(Vector3.ONE * 0.1)])
	arrived.emit(settler)
	return settler


# ---- Visitors ----

# Once a second: plans the next visitor while there's a working Village Center, brings them when
# it's time (by day, below the limit), rings the bell for those who've reached the mast, and sends
# off those whose stay is over (by day). With no working Village Center, visitors move on.
func _tend_visitors() -> void:
	var center := village_center()
	var at := now()
	if at < 0.0:
		return
	var t := fposmod(at, 1.0)
	var daytime := t >= VISIT_DAY.x and t < VISIT_DAY.y
	if center == null:
		_next_visit_at = -1.0
	else:
		if _next_visit_at < 0.0:
			_next_visit_at = at + _rng.randf_range(VISIT_GAP_DAYS.x, VISIT_GAP_DAYS.y)
		if at >= _next_visit_at and daytime and staying_visitors().size() < MAX_VISITORS:
			if spawn_visitor(center) != null:
				_next_visit_at = at + _rng.randf_range(VISIT_GAP_DAYS.x, VISIT_GAP_DAYS.y)
	var mast := visitor_mast()
	for visitor in staying_visitors():
		if not visitor.announced and mast and (visitor.global_position.distance_to(mast.global_position) < BELL_REACH or visitor.travel_time > BELL_LATE):
			visitor.announced = true
			ring_bell(mast.global_position + Vector3.UP * 6.0)
			# (the player shows it as an event banner: "A visitor has arrived")
			visitor_arrived.emit(visitor)
		if center == null or (at >= visitor.stay_until and daytime):
			if visitor.announced and center:
				notice.emit("%s didn't find a home here and has moved on." % visitor.settler_name)
			send_away(visitor)


## Brings a visitor to the Village Center: walking in from the valley's edge (or, with `near`, from
## a few steps in front of that spot: the console's spawn_visitor). Null if there's nowhere safe.
func spawn_visitor(center: Plot, near := Vector3.INF) -> Settler:
	var found := {}
	if near != Vector3.INF:
		found = find_safe_spot(near, "visitor")
	else:
		found = find_safe_spot(_arrival_spot(center), "visitor for %s" % center.plot_name)
		if found.is_empty():
			found = find_safe_spot(center.global_position, "visitor beside %s" % center.plot_name)
	if found.is_empty():
		print("[Settlers]   no visitor: no safe spot found (see above)")
		return null
	var visitor := Settler.new()
	visitor.visitor = true
	visitor.settler_id = "visitor_%d" % _next_id
	_next_id += 1
	visitor.settler_name = _free_name()
	visitor.look = Settler.make_look(_rng.randi())
	visitor.background = BACKGROUNDS[_rng.randi() % BACKGROUNDS.size()]
	visitor.stay_until = maxf(now(), 0.0) + _rng.randf_range(STAY_DAYS.x, STAY_DAYS.y)
	_add_visitor(visitor, found["spot"], _rng.randf() * TAU)
	print("[Settlers]   visitor %s arrived at %s" % [visitor.settler_name, (found["spot"] as Vector3).snapped(Vector3.ONE * 0.1)])
	return visitor


## Recruits a visitor into a free villager House: they become a settler living there, with no job.
## False if that House has no free bed for them (or isn't villager housing).
func recruit(visitor: Settler, house: Plot) -> bool:
	if house == null or not free_homes().has(house) or not visitor.visitor:
		return false
	_visitors.erase(visitor)
	visitor.visitor = false
	visitor.leaving = false
	visitor.settler_id = "settler_%d" % _next_id
	_next_id += 1
	visitor.name = visitor.settler_id
	visitor.home_id = house.plot_id
	visitor.job_id = ""
	_settlers.append(visitor)
	notice.emit("%s has joined the village and moved into %s." % [visitor.settler_name, house.plot_name])
	recruited.emit(visitor)
	return true


## Rings the Bell Mast's bell: a sound at the bell, heard across the valley
func ring_bell(at: Vector3) -> void:
	if not ResourceLoader.exists(BELL_SOUND) or not (world is Node3D):
		return
	var bell := AudioStreamPlayer3D.new()
	bell.stream = load(BELL_SOUND)
	bell.unit_size = 25.0
	bell.max_db = 3.0
	bell.attenuation_model = AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC
	world.add_child(bell)
	bell.global_position = at
	bell.finished.connect(bell.queue_free)
	bell.play()


# ---- Safe places to appear ----

## How far a spot may move from the one first wanted, in rings (meters), each tried at SAFE_TURNS
## directions; and how high above the ground the downward look starts (above any building)
const SAFE_RINGS := [0.0, 3.0, 6.0, 10.0, 15.0, 20.0, 28.0, 40.0, 55.0, 75.0]
const SAFE_TURNS := 8
const SAFE_LOOK_FROM := 80.0
## Too steep to stand on (degrees), and how close a building piece may be
const SAFE_SLOPE := 32.0
const SAFE_BUILDING_GAP := 1.5


## A safe spot for a settler to appear near `wanted` (x and z; any height): {"spot": Vector3} on the
## visible ground, or empty if there's none within the last ring. Each spot is tried as it is and,
## where the settlers' navigation is ready, moved onto the nearest walkable point; every one turned
## down is logged with why (see _spot_problem).
func find_safe_spot(wanted: Vector3, purpose: String) -> Dictionary:
	print("[Settlers] Placing (%s): wanted %s" % [purpose, wanted.snapped(Vector3.ONE * 0.1)])
	var tried := 0
	for radius in SAFE_RINGS:
		var turns := 1 if radius == 0.0 else SAFE_TURNS
		for i in turns:
			var candidate := wanted + Vector3(radius, 0, 0).rotated(Vector3.UP, TAU * i / turns)
			var spots := [candidate]
			if nav and nav.is_ready_at(candidate):
				var walkable := nav.closest_point(candidate)
				if walkable.distance_to(candidate) > 0.3 and Vector2(walkable.x - candidate.x, walkable.z - candidate.z).length() < 4.0:
					spots.append(walkable)
			for spot in spots:
				tried += 1
				var check := _spot_problem(spot)
				if check["problem"].is_empty():
					print("[Settlers]   placed at %s (try %d)" % [(check["spot"] as Vector3).snapped(Vector3.ONE * 0.1), tried])
					return {"spot": check["spot"]}
				print("[Settlers]   %s: %s" % [(spot as Vector3).snapped(Vector3.ONE * 0.1), check["problem"]])
	return {}


# Why a settler can't appear at this spot (x and z), or no problem: {"problem": String, "spot"}.
# It looks straight down from well above the ground; the first solid thing met must be the
# valley's open ground (not a building, tree, rock or landmark), dry, not too steep, clear of the
# wreck, landmarks and rock outcrops, and not inside a building's footprint.
func _spot_problem(at: Vector3) -> Dictionary:
	var valley = get_tree().get_first_node_in_group("valley")
	if valley == null or not (world is Node3D):
		return {"problem": "no valley to stand on", "spot": at}
	var origin: Vector3 = valley.global_position
	var lx := at.x - origin.x
	var lz := at.z - origin.z
	var ground := Plot.ground_at(world, at.x, at.z)
	var from := Vector3(at.x, ground + SAFE_LOOK_FROM, at.z)
	var query := PhysicsRayQueryParameters3D.create(from, Vector3(at.x, ground - 10.0, at.z))
	query.collide_with_areas = false
	var player := get_tree().get_first_node_in_group("player") as CollisionObject3D
	var skip: Array[RID] = []
	if player:
		skip.append(player.get_rid())
	for settler in all_settlers() + all_visitors():
		skip.append(settler.get_rid())
	query.exclude = skip
	var hit := (world as Node3D).get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"problem": "no ground found under it", "spot": at}
	var spot: Vector3 = hit["position"]
	var what: Object = hit["collider"]
	if what is BuildPiece:
		return {"problem": "on a building piece (%s)" % (what as BuildPiece).display_name(), "spot": spot}
	# The valley's ground is drawn in chunks, each its own body (see valley.gd's terrain_ground)
	if not (what is Node and (what as Node).is_in_group("terrain_ground")):
		return {"problem": "on %s, not open ground" % ((what as Node).name if what is Node else "something"), "spot": spot}
	if spot.y < ground - 0.3:
		return {"problem": "under the terrain", "spot": spot}
	if spot.y < origin.y + valley.water_height() + 0.3:
		return {"problem": "in water", "spot": spot}
	if valley.is_near_crash_site(lx, lz):
		return {"problem": "at the airship wreck", "spot": spot}
	if valley.is_under_placed(lx, lz):
		return {"problem": "inside a landmark or rock outcrop (the castle ruin, say)", "spot": spot}
	if valley.is_under_building(lx, lz, 0.5):
		return {"problem": "inside a building's footprint", "spot": spot}
	if plots and plots.pieces:
		for piece in plots.pieces.pieces_near(spot, SAFE_BUILDING_GAP + 2.0):
			if not piece.is_ghost() and (piece as BuildPiece).global_position.distance_to(spot) < SAFE_BUILDING_GAP:
				return {"problem": "right against a building piece (%s)" % piece.display_name(), "spot": spot}
	if valley.get_slope(lx, lz) > SAFE_SLOPE:
		return {"problem": "too steep (%.0f°)" % valley.get_slope(lx, lz), "spot": spot}
	return {"problem": "", "spot": spot + Vector3.UP * 0.05}


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


func _add_visitor(visitor: Settler, spot: Vector3, turn: float) -> void:
	visitor.manager = self
	visitor.name = visitor.settler_id
	world.add_child(visitor)
	visitor.global_position = standing_spot(spot)
	visitor.rotation.y = turn
	_visitors.append(visitor)


## A spot to stand at: on the floor or ground found under a point (looking from a little above it,
## so a settler never starts inside the ground and falls through)
func standing_spot(spot: Vector3) -> Vector3:
	var ground := Plot.ground_at(world, spot.x, spot.z) if world is Node3D else spot.y
	var from := Vector3(spot.x, maxf(spot.y, ground) + 1.2, spot.z)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 6.0, 1)
	var hit := (world as Node3D).get_world_3d().direct_space_state.intersect_ray(query) if world is Node3D else {}
	var y: float = hit["position"].y if not hit.is_empty() else maxf(spot.y, ground)
	return Vector3(spot.x, maxf(y, ground) + 0.05, spot.z)


# Where an arrival would like to start: ARRIVAL_DISTANCE from the House toward the nearest edge of
# the valley, on dry ground (turning a little either way if that's water). find_safe_spot then
# checks it and moves it if it must.
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
	for settler in all_settlers() + all_visitors():
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
	var lingering := staying_visitors()
	return {"next_id": _next_id, "last_dawn_day": _last_dawn_day, "last_dusk_day": _last_dusk_day,
		"list": staying.map(func(s): return s.save_data()),
		"visitors": lingering.map(func(s): return s.save_data()),
		"next_visit_at": _next_visit_at, "quest_arrivals": _quest_arrivals}


func load_data(data: Dictionary) -> void:
	for settler in all_settlers() + all_visitors():
		settler.queue_free()
	_settlers.clear()
	_visitors.clear()
	_next_id = int(data.get("next_id", 1))
	_last_dawn_day = int(data.get("last_dawn_day", -1))
	_last_dusk_day = int(data.get("last_dusk_day", -1))
	_next_visit_at = float(data.get("next_visit_at", -1.0))
	for entry in data.get("list", []):
		var settler := _loaded(entry)
		_add(settler, SaveGame.to_vector(entry.get("position")), float(entry.get("turn", 0.0)))
	for entry in data.get("visitors", []):
		var visitor := _loaded(entry)
		visitor.visitor = true
		visitor.home_id = ""
		visitor.job_id = ""
		visitor.stay_until = float(entry.get("stay_until", 0.0))
		visitor.announced = bool(entry.get("announced", true))
		_add_visitor(visitor, SaveGame.to_vector(entry.get("position")), float(entry.get("turn", 0.0)))
	if data.has("quest_arrivals"):
		_quest_arrivals = int(data["quest_arrivals"])
	else:
		# A save from before quest villagers: its two earliest settlers are the quest villagers
		var earliest := _settlers.duplicate()
		earliest.sort_custom(func(a, b): return int(a.settler_id.trim_prefix("settler_")) < int(b.settler_id.trim_prefix("settler_")))
		for settler in earliest.slice(0, QUEST_VILLAGERS):
			settler.quest = true
		_quest_arrivals = mini(earliest.size(), QUEST_VILLAGERS)


# A settler or visitor as saved (not yet in the world)
func _loaded(entry: Dictionary) -> Settler:
	var settler := Settler.new()
	settler.settler_id = str(entry.get("id", "settler_%d" % _next_id))
	settler.settler_name = str(entry.get("name", _free_name()))
	var saved_look = entry.get("look", {})
	settler.look = saved_look if saved_look is Dictionary and not saved_look.is_empty() else Settler.make_look(hash(settler.settler_id))
	settler.home_id = str(entry.get("home", ""))
	settler.job_id = str(entry.get("job", ""))
	settler.hungry_days = int(entry.get("hungry_days", 0))
	settler.quest = bool(entry.get("quest", false))
	settler.background = str(entry.get("background", ""))
	var number := int(settler.settler_id.get_slice("_", settler.settler_id.get_slice_count("_") - 1))
	_next_id = maxi(_next_id, number + 1)
	return settler
