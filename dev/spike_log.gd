class_name SpikeLog
extends Node
## The lag spike logger (debug builds only; Settings, "Log lag spikes", off by default). Whenever a
## frame takes longer than THRESHOLD_MS it writes one line to the output: how long the frame took,
## what the player was doing, the time each instrumented system spent in that frame, how many
## nodes were added, and how many shader pipelines were compiled for the first time (a first-time
## shader or material compile shows up as a frame with pipelines compiled). Under it, the nodes
## added (names and parents, this frame and the one before) and, with shaders compiled, the kinds
## compiled and the materials those nodes carry.
##
## Systems report their time with
##     var t := SpikeLog.begin()
##     ...work...
##     SpikeLog.end("what it was", t)
## which costs next to nothing while the logger is off. SpikeLog.note() adds a remark to this
## frame's line (a save written, a dawn passing).
##
## The player adds the node once the world is up (see the player). Spikes are also kept in
## `spikes` while it's on, for anything that wants to sum them up.

## A frame slower than this is a spike (two frames at 60 FPS)
const THRESHOLD_MS := 33.0
## How many spikes are kept in `spikes`
const KEEP := 500

## On or off (GameSettings.spike_log, and only ever in a debug build)
static var enabled := false
## Every spike while on: {"ms", "at_ms", "activity", "systems": {name: ms}, "nodes", "compiles", "notes"}
static var spikes: Array = []

# This frame so far: time per system (µs), how often each ran, remarks
static var _times := {}
static var _calls := {}
static var _notes: PackedStringArray = []
static var _nodes_added := 0
# The nodes added this frame (the first MAX_LISTED), to name them and their materials in a spike's line
static var _added: Array[Node] = []
# The frame before's: a node added then is first drawn (and its shaders compiled) in the render that
# falls inside this frame's time
static var _added_before: Array[Node] = []
## How many added nodes a spike's line names (by name and parent, grouped)
const MAX_LISTED := 60

var _last_usec := 0
var _last_compiles := -1
var _last_kinds := {}


## Start timing something (0 while the logger is off)
static func begin() -> int:
	return Time.get_ticks_usec() if enabled else 0


## Stop timing it: its time this frame goes under `system`
static func end(system: String, started: int) -> void:
	if not enabled or started == 0:
		return
	_times[system] = int(_times.get(system, 0)) + Time.get_ticks_usec() - started
	_calls[system] = int(_calls.get(system, 0)) + 1


## A remark for this frame's line, if it turns out to be a spike
static func note(text: String) -> void:
	if enabled and _notes.size() < 8:
		_notes.append(text)


func _ready() -> void:
	name = "SpikeLog"
	# After everything else each frame, so a frame's work is all counted before it's judged
	process_priority = 100000
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	_nodes_added += 1
	if enabled and _added.size() < MAX_LISTED:
		_added.append(node)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var kinds := _pipeline_kinds()
	var compiles := 0
	for kind in kinds:
		compiles += int(kinds[kind])
	if enabled and _last_usec > 0:
		var ms := (now - _last_usec) / 1000.0
		if ms > THRESHOLD_MS:
			var new_kinds := {}
			if _last_compiles >= 0:
				for kind in kinds:
					var more: int = int(kinds[kind]) - int(_last_kinds.get(kind, 0))
					if more > 0:
						new_kinds[kind] = more
			_report(ms, compiles - _last_compiles if _last_compiles >= 0 else 0, new_kinds)
	_last_usec = now
	_last_compiles = compiles
	_last_kinds = kinds
	_times.clear()
	_calls.clear()
	_notes.clear()
	_nodes_added = 0
	_added_before = _added.duplicate()
	_added.clear()


# Writes the spike's line and keeps it. With nodes added, a second line names them (grouped by
# name and parent: "Detail ← Wall ×12"); with shaders compiled, a third gives the kinds compiled
# (mesh, surface, canvas...) and the materials on the nodes added that frame, the likely ones
# (Godot counts pipeline compiles but doesn't say which material each was for).
func _report(ms: float, compiles: int, kinds := {}) -> void:
	var systems := {}
	var counted := 0.0
	var names: Array = _times.keys()
	names.sort_custom(func(a, b): return _times[a] > _times[b])
	var parts: PackedStringArray = []
	for system in names:
		var spent: float = _times[system] / 1000.0
		counted += spent
		systems[system] = spent
		if spent >= 0.5:
			var calls: int = _calls.get(system, 1)
			parts.append("%s %.1f ms%s" % [system, spent, " (x%d)" % calls if calls > 1 else ""])
	parts.append("not in any system (engine, physics, rendering) %.1f ms" % maxf(ms - counted, 0.0))
	var activity := _activity()
	var line := "[Spike] %.0f ms while %s: %s; %d nodes added%s%s" % [ms, activity, ", ".join(parts), _nodes_added,
		"; %d shader pipelines compiled for the first time" % compiles if compiles > 0 else "",
		"; " + "; ".join(_notes) if not _notes.is_empty() else ""]
	print(line)
	var added := _added_text()
	if not added.is_empty():
		print("[Spike]   nodes added (this frame and the one before): " + added)
	var materials := _materials_text()
	if compiles > 0:
		var kind_parts: PackedStringArray = []
		for kind in kinds:
			kind_parts.append("%s %d" % [kind, kinds[kind]])
		print("[Spike]   compiled: %s; materials on the nodes added: %s" % [", ".join(kind_parts), materials if not materials.is_empty() else "none (something already there drawn a new way: in view, fading, shadowed)"])
	spikes.append({"ms": ms, "at_ms": Time.get_ticks_msec(), "activity": activity, "systems": systems, "nodes": _nodes_added, "compiles": compiles, "notes": Array(_notes), "added": added, "materials": materials})
	if spikes.size() > KEEP:
		spikes.pop_front()


# What the player is doing: sleeping, in a menu, placing or taking down, walking, or standing
func _activity() -> String:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return "loading"
	if player.get("_sleeping"):
		return "sleeping"
	var menu := player.get("build_menu") as Control
	if menu and menu.visible:
		return "in the build menu"
	var inventory := player.get("inventory_screen") as Control
	if inventory and inventory.visible:
		return "in the inventory"
	if get_tree().paused:
		return "paused (a menu)"
	var placer = player.get("_placer")
	if placer and placer.has_method("is_placing") and placer.is_placing():
		return "placing"
	if placer and placer.get("_demolisher") and float(placer._demolisher.get("_hold_time")) > 0.0:
		return "taking down a piece"
	var body := player as CharacterBody3D
	if body and Vector2(body.velocity.x, body.velocity.z).length() > 0.5:
		return "walking"
	return "standing"


# Shader pipelines compiled so far, by kind (a new one means a first-time shader compile)
func _pipeline_kinds() -> Dictionary:
	return {
		"canvas (UI, 2D)": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS),
		"mesh": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH),
		"surface": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE),
		"draw": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW),
		"specialization": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION),
	}


# The nodes added this frame, grouped by name and parent: "Detail ← Wall ×12, Smoke ← Campfire"
# (names with numbers in them, like @MeshInstance3D@123, go by their class instead)
func _added_text() -> String:
	var counts := {}
	var order: Array = []
	for node in _added_before + _added:
		if not is_instance_valid(node):
			continue
		var parent := node.get_parent()
		var key := "%s ← %s" % [_label(node), _label(parent) if parent else "(none)"]
		if not counts.has(key):
			order.append(key)
		counts[key] = int(counts.get(key, 0)) + 1
	var parts: PackedStringArray = []
	for key in order:
		parts.append(key + (" ×%d" % counts[key] if counts[key] > 1 else ""))
	if _nodes_added > _added.size():
		parts.append("(and %d more this frame)" % (_nodes_added - _added.size()))
	return ", ".join(parts)


static func _label(node: Node) -> String:
	var text := String(node.name)
	if text.begins_with("@") or text.is_empty():
		return node.get_class()
	return "%s (%s)" % [text, node.get_class()] if text != node.get_class() else text


# The materials on this frame's added nodes (each named by its file, its shader's file or its kind)
func _materials_text() -> String:
	var seen := {}
	for node in _added_before + _added:
		if not is_instance_valid(node):
			continue
		var found: Array = []
		if node is GeometryInstance3D:
			var geometry := node as GeometryInstance3D
			found.append(geometry.material_override)
			found.append(geometry.material_overlay)
			if node is MeshInstance3D and (node as MeshInstance3D).mesh:
				var mesh := (node as MeshInstance3D).mesh
				for s in mesh.get_surface_count():
					found.append(mesh.surface_get_material(s))
			if node is GPUParticles3D:
				found.append((node as GPUParticles3D).process_material)
		elif node is CanvasItem:
			found.append((node as CanvasItem).material)
		for material in found:
			if material is Material:
				seen[_material_name(material)] = true
	return ", ".join(PackedStringArray(seen.keys()))


static func _material_name(material: Material) -> String:
	if not material.resource_path.is_empty():
		return material.resource_path.get_file()
	if material is ShaderMaterial and (material as ShaderMaterial).shader:
		var shader := (material as ShaderMaterial).shader
		return "ShaderMaterial (%s)" % (shader.resource_path.get_file() if not shader.resource_path.is_empty() else "built-in shader")
	if not material.resource_name.is_empty():
		return "%s (%s)" % [material.resource_name, material.get_class()]
	return material.get_class()
