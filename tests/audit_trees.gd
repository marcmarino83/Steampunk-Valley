extends RefCounted
## The new-game audit's tree and wood checks (see new_game_audit.gd, which makes one and calls
## these at their steps, so its output and checks come in the same order as before):
##   - report_trees: the trees near the start and the wood by hand each gives;
##   - fell_a_tree: a real medium tree felled, cut into sections, its stump cleared, its saved
##     state loaded back, and its regrowth;
##   - wood_to_village_center: the wood the way to the Village Center takes, in trees by hand.
## It reports and checks through the audit's own say() and check().

## The audit it's part of (its player, start, helpers, say and check)
var audit: Node
## The average wood by hand from a tree within 60 m of the start (see report_trees)
var wood_per_tree := 0.0


## The trees, how many are within 60 m of the start, and the wood each of those gives by hand
func report_trees() -> void:
	var start: Vector3 = audit.start
	var trees: Array = audit._scripted("world/tree.gd")
	var close := trees.filter(func(t):
		return start.distance_to((t as Node3D).global_position) < 60.0)
	var by_wood := {}
	for t in close:
		by_wood[t.total_wood()] = int(by_wood.get(t.total_wood(), 0)) + 1
		wood_per_tree += float(t.total_wood()) / maxf(close.size(), 1)
	audit.say(("trees: %d with the tree script, %d within 60 m; wood by hand per tree there "
			+ "{wood: trees} %s, %.1f on average") % [trees.size(), close.size(), by_wood,
			wood_per_tree])


# A real medium tree near the start felled with the axe: it lies as sections, each cut for its
# wood, then the stump; its saved state follows each cut, loads back, and it regrows as before
func fell_a_tree() -> void:
	var player: Node = audit.player
	var start: Vector3 = audit.start
	var tree: Node3D = null
	var best := INF
	for t in audit._scripted("world/tree.gd"):
		var d := start.distance_to((t as Node3D).global_position)
		if t.tree_height >= 8.0 and t.tree_height < 15.0 and t.gathers_left > 0 and d < best:
			tree = t
			best = d
	if tree == null:
		audit.check(false, "there's a medium tree to fell")
		return
	var valley = audit.get_tree().get_first_node_in_group("valley")
	var id: String = valley.id_of(tree)
	player._on_held_changed("Axe")
	var wood := func() -> int: return int(player.inventory.get("Wood", 0))
	var start_wood: int = wood.call()
	var hits := 0
	while tree.gathers_left > 0 and hits < 20:
		player.stamina = player.max_stamina()
		tree.interact(player)
		hits += 1
	# (the fall takes about 2 s of real time)
	var waited := Time.get_ticks_msec()
	while tree.get_node_or_null("FallenTrunk") == null and Time.get_ticks_msec() - waited < 8000:
		await audit.get_tree().process_frame
	var sections := func() -> Array:
		var found := []
		var trunk := tree.get_node_or_null("FallenTrunk")
		if trunk:
			for s in trunk.get_children():
				# (a cut section shrinks away for a moment before it's gone)
				if s is TrunkSection and s.gathers_left > 0:
					found.append(s)
		return found
	var state := func() -> String: return str(valley._changes.get(id, ""))
	audit.say(("trees: a %.0f m tree %.0f m away felled in %d hits: wood %d, sections %d, "
			+ "stump swings %d, saved '%s'") % [tree.tree_height, best, hits,
			wood.call() - start_wood, sections.call().size(), tree.gathers_left, state.call()])
	audit.check(sections.call().size() == 4 and tree.gathers_left == tree.STUMP_HITS
			and wood.call() == start_wood,
			"a felled medium tree lies as 4 trunk sections with its stump (no wood yet)")
	audit.check(state.call().begins_with("felled:15:%d:" % tree.STUMP_HITS),
			"a felled tree's trunk and stump are saved")
	# One section cut: its wood, it's gone, and the save follows; then that state loads back
	var first: TrunkSection = sections.call()[0]
	var before: int = wood.call()
	for k in TrunkSection.HITS:
		player.stamina = player.max_stamina()
		first.interact(player)
	await audit.frames(1)
	audit.say("trees: one section cut in %d hits: wood +%d, sections left %d, saved '%s'"
			% [TrunkSection.HITS, wood.call() - before, sections.call().size(), state.call()])
	audit.check(wood.call() - before == 4 and sections.call().size() == 3
			and state.call().begins_with("felled:14:"),
			"a section takes %d hits, gives its wood straight to the inventory and is gone"
			% TrunkSection.HITS)
	Forest.restore(tree, state.call())
	await audit.frames(1)
	audit.check(sections.call().size() == 3 and tree.gathers_left == tree.STUMP_HITS,
			"a part-cut tree loads back as it was saved")
	for s in sections.call():
		for k in TrunkSection.HITS:
			player.stamina = player.max_stamina()
			s.interact(player)
	for k in tree.STUMP_HITS:
		player.stamina = player.max_stamina()
		tree.interact(player)
	await audit.frames(1)
	var total: int = wood.call() - start_wood
	audit.say(("trees: everything cut and the stump cleared: %d wood from the tree (it says %d), "
			+ "saved '%s', stump left: %s") % [total, tree.total_wood(), state.call(),
			tree.can_interact()])
	audit.check(total == tree.total_wood() and total >= 16 and total <= 20
			and not tree.can_interact() and state.call().begins_with("felled:0:0:"),
			"a medium tree gives 16 to 20 wood by its sections and stump, and the stump clears")
	# Regrowth on the same bookings as before
	valley._on_respawn_due("sapling", id)
	audit.check(state.call() == "sapling" and tree.top.visible,
			"a felled tree still grows a sapling")
	valley._on_respawn_due("tree", id)
	audit.check(not valley._changes.has(id) and tree.can_interact(),
			"and then a full tree that can be felled again")
	player._on_held_changed("")
	player.remove_item("Wood", total)


# How much wood (planks are half a wood) the way to the Village Center takes, and so how many
# trees by hand at the average near the start: with the Basic House, and with the Starter House
func wood_to_village_center() -> void:
	var wood_of := func(cost: Dictionary) -> float:
		return float(cost.get("Wood", 0)) + float(cost.get("Planks", 0)) / 2.0
	var extras := 0.0
	for name in ["Lean-to", "Workbench"]:
		var b: Buildable = audit._buildable(name)
		extras += wood_of.call(b.costs[0]) if b and not b.costs.is_empty() else 0.0
	var chest: Recipe = audit._recipe("Storage Chest")
	extras += wood_of.call(chest.costs) if chest else 0.0
	var mast := load("res://buildables/furniture/bell_mast.tres") as Buildable
	extras += wood_of.call(mast.costs[0]) if mast and not mast.costs.is_empty() else 0.0
	for house in ["basic_house", "starter_house"]:
		var total := extras
		var parts: PackedStringArray = []
		for t in [house, "forager_s_hut", "storehouse"]:
			var template := BuildingTemplate.read("res://buildables/templates/%s.json" % t)
			var w: float = wood_of.call(template.total_cost())
			parts.append("%s %.0f" % [t, w])
			total += w
		var trees := ceili(total / maxf(wood_per_tree, 0.1))
		audit.say(("wood to the Village Center with the %s: %.0f wood (%s, lean-to, workbench, "
				+ "chest and bell mast %.0f) = %d trees by hand at %.1f wood a tree (it was %d "
				+ "trees at 3 wood a tree)") % [house, total, ", ".join(parts), extras, trees,
				wood_per_tree, ceili(total / 3.0)])
	var starter := BuildingTemplate.read("res://buildables/templates/starter_house.json")
	audit.say("the Starter House costs %s (%.0f wood)" % [starter.total_cost(),
			wood_of.call(starter.total_cost())])
