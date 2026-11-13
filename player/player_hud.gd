class_name PlayerHud
extends Node
## The player's heads-up display: the frames-per-second label (F3), the vitals panel, the compass
## and watch with the crosshair, the compact controls row and the prompts under the crosshair
## (HudControls), the plot tracker, and the status line at the top of the screen with its short
## messages and settlement news. A child of the player (see player.gd, which forwards flash()).
## Everything but the status line hides while a menu, a page or sleep covers the view.

## The frames-per-second label, and the HUD's parts (see build)
var fps_label: Label
var vitals: VitalsPanel
var instruments: HudInstruments
var controls: HudControls
var plot_tracker: PlotTracker
## The short message at the top of the screen, and how long it has left
var message := ""
var message_time := 0.0

## What the HUD reads, set by the player: the body (which way you face), what's in your hand,
## what you own, the action bar, the inventory screen (and its crafting tab), the build menu, the
## panels, survival (asleep, warnings), what the crosshair is on, the placer (the hammer's own
## controls), crafting (stations in reach), what you've unlocked, the status line, and the
## dowsing rod (only while the iron tier is on)
var body: Node3D
var held: Callable
var inventory: PlayerInventory
var action_bar: ActionBar
var inventory_screen: Control
var build_menu: Control
var panels: PanelHost
var survival: Survival
var interaction: Interaction
var placer: BuildPlacer
var crafting: PlayerCrafting
var progress: Progress
var status_label: Label
var dowsing: Node


## Makes the HUD's parts and puts them in the HUD where they've always been drawn: the
## frames-per-second label at the end; the vitals panel, the controls row and the plot tracker
## under the menus (just before the inventory screen); the compass and watch just above the
## action bar, so the compass's brass sits on the bar's scrollwork
func build(hud: Node) -> void:
	fps_label = Label.new()
	fps_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT,
			Control.PRESET_MODE_MINSIZE, 16)
	fps_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fps_label.add_theme_font_size_override("font_size", 18)
	fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
	fps_label.add_theme_constant_override("outline_size", 5)
	fps_label.visible = false
	hud.add_child(fps_label)
	vitals = VitalsPanel.new()
	hud.add_child(vitals)
	hud.move_child(vitals, inventory_screen.get_index())
	instruments = HudInstruments.new()
	hud.add_child(instruments)
	hud.move_child(instruments, action_bar.get_index() + 1)
	controls = HudControls.new()
	hud.add_child(controls)
	hud.move_child(controls, inventory_screen.get_index())
	plot_tracker = PlotTracker.new()
	hud.add_child(plot_tracker)
	hud.move_child(plot_tracker, inventory_screen.get_index())


## Shows a short message at the top of the screen
func flash(text: String, seconds := 2.5) -> void:
	message = text
	message_time = seconds


## Settlement news (an arrival, a chest full at dawn, a settler hungry or leaving): shown for a
## while, several at once one under another
func announce(text: String) -> void:
	if message_time > 0.0 and message_time > 3.0 and not message.contains(text):
		message += "\n" + text
		message_time = maxf(message_time, 6.0)
	else:
		flash(text, 6.0)


## F3: the frames-per-second label on or off
func toggle_fps() -> void:
	fps_label.visible = not fps_label.visible


## Each frame, right after survival: the status line shows a recent message, or else warnings
## about anything that's run out (see Survival.warnings)
func update_status(delta: float) -> void:
	message_time -= delta
	if message_time > 0.0:
		status_label.text = message
	else:
		status_label.text = "\n".join(survival.warnings())


## Each frame, last: the frames-per-second label, then the rest of the HUD
func update() -> void:
	if fps_label.visible:
		var triangles := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		fps_label.text = "%d FPS\n%d triangles" % [Engine.get_frames_per_second(), triangles]
	_update_hud()


# The compact on-screen controls (see HudControls): what E and F would do, under the crosshair,
# and a row of the controls that apply right now above the action bar (with the piece's panel
# while building). Hidden while a menu, a page or sleep covers the view.
func _update_hud() -> void:
	var bar := action_bar.rect_on_screen()
	controls.set_bar_top(bar.position.y)
	# The compass needle points the way you face (north is -Z); the watch shows the sun's clock
	var facing := -body.global_basis.z
	var sun = get_tree().get_first_node_in_group("sun")
	instruments.update_instruments(atan2(facing.x, -facing.z), sun.time_of_day if sun else 0.5,
			action_bar.first_slot_rect(), bar.end.y, controls.row_rect())
	var covered: bool = panels.any_open() or survival.sleeping or inventory_screen.visible \
			or build_menu.visible
	instruments.show_crosshair(not covered)
	plot_tracker.show_plot(null if covered else interaction.tracked_plot())
	if covered:
		controls.set_prompts([])
		controls.set_controls([])
		controls.set_info({})
		return
	controls.set_prompts(interaction.prompts())

	# Eating isn't aimed at anything, so it goes in the controls row, not under the crosshair
	var items := inventory.items
	var eat := [["Eat Berries", "F"]] if items.get("Berries", 0) > 0 else []
	var held_item: String = held.call()
	if held_item == "Hammer":
		var state: Dictionary = placer.hud_state()
		controls.set_controls(state["controls"] + eat)
		controls.set_info(state["info"])
		return
	var shown := []
	if dowsing and held_item == "Dowsing Rod":
		shown.append(["Dowse for ore", "R"])
	if not held_item.is_empty():
		shown.append(["Drop %s" % held_item, "G"])
	var stations := crafting.nearby_stations()
	if inventory_screen.crafting.anything_craftable(items, stations, progress.is_unlocked):
		shown.append(["Craft something", "I"])
	else:
		for item in items:
			if ToolItem.exists_for(item) and not action_bar.has_item(item):
				shown.append(["Put tools on the bar", "I"])
				break
	controls.set_controls(shown + eat)
	controls.set_info({})
