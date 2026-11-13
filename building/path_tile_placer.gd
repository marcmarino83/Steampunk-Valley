class_name PathTilePlacer
extends Node
## Lays paths (the build menu's Paths tab: Dirt, Gravel, Stone and Remove; see PathTileType) by
## dragging out a strip: press left click where it starts, drag, and let go where it ends. The
## strip is always PathTiles.WIDTH wide, at any angle, its length in LENGTH_STEP steps. Paths are
## only paint on the ground (see PathTiles): nothing to collide with, and nothing stops building.
## (Paths are the one piece that's sized by dragging; see CLAUDE.md.)
##
## The strip's outline shows on the ground while dragging (a circle where it would start before
## that), white, red for Remove or one you can't pay for. With snapping on (Z), either end snaps
## to a path near the crosshair, of any type: onto a strip's end, so a winding path is a chain of
## straight strips, or beside an end on the 1 m step, so strips side by side or half over each
## other make wider and layered roads. Where a strip carries on from the end of one of its own
## type, both ends there are made round, so the bend has no gap or notch. Overlapping is always
## allowed. Remove works the same way: drag over a strip (its ends snap to the strip's) and it
## clears every path type under it back to grass.

const CONTROLS := [["Drag: lay a strip", "LMB"], ["Snap", "Z"], ["Cancel", "RMB"]]
const REMOVE_CONTROLS := [["Drag: clear a strip", "LMB"], ["Snap", "Z"], ["Cancel", "RMB"]]
## How far ahead of the camera it lays, in meters
const REACH := 16.0
## Strip lengths go in these steps (m), and the shortest is one step
const LENGTH_STEP := 0.5
## Snapping: an end snaps to a spot within SNAP_REACH of the crosshair, on strips with an end
## within NEAR of it; spots beside an end are SIDE_STEP apart, out to SIDE_STEPS of them each way
const SNAP_REACH := 0.8
const NEAR := 5.0
const SIDE_STEP := 1.0
const SIDE_STEPS := 4
## The outline: its line's width, how far over the ground it's drawn, and how finely it follows
## the ground (m)
const LINE_WIDTH := 0.06
const LIFT := 0.05
const LINE_STEP := 0.25
## White for the outline, red for Remove or can't pay
const LINE_COLOR := Color(BrassStyle.HIGHLIGHT, 0.9)
const BAD_COLOR := Color(BrassStyle.BAD, 0.9)

var player: CharacterBody3D

var _type: PathTileType
var _snap := true
var _outline: MeshInstance3D
var _mesh: ImmediateMesh
# What the outline shows now, so it's only drawn again when that changes
var _drawn := []
var _aim := Vector3.ZERO
var _aim_ok := false
# Where the strip starts (pressed, or where it would start), where it ends while dragging, and
# whether each was snapped to a path
var _start := Vector2.ZERO
var _end := Vector2.ZERO
var _start_snapped := false
var _end_snapped := false
var _dragging := false


func _ready() -> void:
	set_process(false)


func begin(type: PathTileType) -> void:
	cancel()
	_type = type
	_mesh = ImmediateMesh.new()
	_outline = MeshInstance3D.new()
	_outline.mesh = _mesh
	_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.vertex_color_use_as_albedo = true
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.cull_mode = BaseMaterial3D.CULL_DISABLED
	_outline.material_override = look
	_outline.visible = false
	player.get_parent().add_child(_outline)
	set_process(true)


func cancel() -> void:
	_dragging = false
	_drawn = []
	if _outline:
		_outline.queue_free()
	_outline = null
	_mesh = null
	_type = null
	set_process(false)


func is_active() -> bool:
	return _type != null


func current() -> PathTileType:
	return _type


func handle_input(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		_cancel_drag_or_tool()
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		# Finish or cancel this before putting the hammer away
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			return true
		if event.keycode == KEY_Z:
			_snap = not _snap
			return true
	if event is InputEventMouseButton:
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		# (the wheel would change what's in hand)
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			return true
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and captured:
				_find_spot()
				_dragging = _aim_ok
			elif not event.pressed and _dragging:
				_find_spot()
				_lay()
				_dragging = false
			return true
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and captured:
			_cancel_drag_or_tool()
			return true
	return false


## What the on-screen controls show (see HudControls)
func hud_state() -> Dictionary:
	var length := _length()
	var detail := ""
	if not _aim_ok and not _dragging:
		detail = "Point at the ground"
	elif _dragging:
		detail = "Length %s m" % _meters(length)
		if _end_snapped:
			detail += "  ·  Snapped to a path"
	elif _start_snapped:
		detail = "Starts on a path"
	elif not _snap:
		detail = "Snapping off"
	if _type and _type.is_remove():
		detail += ("  ·  " if not detail.is_empty() else "") + "Clears every path type under it"
	var cost := "Free"
	var short := false
	if _type and not _type.costs.is_empty():
		if _dragging and length > 0.0:
			cost = _type.cost_text_for(length)
			short = _type.cost_for(length, player.inventory).is_empty()
		else:
			cost = _type.cost_text() + " per %s m" % _meters(PathTileType.PER_LENGTH)
			short = not _type.can_afford(player.inventory)
	var remove := _type != null and _type.is_remove()
	return {
		"controls": REMOVE_CONTROLS if remove else CONTROLS,
		"info": {
			"icon": _type.icon if _type else null,
			"title": _type.display_name if _type else "",
			"cost": cost,
			"cost_bad": short,
			"detail": detail,
			"detail_bad": not _aim_ok and not _dragging,
			"detail_warn": false,
		},
	}


func _process(_delta: float) -> void:
	var timing := SpikeLog.begin()
	_find_spot()
	_show_outline()
	SpikeLog.end("path tiles: placing", timing)


func _cancel_drag_or_tool() -> void:
	if _dragging:
		_dragging = false
	else:
		cancel()


# The strip's length as it would be laid now (0 while it's shorter than one step)
func _length() -> float:
	if not _dragging:
		return 0.0
	var length := _start.distance_to(_end)
	return length if length >= LENGTH_STEP - 0.001 else 0.0


func _lay() -> void:
	var length := _length()
	var paths := _paths()
	if length <= 0.0 or _type == null or paths == null:
		return
	var rank := _type.rank
	var cost := {}
	if not _type.is_remove():
		# (paid only if it changes the ground: laying the same strip again is free)
		if paths.has_strip(rank, _start, _end):
			return
		cost = _type.cost_for(length, player.inventory)
		if not _type.costs.is_empty() and cost.is_empty():
			player.flash("Not enough: you need %s" % _type.missing_text_for(length,
					player.inventory))
			return
	# An end carrying on from the end of a strip of this type is made round, and so is that one's
	var caps := 0
	if not _type.is_remove():
		if _joins(paths, _start):
			caps |= PathTiles.ROUND_A
		if _joins(paths, _end):
			caps |= PathTiles.ROUND_B
	if not cost.is_empty():
		player.pay(cost)
	var changed := paths.lay(rank, _start, _end, caps)
	if not changed.has_area():
		return
	for end in [[PathTiles.ROUND_A, _start], [PathTiles.ROUND_B, _end]]:
		if caps & int(end[0]):
			var rounded := paths.round_ends_at(end[1], rank)
			if rounded.has_area():
				changed = changed.merge(rounded)
	player.report_progress("Build", _type.display_name)
	var valley = get_tree().get_first_node_in_group("valley")
	var foliage = valley.get_node_or_null("Foliage") if valley else null
	if foliage:
		if _type.is_remove():
			foliage.regrow_plants_in(changed)
		else:
			foliage.hide_plants_on_paths(changed)


# True if a strip of this type already ends at this spot
func _joins(paths: PathTiles, spot: Vector2) -> bool:
	for strip in paths.strips_near(spot, PathTiles.SAME_SPOT):
		if int(strip["rank"]) == _type.rank:
			return true
	return false


# Where the strip would start (not dragging) or end (dragging): under the crosshair, or
# (snapping) on the nearest path spot to it. A free end keeps the strip's length on its step.
func _find_spot() -> void:
	_aim_ok = _find_aim()
	if not _aim_ok:
		return
	var free := Vector2(_aim.x, _aim.z)
	var snapped := _snap_spot(free)
	if not _dragging:
		_start_snapped = snapped != Vector2.INF
		_start = snapped if _start_snapped else free
		_end = _start
		return
	_end_snapped = snapped != Vector2.INF and snapped.distance_to(_start) >= LENGTH_STEP - 0.001
	if _end_snapped:
		_end = snapped
		return
	var reach := free - _start
	var length := snappedf(reach.length(), LENGTH_STEP)
	_end = _start + reach.normalized() * length if reach.length() > 0.001 else _start


# The path spot nearest this one within SNAP_REACH (Vector2.INF if none, or snapping's off): a
# strip's end, or beside it on the SIDE_STEP
func _snap_spot(spot: Vector2) -> Vector2:
	var paths := _paths()
	if not _snap or paths == null:
		return Vector2.INF
	var best := Vector2.INF
	var best_gap := SNAP_REACH
	for strip in paths.strips_near(spot, NEAR):
		var a: Vector2 = strip["a"]
		var b: Vector2 = strip["b"]
		var side := (b - a).normalized().orthogonal()
		for end: Vector2 in [a, b]:
			for step in range(-SIDE_STEPS, SIDE_STEPS + 1):
				var candidate := end + side * SIDE_STEP * step
				var gap := candidate.distance_to(spot)
				if gap < best_gap:
					best_gap = gap
					best = candidate
	return best


# The outline on the ground: the strip while dragging, or a circle where it would start
func _show_outline() -> void:
	if _outline == null:
		return
	var show := _aim_ok or _dragging
	_outline.visible = show
	if not show:
		return
	var bad := _type.is_remove()
	var length := _length()
	if not bad and not _type.costs.is_empty():
		bad = (_type.cost_for(length, player.inventory).is_empty() if length > 0.0
				else not _type.can_afford(player.inventory))
	var paths := _paths()
	var round_a := false
	var round_b := false
	if paths and not _type.is_remove():
		round_a = _joins(paths, _start)
		round_b = _joins(paths, _end)
	var wanted := [_start, _end if length > 0.0 else _start, round_a, round_b, bad]
	if wanted == _drawn:
		return
	_drawn = wanted
	var points: PackedVector2Array
	if length > 0.0:
		points = _strip_outline(_start, _end, round_a, round_b)
	else:
		points = _arc(_start, Vector2.RIGHT, TAU)
		points.append(points[0])
	_draw_line(points, BAD_COLOR if bad else LINE_COLOR)


# The strip's outline (x, z), closed: along one side, round the b end, back along the other side,
# round the a end
static func _strip_outline(a: Vector2, b: Vector2, round_a: bool,
		round_b: bool) -> PackedVector2Array:
	var half := PathTiles.WIDTH / 2.0
	var along := (b - a).normalized()
	var side := along.orthogonal()
	var points := PackedVector2Array()
	points.append(a + side * half)
	points.append(b + side * half)
	if round_b:
		points.append_array(_arc(b, side, -PI))
	points.append(b - side * half)
	points.append(a - side * half)
	if round_a:
		points.append_array(_arc(a, -side, -PI))
	points.append(a + side * half)
	return points


# Points round a circle of the strip's width about `middle`, from direction `from`, turning
# `sweep` radians
static func _arc(middle: Vector2, from: Vector2, sweep: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var count := 24 if absf(sweep) > PI else 12
	for i in count + 1:
		points.append(middle + from.rotated(sweep * i / count) * PathTiles.WIDTH / 2.0)
	return points


# Draws a line through these points (x, z) just over the ground, following its height
func _draw_line(points: PackedVector2Array, color: Color) -> void:
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_mesh.surface_set_color(color)
	for i in points.size() - 1:
		var from := points[i]
		var to := points[i + 1]
		var pieces := maxi(1, ceili(from.distance_to(to) / LINE_STEP))
		var across := (to - from).normalized().orthogonal() * LINE_WIDTH / 2.0
		for k in pieces:
			var p0 := from.lerp(to, float(k) / pieces)
			var p1 := from.lerp(to, float(k + 1) / pieces)
			var y0 := Plot.ground_at(player, p0.x, p0.y) + LIFT
			var y1 := Plot.ground_at(player, p1.x, p1.y) + LIFT
			var c0 := Vector3(p0.x + across.x, y0, p0.y + across.y)
			var c1 := Vector3(p0.x - across.x, y0, p0.y - across.y)
			var c2 := Vector3(p1.x + across.x, y1, p1.y + across.y)
			var c3 := Vector3(p1.x - across.x, y1, p1.y - across.y)
			for corner in [c0, c1, c2, c2, c1, c3]:
				_mesh.surface_add_vertex(corner)
	_mesh.surface_end()


# Where the crosshair meets the ground within reach, looking past anything that isn't the ground
func _find_aim() -> bool:
	var camera: Camera3D = player.camera
	var from := camera.global_position
	var to := from - camera.global_basis.z * REACH
	var space := player.get_world_3d().direct_space_state
	var skip: Array[RID] = [player.get_rid()]
	for i in 8:
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = skip
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return false
		if (hit["collider"] as Node).is_in_group("terrain_ground"):
			_aim = hit["position"]
			return true
		skip.append(hit["rid"])
	return false


func _paths() -> PathTiles:
	var valley = get_tree().get_first_node_in_group("valley")
	return valley.path_tiles if valley else null


# "4", "6.5"
static func _meters(value: float) -> String:
	return str(snappedf(value, 0.1)).trim_suffix(".0")
