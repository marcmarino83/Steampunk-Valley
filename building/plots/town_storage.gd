class_name TownStorage
extends Node
## The settlement's town storage: one shared pool held by every working Storehouse together. Each
## plot type that holds town storage (PlotType.town_storage_item and town_storage_slots: the
## Storehouse Storage, 60 slots) adds that many slots while it's working and owns at least one of
## that item. A slot holds any amount of one item, as in a chest.
##
## It has a chest's ways in and out (contents, can_take, put, take, take_all and `changed`), so the
## chest screen, settlers and refunds use it the same way.
##
## Nothing in it is lost when its room shrinks:
##   - A Storehouse that stops working (missing requirements, or an older Storehouse that hasn't
##     built its storage yet) keeps its share: the pool may then hold more kinds than it has room
##     for, and takes no new kinds (and no new stock at all while no Storehouse works) until there's
##     room again.
##   - A Storehouse that's removed: whatever the others have no room for drops in a bundle where it
##     stood, with a message.
## Its contents save with the Storehouse plots (see shares and load_share).

## What's in it changed (a day's output went in, a settler ate, the player moved something)
signal changed
## A message for the player (something dropped in a bundle because the storage shrank)
signal notice(text: String)

## The categories the Town Storage screen sorts by, in order
const CATEGORIES := ["Food", "Materials", "Tools", "Other"]
## Food (what settlers eat, and herbs)
const FOOD := ["Berries", "Mushrooms", "Herbs"]

var plots: PlotRegistry

## The pool, like {"Wood": 120, "Berries": 30}, in the order things were first put in
var contents := {}

# plot id -> how many slots each storage plot added when last checked (to tell which one shrank)
var _slots_by_plot := {}


## Every plot that holds town storage while working (working or not)
func storage_plots() -> Array:
	return plots.all_plots().filter(func(p): return p.plot_type.town_storage_slots > 0)


## The slots a plot adds: town_storage_slots while it's working and owns its storage item
func slots_of(plot: Plot) -> int:
	if not plot.working or plot.plot_type.town_storage_slots <= 0:
		return 0
	for item in plots.owned_items(plot):
		if plots.name_of(item) == plot.plot_type.town_storage_item:
			return plot.plot_type.town_storage_slots
	return 0


## All the slots every working storage plot adds together
func capacity() -> int:
	var total := 0
	for plot in storage_plots():
		total += slots_of(plot)
	return total


## How many slots are in use (one per kind of item)
func used() -> int:
	return contents.size()


## True if there's a working Storehouse at all
func is_open() -> bool:
	return capacity() > 0


## True if there's room for this item (some is already in, or a slot is free), with at least one
## working Storehouse
func can_take(item: String) -> bool:
	var room := capacity()
	return room > 0 and (contents.has(item) or contents.size() < room)


func put(item: String, amount: int) -> void:
	if amount > 0:
		contents[item] = int(contents.get(item, 0)) + amount


## Takes out up to `amount` of an item and says how many that was
func take(item: String, amount: int) -> int:
	var have: int = contents.get(item, 0)
	var taken := mini(have, amount)
	if taken <= 0:
		return 0
	if taken == have:
		contents.erase(item)
	else:
		contents[item] = have - taken
	return taken


## Takes out every one of an item and says how many that was
func take_all(item: String) -> int:
	var amount: int = contents.get(item, 0)
	contents.erase(item)
	return amount


## Puts in as much of these items as there's room for; returns what didn't fit
func store(items: Dictionary) -> Dictionary:
	var left := {}
	for item in items:
		if can_take(item):
			put(item, int(items[item]))
		else:
			left[item] = items[item]
	if left.size() < items.size():
		changed.emit()
	return left


## Food (or Materials, Tools, Other) for the Town Storage screen
static func category_of(item: String) -> String:
	if FOOD.has(item):
		return "Food"
	if ToolItem.exists_for(item):
		return "Tools"
	if InventorySlot.ITEM_ICONS.has(item) or InventorySlot.ITEM_COLORS.has(item):
		return "Materials"
	return "Other"


## The contents sorted by category (food, materials, tools, other), then by name
func sorted_contents() -> Dictionary:
	var items := contents.keys()
	items.sort_custom(func(a, b):
		var ca := CATEGORIES.find(category_of(a))
		var cb := CATEGORIES.find(category_of(b))
		if ca != cb:
			return ca < cb
		return String(a).naturalnocasecmp_to(b) < 0)
	var sorted := {}
	for item in items:
		sorted[item] = contents[item]
	return sorted


## How many of each category it holds: {"Food": 34, "Materials": 210, ...}
func category_totals() -> Dictionary:
	var totals := {}
	for category in CATEGORIES:
		totals[category] = 0
	for item in contents:
		totals[category_of(item)] += int(contents[item])
	return totals


# ---- Room shrinking ----

## Called after the plots are checked, and when one is removed (with where it stood). Only a
## removed Storehouse's stock can be pushed out: the kinds of item the rest have no room for (the
## last put in first) drop in a bundle where it stood. A Storehouse that merely stops working keeps
## its share (see above). Waits until every storage plot has been checked once (after loading, none
## has yet).
func reconcile(removed_at = null) -> void:
	var now := {}
	for plot in storage_plots():
		if not plot.checked:
			return
		now[plot.plot_id] = slots_of(plot)
	_slots_by_plot = now
	if removed_at == null:
		return
	var room := 0
	for id in now:
		room += int(now[id])
	# What the plots still standing could hold if they all worked (a removed Storehouse's share
	# stays while any other Storehouse could take it in)
	var could_hold := 0
	for plot in storage_plots():
		could_hold += plot.plot_type.town_storage_slots
	room = maxi(room, could_hold)
	if contents.size() <= room:
		return
	var overflow := {}
	while contents.size() > room:
		var item: String = contents.keys()[-1]
		overflow[item] = contents[item]
		contents.erase(item)
	_drop(overflow, removed_at)
	changed.emit()


# Leaves items in a bundle on the ground at a spot (a Storehouse's middle), with a message
func _drop(items: Dictionary, spot: Vector3) -> void:
	var bundle := ItemBundle.create(items)
	plots.world.add_child(bundle)
	spot.y = Plot.ground_at(plots, spot.x, spot.z) + 0.1
	bundle.global_position = spot
	var parts: PackedStringArray = []
	for item in items:
		parts.append("%d %s" % [items[item], String(item).to_lower()])
	notice.emit("Town storage shrank: %s left in a bundle by the Storehouse" % ", ".join(parts))


# ---- Saving (with the Storehouse plots) ----

## The pool shared out among the storage plots for saving: plot id -> its items. Working ones are
## filled first, each up to its own slots; anything left over goes with the first storage plot.
func shares() -> Dictionary:
	var out := {}
	var order := storage_plots()
	order.sort_custom(func(a, b): return int(a.working) > int(b.working))
	if order.is_empty():
		return out
	var items := contents.keys()
	var i := 0
	for plot in order:
		var share := {}
		var room := slots_of(plot)
		while room > 0 and i < items.size():
			share[items[i]] = contents[items[i]]
			i += 1
			room -= 1
		out[plot.plot_id] = share
	while i < items.size():
		out[order[0].plot_id][items[i]] = contents[items[i]]
		i += 1
	return out


## Empties it (before loading)
func clear() -> void:
	contents.clear()
	_slots_by_plot.clear()


## Adds one Storehouse's saved share back into the pool
func load_share(share: Dictionary) -> void:
	for item in share:
		put(str(item), int(share[item]))
