extends Control
## The hammer's build menu. It looks just like the inventory screen, and lists every Buildable
## resource in res://buildables/, so adding a buildable never means changing this script.

signal chosen(buildable: Buildable)

const SLOT_SCENE = preload("res://ui/build_slot.tscn")
const BUILDABLES_FOLDER := "res://buildables"

## How many slots the menu shows at least. Empty ones still show, as in the backpack.
@export var slot_count := 10

@onready var grid: GridContainer = $Center/Panel/VBox/Grid
@onready var detail_label: Label = $Center/Panel/VBox/Detail

var _buildables: Array[Buildable] = []
var _inventory := {}
# Says whether the player has unlocked a buildable yet
var _is_unlocked: Callable = func(_b): return true
# The buildable under the mouse, whose details are showing
var _hovered: Buildable


func _ready() -> void:
	_buildables = _load_buildables()
	for i in maxi(slot_count, _buildables.size()):
		var slot := SLOT_SCENE.instantiate()
		grid.add_child(slot)
		slot.chosen.connect(chosen.emit)
		slot.hover_changed.connect(_on_hover_changed)
	# The mouse leaving a closed menu doesn't count as leaving a slot, so clear up on closing
	hidden.connect(func():
		_hovered = null
		_update_detail())
	_update_detail()


## Brings every slot up to date with what's in your pockets and what you've unlocked
func refresh(inventory: Dictionary, is_unlocked: Callable) -> void:
	_inventory = inventory
	_is_unlocked = is_unlocked
	var slots := grid.get_children()
	for i in slots.size():
		if i < _buildables.size():
			var unlocked: bool = is_unlocked.call(_buildables[i])
			slots[i].show_buildable(_buildables[i], unlocked and _buildables[i].can_afford(inventory), not unlocked)
		else:
			slots[i].clear()
	_update_detail()


## Every buildable, locked or not
func all_buildables() -> Array[Buildable]:
	return _buildables


func _load_buildables() -> Array[Buildable]:
	var found: Array[Buildable] = []
	var files := ResourceLoader.list_directory(BUILDABLES_FOLDER)
	files.sort()
	for file in files:
		if file.ends_with(".tres"):
			var buildable := load(BUILDABLES_FOLDER.path_join(file)) as Buildable
			if buildable:
				found.append(buildable)
	return found


func _on_hover_changed(buildable: Buildable, hovering: bool) -> void:
	if hovering:
		_hovered = buildable
	elif _hovered == buildable:
		_hovered = null
	_update_detail()


func _update_detail() -> void:
	if _hovered == null:
		detail_label.text = ""
	elif not _is_unlocked.call(_hovered):
		detail_label.text = _hovered.unlock_hint_text()
	elif _hovered.can_afford(_inventory):
		detail_label.text = "Click to place a %s" % _hovered.display_name
	else:
		detail_label.text = "Missing %s" % _hovered.missing_text(_inventory)
