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


# Only offers itself to someone holding a pickaxe, so rocks don't all prompt you bare-handed
func can_interact() -> bool:
	var player = get_tree().get_first_node_in_group("player")
	return hits_left > 0 and player != null and player.held_item == TOOL


func get_prompt() -> String:
	return "Mine Rock"


func interact(player) -> void:
	hits_left -= 1
	player.gathered("Stone", STONE_PER_HIT)
	if _tween:
		_tween.kill()
	_tween = create_tween()
	if hits_left <= 0:
		collision_layer = 0
		_tween.tween_property(model, "scale", Vector3.ZERO, 0.25)
		_tween.tween_callback(queue_free)
	else:
		_tween.tween_property(model, "scale", Vector3.ONE * 0.94, 0.06)
		_tween.tween_property(model, "scale", Vector3.ONE, 0.12)
