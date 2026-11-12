extends Control
## The title screen: the painting (see TitleBackground) with a soft dark gradient on the left
## behind a narrow menu panel in the ornate frame, against the left edge and clear of the refugee.
##
## "Steampunk Valley" at the top, then Continue (the most recent save of any world; greyed out if
## there are none, with what it would load shown small beneath), Load Game (every save, grouped by
## world), New Game (a fresh world with saves of its own), Multiplayer (not yet: "Coming soon" on
## hover), Settings (see SettingsPanel) and Quit Game (asks first). Mouse, keyboard and controller
## all work: Up/Down move, Enter picks, Esc backs out (or asks to quit). The game's version is in
## the bottom-right corner.

## The menu panel (pixels at 1920 x 1080): its gap to the screen's left edge, its width, its gap to
## the top and bottom, and the room kept between it and the refugee
const PANEL_LEFT := 36.0
const PANEL_WIDTH := 440.0
const PANEL_TOP := 54.0
const PANEL_BOTTOM := 54.0
const REFUGEE_ROOM := 40.0
const BUTTON_SIZE := Vector2(330, 58)
const BUTTON_FONT := 24
## The logo's size, made smaller if its widest word is wider than this (the buttons' width and a little)
const LOGO_SIZE := 52
const LOGO_WIDTH := 350.0
## How the lit button (hovered or focused) is tinted: warmer and brighter
const HIGHLIGHT := Color(1.55, 1.3, 0.95)
## The dark gradient behind the menu: how far it reaches across the screen, and how dark it starts
const SHADE_WIDTH := 780.0
const SHADE_ALPHA := 0.72

var _background: TitleBackground
var _buttons: VBoxContainer
var _confirm: VBoxContainer
var _continue: Button
var _continue_info: Label
var _load: Button
var _new: Button
var _multiplayer: Button
var _list: SaveList
var _settings: SettingsPanel


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameSettings.ensure_loaded()
	# While working on the game: quietly redraw any build icon whose piece has changed
	IconUpdater.start(get_tree())
	_background = TitleBackground.new()
	add_child(_background)
	_background.keep_clear = PANEL_LEFT + PANEL_WIDTH + REFUGEE_ROOM
	add_child(_left_shade())

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", BrassStyle.frame("title"))
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = PANEL_LEFT
	panel.offset_right = PANEL_LEFT + PANEL_WIDTH
	panel.offset_top = PANEL_TOP
	panel.offset_bottom = -PANEL_BOTTOM
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	panel.add_child(column)
	# The logo: Cinzel Decorative Black (see BrassStyle's fonts), a word to a line, as big as fits the
	# panel (it's wide: a word is never broken)
	var title := MenuStyle.title("Steampunk\nValley", LOGO_SIZE)
	title.add_theme_font_override("font", BrassStyle.logo_font())
	var logo_font: Font = BrassStyle.logo_font()
	if logo_font:
		var widest: float = logo_font.get_string_size("STEAMPUNK", HORIZONTAL_ALIGNMENT_LEFT, -1, LOGO_SIZE).x
		if widest > LOGO_WIDTH:
			title.add_theme_font_size_override("font_size", floori(LOGO_SIZE * LOGO_WIDTH / widest))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 3)
	column.add_child(title)
	column.add_child(_gap(28))

	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 14)
	_buttons.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.add_child(_buttons)
	_continue = _button("Continue", SaveGame.continue_game)
	_continue_info = MenuStyle.note("")
	_continue_info.add_theme_font_size_override("font_size", 14)
	_continue_info.custom_minimum_size.x = BUTTON_SIZE.x
	_buttons.add_child(_continue_info)
	_buttons.move_child(_continue_info, _continue.get_parent().get_index() + 1)
	_load = _button("Load Game", func(): _list.open("load"))
	_new = _button("New Game", SaveGame.new_game)
	_multiplayer = _button("Multiplayer", func(): pass)
	_multiplayer.disabled = true
	_multiplayer.focus_mode = Control.FOCUS_NONE
	_multiplayer.mouse_entered.connect(func(): _multiplayer.text = "Coming soon")
	_multiplayer.mouse_exited.connect(func(): _multiplayer.text = "Multiplayer")
	_button("Settings", _open_settings)
	_button("Quit Game", _ask_quit)

	# Quit Game asks first
	_confirm = VBoxContainer.new()
	_confirm.add_theme_constant_override("separation", 14)
	_confirm.visible = false
	column.add_child(_confirm)
	var question := MenuStyle.title("Quit the game?", 26)
	_confirm.add_child(question)
	var yes := _make_button("Yes", get_tree().quit)
	_confirm.add_child(_centered(yes))
	var no := _make_button("No", _cancel_quit)
	_confirm.add_child(_centered(no))

	column.add_child(_gap(10, true))
	column.add_child(MenuStyle.note("[Up/Down] Choose  ·  [Enter] Pick"))

	var version := Label.new()
	version.text = "v%s" % str(ProjectSettings.get_setting("application/config/version", "0.1"))
	version.add_theme_font_size_override("font_size", 15)
	version.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7, 0.7))
	version.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(version)

	_list = SaveList.new()
	add_child(_list)
	_list.changed.connect(_update)
	_list.closed.connect(func(_saved): _focus_first())
	_settings = SettingsPanel.new()
	add_child(_settings)
	_settings.closed.connect(_focus_first)
	_update()
	_focus_first.call_deferred()


# What Continue would load (kept up to date as saves are deleted)
func _update() -> void:
	var newest := SaveGame.newest_save()
	var none := newest.is_empty()
	_continue.disabled = none
	_continue.focus_mode = Control.FOCUS_NONE if none else Control.FOCUS_ALL
	_load.disabled = none
	_load.focus_mode = Control.FOCUS_NONE if none else Control.FOCUS_ALL
	if none:
		_continue_info.text = "No saved games yet"
	else:
		_continue_info.text = "%s  ·  Day %d\n%s, %s" % [newest["world_name"], newest["day"], "Manual save" if newest["kind"] == "manual" else "Autosave", newest["saved_text"]]


# Keyboard and controller: the first button that can be picked takes focus
func _focus_first() -> void:
	for button in [_continue, _load, _new]:
		if not button.disabled:
			button.grab_focus()
			return


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or _settings.is_open() or _list.visible:
		return
	get_viewport().set_input_as_handled()
	if _confirm.visible:
		_cancel_quit()
	else:
		_ask_quit()


func _open_settings() -> void:
	_settings.open()


func _ask_quit() -> void:
	_buttons.visible = false
	_confirm.visible = true
	(_confirm.get_child(2).get_child(0) as Button).grab_focus()


func _cancel_quit() -> void:
	_confirm.visible = false
	_buttons.visible = true
	_focus_first()


# ---- Building it ----

# A menu button in the column, in the brass style, lit while hovered or focused
func _button(text: String, action: Callable) -> Button:
	var button := _make_button(text, action)
	_buttons.add_child(_centered(button))
	return button


func _make_button(text: String, action: Callable) -> Button:
	var button := MenuStyle.button(text)
	button.custom_minimum_size = BUTTON_SIZE
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", BUTTON_FONT)
	button.add_theme_stylebox_override("focus", BrassStyle.frame("button_hover"))
	button.add_theme_color_override("font_focus_color", BrassStyle.TEXT)
	button.pressed.connect(action)
	# The mouse moving onto a button gives it the keyboard focus too, so only one is ever lit
	button.mouse_entered.connect(func(): if not button.disabled and button.focus_mode != Control.FOCUS_NONE: button.grab_focus())
	# The lit one glows warmer and brighter, its text gold
	button.focus_entered.connect(func():
		button.self_modulate = HIGHLIGHT
		button.add_theme_color_override("font_focus_color", BrassStyle.HEADING.lightened(0.15)))
	button.focus_exited.connect(func(): button.self_modulate = Color.WHITE)
	return button


func _centered(control: Control) -> CenterContainer:
	var center := CenterContainer.new()
	center.add_child(control)
	return center


func _gap(height: float, expand := false) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size.y = height
	if expand:
		gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return gap


# The soft dark gradient down the left edge, behind the menu
func _left_shade() -> TextureRect:
	var fade := Gradient.new()
	fade.set_color(0, Color(0.02, 0.02, 0.03, SHADE_ALPHA))
	fade.set_color(1, Color(0.02, 0.02, 0.03, 0.0))
	fade.add_point(0.45, Color(0.02, 0.02, 0.03, SHADE_ALPHA * 0.75))
	var texture := GradientTexture2D.new()
	texture.gradient = fade
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(1, 0)
	texture.width = 256
	texture.height = 4
	var shade := TextureRect.new()
	shade.texture = texture
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.anchor_bottom = 1.0
	shade.offset_right = SHADE_WIDTH
	return shade
