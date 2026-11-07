class_name ToolItem
extends Resource
## Marks an inventory item as a tool or weapon: something that can go on the action bar and be
## held in your hand. Each one is a resource file in res://tools/, found by itself, so a new
## tool (axe, pickaxe, gun...) needs no action bar code: add a resource and a held model. What
## the tool does is up to whatever checks the player's held_item.

const FOLDER := "res://tools"

## The name it goes by in the inventory, exactly, like "Dowsing Rod"
@export var item_name := ""
## The placeholder model shown in front of the view while it's held
@export var held_scene: PackedScene

# Every tool, by item name. Filled the first time anything asks.
static var _tools := {}


static func find(item: String) -> ToolItem:
	if _tools.is_empty():
		for file in ResourceLoader.list_directory(FOLDER):
			if file.ends_with(".tres"):
				var tool_item := load(FOLDER.path_join(file)) as ToolItem
				if tool_item:
					_tools[tool_item.item_name] = tool_item
	return _tools.get(item)


static func exists_for(item: String) -> bool:
	return find(item) != null
