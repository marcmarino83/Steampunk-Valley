extends Node
## TEST: the Village screen's Resources tab (the village ledger, VillageLedger). Run headless:
##
##     godot --headless --path . res://tests/ledger_check.tscn --quit-after 20000
##
## Opens a new world (nothing is saved), stops the clock's own dawns and dusks and the plots'
## re-checks, and sets up a working Forager's Hut with a storage chest and settlers. Then:
##   1. Day 1 (output into the hut's chest, no Storehouse): the ledger's planned made and used per
##      day for every resource match what dawn actually put in the stores and dusk's meals took out
##      (the player takes nothing).
##   2. Day 2, with a working Storehouse (town storage) and more mouths than food: the same match,
##      and the food the village runs down on shows as short.
##   3. The hut's sliders: one moved in the ledger's detail panel and one moved in the plot panel
##      are the same value (the plot's own), each panel shows the other's change, and the ledger's
##      planned numbers follow at once.
## Prints "LEDGER PASS" or "LEDGER FAIL" with what went wrong, and quits (exit code 1 on a failure).

const WORLD := "res://world/world.tscn"
const HUT := "res://buildables/plots/foragers_hut.tres"
const STOREHOUSE := "res://buildables/plots/storehouse.tres"
const STOREHOUSE_STORAGE := "res://buildables/furniture/storehouse_storage.tres"
const CHEST := "res://buildables/storage_chest.tres"
const STEP_LIMIT := 3000

var player: Node
var manager: SettlerManager
var plots: PlotRegistry
var _problems: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var world: Node = load(WORLD).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	for i in STEP_LIMIT:
		await get_tree().process_frame
		player = get_tree().get_first_node_in_group("player")
		if player:
			break
	if player == null:
		_fail("the world didn't open")
		_finish()
		return
	SaveGame.set("_test_run", true)
	await _frames(10)
	manager = player._settlers
	plots = player._placer.plots
	# The test runs the days itself
	manager.set_process(false)
	plots.set_physics_process(false)
	player.set_physics_process(false)
	for s in manager.all_settlers():
		manager.send_away(s)
	await _frames(2)
	var spot: Vector3 = player.global_position + Vector3(12, 0, 0)
	spot.y = Plot.ground_at(player, spot.x, spot.z)
	var hut := plots.create(load(HUT), Transform3D(Basis.IDENTITY, spot), Vector2(6, 6))
	hut.working = true
	hut.checked = true
	var chest: Node3D = player._placer.build(load(CHEST), spot + Vector3(1, 0, 1), 0.0)
	plots.set_plot_of(chest, hut.plot_id)
	chest.contents = {"Berries": 3, "Mushrooms": 9}
	var crew := _settlers(4, spot)
	manager.assign_job(crew[0], hut)

	# 1. Day 1: into the hut's chest
	_day("day 1 (hut chest, no Storehouse)")

	# 2. Day 2: a working Storehouse, and more mouths than food
	var store_spot := spot + Vector3(0, 0, 10)
	var storehouse := plots.create(load(STOREHOUSE), Transform3D(Basis.IDENTITY, store_spot), Vector2(6, 6))
	storehouse.working = true
	storehouse.checked = true
	player._placer.registry.spawn(load(STOREHOUSE_STORAGE), Transform3D(Basis.IDENTITY, store_spot), {}, 0, storehouse.plot_id)
	if not plots.town.is_open():
		_fail("the test Storehouse didn't open town storage")
	_settlers(8, spot)
	var ledger := VillageLedger.entries(manager)
	var shorts: Array = ledger["items"].values().filter(func(e): return e["short"] and e["category"] == "Food")
	if shorts.is_empty():
		_fail("day 2: 12 settlers on one hut's food, but no food shows as short")
	else:
		print("LEDGER | day 2 shortages: %s" % ", ".join(shorts.map(func(e): return "%s (%s)" % [e["item"], VillageScreen._storage_text(e, ledger["short"])])))
	_day("day 2 (town storage, shortage)")

	# 3. The sliders
	await _sliders(hut)
	_finish()


# Plans the next day, runs dawn and dusk, and checks the plan against what happened
func _day(label: String) -> void:
	var ledger := VillageLedger.entries(manager)
	var items: Dictionary = ledger["items"]
	var before := _stock()
	manager.economy.dawn()
	var after_dawn := _stock()
	manager.economy.dusk()
	var after_dusk := _stock()
	var names := {}
	for d in [items, before, after_dawn, after_dusk]:
		for k in d:
			names[k] = true
	var checked := 0
	var bad := 0
	for item in names:
		var made := int(after_dawn.get(item, 0)) - int(before.get(item, 0))
		var eaten := int(after_dawn.get(item, 0)) - int(after_dusk.get(item, 0))
		var e: Dictionary = items.get(item, {"made": 0, "used": 0})
		checked += 1
		if int(e["made"]) != made or int(e["used"]) != eaten:
			bad += 1
			_fail("%s: %s planned made %d / used %d, but %d were made and %d eaten" % [label, item, e["made"], e["used"], made, eaten])
	print("LEDGER | %s: %d resources, planned made and used matched what happened for %d (meals short %d)" % [label, checked, checked - bad, ledger["short"]])


# Everything in the settlement's stores: town storage plus the plots' chests
func _stock() -> Dictionary:
	var out := {}
	for item in plots.town.contents:
		out[item] = int(out.get(item, 0)) + int(plots.town.contents[item])
	for chest in manager.economy.settlement_chests():
		for item in chest.contents:
			out[item] = int(out.get(item, 0)) + int(chest.contents[item])
	return out


func _sliders(hut: Plot) -> void:
	var screen: VillageScreen = player._panels.village_screen
	screen.open()
	screen.show_tab(2)
	screen._show_detail("Berries")
	await _frames(2)
	if screen._detail_sliders.is_empty():
		_fail("the Berries detail panel has no sliders for the Forager's Hut")
		return
	var from_ledger: ShareSliders = screen._detail_sliders[0]
	player._panels.plot_panel.open(hut, false)
	await _frames(2)
	var from_plot: ShareSliders = player._panels.plot_panel._share_sliders
	if from_plot == null:
		_fail("the plot panel has no sliders for the Forager's Hut")
		return
	if from_ledger.plot != from_plot.plot or from_ledger.plot != hut:
		_fail("the two panels' sliders aren't for the same plot")
	# Moved in the ledger
	(from_ledger.sliders["Berries"] as HSlider).value = 50
	player._panels.plot_panel._refresh()
	var shared := int(hut.shares()["Berries"])
	var shown := int((from_plot.sliders["Berries"] as HSlider).value)
	if shared != 50 or shown != 50:
		_fail("Berries set to 50%% in the ledger: the plot holds %d%%, its panel shows %d%%" % [shared, shown])
	_planned_follow(screen, hut, "after the ledger's slider")
	# Moved at the building
	(from_plot.sliders["Mushrooms"] as HSlider).value = 40
	screen._refresh()
	shared = int(hut.shares()["Mushrooms"])
	shown = int((from_ledger.sliders["Mushrooms"] as HSlider).value)
	if shared != 40 or shown != 40:
		_fail("Mushrooms set to 40%% in the plot panel: the plot holds %d%%, the ledger shows %d%%" % [shared, shown])
	if int((from_ledger.sliders["Berries"] as HSlider).value) != int(hut.shares()["Berries"]):
		_fail("after the plot panel's change, the ledger's Berries slider no longer matches the plot")
	_planned_follow(screen, hut, "after the plot panel's slider")
	var total := 0
	for item in hut.shares():
		total += int(hut.shares()[item])
	if total != 100:
		_fail("the shares add up to %d%%, not 100%%" % total)
	print("LEDGER | sliders: set from the ledger and from the plot panel, one value (Berries %d%%, Mushrooms %d%%); the planned numbers followed" % [hut.shares()["Berries"], hut.shares()["Mushrooms"]])
	player._panels.plot_panel.close()
	screen.close()


# The ledger's planned made for the hut's items is what the hut would make at dawn now
func _planned_follow(screen: VillageScreen, hut: Plot, label: String) -> void:
	var crew: Array = manager.workers(hut).filter(func(s): return not s.leaving)
	var expected := manager.economy.output_today(hut, crew)
	var items: Dictionary = screen._ledger.get("items", {})
	for item in hut.shares():
		var planned := 0
		if items.has(item):
			for s in items[item]["sources"]:
				if s["plot"] == hut:
					planned = int(s["amount"])
		if planned != int(expected.get(item, 0)):
			_fail("%s: the ledger plans %d %s a day from the hut, the hut would make %d" % [label, planned, item, expected.get(item, 0)])


func _settlers(n: int, near: Vector3) -> Array:
	var made := []
	for i in n:
		var s := manager.spawn(near + Vector3(-3 - i * 0.6, 0, -3), null)
		s.set_physics_process(false)
		made.append(s)
	return made


func _fail(text: String) -> void:
	_problems.append(text)


func _finish() -> void:
	if _problems.is_empty():
		print("LEDGER PASS: the planned numbers matched a simulated day (twice), and the sliders are one shared value")
	else:
		print("LEDGER FAIL: %d problem(s)" % _problems.size())
		for p in _problems:
			print("LEDGER FAIL | " + p)
	get_tree().quit(0 if _problems.is_empty() else 1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
