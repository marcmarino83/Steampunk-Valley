class_name PanelHost
extends Node
## The panels that open over the game, made and wired in one place: the plot panel (which also asks
## plots' yes/no questions), a settler's or visitor's panel, the Village screen, the parchment page
## notes open on, Esc's pause menu, and the event banner. Opening one closes the inventory and stops
## any placing first (see `before_open`) and frees the mouse; a settler's or plot's panel opened from
## the Village screen goes back to it when closed. While one of the plot panel, a settler's panel,
## the Village screen or the note page is open it has the keys: E and Esc close it (Q and R switch the
## Village screen's tabs, V closes it). A child of the player (see player.gd, which forwards its old
## functions here).

const NOTE_PANEL_SCENE = preload("res://ui/note_panel.tscn")
const PAUSE_MENU_SCENE = preload("res://ui/pause_menu.tscn")

var plot_panel: PlotPanel
var settler_panel: SettlerPanel
var village_screen: VillageScreen
var note_panel: Control
var pause_menu: Control
var banner: EventBanner

## What the panels need, set by the player before build(): the placer (moving or removing a plot,
## the plots), the settlers, whether a blueprint is unlocked, saving a plot as a template, a short
## message, remembering a note as read, whether the hammer is in hand, and what to do before a panel
## opens (close the inventory, stop placing)
var placer: BuildPlacer
var settlers: SettlerManager
var is_unlocked: Callable
var save_template: Callable
var flash: Callable
var mark_read: Callable
var hammer_out: Callable
var before_open: Callable

# A settler's or plot's panel was opened from the Village screen: closing it goes back there
var _back_to_village := false


## Makes the panels and puts them in the HUD where they've always been drawn: the note page just
## before `note_before` (the frames-per-second label); the plot panel, the Village screen and a
## settler's panel above the HUD and menus, just under `fade` (the black of sleep); the pause menu and
## the banner just over it
func build(hud: Node, fade: Control, note_before: Control) -> void:
	note_panel = NOTE_PANEL_SCENE.instantiate()
	hud.add_child(note_panel)
	hud.move_child(note_panel, note_before.get_index())
	plot_panel = PlotPanel.new()
	hud.add_child(plot_panel)
	hud.move_child(plot_panel, fade.get_index())
	plot_panel.closed.connect(_after_child_panel)
	plot_panel.move_requested.connect(func(plot):
		# (moving it goes straight to the hammer, not back to the Village screen)
		_back_to_village = false
		plot_panel.close()
		placer.move_plot(plot))
	plot_panel.remove_confirmed.connect(func(plot):
		var plot_name: String = plot.plot_name
		placer.plots.remove_plot(plot)
		flash.call("Removed %s. Its pieces stay standing" % plot_name))
	plot_panel.template_requested.connect(save_template)
	pause_menu = PAUSE_MENU_SCENE.instantiate()
	hud.add_child(pause_menu)
	hud.move_child(pause_menu, fade.get_index() + 1)
	# Event banners (see EventBanner): above the HUD
	banner = EventBanner.new()
	hud.add_child(banner)
	hud.move_child(banner, pause_menu.get_index() + 1)
	plot_panel.settlers = settlers
	plot_panel.is_unlocked = is_unlocked
	settler_panel = SettlerPanel.new()
	settler_panel.manager = settlers
	hud.add_child(settler_panel)
	hud.move_child(settler_panel, fade.get_index())
	settler_panel.closed.connect(_after_child_panel)
	# The Village screen (V): a settler's or a plot's panel opened from it comes back to it
	village_screen = VillageScreen.new()
	village_screen.manager = settlers
	village_screen.plots = placer.plots
	hud.add_child(village_screen)
	hud.move_child(village_screen, settler_panel.get_index())
	village_screen.closed.connect(func(): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	village_screen.settler_requested.connect(func(settler):
		_back_to_village = true
		village_screen.hide()
		open_settler_panel(settler))
	village_screen.plot_requested.connect(func(plot):
		_back_to_village = true
		village_screen.hide()
		open_plot_panel(plot))
	plot_panel.village_requested.connect(func():
		_back_to_village = false
		plot_panel.close()
		open_village())


## True while the plot panel, a settler's panel, the Village screen or the note page is open
func any_open() -> bool:
	return note_panel.is_open() or plot_panel.is_open() or settler_panel.is_open() or village_screen.is_open()


## Opens the plot panel (E aimed inside a plot in plot view)
func open_plot_panel(plot: Plot) -> void:
	before_open.call()
	placer.plots.check(plot)
	plot_panel.open(plot, hammer_out.call())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Opens a settler's (or visitor's) panel (E aimed at a settler)
func open_settler_panel(settler: Settler) -> void:
	before_open.call()
	settler_panel.open(settler)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Opens the Village screen (V, or the Village Center's Village button)
func open_village() -> void:
	before_open.call()
	village_screen.open()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Opens a note, journal or log on the parchment page (anything readable)
func read_note(title: String, text: String) -> void:
	before_open.call()
	mark_read.call(title)
	note_panel.open(title, text)


## An event banner: its title in the banner font, and a line beneath (see EventBanner)
func show_banner(title: String, line := "") -> void:
	banner.show_event(title, line)


## Asks a yes/no question on the plot panel; one of the two is called after
func ask_confirm(question: String, on_yes: Callable, on_no: Callable) -> void:
	plot_panel.ask(question, on_yes, on_no)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func open_pause_menu() -> void:
	pause_menu.open()


# A settler's or plot's panel closed: back to the Village screen if it was opened from there,
# otherwise back to looking around
func _after_child_panel() -> void:
	if _back_to_village:
		_back_to_village = false
		open_village()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## The panels' share of the keys: while one is open, it has them all. Returns true if one was open
## (whether or not the key did anything), so nothing else should take the event.
func handle_input(event: InputEvent) -> bool:
	var key: bool = event is InputEventKey and event.pressed and not event.echo
	# The plot panel: E or Esc closes it (or cancels its question), unless you're typing its name
	if plot_panel.is_open():
		if not plot_panel.is_typing() and ((key and event.keycode == KEY_E) or event.is_action_pressed("ui_cancel")):
			get_viewport().set_input_as_handled()
			plot_panel.dismiss()
		return true
	# A settler's panel: E or Esc closes it (or its list of choices)
	if settler_panel.is_open():
		if (key and event.keycode == KEY_E) or event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			settler_panel.dismiss()
		return true
	# The Village screen: E, V or Esc closes it, Q and R switch tabs, and nothing else happens
	if village_screen.is_open():
		if key and event.keycode == KEY_Q:
			village_screen.cycle_tab(-1)
		elif key and event.keycode == KEY_R:
			village_screen.cycle_tab(1)
		elif (key and event.keycode == KEY_E) or event.is_action_pressed("ui_cancel"):
			# (a resource's detail panel goes back to the ledger first)
			get_viewport().set_input_as_handled()
			if not village_screen.back():
				village_screen.close()
		elif key and event.keycode == KEY_V:
			get_viewport().set_input_as_handled()
			village_screen.close()
		return true
	# While reading, E or Esc puts the page away, and nothing else happens
	if note_panel.is_open():
		if (key and event.keycode == KEY_E) or event.is_action_pressed("ui_cancel"):
			note_panel.close()
		return true
	return false
