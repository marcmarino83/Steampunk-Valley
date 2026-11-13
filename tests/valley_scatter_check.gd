extends Node
## Writes down everything the valley scattered (each thing's scene, position, turn and size, in
## order, then the spots taken), so a change to how the valley scatters things can be checked
## against an older valley.gd: run it once with the older source (say from git), once with the
## current code, and compare the two files. Each run builds the valley once, fresh from the world
## scene's settings, so both are built the same way. Headless:
##
##     git show HEAD:world/valley.gd > <scratch>/valley_old.gd
##     godot --headless --path . res://tests/valley_scatter_check.tscn --quit-after 20000 \
##             -- --source=<scratch>/valley_old.gd --out=<scratch>/before.txt
##     godot --headless --path . res://tests/valley_scatter_check.tscn --quit-after 20000 \
##             -- --out=<scratch>/after.txt
##
## (no --source: the current valley.gd). The two files must be identical. Prints "SCATTER DONE"
## with how many things it wrote, then quits.

const WORLD := "res://world/world.tscn"
# Settings with setters that do editor work: not copied
const SKIP := ["rebuild", "show_slope_view", "show_modifier_markers"]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var source_path := ""
	var out_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--source="):
			source_path = arg.substr(9)
		elif arg.begins_with("--out="):
			out_path = arg.substr(6)
	if out_path.is_empty():
		print("SCATTER FAIL: no --out=<file> given")
		get_tree().quit(1)
		return
	var world_scene: PackedScene = load(WORLD)
	var world: Node = world_scene.instantiate()
	var real := world.get_node("Valley")
	var script: Script = real.get_script()
	if not source_path.is_empty():
		var older := GDScript.new()
		older.source_code = FileAccess.get_file_as_string(source_path)
		if older.source_code.is_empty() or older.reload() != OK:
			print("SCATTER FAIL: %s couldn't be read or didn't compile" % source_path)
			get_tree().quit(1)
			return
		script = older
	# The world's valley swapped for a fresh one with the chosen script and the same settings,
	# before the world is added, so it's the only valley ever built in this run
	var valley := StaticBody3D.new()
	valley.set_script(script)
	for property in real.get_property_list():
		var usage: int = property["usage"]
		var name: String = property["name"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE and usage & PROPERTY_USAGE_STORAGE \
				and not name in SKIP:
			valley.set(name, real.get(name))
	valley.transform = real.transform
	var index := real.get_index()
	var children := real.get_children()
	for child in children:
		real.remove_child(child)
	world.remove_child(real)
	real.free()
	valley.name = "Valley"
	for child in children:
		valley.add_child(child)
	world.add_child(valley)
	world.move_child(valley, index)
	var started := Time.get_ticks_msec()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	var lines := _fingerprint(valley)
	lines.append("taken spots: " + var_to_str(valley.get("_taken_spots")))
	lines.append("tree spots: " + var_to_str(valley.get("_tree_spots")))
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()
	print("SCATTER DONE: %d scattered things written to %s (built in %d ms)"
			% [lines.size() - 2, out_path, Time.get_ticks_msec() - started])
	get_tree().quit(0)


# Everything the valley scattered (made in code from a scene), in order: scene, place, turn, size
static func _fingerprint(valley: Node) -> PackedStringArray:
	var found: PackedStringArray = []
	for child in valley.get_children():
		if child.owner != null or child.scene_file_path.is_empty() or not child is Node3D:
			continue
		var t: Transform3D = (child as Node3D).transform
		found.append("%s %s %s" % [child.scene_file_path.get_file(), var_to_str(t.origin),
				var_to_str(t.basis)])
	return found
