@tool
extends VBoxContainer
## The World Tools panel: buttons that add terrain modifiers, trails and clear zones at the
## middle of the 3D view; a list of everything placed, to select, jump to or delete; and the
## valley's editor views. Everything it adds goes under TerrainEdits in the world scene.

# The scenes the buttons add. They're loaded when a button is pressed, not when this script
# is read, so a moved or broken scene shows up as a message in the panel instead of stopping
# the whole plugin from loading.
const MODIFIER_SCENE := "res://terrain_modifier.tscn"
const PATH_SCENE := "res://terrain_path.tscn"
const ZONE_SCENE := "res://clear_zone.tscn"
## The terrain modifier's modes, in the same order as its Mode setting
const MODES := ["Lower", "Raise", "Flatten", "Smooth", "Squash"]
const FLATTEN := 2

## Where each kind lives in the world scene, under TerrainEdits. Modifiers come before paths,
## so a flattened area is in place before a trail runs into it. (Objects, with the Object
## Painter's trees, rocks and bushes, is made the first time something is placed.)
const GROUPS := ["Modifiers", "Paths", "ClearZones"]
const OBJECT_PAINTER := "res://addons/world_tools/object_painter.gd"
const TEXTURE_BRUSH := "res://addons/world_tools/texture_brush.gd"
const OBJECTS := "objects"
const TEXTURE := "texture"

var undo_redo: EditorUndoRedoManager:
	set(value):
		undo_redo = value
		if _painter:
			_painter.undo_redo = value
		if _brush:
			_brush.undo_redo = value
## Set by the plugin: redraws the 3D view's overlay (the brush circle)
var redraw_overlay := func(): pass

# The painting tools, and which one is switched on ("" = neither)
var _painter: RefCounted
var _brush: RefCounted
var _active_tool := ""
var _object_toggle: Button
var _texture_toggle: Button
var _object_panel: Control
var _texture_panel: Control
var _categories: TabBar
var _palette_list: ItemList
var _material_list: ItemList

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

	_add_heading("Add")
	var grid := GridContainer.new()
	grid.columns = 2
	add_child(grid)
	for mode in MODES.size():
		var label: String = MODES[mode]
		_add_button(grid, label, "Add a %s terrain modifier at the middle of the 3D view" % label, _add_modifier.bind(mode))
	_add_button(grid, "Path", "Add a trail at the middle of the 3D view", _add_path)
	_add_button(grid, "Clear Zone", "Add a circle that keeps trees, resources and boulders out", _add_zone)

	_add_heading("Paint")
	var tools := GridContainer.new()
	tools.columns = 2
	add_child(tools)
	_object_toggle = _add_button(tools, "Object Painter", "Place and paint trees, rocks and bushes in the 3D view", _toggle_tool.bind(OBJECTS))
	_object_toggle.toggle_mode = true
	_texture_toggle = _add_button(tools, "Texture Brush", "Paint grass, dirt, forest floor, gravel or rock onto the ground", _toggle_tool.bind(TEXTURE))
	_texture_toggle.toggle_mode = true
	_object_panel = _build_object_panel()
	add_child(_object_panel)
	_texture_panel = _build_texture_panel()
	add_child(_texture_panel)

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
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(func():
		if _active_tool == OBJECTS:
			_painter.scan_palette()
			_fill_palette())


func _process(delta: float) -> void:
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
	node.name = label
	if mode == FLATTEN:
		# Level to the ground that's there, so a new Flatten doesn't dig a pit or build a mesa
		node.level_to_ground = true
	_place(node, "Modifiers", "Add %s modifier" % label)


func _add_path() -> void:
	var node := _make(PATH_SCENE)
	if node:
		node.name = "Path"
		_place(node, "Paths", "Add trail")


func _add_zone() -> void:
	var node := _make(ZONE_SCENE)
	if node:
		node.name = "ClearZone"
		_place(node, "ClearZones", "Add clear zone")


# Loads a scene and makes one, or says in the panel why it couldn't
func _make(path: String) -> Node3D:
	var scene := load(path) as PackedScene
	if scene == null:
		_status.text = "Couldn't load %s. Was it moved or renamed?" % path
		push_error("World Tools: couldn't load " + path)
		return null
	return scene.instantiate() as Node3D


# Adds a node under its TerrainEdits group, at the ground in the middle of the 3D view, and
# selects it. One Ctrl+Z takes it away again.
func _place(node: Node3D, group: String, action: String) -> void:
	var root := EditorInterface.get_edited_scene_root()
	var parent := _group_node(group)
	if root == null or parent == null:
		node.free()
		return
	var spot := _view_center_on_ground()
	node.position = parent.global_transform.affine_inverse() * spot
	undo_redo.create_action(action)
	undo_redo.add_do_method(parent, "add_child", node, true)
	undo_redo.add_do_method(node, "set_owner", root)
	undo_redo.add_do_reference(node)
	undo_redo.add_undo_method(parent, "remove_child", node)
	undo_redo.commit_action()
	_select(node, false)


# Where the middle of the 3D view is looking at the ground (or a spot in front of the camera)
func _view_center_on_ground() -> Vector3:
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var camera := viewport.get_camera_3d()
	var valley = _valley()
	if camera == null:
		return Vector3.ZERO
	var middle := viewport.get_visible_rect().size * 0.5
	var from := camera.project_ray_origin(middle)
	var direction := camera.project_ray_normal(middle)
	if valley and valley.has_heights():
		var previous := from
		for i in 3000:
			var here := from + direction * 2.0 * i
			if here.y <= valley.get_height(here.x, here.z):
				var above := previous
				var below := here
				for k in 12:
					var mid := (above + below) * 0.5
					if mid.y > valley.get_height(mid.x, mid.z):
						above = mid
					else:
						below = mid
				return Vector3(below.x, valley.get_height(below.x, below.z), below.z)
			previous = here
		# Looking at the sky: drop a spot 30 m ahead onto the ground
		var ahead := from + direction * 30.0
		return Vector3(ahead.x, valley.get_height(ahead.x, ahead.z), ahead.z)
	return from + direction * 30.0


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
				item.select(0)


func _describe(node: Node) -> String:
	if node.is_in_group("clear_zones"):
		return "%s   r %.0f m" % [node.name, node.radius]
	if node.has_method("trail_points"):
		return "%s   %d points" % [node.name, node.curve.point_count if node.curve else 0]
	var mode: String = MODES[node.mode] if node.mode >= 0 and node.mode < MODES.size() else "?"
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
	var tool := _tool()
	if tool == null:
		return false
	var used: bool = tool.handle_input(camera, event, _valley())
	if used and tool == _painter and _painter.status != "":
		_status.text = _painter.status
	return used


## Called by the plugin to draw over the 3D view: the brush circle and the controls hint
func draw_overlay(overlay: Control) -> void:
	var tool := _tool()
	var camera := EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	if tool and camera:
		tool.draw(overlay, camera, _valley())


func _tool() -> RefCounted:
	match _active_tool:
		OBJECTS:
			return _painter
		TEXTURE:
			return _brush
	return null


# Switches a painting tool on (and the other off), or off again if it was already on
func _toggle_tool(which: String) -> void:
	var valley = _valley()
	var tool := _tool()
	if tool and valley:
		tool.finish_stroke(valley)
	_active_tool = "" if _active_tool == which else which
	if _active_tool == OBJECTS and _painter:
		_painter.scan_palette()
		_fill_palette()
	_object_toggle.set_pressed_no_signal(_active_tool == OBJECTS)
	_texture_toggle.set_pressed_no_signal(_active_tool == TEXTURE)
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
	for c in ["Trees", "Rocks", "Bushes"]:
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
	rescan.tooltip_text = "Look for new scenes in assets/trees, assets/rocks and assets/bushes"
	rescan.pressed.connect(func():
		_painter.scan_palette()
		_fill_palette())
	box.add_child(rescan)
	box.add_child(_help("Click: place one. Drag: paint many. Alt: erase (scattered ones too). Drag a placed object to move it; hold Shift for fine moves."))
	return box


func _build_texture_panel() -> Control:
	var box := VBoxContainer.new()
	box.visible = false
	_material_list = ItemList.new()
	_material_list.icon_mode = ItemList.ICON_MODE_TOP
	_material_list.fixed_icon_size = Vector2i(56, 56)
	_material_list.max_columns = 0
	_material_list.same_column_width = true
	_material_list.custom_minimum_size = Vector2(0, 100)
	var swatches := {
		"Grass": Color(0.22, 0.29, 0.1), "Dirt": Color(0.28, 0.24, 0.17),
		"Forest Floor": "res://assets/textures/forest_floor/Ground037_2K-JPG_Color.jpg",
		"Gravel Path": "res://assets/textures/gravel_path/Ground108_2K-JPG_Color.jpg",
		"Rock": "res://assets/textures/rock_cliff/Rock051_2K-JPG_Color.jpg",
	}
	for name in swatches:
		var look = swatches[name]
		var icon: Texture2D
		if look is Color:
			var image := Image.create_empty(56, 56, false, Image.FORMAT_RGB8)
			image.fill(look)
			icon = ImageTexture.create_from_image(image)
		elif ResourceLoader.exists(look):
			icon = load(look)
		_material_list.add_item(name, icon)
	_material_list.select(0)
	_material_list.item_selected.connect(func(i): _brush.material = i)
	box.add_child(_material_list)
	box.add_child(_slider_row("Brush Radius (m)", 0.5, 40.0, 0.5, _brush.radius, func(v): _brush.radius = v))
	box.add_child(_slider_row("Strength", 0.02, 1.0, 0.01, _brush.strength, func(v): _brush.strength = v))
	box.add_child(_slider_row("Falloff", 0.0, 1.0, 0.01, _brush.falloff, func(v): _brush.falloff = v))
	box.add_child(_help("Click or drag to paint. Alt erases back to the automatic coloring. Saved after every stroke."))
	return box


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
