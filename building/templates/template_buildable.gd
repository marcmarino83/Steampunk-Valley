class_name TemplateBuildable
extends Buildable
## A template as the build menu's Buildings tab shows it: its picture, name and what building it
## all costs. It unlocks with its plot type. Placing it costs nothing: its pieces go down as ghosts
## in a new plot, and each is paid for as it's built (see TemplatePlacer and GhostBuilder).

var template: BuildingTemplate
var plot_type: PlotType


static func of(from: BuildingTemplate) -> TemplateBuildable:
	var buildable := TemplateBuildable.new()
	buildable.template = from
	buildable.plot_type = from.plot_type
	buildable.display_name = from.template_name
	buildable.section = "Buildings"
	buildable.icon = from.thumbnail()
	buildable.icon_color = from.plot_type.icon_color
	# Locked the same way as its plot type (so a locked slot says how to unlock it)
	buildable.starts_locked = from.plot_type.starts_locked
	buildable.unlocked_by = from.plot_type.unlocked_by
	buildable.unlock_item = from.plot_type.unlock_item
	buildable.unlock_also = from.plot_type.unlock_also
	buildable.unlock_hint = from.plot_type.unlock_hint
	return buildable


## Placing it is free (each ghost is paid for as it's built)
func cost_to_pay(_inventory: Dictionary) -> Dictionary:
	return {}


func can_afford(_inventory: Dictionary) -> bool:
	return true


## "Built-in · 32 pieces" then what it all costs
func cost_text() -> String:
	var parts: PackedStringArray = []
	var cost := template.total_cost()
	for item in cost:
		parts.append("%d %s" % [cost[item], item])
	return "%s · %d pieces\n%s" % ["Built-in" if template.built_in else "Yours", template.items.size(), ", ".join(parts)]


func missing_text(_inventory: Dictionary) -> String:
	return ""
