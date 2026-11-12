class_name PathTilePlacer
extends Node
## Lays path tiles (the build menu's Paths tab: Dirt, Gravel, Stone and Remove; see PathTileType)
## like building pieces, though they're only paint on the ground (see PathTiles).
##
## The tile (2 m wide, 4 m long) shows on the ground under the crosshair before it's laid: its own
## texture with its soft, ragged edge, a thin white line along its footprint, red for a Remove
## tile or one you can't pay for. The wheel turns it 22.5° (1° with snapping off: Z). Snapping,
## it fits against the path tiles near it, of any type: side by side (a wider road), end to end (a
## longer one), across the end or side of one (a corner or a junction), or right on top of one of
## another type (layering, say gravel down the middle of a dirt road). Holding left click keeps
## laying: each time the crosshair reaches the next spot, another tile goes down, so a road can be
## laid in one sweep. A Remove tile clears every type under it back to grass.

const CONTROLS := [["Place", "LMB"], ["Hold: keep laying", "LMB"], ["Turn", "Wheel"], ["Snap", "Z"], ["Cancel", "RMB"]]
## How far ahead of the camera it lays, in meters
const REACH := 16.0
## Snapping: tiles this close to the crosshair are looked at, a fitting spot is taken within
## SNAP_REACH of it, and each radian its turn is off the tile's costs as much as this many meters
const NEAR := 9.0
const SNAP_REACH := 1.6
const TURN_WEIGHT := 1.5
## The wheel's turn, snapping and not
const TURN_STEP := PI / 8.0
const FINE_STEP := PI / 180.0
## Holding left click: a free (unsnapped) tile goes down once the crosshair is this far from the
## last one; a snapped one whenever it fits somewhere new
const HOLD_GAP := 3.8
const NEW_SPOT := 0.5
## The render layer grass, ferns and scattered rocks are on (see Foliage): the preview isn't drawn on them
const FOLIAGE_LAYER := 1 << 1
## The preview's picture: pixels per meter, and how far it reaches past the tile's footprint (m)
const PREVIEW_DENSITY := 40.0
const PREVIEW_MARGIN := 0.6
## The preview's colours: white for the footprint line, red for Remove or can't pay
const LINE_COLOR := Color(BrassStyle.HIGHLIGHT, 0.9)
const BAD_TINT := BrassStyle.BAD

var player: CharacterBody3D

# The turn the player has set (kept between uses, like building pieces')
static var _yaw := 0.0
# The preview pictures made so far: rank -> Texture2D
static var _pictures := {}

var _type: PathTileType
var _snap := true
var _decal: Decal
var _aim := Vector3.ZERO
var _aim_ok := false
# Where the tile would go now (x, z), its turn, and whether it's fitted to a tile near it
var _spot := Vector2.ZERO
var _turn := 0.0
var _snapped := false
# Holding left click to keep laying, and where the last tile went
var _holding := false
var _last := Vector2.INF
var _last_turn := 0.0


func _ready() -> void:
	set_process(false)


func begin(type: PathTileType) -> void:
	cancel()
	_type = type
	_decal = Decal.new()
	_decal.texture_albedo = _picture(type)
	_decal.cull_mask = 0xFFFFF & ~FOLIAGE_LAYER
	_decal.upper_fade = 0.3
	_decal.lower_fade = 0.3
	_decal.size = Vector3(PathTiles.TILE_SIZE.x + PREVIEW_MARGIN * 2.0, 8.0, PathTiles.TILE_SIZE.y + PREVIEW_MARGIN * 2.0)
	_decal.visible = false
	player.get_parent().add_child(_decal)
	set_process(true)


func cancel() -> void:
	_holding = false
	_last = Vector2.INF
	if _decal:
		_decal.queue_free()
	_decal = null
	_type = null
	set_process(false)


func is_active() -> bool:
	return _type != null


func current() -> PathTileType:
	return _type


func handle_input(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		cancel()
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		# Finish or cancel this before putting the hammer away
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			return true
		if event.keycode == KEY_Z:
			_snap = not _snap
			return true
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var step := TURN_STEP if _snap else FINE_STEP
			_yaw = wrapf(_yaw + (step if event.button_index == MOUSE_BUTTON_WHEEL_UP else -step), 0.0, TAU)
			if _snap:
				_yaw = snappedf(_yaw, TURN_STEP)
			return true
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				_holding = true
				_last = Vector2.INF
				_find_spot()
				_lay()
			elif not event.pressed:
				_holding = false
			return true
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			cancel()
			return true
	return false


## What the on-screen controls show (see HudControls)
func hud_state() -> Dictionary:
	var detail := "Turn %d°" % roundi(rad_to_deg(_turn))
	if not _aim_ok:
		detail = "Point at the ground"
	elif _snapped:
		detail += "  ·  Fitted to the path"
	elif not _snap:
		detail += "  ·  Snapping off"
	if _type and _type.is_remove():
		detail += "  ·  Clears every path type under it"
	var short := _type != null and not _type.can_afford(player.inventory)
	return {
		"controls": CONTROLS,
		"info": {
			"icon": _type.icon if _type else null,
			"title": _type.display_name if _type else "",
			"cost": (_type.cost_text() + " a tile") if _type and not _type.costs.is_empty() else "Free",
			"cost_bad": short,
			"detail": detail,
			"detail_bad": not _aim_ok,
			"detail_warn": false,
		},
	}


func _process(_delta: float) -> void:
	var timing := SpikeLog.begin()
	_find_spot()
	if _decal:
		_decal.visible = _aim_ok
		if _aim_ok:
			var ground := Plot.ground_at(player, _spot.x, _spot.y)
			_decal.global_transform = Transform3D(Basis(Vector3.UP, _turn), Vector3(_spot.x, ground, _spot.y))
			var bad := _type.is_remove() or not _type.can_afford(player.inventory)
			_decal.modulate = BAD_TINT if bad else Color.WHITE
	# Holding left click: the next tile, once the crosshair has reached a new spot
	if _holding and _aim_ok and _type:
		var moved := _last == Vector2.INF or _spot.distance_to(_last) >= (NEW_SPOT if _snapped else HOLD_GAP) or (_snapped and absf(wrapf(_turn - _last_turn, -PI / 2.0, PI / 2.0)) > 0.01)
		if moved:
			_lay()
	SpikeLog.end("path tiles: placing", timing)


func _lay() -> void:
	if not _aim_ok or _type == null:
		return
	var paths := _paths()
	if paths == null:
		return
	if not _type.costs.is_empty():
		var cost := _type.cost_to_pay(player.inventory)
		if cost.is_empty():
			player.flash("Not enough: you need %s" % _type.missing_text(player.inventory))
			_holding = false
			return
		# (paid only if it changes the ground: laying the same tile again is free)
		if paths.has_tile(_type.rank, _spot, _turn):
			return
		player.pay(cost)
	var changed := paths.lay(_type.rank, _spot, _turn)
	_last = _spot
	_last_turn = _turn
	if not changed.has_area():
		return
	player.report_progress("Build", _type.display_name)
	var valley = get_tree().get_first_node_in_group("valley")
	var foliage = valley.get_node_or_null("Foliage") if valley else null
	if foliage:
		if _type.is_remove():
			foliage.regrow_plants_in(changed)
		else:
			foliage.hide_plants_on_paths(changed)


# Where the tile would go: under the crosshair at the player's turn, or (snapping) fitted to the
# path tile spot nearest the crosshair
func _find_spot() -> void:
	_aim_ok = _find_aim()
	_snapped = false
	if not _aim_ok:
		return
	var free := Vector2(_aim.x, _aim.z)
	_spot = free
	_turn = _yaw
	var paths := _paths()
	if not _snap or paths == null:
		return
	var best := INF
	for tile in paths.tiles_near(free, NEAR):
		for slot in _slots(tile):
			var middle: Vector2 = slot[0]
			var turn: float = slot[1]
			var gap := middle.distance_to(free)
			if gap > SNAP_REACH:
				continue
			# Not onto a tile of the same type exactly where it already is
			if not _type.is_remove() and int(tile["rank"]) == _type.rank and middle.distance_to(tile["middle"]) < 0.01:
				continue
			if not _type.is_remove() and paths.has_tile(_type.rank, middle, turn):
				continue
			var score := gap + absf(wrapf(turn - _yaw, -PI / 2.0, PI / 2.0)) * TURN_WEIGHT
			if score < best:
				best = score
				_spot = middle
				_turn = turn
				_snapped = true


# The spots a tile fits against another one: [middle, turn] for right on top of it, beside either
# long side, past either end, and turned a quarter across its sides and ends (on the 1 m step)
func _slots(tile: Dictionary) -> Array:
	var middle: Vector2 = tile["middle"]
	var turn: float = tile["turn"]
	# Its own across (X) and along (Z) on the ground
	var across := Vector2(cos(turn), -sin(turn))
	var along := Vector2(sin(turn), cos(turn))
	var w := PathTiles.TILE_SIZE.x
	var l := PathTiles.TILE_SIZE.y
	var slots := [[middle, turn]]
	for side in [-1.0, 1.0]:
		slots.append([middle + across * w * side, turn])
		slots.append([middle + along * l * side, turn])
		for step in [-1.0, 0.0, 1.0]:
			# Turned a quarter: its end against this one's long side, or its long side across this
			# one's end
			slots.append([middle + across * (w + l) / 2.0 * side + along * step, turn + PI / 2.0])
			slots.append([middle + along * (l + w) / 2.0 * side + across * step, turn + PI / 2.0])
	return slots


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


# The preview's picture for a type: its texture across the tile, fading out past the footprint the
# way its edge does on the ground, with a thin white line along the footprint (Remove: a plain
# fill). Made once per type.
func _picture(type: PathTileType) -> Texture2D:
	if _pictures.has(type.rank):
		return _pictures[type.rank]
	var size := PathTiles.TILE_SIZE + Vector2.ONE * PREVIEW_MARGIN * 2.0
	var width := roundi(size.x * PREVIEW_DENSITY)
	var height := roundi(size.y * PREVIEW_DENSITY)
	var source: Image = null
	var meters := 2.5
	if not type.is_remove():
		var valley = get_tree().get_first_node_in_group("valley")
		var id: String = PathTiles.RANK_SETS[type.rank - 1]
		if valley:
			for set in valley.texture_sets():
				if set["id"] == id:
					var texture := load(set["color"]) as Texture2D
					source = texture.get_image() if texture else null
					var looks: Dictionary = (valley.get_script() as Script).get_script_constant_map().get("SET_LOOKS", {})
					meters = float(looks.get(id, [2.5])[0])
		if source:
			source = source.duplicate()
			if source.is_compressed():
				source.decompress()
			source.convert(Image.FORMAT_RGBA8)
			source.resize(256, 256, Image.INTERPOLATE_BILINEAR)
	var edge: Vector4 = PathTiles.RANK_EDGES[type.rank - 1] if not type.is_remove() else Vector4(-PathTiles.GROW, 0.08, 0.0, 1.0)
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	var half := PathTiles.TILE_SIZE / 2.0
	var line := 0.035
	for y in height:
		for x in width:
			var local := Vector2((x + 0.5) / PREVIEW_DENSITY - size.x / 2.0, (y + 0.5) / PREVIEW_DENSITY - size.y / 2.0)
			var q := Vector2(absf(local.x) - half.x, absf(local.y) - half.y)
			var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)
			d -= (PathTiles.wobble(local.x * 1.7, local.y * 1.7) - 0.5) * 2.0 * PathTiles.WOBBLE + PathTiles.GROW
			var cover := 1.0 - smoothstep(edge.x - edge.y, edge.x + edge.y, d)
			var color := Color(0.85, 0.85, 0.85)
			if source:
				var u := posmod(roundi(local.x / meters * 256.0), 256)
				var v := posmod(roundi(local.y / meters * 256.0), 256)
				color = source.get_pixel(u, v)
			color.a = cover * (0.45 if type.is_remove() else 0.85)
			# The footprint's line
			var on_line := absf(maxf(q.x, q.y)) < line
			if on_line:
				color = LINE_COLOR
			image.set_pixel(x, y, color)
	var picture := ImageTexture.create_from_image(image)
	_pictures[type.rank] = picture
	return picture
