extends Node
## TOOL: lists and fixes the built-in templates. Run headless:
##
##     godot --headless --path . res://tests/template_fix.tscn --quit-after 2000 -- [--write]
##
## Reads each template as the game does (BuildingTemplate.read, so brought up to the current grid by
## GridUpgrade) and prints every piece ("TPLFIX" lines: number, shape, place relative to the plot,
## turn) after the fixes below. With --write it also writes each template it changed back through the
## game's own writer (BuildingTemplate.write, on the current grid version; the picture is kept). The
## fixes are idempotent: on templates already fixed they change nothing.

var _write := false


func _ready() -> void:
	_write = OS.get_cmdline_user_args().has("--write")
	_run.call_deferred()


func _run() -> void:
	for file in DirAccess.get_files_at(BuildingTemplate.BUILT_IN_FOLDER):
		if not file.ends_with(".json"):
			continue
		var template := BuildingTemplate.read(BuildingTemplate.BUILT_IN_FOLDER.path_join(file))
		if template == null:
			print("TPLFIX | %s: couldn't read" % file)
			continue
		# (without --write: what the fixes would do, nothing written)
		var notes := _fix(template)
		if _write and not notes.is_empty():
			template.write(true, null)
		print("TPLFIX | %s %s: %s" % [file, "written" if _write and not notes.is_empty() else "(not written)", " | ".join(notes) if not notes.is_empty() else "no changes"])
		_dump(file, template)
	get_tree().quit()


func _dump(file: String, template: BuildingTemplate) -> void:
	print("TPLFIX | == %s (%s), %d items" % [file, template.template_name, template.items.size()])
	for i in template.items.size():
		var item: Dictionary = template.items[i]
		var b: Buildable = item["buildable"]
		var shape: String = (b as PieceBuildable).shape if b is PieceBuildable else b.resource_path.get_file().get_basename()
		var w: Transform3D = item["relative"]
		print("TPLFIX | %d %s %s %.1f°" % [i, shape, w.origin.snapped(Vector3.ONE * 0.001), rad_to_deg(w.basis.get_euler().y)])


# The fixes; returns what changed:
#   - the whole template lifted so its foundation tops are 1 m up, the building standard's
#     (PieceShapes: foundations' tops 1 m above the ground); they were 0.5 to 0.73 m, which no
#     flight of stairs fits;
#   - each flight swapped for the one exactly as tall as its top is high (Standard first), its top
#     edge kept where it was, so none is partly underground;
#   - each post (pillar, pole) reaching below the ground swapped for the one of its kind exactly as
#     tall as its top is high, standing on the ground, or dropped if none is (a buried leftover);
#   - the Woodcutter's Hut's porch rails (1 m beams made 2 m by the grid change, overlapping and
#     floating above the 1 m poles): one 2 m beam per side on the poles' tops.
func _fix(template: BuildingTemplate) -> Array:
	var notes := []
	var top := INF
	for item in template.items:
		if _shape(item).begins_with("foundation") or _shape(item).begins_with("round_foundation"):
			top = minf(top, (item["relative"] as Transform3D).origin.y)
	var lift := 1.0 - top if top < INF else 0.0
	if absf(lift) > 0.0005:
		for item in template.items:
			item["relative"] = (item["relative"] as Transform3D).translated(Vector3.UP * lift)
		notes.append("lifted %.3f m (foundation tops %.3f -> 1.0)" % [lift, top])
	var kept := []
	for item in template.items:
		var shape := _shape(item)
		var w: Transform3D = item["relative"]
		if PieceShapes.FLIGHTS.has(shape):
			var old_size: Array = PieceShapes.FLIGHTS[shape]
			var edge: Vector3 = w * Vector3(0, old_size[0], old_size[1] / 2.0)
			var pick := ""
			for f in PieceShapes.FLIGHTS:
				if absf(float(PieceShapes.FLIGHTS[f][0]) - edge.y) < 0.002 and (pick == "" or pick.ends_with("_tall")):
					pick = f
			if pick == "":
				notes.append("no flight is %.3f m tall (%s kept)" % [edge.y, shape])
			elif pick != shape or absf(w.origin.y) > 0.002:
				var size: Array = PieceShapes.FLIGHTS[pick]
				item["buildable"] = load("res://buildables/structure/%s.tres" % pick)
				item["relative"] = Transform3D(w.basis, edge - w.basis * Vector3(0, size[0], size[1] / 2.0))
				notes.append("%s -> %s (top edge kept at %s)" % [shape, pick, edge.snapped(Vector3.ONE * 0.001)])
		elif shape.begins_with("pillar") or shape.begins_with("pole"):
			var box := PieceShapes.bounds_of(PieceShapes.build(shape))
			var bottom := w.origin.y + box.position.y
			var post_top := w.origin.y + box.end.y
			if bottom < -0.002:
				var kind := "pole" if shape.begins_with("pole") else shape.substr(0, shape.find("_", 7))
				var pick := _post_of(kind, post_top)
				if pick == "":
					notes.append("dropped a buried %s (%.2f to %.2f m)" % [shape, bottom, post_top])
					continue
				item["buildable"] = load("res://buildables/structure/%s.tres" % pick)
				item["relative"] = Transform3D(w.basis, Vector3(w.origin.x, 0.0, w.origin.z))
				notes.append("buried %s -> %s on the ground" % [shape, pick])
		kept.append(item)
	template.items = kept
	if template.template_name == "Woodcutter's Hut":
		_porch_rails(template, notes)
	# Anything still reaching below the ground (other than foundations)
	for item in template.items:
		var shape := _shape(item)
		if not template_piece(item) or shape.contains("foundation"):
			continue
		var w: Transform3D = item["relative"]
		var low := w.origin.y + PieceShapes.bounds_of(PieceShapes.build(shape)).position.y
		if low < -0.002:
			notes.append("STILL BELOW GROUND: %s at %s" % [shape, w.origin.snapped(Vector3.ONE * 0.001)])
	return notes


# The porch rails: the 2 m beams left floating 0.25 m above the 1 m poles at the porch's sides (two
# per side, overlapping) taken off, and one 2 m beam per side put on the poles' tops, from the front
# corner pole back along the side to the pillar
func _porch_rails(template: BuildingTemplate, notes: Array) -> void:
	var sides := {}
	var poles := template.items.filter(func(i): return _shape(i) == "pole_1")
	for item in template.items.duplicate():
		if _shape(item) != "beam_2":
			continue
		var w: Transform3D = item["relative"]
		var on_poles := poles.filter(func(p): return absf((p["relative"] as Transform3D).origin.x - w.origin.x) < 0.01)
		if on_poles.is_empty():
			continue
		var pole_top: float = (on_poles[0]["relative"] as Transform3D).origin.y + PieceShapes.POLE_HEIGHTS["pole_1"]
		if absf(w.origin.y - pole_top) < 0.002:
			continue
		template.items.erase(item)
		var front := INF
		for p in on_poles:
			front = minf(front, (p["relative"] as Transform3D).origin.z)
		sides[snappedf(w.origin.x, 0.001)] = [w.origin.x, pole_top, front]
	for x in sides:
		var s: Array = sides[x]
		template.items.append({"buildable": load("res://buildables/structure/beam_2.tres"), "relative": Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(s[0], s[1], s[2] + 1.0))})
		notes.append("porch rail rebuilt at x %.3f: one 2 m beam on the pole tops (%.2f m up)" % [s[0], s[1]])


# The standard post of this kind ("pole", "pillar_wood", "pillar_stone") exactly `height` tall, or ""
func _post_of(kind: String, height: float) -> String:
	for file in DirAccess.get_files_at("res://buildables/structure"):
		if not file.begins_with(kind) or not file.ends_with(".tres"):
			continue
		var b := load("res://buildables/structure/" + file) as PieceBuildable
		if b == null or b.shape.ends_with("_tall"):
			continue
		var box := PieceShapes.bounds_of(PieceShapes.build(b.shape))
		if absf(box.size.y - height) < 0.002:
			return b.shape
	return ""


static func template_piece(item: Dictionary) -> bool:
	return item["buildable"] is PieceBuildable


static func _shape(item: Dictionary) -> String:
	return (item["buildable"] as PieceBuildable).shape if item["buildable"] is PieceBuildable else ""
