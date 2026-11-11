class_name PathPainter
extends Node
## The Dirt Path tool (the build menu's Paths tab; see PathTool). Holding left-click paints a
## soft-edged strip of dirt path onto the ground under the crosshair as you drag; the wheel makes
## it wider or narrower; the middle button (or holding X) rubs path out again. A ring on the
## ground shows how wide it paints. It never changes the ground's height and costs nothing.
##
## The path itself is kept by the valley's PaintedPaths, which draws it and saves it. Grass and
## ferns on fresh path are cleared away as you paint, and grow back where it's rubbed out.

const CONTROLS := [["Paint", "LMB"], ["Width", "Wheel"], ["Erase", "MMB"], ["Cancel", "RMB"]]
## How far ahead of the camera it paints, in meters
const REACH := 14.0
## Narrowest and widest path, and how much each wheel click changes it (m)
const MIN_WIDTH := 1.0
const MAX_WIDTH := 3.0
const WIDTH_STEP := 0.25
## A dab's radius (to where it fades to nothing) for each meter of width: the path looks about
## its width across, with the edge fading out softly either side
const RADIUS_PER_WIDTH := 0.67
## How far apart dabs go along a stroke, for each meter of width
const SPACING := 0.2
## The most dabs in one frame (a quick flick of the mouse finishes over the next few frames)
const MAX_DABS := 24
## How often (seconds) grass is cleared off fresh path, or grown back where it was rubbed out
const PLANTS_EVERY := 0.12
## The render layer grass, ferns and scattered rocks are on (see Foliage): the ring isn't drawn on them
const FOLIAGE_LAYER := 1 << 1

var player: CharacterBody3D

var _tool: PathTool
var _width := -1.0
var _painting := false
var _erase_button := false
var _erase_key := false
# Where the last dab of this stroke went, and whether that stroke was rubbing out
var _last := Vector2.ZERO
var _has_last := false
var _last_erasing := false
# Where the crosshair meets the ground (and whether it does)
var _aim := Vector3.ZERO
var _aim_ok := false
var _ring: Decal
# Painted, and rubbed out, since the plants were last seen to; and the time until they next are
var _painted_area := Rect2()
var _erased_area := Rect2()
var _plants_in := 0.0


func _ready() -> void:
	set_process(false)


## Starts painting with this tool (the width stays as it was last time)
func begin(tool: PathTool) -> void:
	cancel()
	_tool = tool
	if _width < 0.0:
		_width = tool.start_width
	_ring = Decal.new()
	_ring.texture_albedo = _ring_texture()
	_ring.cull_mask = 0xFFFFF & ~FOLIAGE_LAYER
	_ring.upper_fade = 0.2
	_ring.lower_fade = 0.2
	_ring.visible = false
	player.get_parent().add_child(_ring)
	set_process(true)


## Stops painting (what's painted stays)
func cancel() -> void:
	_painting = false
	_erase_button = false
	_erase_key = false
	_has_last = false
	_see_to_plants()
	if _ring:
		_ring.queue_free()
	_ring = null
	_tool = null
	set_process(false)


func is_active() -> bool:
	return _tool != null


func current() -> PathTool:
	return _tool


## The middle button held (or let go): rubbing out
func set_erase_button(on: bool) -> void:
	_erase_button = on


## Called every frame while active: whether painting can happen (no menu open...) and whether X is held
func update(active: bool, holding_x: bool) -> void:
	_erase_key = active and holding_x
	if not active:
		_painting = false
		_erase_button = false


func handle_input(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		cancel()
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		# Finish or cancel this before putting the hammer away
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			return true
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var step := WIDTH_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else -WIDTH_STEP
			_width = clampf(_width + step, MIN_WIDTH, MAX_WIDTH)
			return true
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				_painting = true
				_has_last = false
			elif not event.pressed:
				_painting = false
				_has_last = false
			return true
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			cancel()
			return true
	return false


## What the on-screen controls show (see HudControls)
func hud_state() -> Dictionary:
	var detail := "Width %s m" % String.num(_width, 2)
	if not _aim_ok:
		detail += "  ·  Point at the ground"
	elif _erasing():
		detail += "  ·  Erasing"
	return {
		"controls": CONTROLS,
		"info": {
			"icon": _tool.icon if _tool else null,
			"title": _tool.display_name if _tool else "",
			"cost": "Free",
			"cost_bad": false,
			"detail": detail,
			"detail_bad": not _aim_ok,
			"detail_warn": false,
		},
	}


func _erasing() -> bool:
	return _erase_button or _erase_key


func _process(delta: float) -> void:
	var timing := SpikeLog.begin()
	_find_aim()
	var erasing := _erasing()
	if _ring:
		_ring.visible = _aim_ok
		_ring.global_position = _aim
		_ring.size = Vector3(_width * 1.1, 6.0, _width * 1.1)
		_ring.modulate = Color(1.0, 0.45, 0.35, 0.9) if erasing else Color(1.0, 0.92, 0.7, 0.85)
	var valley = _valley()
	var paths: PaintedPaths = valley.painted_paths if valley else null
	if paths and _aim_ok and (_painting or erasing):
		if not _has_last or erasing != _last_erasing:
			_last = Vector2(_aim.x, _aim.z)
			_has_last = true
			_last_erasing = erasing
			_dab(paths, _last, erasing)
		var target := Vector2(_aim.x, _aim.z)
		var step := maxf(_width * SPACING, 0.1)
		var dabs := 0
		while _last.distance_to(target) >= step and dabs < MAX_DABS:
			_last = _last.move_toward(target, step)
			_dab(paths, _last, erasing)
			dabs += 1
	else:
		_has_last = false
	_plants_in -= delta
	if _plants_in <= 0.0:
		_see_to_plants()
	SpikeLog.end("dirt path painting", timing)


func _dab(paths: PaintedPaths, spot: Vector2, erasing: bool) -> void:
	var changed := paths.dab(spot, _width * RADIUS_PER_WIDTH, erasing)
	if changed.has_area():
		if erasing:
			_erased_area = changed if not _erased_area.has_area() else _erased_area.merge(changed)
		else:
			_painted_area = changed if not _painted_area.has_area() else _painted_area.merge(changed)


# Grass and ferns off the fresh path at once; grown back where path was rubbed out
func _see_to_plants() -> void:
	_plants_in = PLANTS_EVERY
	var valley = _valley()
	var foliage = valley.get_node_or_null("Foliage") if valley else null
	if foliage and _painted_area.has_area():
		foliage.hide_plants_on_paths(_painted_area)
	if _erased_area.has_area():
		if valley and valley.painted_paths:
			valley.painted_paths.tidy()
		if foliage:
			foliage.regrow_plants_in(_erased_area)
	_painted_area = Rect2()
	_erased_area = Rect2()


# Where the crosshair meets the ground, within reach (not through a building)
func _find_aim() -> void:
	_aim_ok = false
	var camera: Camera3D = player.camera
	var from := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * REACH)
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not (hit["collider"] as Node).is_in_group("terrain_ground"):
		return
	_aim = hit["position"]
	_aim_ok = true


# The valley (untyped: its painted paths are asked for by name)
func _valley():
	return get_tree().get_first_node_in_group("valley")


# A thin bright ring with a faint fill, for the decal that shows the brush on the ground
static func _ring_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.8, 0.88, 0.94, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.1), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 256
	texture.height = 256
	return texture
