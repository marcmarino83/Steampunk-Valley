class_name ActionBar
extends VBoxContainer
## The nine slots along the bottom of the screen, and which one is in your hand. The bar only
## says which slot each tool sits in; the player's inventory still counts everything you own.

## The tools on the bar changed, so the backpack needs redrawing
signal contents_changed
## A different item (or nothing, as an empty string) is now in your hand
signal held_changed(item: String)

const SLOT_SCENE = preload("res://ui/action_slot.tscn")
const SLOT_COUNT := 9
## How long an item's name stays up after switching to it, and how long it then takes to fade
const NAME_SECONDS := 1.2
const NAME_FADE_SECONDS := 0.4
## The gap kept below the bar, in pixels at 1920 x 1080
const BOTTOM_GAP := 26.0

## action_bar.png (945 x 183, its left end trimmed at the frame): where its first slot opening
## is, how far apart the openings are, and how big each is, in its own pixels (measured from
## the art), and how big its pixels are drawn on screen. The slots are laid out to sit exactly
## over the openings.
const ART_FIRST_SLOT := Vector2(27, 72)
const ART_PITCH := 96.33
const ART_SLOT := Vector2(90, 92)
const ART_SCALE := 0.75
## Without the art: a brass rail round plain slots, this far past them
const FRAME_PAD := Vector2(8, 7)

@onready var row: HBoxContainer = $Row
@onready var name_label: Label = $NameLabel

## The item in each slot, with an empty string for an empty slot
var items: Array[String] = []
## Which slot is selected, or -1 with your hands empty
var selected := -1

var _held := ""
var _name_tween: Tween
# The bar's art (kept loaded while it's drawn), or the code-drawn rail when there's none
var _art: Texture2D
var _frame: StyleBox


func _ready() -> void:
	items.resize(SLOT_COUNT)
	items.fill("")
	_art = BrassStyle.texture("action_bar")
	var slot_size := ART_SLOT * ART_SCALE
	var gap := (ART_PITCH - ART_SLOT.x) * ART_SCALE
	for i in SLOT_COUNT:
		var slot := SLOT_SCENE.instantiate()
		row.add_child(slot)
		slot.set_number(i + 1)
		slot.tool_dropped.connect(assign.bind(i))
		if _art:
			# Each slot is as wide as one step along the bar, its picture filling the opening
			slot.fit_opening(slot_size, gap)
	name_label.modulate.a = 0.0
	set_editing(false)
	_update()
	add_to_group("saveable")
	offset_top = -BOTTOM_GAP
	offset_bottom = -BOTTOM_GAP
	if _art:
		row.add_theme_constant_override("separation", 0)
		# The art reaches further past the first slot than past the last: move over so the art,
		# not just the slots, is centred
		var past_last := _art.get_width() - ART_FIRST_SLOT.x - ART_PITCH * SLOT_COUNT
		offset_left = (ART_FIRST_SLOT.x - past_last) * ART_SCALE / 2.0
		offset_right = offset_left
		# The held item's name sits just above the art's top
		add_theme_constant_override("separation", int(ART_FIRST_SLOT.y * ART_SCALE) + 2)
		name_label.add_theme_font_size_override("font_size", 16)
	else:
		# The plain slots were laid out for the old 1152 x 648 screen, so they're drawn bigger by
		# the same amount the screen layout grew, from the bottom middle
		scale = Vector2.ONE * MenuStyle.OLD_LAYOUT_SCALE
		var keep_bottom_middle := func(): pivot_offset = Vector2(size.x / 2.0, size.y)
		resized.connect(keep_bottom_middle)
		keep_bottom_middle.call()
		_frame = BrassStyle.frame("action_bar")
		add_theme_constant_override("separation", 14)
	row.draw.connect(_draw_frame)


# Behind the slots: the bar's art, placed so its openings fall on the slots; or the plain rail
func _draw_frame() -> void:
	if _art:
		row.draw_texture_rect(_art, _art_rect(), false)
		return
	_frame.draw(row.get_canvas_item(), Rect2(-FRAME_PAD, row.size + FRAME_PAD * 2.0))


# Where the art goes, in the row's own coordinates
func _art_rect() -> Rect2:
	return Rect2(-ART_FIRST_SLOT * ART_SCALE, _art.get_size() * ART_SCALE)


## Where the bar is on screen, as drawn, art and all (the controls row sits above it, the compass
## to its left)
func rect_on_screen() -> Rect2:
	var xform := row.get_global_transform()
	var local := _art_rect() if _art else Rect2(-FRAME_PAD, row.size + FRAME_PAD * 2.0)
	var top_left := xform * local.position
	var bottom_right := xform * local.end
	# The item's name shows above the bar's top
	var name_top := (name_label.get_global_transform() * Vector2.ZERO).y
	top_left.y = minf(top_left.y, name_top)
	return Rect2(top_left, bottom_right - top_left)


## Where slot 1's picture is on screen (the compass tucks in just left of it)
func first_slot_rect() -> Rect2:
	return row.get_child(0).get_global_rect()


func save_key() -> String:
	return "action_bar"


# After the player, so the tools it lists are already back in the inventory
func save_priority() -> int:
	return 50


func save_data() -> Dictionary:
	return {"items": Array(items), "selected": selected}


func load_data(data: Dictionary) -> void:
	var saved: Array = data.get("items", [])
	for i in SLOT_COUNT:
		items[i] = str(saved[i]) if i < saved.size() else ""
	selected = clampi(int(data.get("selected", -1)), -1, SLOT_COUNT - 1)
	_update()
	contents_changed.emit()


## The item in your hand, or an empty string
func held_item() -> String:
	return "" if selected < 0 else items[selected]


## A number key: selects that slot, or puts away what's in your hand if it's already selected
func press(index: int) -> void:
	selected = -1 if selected == index else index
	_update()


## The mouse wheel: moves the selection along the bar, wrapping around at the ends
func cycle(step: int) -> void:
	if selected < 0:
		selected = 0 if step > 0 else SLOT_COUNT - 1
	else:
		selected = posmod(selected + step, SLOT_COUNT)
	_update()


## Moves a tool into a slot. If it came from another slot, whatever's here swaps over there;
## if it came from the backpack, whatever's here goes back to the backpack.
func assign(item: String, index: int) -> void:
	var from := items.find(item)
	if from >= 0:
		items[from] = items[index]
	items[index] = item
	_update()
	contents_changed.emit()


## Takes a tool off the bar, which puts it back in the backpack
func remove(item: String) -> void:
	var slot := items.find(item)
	if slot >= 0:
		items[slot] = ""
		_update()
		contents_changed.emit()


## True if this item is sitting in a slot
func has_item(item: String) -> bool:
	return items.has(item)


## The number key for this item, or 0 if it isn't on the bar
func key_for(item: String) -> int:
	return items.find(item) + 1


## Clears out anything you no longer own
func forget_missing(inventory: Dictionary) -> void:
	var changed := false
	for i in SLOT_COUNT:
		if not items[i].is_empty() and not inventory.has(items[i]):
			items[i] = ""
			changed = true
	if changed:
		_update()


## Slots only take the mouse while the backpack is open, so at any other time a click
## on the bar can still grab the mouse for looking around
func set_editing(editing: bool) -> void:
	for slot in row.get_children():
		slot.mouse_filter = Control.MOUSE_FILTER_STOP if editing else Control.MOUSE_FILTER_IGNORE


func _update() -> void:
	var slots := row.get_children()
	for i in SLOT_COUNT:
		slots[i].show_item(items[i], i == selected)
	if held_item() != _held:
		_held = held_item()
		if not _held.is_empty():
			_show_name(_held)
		held_changed.emit(_held)


func _show_name(item: String) -> void:
	name_label.text = item
	if _name_tween:
		_name_tween.kill()
	name_label.modulate.a = 1.0
	_name_tween = create_tween()
	_name_tween.tween_interval(NAME_SECONDS)
	_name_tween.tween_property(name_label, "modulate:a", 0.0, NAME_FADE_SECONDS)
