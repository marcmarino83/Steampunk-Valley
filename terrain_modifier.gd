@tool
extends Node3D
## Reshapes the valley's ground inside a circle. Drop one into the world, move it where you
## want it, and the Valley applies it when it builds the terrain.
##
## In the editor, select it to see two rings drawn on the ground: the inner ring is where full
## strength ends, the outer ring is where it has faded away to nothing. When it isn't selected
## it shows as just a faint little pole. None of it shows in the game.

enum Mode {
	LOWER,   ## Digs the ground down by Height meters
	RAISE,   ## Builds the ground up by Height meters
	FLATTEN, ## Levels the ground to this marker's own height (or the ground's average, see below)
	SMOOTH,  ## Softens bumps and sharp edges
	SQUASH,  ## Shrinks how far the ground rises above a base level: peaks get shorter but keep their shape
}

## What it does to the ground
@export var mode := Mode.FLATTEN:
	set(value):
		mode = value
		_changed()
## How far it reaches, in meters
@export_range(1.0, 300.0, 0.5) var radius := 15.0:
	set(value):
		radius = value
		_changed()
## How strongly it works: 1 = all the way, 0 = not at all
@export_range(0.0, 1.0, 0.01) var strength := 1.0:
	set(value):
		strength = value
		_changed()
## How much of the circle blends gently into the surrounding ground:
## 0 = a hard edge, 1 = a slow fade all the way from the middle
@export_range(0.0, 1.0, 0.01) var falloff := 0.4:
	set(value):
		falloff = value
		_changed()

@export_group("Raise and Lower")
## How many meters it moves the ground at full strength
@export var height := 3.0:
	set(value):
		height = value
		_changed()

@export_group("Flatten")
## Level to the average height of the ground that's already there, instead of this marker's
## own height. Handy when the marker moves with something else, like the crash site.
@export var level_to_ground := false:
	set(value):
		level_to_ground = value
		_changed()

@export_group("Squash")
## How much to shrink the height above the base: 0 = not at all, 0.5 = half as tall, 1 = all the way down
@export_range(0.0, 1.0, 0.01) var amount := 0.5:
	set(value):
		amount = value
		_changed()
## Set the base level automatically, from the lowest ground on the outer ring
@export var auto_base := true:
	set(value):
		auto_base = value
		_changed()
## The level the ground is squashed toward, in meters (used when Auto Base is off)
@export var base_height := 0.0:
	set(value):
		base_height = value
		_changed()

const MODE_COLORS := {
	Mode.LOWER: Color(0.3, 0.55, 1.0),
	Mode.RAISE: Color(1.0, 0.6, 0.25),
	Mode.FLATTEN: Color(0.4, 0.95, 0.45),
	Mode.SMOOTH: Color(0.8, 0.5, 1.0),
	Mode.SQUASH: Color(1.0, 0.4, 0.6),
}

# The area it last told the valley about, so a move can redo both where it was and where it is
var _last_area := Rect2()
var _last_spot := Vector3.INF
var _selected := false
var _selection_check := 0.0
# While dragged by its handles, the ground waits for the mouse to be let go
var _dragging := false


func _enter_tree() -> void:
	add_to_group("terrain_modifiers")
	set_notify_transform(true)


func _exit_tree() -> void:
	# Removed or deleted: the ground it was shaping goes back to normal
	if Engine.is_editor_hint() and _last_area.has_area():
		var valley = _valley()
		if valley:
			valley.request_rebuild_area(_last_area)


func _ready() -> void:
	_last_spot = _spot_that_matters()
	_last_area = area()
	if not Engine.is_editor_hint():
		hide()
		return
	refresh_rings()


## The square patch of map (x, z) this marker can change
func area() -> Rect2:
	if not is_inside_tree():
		return Rect2()
	return Rect2(global_position.x - radius, global_position.z - radius, radius * 2.0, radius * 2.0)


## How much this changes a spot `distance` meters from its middle: `strength` across the
## middle, easing smoothly to nothing at the edge (a smoothstep curve, so there's no rim)
func weight_at(distance: float) -> float:
	if distance >= radius:
		return 0.0
	return (1.0 - smoothstep(radius * (1.0 - falloff), radius, distance)) * strength


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	# Check a few times a second whether it's selected, so the rings come and go
	_selection_check -= delta
	if _selection_check <= 0.0:
		_selection_check = 0.25
		var now := _is_selected()
		if now != _selected:
			_selected = now
			_update_visibility()


## Starts a drag: until end_drag, moving or resizing this doesn't rebuild the ground
func begin_drag() -> void:
	_dragging = true


## Ends a drag. With `changed`, the ground is rebuilt once, for where it was and where it is.
func end_drag(changed: bool) -> void:
	_dragging = false
	_last_spot = _spot_that_matters()
	if changed:
		_ask_for_rebuild()
	refresh_rings()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint() and not _dragging:
		var spot := _spot_that_matters()
		if spot.distance_to(_last_spot) > 0.01:
			_last_spot = spot
			_ask_for_rebuild()


# Its position, ignoring its height unless that's the level it flattens to
func _spot_that_matters() -> Vector3:
	if not is_inside_tree():
		return Vector3.INF
	var p := global_position
	if mode != Mode.FLATTEN or level_to_ground:
		p.y = 0.0
	return p


func _changed() -> void:
	if not _dragging:
		_ask_for_rebuild()
	refresh_rings()


func _ask_for_rebuild() -> void:
	if not (Engine.is_editor_hint() and is_inside_tree()):
		return
	var valley = _valley()
	if valley:
		var now := area()
		valley.request_rebuild_area(now.merge(_last_area) if _last_area.has_area() else now)
		_last_area = now


func _valley():
	return get_tree().get_first_node_in_group("valley") if is_inside_tree() else null


# Selected itself, or something it belongs to (so selecting the crash site shows its marker)
func _is_selected() -> bool:
	if not Engine.has_singleton("EditorInterface"):
		return false
	var editor = Engine.get_singleton("EditorInterface")
	for node in editor.get_selection().get_selected_nodes():
		if node == self or node.is_ancestor_of(self):
			return true
	return false


## Redraws the rings on the ground (the valley calls this after the terrain changes)
func refresh_rings() -> void:
	if not is_node_ready() or not Engine.is_editor_hint():
		return
	var color: Color = MODE_COLORS[mode]
	var core := maxf(radius * (1.0 - falloff), 0.05)
	$InnerRing.mesh = _ring_mesh(core)
	$OuterRing.mesh = _ring_mesh(radius)
	$InnerRing.material_override = _glow(color, 0.95)
	$OuterRing.material_override = _glow(color, 0.55)
	_update_visibility()


func _update_visibility() -> void:
	if not is_node_ready():
		return
	var valley = _valley()
	var show_markers: bool = valley == null or valley.show_modifier_markers
	var color: Color = MODE_COLORS[mode]
	$InnerRing.visible = show_markers and _selected
	$OuterRing.visible = show_markers and _selected
	$Pole.visible = show_markers
	# A tall, bright pole when selected; a short, faint one otherwise
	$Pole.scale = Vector3(1.0, 1.0 if _selected else 0.4, 1.0)
	$Pole.position.y = 2.0 if _selected else 0.8
	$Pole.material_override = _glow(color, 0.9 if _selected else 0.25)


# A thin flat ribbon around the circle, laid just above the actual ground
func _ring_mesh(ring_radius: float) -> ArrayMesh:
	var valley = _valley()
	var width := clampf(ring_radius * 0.006, 0.12, 0.6)
	var segments := clampi(int(ring_radius * 2.0), 48, 256)
	var points := PackedVector3Array()
	var order := PackedInt32Array()
	var center := global_position
	for s in segments + 1:
		var direction := Vector2.from_angle(TAU * s / segments)
		for edge in [ring_radius - width * 0.5, ring_radius + width * 0.5]:
			var spot := Vector2(center.x, center.z) + direction * maxf(edge, 0.0)
			var ground: float = valley.get_height(spot.x, spot.y) if valley and valley.has_heights() else center.y
			points.append(to_local(Vector3(spot.x, ground + 0.15, spot.y)))
	for s in segments:
		var i := s * 2
		order.append_array([i, i + 1, i + 2, i + 1, i + 3, i + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_INDEX] = order
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _glow(color: Color, alpha: float) -> StandardMaterial3D:
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.albedo_color = Color(color.r, color.g, color.b, alpha)
	look.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Drawn on top of everything, so a ring behind a hill still shows
	look.no_depth_test = true
	return look
