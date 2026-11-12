extends Node
## The trimmed Forager's Hut plot panel at three UI scales, pictured in the real game. Run in a window:
##
##     godot --path . res://tests/ui_v2_shots.tscn --resolution 1920x1080 --quit-after 6000
##
## Opens the world in daylight with the hammer out, marks out a Forager's Hut with its basket and
## chest but no roof (so a requirement is missing), gives it a worker, opens its panel and pictures
## it at 75%, 100% and 125% UI scale into docs/reference/ours/ui/v2/, then puts the scale back as it
## was and quits (nothing is saved).

const WORLD := "res://world/world.tscn"
const SHOTS := "res://docs/reference/ours/ui/v2"
const SCALES := [75.0, 100.0, 125.0]

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
	var at: Vector3 = (player as Node3D).global_position + ahead * 14.0
	at.y = Plot.ground_at(player, at.x, at.z)
	var forager := plots.create(load("res://buildables/plots/foragers_hut.tres"), Transform3D(Basis.IDENTITY, at), Vector2(11, 15))
	var basket := at + Vector3(-1.0, 0, 0)
	basket.y = Plot.ground_at(player, basket.x, basket.z)
	bp.registry.spawn(load("res://buildables/furniture/foraging_basket.tres"), Transform3D(Basis.IDENTITY, basket), {})
	bp.build(load("res://buildables/storage_chest.tres"), at + Vector3(2.0, 0, 2.0), 0.0)
	plots.adopt(forager)
	var manager: SettlerManager = player._settlers
	var settler: Settler = manager.spawn_debug(player, -1.0)
	if settler:
		manager.assign_job(settler, forager)
	await _frames(30)
	plots.check(forager)
	var kept := GameSettings.ui_scale
	player.open_plot_panel(forager)
	for s in SCALES:
		GameSettings.ui_scale = s
		GameSettings.apply_ui_scale()
		await _save("plot_forager_%d.png" % int(s))
	player._plot_panel.close()
	GameSettings.ui_scale = kept
	GameSettings.apply_ui_scale()
	print("UISHOTS | forager missing: %s, worker: %s" % [forager.missing, settler != null])
	get_tree().quit()


func _save(file: String) -> void:
	await _frames(12)
	for k in 8:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(SHOTS.path_join(file)))
	print("UISHOTS | saved %s" % file)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
