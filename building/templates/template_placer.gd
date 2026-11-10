class_name TemplatePlacer
extends Node
## Placing a template from the build menu's Buildings tab (run by the BuildPlacer, hammer out).
##
## The whole building follows the crosshair fully built, looking real, with a soft outline glow:
## green anywhere (like single pieces, it may overlap anything, and it's laid out as ghosts, which
## nobody can be in the way of), yellow (a warning, still placeable) where the ground
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
## About how many nodes of the preview's look are made per frame (see _process)
const NODES_PER_FRAME := 100
## How many of its pieces go into the world per frame once it's laid out (see _lay_out)
const PIECES_PER_FRAME := 12
## Two of its own snap points closer than this meet each other (so neither is on its outside)
const SHARED_GAP := 0.05

var registry: PieceRegistry
var plots: PlotRegistry
var pieces: ValheimPlacer
var builder: BuildPlacer

var _player: CharacterBody3D
var _buildable: TemplateBuildable
var _template: BuildingTemplate
var _look: Node3D
var _outline: Plot
var _glow: ShaderMaterial
# Its outer snap points in its own space: {"position", "yaw", "type"}, and the types of placed snap
# point any of them can meet
var _outer: Array = []
var _outer_wants := {}
# The outer snap points worked out for each template so far: BuildingTemplate -> [_outer, _outer_wants]
var _outer_cache := {}
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
# How many of the template's items the preview's look has so far, and whether it has them all
var _built := 0
var _look_ready := false
# Templates laid out whose ghosts are still going into the world: {"plot", "queue": [[Buildable,
# Transform3D], ...]}
var _laying: Array = []


func _ready() -> void:
	_player = get_parent().get_parent()
	set_physics_process(false)
	set_process(false)


func is_active() -> bool:
	return _template != null


func current() -> TemplateBuildable:
	return _buildable


func begin(buildable: TemplateBuildable) -> void:
	var timing := SpikeLog.begin()
	_begin(buildable)
	SpikeLog.end("template preview built", timing)


func _begin(buildable: TemplateBuildable) -> void:
	cancel()
	_buildable = buildable
	_template = buildable.template
	_glow = ShaderMaterial.new()
	_glow.shader = BuildPiece.GHOST_SHADER
	# Soft: a faint wash, and a glow only right at the edges, so the building's real look shows
	_glow.set_shader_parameter("fill", 0.03)
	_glow.set_shader_parameter("edge", 0.5)
	_glow.set_shader_parameter("sharpness", 5.0)
	# Its look is built a few parts per frame (see _process) and shown once it's all there
	_look = Node3D.new()
	_look.name = "TemplateLook"
	_look.visible = false
	_player.get_parent().add_child(_look)
	_built = 0
	_look_ready = _template.items.is_empty()
	_look.visible = _look_ready
	set_process(not _look_ready)
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
	# (still running while a laid-out template's ghosts are going in)
	set_process(not _laying.is_empty())


# Builds the preview's look a few parts per frame (about NODES_PER_FRAME new nodes), so choosing a
# big template doesn't freeze the game; it shows once every part is there
func _process(_delta: float) -> void:
	if not _laying.is_empty():
		var timing := SpikeLog.begin()
		_lay_out()
		SpikeLog.end("template laid out: ghosts put in the world (a few a frame)", timing)
	if _template != null and not _look_ready:
		var timing := SpikeLog.begin()
		_build_parts(NODES_PER_FRAME)
		SpikeLog.end("template preview: building its look (a few parts a frame)", timing)
	if _laying.is_empty() and (_template == null or _look_ready):
		set_process(false)


# Adds parts to the look until about this many nodes have been made (or it's finished)
func _build_parts(budget: int) -> void:
	var made := 0
	while _built < _template.items.size() and made < budget:
		var part := TemplateLook.part_for(registry, _template, _built)
		for found in part.find_children("*", "GeometryInstance3D", true, false):
			if found is GPUParticles3D:
				continue
			(found as GeometryInstance3D).material_overlay = _glow
			(found as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		made += part.find_children("*", "", true, false).size() + 1
		_look.add_child(part)
		_built += 1
	if _built >= _template.items.size():
		_look_ready = true
		_look.visible = true
		_check_in = 0
		set_process(false)


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
	if not _look_ready:
		details.append("Setting out the preview…")
	elif not _problem.is_empty():
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
	# Checked again every few frames (sooner once it's moved), not every frame it moves: checking
	# each of its pieces where it stands is too much to do every frame while you sweep it about
	_check_in -= 2 if moved else 1
	# (not until the look has all its parts: the check goes through them)
	if _check_in <= 0 and _look_ready:
		_check_in = CHECK_FRAMES
		_checked_at = _where
		var timing := SpikeLog.begin()
		_problem = _check()
		SpikeLog.end("template preview: checking where it stands", timing)
		var bad := not _problem.is_empty()
		var warned := not bad and not _warning.is_empty()
		_glow.set_shader_parameter("glow_color", BAD_GLOW if bad else (WARN_GLOW if warned else GOOD_GLOW))
		_outline.set_tint(PlotPlacer.BAD_COLOR if bad else (PlotPlacer.WARN_COLOR if warned else PlotPlacer.GOOD_COLOR))


# ---- Snapping ----

# Its snap points that don't meet another of its own pieces: the ones on its outside. The points are
# sorted into 5 cm cubes, so each only looks at the few in the cubes round it; the answer is kept
# for each template (it only changes if the template's saved again)
func _find_outer_snap_points() -> void:
	if _outer_cache.has(_template):
		_outer = _outer_cache[_template][0].duplicate()
		_outer_wants = _outer_cache[_template][1]
		return
	var all := []
	for item in _template.items:
		var buildable: Buildable = item["buildable"]
		if not buildable is PieceBuildable:
			continue
		var relative: Transform3D = item["relative"]
		var turn := relative.basis.get_euler().y
		for socket in registry.shape_of((buildable as PieceBuildable).shape)["sockets"]:
			all.append({"position": relative * (socket["position"] as Vector3), "yaw": turn + socket["yaw"], "type": socket["type"]})
	var cubes := {}
	for i in all.size():
		var cube := Vector3i(((all[i]["position"] as Vector3) / SHARED_GAP).floor())
		if not cubes.has(cube):
			cubes[cube] = []
		cubes[cube].append(i)
	for i in all.size():
		var here: Vector3 = all[i]["position"]
		var cube := Vector3i((here / SHARED_GAP).floor())
		var shared := false
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					for j in cubes.get(cube + Vector3i(dx, dy, dz), []):
						if j != i and here.distance_to(all[j]["position"]) < SHARED_GAP:
							shared = true
							break
					if shared:
						break
				if shared:
					break
			if shared:
				break
		if not shared:
			_outer.append(all[i])
	_outer_wants = PieceShapes.targets_for(_outer)
	_outer_cache[_template] = [_outer.duplicate(), _outer_wants]


# Where it goes if one of its outer snap points is close to a nearby building's snap point that
# the snap rules let it meet at its current turn (the nearest pair wins), or null. The nearby snap
# points are first sorted into 1 m squares (only the kinds its outer points can meet), so each of
# its outer points only looks at the few in the squares around it.
func _snap(where: Transform3D):
	if _outer.is_empty():
		return null
	var timing := SpikeLog.begin()
	var grid := {}
	for piece in registry.pieces_near(where.origin, _reach + SNAP_RADIUS):
		for other in piece.world_sockets():
			if not _outer_wants.has(other["type"]):
				continue
			var there: Vector3 = other["position"]
			var square := Vector2i(floori(there.x), floori(there.z))
			if not grid.has(square):
				grid[square] = []
			grid[square].append(other)
	var best_gap := SNAP_RADIUS
	var shift = null
	if not grid.is_empty():
		var squares := ceili(SNAP_RADIUS)
		for own in _outer:
			var at: Vector3 = where * (own["position"] as Vector3)
			var yaw: float = _turn + float(own["yaw"])
			var middle := Vector2i(floori(at.x), floori(at.z))
			for dz in range(-squares, squares + 1):
				for dx in range(-squares, squares + 1):
					for other in grid.get(middle + Vector2i(dx, dz), []):
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
	SpikeLog.end("template preview: snap search", timing)
	if shift == null:
		return null
	return Transform3D(where.basis, where.origin + shift)


# ---- Checking where it is ----

# Why it can't go here, or empty if it can: nothing stops it. Like single pieces it may overlap
# anything and sink into the ground, and it's laid out as ghosts, which aren't solid (anyone in one
# glides aside when it's built). Water, or steep ground under its foundations, is a warning
# (yellow). Pieces that would exactly repeat ones already there are counted (they're left out when
# it's placed).
func _check() -> String:
	_warning = ""
	_repeats = 0
	var valley = get_tree().get_first_node_in_group("valley")
	if valley and _where.origin.y < valley.global_position.y + valley.water_height():
		_warning = "In the water"
	var parts := _look.get_children()
	for i in parts.size():
		var part: Node3D = parts[i]
		if not part is BuildPiece:
			continue
		var at := _where * (_template.items[i]["relative"] as Transform3D)
		if _warning.is_empty() and part.buildable.shape.contains("foundation") and _steepness_under(at, PieceShapes.bounds_of(part.shape_def())) > MAX_SLOPE:
			_warning = "Steep ground under its foundations"
		if registry.duplicate_of(part.buildable.shape, at):
			_repeats += 1
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
	# Clicked before the preview had all its parts: finish it now, and check the spot with them
	if not _look_ready:
		_build_parts(1 << 30)
		_checked_at = _where
		_problem = _check()
	if not _problem.is_empty():
		_player.flash(_problem)
		return
	SpikeLog.note("a template laid out")
	var plot := plots.create(_template.plot_type, _where, _template.size)
	# Its ghosts go into the world PIECES_PER_FRAME at a time (see _lay_out), in the template's order
	var queue: Array = []
	for item in _template.items:
		queue.append([item["buildable"], _where * (item["relative"] as Transform3D)])
	_laying.append({"plot": plot, "queue": queue})
	_player.flash("%s laid out as ghosts. Aim at one with the hammer and click to build it (hold to keep going)" % plot.plot_name, 6.0)
	cancel()
	set_process(true)


# Puts the next few ghosts of the templates being laid out into the world; once a template's are
# all there, its plot takes in what stands inside it and its checklist is checked
func _lay_out() -> void:
	var left := PIECES_PER_FRAME
	while left > 0 and not _laying.is_empty():
		var job: Dictionary = _laying[0]
		var plot: Plot = job["plot"]
		var queue: Array = job["queue"]
		if not is_instance_valid(plot) or plot.is_queued_for_deletion():
			_laying.pop_front()
			continue
		while left > 0 and not queue.is_empty():
			var next: Array = queue.pop_front()
			var buildable: Buildable = next[0]
			var at: Transform3D = next[1]
			left -= 1
			if buildable is PieceBuildable:
				# Left out where an identical piece is already there (a shared wall, say)
				if registry.duplicate_of((buildable as PieceBuildable).shape, at):
					continue
				registry.spawn(buildable, at, {}, 0, plot.plot_id, {"ghost": true})
			else:
				builder.place_ghost_building(buildable, at, plot.plot_id)
		if queue.is_empty():
			plots.adopt(plot)
			plots.mark_dirty()
			_laying.pop_front()


## True while a laid-out template's ghosts are still going into the world
func is_laying_out() -> bool:
	return not _laying.is_empty()


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
