class_name TemplatePlacer
extends Node
## Placing a template from the build menu's Buildings tab (run by the BuildPlacer, hammer out).
##
## The whole building follows the crosshair fully built, looking real, with a soft outline glow:
## green where it can go, red only where you or a settler would be inside one of its pieces (like
## single pieces, it may overlap anything), yellow (a warning, still placeable) where the ground
## under its foundations is steep or it'd stand in water. Pieces that would exactly repeat ones
## already there (a wall shared with the building beside it) are left out. Its plot's outline shows on the
## ground round it. R turns it 90°, Alt + wheel 15°; Page Up / Page Down raise and lower it (Alt:
## finely), Backspace puts the turn and height back. Near another building it snaps into place
## where one of its outer snap points meets one of theirs (the usual snap rules, at its current
## turn).
##
## Left-click puts it down: a new plot of the template's type and size (adjustable afterwards in
## plot view) with every piece, furniture item, workbench, chest and campfire in it as a ghost, to
## be built with materials one by one (see GhostBuilder). Placing it costs nothing.

## How far the crosshair reaches for the spot, and how near a snap point must be to snap
const REACH := 24.0
const SNAP_RADIUS := 1.0
const SNAP_HEIGHT := 1.2
## The steepest ground under a foundation, in degrees
const MAX_SLOPE := 30.0
const HEIGHT_STEP := 0.25
const FINE_HEIGHT_STEP := 0.05
const FINE_TURN := PI / 12.0
const GOOD_GLOW := Color(0.3, 1.0, 0.4, 0.75)
const BAD_GLOW := Color(1.0, 0.25, 0.2, 0.85)
const WARN_GLOW := Color(1.0, 0.85, 0.25, 0.8)
## How many physics frames at most between checks of where it is (also checked whenever it moves)
const CHECK_FRAMES := 6

var registry: PieceRegistry
var plots: PlotRegistry
var pieces: PiecePlacer
var builder: BuildPlacer

var _player: CharacterBody3D
var _buildable: TemplateBuildable
var _template: BuildingTemplate
var _look: Node3D
var _outline: Plot
var _glow: ShaderMaterial
# Its outer snap points in its own space: {"position", "yaw", "type"}
var _outer: Array = []
var _reach := 6.0
var _turn := 0.0
var _height := 0.0
var _where := Transform3D.IDENTITY
var _checked_at := Transform3D()
var _check_in := 0
var _problem := ""
# Placeable, but worth knowing (water, steep ground under its foundations): shown in yellow
var _warning := ""
# How many of its pieces repeat ones already there (they're left out)
var _repeats := 0
var _snapped := false


func _ready() -> void:
	_player = get_parent().get_parent()
	set_physics_process(false)


func is_active() -> bool:
	return _template != null


func current() -> TemplateBuildable:
	return _buildable


func begin(buildable: TemplateBuildable) -> void:
	cancel()
	_buildable = buildable
	_template = buildable.template
	_glow = ShaderMaterial.new()
	_glow.shader = BuildPiece.GHOST_SHADER
	# Soft: a faint wash, and a glow only right at the edges, so the building's real look shows
	_glow.set_shader_parameter("fill", 0.03)
	_glow.set_shader_parameter("edge", 0.5)
	_glow.set_shader_parameter("sharpness", 5.0)
	_look = TemplateLook.build(registry, _template)
	for found in _look.find_children("*", "GeometryInstance3D", true, false):
		if found is GPUParticles3D:
			continue
		(found as GeometryInstance3D).material_overlay = _glow
		(found as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_player.get_parent().add_child(_look)
	_outline = Plot.new()
	_outline.setup(_template.plot_type, _template.size, true)
	_outline.plot_name = _template.template_name
	_player.get_parent().add_child(_outline)
	_outline.set_label("%s  ·  %s m" % [_template.template_name, PlotType.size_text(Vector2i(_template.size))])
	_find_outer_snap_points()
	_reach = _template.size.length() / 2.0 + 3.0
	_problem = ""
	_check_in = 0
	set_physics_process(true)


func cancel() -> void:
	if _look:
		_look.queue_free()
	if _outline:
		_outline.queue_free()
	_look = null
	_outline = null
	_template = null
	_buildable = null
	_outer.clear()
	set_physics_process(false)


## Takes the keys and clicks that mean something while placing. True if it used this one.
func handle_input(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		cancel()
		return true
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_PAGEUP or event.keycode == KEY_PAGEDOWN:
			var step := FINE_HEIGHT_STEP if event.alt_pressed else HEIGHT_STEP
			_height = snappedf(_height + step * (1.0 if event.keycode == KEY_PAGEUP else -1.0), FINE_HEIGHT_STEP)
			return true
		if event.keycode == KEY_BACKSPACE:
			_height = 0.0
			_turn = 0.0
			return true
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			_turn = wrapf(snappedf(_turn, PI / 2.0) + PI / 2.0, 0.0, TAU)
			return true
		# Finish or cancel this first (Tab opens the build menu to switch)
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			return true
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var up := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
			if event.alt_pressed:
				_turn = wrapf(_turn + FINE_TURN * up, 0.0, TAU)
			elif event.ctrl_pressed:
				_height = snappedf(_height + HEIGHT_STEP * up, FINE_HEIGHT_STEP)
			return true
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return false
		if event.button_index == MOUSE_BUTTON_LEFT:
			_place()
			return true
		if event.button_index == MOUSE_BUTTON_RIGHT:
			cancel()
			return true
	return false


## The on-screen controls and panel while placing (see HudControls)
func hud_state() -> Dictionary:
	var controls := [["Place", "LMB"], ["Rotate 90°", "R"], ["Rotate 15°", "Alt+Wheel"], ["Raise/Lower", "PgUp/PgDn"]]
	if not is_zero_approx(_height) or not is_zero_approx(_turn):
		controls.append(["Reset", "Backspace"])
	controls.append(["Cancel", "RMB"])
	var details: PackedStringArray = []
	details.append("Snapped" if _snapped else "Free")
	if not is_zero_approx(_turn):
		details.append("turned %d°" % (roundi(rad_to_deg(_turn)) % 360))
	if not is_zero_approx(_height):
		details.append("%+.2f m" % _height)
	if not _problem.is_empty():
		details.append(_problem)
	elif not _warning.is_empty():
		details.append(_warning)
	else:
		details.append("Placed as ghosts in a new %s plot" % _template.plot_type.display_name)
	if _repeats > 0 and _problem.is_empty():
		details.append("%d already there, left out" % _repeats)
	var cost: Dictionary = _template.total_cost()
	var parts: PackedStringArray = []
	for item in cost:
		parts.append("%d %s" % [cost[item], item])
	return {
		"controls": controls,
		"info": {
			"icon": _buildable.icon,
			"title": "%s (%s)" % [_template.template_name, _template.plot_type.display_name],
			"cost": "To build: " + ", ".join(parts),
			"cost_bad": false,
			"detail": "  ·  ".join(details),
			"detail_bad": not _problem.is_empty(),
			"detail_warn": _problem.is_empty() and not _warning.is_empty(),
		},
	}


func _physics_process(_delta: float) -> void:
	var spot := _crosshair_spot()
	var where := Transform3D(Basis(Vector3.UP, _turn), spot + Vector3.UP * _height)
	var snapped = _snap(where)
	_snapped = snapped != null
	if _snapped:
		where = snapped
	_where = where
	_look.global_transform = _where
	var moved := not _where.is_equal_approx(_checked_at)
	if moved:
		_outline.global_transform = _where
		_outline.rebuild()
	_check_in -= 1
	if moved or _check_in <= 0:
		_check_in = CHECK_FRAMES
		_checked_at = _where
		_problem = _check()
		var bad := not _problem.is_empty()
		var warned := not bad and not _warning.is_empty()
		_glow.set_shader_parameter("glow_color", BAD_GLOW if bad else (WARN_GLOW if warned else GOOD_GLOW))
		_outline.set_tint(PlotPlacer.BAD_COLOR if bad else (PlotPlacer.WARN_COLOR if warned else PlotPlacer.GOOD_COLOR))


# ---- Snapping ----

# Its snap points that don't meet another of its own pieces: the ones on its outside
func _find_outer_snap_points() -> void:
	var all := []
	for item in _template.items:
		var buildable: Buildable = item["buildable"]
		if not buildable is PieceBuildable:
			continue
		var relative: Transform3D = item["relative"]
		var turn := relative.basis.get_euler().y
		for socket in registry.shape_of((buildable as PieceBuildable).shape)["sockets"]:
			all.append({"position": relative * (socket["position"] as Vector3), "yaw": turn + socket["yaw"], "type": socket["type"]})
	for i in all.size():
		var shared := false
		for j in all.size():
			if i != j and (all[i]["position"] as Vector3).distance_to(all[j]["position"]) < 0.05:
				shared = true
				break
		if not shared:
			_outer.append(all[i])


# Where it goes if one of its outer snap points is close to a nearby building's snap point that
# the snap rules let it meet at its current turn (the nearest pair wins), or null
func _snap(where: Transform3D):
	if _outer.is_empty():
		return null
	var theirs := []
	for piece in registry.pieces_near(where.origin, _reach + SNAP_RADIUS):
		theirs.append_array(piece.world_sockets())
	if theirs.is_empty():
		return null
	var best_gap := SNAP_RADIUS
	var shift = null
	for own in _outer:
		var at: Vector3 = where * (own["position"] as Vector3)
		var yaw: float = _turn + float(own["yaw"])
		for other in theirs:
			var there: Vector3 = other["position"]
			var gap := Vector2(there.x - at.x, there.z - at.z).length()
			if gap >= best_gap or absf(there.y - at.y) > SNAP_HEIGHT:
				continue
			var lined_up := false
			for turn in PieceShapes.turns_for(own["type"], other["type"]):
				if absf(wrapf(float(other["yaw"]) - yaw + float(turn), -PI, PI)) < 0.03:
					lined_up = true
					break
			if lined_up:
				best_gap = gap
				shift = there - at
	if shift == null:
		return null
	return Transform3D(where.basis, where.origin + shift)


# ---- Checking where it is ----

# Why it can't go here, or empty if it can. Like single pieces it may overlap anything: only you
# or a settler inside one of its pieces stops it. Water, or steep ground under its foundations, is
# a warning (yellow). Pieces that would exactly repeat ones already there are counted (they're
# left out when it's placed).
func _check() -> String:
	_warning = ""
	_repeats = 0
	var valley = get_tree().get_first_node_in_group("valley")
	if valley and _where.origin.y < valley.global_position.y + valley.water_height():
		_warning = "In the water"
	var parts := _look.get_children()
	for i in parts.size():
		var part: Node3D = parts[i]
		var relative: Transform3D = _template.items[i]["relative"]
		var at := _where * relative
		var hit: Object = null
		if part is BuildPiece:
			var box := PieceShapes.bounds_of(part.shape_def())
			if _warning.is_empty() and part.buildable.shape.contains("foundation") and _steepness_under(at, box) > MAX_SLOPE:
				_warning = "Steep ground under its foundations"
			hit = pieces.piece_blocked(part, at)
			if registry.duplicate_of(part.buildable.shape, at):
				_repeats += 1
		else:
			hit = builder.building_blocked(part, at)
		if hit == _player:
			return "You're in the way"
		if hit:
			return "Someone's in the way"
	return ""


# How steep the ground is under a piece's footprint, in degrees (its corners and middle compared)
func _steepness_under(at: Transform3D, box: AABB) -> float:
	var points := []
	for corner in [Vector2(box.position.x, box.position.z), Vector2(box.end.x, box.position.z), Vector2(box.position.x, box.end.z), Vector2(box.end.x, box.end.z), Vector2(box.get_center().x, box.get_center().z)]:
		var p := at * Vector3(corner.x, 0, corner.y)
		p.y = Plot.ground_at(self, p.x, p.z)
		points.append(p)
	var steepest := 0.0
	for a in points.size():
		for b in range(a + 1, points.size()):
			var pa: Vector3 = points[a]
			var pb: Vector3 = points[b]
			var across := Vector2(pa.x - pb.x, pa.z - pb.z).length()
			if across > 0.3:
				steepest = maxf(steepest, rad_to_deg(atan(absf(pa.y - pb.y) / across)))
	return steepest


# ---- Placing ----

func _place() -> void:
	if not _problem.is_empty():
		_player.flash(_problem)
		return
	var plot := plots.create(_template.plot_type, _where, _template.size)
	for item in _template.items:
		var buildable: Buildable = item["buildable"]
		var at: Transform3D = _where * (item["relative"] as Transform3D)
		if buildable is PieceBuildable:
			# Left out where an identical piece is already there (a shared wall, say)
			if registry.duplicate_of((buildable as PieceBuildable).shape, at):
				continue
			registry.spawn(buildable, at, {}, 0, plot.plot_id, {"ghost": true})
		else:
			builder.place_ghost_building(buildable, at, plot.plot_id)
	plots.adopt(plot)
	plots.mark_dirty()
	_player.flash("%s laid out as ghosts. Aim at one with the hammer and click to build it (hold to keep going)" % plot.plot_name, 6.0)
	cancel()


# Where the crosshair meets the ground (the middle of the plot goes there)
func _crosshair_spot() -> Vector3:
	var camera: Camera3D = _player.camera
	var from := camera.global_position
	var to := from - camera.global_basis.z * REACH
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	var spot: Vector3 = hit["position"] if not hit.is_empty() else to
	spot.y = Plot.ground_at(self, spot.x, spot.z)
	return spot
