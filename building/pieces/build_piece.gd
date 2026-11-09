class_name BuildPiece
extends StaticBody3D
## One placed building piece. It builds its look, collision and snap points from its shape
## (PieceShapes) when the piece registry makes it. Doors open and close with E.
##
## Every piece has an id that stays the same across saves, and the plot that owns it (empty for
## none; see PlotRegistry). The registry lists them all.

## How far a door swings open, in degrees
const DOOR_OPEN_DEGREES := 95.0
const DOOR_SWING_SECONDS := 0.35

## Its id, unique in this world, and the plot that owns it (empty: no plot)
var piece_id := 0
var owner_plot := ""
## What it is, and what was paid for it (all of which comes back when it's taken down)
var buildable: PieceBuildable
var paid := {}

var _def: Dictionary
var _door_open := false
var _door_angle := 0.0
# The door's swinging parts and how each one sits when closed
var _door_parts: Array = []
var _door_tween: Tween
# The plain textured box look, which only shows from far off once it has a close-up look
var _plain_looks: Array[MeshInstance3D] = []

## Beyond this distance a piece shows its plain textured box instead of its close-up look
const DETAIL_RANGE := 60.0
const DETAIL_FADE := 4.0


## Builds it from its shape. Called before it's added to the world.
func setup(piece: PieceBuildable, def: Dictionary, material: Material) -> void:
	buildable = piece
	_def = def
	name = "Piece"
	add_to_group("build_pieces")
	if piece.model_scene:
		add_child(fitted_model(piece, def))
	else:
		var look := MeshInstance3D.new()
		look.mesh = def["mesh"]
		look.material_override = material
		add_child(look)
		_plain_looks.append(look)
	if def["door_mesh"]:
		var panel := MeshInstance3D.new()
		panel.mesh = def["door_mesh"]
		panel.material_override = material
		add_child(panel)
		_door_parts.append({"node": panel, "rest": Transform3D.IDENTITY})
		_plain_looks.append(panel)
	if def.get("hearth", false):
		_make_hearth_fire()
	for part in def["collision"]:
		var solid := CollisionShape3D.new()
		solid.shape = part["shape"]
		solid.transform = part["transform"]
		add_child(solid)
		if part["door"]:
			_door_parts.append({"node": solid, "rest": part["transform"]})


## Gives it its close-up look (see PieceDetail: separate planks, logs, shakes, stones and rope),
## shown within DETAIL_RANGE; its plain textured box takes over beyond that. A door's panel gets
## its own close-up look, which swings with it. Nothing changes for a shape without one.
func dress(detail: Dictionary, material: Material) -> void:
	if detail.is_empty() or detail.get("mesh") == null and detail.get("door_mesh") == null:
		return
	for plain in _plain_looks:
		plain.visibility_range_begin = DETAIL_RANGE
		plain.visibility_range_begin_margin = DETAIL_FADE
	for key in ["mesh", "door_mesh"]:
		var mesh: Mesh = detail.get(key)
		if mesh == null:
			continue
		var near := MeshInstance3D.new()
		near.name = "Detail" if key == "mesh" else "DoorDetail"
		near.mesh = mesh
		near.material_override = material
		near.visibility_range_end = DETAIL_RANGE
		near.visibility_range_end_margin = DETAIL_FADE
		add_child(near)
		if key == "door_mesh":
			_door_parts.append({"node": near, "rest": Transform3D.IDENTITY})


## Gives its textured surface (see piece_surface.gdshader) this piece's own slight colour and
## brightness, picked from its id so it stays the same every time, and its box, for the grime
## toward its edges. Called once it has its id.
func weather() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(piece_id * 7919 + 17)
	var bright := rng.randf_range(0.92, 1.05)
	var warm := rng.randf_range(-0.035, 0.035)
	var tint := Color(bright * (1.0 + warm), bright, bright * (1.0 - warm * 1.4))
	var box := PieceShapes.bounds_of(_def)
	for child in get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).material_override is ShaderMaterial:
			var look := child as MeshInstance3D
			look.set_instance_shader_parameter("tint", tint)
			look.set_instance_shader_parameter("box_min", box.position)
			look.set_instance_shader_parameter("box_max", box.end)
			look.set_instance_shader_parameter("frame_offset", _def.get("frame_offset", 0.0))


## A piece's model, scaled evenly to fit its solid box and placed in it: standing on the box's
## floor, centred side to side, its back against the box's back (-Z). Used for the piece itself and
## its placement preview.
static func fitted_model(piece: PieceBuildable, def: Dictionary) -> Node3D:
	var model: Node3D = piece.model_scene.instantiate()
	var box := PieceShapes.bounds_of(def)
	var own := _model_bounds(model)
	if own.size.x <= 0.0 or own.size.y <= 0.0 or own.size.z <= 0.0:
		return model
	var s := minf(minf(box.size.x / own.size.x, box.size.y / own.size.y), box.size.z / own.size.z)
	var holder := Node3D.new()
	holder.name = "Model"
	holder.add_child(model)
	model.scale = Vector3.ONE * s
	var centre := own.get_center() * s
	model.position = Vector3(box.get_center().x - centre.x, box.position.y - own.position.y * s, box.position.z - own.position.z * s)
	return holder


# The box round every mesh in a model, in the model's own space
static func _model_bounds(model: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for found in model.find_children("*", "MeshInstance3D", true, false):
		var look := found as MeshInstance3D
		var xform := Transform3D.IDENTITY
		var n: Node = look
		while n != model and n is Node3D:
			xform = (n as Node3D).transform * xform
			n = n.get_parent()
		var part: AABB = xform * look.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


func display_name() -> String:
	return buildable.display_name if buildable else "Piece"


## Its snap points in the world: [{"position", "yaw", "type"}]
func world_sockets() -> Array:
	var found := []
	for socket in _def["sockets"]:
		found.append({
			"position": global_transform * (socket["position"] as Vector3),
			"yaw": global_rotation.y + socket["yaw"],
			"type": socket["type"],
		})
	return found


## A roof (or cone roof) section: standing under it counts as shelter
func is_roof() -> bool:
	return _def.get("roof", false)


## A floor or round floor wedge
func is_floor() -> bool:
	return _def.get("floor", false)


## Furniture (a bed, a shelf...): counts toward a plot's requirements by its name
func is_furniture() -> bool:
	return _def.get("furniture", false)


## Furniture that backs up flush against a wall when placed near one (bed, shelves, tool rack)
func backs_to_wall() -> bool:
	return _def.get("backs_to_wall", false)


# ---- The fireplace ----
#
# It burns all the time (no fuel yet) and warms you like a campfire: it's in the "campfires"
# group, so the player's warmth and a warm night's sleep count it.

const HEARTH_HEAT_RADIUS := 6.0

var _hearth_light: OmniLight3D
var _hearth_flame: MeshInstance3D


## A fire that's burning (only the fireplace, which always is)
func is_lit() -> bool:
	return _def.get("hearth", false)


## How close you need to be to feel its heat
func heat_radius() -> float:
	return HEARTH_HEAT_RADIUS


func _make_hearth_fire() -> void:
	add_to_group("campfires")
	_hearth_light = OmniLight3D.new()
	_hearth_light.light_color = Color(1.0, 0.62, 0.3)
	_hearth_light.light_energy = 1.8
	_hearth_light.omni_range = 7.0
	_hearth_light.shadow_enabled = true
	# Where the flames burn, inside the hearth (PieceShapes.HEARTH_FIRE); the light just in front
	var fire: Vector3 = _def.get("hearth_at", Vector3.ZERO)
	_hearth_light.position = fire + Vector3(0, 0.2, 0.4)
	add_child(_hearth_light)
	# A plain glowing flame in the hearth, flickering with the light
	_hearth_flame = MeshInstance3D.new()
	var flame := PrismMesh.new()
	flame.size = Vector3(0.3, 0.32, 0.14)
	_hearth_flame.mesh = flame
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.55, 0.15)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.45, 0.1)
	glow.emission_energy_multiplier = 2.5
	_hearth_flame.material_override = glow
	_hearth_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hearth_flame.position = fire + Vector3(0, 0.16, 0)
	add_child(_hearth_flame)


func _process(_delta: float) -> void:
	if _hearth_light == null:
		set_process(false)
		return
	var t := Time.get_ticks_msec() * 0.001 + float(piece_id)
	var flicker := sin(t * 11.0) * 0.5 + sin(t * 6.7) * 0.5
	_hearth_light.light_energy = 1.8 + flicker * 0.35
	_hearth_flame.scale = Vector3(1.0, 1.0 + flicker * 0.12, 1.0)


## The middle of its solid parts, in the world: a plot owns it if this is inside the plot
func center() -> Vector3:
	return global_transform * PieceShapes.bounds_of(_def).get_center()


## Its shape's look, collision and snap points (see PieceShapes.build)
func shape_def() -> Dictionary:
	return _def


## Lays a glow over the piece (the hammer's demolish target shows red), or takes it off (null)
func set_highlight(glow: Material) -> void:
	for look in find_children("*", "GeometryInstance3D", true, false):
		(look as GeometryInstance3D).material_overlay = glow


## Slender: a pillar, pole, beam or ladder (these only bump into each other)
func is_slender() -> bool:
	return _def.get("slender", false)


## An eave, gable overhang or eave corner: these only bump into each other (they tuck over wall
## tops and gables), and don't count as roof for shelter
func is_overhang() -> bool:
	return _def.get("overhang", false)


## A ladder: W climbs it while you look at it
func is_ladder() -> bool:
	return _def.get("ladder", false)


func is_door() -> bool:
	return not _door_parts.is_empty()


## True unless it's a door standing open
func is_closed() -> bool:
	return not (is_door() and _door_open)


## The circle of grass it keeps clear (radius 0 for none), from its origin
func clear_area() -> Dictionary:
	return {"center": _def.get("clear_center", Vector3.ZERO), "radius": _def.get("clear_radius", 0.0)}


# ---- Doors ----

func can_interact() -> bool:
	return is_door()


func get_prompt() -> String:
	return "Close Door" if _door_open else "Open Door"


func interact(_player) -> void:
	if is_door():
		set_open(not _door_open)


## Swings the door open or shut (at once, when `instantly`, for loading a save)
func set_open(open: bool, instantly := false) -> void:
	_door_open = open
	var target := DOOR_OPEN_DEGREES if open else 0.0
	if _door_tween:
		_door_tween.kill()
	if instantly:
		_set_door_angle(target)
		return
	_door_tween = create_tween()
	_door_tween.tween_method(_set_door_angle, _door_angle, target, DOOR_SWING_SECONDS).set_trans(Tween.TRANS_SINE)


# Turns the door's parts about its hinge, down its left edge
func _set_door_angle(degrees: float) -> void:
	_door_angle = degrees
	var hinge := Vector3(-(PieceShapes.DOOR_WIDTH - 0.04) / 2.0, 0, 0)
	var swing := Transform3D(Basis.IDENTITY, hinge) * Transform3D(Basis(Vector3.UP, deg_to_rad(-degrees)), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -hinge)
	for part in _door_parts:
		part["node"].transform = swing * (part["rest"] as Transform3D)


## What the save keeps of it beyond where it is (a door's open or shut)
func save_state() -> Dictionary:
	return {"open": true} if _door_open else {}


func load_state(state: Dictionary) -> void:
	if state.get("open", false):
		set_open(true, true)
