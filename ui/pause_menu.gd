extends Control
## Esc, when nothing else is open: pauses the game and offers Resume, Save, Load, Settings (the
## same panel as the title screen's, see SettingsPanel) and Quit.
## Save opens this world's save slots, Load lists every save. It keeps working while everything
## else is paused. Quit autosaves first. In a test run (the world scene run straight from the
## editor) Save is greyed out and Quit just closes.

var _save_button: Button
var _load_button: Button
var _quit_button: Button
var _list: SaveList
var _settings: SettingsPanel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	var column := MenuStyle.screen(self)
	column.add_child(MenuStyle.title("Paused"))
	_add_button(column, "Resume", close)
	_save_button = _add_button(column, "Save", func(): _list.open("save"))
	_load_button = _add_button(column, "Load", func(): _list.open("load"))
	_add_button(column, "Settings", func(): _settings.open())
	_quit_button = _add_button(column, "Quit", _quit)
	_list = SaveList.new()
	add_child(_list)
	# The same settings panel as the title screen's
	_settings = SettingsPanel.new()
	add_child(_settings)
	# Saving goes straight back to the game, as Save always has
	_list.closed.connect(func(saved): if saved: close())
	_list.changed.connect(_update_buttons)


func _add_button(column: VBoxContainer, text: String, action: Callable) -> Button:
	var b := MenuStyle.button(text)
	b.pressed.connect(action)
	column.add_child(b)
	return b


func open() -> void:
	# A picture of the game for any save made from here, taken before the menu covers it
	SaveGame.take_snapshot()
	_update_buttons()
	_quit_button.disabled = false
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	_list.visible = false
	_settings.close()
	visible = false
	SaveGame.clear_snapshot()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _update_buttons() -> void:
	_load_button.disabled = not SaveGame.has_save()
	_save_button.disabled = not SaveGame.can_save()
	_save_button.text = "Save" if SaveGame.can_save() else "Save (test run)"


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel") and not _settings.is_open():
		get_viewport().set_input_as_handled()
		close()


func _quit() -> void:
	_quit_button.disabled = true
	SaveGame.save_and_quit()
