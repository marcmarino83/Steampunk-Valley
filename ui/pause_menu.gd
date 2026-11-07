extends Control
## Esc, when nothing else is open: pauses the game and offers Resume, Save, Load and Quit.
## It keeps working while everything else is paused. Quit saves first. In a test run (the
## world scene run straight from the editor) Save is greyed out and Quit just closes.

var _save_button: Button
var _load_button: Button
var _quit_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	var column := MenuStyle.screen(self)
	column.add_child(MenuStyle.title("Paused"))
	_add_button(column, "Resume", close)
	_save_button = _add_button(column, "Save", _save)
	_load_button = _add_button(column, "Load", _load)
	_quit_button = _add_button(column, "Quit", _quit)


func _add_button(column: VBoxContainer, text: String, action: Callable) -> Button:
	var b := MenuStyle.button(text)
	b.pressed.connect(action)
	column.add_child(b)
	return b


func open() -> void:
	_load_button.disabled = not SaveGame.has_save()
	_save_button.disabled = not SaveGame.can_save()
	_save_button.text = "Save" if SaveGame.can_save() else "Save (test run)"
	_quit_button.disabled = false
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _save() -> void:
	SaveGame.save_now()
	close()


func _load() -> void:
	SaveGame.world_closed()
	SaveGame.continue_game()


func _quit() -> void:
	_quit_button.disabled = true
	SaveGame.save_and_quit()
