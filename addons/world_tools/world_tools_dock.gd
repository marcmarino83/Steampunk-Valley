@tool
extends VBoxContainer
## The World Tools panel: buttons that add terrain modifiers, trails and clear zones where
## the ground is next clicked; a list of everything placed, to select, jump to or delete; and the
## valley's editor views. Everything it adds goes under TerrainEdits in the world scene.

# The scenes the buttons add. They're loaded when a button is pressed, not when this script
# is read, so a moved or broken scene shows up as a message in the panel instead of stopping
# the whole plugin from loading.
const MODIFIER_SCENE := "res://world/terrain_modifier.tscn"
const PATH_SCENE := "res://world/terrain_path.tscn"
const ZONE_SCENE := "res://building/clear_zone.tscn"
## The terrain modifier's modes, by the number its Mode setting saves
const MODES := {1: "Raise/Lower", 2: "Flatten", 3: "Smooth", 4: "Squash"}
const FLATTEN := 2

## Where each kind lives in the world scene, under TerrainEdits. Modifiers come before paths,
## so a flattened area is in place before a trail runs into it. (Objects, with the Object
## Painter's trees, rocks and bushes, is made the first time something is placed.)
const GROUPS := ["Modifiers", "Paths", "ClearZones"]
const MODIFIER_HANDLES := "res://addons/world_tools/modifier_handles.gd"
const OBJECT_PAINTER := "res://addons/world_tools/object_painter.gd"
const TEXTURE_BRUSH := "res://addons/world_tools/texture_brush.gd"
const SCULPT_BRUSH := "res://addons/world_tools/sculpt_brush.gd"
const OBJECTS := "objects"
const TEXTURE := "texture"
const SCULPT := "sculpt"

var undo_redo: EditorUndoRedoManager:
	set(value):
		undo_redo = value
		if _painter:
			_painter.undo_redo = value
		if _brush:
			_brush.undo_redo = value
		if _sculpt:
			_sculpt.undo_redo = value
		if _handles:
			_handles.undo_redo = value
## Set by the plugin: redraws the 3D view's overlay (the brush circle)
var redraw_overlay := func(): pass

# The painting tools, and which one is switched on ("" = neither)
var _painter: RefCounted
var _brush: RefCounted
var _sculpt: RefCounted
# Dragging a selected terrain modifier's middle, height and radius
var _handles: RefCounted
# Something waiting to be placed where the ground is next clicked: [node, group, undo name]
var _placing: Array = []
var _placing_cursor = null
var _eat_release := false
var _active_tool := ""
var _object_toggle: Button
var _texture_toggle: Button
var _sculpt_toggle: Button
var _sculpt_panel: Control
var _object_panel: Control
var _texture_panel: Control
var _categories: TabBar
var _palette_list: ItemList
var _material_list: ItemList
# The Texture Brush's material pictures, by color or image path
var _thumbnails := {}
const THUMBNAIL := 48

var _list: Tree
var _slope_view: CheckBox
var _markers: CheckBox
var _status: Label
var _buttons: Array[Button] = []
var _list_dirty := true
var _refresh_wait := 0.0


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	_painter = load(OBJECT_PAINTER).new()
	_painter.redraw = func(): redraw_overlay.call()
	_brush = load(TEXTURE_BRUSH).new()
	_brush.redraw = func(): redraw_overlay.call()
	_sculpt = load(SCULPT_BRUSH).new()
	_sculpt.redraw = func(): redraw_overlay.call()
	_handles = load(MODIFIER_HANDLES).new()
	_handles.redraw = func(): redraw_overlay.call()

	_add_heading("Add")
	var grid := GridContainer.new()
	grid.columns = 2
	add_child(grid)
	for mode in MODES:
		var label: String = MODES[mode]
		_add_button(grid, label, "Add a %s terrain modifier where you next click the ground" % label, _add_modifier.bind(mode))
	_add_button(grid, "Path", "Add a trail where you next click the ground", _add_path)
	_add_button(grid, "Clear Zone", "Add a circle that keeps trees, resources and boulders out, where you next click the ground", _add_zone)

	_add_heading("Paint")
	var tools := GridContainer.new()
	tools.columns = 2
	add_child(tools)
	_object_toggle = _add_button(tools, "Object Painter", "Place and paint trees, rocks and bushes in the 3D view", _toggle_tool.bind(OBJECTS))
	_object_toggle.toggle_mode = true
	_texture_toggle = _add_button(tools, "Texture Brush", "Paint grass, dirt, forest floor, gravel or rock onto the ground", _toggle_tool.bind(TEXTURE))
	_texture_toggle.toggle_mode = true
	_sculpt_toggle = _add_button(tools, "Sculpt Brush", "Raise, lower, smooth and flatten the ground, or make ramps, by painting in the 3D view", _toggle_tool.bind(SCULPT))
	_sculpt_toggle.toggle_mode = true
	_object_panel = _build_object_panel()
	add_child(_object_panel)
	_texture_panel = _build_texture_panel()
	add_child(_texture_panel)
	_sculpt_panel = _build_sculpt_panel()
	add_child(_sculpt_panel)

	_add_heading("View")
	_slope_view = CheckBox.new()
	_slope_view.text = "Show Slope View"
	_slope_view.tooltip_text = "Tint the ground green (walkable), yellow (near the limit) or red (too steep)"
	_slope_view.toggled.connect(func(on): _set_valley("show_slope_view", on))
	add_child(_slope_view)
	_markers = CheckBox.new()
	_markers.text = "Show Modifier Markers"
	_markers.tooltip_text = "Show the markers, trail lines and clear zone edges in the 3D view"
	_markers.toggled.connect(func(on): _set_valley("show_modifier_markers", on))
	add_child(_markers)
	var rebuild := Button.new()
	rebuild.text = "Rebuild Terrain"
	rebuild.tooltip_text = "Rebuild the whole valley: ground, trees, resources and all"
	rebuild.pressed.connect(func():
		var valley = _valley()
		if valley:
			valley.generate())
	add_child(rebuild)

	_add_heading("In the world")
	_list = Tree.new()
	_list.hide_root = true
	_list.columns = 1
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(0, 200)
	_list.item_selected.connect(_on_item_selected)
	_list.button_clicked.connect(_on_item_button)
	add_child(_list)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color(1, 0.8, 0.45))
	add_child(_status)


func _ready() -> void:
	get_tree().node_added.connect(func(_n): _list_dirty = true)
	get_tree().node_removed.connect(func(_n): _list_dirty = true)
	EditorInterface.get_selection().selection_changed.connect(func(): _list_dirty = true)
	# New scenes dropped into assets/ show up in the palette by themselves
	# ...and so do new texture sets in assets/textures, in the Texture Brush's picker (the
	# ground picks them up at its next rebuild)
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(func():
		if _active_tool == OBJECTS:
			_painter.scan_palette()
			_fill_palette()
		elif _active_tool == TEXTURE:
			_fill_materials())


func _process(delta: float) -> void:
	_handles.poll(_valley())
	_sculpt.poll(_valley())
	_refresh_wait -= delta
	if _refresh_wait > 0.0:
		return
	_refresh_wait = 0.5
	var valley = _valley()
	for b in _buttons:
		b.disabled = valley == null
	if valley == null:
		_status.text = "Open the world scene (world.tscn) to use these tools."
		_list.clear()
		if _active_tool != "":
			_toggle_tool(_active_tool)
		return
	if _status.text.begins_with("Open the world scene"):
		_status.text = ""
	# Mirror the valley's own settings, in case they were changed in the Inspector
	_slope_view.set_pressed_no_signal(valley.show_slope_view)
	_markers.set_pressed_no_signal(valley.show_modifier_markers)
	_organize_loose_nodes()
	if _list_dirty:
		_list_dirty = false
		_rebuild_list()


# ---- Adding things ----

func _add_modifier(mode: int) -> void:
	var node := _make(MODIFIER_SCENE)
	if node == null:
		return
	node.mode = mode
	var label: String = MODES[mode]
	node.name = label.replace("/", "")
	if mode == FLATTEN:
		node.falloff = 0.7
	_begin_placing(node, "Modifiers", "Add %s modifier" % label)


func _add_path() -> void:
	var node := _make(PATH_SCENE)
	if node:
		node.name = "Path"
		_begin_placing(node, "Paths", "Add trail")


func _add_zone() -> void:
	var node := _make(ZONE_SCENE)
	if node:
		node.name = "ClearZone"
		_begin_placing(node, "ClearZones", "Add clear zone")


# Loads a scene and makes one, or says in the panel why it couldn't
func _make(path: String) -> Node3D:
	var scene := load(path) as PackedScene
	if scene == null:
		_status.text = "Couldn't load %s. Was it moved or renamed?" % path
		push_error("World Tools: couldn't load " + path)
		return null
	return scene.instantiate() as Node3D


# Waits for a click on the ground to say where a new node goes
func _begin_placing(node: Node3D, group: String, action: String) -> void:
	_cancel_placing()
	var tool := _tool()
	if tool and _valley():
		tool.finish_stroke(_valley())
	if _active_tool != "":
		_toggle_tool(_active_tool)
	_placing = [node, group, action]
	_status.text = "%s: click the ground to place it (Esc to cancel)" % action
	EditorInterface.set_main_screen_editor("3D")
	redraw_overlay.call()


func _cancel_placing() -> void:
	if _placing.is_empty():
		return
	_placing[0].free()
	_placing = []
	_placing_cursor = null
	_status.text = ""
	redraw_overlay.call()


# Esc cancels placing wherever the keyboard focus happens to be
func _input(event: InputEvent) -> void:
	if not _placing.is_empty() and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_placing()
		get_viewport().set_input_as_handled()


func _placing_input(camera: Camera3D, event: InputEvent) -> bool:
	var valley = _valley()
	if valley == null or not valley.has_heights():
		return false
	if event is InputEventMouse:
		_placing_cursor = valley.ground_under_ray(camera.project_ray_origin(event.position), camera.project_ray_normal(event.position))
	if event is InputEventMouseMotion:
		redraw_overlay.call()
		return false
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_placing()
		return true
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_placing()
			return true
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _placing_cursor != null:
				var waiting := _placing
				_placing = []
				_status.text = ""
				_eat_release = true
				# A modifier starts level with the ground it acts on, so a Raise/Lower has no effect
				# until it's moved
				if waiting[0].has_method("uses_height"):
					_placing_cursor.y = valley.modifier_ground_at(_placing_cursor.x, _placing_cursor.z)
				_place(waiting[0], waiting[1], waiting[2], _placing_cursor)
				_placing_cursor = null
				redraw_overlay.call()
			return true
	return false


# Adds a node under its TerrainEdits group, on the ground at a spot, and selects it. One
# Ctrl+Z takes it away again.
func _place(node: Node3D, group: String, action: String, spot: Vector3) -> void:
	var root := EditorInterface.get_edited_scene_root()
	var parent := _group_node(group)
	if root == null or parent == null:
		node.free()
		return
	node.position = parent.global_transform.affine_inverse() * spot
	undo_redo.create_action(action)
	undo_redo.add_do_method(parent, "add_child", node, true)
	undo_redo.add_do_method(node, "set_owner", root)
	undo_redo.add_do_reference(node)
	undo_redo.add_undo_method(parent, "remove_child", node)
	undo_redo.commit_action()
	_select(node, false)


# ---- Keeping things tidy ----

# Finds (or makes) TerrainEdits/<group> in the world scene
func _group_node(group: String) -> Node3D:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return null
	var edits := root.get_node_or_null("TerrainEdits") as Node3D
	if edits == null:
		edits = Node3D.new()
		edits.name = "TerrainEdits"
		root.add_child(edits, true)
		edits.owner = root
		for g in GROUPS:
			var holder := Node3D.new()
			holder.name = g
			edits.add_child(holder, true)
			holder.owner = root
		EditorInterface.mark_scene_as_unsaved()
	var holder := edits.get_node_or_null(group) as Node3D
	if holder == null:
		holder = Node3D.new()
		holder.name = group
		edits.add_child(holder, true)
		holder.owner = root
		# Keep the groups in their proper order
		edits.move_child(holder, mini(GROUPS.find(group), edits.get_child_count() - 1))
		EditorInterface.mark_scene_as_unsaved()
	return holder


# Moves any modifiers, paths or clear zones sitting loose in the world scene into their
# groups, keeping exactly where they are (and their order, so their effect doesn't change).
# Ones that belong to something else, like the crash site's own flatten, are left alone.
func _organize_loose_nodes() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return
	var loose: Array = []
	for child in root.get_children():
		var group := _group_for(child)
		if group != "":
			loose.append([child, group])
	if loose.is_empty():
		return
	undo_redo.create_action("Organize terrain edits")
	for entry in loose:
		var node: Node3D = entry[0]
		var holder := _group_node(entry[1])
		undo_redo.add_do_method(node, "reparent", holder, true)
		undo_redo.add_do_method(node, "set_owner", root)
		undo_redo.add_undo_method(node, "reparent", root, true)
		undo_redo.add_undo_method(root, "move_child", node, node.get_index())
		undo_redo.add_undo_method(node, "set_owner", root)
	undo_redo.commit_action()
	_list_dirty = true


func _group_for(node: Node) -> String:
	if node.is_in_group("clear_zones"):
		return "ClearZones"
	if node.is_in_group("terrain_modifiers"):
		return "Paths" if node.has_method("trail_points") else "Modifiers"
	return ""


# ---- The list ----

func _rebuild_list() -> void:
	_list.clear()
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return
	var top := _list.create_item()
	var sections := {"Modifiers": [], "Paths": [], "Clear Zones": []}
	for node in root.find_children("*", "Node3D", true, false):
		if node.is_in_group("clear_zones"):
			sections["Clear Zones"].append(node)
		elif node.is_in_group("terrain_modifiers"):
			sections["Paths" if node.has_method("trail_points") else "Modifiers"].append(node)
	var selected := EditorInterface.get_selection().get_selected_nodes()
	var delete_icon := EditorInterface.get_editor_theme().get_icon("Remove", "EditorIcons")
	for title in sections:
		var heading := _list.create_item(top)
		heading.set_text(0, "%s (%d)" % [title, sections[title].size()])
		heading.set_selectable(0, false)
		heading.set_custom_color(0, Color(1, 0.8, 0.45))
		for node in sections[title]:
			var item := _list.create_item(heading)
			item.set_text(0, _describe(node))
			item.set_tooltip_text(0, str(root.get_path_to(node)))
			item.set_metadata(0, node)
			item.add_button(0, delete_icon, 0, false, "Delete")
			if node in selected:
				# Only showing what's already selected. Without blocking its signal this counts as
				# clicking the row, which re-selects the node in the editor: in the middle of a
				# gizmo drag that throws away where the drag started, and the node jumps to the
				# world's origin.
				_list.set_block_signals(true)
				item.select(0)
				_list.set_block_signals(false)


func _describe(node: Node) -> String:
	if node.is_in_group("clear_zones"):
		return "%s   r %.0f m" % [node.name, node.radius]
	if node.has_method("trail_points"):
		return "%s   %d points" % [node.name, node.curve.point_count if node.curve else 0]
	var mode: String = MODES.get(node.mode, "?")
	return "%s   %s, r %.0f m" % [node.name, mode, node.radius]


func _on_item_selected() -> void:
	var item := _list.get_selected()
	if item and item.get_metadata(0) is Node3D:
		_select(item.get_metadata(0), true)


func _on_item_button(item: TreeItem, _column: int, _id: int, _mouse: int) -> void:
	var node = item.get_metadata(0)
	if not (node is Node3D) or not is_instance_valid(node):
		return
	var parent: Node = node.get_parent()
	var root := EditorInterface.get_edited_scene_root()
	undo_redo.create_action("Delete %s" % node.name)
	undo_redo.add_do_method(parent, "remove_child", node)
	undo_redo.add_undo_method(parent, "add_child", node, true)
	undo_redo.add_undo_method(parent, "move_child", node, node.get_index())
	undo_redo.add_undo_method(node, "set_owner", root)
	undo_redo.add_undo_reference(node)
	undo_redo.commit_action()
	_list_dirty = true


# Selects a node in the editor, and (if asked) swings the 3D view round to it, the same as
# pressing F (Focus Selection) in the 3D view
func _select(node: Node3D, focus: bool) -> void:
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(node)
	EditorInterface.edit_node(node)
	if focus:
		EditorInterface.set_main_screen_editor("3D")
		_focus_view.call_deferred()


func _focus_view() -> void:
	# The 3D view focuses the selection when it gets the F key, so give it one
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var surface := viewport.get_parent() as Control
	if surface:
		surface.grab_focus()
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_F
		key.physical_keycode = KEY_F
		key.pressed = pressed
		Input.parse_input_event(key)


# ---- Painting: the Object Painter and the Texture Brush ----

## Called by the plugin for every input event in the 3D view. True means a tool used it.
func forward_input(camera: Camera3D, event: InputEvent) -> bool:
	if not _placing.is_empty():
		return _placing_input(camera, event)
	if _eat_release and event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_eat_release = false
		return true
	var tool := _tool()
	if tool == null:
		return _handles.handle_input(camera, event, _valley())
	var used: bool = tool.handle_input(camera, event, _valley())
	if used and tool.status != "":
		_status.text = tool.status
	return used


## Called by the plugin to draw over the 3D view: the brush circle and the controls hint
func draw_overlay(overlay: Control) -> void:
	var tool := _tool()
	var camera := EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	if camera == null:
		return
	if not _placing.is_empty():
		var painter = load(OBJECT_PAINTER)
		if _placing_cursor != null and _valley():
			painter._ring(overlay, camera, _valley(), _placing_cursor, float(_placing[0].get("radius")) if _placing[0].get("radius") != null else 2.0, Color(0.55, 0.95, 0.55), 2.0)
		painter._hint(overlay, ["%s" % _placing[2], "Click the ground: place it here", "Esc or right-click: cancel"])
	elif tool:
		tool.draw(overlay, camera, _valley())
	else:
		_handles.draw(overlay, camera, _valley())


## Called by the plugin when a terrain modifier is selected (null when none is)
func edit_modifier(node: Node3D) -> void:
	_handles.set_target(node)
	redraw_overlay.call()


func _tool() -> RefCounted:
	match _active_tool:
		OBJECTS:
			return _painter
		TEXTURE:
			return _brush
		SCULPT:
			return _sculpt
	return null


# Switches a painting tool on (and the other off), or off again if it was already on
func _toggle_tool(which: String) -> void:
	_cancel_placing()
	var valley = _valley()
	var tool := _tool()
	if tool and valley:
		tool.finish_stroke(valley)
	_active_tool = "" if _active_tool == which else which
	if _active_tool == OBJECTS and _painter:
		_painter.scan_palette()
		_fill_palette()
	if _active_tool == TEXTURE:
		_fill_materials()
	_object_toggle.set_pressed_no_signal(_active_tool == OBJECTS)
	_texture_toggle.set_pressed_no_signal(_active_tool == TEXTURE)
	_sculpt_toggle.set_pressed_no_signal(_active_tool == SCULPT)
	_sculpt_panel.visible = _active_tool == SCULPT
	_object_panel.visible = _active_tool == OBJECTS
	_texture_panel.visible = _active_tool == TEXTURE
	if _active_tool != "":
		EditorInterface.set_main_screen_editor("3D")
	redraw_overlay.call()


func _build_object_panel() -> Control:
	var box := VBoxContainer.new()
	box.visible = false
	_categories = TabBar.new()
	_categories.clip_tabs = false
	for c in _painter.CATEGORIES:
		_categories.add_tab(c)
	_categories.tab_changed.connect(func(tab):
		_painter.category = _categories.get_tab_title(tab)
		_painter.selected.clear()
		_fill_palette())
	box.add_child(_categories)
	_palette_list = ItemList.new()
	_palette_list.select_mode = ItemList.SELECT_MULTI
	_palette_list.icon_mode = ItemList.ICON_MODE_TOP
	_palette_list.fixed_icon_size = Vector2i(64, 64)
	_palette_list.max_columns = 0
	_palette_list.same_column_width = true
	_palette_list.custom_minimum_size = Vector2(0, 190)
	_palette_list.tooltip_text = "Pick one, or Ctrl+click several to paint a mix"
	_palette_list.multi_selected.connect(func(_i, _on): _read_palette_picks())
	_palette_list.item_selected.connect(func(_i): _read_palette_picks())
	box.add_child(_palette_list)
	box.add_child(_slider_row("Brush Radius (m)", 0.5, 40.0, 0.5, _painter.radius, func(v): _painter.radius = v))
	box.add_child(_slider_row("Density (per 100 m²)", 0.1, 30.0, 0.1, _painter.density, func(v): _painter.density = v))
	var rescan := Button.new()
	rescan.text = "Rescan assets/"
	rescan.tooltip_text = "Look for new scenes in assets/trees, assets/rocks, assets/bushes and assets/landmarks"
	rescan.pressed.connect(func():
		_painter.scan_palette()
		_fill_palette())
	box.add_child(rescan)
	box.add_child(_help("Click: place one. Drag: paint many. Alt: erase (scattered ones too). Drag a placed object to move it; hold Shift for fine moves."))
	return box


func _build_sculpt_panel() -> Control:
	var box := VBoxContainer.new()
	box.visible = false
	var modes := GridContainer.new()
	modes.columns = 3
	var group := ButtonGroup.new()
	for mode in _sculpt.MODES:
		var button := Button.new()
		button.text = mode
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = mode == _sculpt.mode
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func():
			_sculpt.mode = mode
			redraw_overlay.call())
		modes.add_child(button)
	box.add_child(modes)
	box.add_child(_slider_row("Brush Radius (m)", 2.0, 80.0, 0.5, _sculpt.radius, func(v): _sculpt.radius = v))
	box.add_child(_slider_row("Strength", 0.02, 1.0, 0.01, _sculpt.strength, func(v): _sculpt.strength = v))
	box.add_child(_slider_row("Falloff", 0.0, 1.0, 0.01, _sculpt.falloff, func(v): _sculpt.falloff = v))
	box.add_child(_help("Hold and paint. Flatten: Ctrl + click samples the height to pull toward. Ramp: press at one end, drag to the other, let go. Alt rubs sculpting out. Saved after every stroke; Ctrl+Z undoes a stroke."))
	return box


func _build_texture_panel() -> Control:
	var box := VBoxContainer.new()
	box.visible = false
	# A grid of small pictures that wraps onto as many rows as it needs and grows to fit them
	# all, so every material shows without scrolling
	_material_list = ItemList.new()
	_material_list.icon_mode = ItemList.ICON_MODE_TOP
	_material_list.fixed_icon_size = Vector2i(THUMBNAIL, THUMBNAIL)
	_material_list.max_columns = 0
	_material_list.same_column_width = true
	_material_list.fixed_column_width = THUMBNAIL + 34
	_material_list.max_text_lines = 2
	_material_list.auto_height = true
	_material_list.item_selected.connect(func(i):
		_brush.material = _material_list.get_item_metadata(i)
		_brush.material_name = _material_list.get_item_text(i)
		redraw_overlay.call())
	box.add_child(_material_list)
	box.add_child(_slider_row("Brush Radius (m)", 0.5, 40.0, 0.5, _brush.radius, func(v): _brush.radius = v))
	box.add_child(_slider_row("Strength", 0.02, 1.0, 0.01, _brush.strength, func(v): _brush.strength = v))
	box.add_child(_slider_row("Falloff", 0.0, 1.0, 0.01, _brush.falloff, func(v): _brush.falloff = v))
	box.add_child(_help("Click or drag to paint. Alt erases back to the automatic coloring. Saved after every stroke."))
	return box


# Lists every material the Texture Brush can paint: grass, dirt, and each texture set found in
# assets/textures (so a new folder there shows up here by itself), each with a small
# picture of its Color image
func _fill_materials() -> void:
	var valley = _valley()
	if valley == null or not valley.has_method("paint_materials"):
		return
	var picked: String = _brush.material
	_material_list.clear()
	for entry in valley.paint_materials():
		var index := _material_list.add_item(entry["name"], _thumbnail(entry["color"]))
		_material_list.set_item_metadata(index, entry["id"])
		_material_list.set_item_tooltip(index, entry["name"] + ("" if entry["color"] is Color else "\n" + String(entry["color"])))
		if entry["id"] == picked:
			_material_list.select(index)
	if not _material_list.is_anything_selected() and _material_list.item_count > 0:
		_material_list.select(0)
		_brush.material = _material_list.get_item_metadata(0)
		_brush.material_name = _material_list.get_item_text(0)


# A small square picture of a material: a plain swatch for a color, or its Color image shrunk
# down (made once, then kept)
func _thumbnail(look) -> Texture2D:
	var key := str(look)
	if _thumbnails.has(key):
		return _thumbnails[key]
	var image: Image
	if look is Color:
		image = Image.create_empty(THUMBNAIL, THUMBNAIL, false, Image.FORMAT_RGB8)
		image.fill(look)
	else:
		var texture := load(look) as Texture2D
		if texture == null:
			return null
		image = texture.get_image().duplicate()
		if image.is_compressed():
			image.decompress()
		image.convert(Image.FORMAT_RGB8)
		image.resize(THUMBNAIL, THUMBNAIL, Image.INTERPOLATE_LANCZOS)
	_thumbnails[key] = ImageTexture.create_from_image(image)
	return _thumbnails[key]


# Shows the current category's scenes, with pictures of them as they load
func _fill_palette() -> void:
	_palette_list.clear()
	var entries: Array = _painter.palette.get(_painter.category, [])
	var previewer := EditorInterface.get_resource_previewer()
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var label: String = entry["name"] + ("  (local)" if entry["local_only"] else "")
		var index := _palette_list.add_item(label)
		_palette_list.set_item_metadata(index, entry["path"])
		_palette_list.set_item_tooltip(index, entry["path"] + ("\nLocal only: this folder is kept out of git" if entry["local_only"] else ""))
		if entry["path"] in _painter.selected:
			_palette_list.select(index, false)
		previewer.queue_resource_preview(entry["path"], self, "_on_preview", index)
	if entries.is_empty():
		_status.text = "Nothing in %s yet: put scenes in assets/%s/." % [_painter.category, _painter.category.to_lower()]


func _on_preview(path: String, preview: Texture2D, _thumbnail: Texture2D, index: int) -> void:
	if preview and index < _palette_list.item_count and _palette_list.get_item_metadata(index) == path:
		_palette_list.set_item_icon(index, preview)


func _read_palette_picks() -> void:
	var picks: Array[String] = []
	for i in _palette_list.get_selected_items():
		picks.append(_palette_list.get_item_metadata(i))
	_painter.selected = picks
	_status.text = ""


# A labelled slider with its number beside it
func _slider_row(label: String, low: float, high: float, step: float, value: float, changed: Callable) -> Control:
	var row := VBoxContainer.new()
	var title := Label.new()
	title.text = label
	row.add_child(title)
	var line := HBoxContainer.new()
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var number := SpinBox.new()
	number.min_value = low
	number.max_value = high
	number.step = step
	number.value = value
	number.custom_minimum_size.x = 80
	slider.value_changed.connect(func(v):
		number.set_value_no_signal(v)
		changed.call(v)
		redraw_overlay.call())
	number.value_changed.connect(func(v):
		slider.set_value_no_signal(v)
		changed.call(v)
		redraw_overlay.call())
	line.add_child(slider)
	line.add_child(number)
	row.add_child(line)
	return row


func _help(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	label.add_theme_font_size_override("font_size", 12)
	return label


# ---- Helpers ----

func _valley():
	var root := EditorInterface.get_edited_scene_root()
	if root == null or not root.is_inside_tree():
		return null
	var valley = root.get_tree().get_first_node_in_group("valley")
	if valley and (valley == root or root.is_ancestor_of(valley)):
		return valley
	return null


func _set_valley(setting: String, on: bool) -> void:
	var valley = _valley()
	if valley == null or valley.get(setting) == on:
		return
	undo_redo.create_action("Set %s" % setting.capitalize())
	undo_redo.add_do_property(valley, setting, on)
	undo_redo.add_undo_property(valley, setting, valley.get(setting))
	undo_redo.commit_action()


func _add_heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	add_child(label)


func _add_button(parent: Control, text: String, tip: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	parent.add_child(button)
	_buttons.append(button)
	return button
