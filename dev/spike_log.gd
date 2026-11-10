class_name SpikeLog
extends Node
## The lag spike logger (debug builds only; Settings, "Log lag spikes", off by default). Whenever a
## frame takes longer than THRESHOLD_MS it writes one line to the output: how long the frame took,
## what the player was doing, the time each instrumented system spent in that frame, how many
## nodes were added, and how many shader pipelines were compiled for the first time (a first-time
## shader or material compile shows up as a frame with pipelines compiled).
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

var _last_usec := 0
var _last_compiles := -1


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
	get_tree().node_added.connect(func(_node): _nodes_added += 1)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var compiles := _pipeline_compiles()
	if enabled and _last_usec > 0:
		var ms := (now - _last_usec) / 1000.0
		if ms > THRESHOLD_MS:
			_report(ms, compiles - _last_compiles if _last_compiles >= 0 else 0)
	_last_usec = now
	_last_compiles = compiles
	_times.clear()
	_calls.clear()
	_notes.clear()
	_nodes_added = 0


# Writes the spike's line and keeps it
func _report(ms: float, compiles: int) -> void:
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
	spikes.append({"ms": ms, "at_ms": Time.get_ticks_msec(), "activity": activity, "systems": systems, "nodes": _nodes_added, "compiles": compiles, "notes": Array(_notes)})
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
	if placer and placer.get("_pieces") and placer._pieces.get("_hold_time") and float(placer._pieces._hold_time) > 0.0:
		return "taking down a piece"
	var body := player as CharacterBody3D
	if body and Vector2(body.velocity.x, body.velocity.z).length() > 0.5:
		return "walking"
	return "standing"


# Shader pipelines compiled so far, all kinds (a new one means a first-time shader compile)
func _pipeline_compiles() -> int:
	var total := 0
	for info in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
		total += RenderingServer.get_rendering_info(info)
	return total
