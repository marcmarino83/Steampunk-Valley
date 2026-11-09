class_name BuildingTemplate
extends RefCounted
## A saved building: every piece, furniture item, workbench, chest and campfire a plot owned (where
## each sat relative to the plot, turn and height included), with the plot's type and size, under a
## name. Placing one puts it all down as ghosts in a new plot (see TemplatePlacer).
##
## Each is a JSON file with a picture of the building beside it (.png):
##   - built-in ones in the project, res://buildables/templates/ (made in debug builds with "Save as
##     built-in"; marked built-in in the menu)
##   - the player's own in the user folder, user://templates/
## The file: {"name", "plot_type" (a PlotType path), "size": [w, d], "built_in",
## "items": [{"buildable" (a path), "position": [x, y, z], "turn"}, ...]} with positions and turns
## relative to the plot (its middle, on the ground).

const BUILT_IN_FOLDER := "res://buildables/templates"
const PLAYER_FOLDER := "user://templates"

var template_name := ""
var plot_type: PlotType
var size := Vector2(6, 6)
var built_in := false
## {"buildable": Buildable, "relative": Transform3D}, pieces and buildings alike
var items: Array = []
## Where it was read from (its .json)
var path := ""

var _thumbnail: Texture2D
var _cost := {}


## Every template there is, built-in ones first, each group by name
static func load_all() -> Array:
	var found := []
	for folder in [BUILT_IN_FOLDER, PLAYER_FOLDER]:
		var group := []
		if not DirAccess.dir_exists_absolute(folder):
			continue
		for file in DirAccess.get_files_at(folder):
			if not file.ends_with(".json"):
				continue
			var template := read(folder.path_join(file))
			if template:
				group.append(template)
		group.sort_custom(func(a, b): return a.template_name.naturalnocasecmp_to(b.template_name) < 0)
		found.append_array(group)
	return found


## A template from its file, or null if it can't be read
static func read(file_path: String) -> BuildingTemplate:
	if not FileAccess.file_exists(file_path):
		return null
	var data = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	if not data is Dictionary:
		return null
	var type := load(str(data.get("plot_type", ""))) as PlotType
	if type == null:
		return null
	var template := BuildingTemplate.new()
	template.path = file_path
	template.template_name = str(data.get("name", file_path.get_file().get_basename()))
	template.plot_type = type
	var saved_size: Array = data.get("size", [type.min_size.x, type.min_size.y])
	template.size = Vector2(float(saved_size[0]), float(saved_size[1]))
	template.built_in = file_path.begins_with("res://")
	for entry in data.get("items", []):
		var buildable := load(str(entry.get("buildable", ""))) as Buildable
		if buildable == null:
			continue
		var at := SaveGame.to_vector(entry.get("position"))
		template.items.append({"buildable": buildable, "relative": Transform3D(Basis(Vector3.UP, float(entry.get("turn", 0.0))), at)})
	return template


## A template of everything a plot owns (ghosts included), or null if it owns nothing
static func from_plot(plots: PlotRegistry, plot: Plot, name: String) -> BuildingTemplate:
	var template := BuildingTemplate.new()
	template.template_name = name
	template.plot_type = plot.plot_type
	template.size = plot.size
	var from := plot.global_transform.affine_inverse()
	for item in plots.owned_items(plot, true):
		var buildable: Buildable = null
		if item is BuildPiece:
			buildable = item.buildable
		else:
			buildable = load(str(item.get_meta(BuildPlacer.BUILDABLE_META, ""))) as Buildable
		if buildable == null:
			continue
		var relative: Transform3D = from * (item as Node3D).global_transform
		# Only its turn about the upright counts (pieces never tilt)
		var turn := relative.basis.get_euler().y
		template.items.append({"buildable": buildable, "relative": Transform3D(Basis(Vector3.UP, turn), relative.origin)})
	return template if not template.items.is_empty() else null


## Writes it to its file (built-in: into the project; otherwise the player's folder), with its
## picture. Returns the file's path, or empty if it couldn't be written.
func write(as_built_in: bool, picture: Image) -> String:
	built_in = as_built_in
	var folder := BUILT_IN_FOLDER if as_built_in else PLAYER_FOLDER
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder) if as_built_in else folder)
	var file_path := folder.path_join(slug(template_name) + ".json")
	var list := []
	for item in items:
		var relative: Transform3D = item["relative"]
		list.append({
			"buildable": (item["buildable"] as Buildable).resource_path,
			"position": SaveGame.from_vector(relative.origin),
			"turn": relative.basis.get_euler().y,
		})
	var data := {
		"name": template_name,
		"plot_type": plot_type.resource_path,
		"size": [size.x, size.y],
		"built_in": as_built_in,
		"items": list,
	}
	var target := ProjectSettings.globalize_path(file_path) if as_built_in else file_path
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		push_error("BuildingTemplate: couldn't write %s (error %d)" % [target, FileAccess.get_open_error()])
		return ""
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	if picture:
		picture.save_png(target.get_basename() + ".png")
	path = file_path
	_thumbnail = ImageTexture.create_from_image(picture) if picture else null
	return file_path


## True if it may be deleted or renamed: the player's own always; a built-in one only in a debug
## build (which edits the files in res://buildables/templates/), never in a release build
func can_change() -> bool:
	return not built_in or OS.is_debug_build()


## Deletes its file and its picture. Plots and buildings already placed from it don't depend on
## the file, so they stay as they are. Returns why it couldn't, or empty if it did.
func delete_files() -> String:
	if not can_change():
		return "Built-in templates can't be deleted"
	if path.is_empty() or not FileAccess.file_exists(path):
		return "Its file is already gone"
	var error := DirAccess.remove_absolute(_disk(path))
	if error != OK:
		return "Couldn't delete %s (error %d)" % [path.get_file(), error]
	for extra in [_picture_path(), _picture_path() + ".import"]:
		if FileAccess.file_exists(extra):
			DirAccess.remove_absolute(_disk(extra))
	path = ""
	_thumbnail = null
	return ""


## Gives it a new name: rewrites its file with the name, and renames the file and its picture to
## match ("Big House" -> big_house.json, big_house.png). Returns why it couldn't, or empty if it did.
func rename_to(new_name: String) -> String:
	new_name = new_name.strip_edges()
	if not can_change():
		return "Built-in templates can't be renamed"
	if new_name.is_empty():
		return "Give it a name"
	if slug(new_name).replace("_", "").is_empty():
		return "Use some letters or numbers in the name"
	if path.is_empty() or not FileAccess.file_exists(path):
		return "Its file is gone"
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return "Couldn't read %s" % path.get_file()
	var new_path := path.get_base_dir().path_join(slug(new_name) + ".json")
	if new_path != path and FileAccess.file_exists(new_path):
		return "There's already a template called that"
	data["name"] = new_name
	var file := FileAccess.open(_disk(new_path), FileAccess.WRITE)
	if file == null:
		return "Couldn't write %s (error %d)" % [new_path.get_file(), FileAccess.get_open_error()]
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	if new_path != path:
		DirAccess.remove_absolute(_disk(path))
		var old_picture := _picture_path()
		var new_picture := new_path.get_basename() + ".png"
		if FileAccess.file_exists(old_picture):
			DirAccess.rename_absolute(_disk(old_picture), _disk(new_picture))
		# The editor imports the renamed picture afresh
		if FileAccess.file_exists(old_picture + ".import"):
			DirAccess.remove_absolute(_disk(old_picture + ".import"))
	path = new_path
	template_name = new_name
	return ""


func _picture_path() -> String:
	return path.get_basename() + ".png"


# A path as the file system sees it (res:// paths into the project folder)
static func _disk(file_path: String) -> String:
	return ProjectSettings.globalize_path(file_path) if file_path.begins_with("res://") else file_path


## Replaces its picture (the .png beside its file), e.g. after the thumbnail staging changed
func replace_picture(picture: Image) -> void:
	if picture == null or path.is_empty():
		return
	var picture_path := path.get_basename() + ".png"
	picture.save_png(ProjectSettings.globalize_path(picture_path) if picture_path.begins_with("res://") else picture_path)
	_thumbnail = ImageTexture.create_from_image(picture)


## Its picture (rendered when it was saved), or null
func thumbnail() -> Texture2D:
	if _thumbnail == null and not path.is_empty():
		var picture_path := path.get_basename() + ".png"
		var image := Image.load_from_file(ProjectSettings.globalize_path(picture_path) if picture_path.begins_with("res://") else picture_path)
		if image and not image.is_empty():
			_thumbnail = ImageTexture.create_from_image(image)
	return _thumbnail


## What building all of it costs (each piece's first way of paying), as {item: amount}
func total_cost() -> Dictionary:
	if _cost.is_empty():
		for item in items:
			var buildable: Buildable = item["buildable"]
			if buildable.costs.is_empty():
				continue
			var cost: Dictionary = buildable.costs[0]
			for thing in cost:
				_cost[thing] = int(_cost.get(thing, 0)) + int(cost[thing])
	return _cost


## A file name for a template name: "Small House" -> "small_house"
static func slug(text: String) -> String:
	var out := ""
	for c in text.to_lower().strip_edges():
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.trim_prefix("_").trim_suffix("_")
	return out if not out.is_empty() else "template"
