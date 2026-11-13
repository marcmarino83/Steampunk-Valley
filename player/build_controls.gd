class_name BuildControls
extends Node
## The hammer's controls around the build placer: the build menu (Tab), what was being placed put
## aside while it's open and taken up again when it closes, the hammer's clicks (building ghosts,
## demolishing, dragging a plot's edge), the mouse wheel while placing, and plot view (P). A child
## of the player (see player.gd, which forwards its old functions here). The player hands it input
## at the points it always handled it, so the order keys are taken in doesn't change.

## The placer, the build menu, the inventory screen, the panels, survival (asleep or not), whether
## the hammer is in hand, and a short message. Set by the player before setup().
var placer: BuildPlacer
var build_menu: Control
var inventory_screen: Control
var panels: PanelHost
var survival: Survival
var hammer_out: Callable
var flash: Callable

# What was being placed when the build menu opened, to go back to if nothing else is picked
var _build_resume: Buildable
# Plot view switched on with P (it only shows with the hammer out)
var _plot_view := false


## Listens to the build menu: a pick starts placing it; a template deleted while it was put aside
## isn't brought back when the menu closes
func setup() -> void:
	build_menu.chosen.connect(_on_buildable_chosen)
	build_menu.template_deleted.connect(func(template: BuildingTemplate):
		var resume := _build_resume as TemplateBuildable
		if resume and resume.template == template:
			_build_resume = null)


## Each frame, with the hammer out: the piece that would come down glows red while the middle
## button (or X) is held; the ghost under the crosshair lights up, and holding left-click keeps
## building ghosts; plot view follows P, the build menu's Buildings tab and a plot being drawn,
## moved or resized
func update(delta: float) -> void:
	placer.update_demolish(delta, can_demolish(), Input.is_key_pressed(KEY_X))
	placer.update_ghosts(delta, can_demolish())
	placer.update_plot_view(plot_view_on())


## True when the hammer is out and nothing else is in the way (no menu, page or sleep), so
## demolishing works. (A settler's panel doesn't stop it: it was never in this list.)
func can_demolish() -> bool:
	return hammer_out.call() and not survival.sleeping and not panels.note_panel.is_open() \
			and not panels.plot_panel.is_open() and not panels.village_screen.is_open() \
			and not placer.is_plot_mode() and not inventory_screen.visible \
			and not build_menu.visible and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## True while plot view shows: the hammer is out, and P has switched it on, or the build menu's
## Buildings tab is open, or a plot is being drawn, moved or resized
func plot_view_on() -> bool:
	if not hammer_out.call():
		return false
	var buildings_tab: bool = build_menu.visible and build_menu.current_tab_name() == "Buildings"
	return _plot_view or buildings_tab or placer.is_plot_mode()


## P: plot view on or off (it shows with the hammer out)
func toggle_plot_view() -> void:
	if hammer_out.call():
		_plot_view = not _plot_view
		flash.call("Plot view on" if _plot_view else "Plot view off")
	else:
		flash.call("Equip a hammer to see your plots")


## Opens the build menu. While placing something, what you were placing is put aside: picking
## something else switches to it (keeping the height and turn), closing the menu goes back to it.
func open_build_menu() -> void:
	if inventory_screen.visible:
		return
	if not hammer_out.call():
		flash.call("Equip a hammer to build")
		return
	if placer.is_placing():
		_build_resume = placer.current_buildable()
		# Moving or resizing a plot: finish that first
		if _build_resume == null:
			return
		placer.cancel()
	var timing := SpikeLog.begin()
	build_menu.show()
	SpikeLog.end("build menu opened", timing)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Closes the build menu without picking anything: back to whatever was being placed
func close_build_menu() -> void:
	build_menu.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _build_resume:
		var resume := _build_resume
		_build_resume = null
		placer.begin(resume, true)


func _on_buildable_chosen(buildable: Buildable) -> void:
	var switching := _build_resume != null
	_build_resume = null
	close_build_menu()
	placer.begin(buildable, switching)


## While the build menu is open, Q and R change tab, E, Tab or Esc closes it, and nothing else
## happens (E only ever closes panels and interacts). Returns true while it's open.
func menu_input(event: InputEvent) -> bool:
	if not build_menu.visible:
		return false
	# A template's Rename / Delete is showing: it has the keys (Esc steps back out of it)
	if build_menu.template_actions_open():
		return true
	var key: bool = event is InputEventKey and event.pressed and not event.echo
	if key and event.keycode == KEY_Q:
		build_menu.cycle_tab(-1)
	elif key and event.keycode == KEY_R:
		build_menu.cycle_tab(1)
	elif (key and event.keycode in [KEY_E, KEY_TAB]) or event.is_action_pressed("ui_cancel"):
		close_build_menu()
	return true


## The hammer's clicks, and whatever's being placed: true if the event was taken
func hammer_input(event: InputEvent) -> bool:
	var button := event as InputEventMouseButton
	# Placing or not: holding the middle button picks the piece under the crosshair (it glows red),
	# and letting go takes it down
	if button and button.button_index == MOUSE_BUTTON_MIDDLE:
		if button.pressed and can_demolish():
			placer.press_demolish()
		elif not button.pressed:
			placer.release_demolish(can_demolish())
		return true
	# Letting go of left-click stops building ghosts
	if button and button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
		placer.release_ghost()
	# Nothing being placed: left-click on a ghost builds it (holding keeps building); in plot view,
	# on a plot's edge or corner it starts dragging the edge
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if hammer_out.call() and not placer.is_placing() and button and button.pressed \
			and button.button_index == MOUSE_BUTTON_LEFT and captured:
		if placer.press_ghost():
			return true
		if plot_view_on() and placer.try_grab_plot():
			return true
	# While placing, clicks, R and Esc belong to that
	return placer.is_placing() and placer.handle_input(event)


## While placing with the mouse captured (no cursor showing), the mouse wheel turns, tilts and tips
## what's being placed. Taken before any part of the screen can catch it: a panel under where the
## hidden cursor rests would otherwise swallow the scroll. `blocked`: asleep, or typing in the
## console.
func wheel_input(event: InputEvent, blocked: bool) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	var wheel := [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
	if not button.button_index in wheel:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or blocked or not placer.is_placing():
		return
	if build_menu.visible or inventory_screen.visible or panels.any_open():
		return
	if placer.handle_input(event):
		get_viewport().set_input_as_handled()
