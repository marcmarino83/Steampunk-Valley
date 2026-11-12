extends Node
## TEST: which pieces in a save sit off the building grid. Run headless, with the save's path:
##
##     godot --headless --path . res://tests/save_grid_audit.tscn --quit-after 20000 -- <save.json>
##
## Loads the save through SaveGame (as Load Game does; marked a test run, so nothing is saved), then
## groups its building pieces into buildings (pieces within JOIN of each other) and measures each
## piece against its own local frame: the nearest other foundation or floor in its building turned the
## same way (to a 90° step; a wing built at 45° has its own grid). A piece is off the grid when, in
## that frame:
##   - its turn isn't a whole number of 45° steps (22.5° for round and 45° triangle pieces),
##   - its place across isn't on the 0.25 m grid (pieces whose own frame is turned 22.5° are skipped),
##   - or its height isn't on the 0.125 m grid (the Tall strip's 0.625 m is the finest step).
## It also reports each converted piece none of whose typed edges lies along a compatible placed edge,
## and each point piece with none of its typed points on a placed point (not joined to anything), and
## lists the walls with a pole or pillar and a flight of stairs close by (to find a spot by eye).
## Prints "SAVEAUDIT" lines, then quits.

const JOIN := 3.0
const ANGLE_TOLERANCE := 0.5
const PLACE_TOLERANCE := 0.002

var _save := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_save = args[0] if not args.is_empty() else ""
	_run.call_deferred()


func _run() -> void:
	if _save.is_empty() or not FileAccess.file_exists(_save):
		print("SAVEAUDIT | no save given (or it isn't there): %s" % _save)
		get_tree().quit(1)
		return
	# (a template (it has "items"): laid out on the ground in a fresh world instead)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(_save))
	if parsed is Dictionary and (parsed as Dictionary).has("items"):
		await _template_run()
		return
	# (loading changes the scene, which frees the current one: a stand-in takes this node's place)
	var stand_in := Node.new()
	get_tree().root.add_child(stand_in)
	get_tree().current_scene = stand_in
	SaveGame.load_save(_save)
	var player: Node = null
	for i in 3000:
		await get_tree().process_frame
		player = get_tree().get_first_node_in_group("player")
		if player and SaveGame.get("_in_world"):
			break
	if player == null:
		print("SAVEAUDIT | the world didn't open")
		get_tree().quit(1)
		return
	SaveGame.set("_test_run", true)
	var registry: PieceRegistry = player._placer.registry
	for i in 600:
		await get_tree().process_frame
		if not registry.all_pieces().is_empty():
			break
	for i in 30:
		await get_tree().process_frame
	_audit(registry.all_pieces().filter(func(p): return not p.is_furniture()))
	get_tree().quit()


# A template, read as the game reads it (brought up to the current grid) and laid out at the world's
# starting spot, on the ground there, then audited the same way
func _template_run() -> void:
	var world: Node = load("res://world/world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	var player: Node = null
	for i in 3000:
		await get_tree().process_frame
		player = get_tree().get_first_node_in_group("player")
		if player:
			break
	for i in 30:
		await get_tree().process_frame
	var registry: PieceRegistry = player._placer.registry
	var template := BuildingTemplate.read(_save)
	var at: Vector3 = player.global_position
	at.y = Plot.ground_at(player, at.x, at.z)
	for item in template.items:
		if item["buildable"] is PieceBuildable:
			registry.spawn(item["buildable"], Transform3D(Basis.IDENTITY, at) * (item["relative"] as Transform3D), {})
	for i in 10:
		await get_tree().process_frame
	_audit(registry.all_pieces().filter(func(p): return not p.is_furniture()))
	get_tree().quit()


func _audit(pieces: Array) -> void:
	print("SAVEAUDIT | %s: %d building pieces (furniture left out)" % [_save.get_file(), pieces.size()])
	# Buildings: pieces within JOIN of each other, by their middles
	var groups: Array = []
	var left: Array = pieces.duplicate()
	while not left.is_empty():
		var group: Array = [left.pop_back()]
		var i := 0
		while i < group.size():
			var here: Vector3 = (group[i] as BuildPiece).center()
			for p in left.duplicate():
				if (p as BuildPiece).center().distance_to(here) <= JOIN:
					group.append(p)
					left.erase(p)
			i += 1
		groups.append(group)
	var all_edges := []
	var all_points := []
	for p in pieces:
		all_edges.append_array(SnapEdges.in_world(p))
		all_points.append_array(SnapEdges.points_in_world(p))
	var off := 0
	var loose := 0
	for group in groups:
		var frames: Array = (group as Array).filter(func(p): return (p as BuildPiece).is_floor())
		print("SAVEAUDIT | building of %d pieces round %s" % [group.size(), (group[0] as BuildPiece).center().snapped(Vector3.ONE * 0.1)])
		for p in group:
			var piece := p as BuildPiece
			# Its frame: the nearest other floor or foundation turned the same way (to a 90° step)
			var reference: BuildPiece = null
			var best := INF
			for f in frames:
				if f == piece:
					continue
				var apart := fposmod(rad_to_deg(_yaw(piece.global_basis) - _yaw((f as BuildPiece).global_basis)) + 1.0, 90.0)
				if apart > 2.0:
					continue
				var d: float = (f as BuildPiece).global_position.distance_to(piece.global_position)
				if d < best:
					best = d
					reference = f
			if reference == null:
				continue
			var frame := Transform3D(Basis(Vector3.UP, _yaw(reference.global_basis)), reference.global_position)
			var inverse := frame.affine_inverse()
			var problems := []
			if SaveGame.is_leaning(piece.global_basis):
				problems.append("tilted (not upright)")
			var fine: bool = piece.shape_name.contains("round") or piece.shape_name.contains("curved") or piece.shape_name.contains("cone") or piece.shape_name.contains("tri45") or piece.shape_name.begins_with("chimney")
			var step := 22.5 if fine else 45.0
			var turn := fposmod(rad_to_deg(_yaw(piece.global_basis) - _yaw(reference.global_basis)), 360.0)
			var turn_off := absf(turn - roundf(turn / step) * step)
			if turn_off > ANGLE_TOLERANCE:
				problems.append("turned %.2f° off a %d° step (at %.2f°)" % [turn_off, int(step), turn])
			var local := inverse * piece.global_position
			if not fine and absf(fposmod(roundf(turn / 22.5), 2.0)) < 0.5:
				for axis in [0, 2]:
					var v: float = local[axis]
					var d := absf(v - roundf(v / 0.25) * 0.25)
					if d > PLACE_TOLERANCE:
						problems.append("%s %.3f m, %.0f mm off the 0.25 m grid" % ["x" if axis == 0 else "z", v, d * 1000.0])
			var dy := absf(local.y - roundf(local.y / 0.125) * 0.125)
			if dy > PLACE_TOLERANCE:
				problems.append("height %.3f m, %.0f mm off the 0.125 m grid" % [local.y, dy * 1000.0])
			if not problems.is_empty():
				off += 1
				print("SAVEAUDIT | off grid | %s #%d at %s (from %s #%d: %s, turned %.1f°) | %s" % [piece.shape_name, piece.piece_id, piece.global_position.snapped(Vector3.ONE * 0.001), reference.shape_name, reference.piece_id, local.snapped(Vector3.ONE * 0.001), turn, "; ".join(problems)])
			# Joined to anything?
			var others_edges: Array = all_edges.filter(func(e): return e["piece"] != piece)
			if SnapEdges.edge_shape(piece.shape_name) and SnapEdges.matched(piece.shape_name, piece.shape_def(), piece.global_transform, others_edges) == 0:
				loose += 1
				print("SAVEAUDIT | not joined | %s #%d at %s: none of its edges lies along a compatible placed edge" % [piece.shape_name, piece.piece_id, piece.global_position.snapped(Vector3.ONE * 0.001)])
			elif SnapEdges.point_shape(piece.shape_name):
				var held := false
				for q in SnapEdges.points_in_world(piece):
					if all_points.any(func(o): return o["piece"] != piece and (o["p"] as Vector3).distance_to(q["p"]) < 0.002):
						held = true
						break
				if not held and SnapEdges.beam_line(piece.shape_name, piece.shape_def()).is_empty():
					loose += 1
					print("SAVEAUDIT | not joined | %s #%d at %s: none of its points is on a placed point" % [piece.shape_name, piece.piece_id, piece.global_position.snapped(Vector3.ONE * 0.001)])
	print("SAVEAUDIT | %d pieces off the grid, %d not joined to anything, in %d buildings" % [off, loose, groups.size()])
	# Pillars and poles with a flight of stairs close by (the spots between a post and a pillar under
	# the stairs), and the walls round them
	for q in pieces:
		var post := q as BuildPiece
		if not (post.shape_name.begins_with("pillar") or post.shape_name.begins_with("pole")):
			continue
		var flights: Array = pieces.filter(func(p): return p.shape_name in SnapEdges.FLIGHTS and p.center().distance_to(post.center()) < 4.5)
		if flights.is_empty():
			continue
		var around: Array = pieces.filter(func(p): return p != post and (p.shape_name.begins_with("pillar") or p.shape_name.begins_with("pole") or p.shape_name in SnapEdges.WALLS) and p.center().distance_to(post.center()) < 3.0)
		print("SAVEAUDIT | spot | %s #%d at %s (turn %.1f°), flights %s | round it: %s" % [post.shape_name, post.piece_id, post.global_position.snapped(Vector3.ONE * 0.001), rad_to_deg(_yaw(post.global_basis)),
			flights.map(func(p): return "#%d %s at %s turn %.1f°" % [p.piece_id, p.shape_name, (p.global_position as Vector3).snapped(Vector3.ONE * 0.001), rad_to_deg(_yaw(p.global_basis))]),
			around.map(func(p): return "#%d %s at %s turn %.1f°" % [p.piece_id, p.shape_name, (p.global_position as Vector3).snapped(Vector3.ONE * 0.001), rad_to_deg(_yaw(p.global_basis))])])


static func _yaw(b: Basis) -> float:
	return atan2(b.z.x, b.z.z)
