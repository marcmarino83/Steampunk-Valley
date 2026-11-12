extends Node
## The rebuilt panels (the standard panel builder, see BrassPanel), pictured in the real game. Run
## in a window:
##
##     godot --path . res://tests/ui_v1_shots.tscn --resolution 1920x1080 --quit-after 6000
##
## Opens the world in daylight with the hammer out, marks out a Woodcutter's Hut (with its chopping
## block, tool rack and storage chest, so it works) and a Forager's Hut (its basket and chest, but
## no roof), brings a settler (a quest villager, working at the Woodcutter's Hut) and a visitor,
## and pictures the real plot, settler and visitor panels into docs/reference/ours/ui/v1/. Then quits.

const WORLD := "res://world/world.tscn"
const SHOTS := "res://docs/reference/ours/ui/v1"

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
	await _frames(30)
	SaveGame._test_run = true
	DevCheats.freebuild = true
	player.set_physics_process(false)
	player._on_held_changed("Hammer")
	var sun = get_tree().get_first_node_in_group("sun")
	if sun:
		sun.time_of_day = 0.42
	await _frames(5)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	var bp: BuildPlacer = player._placer
	var plots: PlotRegistry = bp.plots
	var ahead: Vector3 = -(player as Node3D).global_basis.z
	ahead.y = 0.0
	ahead = ahead.normalized()
	var side := ahead.cross(Vector3.UP)
	var base: Vector3 = (player as Node3D).global_position + ahead * 14.0

	# The Woodcutter's Hut, working: its chopping block, tool rack and storage chest
	var wood_at := base - side * 6.0
	wood_at.y = Plot.ground_at(player, wood_at.x, wood_at.z)
	var woodcutter := plots.create(load("res://buildables/plots/woodcutters_hut.tres"), Transform3D(Basis.IDENTITY, wood_at), Vector2(8, 10))
	_furniture(bp, "res://buildables/furniture/chopping_block.tres", wood_at + Vector3(-1.5, 0, 0))
	_furniture(bp, "res://buildables/furniture/tool_rack.tres", wood_at + Vector3(1.5, 0, -2.0))
	bp.build(load("res://buildables/storage_chest.tres"), wood_at + Vector3(2.0, 0, 2.0), 0.0)
	plots.adopt(woodcutter)
	# The Forager's Hut: its basket and chest, but nothing over them
	var forage_at := base + side * 7.0
	forage_at.y = Plot.ground_at(player, forage_at.x, forage_at.z)
	var forager := plots.create(load("res://buildables/plots/foragers_hut.tres"), Transform3D(Basis.IDENTITY, forage_at), Vector2(11, 15))
	_furniture(bp, "res://buildables/furniture/foraging_basket.tres", forage_at + Vector3(-1.0, 0, 0))
	bp.build(load("res://buildables/storage_chest.tres"), forage_at + Vector3(2.0, 0, 2.0), 0.0)
	plots.adopt(forager)
	await _frames(10)
	for plot in [woodcutter, forager]:
		plots.check(plot)

	# A settler (a quest villager) working at the Woodcutter's Hut, and a visitor
	var manager: SettlerManager = player._settlers
	var settler: Settler = manager.spawn_debug(player, -1.0)
	if settler:
		settler.quest = true
		manager.assign_job(settler, woodcutter)
	var visitor: Settler = manager.spawn_visitor(forager, (player as Node3D).global_position + ahead * 3.0 + side * 1.5)
	if visitor:
		visitor.background = "Mended clocks in the city. Says the valley ticks slower, and likes it."
		visitor.stay_until = manager.now() + 1.2
	await _frames(60)

	player.open_plot_panel(woodcutter)
	await _save("plot_woodcutter.png")
	player._plot_panel.close()
	player.open_plot_panel(forager)
	await _save("plot_forager.png")
	player._plot_panel.close()
	if settler:
		player.open_settler_panel(settler)
		await _save("settler_panel.png")
		player._settler_panel.close()
	if visitor:
		player.open_settler_panel(visitor)
		await _save("visitor_panel.png")
		player._settler_panel.close()
	print("UISHOTS | woodcutter working: %s, forager missing: %s, settler: %s, visitor: %s" % [woodcutter.working, forager.missing, settler != null, visitor != null])
	get_tree().quit()


func _furniture(bp: BuildPlacer, path: String, at: Vector3) -> void:
	at.y = Plot.ground_at(player, at.x, at.z)
	bp.registry.spawn(load(path), Transform3D(Basis.IDENTITY, at), {})


func _save(file: String) -> void:
	await _frames(10)
	for k in 8:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(SHOTS.path_join(file)))
	print("UISHOTS | saved %s" % file)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
