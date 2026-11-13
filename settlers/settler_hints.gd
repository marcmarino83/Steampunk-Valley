class_name SettlerHints
extends RefCounted
## Short hints for the settlement's two easy-to-miss rules, shown on the status line (through
## the settler manager's `notice`) and in the settler panel:
##   - settlers only eat from town storage or a chest that belongs to a plot, never from the
##     player's pockets or the player's own chests outside every plot;
##   - a visitor can only be invited to stay into a free villager House.

const FOOD_PLACE := "Settlers eat from town storage or a plot's chest."
const VISITOR_HOME := "A visitor is at the Village Center. Build a house to invite them to stay."


## True when the settlement has no food left that settlers can eat, but there's food in the
## player's inventory or the player's own chests (outside every plot)
static func food_out_of_reach(manager: SettlerManager) -> bool:
	if manager.economy.food_stored() > 0:
		return false
	var elsewhere := 0
	var player = manager.get_tree().get_first_node_in_group("player")
	if player:
		for food in SettlementEconomy.FOODS:
			elsewhere += int(player.inventory.get(food, 0))
	var settlement := manager.economy.settlement_chests()
	for chest in manager.economy.all_chests():
		if not settlement.has(chest):
			for food in SettlementEconomy.FOODS:
				elsewhere += int(chest.contents.get(food, 0))
	return elsewhere > 0


## True when a visitor has nowhere to be invited into: no villager House with a free bed
static func visitor_needs_home(manager: SettlerManager) -> bool:
	return manager.free_homes().is_empty()
