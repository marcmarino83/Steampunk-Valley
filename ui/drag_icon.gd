class_name DragIcon
extends CanvasLayer
## The picture that follows the mouse while an item is dragged. Godot's own drag preview is drawn
## on the bottom layer, under the HUD and the menus, so this draws it on a layer of its own above
## everything: centred on the mouse, a little see-through, and never in the way of the drop (the
## mouse goes straight through it). The slot it came from shows dimmed until the drag ends.

## Above every menu and the HUD
const LAYER := 128
## How see-through the dragged picture is, and how dim the slot it came from goes meanwhile
const PICTURE_ALPHA := 0.75
const SOURCE_ALPHA := 0.4

# The drag in progress, if any
static var _current: DragIcon

var _picture: Control
var _source: Control
var _source_alpha := 1.0


## Starts showing `picture` at the mouse, dragged out of `source`. A slot calls this from
## _get_drag_data, and stop() when it's told the drag has ended.
static func start(source: Control, picture: Control) -> void:
	stop()
	var shown := DragIcon.new()
	shown.layer = LAYER
	shown.process_mode = Node.PROCESS_MODE_ALWAYS
	shown._picture = picture
	shown._source = source
	shown._source_alpha = source.modulate.a
	picture.modulate.a = PICTURE_ALPHA
	_let_mouse_through(picture)
	shown.add_child(picture)
	source.get_tree().root.add_child(shown)
	source.modulate.a = SOURCE_ALPHA
	shown._follow_mouse()
	_current = shown


## Ends the drag picture (safe to call when there's none) and brings the slot back to normal
static func stop() -> void:
	if _current and is_instance_valid(_current):
		if is_instance_valid(_current._source):
			_current._source.modulate.a = _current._source_alpha
		_current.queue_free()
	_current = null


static func _let_mouse_through(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in control.get_children():
		if child is Control:
			_let_mouse_through(child)


func _process(_delta: float) -> void:
	_follow_mouse()


# The picture is built around its own middle (see InventorySlot.make_drag_preview), so placing
# it at the mouse centres it there
func _follow_mouse() -> void:
	if _picture:
		_picture.position = get_viewport().get_mouse_position()
