extends ResourceNode
## Iron or coal buried under a hillside. It's invisible and can't be gathered until a
## dowsing rod's pulse reveals it: then a dig spot appears on the ground with a faint
## marker floating above it, and E digs it out like any other resource.
## If it's left untouched, it hides again when the reveal runs out; once you've started
## digging, it stays found.

## The faint marker's color, so iron and coal can be told apart from a distance
@export var marker_color := Color(1.0, 0.5, 0.25)

@onready var marker: Node3D = $Marker

## True while it can be seen and dug
var revealed := false
var _full_gathers := 0
var _hide_at_msec := 0
var _solid_layer := 1


func _ready() -> void:
	add_to_group("hidden_deposits")
	_full_gathers = gathers_left
	_solid_layer = collision_layer
	# A soft, glowing see-through color for the marker and its beam
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.albedo_color = Color(marker_color.r * 2.0, marker_color.g * 2.0, marker_color.b * 2.0, 0.45)
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	var parts: Array = marker.find_children("*", "MeshInstance3D", true, false)
	parts.append(marker)
	for part in parts:
		(part as MeshInstance3D).material_override = glow
	_set_shown(false)


func can_interact() -> bool:
	return revealed and gathers_left > 0


func get_prompt() -> String:
	return "Dig %s" % resource_name


## Shows this deposit for `seconds` (called by the dowsing rod's pulse)
func reveal(seconds: float) -> void:
	_hide_at_msec = Time.get_ticks_msec() + int(seconds * 1000.0)
	_set_shown(true)


func _process(_delta: float) -> void:
	if not revealed:
		return
	# The marker bobs gently and slowly turns
	var t := Time.get_ticks_msec() * 0.001
	marker.position.y = 2.6 + sin(t * 2.0) * 0.12
	marker.rotation.y = t * 0.8
	# Untouched deposits sink back out of sight when the reveal runs out
	if Time.get_ticks_msec() > _hide_at_msec and gathers_left == _full_gathers:
		_set_shown(false)


func _set_shown(shown: bool) -> void:
	revealed = shown
	visible = shown
	collision_layer = _solid_layer if shown else 0
