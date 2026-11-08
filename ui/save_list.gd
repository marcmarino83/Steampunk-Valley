class_name SaveList
extends Control
## The list of saved games, on top of the title screen or the pause menu, in one of two modes:
##   "load": every save, grouped by world (the world played most recently first), newest first
##           within each. Each can be loaded or deleted (after asking).
##   "save": this world's manual saves, to overwrite (after asking), and a box to name a new one.
## Each save shows its picture, name, whether it's manual or an autosave, the in-game day, the
## time played, and when it was saved.

## Emitted when the list closes, and whether a save was just made from it
signal closed(saved: bool)
## Emitted after a save is deleted, so the screen behind can update
signal changed

const ROW_COLOR := Color(0.2, 0.16, 0.12)
const ROW_BORDER := Color(0.45, 0.28, 0.16)
const THUMB_SIZE := Vector2(160, 90)

var _mode := "load"
var _title: Label
var _name_row: HBoxContainer
var _name_edit: LineEdit
var _empty_note: Label
var _rows: VBoxContainer
var _confirm: Control
var _confirm_text: Label
var _confirm_yes: Button
var _confirm_action: Callable


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


func _ready() -> void:
	var column := MenuStyle.screen(self, 0.6)
	column.custom_minimum_size = Vector2(820, 560)
	_title = MenuStyle.title("", 26)
	column.add_child(_title)

	# Save mode: name the new save (or leave it for the default name)
	_name_row = HBoxContainer.new()
	_name_row.add_theme_constant_override("separation", 10)
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.max_length = 48
	_name_edit.add_theme_font_size_override("font_size", 17)
	_name_edit.text_submitted.connect(func(_t): _save_new())
	_name_row.add_child(_name_edit)
	var new_slot := MenuStyle.button("Save to New Slot")
	new_slot.pressed.connect(_save_new)
	_name_row.add_child(new_slot)
	column.add_child(_name_row)

	_empty_note = MenuStyle.note("")
	column.add_child(_empty_note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 8)
	scroll.add_child(_rows)

	var back := MenuStyle.button("Back")
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(close)
	column.add_child(back)

	# Asked before overwriting or deleting, on top of the list
	_confirm = Control.new()
	_confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm.visible = false
	add_child(_confirm)
	var ask := MenuStyle.screen(_confirm, 0.5)
	_confirm_text = MenuStyle.title("", 22)
	_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_text.custom_minimum_size.x = 420
	ask.add_child(_confirm_text)
	_confirm_yes = MenuStyle.button("")
	_confirm_yes.pressed.connect(func():
		_confirm.visible = false
		_confirm_action.call())
	ask.add_child(_confirm_yes)
	var cancel := MenuStyle.button("Cancel")
	cancel.pressed.connect(func(): _confirm.visible = false)
	ask.add_child(cancel)


## Shows the list: "load" or "save"
func open(mode: String) -> void:
	_mode = mode
	_name_edit.text = ""
	_confirm.visible = false
	_fill()
	visible = true
	if mode == "save":
		_name_edit.grab_focus()


func close(saved := false) -> void:
	_name_edit.release_focus()
	visible = false
	closed.emit(saved)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _confirm.visible:
			_confirm.visible = false
		else:
			close()


func _fill() -> void:
	for child in _rows.get_children():
		child.queue_free()
	var saves: Array[Dictionary]
	if _mode == "save":
		var world := SaveGame.current_world()
		saves.assign(SaveGame.saves_in(world).filter(func(s): return s["kind"] == "manual"))
		_title.text = "Save Game"
		_name_edit.placeholder_text = "Name (optional) – otherwise \"Day %d – date and time\"" % _day_now()
		_empty_note.text = "No saved slots in this world yet." if saves.is_empty() else "Or overwrite one of this world's saves:"
	else:
		saves = SaveGame.list_saves()
		_title.text = "Load Game"
		_empty_note.text = "No saved games." if saves.is_empty() else ""
	_name_row.visible = _mode == "save"
	_empty_note.visible = not _empty_note.text.is_empty()

	if _mode == "save":
		for save in saves:
			_rows.add_child(_row(save))
		return
	# Grouped by world, in the order each world was last saved
	var worlds: Array[String] = []
	for save in saves:
		if not worlds.has(save["world_id"]):
			worlds.append(save["world_id"])
	for world in worlds:
		var in_world := saves.filter(func(s): return s["world_id"] == world)
		var header := MenuStyle.title(in_world[0]["world_name"], 19)
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_rows.add_child(header)
		for save in in_world:
			_rows.add_child(_row(save))


func _row(save: Dictionary) -> PanelContainer:
	var row := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = ROW_COLOR
	style.border_color = ROW_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	row.add_theme_stylebox_override("panel", style)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	row.add_child(line)

	var picture := TextureRect.new()
	picture.custom_minimum_size = THUMB_SIZE
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var image := Image.load_from_file(save["thumbnail"]) if not save["thumbnail"].is_empty() else null
	if image:
		picture.texture = ImageTexture.create_from_image(image)
	else:
		var blank := ColorRect.new()
		blank.color = Color(0.08, 0.06, 0.05)
		blank.set_anchors_preset(Control.PRESET_FULL_RECT)
		picture.add_child(blank)
	line.add_child(picture)

	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	var title := Label.new()
	title.text = save["name"]
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", MenuStyle.TEXT)
	words.add_child(title)
	var kind := Label.new()
	kind.text = "Manual save" if save["kind"] == "manual" else "Autosave"
	kind.add_theme_font_size_override("font_size", 14)
	kind.add_theme_color_override("font_color", Color(0.98, 0.78, 0.32) if save["kind"] == "manual" else Color(0.6, 0.75, 0.85))
	words.add_child(kind)
	var details := Label.new()
	details.text = "Day %d  ·  Played %s  ·  Saved %s" % [save["day"], SaveGame.play_time_text(save["play_seconds"]), save["saved_text"]]
	details.add_theme_font_size_override("font_size", 14)
	details.add_theme_color_override("font_color", MenuStyle.TEXT_DIM)
	words.add_child(details)
	line.add_child(words)

	var buttons := VBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	var path: String = save["path"]
	if _mode == "save":
		var overwrite := func(): _save_over(path)
		buttons.add_child(_small_button("Overwrite", _ask.bind("Overwrite \"%s\"?" % save["name"], "Overwrite", overwrite)))
	else:
		var remove := func(): _delete(path)
		buttons.add_child(_small_button("Load", SaveGame.load_save.bind(path)))
		buttons.add_child(_small_button("Delete", _ask.bind("Delete \"%s\"? This can't be undone." % save["name"], "Delete", remove)))
	line.add_child(buttons)
	return row


func _small_button(text: String, action: Callable) -> Button:
	var b := MenuStyle.button(text)
	b.custom_minimum_size = Vector2(120, 36)
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(action)
	return b


func _ask(question: String, yes_text: String, action: Callable) -> void:
	_confirm_text.text = question
	_confirm_yes.text = yes_text
	_confirm_action = action
	_confirm.visible = true


func _save_new() -> void:
	SaveGame.save_manual(_name_edit.text)
	close(true)


func _save_over(path: String) -> void:
	SaveGame.save_manual(_name_edit.text, path)
	close(true)


func _delete(path: String) -> void:
	SaveGame.delete_save(path)
	_fill()
	changed.emit()


func _day_now() -> int:
	var sun = get_tree().get_first_node_in_group("sun")
	return int(sun.day) + 1 if sun else 1
