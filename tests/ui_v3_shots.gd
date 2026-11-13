extends Node
## The interface in its fonts (see BrassStyle's fonts), pictured in the real game. Run in a window:
##
##     godot --path . res://tests/ui_v3_shots.tscn --resolution 1920x1080 --quit-after 9000
##
## Opens the world in daylight with the hammer out at 100% UI scale, marks out a Forager's Hut with
## no roof (and a worker), a working Village Center (its Bell Mast) and a Free build plot, brings
## two settlers and a visitor, then pictures into docs/reference/ours/ui/v3/: the Forager's Hut
## plot panel, the Village screen's Settlers tab, the build menu (its Buildings tab), a "visitor
## arrived" banner, and the title screen. Then quits (nothing is saved).

const WORLD := "res://world/world.tscn"
const TITLE := "res://ui/title_screen.tscn"
const SHOTS := "res://docs/reference/ours/ui/v3"

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
	GameSettings.ui_scale = 100.0
	GameSettings.apply_ui_scale()
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
	var base: Vector3 = (player as Node3D).global_position + ahead * 16.0
	var forage_at := _ground(base)
	var forager := plots.create(load("res://buildables/plots/foragers_hut.tres"), Transform3D(Basis.IDENTITY, forage_at), Vector2(11, 15))
	bp.registry.spawn(load("res://buildables/furniture/foraging_basket.tres"), Transform3D(Basis.IDENTITY, _ground(forage_at + Vector3(-1.0, 0, 0))), {})
	bp.build(load("res://buildables/storage_chest.tres"), forage_at + Vector3(2.0, 0, 2.0), 0.0)
	plots.adopt(forager)
	var center_at := _ground(base + ahead * 14.0 + side * 8.0)
	var center := plots.create(load("res://buildables/plots/village_center.tres"), Transform3D(Basis.IDENTITY, center_at), Vector2(6, 6))
	bp.registry.spawn(load("res://buildables/furniture/bell_mast.tres"), Transform3D(Basis.IDENTITY, center_at), {})
	plots.adopt(center)
	plots.create(load("res://buildables/plots/free_build.tres"), Transform3D(Basis.IDENTITY, _ground(base - side * 12.0)), Vector2(10, 10))
	await _frames(10)
	for p in plots.all_plots():
		plots.check(p)
	var manager: SettlerManager = player._settlers
	var first: Settler = manager.spawn_debug(player, -1.0)
	var second: Settler = manager.spawn_debug(player, 1.0)
	if first:
		manager.assign_job(first, forager)
	if second:
		second.hungry_days = 1
	var visitor: Settler = manager.spawn_visitor(center, (player as Node3D).global_position + ahead * 4.0 + side * 2.5)
	if visitor:
		visitor.background = "Mended clocks in the city. Says the valley ticks slower, and likes it."
		visitor.stay_until = manager.now() + 1.4
		visitor.announced = true
	await _frames(60)

	player.open_plot_panel(forager)
	await _save("plot_forager.png")
	player._panels.plot_panel.close()
	player._panels.open_village()
	player._panels.village_screen.show_tab(0)
	await _save("village_settlers.png")
	player._panels.village_screen.close()
	player._build.open_build_menu()
	var menu = player.build_menu
	menu.show_tab(menu.get_script().get_script_constant_map()["TABS"].find("Buildings"))
	await _save("build_menu.png")
	player._build.close_build_menu()
	await _frames(5)
	player._panels.show_banner("A visitor has arrived", "%s is waiting at the Village Center" % (visitor.settler_name if visitor else "Mira Fenwick"))
	await get_tree().create_timer(0.8).timeout
	await _save("banner_visitor.png")
	print("UISHOTS | forager missing %s, free build working %s, settlers %d, visitors %d" % [forager.missing, plots.plots_of("Free build")[0].working, manager.all_settlers().size(), manager.staying_visitors().size()])

	# The title screen, on its own
	world.queue_free()
	await _frames(5)
	var title: Node = load(TITLE).instantiate()
	get_tree().root.add_child(title)
	get_tree().current_scene = title
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _frames(30)
	await _save("title_screen.png")
	get_tree().quit()


func _ground(at: Vector3) -> Vector3:
	at.y = Plot.ground_at(player, at.x, at.z)
	return at


func _save(file: String) -> void:
	await _frames(12)
	for k in 8:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(SHOTS.path_join(file)))
	print("UISHOTS | saved %s" % file)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
