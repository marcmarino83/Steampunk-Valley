class_name Respawner
extends Node
## Brings gathered things back after a while: pickups, berries, trees, mined boulders. When one is
## used up, a booking goes in here: when it's due, where it is, what kind of return it is and
## which thing (by its id). Bookings are plain data, so they're kept in the save. When one is due
## and the player is away, `handler` is called with the kind and id (the valley does the rest).
##
## Time is counted in in-game days on the sun's clock, so sleeping through the night counts too.
## Nothing comes back while the player is close by or looking at the spot, so nothing pops in in
## front of them; it just waits until they've gone. The times are on the Valley node.

## Nothing comes back closer than this to the player, in meters
var min_distance := 30.0
## Called as handler.call(kind, id) when a booking comes due
var handler: Callable

## How often to check what's due, in seconds
const CHECK_EVERY := 2.0
## At most this many things come back in one check; if more are due the next check is SOON
const MAX_PER_CHECK := 6
const SOON := 0.1
## How long a whole day is if there's no sun to ask, in seconds
const FALLBACK_DAY_SECONDS := 2400.0

# Days counted here only when there's no sun
var _days_without_sun := 0.0
# Each booking: {"due": days, "where": [x, y, z], "kind": String, "id": String}
var _bookings: Array = []
var _until_check := 0.0


func _ready() -> void:
	add_to_group("respawner")
	add_to_group("saveable")


## In-game days since the game began
func now_days() -> float:
	var sun = get_tree().get_first_node_in_group("sun")
	return sun.total_days() if sun else _days_without_sun


## Books a return after this many in-game days, at this spot (global position)
func schedule(after_days: float, where: Vector3, kind: String, id: String) -> void:
	_bookings.append({"due": now_days() + after_days, "where": SaveGame.from_vector(where), "kind": kind, "id": id})


func _process(delta: float) -> void:
	if get_tree().get_first_node_in_group("sun") == null:
		_days_without_sun += delta / FALLBACK_DAY_SECONDS
	_until_check -= delta
	if _until_check > 0.0:
		return
	_until_check = CHECK_EVERY
	var timing := SpikeLog.begin()
	var now := now_days()
	var brought_back := 0
	for i in range(_bookings.size() - 1, -1, -1):
		var booking: Dictionary = _bookings[i]
		if float(booking["due"]) > now or not _out_of_sight(SaveGame.to_vector(booking["where"])):
			continue
		# A few at a time (after a long sleep many are due at once); the rest follow shortly
		if brought_back >= MAX_PER_CHECK:
			_until_check = SOON
			break
		_bookings.remove_at(i)
		brought_back += 1
		if handler.is_valid():
			handler.call(booking["kind"], booking["id"])
	SpikeLog.end("respawns", timing)


# True if the player is far enough away and not looking toward the spot
func _out_of_sight(where: Vector3) -> bool:
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return true
	if player.global_position.distance_to(where) < min_distance:
		return false
	var camera := get_viewport().get_camera_3d()
	return camera == null or not camera.is_position_in_frustum(where)


func save_key() -> String:
	return "respawns"


func save_priority() -> int:
	return 20


func save_data() -> Dictionary:
	return {"bookings": _bookings.duplicate(true)}


func load_data(data: Dictionary) -> void:
	_bookings = Array(data.get("bookings", [])).duplicate(true)
