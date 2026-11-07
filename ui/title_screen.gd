extends Control
## The first thing you see. With no save, it goes straight into a new game. With one, it offers
## Continue or New Game; New Game asks before starting over, since the next save replaces the old.

var _confirm_layer: Control


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
	var when := SaveGame.saved_when()
	if not when.is_empty():
		choices.add_child(MenuStyle.note("Last saved %s" % when))
	var go_on := MenuStyle.button("Continue")
	go_on.pressed.connect(SaveGame.continue_game)
	choices.add_child(go_on)
	var fresh := MenuStyle.button("New Game")
	fresh.pressed.connect(func(): _confirm_layer.visible = true)
	choices.add_child(fresh)

	# Asked before starting over, on top of everything else
	_confirm_layer = Control.new()
	_confirm_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.visible = false
	add_child(_confirm_layer)
	var confirm := MenuStyle.screen(_confirm_layer, 0.6)
	confirm.add_child(MenuStyle.title("Start a new game?", 24))
	confirm.add_child(MenuStyle.note("Your saved game will be replaced the next time the game saves."))
	var yes := MenuStyle.button("Start New Game")
	yes.pressed.connect(SaveGame.new_game)
	confirm.add_child(yes)
	var no := MenuStyle.button("Back")
	no.pressed.connect(func(): _confirm_layer.visible = false)
	confirm.add_child(no)
