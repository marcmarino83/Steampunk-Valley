class_name IconUpdater
extends Node
## Keeps the build menu's icons up to date while working on the game: re-renders (with IconStudio)
## every icon whose piece has changed since it was last drawn, and writes it over the icon file.
##
## Each icon's fingerprint covers everything it's drawn from: the buildable's file and what it
## loads (its scene, model, materials and their textures), the piece's model folder in
## assets/buildables/<shape>/, the code that shapes and draws pieces, the studio itself and
## STAGING_VERSION (bump it to redraw them all). The fingerprints are kept in MANIFEST.
##
## Runs from the title screen in debug runs from the project (never in an exported game), and from
## the developer console ("icons", or "icons all" to redraw every one). The game uses the new
## pictures at once; the editor picks the files up when it next gets focus.

signal finished(count: int)

const MANIFEST := "res://assets/icons/build/icon_manifest.json"
const BUILDABLES_FOLDER := "res://buildables"
## Bump to redraw every icon (after changing how they're staged)
const STAGING_VERSION := 1
## How template pictures are staged: a picture older than this file is drawn again
const THUMBNAIL_CODE := "res://building/templates/template_thumbnail.gd"
## Code that changes how pieces look
const CODE := [
	"res://building/icons/icon_studio.gd",
	"res://building/icons/icon_ghost.gdshader",
	"res://building/pieces/piece_shapes.gd",
	"res://building/pieces/piece_detail.gd",
	"res://building/pieces/piece_registry.gd",
	"res://building/pieces/build_piece.gd",
	"res://building/pieces/piece_surface.gdshader",
	"res://building/pieces/piece_detail.gdshader",
]

var running := false

# The pictures drawn this run, by icon path: held so they stay in the resource cache in place of
# the not-yet-reimported files
static var _fresh := {}

var _run_on_ready := false
var _run_all := false


## True where icons can be redrawn: a debug run from the project, with a screen
static func available() -> bool:
	return OS.is_debug_build() and not OS.has_feature("template") and DisplayServer.get_name() != "headless"


## Starts a quiet update in the background, on the scene tree's root (so it carries on when the
## title screen gives way to the game). Returns the updater, or null where it can't run.
static func start(tree: SceneTree, all := false) -> IconUpdater:
	if not available():
		return null
	var updater := IconUpdater.new()
	updater.name = "IconUpdater"
	updater._run_on_ready = true
	updater._run_all = all
	tree.root.add_child.call_deferred(updater)
	return updater


func _ready() -> void:
	if _run_on_ready:
		await update(_run_all)
		queue_free()


## Redraws the icons that have changed (or every one, with `all`). Returns how many it drew.
func update(all := false) -> int:
	if running or not available():
		return 0
	running = true
	var buildables := _drawable_buildables()
	var manifest := _read_manifest()
	var code_print := _code_fingerprint()
	var stale: Array[Buildable] = []
	var prints := {}
	for buildable in buildables:
		var fingerprint := _fingerprint(buildable, code_print)
		prints[buildable.resource_path] = fingerprint
		var icon_file := ProjectSettings.globalize_path(buildable.icon.resource_path)
		if all or manifest.get(buildable.resource_path, "") != fingerprint or not FileAccess.file_exists(icon_file):
			stale.append(buildable)
	var old_pictures := _stale_template_pictures(all)
	if stale.is_empty() and old_pictures.is_empty():
		running = false
		finished.emit(0)
		return 0
	var registry := PieceRegistry.new()
	# Template pictures drawn before the thumbnail staging last changed
	for template in old_pictures:
		var picture: Image = await TemplateThumbnail.render(self, registry, template)
		(template as BuildingTemplate).replace_picture(picture)
	var studio := IconStudio.new()
	studio.registry = registry
	add_child(studio)
	studio.measure(buildables)
	for buildable in stale:
		var image: Image = await studio.render(buildable)
		var path := buildable.icon.resource_path
		var error := image.save_png(ProjectSettings.globalize_path(path))
		if error != OK:
			push_warning("IconUpdater: couldn't write %s (error %d)" % [path, error])
			continue
		# Written after every icon, so stopping part-way (the game closing) loses nothing
		manifest[buildable.resource_path] = prints[buildable.resource_path]
		_write_manifest(manifest)
		# Use the new picture at once (the imported copy catches up when the editor reimports it)
		# (kept alive in _fresh, so loading the buildable again later this run still finds it)
		var fresh := ImageTexture.create_from_image(image)
		fresh.take_over_path(path)
		_fresh[path] = fresh
		buildable.icon = fresh
	studio.queue_free()
	registry.free()
	running = false
	print("IconUpdater: redrew %d build icon(s) and %d template picture(s)" % [stale.size(), old_pictures.size()])
	finished.emit(stale.size() + old_pictures.size())
	return stale.size() + old_pictures.size()


# Templates whose picture is older than the thumbnail code (or every one, with `all`)
func _stale_template_pictures(all: bool) -> Array:
	var staged := FileAccess.get_modified_time(THUMBNAIL_CODE)
	var found := []
	for template in BuildingTemplate.load_all():
		var picture := (template as BuildingTemplate).path.get_basename() + ".png"
		if all or not FileAccess.file_exists(picture) or FileAccess.get_modified_time(picture) < staged:
			found.append(template)
	return found


# Every buildable with an icon file that IconStudio draws (not plots or templates)
func _drawable_buildables() -> Array[Buildable]:
	var found: Array[Buildable] = []
	for file in _files_in(BUILDABLES_FOLDER):
		var buildable := load(file) as Buildable
		if buildable == null or buildable is PlotType or buildable is TemplateBuildable:
			continue
		if buildable.icon == null or buildable.icon.resource_path.is_empty():
			continue
		if not buildable is PieceBuildable and buildable.scene == null:
			continue
		found.append(buildable)
	return found


func _files_in(folder: String) -> PackedStringArray:
	var files: PackedStringArray = []
	for entry in ResourceLoader.list_directory(folder):
		if entry.ends_with("/"):
			files.append_array(_files_in(folder.path_join(entry.trim_suffix("/"))))
		elif entry.ends_with(".tres"):
			files.append(folder.path_join(entry))
	return files


func _fingerprint(buildable: Buildable, code_print: String) -> String:
	var parts := PackedStringArray([str(STAGING_VERSION), code_print])
	var seen := {buildable.icon.resource_path: true}
	_add_file(parts, buildable.resource_path, seen, 3)
	if buildable is PieceBuildable:
		var folder := "res://assets/buildables/%s" % (buildable as PieceBuildable).shape
		if DirAccess.dir_exists_absolute(folder):
			for file in DirAccess.get_files_at(folder):
				if not file.ends_with(".import"):
					_add_file(parts, folder.path_join(file), seen, 0)
		_add_file(parts, "res://building/furniture/%s_material.tres" % (buildable as PieceBuildable).shape, seen, 1)
	return "\n".join(parts).md5_text()


# A file's change time, and those of what it loads (to `depth` steps)
func _add_file(parts: PackedStringArray, path: String, seen: Dictionary, depth: int) -> void:
	if seen.has(path) or not FileAccess.file_exists(path):
		return
	seen[path] = true
	parts.append("%s@%d" % [path, FileAccess.get_modified_time(path)])
	if depth <= 0:
		return
	for dependency in ResourceLoader.get_dependencies(path):
		# "uid://...::::res://path" or just the path
		var dep_path := dependency.get_slice("::", 2) if dependency.contains("::") else dependency
		if dep_path.is_empty():
			dep_path = dependency.get_slice("::", 0)
		_add_file(parts, dep_path, seen, depth - 1)


func _code_fingerprint() -> String:
	var parts := PackedStringArray()
	for path in CODE:
		if FileAccess.file_exists(path):
			parts.append("%s@%d" % [path, FileAccess.get_modified_time(path)])
	return "\n".join(parts).md5_text()


func _read_manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return parsed if parsed is Dictionary else {}


func _write_manifest(manifest: Dictionary) -> void:
	var file := FileAccess.open(ProjectSettings.globalize_path(MANIFEST), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(manifest, "\t", true))
