class_name IronTier
## The switch for everything saved up for the iron tier: the dowsing rod (item, recipe, model,
## pulse) and the buried iron and coal seams with their markers and dig spots. All of it lives
## in this folder. Set ENABLED to true and it all comes back.

const ENABLED := false


## The folders to look in for a kind of data file: the game's own folder, plus this tier's
## matching folder when the tier is switched on
static func folders(main_folder: String, tier_folder: String) -> PackedStringArray:
	var found: PackedStringArray = [main_folder]
	if ENABLED:
		found.append(tier_folder)
	return found
