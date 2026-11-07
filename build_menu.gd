extends Control
## The hammer's build menu. It looks just like the inventory screen, and lists every Buildable
## resource in res://buildables/, so adding a buildable never means changing this script.

signal chosen(buildable: Buildable)

const SLOT_SCENE = preload("res://build_slot.tscn")
const BUILDABLES_FOLDER := "res://buildables"

## How many slots the menu shows at least. Empty ones still show, as in the backpack.
@export var slot_count := 10

@onready var grid: GridContainer = $Center/Panel/VBox/Grid
@onready var detail_label: Label = $Center/Panel/VBox/Detail

var _buildables: Array[Buildable] = []
var _inventory := {}
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


## Brings every slot up to date with what's in your pockets
func refresh(inventory: Dictionary) -> void:
	_inventory = inventory
	var slots := grid.get_children()
	for i in slots.size():
		if i < _buildables.size():
			slots[i].show_buildable(_buildables[i], _buildables[i].can_afford(inventory))
		else:
			slots[i].clear()
	_update_detail()


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
	elif _hovered.can_afford(_inventory):
		detail_label.text = "Click to place a %s" % _hovered.display_name
	else:
		detail_label.text = "Missing %s" % _hovered.missing_text(_inventory)
