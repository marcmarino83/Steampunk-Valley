class_name FallenTrunk
extends Node3D
## A felled tree's trunk lying where it fell, as a row of log sections from the stump outward
## (see TrunkSection), each following the ground beneath it. No physics: it never rolls or
## moves. A child of its tree (see tree.gd), in the tree's own frame, so it scales with it.
## Which sections are left is saved with the tree (see mask()).

## How much of the tree's height is usable trunk, and how much thinner its far end is
const BOLE := 0.75
const TAPER := 0.5
## The gap between the stump and the first section (m, at the tree's normal size)
const GAP := 0.2
## The logs' look: plain bark brown (the trees' own bark is a texture atlas)
const BARK := Color(0.3, 0.22, 0.15)

static var _look: StandardMaterial3D

## The tree it fell from (it hears about each section cut: see tree.gd's section_cut)
var tree: Node
## Wood each section gives
var wood_each := 0

var _left: Array[bool] = []


## Lays the trunk out: `count` sections along `turn` (the way the tree fell, about its up axis),
## for a tree `height` tall with a trunk `radius` thick at its foot, keeping only the sections
## whose bit is set in `remaining` (bit 0: nearest the stump)
func lay(turn: float, count: int, height: float, radius: float, remaining: int) -> void:
	if _look == null:
		_look = StandardMaterial3D.new()
		_look.albedo_color = BARK
		_look.roughness = 0.95
	var along := Vector3(sin(turn), 0.0, cos(turn))
	var length := height * BOLE / count
	var start := radius + GAP
	_left.clear()
	for i in count:
		var kept := (remaining >> i) & 1 == 1
		_left.append(kept)
		if not kept:
			continue
		var thick := radius * lerpf(1.0, TAPER, (i + 0.5) / count)
		var from := _on_ground(along * (start + length * i), thick)
		var to := _on_ground(along * (start + length * (i + 1)), thick)
		var section := TrunkSection.new()
		section.index = i
		section.trunk = self
		section.build(from.distance_to(to) * 0.97, thick, _look)
		# The log's own Y runs from one end to the other
		var axis := (to - from).normalized()
		var side := axis.cross(Vector3.UP).normalized()
		if side.length() < 0.01:
			side = Vector3.RIGHT
		var basis := Basis(side, axis, side.cross(axis))
		section.transform = Transform3D(basis, (from + to) / 2.0)
		add_child(section)


## Section `index` has been cut free: its wood
func cut(index: int) -> int:
	if index < _left.size() and _left[index]:
		_left[index] = false
		if tree:
			tree.section_cut()
		return wood_each
	return 0


## Which sections are left, one bit each (bit 0: nearest the stump; 0: all cut)
func mask() -> int:
	var bits := 0
	for i in _left.size():
		if _left[i]:
			bits |= 1 << i
	return bits


# A spot `offset` out from the tree's foot (in the tree's frame), lifted onto the ground there by
# `thick` (so the log rests on it)
func _on_ground(offset: Vector3, thick: float) -> Vector3:
	var parent := get_parent() as Node3D
	var world := parent.to_global(offset)
	var ground := Plot.ground_at(parent, world.x, world.z)
	var local := parent.to_local(Vector3(world.x, ground, world.z))
	return Vector3(offset.x, local.y + thick, offset.z)
