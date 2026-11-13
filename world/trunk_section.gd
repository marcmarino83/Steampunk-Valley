class_name TrunkSection
extends ResourceNode
## One section of a felled tree's trunk, lying on the ground (see FallenTrunk). HITS swings of
## the axe cut it free: its wood goes straight into the inventory and that part of the trunk is
## gone. Stamina per swing and the Axe needed work as for any tool (see ResourceNode.interact).

## Swings to cut one section free
const HITS := 2

## Which section of its trunk this is (0 nearest the stump), and the trunk it belongs to
var index := 0
var trunk: Node

var _mesh: MeshInstance3D


func _init() -> void:
	resource_name = "Wood"
	required_tool = "Axe"
	gathers_left = HITS


## Gives it its look and shape: a log `length` long and `radius` thick, along its own Y
func build(length: float, radius: float, look: Material) -> void:
	_mesh = MeshInstance3D.new()
	var log_mesh := CylinderMesh.new()
	log_mesh.height = length
	log_mesh.top_radius = radius * 0.92
	log_mesh.bottom_radius = radius
	log_mesh.radial_segments = 10
	log_mesh.rings = 1
	log_mesh.material = look
	_mesh.mesh = log_mesh
	add_child(_mesh)
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.height = length
	cylinder.radius = radius
	shape.shape = cylinder
	add_child(shape)


func get_prompt() -> String:
	return "Cut Log"


## One swing: a shudder, and on the last one its wood, and it's gone
func gather() -> int:
	gathers_left -= 1
	if _tween:
		_tween.kill()
	_tween = create_tween()
	if gathers_left > 0:
		_tween.tween_property(_mesh, "scale", Vector3(1.08, 0.97, 1.08), 0.05)
		_tween.tween_property(_mesh, "scale", Vector3.ONE, 0.1)
		return 0
	collision_layer = 0
	_tween.tween_property(_mesh, "scale", Vector3.ZERO, 0.2)
	_tween.tween_callback(queue_free)
	var wood: int = trunk.cut(index) if trunk else 0
	return wood
