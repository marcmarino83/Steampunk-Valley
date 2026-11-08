class_name ItemBundle
extends StaticBody3D
## A bundle of things left on the ground because the backpack was full (a demolished piece's
## refund, say). E picks up whatever fits; anything that still doesn't stays in the bundle.

const SIZE := Vector3(0.5, 0.32, 0.4)
const COLOR := Color(0.5, 0.38, 0.22)
const STRAP_COLOR := Color(0.32, 0.24, 0.15)

## What's in it: item -> how many
var contents := {}


## Makes a bundle holding these items
static func create(items: Dictionary) -> ItemBundle:
	var bundle := ItemBundle.new()
	bundle.contents = items.duplicate()
	bundle.add_to_group("item_bundles")
	var look := StandardMaterial3D.new()
	look.albedo_color = COLOR
	look.roughness = 0.95
	var sack := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = SIZE
	box.material = look
	sack.mesh = box
	sack.position.y = SIZE.y / 2.0
	bundle.add_child(sack)
	# A strap round it, so it reads as a tied-up bundle
	var strap_look := StandardMaterial3D.new()
	strap_look.albedo_color = STRAP_COLOR
	var strap := MeshInstance3D.new()
	var band := BoxMesh.new()
	band.size = Vector3(0.06, SIZE.y + 0.02, SIZE.z + 0.02)
	band.material = strap_look
	strap.mesh = band
	strap.position.y = SIZE.y / 2.0
	bundle.add_child(strap)
	var solid := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = SIZE
	solid.shape = shape
	solid.position.y = SIZE.y / 2.0
	bundle.add_child(solid)
	return bundle


func can_interact() -> bool:
	return not contents.is_empty()


func get_prompt() -> String:
	var parts: PackedStringArray = []
	for item in contents:
		parts.append("%d %s" % [contents[item], item])
	return "Pick up %s" % ", ".join(parts)


func interact(player) -> void:
	var taken := false
	for item in contents.keys():
		if player.has_room_for(item):
			player.add_item(item, contents[item])
			contents.erase(item)
			taken = true
	if contents.is_empty():
		queue_free()
	elif not taken:
		player.flash("Inventory full")
	else:
		player.flash("Inventory full: some is still in the bundle")
