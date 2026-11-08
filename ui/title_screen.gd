extends Control
## The first thing you see. With no saves at all, it goes straight into a new game. Otherwise it
## offers Continue (the most recent save of any world), New Game (a fresh world with saves of
## its own; other worlds are left alone) and Load Game (every save, grouped by world).

var _latest: Label
var _continue: Button
var _load: Button
var _list: SaveList


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not SaveGame.has_save():
		SaveGame.new_game.call_deferred()
		return
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.06, 0.05, 0.04)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var choices := MenuStyle.screen(self, 0.0)
	choices.add_child(MenuStyle.title("Steampunk Valley", 34))
	_latest = MenuStyle.note("")
	_latest.custom_minimum_size.x = 300
	choices.add_child(_latest)
	_continue = MenuStyle.button("Continue")
	_continue.pressed.connect(SaveGame.continue_game)
	choices.add_child(_continue)
	var fresh := MenuStyle.button("New Game")
	fresh.pressed.connect(SaveGame.new_game)
	choices.add_child(fresh)
	_load = MenuStyle.button("Load Game")
	_load.pressed.connect(func(): _list.open("load"))
	choices.add_child(_load)

	_list = SaveList.new()
	add_child(_list)
	_list.changed.connect(_update)
	_update()


# What Continue would load, kept up to date as saves are deleted
func _update() -> void:
	var newest := SaveGame.newest_save()
	_continue.disabled = newest.is_empty()
	_load.disabled = newest.is_empty()
	if newest.is_empty():
		_latest.text = "No saved games"
	else:
		_latest.text = "Latest: %s\n%s, %s" % [newest["name"], newest["world_name"], "manual save" if newest["kind"] == "manual" else "autosave"]
