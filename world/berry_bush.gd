extends ResourceNode
## A berry bush. Picking it clean leaves the bush standing, bare, until its berries grow back
## (the Valley's Berries Regrow Days).

var _full_gathers := 0


func _ready() -> void:
	_full_gathers = gathers_left


# Bare bushes still answer, so looking at one says why there's nothing to pick
func can_interact() -> bool:
	return true


func get_prompt() -> String:
	return "Gather %s" % resource_name if gathers_left > 0 else "No berries yet"


func interact(player) -> void:
	if gathers_left <= 0:
		player.flash("No berries yet.")
		return
	super.interact(player)


func gather() -> int:
	var mesh: Node3D = $MeshInstance3D
	gathers_left -= 1
	if _tween:
		_tween.kill()
	_tween = create_tween()
	# A quick squash so you can see it worked
	_tween.tween_property(mesh, "scale", Vector3(1.1, 0.88, 1.1), 0.06)
	_tween.tween_property(mesh, "scale", Vector3.ONE, 0.12)
	if gathers_left <= 0:
		_show_berries(false)
		var valley = get_tree().get_first_node_in_group("valley")
		if valley:
			valley.bush_emptied(self)
	return amount_per_gather


## Berries back on the bush (the valley calls this when they've grown back)
func regrow() -> void:
	gathers_left = _full_gathers
	_show_berries(true)


## Picked clean (used when loading a save)
func set_empty() -> void:
	gathers_left = 0
	_show_berries(false)


# The berries are the bush mesh's children named Berry, Berry2 and so on
func _show_berries(shown: bool) -> void:
	for child in $MeshInstance3D.get_children():
		if child.name.begins_with("Berry"):
			child.visible = shown
