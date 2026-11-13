class_name VillageLedger
extends RefCounted
## The village ledger behind the Village screen's Resources tab: one entry per resource the village
## makes, uses or stores, from tomorrow's plan (SettlementEconomy.plan_day: what dawn makes from the
## current workers and slider settings, what dusk's meals eat) and what's stored now.
##
## Each entry (item name -> Dictionary):
##   category  "Food", "Building materials", "Crafting materials" or "Tools" (see category_of)
##   made      planned per day, every building together
##   used      planned per day by the villagers (food eaten); the player's own takings never count
##   stored    in the settlement's stores now: town storage (the Storehouses) plus the plots' own
##             storage chests (a hut's chest, where output goes when town storage is full). The
##             player's chests outside every plot don't count.
##   town, chests  that amount split by where it is
##   short     true when the village runs down on it: used > made, or (food) the plan leaves meals
##             missing and this food is all eaten
##   days_left with used > made, how many whole days the stock lasts (-1 otherwise)
##   sources   [{plot, workers: Array of Settler, share: percent (-1 for a fixed amount), amount}]
##   uses      [{text, amount}] ("Eaten by 3 villagers")

const CATEGORIES := ["Food", "Building materials", "Crafting materials", "Tools"]
## Where building pieces' costs are read from (what's in them is a building material)
const PIECE_FOLDERS := ["res://buildables/structure", "res://buildables/round"]

static var _building_materials := {}


## The ledger as of now: {"items": item -> entry (see above), "short": meals' worth missing tomorrow}
static func entries(manager: SettlerManager) -> Dictionary:
	var out := {}
	if manager == null or manager.economy == null or manager.plots == null:
		return {"items": out, "short": 0}
	var plan := manager.economy.plan_day()
	var town := manager.plots.town
	for item in town.contents:
		_entry(out, item)["town"] += int(town.contents[item])
	for chest in manager.economy.settlement_chests():
		for item in chest.contents:
			_entry(out, item)["chests"] += int(chest.contents[item])
	var made_by: Dictionary = plan["made"]
	for plot in made_by:
		var crew: Array = manager.workers(plot).filter(func(s): return not s.leaving)
		var split: bool = plot.plot_type.split_output_total > 0
		for item in made_by[plot]:
			var amount := int(made_by[plot][item])
			var e := _entry(out, item)
			e["made"] += amount
			e["sources"].append({"plot": plot, "workers": crew, "amount": amount,
				"share": int(plot.shares().get(item, -1)) if split and plot.plot_type.split_output.has(item) else -1})
	# Buildings that could make it but don't right now (no worker, not working) still show, at 0,
	# so their sliders can be set from the ledger too
	for plot in manager.plots.all_plots():
		if not SettlerManager.is_workplace(plot) or made_by.has(plot):
			continue
		var crew: Array = manager.workers(plot).filter(func(s): return not s.leaving)
		var could: Dictionary = plot.daily_output()
		for item in could:
			if int(could[item]) <= 0:
				continue
			var e := _entry(out, item)
			e["sources"].append({"plot": plot, "workers": crew, "amount": 0,
				"share": int(plot.shares().get(item, -1)) if plot.plot_type.split_output_total > 0 and plot.plot_type.split_output.has(item) else -1})
	var eaten: Dictionary = plan["eaten"]
	for food in eaten:
		var e := _entry(out, food)
		e["used"] += int(eaten[food])
		var n := int(plan["eaters"].get(food, 0))
		e["uses"].append({"text": "Eaten by %d %s" % [n, "villager" if n == 1 else "villagers"], "amount": int(eaten[food])})
	# Every food settlers eat has a row, even with none made, used or stored
	for food in SettlementEconomy.FOODS:
		_entry(out, food)
	var short_meals := int(plan["short"])
	for item in out:
		var e: Dictionary = out[item]
		e["stored"] = e["town"] + e["chests"]
		var drain: int = e["used"] - e["made"]
		if drain > 0:
			e["short"] = true
			e["days_left"] = floori(e["stored"] / float(drain))
		elif short_meals > 0 and e["category"] == "Food" and SettlementEconomy.FOODS.has(item) and e["used"] >= e["stored"] + e["made"]:
			# Everyone's meals aren't covered and this food is all eaten
			e["short"] = true
	return {"items": out, "short": short_meals}


## Food (what settlers eat), Building materials (in a building piece's cost), Tools, or Crafting
## materials (the rest)
static func category_of(item: String) -> String:
	if SettlementEconomy.FOODS.has(item):
		return "Food"
	if building_materials().has(item):
		return "Building materials"
	if ToolItem.exists_for(item):
		return "Tools"
	return "Crafting materials"


## Every item a building piece costs (read once from the piece folders)
static func building_materials() -> Dictionary:
	if _building_materials.is_empty():
		for folder in PIECE_FOLDERS:
			_read_costs(folder)
	return _building_materials


static func _read_costs(folder: String) -> void:
	for entry in ResourceLoader.list_directory(folder):
		if entry.ends_with("/"):
			_read_costs(folder.path_join(entry.trim_suffix("/")))
		elif entry.ends_with(".tres"):
			var b := load(folder.path_join(entry)) as Buildable
			if b:
				for cost in b.costs:
					for item in cost:
						_building_materials[str(item)] = true


static func _entry(out: Dictionary, item: String) -> Dictionary:
	if not out.has(item):
		out[item] = {"item": item, "category": category_of(item), "made": 0, "used": 0, "stored": 0,
			"town": 0, "chests": 0, "short": false, "days_left": -1, "sources": [], "uses": []}
	return out[item]
