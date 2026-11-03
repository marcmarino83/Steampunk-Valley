extends ResourceNode

## How much wood drops when the tree comes down
@export var wood_amount := 3
## The tree's height and trunk radius at its normal size, in meters. The valley uses these
## to sink it into the ground by the right amount for its size.
@export var tree_height := 8.0
@export var trunk_radius := 0.3

@onready var top: Node3D = $Top
@onready var trunk_collision: CollisionShape3D = $TrunkCollision


func get_prompt() -> String:
	return "Chop Tree"


## One swing of the axe. Gives nothing until the last hit fells the tree.
func gather() -> int:
	gathers_left -= 1
	if _tween:
		_tween.kill()
	_tween = create_tween()

	if gathers_left > 0:
		# Shudder from the hit
		_tween.tween_property(top, "rotation:z", 0.06, 0.05)
		_tween.tween_property(top, "rotation:z", -0.04, 0.08)
		_tween.tween_property(top, "rotation:z", 0.0, 0.1)
		return 0

	_topple()
	return wood_amount


func _topple() -> void:
	# Fall away from whoever chopped it
	var camera := get_viewport().get_camera_3d()
	if camera:
		var away := -to_local(camera.global_position)
		top.rotation.y = atan2(away.x, away.z)
	top.rotation.z = 0.0

	# The stump stays solid, but you can walk where the trunk was
	trunk_collision.set_deferred("disabled", true)

	# Tip over slowly at first, then crash down, lie there a moment, then vanish
	_tween.tween_property(top, "rotation:x", deg_to_rad(85), 1.0) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_interval(0.8)
	_tween.tween_property(top, "scale", Vector3.ZERO, 0.4)
	_tween.tween_callback(top.queue_free)
