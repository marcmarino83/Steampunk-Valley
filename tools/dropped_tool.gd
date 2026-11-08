class_name DroppedTool
extends StaticBody3D
## A tool lying on the ground, showing its own model. E picks it back up.

const PICKUP_RADIUS := 0.22

var _item := ""


## Makes the thing to drop for this tool
static func create(tool_item: ToolItem) -> DroppedTool:
	var dropped := DroppedTool.new()
	dropped._item = tool_item.item_name
	dropped.add_to_group("dropped_tools")
	# The model alone: a tool's held effect (a torch's flame) is only added in the hand
	dropped.add_child(tool_item.make_dropped_model())
	var sphere := SphereShape3D.new()
	sphere.radius = PICKUP_RADIUS
	var collision := CollisionShape3D.new()
	collision.shape = sphere
	collision.position = Vector3.UP * PICKUP_RADIUS * 0.5
	dropped.add_child(collision)
	return dropped


## Which tool this is
func item() -> String:
	return _item


func can_interact() -> bool:
	return true


func get_prompt() -> String:
	return "Pick up %s" % _item


func interact(player) -> void:
	var tool_item := ToolItem.find(_item)
	if player.inventory.has(_item) and not (tool_item and tool_item.stackable):
		player.flash("You already have one")
		return
	player.add_item(_item, 1)
	queue_free()
