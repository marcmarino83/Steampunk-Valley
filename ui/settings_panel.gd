class_name SettingsPanel
extends Control
## The settings, over whatever's behind (the title screen, or the paused game): the ornate frame
## with Audio (master, music and effects volume), Display (window mode, resolution, V-Sync, render
## scale) and
## Controls (mouse sensitivity, invert Y, field of view). Every change applies at once and is saved
## (see GameSettings). Back or Esc closes it. Works while the game is paused.

signal closed

const WIDTH := 640.0
const FONT_SIZE := 20
const LABEL_WIDTH := 230.0

var _first: Control
var _resolution: OptionButton
var _resolutions: Array = []
var _value_labels := {}
# A slider moved since the settings were last saved
var _unsaved := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	GameSettings.ensure_loaded()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", BrassStyle.frame("title"))
	center.add_child(box)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = WIDTH
	column.add_theme_constant_override("separation", 10)
	box.add_child(column)
	column.add_child(MenuStyle.title("Settings", 38))

	column.add_child(_heading("Audio"))
	_first = _slider_row(column, "Master volume", "master", 0, 100, 1, "%d%%")
	_slider_row(column, "Music volume", "music", 0, 100, 1, "%d%%")
	_slider_row(column, "Effects volume", "effects", 0, 100, 1, "%d%%")

	column.add_child(_heading("Display"))
	var mode := _option_row(column, "Window mode", ["Windowed", "Fullscreen", "Borderless"], GameSettings.WINDOW_MODES.find(GameSettings.window_mode))
	mode.item_selected.connect(func(i):
		GameSettings.window_mode = GameSettings.WINDOW_MODES[i]
		GameSettings.apply_display()
		_resolution.disabled = GameSettings.window_mode != "windowed"
		GameSettings.save())
	_resolutions = GameSettings.resolutions_that_fit()
	var names := []
	var current := -1
	var window_size := DisplayServer.window_get_size() if DisplayServer.get_name() != "headless" else Vector2i.ZERO
	for i in _resolutions.size():
		var r: Vector2i = _resolutions[i]
		names.append("%d × %d" % [r.x, r.y])
		if r == GameSettings.resolution or (GameSettings.resolution == Vector2i.ZERO and r == window_size):
			current = i
	_resolution = _option_row(column, "Resolution", names, current)
	_resolution.disabled = GameSettings.window_mode != "windowed"
	_resolution.tooltip_text = "The window's size in windowed mode"
	_resolution.item_selected.connect(func(i):
		GameSettings.resolution = _resolutions[i]
		GameSettings.apply_display()
		GameSettings.save())
	var vsync := _check_row(column, "V-Sync", GameSettings.vsync)
	vsync.toggled.connect(func(on):
		GameSettings.vsync = on
		GameSettings.apply_display()
		GameSettings.save())
	var render_slider := _slider_row(column, "Render scale", "render_scale", 50, 100, 5, "%d%%")
	render_slider.tooltip_text = "Draws the world at this share of the resolution, sharpened back up with AMD FSR.\nLower is faster; the HUD stays sharp."

	column.add_child(_heading("Controls"))
	_slider_row(column, "Mouse sensitivity", "mouse_sensitivity", 0.2, 3.0, 0.05, "%.2f×")
	var invert := _check_row(column, "Invert Y", GameSettings.invert_y)
	invert.toggled.connect(func(on):
		GameSettings.invert_y = on
		GameSettings.save())
	_slider_row(column, "Field of view", "fov", 60, 100, 1, "%d°")

	# Debug builds only: the lag spike logger (see SpikeLog)
	if OS.is_debug_build():
		column.add_child(_heading("Debug"))
		var spikes := _check_row(column, "Log lag spikes", GameSettings.spike_log)
		spikes.tooltip_text = "Writes a line to the output for every frame slower than 33 ms:\nwhat you were doing and the time each system took"
		spikes.toggled.connect(func(on):
			GameSettings.spike_log = on
			SpikeLog.enabled = on
			GameSettings.save())

	var back := MenuStyle.button("Back")
	back.focus_mode = Control.FOCUS_ALL
	back.custom_minimum_size = Vector2(220, 50)
	back.add_theme_font_size_override("font_size", 22)
	back.add_theme_stylebox_override("focus", BrassStyle.frame("button_hover"))
	back.pressed.connect(close)
	var back_row := HBoxContainer.new()
	back_row.alignment = BoxContainer.ALIGNMENT_CENTER
	back_row.add_child(back)
	column.add_child(back_row)
	column.add_child(MenuStyle.note("Changes apply straight away  ·  [Esc] Back"))


func open() -> void:
	visible = true
	_first.grab_focus()


func close() -> void:
	if not visible:
		return
	_save_if_changed()
	visible = false
	closed.emit()


func _save_if_changed() -> void:
	if _unsaved:
		_unsaved = false
		GameSettings.save()


func is_open() -> bool:
	return visible


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


# ---- Rows ----

func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", MenuStyle.TEXT)
	return label


func _row(column: VBoxContainer, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = LABEL_WIDTH
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", BrassStyle.TEXT)
	row.add_child(label)
	column.add_child(row)
	return row


func _slider_row(column: VBoxContainer, text: String, key: String, low: float, high: float, step: float, value_format: String) -> HSlider:
	var row := _row(column, text)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size.y = 26
	slider.focus_mode = Control.FOCUS_ALL
	BrassStyle.style_slider(slider)
	slider.value = GameSettings.value_of(key)
	row.add_child(slider)
	var shown := Label.new()
	shown.custom_minimum_size.x = 80
	shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	shown.add_theme_font_size_override("font_size", FONT_SIZE)
	shown.add_theme_color_override("font_color", BrassStyle.TEXT_DIM)
	shown.text = value_format % slider.value
	row.add_child(shown)
	_value_labels[key] = shown
	slider.value_changed.connect(func(v):
		GameSettings.set_value(key, v)
		shown.text = value_format % v
		_unsaved = true)
	# Saved once the slider's let go of (or it loses focus after keys moved it), not every step
	slider.drag_ended.connect(func(_changed): _save_if_changed())
	slider.focus_exited.connect(_save_if_changed)
	return slider


func _option_row(column: VBoxContainer, text: String, items: Array, selected: int) -> OptionButton:
	var row := _row(column, text)
	var option := OptionButton.new()
	for item in items:
		option.add_item(item)
	if selected >= 0:
		option.select(selected)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.focus_mode = Control.FOCUS_ALL
	option.add_theme_font_size_override("font_size", FONT_SIZE)
	BrassStyle.style_button(option)
	option.add_theme_stylebox_override("focus", BrassStyle.frame("button_hover"))
	option.get_popup().add_theme_font_size_override("font_size", FONT_SIZE)
	row.add_child(option)
	return option


func _check_row(column: VBoxContainer, text: String, on: bool) -> CheckButton:
	var row := _row(column, text)
	var check := CheckButton.new()
	check.button_pressed = on
	check.focus_mode = Control.FOCUS_ALL
	check.add_theme_stylebox_override("focus", BrassStyle.frame("button_hover"))
	row.add_child(check)
	return check
