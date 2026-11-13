extends Node
## TEST: the T1 opening from a brand-new game, step by step (report only, changes nothing). Run
## headless:
##
##     godot --headless --path . res://tests/new_game_audit.tscn --quit-after 40000
##
## Starts a New Game through SaveGame (marked a test run at once, so nothing is saved), then walks the
## T1 opening with shortcuts (giving items, skipping time, placing the built-in templates), checking
## each step's result directly: what the player starts with, gathering by hand, the stone tools and
## what they unlock, the lean-to and sleeping in it, the workbench and chest, the castle ruin, a House
## and the quest villagers, the Forager's Hut and jobs, four days without food, the Storehouse, the
## Village Center and visitors, then what's still locked, any cost nobody can get, the text on screen,
## and every error the engine or a script reported. Prints "AUDIT" lines, then quits.
##
## Part of the full suite (tests/run_suite.ps1): what must stay true is checked ("AUDIT FAIL" lines,
## and an "AUDIT SUMMARY" line at the end; exit code 1 on any failure or error): the empty start,
## picking things up by hand, the unlock chain (Hammer → Lean-to and plots, Axe + Pickaxe →
## Workbench → Storage Chest, Planks → building pieces, a working Storehouse → Village Center),
## sleeping in the lean-to, a working House bringing two quest villagers, the Forager's Hut making
## its day's output once they've eaten, quest villagers never leaving, and the Village Center
## working. Known gaps (the castle quest, objectives) are reported, not failed.

var _checks := 0
var _failed: Array[String] = []


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed.append(what)
		print("AUDIT FAIL " + what)

class Catcher extends Logger:
	var errors: Array[String] = []
	var _lock := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _n: bool, error_type: int, _b: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_lock.lock()
		errors.append("%s (%s:%d, %s)" % [rationale if not rationale.is_empty() else code, file.get_file(), line, function])
		_lock.unlock()
	func _log_message(_m: String, _e: bool) -> void:
		pass

var catcher := Catcher.new()
var root: Window
var sg: Node
var player: Node
var registry: PieceRegistry
var plots: PlotRegistry
var manager: SettlerManager
var placer: BuildPlacer
var start := Vector3.ZERO


func _ready() -> void:
	root = get_tree().root
	OS.add_logger(catcher)
	_run.call_deferred()


func say(s: String) -> void:
	print("AUDIT | " + s)


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	await get_tree().process_frame
	sg = root.get_node_or_null("SaveGame")
	# (New Game replaces the current scene: a stand-in is made current first, so this test stays)
	var stand := Node.new()
	root.add_child(stand)
	get_tree().current_scene = stand
	var t0 := Time.get_ticks_msec()
	sg.new_game()
	for i in 6000:
		await get_tree().process_frame
		player = get_tree().get_first_node_in_group("player")
		if player and sg._in_world:
			break
	# (a test run from here on: nothing is saved, no world appears in the save list)
	sg._test_run = true
	await frames(30)
	say("new game opened in %.1f s (headless)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	registry = player._placer.registry
	plots = player._placer.plots
	manager = player._settlers
	placer = player._placer
	start = player.global_position
	await _start_state()
	_resources()
	await _gather_and_craft()
	await _lean_to_and_sleep()
	await _workbench_and_chest()
	_castle()
	var house := await _house()
	await _quest_villagers(house)
	var hut := await _forager()
	await _hunger(hut)
	await _storehouse()
	await _village_center()
	await _panel_keys()
	_still_locked()
	_hud_leftovers()
	await frames(5)
	var seen := {}
	say("errors during the run: %d" % catcher.errors.size())
	for e in catcher.errors:
		if not seen.has(e):
			seen[e] = true
			say("  error: " + e)
	check(catcher.errors.is_empty(), "no engine or script errors in a new game's opening (%d)" % catcher.errors.size())
	print("AUDIT SUMMARY: %d checks, %d passed, %d failed" % [_checks, _checks - _failed.size(), _failed.size()])
	OS.remove_logger(catcher)
	get_tree().quit(0 if _failed.is_empty() else 1)


# ---- 0. What the player starts with ----

func _start_state() -> void:
	var sun = get_tree().get_first_node_in_group("sun")
	say("start: at %s, day %d, time %.3f (sunrise 0.25, sunset 0.75); day %.0f min + night %.0f min = %.0f min a full day" % [start.snapped(Vector3.ONE * 0.1), sun.day, sun.time_of_day, sun.day_minutes, sun.night_minutes, sun.day_minutes + sun.night_minutes])
	say("start: inventory %s; held '%s'" % [player.inventory, player.held_item])
	check(player.inventory.is_empty() and player.held_item == "", "a new game starts with empty pockets and nothing in hand")
	say("start: hunger %.0f, stamina %.0f; warmth on: %s; cheats: freebuild %s god %s fly %s" % [player.hunger, player.stamina, player._survival.warmth_on, DevCheats.freebuild, DevCheats.god, DevCheats.fly])
	var unlocked := []
	var locked := []
	for b in player._all_blueprints():
		if player._progress.is_unlocked(b):
			unlocked.append(b.display_name)
		else:
			locked.append(b.display_name)
	say("start: %d blueprints usable: %s" % [unlocked.size(), ", ".join(unlocked)])
	say("start: %d locked" % locked.size())
	for n in _scripted("crash_site.gd"):
		say("start: crash site %.0f m away" % start.distance_to((n as Node3D).global_position))
	for n in _scripted("world/note.gd"):
		say("start: note '%s' %.0f m away" % [n.get("title") if n.get("title") != null else n.name, start.distance_to((n as Node3D).global_position)])
	say("start: settlers in the world: %d; visitors %d" % [manager.all_settlers().size(), manager.all_visitors().size()])


func _resources() -> void:
	var counts := {}
	var near := {}
	var nearest := {}
	var tools := {}
	for n in root.find_children("*", "StaticBody3D", true, false):
		if n is ResourceNode:
			var item: String = n.resource_name
			counts[item] = int(counts.get(item, 0)) + 1
			var d := start.distance_to((n as Node3D).global_position)
			if d < 60.0:
				near[item] = int(near.get(item, 0)) + 1
			nearest[item] = minf(float(nearest.get(item, INF)), d)
			if not tools.has(item):
				tools[item] = ("needs " + n.required_tool) if n.required_tool != "" else "by hand"
	say("resources in the world: %s" % counts)
	say("resources within 60 m of the start: %s" % near)
	say("nearest of each: %s" % ", ".join(nearest.keys().map(func(k): return "%s %.0f m" % [k, nearest[k]])))
	say("gathering: %s" % tools)
	var trees := _scripted("world/tree.gd")
	say("trees: %d with the tree script, %d within 60 m" % [trees.size(), trees.filter(func(t): return start.distance_to((t as Node3D).global_position) < 60.0).size()])


# ---- 1. Gather, craft the stone tools ----

func _gather_and_craft() -> void:
	# A real gather by hand: the nearest stone, sticks and plant fiber
	for item in ["Stone", "Sticks", "Plant Fiber"]:
		var best: Node = null
		var bd := INF
		for n in root.find_children("*", "StaticBody3D", true, false):
			if n is ResourceNode and n.resource_name == item and n.required_tool == "" and n.visible:
				var d := start.distance_to((n as Node3D).global_position)
				if d < bd:
					bd = d
					best = n
		if best == null:
			say("step 1: no %s to pick up by hand anywhere" % item)
			continue
		var before := int(player.inventory.get(item, 0))
		best.interact(player)
		await frames(2)
		say("step 1: picked up %s by hand (%.0f m away): %d → %d" % [item, bd, before, int(player.inventory.get(item, 0))])
		check(int(player.inventory.get(item, 0)) > before, "%s can be picked up by hand near the start" % item)
	var unlocked_before := _unlocked_names()
	for item in ["Stone", "Sticks", "Plant Fiber"]:
		player.gathered(item, 20)
	_new_unlocks("step 1: gathering stone, sticks and fiber", unlocked_before)
	for tool in ["Hammer", "Axe", "Pickaxe", "Knife"]:
		var r := _recipe(tool)
		if r == null:
			say("step 2: no recipe for %s" % tool)
			continue
		var before := _unlocked_names()
		var was: bool = player._progress.is_unlocked(r)
		player._crafting.craft(r)
		await frames(1)
		say("step 2: craft %s (%s, %s; usable before: %s): now have %d" % [tool, r.station, r.costs, was, int(player.inventory.get(tool, 0))])
		check(was and int(player.inventory.get(tool, 0)) == 1, "the %s can be crafted by hand from the start" % tool)
		_new_unlocks("step 2: crafting the %s" % tool, before)
	for name in ["Lean-to", "House", "Forager's Hut", "Storehouse", "Workbench"]:
		check(player._progress.is_unlocked(_buildable(name)), "%s is unlocked once the stone tools are made" % name)
	await _views_follow()


# The views that show what you own bring themselves up to date: the backpack shows what isn't on
# the action bar, a tool put on the bar leaves the backpack, the bar lets go of a tool you no longer
# own, and the build menu knows what's locked
func _views_follow() -> void:
	check(_backpack_shown() == _backpack_wanted(), "the backpack shows what you carry that isn't on the action bar")
	var bar: ActionBar = player.action_bar
	bar.assign("Knife", 0)
	await frames(1)
	check(bar.has_item("Knife") and not _backpack_shown().has("Knife") and _backpack_shown() == _backpack_wanted(), "a tool put on the action bar leaves the backpack")
	player.remove_item("Knife", 1)
	await frames(1)
	check(not bar.has_item("Knife"), "the action bar lets go of a tool you no longer own")
	var menu = player.build_menu
	check(menu._unlocked(_buildable("Lean-to")) and not menu._unlocked(_buildable("Village Center")), "the build menu knows what's unlocked and what's still locked")


# What the backpack's slots show: item -> count
func _backpack_shown() -> Dictionary:
	var shown := {}
	for slot in player.inventory_screen.grid.get_children():
		if not slot._empty:
			shown[slot._item] = int(slot.count_label.text.trim_prefix("x"))
	return shown


# What it should show: everything you own that isn't on the action bar
func _backpack_wanted() -> Dictionary:
	var wanted := {}
	for item in player.inventory:
		if not player.action_bar.has_item(item):
			wanted[item] = int(player.inventory[item])
	return wanted


# ---- 2. Lean-to; sleep in it ----

func _lean_to_and_sleep() -> void:
	var lean := _buildable("Lean-to")
	say("step 3: Lean-to usable: %s, cost %s" % [player._progress.is_unlocked(lean), lean.costs])
	player.gathered("Wood", 30)
	var built := _place_building(lean, start + Vector3(4, 0, 0))
	await frames(5)
	var sun = get_tree().get_first_node_in_group("sun")
	var mat := built.get_node_or_null("Mat")
	if mat == null:
		say("step 3: the lean-to has no sleeping mat")
		return
	sun.time_of_day = 0.5
	mat.interact(player)
	await frames(3)
	say("step 3: sleeping by day says: '%s'" % player._message)
	sun.time_of_day = 0.8
	var day_before: int = sun.day
	var hunger_before: float = player.hunger
	mat.interact(player)
	# (until you wake, however fast the frames run: then measured at once, before the day moves on)
	await frames(2)
	for i in 3000:
		if not player._sleeping:
			break
		await get_tree().process_frame
	say("step 3: slept in the lean-to at 0.80: now day %d (was %d), time %.3f, hunger %.0f (was %.0f), stamina %.0f, still sleeping %s" % [sun.day, day_before, sun.time_of_day, player.hunger, hunger_before, player.stamina, player._sleeping])
	check(sun.day == day_before + 1 and absf(sun.time_of_day - 0.27) < 0.01 and not player._sleeping, "sleeping in the lean-to at night wakes you the next morning")
	check(absf(player.hunger - (hunger_before - 25.0)) < 1.0, "a night's sleep costs 25 hunger")


# ---- 3. Workbench, rope and planks, chest ----

func _workbench_and_chest() -> void:
	var bench := _buildable("Workbench")
	say("step 4: Workbench usable: %s (%s %s + %s), cost %s" % [player._progress.is_unlocked(bench), bench.unlocked_by, bench.unlock_item, bench.get("unlock_also"), bench.costs])
	var before := _unlocked_names()
	_place_building(bench, player.global_position + Vector3(1.5, 0, 0))
	await frames(3)
	_new_unlocks("step 4: building the Workbench", before)
	say("step 4: stations in reach: %s" % player._crafting.nearby_stations())
	check(player._progress.is_unlocked(_buildable("Storage Chest")), "building the Workbench unlocks the Storage Chest")
	check(player._crafting.nearby_stations().has("workbench"), "the Workbench counts as a station in reach")
	for item in ["Rope", "Planks", "Torch", "Spear"]:
		var r := _recipe(item)
		var have := int(player.inventory.get(item, 0))
		var b2 := _unlocked_names()
		player._crafting.craft(r)
		await frames(1)
		say("step 4: craft %s (usable %s): %d → %d" % [item, player._progress.is_unlocked(r), have, int(player.inventory.get(item, 0))])
		_new_unlocks("step 4: crafting %s" % item, b2)
	check(player._progress.is_unlocked(_buildable("Floor")) and player._progress.is_unlocked(_buildable("Wall 2 m")), "the first Planks unlock the building pieces")
	check(player.inventory_screen.crafting._stations.has("workbench"), "the crafting tab knows the workbench is in reach")
	for i in 3:
		player._crafting.craft(_recipe("Planks"))
	var chest := _buildable("Storage Chest")
	say("step 4: Storage Chest usable: %s, cost %s, have planks %d, rope %d" % [player._progress.is_unlocked(chest), chest.costs, int(player.inventory.get("Planks", 0)), int(player.inventory.get("Rope", 0))])
	var c := _place_building(chest, player.global_position + Vector3(-1.5, 0, 1.0))
	say("step 4: chest placed: %s, its prompt: '%s'" % [c != null, c.get_prompt() if c else ""])
	# Opening it (the inventory opens beside it), a stack in and back out
	player.gathered("Stone", 5)
	var stone := int(player.inventory.get("Stone", 0))
	player.open_chest(c)
	await frames(1)
	player.inventory_screen.item_moved.emit("Stone", "backpack")
	var in_chest := int(c.contents.get("Stone", 0))
	player.inventory_screen.item_moved.emit("Stone", "chest")
	say("step 4: chest opened (inventory showing %s); Stone in: chest %d, back: backpack %d (was %d)" % [player.inventory_screen.visible, in_chest, int(player.inventory.get("Stone", 0)), stone])
	check(player.inventory_screen.visible and in_chest == stone and int(player.inventory.get("Stone", 0)) == stone and not c.contents.has("Stone"), "a chest opens beside the inventory, and a stack moves into it and back")
	player._toggle_inventory()


# ---- 4. The ruined castle ----

func _castle() -> void:
	var castle: Node3D = root.find_child("CastleRuin", true, false)
	if castle == null:
		say("step 5: no castle ruin in the world")
		return
	say("step 5: castle ruin at %s, %.0f m from the start" % [castle.global_position.snapped(Vector3.ONE), start.distance_to(castle.global_position)])
	var near := manager.all_settlers().filter(func(s): return s.global_position.distance_to(castle.global_position) < 60.0)
	say("step 5: people at the castle: %d; things to interact with in it: %d" % [near.size(), castle.find_children("*", "", true, false).filter(func(n): return n.has_method("interact")).size()])


# ---- 5. A house; the quest villagers ----

func _house() -> Plot:
	return await _template_plot("basic_house", "House", start + Vector3(25, 0, 0), "step 6")


func _quest_villagers(house: Plot) -> void:
	if house == null:
		return
	for k in 3:
		manager.skip_to_dawn()
		manager._dawn()
		await frames(5)
		var q := manager.all_settlers().filter(func(s): return s.quest)
		say("step 6: dawn %d with the House: %d settlers, %d quest villagers (%s), homes %s" % [k + 1, manager.all_settlers().size(), q.size(), ", ".join(q.map(func(s): return s.settler_name)), q.map(func(s): return manager.plot(s.home_id).plot_name if manager.plot(s.home_id) else "none")])
	var quest := manager.all_settlers().filter(func(s): return s.quest)
	check(house.working, "the Basic House template makes a working House")
	check(quest.size() == 2 and quest.all(func(s): return s.home_id == house.plot_id), "a working House brings the two quest villagers, who live in it")


# ---- 6. Food: Forager's Hut, jobs ----

func _forager() -> Plot:
	var hut := await _template_plot("forager_s_hut", "Forager's Hut", start + Vector3(25, 0, 18), "step 7")
	if hut == null:
		return null
	var q := manager.all_settlers().filter(func(s): return s.quest)
	if q.is_empty():
		say("step 7: no quest villager to give the job to")
		return hut
	say("step 7: free jobs: %s" % manager.free_jobs().map(func(p): return p.plot_name))
	manager.assign_job(q[0], hut)
	var chest = manager.economy.chest_of(hut)
	say("step 7: quest villagers' hungry days before any food: %s; the hungry worker would make %s" % [q.map(func(s): return s.hungry_days), manager.economy.output_today(hut, manager.workers(hut))])
	var before: Dictionary = chest.contents.duplicate() if chest else {}
	manager.skip_days(1)
	await frames(5)
	say("step 7: a day later (no food anywhere) the hut's chest holds %s (was %s); worker: '%s', hungry days %d" % [chest.contents if chest else "no chest", before, q[0].status_text(), q[0].hungry_days])
	# As a player would: berries picked by hand put into the hut's chest (a plot's chest, which
	# settlers eat from; the player's own chests outside every plot they never touch)
	if chest:
		chest.put("Berries", 12)
	manager.skip_days(1)
	await frames(5)
	say("step 7: with 12 berries put in the hut's chest: a day later it holds %s; hungry days %s; worker: '%s'" % [chest.contents if chest else "no chest", q.map(func(s): return s.hungry_days), q[0].status_text()])
	check(hut.working, "the Forager's Hut template makes a working Forager's Hut")
	check(chest != null and int(chest.contents.get("Stone", 0)) > 0 and q.all(func(s): return s.hungry_days == 0), "fed, the quest villagers eat and the Forager's Hut makes its day's output")
	manager.skip_days(1)
	await frames(5)
	say("step 7: and the day after: the chest holds %s; hungry days %s" % [chest.contents if chest else "no chest", q.map(func(s): return s.hungry_days)])
	return hut


func _hunger(hut: Plot) -> void:
	var q := manager.all_settlers().filter(func(s): return s.quest)
	if q.is_empty():
		return
	# Every bit of food taken away, and taken again after each dawn's output
	for d in 4:
		for c in manager.economy.settlement_chests():
			for f in SettlementEconomy.FOODS:
				c.contents.erase(f)
		for f in SettlementEconomy.FOODS:
			plots.town.contents.erase(f)
		manager.skip_to_dawn()
		manager._dawn()
		await frames(3)
	var still := manager.all_settlers().filter(func(s): return s.quest and not s.leaving)
	say("step 7: four nights with no food: quest villagers still here %d of %d; hungry days %s; status %s" % [still.size(), q.size(), q.map(func(s): return s.hungry_days), q.map(func(s): return s.status_text())])
	check(still.size() == q.size(), "quest villagers never leave, however long they go hungry")
	if hut:
		var made := manager.economy.output_today(hut, manager.workers(hut))
		say("step 7: what the hungry worker makes today: %s" % made)
		check(made.is_empty(), "a hungry quest villager stops working (makes nothing)")


# ---- 7. Storage ----

func _storehouse() -> void:
	var before := _unlocked_names()
	await _template_plot("storehouse", "Storehouse", start + Vector3(45, 0, 0), "step 8")
	_new_unlocks("step 8: the Storehouse working", before)
	say("step 8: town storage open: %s, %d slots" % [plots.town.is_open(), plots.town.capacity()])
	check(plots.town.is_open(), "a working Storehouse opens town storage")
	# Deposit resources at its Storehouse Storage: every material and food goes in, tools stay
	var shelf: Node3D = null
	for p in registry.all_pieces():
		if (p as BuildPiece).buildable.display_name == "Storehouse Storage":
			shelf = p
	if shelf:
		player.global_position = shelf.global_position + Vector3(0, 1, 1.5)
		player.gathered("Plant Fiber", 4)
		var fiber_before := int(plots.town.contents.get("Plant Fiber", 0))
		var carried := int(player.inventory.get("Plant Fiber", 0))
		player.open_town_storage(shelf)
		await frames(1)
		player.inventory_screen.deposit_requested.emit()
		say("step 8: deposited at the Storehouse Storage: town Plant Fiber %d → %d; still carrying fiber %d, hammer %d" % [fiber_before, int(plots.town.contents.get("Plant Fiber", 0)), int(player.inventory.get("Plant Fiber", 0)), int(player.inventory.get("Hammer", 0))])
		check(int(plots.town.contents.get("Plant Fiber", 0)) == fiber_before + carried and not player.inventory.has("Plant Fiber") and player.inventory.has("Hammer"), "Deposit resources puts materials into town storage and keeps tools")
		# Walking away closes it
		player.global_position = shelf.global_position + Vector3(0, 1, 12.0)
		await frames(3)
		check(not player.inventory_screen.visible, "walking away from town storage closes it")
	else:
		check(false, "the Storehouse template has a Storehouse Storage")
	check(player._progress.is_unlocked(_buildable("Village Center")), "a working Storehouse unlocks the Village Center")


# ---- 8. Village Center, visitors ----

func _village_center() -> void:
	var vc_type := _buildable("Village Center") as PlotType
	if vc_type == null:
		say("step 9: no Village Center in the build menu's list")
		return
	say("step 9: Village Center usable: %s (%s %s)" % [player._progress.is_unlocked(vc_type), vc_type.unlocked_by, vc_type.unlock_item])
	var at := start + Vector3(45, 0, 20)
	at.y = Plot.ground_at(player, at.x, at.z)
	var plot := plots.create(vc_type, Transform3D(Basis.IDENTITY, at), Vector2(maxf(vc_type.min_size.x, 6), maxf(vc_type.min_size.y, 6)))
	var mast := load("res://buildables/furniture/bell_mast.tres") as Buildable
	if mast is PieceBuildable:
		registry.spawn(mast, Transform3D(Basis.IDENTITY, at), {}, 0, plot.plot_id)
	else:
		plots.set_plot_of(placer.build(mast, at, 0.0), plot.plot_id)
	plots.check(plot)
	await frames(3)
	say("step 9: Village Center working: %s, missing %s" % [plot.working, plot.missing])
	check(plot.working, "a Village Center plot with the Bell Mast works")
	var homes := manager.free_homes()
	say("step 9: free villager homes: %d" % homes.size())
	for k in 6:
		manager.skip_days(1)
		await frames(3)
	var v := manager.staying_visitors()
	say("step 9: after 6 days: visitors staying %d (all visitors %d)" % [v.size(), manager.all_visitors().size()])
	if not v.is_empty():
		homes = manager.free_homes()
		if homes.is_empty():
			# (the first House is full with the two quest villagers: a second one, as a player would)
			await _template_plot("basic_house", "House", start + Vector3(25, 0, -16), "step 9")
			homes = manager.free_homes()
		var ok := false
		if not homes.is_empty():
			ok = manager.recruit(v[0], homes[0])
		say("step 9: recruit %s into %s: %s" % [v[0].settler_name, homes[0].plot_name if not homes.is_empty() else "(no free home)", ok])


# ---- The panels' keys (E closes, Q and R switch the Village screen's tabs, V closes it; a panel
# opened from the Village screen goes back to it) ----

func _panel_keys() -> void:
	var screen: VillageScreen = player._panels.village_screen
	# Drawn in the HUD as always: the note page under the frames-per-second label; the plot panel,
	# the Village screen and a settler's panel above the HUD and menus, under the black of sleep; the
	# pause menu and the banner over it
	var at := func(node: Node) -> int: return node.get_index()
	var fade: Node = player._fade
	var order_ok: bool = at.call(player._panels.note_panel) == at.call(player._fps_label) - 1 \
		and at.call(player._panels.plot_panel) < at.call(screen) and at.call(screen) < at.call(player._panels.settler_panel) \
		and at.call(player._panels.settler_panel) == at.call(fade) - 1 and at.call(player._panels.plot_panel) > at.call(player.inventory_screen) \
		and at.call(player._panels.pause_menu) == at.call(fade) + 1 and at.call(player._panels.banner) == at.call(fade) + 2
	check(order_ok, "the panels are drawn in the HUD in their usual order")
	player._panels.open_village()
	await frames(1)
	var tab_before: int = screen._tab
	_press(KEY_R)
	await frames(1)
	var tab_after: int = screen._tab
	_press(KEY_Q)
	await frames(1)
	check(screen.is_open() and tab_after == posmod(tab_before + 1, VillageScreen.TABS.size()) and screen._tab == tab_before, "R and Q switch the Village screen's tabs")
	_press(KEY_V)
	await frames(1)
	check(not screen.is_open(), "V closes the Village screen")
	player._panels.open_village()
	await frames(1)
	_press(KEY_E)
	await frames(1)
	check(not screen.is_open(), "E closes the Village screen")
	# A settler's panel opened from the Village screen: E closes it and goes back to the screen
	var someone: Array = manager.all_settlers()
	if not someone.is_empty():
		player._panels.open_village()
		await frames(1)
		screen.settler_requested.emit(someone[0])
		await frames(1)
		var opened: bool = player._panels.settler_panel.is_open() and not screen.is_open()
		_press(KEY_E)
		await frames(2)
		check(opened and not player._panels.settler_panel.is_open() and screen.is_open(), "a settler's panel opened from the Village screen goes back to it when E closes it")
		_press(KEY_E)
		await frames(1)
	# The plot panel and the note page: E closes them
	var a_plot: Plot = plots.all_plots()[0] if not plots.all_plots().is_empty() else null
	if a_plot:
		player.open_plot_panel(a_plot)
		await frames(1)
		var plot_open: bool = player._panels.plot_panel.is_open()
		_press(KEY_E)
		await frames(1)
		check(plot_open and not player._panels.plot_panel.is_open(), "E closes the plot panel")
	player.read_note("Audit", "A test page.")
	await frames(1)
	var note_open: bool = player._panels.note_panel.is_open()
	_press(KEY_E)
	await frames(1)
	check(note_open and not player._panels.note_panel.is_open() and player._progress.has_read("Audit"), "E closes the note page, and the note counts as read")


# A key press (and its release) through the player's own input handling
func _press(key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		player._unhandled_input(event)


# ---- Helpers ----

func _template_plot(name: String, type_name: String, near: Vector3, step: String) -> Plot:
	var type := _buildable(type_name) as PlotType
	if type == null:
		say("%s: no %s plot type in the build menu's list" % [step, type_name])
		return null
	say("%s: %s plot usable: %s" % [step, type_name, player._progress.is_unlocked(type)])
	var template := BuildingTemplate.read("res://buildables/templates/%s.json" % name)
	if template == null:
		say("%s: no %s template" % [step, name])
		return null
	var at := near
	at.y = Plot.ground_at(player, at.x, at.z)
	var frame := Transform3D(Basis.IDENTITY, at)
	var plot := plots.create(type, frame, template.size)
	var n := 0
	for item in template.items:
		var b: Buildable = item["buildable"]
		var where: Transform3D = frame * (item["relative"] as Transform3D)
		if b is PieceBuildable:
			registry.spawn(b, where, {}, 0, plot.plot_id)
		else:
			plots.set_plot_of(placer.build(b, where.origin, where.basis.get_euler().y), plot.plot_id)
		n += 1
	await frames(5)
	plots.check(plot)
	await frames(3)
	say("%s: %s placed from the '%s' template (%d items, %s m): working %s, missing %s, holds %d; the template costs %s" % [step, type_name, name, n, template.size, plot.working, plot.missing, plot.capacity, template.total_cost()])
	return plot


func _place_building(b: Buildable, where: Vector3) -> Node3D:
	if not player._progress.is_unlocked(b):
		say("   (placing %s while it's still locked)" % b.display_name)
	if not b.can_afford(player.inventory):
		say("   (can't afford %s: %s)" % [b.display_name, b.missing_text(player.inventory)])
	player.pay(b.costs[0] if not b.costs.is_empty() else {})
	where.y = Plot.ground_at(player, where.x, where.z)
	var built := placer.build(b, where, 0.0)
	player.report_progress("Build", b.display_name)
	return built


func _recipe(result: String) -> Recipe:
	for r in player.inventory_screen.crafting.all_recipes():
		if r.result == result:
			return r
	return null


func _buildable(name: String) -> Buildable:
	for b in player.build_menu.all_buildables():
		if b.display_name == name:
			return b
	return null


func _scripted(ending: String) -> Array:
	return root.find_children("*", "", true, false).filter(func(n): return n.get_script() and (n.get_script() as Script).resource_path.ends_with(ending))


func _unlocked_names() -> Array:
	var out := []
	for b in player._all_blueprints():
		if player._progress.is_unlocked(b):
			out.append(b.display_name)
	return out


func _new_unlocks(what: String, before: Array) -> void:
	var fresh := _unlocked_names().filter(func(n): return not before.has(n))
	say("%s unlocked %d: %s" % [what, fresh.size(), ", ".join(fresh) if fresh.size() <= 12 else ", ".join(fresh.slice(0, 12)) + " and %d more" % (fresh.size() - 12)])


func _still_locked() -> void:
	for b in player._all_blueprints():
		if not player._progress.is_unlocked(b):
			say("end: still locked: %s (%s %s, also %s)" % [b.display_name, b.unlocked_by, b.unlock_item, b.get("unlock_also")])
	# Every cost: can it be gathered, crafted or made by a workplace?
	var gotten := {"Wood": true}
	for n in root.find_children("*", "StaticBody3D", true, false):
		if n is ResourceNode:
			gotten[n.resource_name] = true
	for r in player.inventory_screen.crafting.all_recipes():
		gotten[r.result] = true
	for t in PlotRegistry.all_types():
		for i in t.daily_output:
			gotten[i] = true
		for i in t.split_output:
			gotten[i] = true
	var needed := {}
	for b in player._all_blueprints():
		var lists: Array = [(b as Recipe).costs] if b is Recipe else (b as Buildable).costs
		for cost in lists:
			for item in cost:
				needed[item] = needed.get(item, []) + [b.display_name]
	for item in needed:
		if not gotten.has(item):
			say("end: '%s' is needed (by %s) but can't be gathered, crafted or made by a workplace" % [item, ", ".join((needed[item] as Array).slice(0, 4))])


func _hud_leftovers() -> void:
	var shown := []
	for l in root.find_children("*", "Label", true, false):
		if (l as Label).is_visible_in_tree() and not (l as Label).text.strip_edges().is_empty():
			shown.append("'%s'" % (l as Label).text.replace("\n", " / ").left(60))
	say("end: text showing on screen (no menus open): %s" % ", ".join(shown))
	say("end: debug build %s; console present %s; test-run note showing %s" % [OS.is_debug_build(), player._console != null, sg._test_note.visible])
