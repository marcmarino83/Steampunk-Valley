class_name PathTool
extends Buildable
## A tool in the build menu's Paths tab that paints onto the ground instead of placing anything
## (see PathPainter). Free to use: it costs nothing and needs no materials.

## The path's width while painting starts, in meters (the wheel changes it)
@export_range(1.0, 3.0, 0.25) var start_width := 1.5
## What it says in the build menu when hovered
@export_multiline var menu_hint := ""


func cost_to_pay(_inventory: Dictionary) -> Dictionary:
	return {}


func can_afford(_inventory: Dictionary) -> bool:
	return true


func cost_text() -> String:
	return "Free"


func missing_text(_inventory: Dictionary) -> String:
	return ""
