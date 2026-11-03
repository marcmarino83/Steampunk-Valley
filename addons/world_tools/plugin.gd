@tool
extends EditorPlugin
## Puts the World Tools panel in a tab beside the Inspector (with Inspector and Signals), opens
## it when the plugin loads, and adds Project > Tools > Show World Tools to bring it back.
##
## The panel's contents are loaded only when the plugin starts (not when Godot first reads
## this file), so a problem in them can never stop the plugin itself from being enabled. If
## they can't load, the reason is printed to the Output panel instead.

const PANEL_PATH := "res://addons/world_tools/world_tools_dock.gd"
const MENU_ITEM := "Show World Tools"

var _dock: EditorDock
var _panel: Control


func _enter_tree() -> void:
	var panel_script := load(PANEL_PATH) as Script
	if panel_script == null or not panel_script.can_instantiate():
		push_error("World Tools: couldn't load %s. Check that script for errors in the Script editor." % PANEL_PATH)
		return
	_panel = panel_script.new()
	_panel.set("undo_redo", get_undo_redo())
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_dock = EditorDock.new()
	_dock.name = "WorldTools"
	_dock.title = "World Tools"
	# Remembered across sessions under this name, like Godot's own docks
	_dock.layout_key = "world_tools"
	# The Inspector's group (Inspector, Signals, History), on the right
	_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_UL
	_dock.closable = true
	_dock.add_child(_panel)
	add_dock(_dock)
	add_tool_menu_item(MENU_ITEM, show_panel)
	# Bring it to the front once the editor has finished restoring its saved layout (which
	# happens just after plugins start, and would otherwise switch back to the Inspector)
	get_tree().create_timer(1.0).timeout.connect(show_panel)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_ITEM)
	if _dock:
		remove_dock(_dock)
		_dock.queue_free()
		_dock = null
		_panel = null


## Opens the World Tools tab (even if it was closed) and switches to it
func show_panel() -> void:
	if _dock == null:
		return
	_dock.open()
	_dock.make_visible()
