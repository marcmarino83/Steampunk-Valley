class_name SettlementEconomy
extends Node
## The settlement's daily round of work and food (run by the SettlerManager on the sun's clock).
##
## At dawn every working workplace with a worker makes its day's output (PlotType.daily_output
## and its slider-shared output, see Plot.daily_output) into town storage (see TownStorage) while
## it has room, otherwise into the workplace's own storage chest; a hungry worker makes half. What
## fits in neither is lost: "Forager's Hut: Town storage full (4 herbs lost)" (or "chest full" with
## no working Storehouse). With neither a chest nor town storage, the whole day's output is lost.
##
## At dusk every settler eats MEAL food (berries first, then mushrooms), from town storage first,
## then from the nearest storage chest belonging to a working plot that has any, then from any
## other chest belonging to a plot.
## Chests outside every plot are the player's own: settlers never eat from them. One who
## can't eat their fill is hungry for the day; HUNGRY_DAYS_TO_LEAVE hungry days in a row and they
## leave the settlement.

## Sent with a message for the player ("Forager's Hut: chest full", "Ada Cobb has left...")
signal notice(text: String)

## What a settler eats each dusk, and what counts as food (eaten in this order)
const MEAL := 2
const FOODS := ["Berries", "Mushrooms"]
const HUNGRY_DAYS_TO_LEAVE := 3
const CHEST_NAME := "Storage Chest"

var manager: SettlerManager


## The day's output from every working workplace with a worker, into its chest
func dawn() -> void:
	var notes: PackedStringArray = []
	for plot in manager.plots.all_plots():
		if not SettlerManager.is_workplace(plot) or not plot.working:
			continue
		var crew: Array = manager.workers(plot).filter(func(s): return not s.leaving)
		if crew.is_empty():
			continue
		var made := output_today(plot, crew)
		if made.is_empty():
			continue
		var town := manager.plots.town
		var chest := chest_of(plot)
		if chest == null and not town.is_open():
			notes.append("%s: no storage chest, today's output was lost" % plot.plot_name)
			continue
		# Into town storage while it has room, then the hut's own chest
		var lost: PackedStringArray = []
		for item in made:
			if town.can_take(item):
				town.put(item, made[item])
			elif chest and chest.can_take(item):
				chest.put(item, made[item])
			else:
				lost.append("%d %s" % [made[item], item.to_lower()])
		town.changed.emit()
		if chest:
			chest.changed.emit()
		if not lost.is_empty():
			var full := "Town storage full" if town.is_open() else "chest full"
			notes.append("%s: %s (%s lost)" % [plot.plot_name, full, ", ".join(lost)])
	for note in notes:
		notice.emit(note)


## What a workplace makes today with these workers: its full day's output, halved for each
## hungry worker's share (a place with no worker in it makes nothing)
func output_today(plot: Plot, crew: Array) -> Dictionary:
	var places := maxi(plot.plot_type.workers, 1)
	var strength := 0.0
	for settler in crew:
		strength += 0.5 if settler.is_hungry() else 1.0
	strength = minf(strength / places, 1.0)
	var full := plot.daily_output()
	var total := 0
	for item in full:
		total += int(full[item])
	var wanted := roundi(total * strength)
	if wanted <= 0:
		return {}
	if wanted == total:
		return full
	# Shared out in the same proportions, adding up exactly
	var made := PlotType.split(wanted, full)
	for item in made.keys():
		if made[item] <= 0:
			made.erase(item)
	return made


## Every settler's meal (berries or mushrooms); the hungry go hungry, and some leave
func dusk() -> void:
	var hungry: PackedStringArray = []
	for settler in manager.all_settlers():
		if settler.leaving:
			continue
		var eaten := _feed(settler.global_position)
		if eaten >= MEAL:
			settler.hungry_days = 0
			continue
		settler.hungry_days += 1
		if settler.hungry_days >= HUNGRY_DAYS_TO_LEAVE:
			notice.emit("%s has left the settlement after %d days without food." % [settler.settler_name, settler.hungry_days])
			manager.send_away(settler)
		else:
			hungry.append(settler.settler_name)
	if not hungry.is_empty():
		notice.emit("No food for %s tonight: they're hungry and will work at half pace." % ", ".join(hungry))


# Eats up to a meal from town storage first, then the chests, nearest working plot's first;
# returns how much was eaten
func _feed(spot: Vector3) -> int:
	var eaten := 0
	var town := manager.plots.town
	for food in FOODS:
		if eaten < MEAL:
			eaten += town.take(food, MEAL - eaten)
	if eaten > 0:
		town.changed.emit()
	for i in 8:
		if eaten >= MEAL:
			break
		var chest := _food_chest(spot)
		if chest == null:
			break
		for food in FOODS:
			if eaten < MEAL:
				eaten += chest.take(food, MEAL - eaten)
		chest.changed.emit()
	return eaten


# The chest to eat from: the nearest storage chest of a working plot that holds food, else the
# nearest storage chest anywhere that does
func _food_chest(spot: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for plot in manager.plots.all_plots():
		if not plot.working:
			continue
		for item in manager.plots.owned_items(plot):
			if manager.plots.name_of(item) == CHEST_NAME and _food_in(item) > 0:
				var distance: float = item.global_position.distance_to(spot)
				if distance < best_distance:
					best = item
					best_distance = distance
	if best:
		return best
	for chest in settlement_chests():
		if _food_in(chest) > 0:
			var distance: float = chest.global_position.distance_to(spot)
			if distance < best_distance:
				best = chest
				best_distance = distance
	return best


## A plot's own storage chest (the first one it owns), or null
func chest_of(plot: Plot) -> Node3D:
	for item in manager.plots.owned_items(plot):
		if manager.plots.name_of(item) == CHEST_NAME:
			return item
	return null


## Every storage chest in the world
func all_chests() -> Array:
	return get_tree().get_nodes_in_group("buildings").filter(func(b): return is_instance_valid(b) and b.has_method("can_take") and not b.is_queued_for_deletion())


## The settlement's storage chests: those belonging to a plot (any plot, working or not). Chests
## outside every plot are the player's own, and settlers never touch them.
func settlement_chests() -> Array:
	return all_chests().filter(func(c): return manager.plot(manager.plots.plot_of(c)) != null)


func _food_in(chest: Node) -> int:
	var total := 0
	for food in FOODS:
		total += int(chest.contents.get(food, 0))
	return total


## All the food settlers can eat: in town storage and every storage chest belonging to a plot
func food_stored() -> int:
	var total := 0
	for food in FOODS:
		total += int(manager.plots.town.contents.get(food, 0))
	for chest in settlement_chests():
		total += _food_in(chest)
	return total


## How many days the stored food lasts everyone in the settlement (-1 with no settlers)
func days_of_food() -> int:
	var mouths: int = manager.all_settlers().filter(func(s): return not s.leaving).size()
	if mouths == 0:
		return -1
	return floori(food_stored() / float(MEAL * mouths))
