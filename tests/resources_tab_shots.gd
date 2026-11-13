extends Node
## The Village screen's Resources tab (the village ledger), pictured in the real game. Run in a
## window:
##
##     godot --path . res://tests/resources_tab_shots.tscn --resolution 1920x1080 --quit-after 6000
##
## Opens the world in daylight at 100% UI scale, sets up a working Forager's Hut (its chest holding
## a little food, one worker) and a working Storehouse with some stock, brings in more settlers than
## the hut can feed (so food runs short), opens the Resources tab with Berries' detail panel, takes
## one picture (docs/reference/ours/ui/resources_tab.png), then quits (nothing is saved).

const WORLD := "res://world/world.tscn"
const SHOT := "res://docs/reference/ours/ui/resources_tab.png"

var player: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var world: Node = load(WORLD).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	for i in 3000:
		await get_tree().process_frame
		player = get_tree().get_first_node_in_group("player")
		if player:
			break
	if player == null:
		print("RESSHOT | the world didn't open")
		get_tree().quit(1)
		return
	# The loading cover can stay up while the walls' far looks bake (up to two minutes): this picture
	# doesn't need them, so the cover is hidden (the warm-up carries on underneath)
	await _frames(30)
	for warmup in get_tree().root.find_children("*", "ShaderWarmup", true, false):
		for layer in warmup.find_children("*", "CanvasLayer", true, false):
			(layer as CanvasLayer).visible = false
	SaveGame._test_run = true
	GameSettings.ui_scale = 100.0
	GameSettings.apply_ui_scale()
	player.set_physics_process(false)
	var sun = get_tree().get_first_node_in_group("sun")
	if sun:
		sun.time_of_day = 0.42
	var manager: SettlerManager = player._settlers
	var plots: PlotRegistry = player._placer.plots
	manager.set_process(false)
	plots.set_physics_process(false)
	var spot: Vector3 = (player as Node3D).global_position + Vector3(12, 0, 0)
	spot.y = Plot.ground_at(player, spot.x, spot.z)
	var hut := plots.create(load("res://buildables/plots/foragers_hut.tres"), Transform3D(Basis.IDENTITY, spot), Vector2(6, 6))
	hut.working = true
	hut.checked = true
	var chest: Node3D = player._placer.build(load("res://buildables/storage_chest.tres"), spot + Vector3(1, 0, 1), 0.0)
	plots.set_plot_of(chest, hut.plot_id)
	chest.contents = {"Berries": 4, "Mushrooms": 6}
	var store_spot := spot + Vector3(0, 0, 10)
	var storehouse := plots.create(load("res://buildables/plots/storehouse.tres"), Transform3D(Basis.IDENTITY, store_spot), Vector2(6, 6))
	storehouse.working = true
	storehouse.checked = true
	player._placer.registry.spawn(load("res://buildables/furniture/storehouse_storage.tres"), Transform3D(Basis.IDENTITY, store_spot), {}, 0, storehouse.plot_id)
	plots.town.contents = {"Berries": 20, "Mushrooms": 14, "Wood": 86, "Sticks": 40, "Stone": 31, "Plant Fiber": 12, "Herbs": 9, "Copper Ore": 6}
	var crew := []
	for i in 9:
		var s := manager.spawn(spot + Vector3(-3 - i * 0.6, 0, -3), null)
		s.set_physics_process(false)
		crew.append(s)
	manager.assign_job(crew[0], hut)
	await _frames(20)
	var screen: VillageScreen = player._panels.village_screen
	player._panels.open_village()
	screen.show_tab(2)
	await _frames(5)
	screen._show_detail("Berries")
	await _frames(10)
	var ledger := VillageLedger.entries(manager)
	print("RESSHOT | shortages: %s" % ", ".join(ledger["items"].values().filter(func(e): return e["short"]).map(func(e): return e["item"])))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT.get_base_dir()))
	await _frames(12)
	for k in 8:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(SHOT))
	print("RESSHOT | saved %s" % SHOT)
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
