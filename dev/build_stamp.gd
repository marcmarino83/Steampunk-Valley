class_name BuildStamp
extends RefCounted
## Which code a debug run is: a short hash of every script and shader in the project (tests aside),
## the time of the newest change among them, and the git commit it's on. Any change to the code
## changes the hash, so a bug snapshot (F9) or a screenshot says exactly which code made it. Shown
## in the top-right corner of debug builds (see DevConsole), and kept in every snapshot's JSON.

## Folders left out: not the game's code, or too big to look through
const SKIP := [".godot", ".git", "assets", "docs", "tests", "addons"]

static var _text := ""
static var _hash := ""


## "code 1a2b3c4d · 10 Nov 20:31 · git d429f7f"
static func text() -> String:
	if _text.is_empty():
		_work_out()
	return _text


## Just the code's hash ("1a2b3c4d")
static func code_hash() -> String:
	if _hash.is_empty():
		_work_out()
	return _hash


static func _work_out() -> void:
	var files: PackedStringArray = []
	_gather("res://", files)
	files.sort()
	var sums := ""
	var newest := 0
	for path in files:
		sums += path + ":" + FileAccess.get_md5(path) + ";"
		newest = maxi(newest, FileAccess.get_modified_time(path))
	_hash = sums.md5_text().substr(0, 8)
	var when := Time.get_datetime_dict_from_unix_time(newest + int(Time.get_time_zone_from_system()["bias"]) * 60)
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	_text = "code %s · %d %s %02d:%02d" % [_hash, when["day"], months[int(when["month"]) - 1], when["hour"], when["minute"]]
	var commit := _git_commit()
	if not commit.is_empty():
		_text += " · git " + commit


static func _gather(folder: String, files: PackedStringArray) -> void:
	for dir in DirAccess.get_directories_at(folder):
		if dir in SKIP or dir.begins_with("."):
			continue
		_gather(folder.path_join(dir), files)
	for file in DirAccess.get_files_at(folder):
		if file.ends_with(".gd") or file.ends_with(".gdshader"):
			files.append(folder.path_join(file))


# The commit the project's checked out at (short), or empty if it isn't a git checkout
static func _git_commit() -> String:
	var head_path := ProjectSettings.globalize_path("res://.git/HEAD")
	if not FileAccess.file_exists(head_path):
		return ""
	var head := FileAccess.get_file_as_string(head_path).strip_edges()
	if head.begins_with("ref: "):
		var ref := ProjectSettings.globalize_path("res://.git/" + head.substr(5))
		head = FileAccess.get_file_as_string(ref).strip_edges() if FileAccess.file_exists(ref) else ""
	return head.substr(0, 7)
