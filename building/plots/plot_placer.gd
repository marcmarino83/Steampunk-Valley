class_name PlotPlacer
extends Node
## Drawing, moving and resizing plots, with the hammer out (run by the BuildPlacer):
##
##   - Drawing: click one corner on the ground, move, and click the opposite corner. The rectangle
##     stretches between them in 1 m steps, showing its size ("8 × 6 m"). Before the first click,
##     R turns the drawing direction 90° (Alt + wheel 15°), to line plots up with buildings. Under
##     the type's smallest size it shows red, with that size in its label, and won't place.
##   - Moving (the plot panel's Move plot, or M while it's open): the plot and everything it owns
##     lift into a see-through preview that follows the crosshair, turning about its middle like a
##     piece being placed: the wheel 5° a notch, Alt + wheel 1°, R back to how it stood; Page Up /
##     Page Down raise and lower the whole building (0.25 m, 0.05 m with Alt; no limit), Backspace
##     back to where it would sit; the panel shows "Turn 30° · Height +0.75 m". Nothing
##     stops it: its pieces may overlap other buildings and plots and sink into the ground as far as
##     you like, and you or a settler standing where it lands glide aside (see PeopleMover); steep
##     ground is only a warning (yellow). Left-click puts it all down there. Pieces belonging to
##     other plots never move, even joined to it (a shared wall stays with its own plot). Settlers
##     keep their jobs and beds there.
##   - Resizing, in plot view: aim at an edge or corner (it lights up), hold left-click and drag.
##     The outline follows in 1 m steps, never below the type's smallest size. Things the plot owns
##     that would end up outside glow red; letting go asks first, then takes them down and refunds
##     them: into town storage first (see TownStorage), then your inventory, then a bundle at your
##     feet.
##
## Right-click or Esc cancels any of them.

enum Mode { NONE, DRAW, MOVE, RESIZE }

## How far the crosshair reaches for a spot on the ground
const REACH := 24.0
## The steepest ground a moved plot can go on, in degrees
const MAX_SLOPE := 30.0
## How close to an edge (in meters) the crosshair must be to grab it, and how far past its ends
const EDGE_GRAB := 1.0
const GOOD_COLOR := Color(0.3, 1.0, 0.4)
const BAD_COLOR := Color(1.0, 0.25, 0.2)
const LABEL_GOOD := Color(0.8, 1.0, 0.75)
const LABEL_BAD := Color(1.0, 0.55, 0.45)
const GHOST_GOOD := Color(0.25, 1.0, 0.35, 0.4)
const GHOST_BAD := Color(1.0, 0.2, 0.15, 0.4)
const GHOST_WARN := Color(BrassStyle.WARN, 0.4)
const WARN_COLOR := BrassStyle.WARN
const OUTSIDE_GLOW := Color(1.0, 0.15, 0.1, 0.5)
const FINE_TURN := PI / 12.0
## Turning a plot being moved: a wheel notch, and with Alt
const MOVE_TURN := PI / 36.0
const MOVE_FINE_TURN := PI / 180.0

var plots: PlotRegistry
var pieces: ValheimPlacer
## Raising and lowering a building being moved, in meters: a press, and with Alt held
const HEIGHT_STEP := 0.25
const FINE_HEIGHT_STEP := 0.05
var builder: BuildPlacer

var _player: CharacterBody3D
var _mode := Mode.NONE
var _type: PlotType
var _size := Vector2.ZERO
var _turn := 0.0
# Moving: how far the whole building is raised (+) or lowered (-) from where it would sit (Page Up /
# Page Down, Backspace back to 0); no limit either way
var _height := 0.0
var _preview: Plot
var _problem := ""
# Moving: worth knowing but not stopping it (steep ground), shown in yellow
var _warning := ""
# Drawing: the drawing direction (kept from one plot to the next, to line them up), and the first
# corner once it's clicked
var _draw_turn := 0.0
var _corner := Vector3.ZERO
var _has_corner := false
var _big_enough := false
# Moving and resizing: the plot, what it owns, and where each of those sits relative to the plot
var _plot: Plot
var _items: Array = []
var _relative: Array[Transform3D] = []
var _ghost_root: Node3D
var _ghost: StandardMaterial3D
var _where := Transform3D.IDENTITY
var _check_in := 0
var _checked_at := Transform3D()
var _skip: Array[RID] = []
# Resizing: which edges are being dragged (Plot.RIGHT... bits), where the drag started (in the
# plot's own x, z), the plot's sides then and now, how far the middle has moved, what would end up
# outside, and whether we're waiting for the player to confirm
var _edges := 0
var _grab := Vector2.ZERO
var _start_lo := Vector2.ZERO
var _start_hi := Vector2.ZERO
var _offset := Vector2.ZERO
var _outside: Array = []
var _asking := false
var _outside_glow: StandardMaterial3D
# Plot view, not placing anything: the plot and edges the crosshair is on (to drag), if any
var _hover_plot: Plot
var _hover_edges := 0


func _ready() -> void:
	_player = get_parent().get_parent()
	set_physics_process(false)


func is_active() -> bool:
	return _mode != Mode.NONE


## The plot type being drawn (null if not drawing one)
func placing_type() -> PlotType:
	return _type if _mode == Mode.DRAW else null


## Starts drawing a new plot of this type
func begin_new(type: PlotType) -> void:
	cancel()
	_mode = Mode.DRAW
	_type = type
	_has_corner = false
	_size = Vector2.ONE
	_preview = _make_preview(type, _size)
	set_physics_process(true)


## Lifts a plot and everything it owns, to put down somewhere else
func begin_move(plot: Plot) -> void:
	cancel()
	_mode = Mode.MOVE
	_plot = plot
	_type = plot.plot_type
	_size = plot.size
	_turn = 0.0
	_height = 0.0
	_items = plots.owned_items(plot, true)
	_relative.clear()
	_skip.clear()
	var from := plot.global_transform.affine_inverse()
	_ghost = StandardMaterial3D.new()
	_ghost.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost_root = Node3D.new()
	_player.get_parent().add_child(_ghost_root)
	for item in _items:
		var relative: Transform3D = from * item.global_transform
		_relative.append(relative)
		var copy := _ghost_of(item)
		copy.transform = relative
		_ghost_root.add_child(copy)
		item.visible = false
		_skip.append_array(_rids_of(item))
	plot.set_shown(false)
	_preview = _make_preview(_type, _size)
	_preview.set_label(plot.plot_name, LABEL_GOOD)
	_where = plot.global_transform
	_check_in = 0
	set_physics_process(true)


## Plot view, nothing being placed: lights up the edge or corner of a plot the crosshair is on,
## ready to drag (call every frame; `active` false clears it)
func hover(active: bool) -> void:
	var found := _edge_under_crosshair() if active and _mode == Mode.NONE else {}
	var plot: Plot = found.get("plot")
	var edges: int = found.get("edges", 0)
	if is_instance_valid(_hover_plot) and (_hover_plot != plot or edges == 0):
		_hover_plot.highlight_edges = 0
	_hover_plot = plot
	_hover_edges = edges
	if plot:
		plot.highlight_edges = edges


## True while the crosshair is on a plot's edge or corner that left-click would drag
func can_grab() -> bool:
	return _hover_edges != 0 and is_instance_valid(_hover_plot)


## Left-click pressed in plot view: starts dragging the edge or corner under the crosshair, if
## any. True if it did.
func try_grab() -> bool:
	if not can_grab():
		return false
	var plot := _hover_plot
	var edges := _hover_edges
	plot.highlight_edges = 0
	_hover_plot = null
	_hover_edges = 0
	cancel()
	_mode = Mode.RESIZE
	_plot = plot
	_type = plot.plot_type
	_size = plot.size
	_edges = edges
	_grab = plot.to_local_2d(_crosshair_spot())
	_start_hi = plot.size / 2.0
	_start_lo = -plot.size / 2.0
	_offset = Vector2.ZERO
	_items = plots.owned_items(plot, true)
	_outside.clear()
	_outside_glow = StandardMaterial3D.new()
	_outside_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outside_glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_outside_glow.albedo_color = OUTSIDE_GLOW
	# The real plot steps aside for the preview
	plot.set_shown(false)
	_preview = _make_preview(_type, _size)
	_preview.global_transform = plot.global_transform
	_preview.highlight_edges = edges
	set_physics_process(true)
	return true


func cancel() -> void:
	if _mode == Mode.MOVE and is_instance_valid(_plot):
		for item in _items:
			if is_instance_valid(item):
				item.visible = true
		_plot.set_shown(true)
	if _mode == Mode.RESIZE:
		_set_outside([])
		if is_instance_valid(_plot):
			_plot.set_shown(true)
	if _preview:
		_preview.queue_free()
	if _ghost_root:
		_ghost_root.queue_free()
	_preview = null
	_ghost_root = null
	_plot = null
	_items.clear()
	_relative.clear()
	_skip.clear()
	_mode = Mode.NONE
	_asking = false
	set_physics_process(false)


## Takes the keys and clicks that mean something now. Returns true if it used this one.
func handle_input(event: InputEvent) -> bool:
	if _asking:
		return true
	if event.is_action_pressed("ui_cancel"):
		cancel()
		return true
	# Moving: Page Up / Page Down raise and lower the whole building (repeating while held), 0.25 m
	# a press or 0.05 m with Alt, as for placing pieces; Backspace puts it back where it would sit
	if _mode == Mode.MOVE and event is InputEventKey and event.pressed:
		if event.keycode == KEY_PAGEUP or event.keycode == KEY_PAGEDOWN:
			var step := FINE_HEIGHT_STEP if event.alt_pressed else HEIGHT_STEP
			_height = snappedf(_height + step * (1.0 if event.keycode == KEY_PAGEUP else -1.0), FINE_HEIGHT_STEP)
			return true
		if event.keycode == KEY_BACKSPACE:
			_height = 0.0
			return true
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R and _mode == Mode.DRAW and not _has_corner:
			_draw_turn = wrapf(_draw_turn + PI / 2.0, 0.0, TAU)
			return true
		if event.keycode == KEY_R and _mode == Mode.MOVE:
			_turn = 0.0
			return true
		# Finish or cancel this before putting the hammer away. Drawing a new plot, Tab opens the
		# build menu to switch; moving or resizing, it waits.
		if (event.keycode == KEY_TAB and _mode != Mode.DRAW) or (event.keycode >= KEY_1 and event.keycode <= KEY_9):
			return true
	# Letting go of a dragged edge: resize (asking first if pieces would be removed)
	if _mode == Mode.RESIZE and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_confirm_resize()
		return true
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var up := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
			# Alt + wheel turns the drawing direction finely, before the first corner
			if _mode == Mode.DRAW and event.alt_pressed and not _has_corner:
				_draw_turn = wrapf(_draw_turn + FINE_TURN * up, 0.0, TAU)
			# Moving: the wheel turns it 5° a notch, Alt + wheel 1°
			elif _mode == Mode.MOVE:
				_turn = wrapf(_turn + (MOVE_FINE_TURN if event.alt_pressed else MOVE_TURN) * up, 0.0, TAU)
			return true
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return false
		if event.button_index == MOUSE_BUTTON_LEFT:
			match _mode:
				Mode.DRAW:
					_draw_click()
				Mode.MOVE:
					_finish_move()
			return true
		if event.button_index == MOUSE_BUTTON_RIGHT:
			cancel()
			return true
	return false


## What the on-screen controls show (see HudControls)
func hud_state() -> Dictionary:
	match _mode:
		Mode.DRAW:
			var controls := [["Opposite corner", "LMB"], ["Cancel", "RMB"]] if _has_corner else [["First corner", "LMB"], ["Rotate 90°", "R"], ["Rotate 15°", "Alt+Wheel"], ["Cancel", "RMB"]]
			var cost := "%s m" % _size_text(_size) if _has_corner else "Click a corner"
			var detail := "At least %s m  ·  Needs %s" % [PlotType.size_text(_type.min_size), _type.requirements_text()]
			var taken := _already_one()
			if taken:
				detail = "The village already has a %s (one per village)" % _type.display_name
			return {
				"controls": controls,
				"info": {
					"title": "%s plot" % _type.display_name,
					"cost": cost,
					"cost_bad": _has_corner and not _big_enough,
					"detail": detail,
					"detail_bad": taken,
				},
			}
		Mode.MOVE:
			var turn := "Turn %d° · Height %+.2f m" % [roundi(rad_to_deg(_turn)) % 360, _height]
			var controls := [["Put down", "LMB"], ["Turn 5° / 1°", "Wheel / Alt+Wheel"], ["Reset turn", "R"], ["Raise/Lower", "PgUp/PgDn"]]
			if not is_zero_approx(_height):
				controls.append(["Reset height", "Backspace"])
			controls.append(["Cancel", "RMB / Esc"])
			return {
				"controls": controls,
				"info": {
					"title": "Moving %s" % _plot.plot_name,
					"cost": "%d pieces" % _items.size(),
					"detail": turn + "  ·  " + (_problem if not _problem.is_empty() else (_warning if not _warning.is_empty() else "Its own pieces move with it; other plots' pieces stay")),
					"detail_bad": not _problem.is_empty(),
					"detail_warn": _problem.is_empty() and not _warning.is_empty(),
				},
			}
		Mode.RESIZE:
			# (the smallest it can be shows here, while resizing, rather than in its panel)
			var detail := "Let go to resize  ·  min %s m" % _size_text(Vector2(_plot.plot_type.min_size))
			if not _outside.is_empty():
				detail = "%d %s outside will be removed" % [_outside.size(), "piece" if _outside.size() == 1 else "pieces"]
			return {
				"controls": [["Resize", "Release LMB"], ["Cancel", "RMB"]],
				"info": {
					"title": "Resizing %s" % _plot.plot_name,
					"cost": "%s m" % _size_text(_size),
					"detail": detail,
					"detail_bad": not _outside.is_empty(),
				},
			}
	return {"controls": [], "info": {}}


func _physics_process(_delta: float) -> void:
	match _mode:
		Mode.DRAW:
			_update_drawing()
		Mode.MOVE:
			var spot := _crosshair_spot()
			_where = Transform3D(Basis(Vector3.UP, _plot.global_rotation.y + _turn), spot + Vector3.UP * _height)
			_ghost_root.global_transform = _where
			_preview.global_transform = _where
			# Checked every few frames, and soon after it stops moving (checking every piece is too
			# much to do every frame while it's swept about)
			var moved := not _where.is_equal_approx(_checked_at)
			_check_in -= 1
			if _check_in <= 0 or (moved and _check_in <= 2):
				_check_in = 6
				_checked_at = _where
				var timing := SpikeLog.begin()
				_problem = _move_problem()
				SpikeLog.end("moving a plot: checking where it would go", timing)
			var bad := not _problem.is_empty()
			var warned := not bad and not _warning.is_empty()
			_ghost.albedo_color = GHOST_BAD if bad else (GHOST_WARN if warned else GHOST_GOOD)
			_preview.set_tint(BAD_COLOR if bad else (WARN_COLOR if warned else GOOD_COLOR))
			_preview.rebuild()
		Mode.RESIZE:
			if _asking:
				return
			_update_drag()
			_preview.global_transform = _resized_transform()
			_preview.size = _size
			_preview.set_tint(BAD_COLOR if not _outside.is_empty() else GOOD_COLOR)
			_preview.set_label("%s m  ·  min %s m" % [_size_text(_size), _size_text(Vector2(_plot.plot_type.min_size))], LABEL_BAD if not _outside.is_empty() else LABEL_GOOD)
			_preview.rebuild()


# ---- Drawing ----

# Before the first click: a 1 m square marks the corner and the drawing direction. After it: the
# rectangle from that corner to the crosshair, in whole meters.
func _update_drawing() -> void:
	var spot := _crosshair_spot()
	var basis := Basis(Vector3.UP, _draw_turn)
	if not _has_corner:
		_size = Vector2.ONE
		var middle := spot + basis * Vector3(0.5, 0, 0.5)
		middle.y = Plot.ground_at(self, middle.x, middle.z)
		_preview.global_transform = Transform3D(basis, middle)
		_preview.size = _size
		_preview.set_tint(GOOD_COLOR)
		_preview.set_label("Click a corner", LABEL_GOOD)
		_preview.rebuild()
		return
	var across := basis.inverse() * (spot - _corner)
	var width := maxf(roundf(absf(across.x)), 1.0)
	var depth := maxf(roundf(absf(across.z)), 1.0)
	var sx := 1.0 if across.x >= 0.0 else -1.0
	var sz := 1.0 if across.z >= 0.0 else -1.0
	_size = Vector2(width, depth)
	var middle := _corner + basis * Vector3(sx * width / 2.0, 0, sz * depth / 2.0)
	middle.y = Plot.ground_at(self, middle.x, middle.z)
	_big_enough = width >= _type.min_size.x and depth >= _type.min_size.y
	_preview.global_transform = Transform3D(basis, middle)
	_preview.size = _size
	_preview.set_tint(GOOD_COLOR if _big_enough else BAD_COLOR)
	if _big_enough:
		_preview.set_label("%s m" % _size_text(_size), LABEL_GOOD)
	else:
		_preview.set_label("%s m  ·  at least %s m" % [_size_text(_size), _size_text(Vector2(_type.min_size))], LABEL_BAD)
	_preview.rebuild()


# True if this is a one-per-village type (the Village Center) and the village has one already
func _already_one() -> bool:
	return _type.one_per_village and not plots.plots_of(_type.display_name).is_empty()


func _draw_click() -> void:
	if not _has_corner:
		_corner = _crosshair_spot()
		_has_corner = true
		return
	if not _big_enough:
		_player.flash("A %s needs at least %s m" % [_type.display_name, _size_text(Vector2(_type.min_size))])
		return
	if _already_one():
		_player.flash("The village already has a %s (one per village)" % _type.display_name)
		return
	var plot := plots.create(_type, _preview.global_transform, _size)
	plots.adopt(plot)
	_player.flash("%s marked out. Plot view [P] shows it; press E inside it for its checklist" % plot.plot_name)
	cancel()


# ---- Moving ----

# Why the plot can't go where the preview is, or empty if it can: nothing stops it. Its pieces may
# overlap other buildings (pieces, furniture, workbenches, chests, campfires) and plots and sink
# into the ground as far as you like, and anyone standing where it lands glides aside (see
# _finish_move). Steep ground is a warning, in yellow.
func _move_problem() -> String:
	_warning = "Steep ground here" if _slope_under(_where, _size) > MAX_SLOPE else ""
	return ""


func _finish_move() -> void:
	# (checked here if it moved since the last check: the steep-ground warning)
	if not _where.is_equal_approx(_checked_at):
		_checked_at = _where
		_problem = _move_problem()
	var valley = get_tree().get_first_node_in_group("valley")
	var placed: Array = _items.duplicate()
	for i in _items.size():
		var item: Node3D = _items[i]
		if not is_instance_valid(item):
			continue
		var zones := _clear_zones(item)
		for zone in zones:
			if valley:
				valley.remove_clear_zone(zone)
		item.global_transform = _where * _relative[i]
		item.visible = true
		for zone in zones:
			if valley:
				valley.add_clear_zone(zone)
	var plot := _plot
	plot.global_transform = _where
	plot.set_shown(true)
	plot.rebuild()
	_items.clear()
	_mode = Mode.NONE
	cancel()
	plots.mark_dirty()
	# Corner posts, ridge logs and lips are worked out again for where the pieces are now (settlers'
	# paths follow on their own; their jobs and beds go by the plot's id, which stays)
	if plots.pieces:
		plots.pieces.changed.emit()
	# Anyone standing where it landed glides aside
	PeopleMover.clear_from(placed)
	_player.flash("Moved %s" % plot.plot_name)


# The steepest the ground gets under a plot, in degrees, measured a meter at a time
func _slope_under(where: Transform3D, plot_size: Vector2) -> float:
	var steepest := 0.0
	var cols := maxi(roundi(plot_size.x), 1)
	var rows := maxi(roundi(plot_size.y), 1)
	var heights := []
	for r in rows + 1:
		var row := []
		for c in cols + 1:
			var p := where * Vector3(-plot_size.x / 2.0 + plot_size.x * c / cols, 0, -plot_size.y / 2.0 + plot_size.y * r / rows)
			row.append(Plot.ground_at(self, p.x, p.z))
		heights.append(row)
	for r in rows + 1:
		for c in cols + 1:
			if c < cols:
				steepest = maxf(steepest, rad_to_deg(atan(absf(heights[r][c + 1] - heights[r][c]) / (plot_size.x / cols))))
			if r < rows:
				steepest = maxf(steepest, rad_to_deg(atan(absf(heights[r + 1][c] - heights[r][c]) / (plot_size.y / rows))))
	return steepest


# ---- Resizing by dragging ----

# The plot edge (or corner: two edges) nearest the crosshair, within EDGE_GRAB: {"plot", "edges"}
func _edge_under_crosshair() -> Dictionary:
	var spot := _crosshair_spot()
	var best := {}
	var best_gap := EDGE_GRAB
	for plot in plots.all_plots():
		var local: Vector2 = plot.to_local_2d(spot)
		var half: Vector2 = plot.size / 2.0
		if absf(local.x) > half.x + EDGE_GRAB or absf(local.y) > half.y + EDGE_GRAB:
			continue
		var edges := 0
		var gap := INF
		for side in [[local.x - half.x, Plot.RIGHT], [-local.x - half.x, Plot.LEFT], [local.y - half.y, Plot.FRONT], [-local.y - half.y, Plot.BACK]]:
			var d := absf(float(side[0]))
			if d <= EDGE_GRAB:
				edges |= int(side[1])
				gap = minf(gap, d)
		if edges != 0 and gap < best_gap:
			best = {"plot": plot, "edges": edges}
			best_gap = gap
	return best


# The dragged edges follow the crosshair in whole meters, never closer together than the type's
# smallest size (or the plot's own size, if an older plot is smaller than that)
func _update_drag() -> void:
	var moved := _plot.to_local_2d(_crosshair_spot()) - _grab
	var step := Vector2(roundf(moved.x), roundf(moved.y))
	var smallest := Vector2(minf(_type.min_size.x, _plot.size.x), minf(_type.min_size.y, _plot.size.y))
	var lo := _start_lo
	var hi := _start_hi
	if _edges & Plot.RIGHT:
		hi.x = maxf(_start_hi.x + step.x, lo.x + smallest.x)
	if _edges & Plot.LEFT:
		lo.x = minf(_start_lo.x + step.x, hi.x - smallest.x)
	if _edges & Plot.FRONT:
		hi.y = maxf(_start_hi.y + step.y, lo.y + smallest.y)
	if _edges & Plot.BACK:
		lo.y = minf(_start_lo.y + step.y, hi.y - smallest.y)
	var new_size := hi - lo
	var new_offset := (hi + lo) / 2.0
	if new_size != _size or new_offset != _offset:
		_size = new_size
		_offset = new_offset
		_update_outside()


func _resized_transform() -> Transform3D:
	var xform := _plot.global_transform
	var middle := xform * Vector3(_offset.x, 0, _offset.y)
	middle.y = Plot.ground_at(self, middle.x, middle.z)
	return Transform3D(xform.basis, middle)


# What the plot owns that the resized plot wouldn't contain: those glow red
func _update_outside() -> void:
	var outside := []
	var half := _size / 2.0
	for item in _items:
		if not is_instance_valid(item):
			continue
		var local := _plot.to_local_2d(plots.center_of(item)) - _offset
		if absf(local.x) > half.x + 0.001 or absf(local.y) > half.y + 0.001:
			outside.append(item)
	_set_outside(outside)


func _set_outside(outside: Array) -> void:
	for item in _outside:
		if is_instance_valid(item):
			_glow(item, null)
	_outside = outside
	for item in _outside:
		_glow(item, _outside_glow)


func _confirm_resize() -> void:
	if _size == _plot.size and _offset == Vector2.ZERO:
		cancel()
		return
	if _outside.is_empty():
		_apply_resize()
		return
	_asking = true
	var count := _outside.size()
	_player.ask_confirm("%d %s will be removed and refunded to your storage. Proceed?" % [count, "piece" if count == 1 else "pieces"],
			func():
				_asking = false
				_apply_resize(),
			func(): cancel())


func _apply_resize() -> void:
	var plot := _plot
	var refund := {}
	for item in _outside:
		if is_instance_valid(item):
			_glow(item, null)
			var got: Dictionary = builder.take_down(item)
			for thing in got:
				refund[thing] = int(refund.get(thing, 0)) + int(got[thing])
	_outside.clear()
	plot.global_transform = _resized_transform()
	plot.size = _size
	_mode = Mode.NONE
	cancel()
	plot.set_shown(true)
	plot.rebuild()
	plots.adopt(plot)
	plots.mark_dirty()
	var message := "%s is now %s m" % [plot.plot_name, _size_text(plot.size)]
	if not refund.is_empty():
		# Into town storage first, then your inventory, then a bundle at your feet
		var rest: Dictionary = plots.town.store(refund)
		var stored := {}
		for item in refund:
			if not rest.has(item):
				stored[item] = refund[item]
		var left: Dictionary = _player.give_or_drop(rest, _player.global_position) if not rest.is_empty() else {}
		var parts: PackedStringArray = []
		if not stored.is_empty():
			parts.append("%s to town storage" % _items_text(stored))
		var carried := {}
		for item in rest:
			if not left.has(item):
				carried[item] = rest[item]
		if not carried.is_empty():
			parts.append("%s to you" % _items_text(carried))
		if not left.is_empty():
			parts.append("backpack full: %s left at your feet" % _items_text(left))
		message += " (refunded %s)" % "; ".join(parts)
	_player.flash(message)


# ---- Helpers ----

func _make_preview(type: PlotType, plot_size: Vector2) -> Plot:
	var preview := Plot.new()
	preview.setup(type, plot_size, true)
	preview.plot_name = type.display_name
	_player.get_parent().add_child(preview)
	return preview


# Where the crosshair meets the ground (or the ground under the end of its reach), passing
# through anything being moved
func _crosshair_spot() -> Vector3:
	var camera: Camera3D = _player.camera
	var from := camera.global_position
	var to := from - camera.global_basis.z * REACH
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var skip: Array[RID] = [_player.get_rid()]
	skip.append_array(_skip)
	query.exclude = skip
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	var spot: Vector3 = hit["position"] if not hit.is_empty() else to
	spot.y = Plot.ground_at(self, spot.x, spot.z)
	return spot


# A see-through copy of a piece or building's look, for the move preview
func _ghost_of(item: Node3D) -> Node3D:
	var copy := Node3D.new()
	var from := item.global_transform.affine_inverse()
	for look in item.find_children("*", "MeshInstance3D", true, false):
		var mesh_look := look as MeshInstance3D
		if not mesh_look.is_visible_in_tree() and item.visible:
			continue
		var ghost := MeshInstance3D.new()
		ghost.mesh = mesh_look.mesh
		ghost.transform = from * mesh_look.global_transform
		ghost.material_override = _ghost
		ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		copy.add_child(ghost)
	return copy


# The physics bodies of a piece or building, so moving it doesn't count it as in its own way
func _rids_of(item: Node) -> Array[RID]:
	var found: Array[RID] = []
	if item is CollisionObject3D:
		found.append(item.get_rid())
	for body in item.find_children("*", "CollisionObject3D", true, false):
		found.append((body as CollisionObject3D).get_rid())
	return found


# The grass-clearing zones under a piece or building (the valley has to be told when they move)
func _clear_zones(item: Node) -> Array:
	return item.find_children("*", "Node3D", true, false).filter(func(n): return n.has_meta(&"under_building"))


func _glow(item: Node, glow: Material) -> void:
	for look in item.find_children("*", "GeometryInstance3D", true, false):
		(look as GeometryInstance3D).material_overlay = glow


func _size_text(plot_size: Vector2) -> String:
	return "%d × %d" % [roundi(plot_size.x), roundi(plot_size.y)]


func _items_text(items: Dictionary) -> String:
	var parts: PackedStringArray = []
	for item in items:
		parts.append("%d %s" % [items[item], item])
	return ", ".join(parts)
