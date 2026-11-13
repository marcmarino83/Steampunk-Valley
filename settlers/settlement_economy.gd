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
## At dusk every settler eats MEAL food: first any of their own (quest villagers arrive with
## ARRIVAL_FOOD_DAYS' worth), then berries before mushrooms, from town storage first,
## then from the nearest storage chest belonging to a working plot that has any, then from any
## other chest belonging to a plot.
## Chests outside every plot are the player's own: settlers never eat from them. One who
## can't eat their fill is hungry for the day; HUNGRY_DAYS_TO_LEAVE hungry days in a row and they
## leave the settlement. Quest villagers never leave: hungry, they stop working instead (and make
## nothing) until they're fed. Visitors don't eat.
##
## plan_day runs the same steps on copies of the stores, for the Village screen's ledger.

## Sent with a message for the player ("Forager's Hut: chest full", "Ada Cobb has left...")
signal notice(text: String)

## What a settler eats each dusk, and what counts as food (eaten in this order)
const MEAL := 2
## Days of their own food the quest villagers arrive with (see Settler.own_food)
const ARRIVAL_FOOD_DAYS := 3
const FOODS := ["Berries", "Mushrooms"]
const HUNGRY_DAYS_TO_LEAVE := 3
const CHEST_NAME := "Storage Chest"

var manager: SettlerManager


## The day's output from every working workplace with a worker, into its chest
func dawn() -> void:
	var notes: PackedStringArray = []
	var outputs := outputs_today()
	for plot in outputs:
		var made: Dictionary = outputs[plot]
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


## What every working workplace with a worker makes at dawn, with its workers as they are now:
## {plot: {item: amount}} (places that would make nothing are left out)
func outputs_today() -> Dictionary:
	var out := {}
	for plot in manager.plots.all_plots():
		if not SettlerManager.is_workplace(plot) or not plot.working:
			continue
		var crew: Array = manager.workers(plot).filter(func(s): return not s.leaving)
		if crew.is_empty():
			continue
		var made := output_today(plot, crew)
		if not made.is_empty():
			out[plot] = made
	return out


## The next day as planned (the Village screen's Resources tab): what dawn makes and what dusk's
## meals eat, worked out by the same steps as dawn() and dusk() on copies of the stores, so nothing
## changes. Taken from the settlers' and the plots' state now (workers, hunger, slider settings).
##   made:   {plot: {item: amount}}, as outputs_today()
##   eaten:  {food: amount} eaten at dusk
##   eaters: {food: how many settlers eat some of it}
##   short:  meals' worth of food missing (0: everyone eats their fill)
## The player's own takings aren't in it (no one can plan them); output lost for want of room
## still counts as made.
func plan_day() -> Dictionary:
	var made := outputs_today()
	var stores := _stores(true)
	var town: Dictionary = stores["town"]
	var room: int = stores["room"]
	# The output goes in as dawn puts it: into town storage while it has room, then the hut's chest
	for plot in made:
		var chest := chest_of(plot)
		var own: Variant = stores["chests"].get(chest) if chest else null
		for item in made[plot]:
			var amount := int(made[plot][item])
			if room > 0 and (town.has(item) or town.size() < room):
				town[item] = int(town.get(item, 0)) + amount
			elif own != null and (own.has(item) or own.size() < _slots_of(chest)):
				own[item] = int(own.get(item, 0)) + amount
	var eaten := {}
	var eaters := {}
	var short := 0
	for settler in manager.all_settlers():
		if settler.leaving:
			continue
		var ate := {}
		# (their own food isn't from the stores: it only makes the meal they need smaller)
		var own := mini(settler.own_food, MEAL)
		short += MEAL - own - _feed(settler.global_position, stores, ate, MEAL - own)
		for food in ate:
			eaten[food] = int(eaten.get(food, 0)) + int(ate[food])
			eaters[food] = int(eaters.get(food, 0)) + 1
	return {"made": made, "eaten": eaten, "eaters": eaters, "short": short}


## What a workplace makes today with these workers: its full day's output, halved for each
## hungry worker's share (a place with no worker in it makes nothing)
func output_today(plot: Plot, crew: Array) -> Dictionary:
	var places := maxi(plot.plot_type.workers, 1)
	var strength := 0.0
	for settler in crew:
		# (a quest villager whose needs aren't met doesn't work at all)
		if not settler.unmet_need().is_empty():
			continue
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
	var stopped: PackedStringArray = []
	var stores := _stores(false)
	for settler in manager.all_settlers():
		if settler.leaving:
			continue
		var own := mini(settler.own_food, MEAL)
		settler.own_food -= own
		var eaten := own + _feed(settler.global_position, stores, {}, MEAL - own)
		if eaten >= MEAL:
			settler.hungry_days = 0
			continue
		settler.hungry_days += 1
		if settler.quest:
			# Quest villagers never leave: they stop working until they're fed
			stopped.append(settler.settler_name)
		elif settler.hungry_days >= HUNGRY_DAYS_TO_LEAVE:
			notice.emit("%s has left the settlement after %d days without food." % [settler.settler_name, settler.hungry_days])
			manager.send_away(settler)
		else:
			hungry.append(settler.settler_name)
	if stores["town_touched"]:
		manager.plots.town.changed.emit()
	for chest in stores["touched"]:
		if is_instance_valid(chest):
			chest.changed.emit()
	if not hungry.is_empty():
		notice.emit("No food for %s tonight: they're hungry and will work at half pace." % ", ".join(hungry))
	if not stopped.is_empty():
		notice.emit("No food for %s tonight: \"We can't work hungry.\" They won't work until they're fed." % ", ".join(stopped))
	# Food the player has, but where settlers never look: say where it has to go
	if (not hungry.is_empty() or not stopped.is_empty()) and SettlerHints.food_out_of_reach(manager):
		notice.emit(SettlerHints.FOOD_PLACE)


# The stores meals come from, as plain dictionaries: the town storage pool, its room (slots), and
# every storage chest's contents (chest -> its contents). Dusk works on the real ones (the very
# dictionaries the storage holds); plan_day on copies, by the same steps. "town_touched" and
# "touched" (chest -> true) note what was eaten from, so dusk can say they changed.
func _stores(copies: bool) -> Dictionary:
	var town := manager.plots.town
	var chests := {}
	for chest in all_chests():
		chests[chest] = chest.contents.duplicate() if copies else chest.contents
	return {"town": town.contents.duplicate() if copies else town.contents, "room": town.capacity(),
		"chests": chests, "town_touched": false, "touched": {}}


# Eats up to `wanted` food from town storage first, then the chests, nearest working plot's
# first; returns how much was eaten, adding each food to `ate` ({food: amount})
func _feed(spot: Vector3, stores: Dictionary, ate: Dictionary, wanted := MEAL) -> int:
	var eaten := 0
	for food in FOODS:
		if eaten < wanted:
			var got := _take(stores["town"], food, wanted - eaten)
			if got > 0:
				eaten += got
				ate[food] = int(ate.get(food, 0)) + got
				stores["town_touched"] = true
	for i in 8:
		if eaten >= wanted:
			break
		var chest := _food_chest(spot, stores["chests"])
		if chest == null:
			break
		for food in FOODS:
			if eaten < wanted:
				var got := _take(stores["chests"][chest], food, wanted - eaten)
				eaten += got
				if got > 0:
					ate[food] = int(ate.get(food, 0)) + got
		stores["touched"][chest] = true
	return eaten


# Takes up to `amount` of an item out of a store's contents (as a chest's take does); how many
static func _take(contents: Dictionary, item: String, amount: int) -> int:
	var have: int = contents.get(item, 0)
	var taken := mini(have, amount)
	if taken <= 0:
		return 0
	if taken == have:
		contents.erase(item)
	else:
		contents[item] = have - taken
	return taken


# How many kinds of item a storage chest holds (its SLOTS)
static func _slots_of(chest: Node) -> int:
	return int(chest.get_script().get_script_constant_map().get("SLOTS", 0)) if chest.get_script() else 0


# The chest to eat from: the nearest storage chest of a working plot that holds food, else the
# nearest storage chest anywhere that does (`chests`: chest -> its contents, see _stores)
func _food_chest(spot: Vector3, chests: Dictionary) -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for plot in manager.plots.all_plots():
		if not plot.working:
			continue
		for item in manager.plots.owned_items(plot):
			if chests.has(item) and manager.plots.name_of(item) == CHEST_NAME and _food_in_contents(chests[item]) > 0:
				var distance: float = item.global_position.distance_to(spot)
				if distance < best_distance:
					best = item
					best_distance = distance
	if best:
		return best
	for chest in settlement_chests():
		if chests.has(chest) and _food_in_contents(chests[chest]) > 0:
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
	return _food_in_contents(chest.contents)


static func _food_in_contents(contents: Dictionary) -> int:
	var total := 0
	for food in FOODS:
		total += int(contents.get(food, 0))
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
