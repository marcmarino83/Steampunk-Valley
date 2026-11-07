class_name MineableRock
extends StaticBody3D
## A hand-placed rock or boulder. With a pickaxe in hand, E chips stone off it until it's gone.
## (Rocks scattered over the valley are mined the same way: see foliage.gd.)
## There's deliberately no gather() here: the valley treats anything with one as its own
## scattered resource, and hand-placed rocks aren't.

const TOOL := "Pickaxe"
const STONE_PER_HIT := 2

## How many hits before it's used up
@export var hits_left := 4

@onready var model: Node3D = $Model

var _tween: Tween
# How it was before it was mined, to come back to
var _full_hits := 0
var _solid_layer := 1


func _ready() -> void:
	_full_hits = hits_left
	_solid_layer = collision_layer


# Only offers itself to someone holding a pickaxe, so rocks don't all prompt you bare-handed
func can_interact() -> bool:
	var player = get_tree().get_first_node_in_group("player")
	return hits_left > 0 and player != null and player.held_item == TOOL


func get_prompt() -> String:
	return "Mine Rock"


func _mined_out() -> void:
	visible = false
	var valley = get_tree().get_first_node_in_group("valley")
	if valley:
		valley.rock_mined(self)


## Mined out (used when loading a save)
func set_mined() -> void:
	hits_left = 0
	collision_layer = 0
	visible = false


## Back as it was, unless a building now stands where it was. True if it came back.
func come_back() -> bool:
	var valley = get_tree().get_first_node_in_group("valley")
	if valley and valley.is_under_building(global_position.x, global_position.z, 0.5):
		return false
	hits_left = _full_hits
	model.scale = Vector3.ONE
	collision_layer = _solid_layer
	visible = true
	return true


func interact(player) -> void:
	hits_left -= 1
	player.gathered("Stone", STONE_PER_HIT)
	if _tween:
		_tween.kill()
	_tween = create_tween()
	if hits_left <= 0:
		# Mined out: it shrinks away, and comes back after the Valley's Boulder Respawn Days
		collision_layer = 0
		_tween.tween_property(model, "scale", Vector3.ZERO, 0.25)
		_tween.tween_callback(_mined_out)
	else:
		_tween.tween_property(model, "scale", Vector3.ONE * 0.94, 0.06)
		_tween.tween_property(model, "scale", Vector3.ONE, 0.12)
