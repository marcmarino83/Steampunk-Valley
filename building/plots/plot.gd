class_name Plot
extends Node3D
## One plot: a rectangle on the ground (its middle is this node's origin, its sides along its own
## X and Z) that turns the pieces and furniture built in it into a working building. Once placed it
## shows nothing in the world, except in plot view (P with the hammer out, or while the build
## menu's Plots tab is open): then a faint glowing outline on the ground, green while it's working
## and amber while it's missing requirements. Its name, status and checklist show in the HUD's plot
## tracker (see PlotTracker). In plot view, E aimed at the ground or a piece inside it opens the
## plot panel. PlotRegistry keeps them all, works out which pieces each one owns, and checks their
## requirements. A preview (drawing, moving, resizing) also floats a label with its size.

## The outline: a low glowing strip along the ground, measured against the ground this often
const LINE_HEIGHT := 0.14
const LINE_WIDTH := 0.07
const LINE_STEP := 0.5
## How bright it is (above 1 so it glows), how see-through, and how much brighter an edge being
## dragged is
const GLOW := 1.5
const FAINT := 0.55
const EDGE_RIM := 1.0
const EDGE_PLAIN := 0.6
## A preview's label floats this high above the middle
const LABEL_HEIGHT := 2.2
## Outline colours in plot view: working, and missing requirements
const WORKING_COLOR := Color(0.35, 0.95, 0.4)
const MISSING_COLOR := BrassStyle.WARN
## Edges, as bits (for `highlight_edges`): +X, -X, +Z, -Z
const RIGHT := 1
const LEFT := 2
const FRONT := 4
const BACK := 8

## Its id (kept in saves and on every piece it owns), kind, name and size in meters (x: width
## along its X, y: depth along its Z)
var plot_id := ""
var plot_type: PlotType
var plot_name := ""
var size := Vector2(6, 6)
## The last requirement check (see PlotRegistry): every line as {"text", "ok"}, whether all are
## met, what's missing in a few words ("bed", "door"), and how many settlers it holds
var checklist: Array = []
var working := false
var missing: PackedStringArray = []
var capacity := 0
## True once its requirements have been checked at least once
var checked := false
## For a plot whose output is shared out by sliders (the Forager's Hut): item -> percent, adding up
## to 100 (empty: the type's starting split)
var production := {}
## For a house (a plot that houses settlers): "villager" (settlers can be assigned to it) or
## "player" (the player's own home: never assigned)
var housing := "villager"
## Which edges stand out (while dragging one), as RIGHT | LEFT | FRONT | BACK bits
var highlight_edges := 0:
	set(value):
		if value != highlight_edges:
			highlight_edges = value
			rebuild()

var _outline: MeshInstance3D
var _material: StandardMaterial3D
var _label: Label3D
var _preview := false
var _shown := false
var _tint := Color(0, 0, 0, 0)


## Sets it up before it's added to the world. A preview (drawing, moving or resizing) always shows.
func setup(type: PlotType, plot_size: Vector2, preview := false) -> void:
	plot_type = type
	size = plot_size
	_preview = preview
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.vertex_color_use_as_albedo = true
	_outline = MeshInstance3D.new()
	_outline.top_level = true
	_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_outline.material_override = _material
	add_child(_outline)
	_shown = preview
	_apply_colour()
	if not preview:
		return
	_label = Label3D.new()
	_label.top_level = true
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0011
	_label.font_size = 30
	_label.outline_size = 9
	_label.outline_modulate = Color(0.08, 0.05, 0.03, 0.9)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)


func _ready() -> void:
	rebuild()
	set_view(_shown)


## Plot view on or off: the outline shows, or nothing does
func set_view(shown: bool) -> void:
	_shown = shown or _preview
	if _outline:
		_outline.visible = _shown


## Tints the outline (green or red while drawing or moving), or back to its own colour (alpha 0)
func set_tint(color: Color) -> void:
	_tint = color
	_apply_colour()


## Hides the whole plot (while it's being moved, or a preview stands in for it), or shows it again
func set_shown(shown: bool) -> void:
	visible = shown


func rename(new_name: String) -> void:
	plot_name = new_name


## After a requirement check: the outline's colour follows whether it's working
func update_status() -> void:
	_apply_colour()


## A preview's label (its size as it's drawn), in a colour
func set_label(text: String, color := Color(1, 1, 1)) -> void:
	if _label:
		_label.text = text
		_label.modulate = color


## True if a spot (in the world) is inside, seen from above
func contains(point: Vector3) -> bool:
	var local := to_local_2d(point)
	return absf(local.x) <= size.x / 2.0 + 0.001 and absf(local.y) <= size.y / 2.0 + 0.001


## A spot in the world, as (x, z) in the plot's own flat space
func to_local_2d(point: Vector3) -> Vector2:
	var local := global_transform.affine_inverse() * point
	return Vector2(local.x, local.z)


## The ground height under a spot (x, z in the world), from the valley's terrain
static func ground_at(node: Node, x: float, z: float) -> float:
	var valley = node.get_tree().get_first_node_in_group("valley") if node.is_inside_tree() else null
	if valley and valley.has_heights():
		var origin: Vector3 = valley.global_position
		return origin.y + valley.get_surface_height(x - origin.x, z - origin.z)
	return node.global_position.y if node is Node3D and node.is_inside_tree() else 0.0


## Remakes the outline (following the ground) and puts the label over the middle. Call after
## moving or resizing it.
func rebuild() -> void:
	if not is_inside_tree() or _outline == null:
		return
	_outline.global_transform = Transform3D.IDENTITY
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := size / 2.0
	var corners := [Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y), Vector2(-half.x, -half.y)]
	# Right (+X), left (-X), front (+Z), back (-Z)
	var edges := [[corners[0], corners[1], RIGHT], [corners[2], corners[3], LEFT], [corners[1], corners[2], FRONT], [corners[3], corners[0], BACK]]
	for edge in edges:
		var lit: bool = highlight_edges & int(edge[2]) != 0
		var shade := EDGE_RIM if lit else EDGE_PLAIN
		_strip(st, edge[0], edge[1], Color(shade, shade, shade, 1.0 if lit else FAINT))
	_outline.mesh = st.commit()
	var middle := _world_at(Vector2.ZERO)
	if _label:
		_label.global_position = middle + Vector3.UP * LABEL_HEIGHT


# ---- Opening its panel (E, aimed inside it in plot view; see the player) ----

func can_interact() -> bool:
	return not _preview


func get_prompt() -> String:
	return "Open %s" % plot_name


func interact(player) -> void:
	player.open_plot_panel(self)


## The slider percentages (the type's starting split until changed)
func shares() -> Dictionary:
	if production.is_empty():
		production = plot_type.split_output.duplicate()
	return production


## What it makes in a day at full strength (item -> amount)
func daily_output() -> Dictionary:
	return plot_type.output_for(shares() if plot_type.split_output_total > 0 else {})


func save_data() -> Dictionary:
	var data := {
		"id": plot_id,
		"type": plot_type.resource_path,
		"name": plot_name,
		"position": SaveGame.from_vector(global_position),
		"turn": global_rotation.y,
		"size": [size.x, size.y],
	}
	if not production.is_empty():
		data["production"] = production.duplicate()
	if housing != "villager":
		data["housing"] = housing
	return data


## True if settlers can be given a home here: a house plot set to villager housing
func is_villager_housing() -> bool:
	return not plot_type.houses_per.is_empty() and housing == "villager"


func _apply_colour() -> void:
	if _material == null:
		return
	# A preview takes its tint; a placed plot shows its status
	var base: Color = _tint if _tint.a > 0.0 else (WORKING_COLOR if working else MISSING_COLOR)
	_material.albedo_color = Color(base.r * GLOW, base.g * GLOW, base.b * GLOW)


# A spot in the plot's flat space, on the ground, in the world
func _world_at(local: Vector2) -> Vector3:
	var point := global_transform * Vector3(local.x, 0, local.y)
	point.y = ground_at(self, point.x, point.z)
	return point


# One edge: a low upright strip and a flat band on the ground, following it
func _strip(st: SurfaceTool, a: Vector2, b: Vector2, color: Color) -> void:
	var length := a.distance_to(b)
	var steps := maxi(ceili(length / LINE_STEP), 1)
	var across3 := Vector3(b.y - a.y, 0, a.x - b.x).normalized()
	var across := global_transform.basis * across3 * (LINE_WIDTH / 2.0)
	var previous := _world_at(a) + Vector3.UP * 0.03
	for k in range(1, steps + 1):
		var point := _world_at(a.lerp(b, float(k) / steps)) + Vector3.UP * 0.03
		_quad(st, previous, point, point + Vector3.UP * LINE_HEIGHT, previous + Vector3.UP * LINE_HEIGHT, color)
		_quad(st, previous - across, point - across, point + across, previous + across, color)
		previous = point


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	for p in [a, b, c, a, c, d]:
		st.set_color(color)
		st.add_vertex(p)
