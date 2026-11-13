class_name Survival
extends Node
## The player's survival: hunger, stamina and warmth (warmth only while it's switched on, see
## WARMTH_SETTING), whether you're sheltered or shut in a room, eating, sleeping through the night
## and the torch in your hand burning down. A child of the player (see player.gd, which forwards its
## old functions and values here). Saved with the player, under its "hunger", "warmth", "stamina"
## and "torch_left" keys.
##
## Each frame the player calls update() (it says whether you're sprinting and holding a torch), then
## burn_torch(). Messages for the player go out as `message`, the vitals panel's values as
## `vitals_changed`, and falling asleep as `fell_asleep` (the player stops placing and stands still).

## A short message for the player ("You're not hungry")
signal message(text: String)
## Hunger and stamina now, 0 to 100 (each frame)
signal vitals_changed(hunger: float, stamina: float)
## Sleep has begun (the screen is fading out)
signal fell_asleep

## Sprinting: how much faster hunger drains
const SPRINT_HUNGER := 1.5
## Stamina (0 to 100): what sprinting costs per second, and what a jump and a tool swing (chopping,
## mining) cost each; how fast it comes back (per second) once you've spent none for REGEN_DELAY
## seconds; and, once it hits 0, how high it must climb back before you can sprint or swing again
const SPRINT_STAMINA := 12.0
const JUMP_STAMINA := 8.0
const SWING_STAMINA := 6.0
const STAMINA_REGEN := 20.0
const STAMINA_REGEN_DELAY := 1.0
const STAMINA_RECOVER := 15.0
## Starving: the most stamina you can have, and how fast it comes back (0.5 = half as fast). Well
## fed is full on both; in between eases from one to the other as hunger runs down.
const STARVING_MAX_STAMINA := 50.0
const STARVING_STAMINA_REGEN := 0.5
## The project setting that switches warmth (and the cold) on. Off for now: warmth returns for cold
## regions and winter. While off there's no warmth meter, no cold, and no shelter messages; fires
## still give light and shelter checks still run.
const WARMTH_SETTING := "game/survival/warmth_enabled"
## Hunger and warmth follow the sun's clock (its Day Minutes and Night Minutes), so they stay fair
## however long the day is. A full belly lasts this many whole days (a day and its night).
const FULL_BELLY_DAYS := 1.0
## How much hunger one berry fills back up
const BERRY_FOOD = 15.0
## Out in the open with no fire: how much warmth a whole night costs at the cold of deep night, and
## how much a whole day gives back at the warmth of midday (dawn and dusk sit in between)
const NIGHT_CHILL_PER_NIGHT := 90.0
const DAY_WARMTH_PER_DAY := 18.0
## If there's no sun to ask, these day and night lengths are used, in seconds
const FALLBACK_DAY_SECONDS := 1680.0
const FALLBACK_NIGHT_SECONDS := 720.0
## Warmth gained per second standing by a lit campfire
const FIRE_WARMTH = 6.0
## Inside a shelter, the cold gets to you only this fast (0.35 = a bit over a third as fast)
const SHELTER_CHILL = 0.35
## Sleeping: when you wake (0.27 is just after sunrise), how much hunger a night costs, how close a
## lit campfire must be to wake up warm, and how warm you are without one
const WAKE_TIME := 0.27
const SLEEP_HUNGER := 25.0
const SLEEP_FIRE_RANGE := 5.0
const COLD_WAKE_WARMTH := 25.0
## How long the screen takes to fade out and back in, and how long it stays dark, in seconds
const SLEEP_FADE := 1.0
const SLEEP_DARK := 0.6
## A torch burns for this share of a night while held, and while held the cold gets to you only
## this fast (0.75 = three quarters as fast)
const TORCH_NIGHTS := 0.5
const TORCH_CHILL := 0.75
## Checking for a roof overhead and a closed room around you: how often, in seconds, how far the
## rays look, in meters, and how many go round the room
const SHELTER_CHECK_SECONDS := 0.4
const SHELTER_REACH := 14.0
const ENCLOSURE_RAYS := 32

## 100 = full, 0 = starving
var hunger := 100.0
## 100 = toasty, 0 = freezing (only changes while warmth is switched on, see WARMTH_SETTING)
var warmth := 100.0
## 100 = fresh, 0 = spent (the most you can have drops while hungry, see max_stamina)
var stamina := 100.0
## Whether warmth and the cold are switched on (read once from the project settings)
var warmth_on: bool = ProjectSettings.get_setting(WARMTH_SETTING, false)
## Ran out of stamina: no sprinting or swinging until it's back above STAMINA_RECOVER
var winded := false
## Asleep right now (the screen faded out)
var sleeping := false
## Shut in a room you've built (see _check_shelter)
var enclosed := false
## Seconds left on the torch in your hand (0 = a fresh one is lit when you next hold one)
var torch_left := 0.0

## The player's body (where you stand, its rays), half its height (its origin is its middle), what
## you own (berries to eat, the torch) and the black screen sleep fades through. Set by the player.
var body: CharacterBody3D
var half_height := 1.0
var inventory: PlayerInventory
var fade: SleepFade

# Seconds since stamina was last spent (it starts coming back after STAMINA_REGEN_DELAY)
var _since_spent := 0.0
# Under a roof you've built (see _check_shelter), and when to check again
var _under_roof := false
var _shelter_check_in := 0.0


## Each frame: hunger drains (faster sprinting), stamina comes back, shelter is checked, warmth
## follows the day and night (while on), then `vitals_changed`
func update(delta: float, sprinting: bool, holding_torch: bool) -> void:
	var daylight := 1.0
	var day_seconds := FALLBACK_DAY_SECONDS
	var night_seconds := FALLBACK_NIGHT_SECONDS
	var sun = get_tree().get_first_node_in_group("sun")
	if sun:
		daylight = sun.daylight
		day_seconds = sun.day_seconds()
		night_seconds = sun.night_seconds()

	# Sprinting works up an appetite
	var appetite := SPRINT_HUNGER if sprinting else 1.0
	# The god cheat: hunger never drops
	if not DevCheats.god:
		hunger = maxf(hunger - 100.0 / (FULL_BELLY_DAYS * (day_seconds + night_seconds)) * appetite * delta, 0.0)

	_update_stamina(delta)

	# Shelter is checked whether or not warmth is on (beds and settlers will need it too)
	_check_shelter(delta)
	var sheltered := is_sheltered()
	if warmth_on:
		# Chilly at night, slowly warming by day, and quickly warming by a fire
		var night_chill := NIGHT_CHILL_PER_NIGHT / night_seconds
		var day_warmth := DAY_WARMTH_PER_DAY / day_seconds
		var warmth_change := lerpf(-night_chill, day_warmth, daylight)
		# Out of the wind, the cold creeps in much more slowly; shut in a room, not at all
		if sheltered and warmth_change < 0.0:
			warmth_change *= SHELTER_CHILL
		if enclosed and warmth_change < 0.0:
			warmth_change = 0.0
		# A lit torch in your hand keeps a little of the cold off
		if holding_torch and warmth_change < 0.0:
			warmth_change *= TORCH_CHILL
		if _near_lit_fire():
			warmth_change = FIRE_WARMTH
		if DevCheats.god:
			warmth_change = maxf(warmth_change, 0.0)
		warmth = clampf(warmth + warmth_change * delta, 0.0, 100.0)

	vitals_changed.emit(hunger, stamina)


## What's run out, for the status line ("You're starving! Eat something [F]"), and while warmth is on,
## whether you're indoors or sheltered
func warnings() -> PackedStringArray:
	var out: PackedStringArray = []
	if hunger <= 0.0:
		out.append("You're starving! Eat something [F]")
	if warmth_on:
		if warmth <= 0.0:
			out.append("You're freezing! Get to a fire")
		if out.is_empty() and enclosed:
			out.append("Indoors: the cold can't get in here")
		elif out.is_empty() and is_sheltered():
			out.append("Sheltered: the cold creeps in slowly here")
	return out


## True while starving, or freezing while warmth is on: you trudge at half speed
func slowed() -> bool:
	return hunger <= 0.0 or (warmth_on and warmth <= 0.0)


## The most stamina you can have right now: 100 when well fed, easing down to
## STARVING_MAX_STAMINA as hunger runs out
func max_stamina() -> float:
	return lerpf(STARVING_MAX_STAMINA, 100.0, clampf(hunger / 100.0, 0.0, 1.0))


## Spends a tool swing's stamina (chopping, mining). Returns false, spending nothing, if you're too
## winded to swing; the thing being hit should then do nothing.
func swing_tool() -> bool:
	if winded:
		message.emit("Too tired to swing. Catch your breath")
		return false
	spend_stamina(SWING_STAMINA)
	return true


## Takes stamina away (never below 0) and holds off its coming back; at 0 you're winded. Not with
## the god cheat on.
func spend_stamina(amount: float) -> void:
	if DevCheats.god:
		return
	stamina = maxf(stamina - amount, 0.0)
	_since_spent = 0.0
	if stamina <= 0.0:
		winded = true


# Stamina comes back once none has been spent for a moment, more slowly the hungrier you are, up to
# max_stamina (which also drops while hungry). Winded ends once it's back above STAMINA_RECOVER.
func _update_stamina(delta: float) -> void:
	var fed := clampf(hunger / 100.0, 0.0, 1.0)
	var top := max_stamina()
	_since_spent += delta
	if _since_spent >= STAMINA_REGEN_DELAY:
		stamina += STAMINA_REGEN * lerpf(STARVING_STAMINA_REGEN, 1.0, fed) * delta
	stamina = clampf(stamina, 0.0, top)
	if winded and stamina > STAMINA_RECOVER:
		winded = false


## Eats a berry, if you have one and aren't full
func eat() -> void:
	if hunger >= 100.0:
		message.emit("You're not hungry")
	elif inventory.remove("Berries", 1):
		hunger = minf(hunger + BERRY_FOOD, 100.0)
	else:
		message.emit("You have nothing to eat")


## Sleeps through to morning, if it's night: the screen fades to black, the clock jumps to just
## after sunrise, then it fades back in. A night's sleep costs hunger; you wake up warm only if a
## lit campfire was within reach of where you slept.
func sleep(where: Vector3) -> void:
	var sun = get_tree().get_first_node_in_group("sun")
	if sun == null or sleeping:
		return
	# Night is when the sun is below the horizon: before sunrise (0.25) or after sunset (0.75)
	if sun.time_of_day > 0.25 and sun.time_of_day < 0.75:
		message.emit("You can only sleep at night.")
		return
	var warm := false
	for fire in get_tree().get_nodes_in_group("campfires"):
		if fire.is_lit() and where.distance_to(fire.global_position) <= SLEEP_FIRE_RANGE:
			warm = true
	sleeping = true
	fell_asleep.emit()
	fade.play(SLEEP_FADE, SLEEP_DARK, func():
		# Sleeping from before midnight wakes you on the next day
		if sun.time_of_day > 0.5:
			sun.day += 1
		sun.time_of_day = WAKE_TIME
		if not DevCheats.god:
			hunger = maxf(hunger - SLEEP_HUNGER, 0.0)
		stamina = max_stamina()
		winded = false
		if warmth_on:
			warmth = 100.0 if warm else COLD_WAKE_WARMTH,
	func():
		sleeping = false
		SaveGame.autosave())


## A torch in your hand burns down; when it's out, it's gone and the next one is ready to light
func burn_torch(delta: float, holding_torch: bool) -> void:
	if not holding_torch:
		return
	var burn_time := TORCH_NIGHTS * FALLBACK_NIGHT_SECONDS
	var sun = get_tree().get_first_node_in_group("sun")
	if sun:
		burn_time = TORCH_NIGHTS * sun.night_seconds()
	if torch_left <= 0.0:
		torch_left = burn_time
	torch_left -= delta
	if torch_left <= 0.0:
		torch_left = 0.0
		inventory.remove("Torch", 1)
		message.emit("Your torch burned out")


## True while standing inside a shelter (any Area3D in the "shelters" group), like the intact half
## of the wreck, or under a roof you've built. Wind and rain will check this too, later.
func is_sheltered() -> bool:
	if _under_roof or enclosed:
		return true
	for shelter in get_tree().get_nodes_in_group("shelters"):
		if shelter.overlaps_body(body):
			return true
	return false


# Under a roof, and shut in a room, checked a few times a second with rays: one up for a roof, one
# down for a floor, a ring of them across the room (below window height) that must all meet a wall
# or a closed door, and some up from around the room that must all meet a roof or a floor above.
# Works for round rooms as for square ones.
func _check_shelter(delta: float) -> void:
	_shelter_check_in -= delta
	if _shelter_check_in > 0.0:
		return
	_shelter_check_in = SHELTER_CHECK_SECONDS
	# The body's origin is its middle: the feet are half its height below
	var feet := body.global_position + Vector3.DOWN * half_height
	var overhead := _roof_hit(feet + Vector3.UP * 1.6, feet + Vector3.UP * SHELTER_REACH)
	_under_roof = overhead != null and (overhead.is_roof() or overhead.is_floor())
	enclosed = false
	if not _under_roof:
		return
	var underfoot := _piece_hit(feet + Vector3.UP * 0.3, feet + Vector3.DOWN * 1.0)
	if underfoot == null or not underfoot.is_floor():
		return
	for i in ENCLOSURE_RAYS:
		var direction := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / ENCLOSURE_RAYS)
		var reach := INF
		for height in [0.5, 1.0]:
			var from: Vector3 = feet + Vector3.UP * height
			var hit := _wall_hit(from, from + direction * SHELTER_REACH)
			# A gap, something that isn't part of the building, or a door standing open
			if hit.is_empty() or not hit["collider"] is BuildPiece or not hit["collider"].is_closed():
				return
			reach = minf(reach, from.distance_to(hit["position"]))
		# The ceiling must cover the room, not just the spot you're standing on
		if i % 4 == 0:
			var inside := feet + direction * reach * 0.7 + Vector3.UP * 1.6
			var ceiling := _roof_hit(inside, inside + Vector3.UP * SHELTER_REACH)
			if ceiling == null or not (ceiling.is_roof() or ceiling.is_floor()):
				return
	enclosed = true


# What a level ray across a room meets, looking past furniture, chimneys and the workbench, chest
# and campfire (things standing in the room, not part of its walls)
func _wall_hit(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var skip: Array[RID] = [body.get_rid()]
	for i in 8:
		query.exclude = skip
		var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return hit
		var other: Object = hit["collider"]
		var in_room: bool = (other is BuildPiece and (other.is_furniture() or other.is_chimney())) \
				or (other is Node and ((other as Node).is_in_group("buildings") or (other as Node).is_in_group("settlers")))
		if not in_room:
			return hit
		skip.append(hit["rid"])
	return {}


# Like _piece_hit, looking up for a roof: chimneys and furniture (a chimney stack passing through
# the roof, a tall shelf) are looked past, so they never break the shelter or enclosure check
func _roof_hit(from: Vector3, to: Vector3) -> BuildPiece:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var skip: Array[RID] = [body.get_rid()]
	for i in 8:
		query.exclude = skip
		var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or not hit["collider"] is BuildPiece:
			return null
		var piece: BuildPiece = hit["collider"]
		if not (piece.is_chimney() or piece.is_furniture()):
			return piece
		skip.append(piece.get_rid())
	return null


# The building piece a line from one point to another meets first, or null if it meets something
# else first (or nothing)
func _piece_hit(from: Vector3, to: Vector3) -> BuildPiece:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not hit["collider"] is BuildPiece:
		return null
	return hit["collider"]


func _near_lit_fire() -> bool:
	for fire in get_tree().get_nodes_in_group("campfires"):
		if fire.is_lit() and body.global_position.distance_to(fire.global_position) < fire.heat_radius():
			return true
	return false


func save_data() -> Dictionary:
	return {"hunger": hunger, "warmth": warmth, "stamina": stamina, "torch_left": torch_left}


func load_data(data: Dictionary) -> void:
	hunger = float(data.get("hunger", hunger))
	# Older saves have warmth but no stamina: with warmth switched off, their warmth is ignored
	warmth = float(data.get("warmth", warmth)) if warmth_on else 100.0
	stamina = clampf(float(data.get("stamina", 100.0)), 0.0, max_stamina())
	winded = false
	_since_spent = STAMINA_REGEN_DELAY
	torch_left = float(data.get("torch_left", 0.0))
