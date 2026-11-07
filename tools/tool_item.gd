class_name ToolItem
extends Resource
## Marks an inventory item as a tool or weapon: something that can go on the action bar, be held
## in your hand, and be dropped in the world. Each one is a resource file in res://tools/, found
## by itself, so a new tool (gun, magitek...) needs no action bar code: add a resource and a
## model. What the tool does is up to whatever checks the player's held_item.

const FOLDER := "res://tools"
const TIER_FOLDER := "res://iron_tier/tools"

## The name it goes by in the inventory, exactly, like "Hammer"
@export var item_name := ""
## The real model. Until this file is in the project, the placeholder below is used instead.
@export_file("*.fbx", "*.glb", "*.gltf") var model_file := ""
## A simple stand-in model
@export var placeholder_scene: PackedScene
## How long the tool is along its longest side, in meters. Any model is scaled to this,
## whatever size it was made at, and centered.
@export var length := 0.5
## Squares up the real model, however it was exported, before anything else: the head should end
## up at +Y, its working edge toward -Z, and its flat side facing +X and -X. Doesn't apply to the
## placeholder, which is already built that way.
@export var model_rotation_degrees := Vector3.ZERO

@export_group("In the hand")
## Added to where the hand is, in meters (+X is right, +Y is up, -Z is away from you)
@export var held_position := Vector3.ZERO
## Turns the tool in the hand, in degrees. With the head at the top of the model: Z leans the
## head in toward the middle of the view, and a negative X tips it away from you.
@export var held_rotation_degrees := Vector3(-25, -10, 20)

@export_group("On the ground")
## How it lies when dropped, in degrees
@export var dropped_rotation_degrees := Vector3(90, 0, 0)
## How far off the ground its middle sits when dropped, in meters
@export var dropped_height := 0.06

# Every tool, by item name. Filled the first time anything asks.
static var _tools := {}


static func find(item: String) -> ToolItem:
	if _tools.is_empty():
		for folder in IronTier.folders(FOLDER, TIER_FOLDER):
			for file in ResourceLoader.list_directory(folder):
				if file.ends_with(".tres"):
					var tool_item := load(folder.path_join(file)) as ToolItem
					if tool_item:
						_tools[tool_item.item_name] = tool_item
	return _tools.get(item)


static func exists_for(item: String) -> bool:
	return find(item) != null


## Lets go of the list of tools. The player calls this as the game closes: tools still held in
## the list at exit would otherwise be reported as leaked.
static func forget_all() -> void:
	_tools.clear()


## The model for holding: turned to suit the hand, casting no shadow on the world
func make_held_model() -> Node3D:
	var model := _make_model()
	model.position = held_position
	model.rotation_degrees = held_rotation_degrees
	_turn_off_shadows(model)
	return model


## The model for lying on the ground
func make_dropped_model() -> Node3D:
	var model := _make_model()
	model.position = Vector3.UP * dropped_height
	model.rotation_degrees = dropped_rotation_degrees
	return model


# The GLB if it's there, or the placeholder, scaled to the tool's length and centered on a pivot,
# so that the same settings suit a model of any size
func _make_model() -> Node3D:
	var scene: PackedScene = placeholder_scene
	var turn := Basis.IDENTITY
	if not model_file.is_empty() and ResourceLoader.exists(model_file):
		scene = load(model_file)
		turn = Basis.from_euler(model_rotation_degrees * PI / 180.0)
	var pivot := Node3D.new()
	if scene == null:
		return pivot
	var model: Node3D = scene.instantiate()
	var bounds := Transform3D(turn, Vector3.ZERO) * _bounds_of(model, Transform3D.IDENTITY, AABB())
	var longest := bounds.get_longest_axis_size()
	var fit := length / longest if longest > 0.0 else 1.0
	model.transform = Transform3D(turn.scaled(Vector3.ONE * fit), -bounds.get_center() * fit)
	pivot.add_child(model)
	return pivot


# The box around all of a node's meshes, measured from that node
func _bounds_of(node: Node, parent_transform: Transform3D, bounds: AABB) -> AABB:
	for child in node.get_children():
		if not child is Node3D:
			continue
		var child_transform: Transform3D = parent_transform * child.transform
		if child is MeshInstance3D and child.mesh:
			var box: AABB = child_transform * child.mesh.get_aabb()
			bounds = box if not bounds.has_volume() else bounds.merge(box)
		bounds = _bounds_of(child, child_transform, bounds)
	return bounds


func _turn_off_shadows(node: Node) -> void:
	for child in node.get_children():
		if child is GeometryInstance3D:
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_turn_off_shadows(child)
