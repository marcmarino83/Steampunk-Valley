extends ResourceNode
## A tree. A few swings of the axe fell it (gathers_left, as set in its scene). A grown tree
## then lies where it fell as log sections (see FallenTrunk, TrunkSection), each cut free in
## TrunkSection.HITS swings for its wood, and its stump stays until STUMP_HITS swings clear it for
## a little more. How many sections and how much wood depend on its size (SIZES). A young tree
## (shorter than SIZES' first height) just falls and gives `wood_amount`. Either way it grows
## back on the valley's timers (stump, sapling, full: see Forest), and what's left of a felled
## tree is saved with the valley (see save_state).

## How much wood a young tree (no sections) gives when it comes down
@export var wood_amount := 3
## The tree's height and trunk radius at its normal size, in meters. The valley uses these
## to sink it into the ground by the right amount for its size, and they size its trunk sections.
@export var tree_height := 8.0
@export var trunk_radius := 0.3

## How big the sapling is, compared to the full tree, while it grows back from the stump
## (when the sapling appears is Forest.SAPLING_AT)
const SAPLING_SIZE := 0.3
## By size: [shorter than this height (m), sections, wood a section, wood from the stump]. A tree
## shorter than the first height is young: no sections, no stump to clear.
const SIZES := [
	[3.0, 0, 0, 0],
	[8.0, 3, 2, 1],
	[15.0, 4, 4, 2],
	[INF, 6, 4, 3],
]
## Swings to clear a stump
const STUMP_HITS := 2
## The stump made for trees whose scene has none: its height (m, at the tree's normal size)
const STUMP_HEIGHT := 0.45

@onready var top: Node3D = $Top
@onready var trunk_collision: CollisionShape3D = $TrunkCollision

# How it stood before it was felled, to grow back to
var _full_gathers := 0
var _top_transform := Transform3D.IDENTITY
# Once felled: the trunk lying on the ground (or null), the stump, and which way it fell
var _trunk: FallenTrunk
var _stump: Node3D
var _stump_collision: CollisionShape3D
var _fall_turn := 0.0
var _felled_now := false
var _scene_stump := false


func _init() -> void:
	required_tool = "Axe"


func _ready() -> void:
	_full_gathers = gathers_left
	_top_transform = top.transform
	_stump = get_node_or_null("Stump")
	_stump_collision = get_node_or_null("StumpCollision")
	_scene_stump = _stump != null and _stump_collision != null


func get_prompt() -> String:
	return "Clear Stump" if _felled_now else "Chop Tree"


## One swing of the axe. Standing, it gives nothing until the last hit fells it (a young tree
## gives its wood then); felled, it's the stump, whose last hit gives the stump's wood.
func gather() -> int:
	gathers_left -= 1
	if _tween:
		_tween.kill()
	if _felled_now:
		if gathers_left > 0:
			_tween = create_tween()
			_tween.tween_property(_stump, "scale", Vector3(1.06, 0.94, 1.06), 0.05)
			_tween.tween_property(_stump, "scale", Vector3.ONE, 0.1)
			return 0
		_clear_stump()
		_report_change()
		return _size()[3]
	_tween = create_tween()

	if gathers_left > 0:
		# Shudder from the hit
		_tween.tween_property(top, "rotation:z", 0.06, 0.05)
		_tween.tween_property(top, "rotation:z", -0.04, 0.08)
		_tween.tween_property(top, "rotation:z", 0.0, 0.1)
		return 0

	_topple()
	return wood_amount if _size()[1] == 0 else 0


## All the wood this tree gives by hand: its sections and stump, or a young tree's wood_amount
func total_wood() -> int:
	var size := _size()
	return wood_amount if size[1] == 0 else size[1] * size[2] + size[3]


## A section of the trunk was cut free (see FallenTrunk.cut): the valley keeps what's left
func section_cut() -> void:
	_report_change()


## What's left of a felled tree, as the valley saves it: "felled:<sections left, one bit each>:
## <stump swings left>:<which way it fell>". (Standing, sapling and older "stump" states are the
## valley's own: see Forest.)
func save_state() -> String:
	var left := _trunk.mask() if _trunk and is_instance_valid(_trunk) else 0
	return "felled:%d:%d:%s" % [left, gathers_left if _felled_now else 0, str(_fall_turn)]


## Loading a save: a felled tree as save_state wrote it
func restore_state(state: String) -> void:
	var parts := state.split(":")
	if parts.size() < 4:
		set_stage("stump")
		return
	_fall_turn = float(parts[3])
	_lie_felled(int(parts[1]), int(parts[2]))


func _topple() -> void:
	# Fall away from whoever chopped it
	var camera := get_viewport().get_camera_3d()
	if camera:
		var away := -to_local(camera.global_position)
		top.rotation.y = atan2(away.x, away.z)
	top.rotation.z = 0.0
	_fall_turn = top.rotation.y

	# You can walk where the trunk stood
	trunk_collision.set_deferred("disabled", true)

	# Tip over slowly at first, then crash down, lie there a moment; then the crown goes (kept,
	# hidden, to grow back from the stump later) and the trunk's sections lie in its place
	_tween.tween_property(top, "rotation:x", deg_to_rad(85), 1.0) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_interval(0.8)
	_tween.tween_property(top, "scale", Vector3.ZERO, 0.4)
	_tween.tween_callback(_felled)


# The tree is down: young, nothing's left; grown, its trunk lies there and its stump stands. The
# stump grows a sapling partway through the Valley's Tree Regrow Days, then a full tree.
func _felled() -> void:
	var size := _size()
	if size[1] > 0:
		_lie_felled((1 << size[1]) - 1, STUMP_HITS)
	else:
		top.visible = false
		_show_billboard(false)
	var valley = get_tree().get_first_node_in_group("valley")
	if valley:
		valley.tree_felled(self)


# Felled: the crown hidden, the trunk sections in `left` lying along the fall, and the stump with
# `stump_hits` swings left (0: already cleared)
func _lie_felled(left: int, stump_hits: int) -> void:
	var size := _size()
	top.visible = false
	trunk_collision.set_deferred("disabled", true)
	_show_billboard(false)
	_remove_trunk()
	if size[1] > 0 and left != 0:
		_trunk = FallenTrunk.new()
		_trunk.name = "FallenTrunk"
		_trunk.tree = self
		_trunk.wood_each = size[2]
		add_child(_trunk)
		_trunk.lay(_fall_turn, size[1], tree_height, trunk_radius, left)
	_felled_now = stump_hits > 0
	gathers_left = stump_hits
	if _felled_now:
		_make_stump()
		_stump.visible = true
		_stump.scale = Vector3.ONE
		_stump_collision.set_deferred("disabled", false)
	else:
		_clear_stump()


## How far the tree has grown back: "stump" (just felled), "sapling" or "full". The valley calls
## this as it regrows, and when loading a save. ("stump" here is an older save's felled tree: its
## trunk was already gone, and its stump can still be cleared.)
func set_stage(stage: String) -> void:
	match stage:
		"stump":
			_lie_felled(0, STUMP_HITS if _size()[1] > 0 else 0)
		"sapling":
			_back_to_growing()
			top.transform = Transform3D(_top_transform.basis.scaled(Vector3.ONE * SAPLING_SIZE),
					_top_transform.origin)
			top.visible = true
			trunk_collision.set_deferred("disabled", true)
			gathers_left = 0
		"full":
			_back_to_growing()
			top.transform = _top_transform
			top.visible = true
			_show_billboard(true)
			trunk_collision.set_deferred("disabled", false)
			gathers_left = _full_gathers


# Growing again: whatever was left of the felled tree goes (the old trunk rots away). A stump
# that's part of the tree's own scene stays, as it always has.
func _back_to_growing() -> void:
	_felled_now = false
	_remove_trunk()
	_clear_stump()
	if _scene_stump:
		_stump.visible = true
		_stump_collision.set_deferred("disabled", false)


func _remove_trunk() -> void:
	if _trunk and is_instance_valid(_trunk):
		# (out of the tree at once, so a trunk laid again straight after takes its name)
		remove_child(_trunk)
		_trunk.queue_free()
	_trunk = null


func _clear_stump() -> void:
	_felled_now = false
	gathers_left = 0
	if _stump:
		_stump.visible = false
	if _stump_collision:
		_stump_collision.set_deferred("disabled", true)


# A stump for trees whose scene has none: a short bark-brown cylinder, solid, to aim at
func _make_stump() -> void:
	if _stump == null:
		var mesh := CylinderMesh.new()
		mesh.height = STUMP_HEIGHT
		mesh.top_radius = trunk_radius
		mesh.bottom_radius = trunk_radius * 1.15
		mesh.radial_segments = 10
		mesh.rings = 1
		var look := StandardMaterial3D.new()
		look.albedo_color = FallenTrunk.BARK
		look.roughness = 0.95
		mesh.material = look
		var shown := MeshInstance3D.new()
		shown.name = "Stump"
		shown.mesh = mesh
		shown.position.y = STUMP_HEIGHT / 2.0
		add_child(shown)
		_stump = shown
	if _stump_collision == null:
		var shape := CylinderShape3D.new()
		shape.height = STUMP_HEIGHT
		shape.radius = trunk_radius * 1.15
		_stump_collision = CollisionShape3D.new()
		_stump_collision.name = "StumpCollision"
		_stump_collision.shape = shape
		_stump_collision.position.y = STUMP_HEIGHT / 2.0
		add_child(_stump_collision)


# The far-away picture some trees have outside their crown: shown only while standing
func _show_billboard(shown: bool) -> void:
	var billboard := get_node_or_null("Billboard") as Node3D
	if billboard:
		billboard.visible = shown


# This tree's row of SIZES
func _size() -> Array:
	for row in SIZES:
		if tree_height < row[0]:
			return row
	return SIZES[-1]


func _report_change() -> void:
	var valley = get_tree().get_first_node_in_group("valley")
	if valley and valley.has_method("tree_changed"):
		valley.tree_changed(self)
