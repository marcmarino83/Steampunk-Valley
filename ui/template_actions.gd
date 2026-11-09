class_name TemplateActions
extends Control
## Over the build menu's Buildings tab: what you can do with a template (right-click it, or click
## the small ✕ that shows while hovering it). First a choice of Rename or Delete, then a
## confirmation for each: Delete asks "Delete X?"; Rename asks for the new name and does it on
## Rename. The player's own templates can always be changed; built-in ones only in a debug build
## (see BuildingTemplate.can_change). Esc steps back out. Plots and buildings already placed from a
## template aren't affected.

## A template was deleted, or renamed (the build menu reads the templates again)
signal template_deleted(template: BuildingTemplate)
signal template_renamed(template: BuildingTemplate)

const WIDTH := 420.0

var _template: BuildingTemplate
var _choose: Control
var _choose_title: Label
var _choose_note: Label
var _confirm: Control
var _question: Label
var _rename: Control
var _rename_title: Label
var _name: LineEdit
var _rename_problem: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			close())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_choose = _build_choose(center)
	_confirm = _build_confirm(center)
	_rename = _build_rename(center)


# Esc steps back (caught before the name field or the player can take it)
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		back()
		get_viewport().set_input_as_handled()


## True while it's showing (the build menu leaves Esc to it)
func is_open() -> bool:
	return visible


## Shows what can be done with a template
func open(template: BuildingTemplate) -> void:
	_template = template
	_choose_title.text = template.template_name
	var changeable := template.can_change()
	_choose_note.text = ("Built-in template: changes the project's files (debug build)" if template.built_in else "Your template") \
		if changeable else "Built-in templates can't be renamed or deleted"
	for button in _choose.find_children("*", "Button", true, false):
		if button.text != "Cancel":
			(button as Button).disabled = not changeable
	_show(_choose)


func close() -> void:
	_name.release_focus()
	_template = null
	visible = false


## Esc: back from a confirmation to the choice, or closed from the choice
func back() -> void:
	if _choose.get_parent().visible or _template == null:
		close()
	else:
		_show(_choose)


func _show(part: Control) -> void:
	visible = true
	for each in [_choose, _confirm, _rename]:
		each.get_parent().visible = each == part


func _ask_delete() -> void:
	_question.text = "Delete the template %s?\nIts file and picture go for good. Plots and buildings already placed from it stay as they are." % _template.template_name
	_show(_confirm)


func _delete() -> void:
	var template := _template
	var problem := template.delete_files()
	if not problem.is_empty():
		_question.text = problem
		return
	close()
	template_deleted.emit(template)


func _ask_rename() -> void:
	_rename_title.text = "Rename %s" % _template.template_name
	_name.text = _template.template_name
	_rename_problem.text = ""
	_show(_rename)
	_name.grab_focus()
	_name.select_all()


func _do_rename() -> void:
	var wanted := _name.text.strip_edges()
	if wanted == _template.template_name:
		close()
		return
	var template := _template
	var problem := template.rename_to(wanted)
	if not problem.is_empty():
		_rename_problem.text = problem
		return
	close()
	template_renamed.emit(template)


# ---- Building the parts ----

func _build_choose(center: CenterContainer) -> Control:
	var column := _part(center)
	_choose_title = MenuStyle.title("", 22)
	column.add_child(_choose_title)
	_choose_note = _label(14, BrassStyle.TEXT_DIM)
	column.add_child(_choose_note)
	var buttons := _row(column)
	buttons.add_child(_button("Rename", _ask_rename))
	buttons.add_child(_button("Delete", _ask_delete))
	buttons.add_child(_button("Cancel", close))
	return _finish(column)


func _build_confirm(center: CenterContainer) -> Control:
	var column := _part(center)
	_question = _label(17, BrassStyle.TEXT)
	column.add_child(_question)
	var buttons := _row(column)
	var yes := _button("Delete", _delete)
	yes.add_theme_color_override("font_color", BrassStyle.BAD)
	buttons.add_child(yes)
	buttons.add_child(_button("Cancel", back))
	return _finish(column)


func _build_rename(center: CenterContainer) -> Control:
	var column := _part(center)
	_rename_title = MenuStyle.title("", 22)
	column.add_child(_rename_title)
	_name = LineEdit.new()
	_name.max_length = 40
	_name.add_theme_font_size_override("font_size", 17)
	_name.add_theme_color_override("font_color", BrassStyle.TEXT)
	_name.add_theme_color_override("caret_color", BrassStyle.TEXT)
	_name.add_theme_stylebox_override("normal", BrassStyle.frame("slot"))
	_name.add_theme_stylebox_override("focus", BrassStyle.frame("slot_hover"))
	_name.text_submitted.connect(func(_t): _do_rename())
	column.add_child(_name)
	_rename_problem = _label(14, BrassStyle.BAD)
	column.add_child(_rename_problem)
	var buttons := _row(column)
	buttons.add_child(_button("Rename", _do_rename))
	buttons.add_child(_button("Cancel", back))
	column.add_child(MenuStyle.note("[Enter] Rename   [Esc] Back"))
	return _finish(column)


# A brass plaque in the middle, holding a column
func _part(center: CenterContainer) -> VBoxContainer:
	var box := MenuStyle.panel()
	center.add_child(box)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = WIDTH
	column.add_theme_constant_override("separation", 12)
	box.add_child(column)
	return column


# Drawn at menu size (MenuStyle.enlarge puts the plaque in a holder) and hidden until shown.
# Returns the plaque; its parent (the holder) is what shows and hides.
func _finish(column: VBoxContainer) -> Control:
	var box := column.get_parent() as Control
	MenuStyle.enlarge(box)
	box.get_parent().visible = false
	return box


func _row(column: VBoxContainer) -> HBoxContainer:
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(buttons)
	return buttons


func _button(text: String, action: Callable) -> Button:
	var button := MenuStyle.button(text)
	button.custom_minimum_size = Vector2(120, 38)
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(action)
	return button


func _label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
