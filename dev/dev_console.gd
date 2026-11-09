class_name DevConsole
extends Control
## The developer console (debug builds only: the player never makes one in a release build).
##
## ~ (the backquote key) opens and closes it: a brass plaque across the top of the screen with a
## scrolling log, in monospace, over an input line. Enter runs a command; Up / Down go through
## the commands typed before; Tab completes a command's name, an item name (give) or "settlement"
## (tp); Esc closes it. While it's open the player stands still and no other keys do anything.
## A small "DEV" tag shows in the top-right corner while any cheat toggle is on (see DevCheats).
##
## F9 and F10 are shortcuts for spawn_settler and day.

## How tall the plaque is (pixels at 1920 x 1080), and the gap to the screen's edges
const HEIGHT := 400.0
const EDGE := 24.0
const HISTORY_KEPT := 50
const ERROR_COLOR := "ff7a66"
const DIM_COLOR := "b8a98c"
const GOOD_COLOR := "9ee68a"

## Every command: its usage and what it does, in the order help lists them
const COMMANDS := {
	"help": ["help", "List the commands"],
	"give": ["give <item> [amount]", "Add items to your inventory (default 1), e.g. give planks 200"],
	"give_all": ["give_all [amount]", "Every resource item (default 100)"],
	"freebuild": ["freebuild", "Toggle: building, furniture, ghosts and crafting cost nothing"],
	"unlock_all": ["unlock_all", "Unlock every blueprint, recipe and plot type"],
	"god": ["god", "Toggle: hunger and stamina never drop, no damage"],
	"fly": ["fly", "Toggle: fly through everything (Space up, Ctrl down, Shift faster)"],
	"time": ["time <0-24>", "Set the time of day, in hours (6 is sunrise, 18 sunset)"],
	"day": ["day", "Skip to the next dawn: dusk meals, then dawn output (also F10)"],
	"spawn_settler": ["spawn_settler [count]", "Bring settlers in at once (default 1; also F9)"],
	"tp": ["tp <x> <z>  |  tp settlement", "Jump to a spot, or to the nearest plot"],
	"clear_inventory": ["clear_inventory", "Empty your inventory and action bar"],
	"save": ["save", "Make a manual save"],
	"load": ["load", "Load this world's newest save"],
	"icons": ["icons [all]", "Redraw the build icons whose pieces changed (all: every one)"],
}

var player: Node

var _panel: PanelContainer
var _log: RichTextLabel
var _entry: LineEdit
var _tag: Label
var _history: PackedStringArray = []
var _history_at := -1
var _mouse_before := Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "DejaVu Sans Mono", "Courier New", "monospace"])
	_panel = MenuStyle.panel()
	_panel.visible = false
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_panel.add_child(column)
	var title := Label.new()
	title.text = "Developer console  ·  help lists the commands  ·  [~] or [Esc] closes"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", BrassStyle.TEXT_DIM)
	column.add_child(title)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_override("normal_font", mono)
	_log.add_theme_font_size_override("normal_font_size", 17)
	_log.add_theme_color_override("default_color", BrassStyle.TEXT)
	column.add_child(_log)
	_entry = LineEdit.new()
	_entry.placeholder_text = "Type a command (Tab completes, Up/Down for earlier ones)"
	_entry.add_theme_font_override("font", mono)
	_entry.add_theme_font_size_override("font_size", 18)
	_entry.add_theme_color_override("font_color", BrassStyle.TEXT)
	_entry.add_theme_color_override("caret_color", BrassStyle.TEXT)
	_entry.add_theme_stylebox_override("normal", BrassStyle.frame("slot"))
	_entry.add_theme_stylebox_override("focus", BrassStyle.frame("slot_hover"))
	_entry.text_submitted.connect(_submit)
	column.add_child(_entry)
	_tag = Label.new()
	_tag.add_theme_font_override("font", mono)
	_tag.add_theme_font_size_override("font_size", 15)
	_tag.add_theme_color_override("font_color", Color(1.0, 0.55, 0.3))
	_tag.add_theme_color_override("font_outline_color", Color.BLACK)
	_tag.add_theme_constant_override("outline_size", 4)
	_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tag)
	_print("Steampunk Valley developer console. Type [b]help[/b] for the commands.", DIM_COLOR)


func is_open() -> bool:
	return _panel.visible


func open() -> void:
	if is_open():
		return
	_mouse_before = Input.mouse_mode
	_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_entry.grab_focus()


func close() -> void:
	if not is_open():
		return
	_panel.visible = false
	_entry.release_focus()
	Input.mouse_mode = _mouse_before


func _process(_delta: float) -> void:
	var screen := get_viewport_rect().size
	_panel.position = Vector2(EDGE, EDGE)
	_panel.size = Vector2(screen.x - EDGE * 2.0, HEIGHT)
	_tag.visible = DevCheats.any()
	if _tag.visible:
		_tag.text = "DEV · " + ", ".join(DevCheats.active_names())
		_tag.size = _tag.get_combined_minimum_size()
		_tag.position = Vector2(screen.x - EDGE - _tag.size.x, 76.0)


# The console's own keys come first: ~ opens and closes it, and while it's open Esc, Up, Down and
# Tab are its own
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	var key := event as InputEventKey
	if not key.echo and (key.keycode == KEY_QUOTELEFT or key.physical_keycode == KEY_QUOTELEFT):
		get_viewport().set_input_as_handled()
		if is_open():
			close()
		else:
			open()
		return
	if not is_open():
		return
	match key.keycode:
		KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close()
		KEY_UP:
			get_viewport().set_input_as_handled()
			_step_history(-1)
		KEY_DOWN:
			get_viewport().set_input_as_handled()
			_step_history(1)
		KEY_TAB:
			get_viewport().set_input_as_handled()
			_complete()


func _submit(text: String) -> void:
	_entry.clear()
	var line := text.strip_edges()
	if line.is_empty():
		return
	if _history.is_empty() or _history[-1] != line:
		_history.append(line)
		if _history.size() > HISTORY_KEPT:
			_history.remove_at(0)
	_history_at = -1
	_print("> " + line, DIM_COLOR)
	run(line)


func _step_history(step: int) -> void:
	if _history.is_empty():
		return
	if _history_at < 0:
		_history_at = _history.size() if step < 0 else -1
	_history_at += step
	if _history_at < 0:
		_history_at = 0
	if _history_at >= _history.size():
		_history_at = -1
		_entry.text = ""
	else:
		_entry.text = _history[_history_at]
	_entry.caret_column = _entry.text.length()


# ---- Running commands ----

## Runs one command line (typed, or from a shortcut key)
func run(line: String) -> void:
	var words := line.strip_edges().split(" ", false)
	if words.is_empty():
		return
	var command := words[0].to_lower()
	var args := words.slice(1)
	match command:
		"help":
			for name in COMMANDS:
				_print("  %-34s %s" % [COMMANDS[name][0], COMMANDS[name][1]])
		"give":
			_give(args)
		"give_all":
			_give_all(args)
		"freebuild":
			DevCheats.freebuild = not DevCheats.freebuild
			player._refresh_inventory_display()
			_toggled("freebuild", DevCheats.freebuild)
		"unlock_all":
			_unlock_all()
		"god":
			DevCheats.god = not DevCheats.god
			if DevCheats.god:
				player.hunger = 100.0
				player.stamina = player.max_stamina()
			_toggled("god", DevCheats.god)
		"fly":
			DevCheats.fly = not DevCheats.fly
			player.velocity = Vector3.ZERO
			_toggled("fly", DevCheats.fly)
		"time":
			_time(args)
		"day":
			player._settlers.skip_to_dawn()
			player.flash("Skipped to dawn (debug)")
			_print("Skipped to dawn: tonight's meals, then the day's output.", GOOD_COLOR)
		"spawn_settler":
			_spawn_settlers(args)
		"tp":
			_teleport(args)
		"clear_inventory":
			for item in player.action_bar.items.duplicate():
				if not item.is_empty():
					player.action_bar.remove(item)
			player.inventory.clear()
			player._refresh_inventory_display()
			_print("Inventory emptied.", GOOD_COLOR)
		"save":
			_save()
		"load":
			_load()
		"icons":
			_icons(args)
		_:
			_error("Unknown command '%s'. Type help for the list." % command)


func _icons(args: PackedStringArray) -> void:
	if not IconUpdater.available():
		_error("Icons can only be redrawn in a debug run from the project.")
		return
	var all := not args.is_empty() and args[0].to_lower() == "all"
	var updater := IconUpdater.new()
	add_child(updater)
	_print("Redrawing %s build icons..." % ("all the" if all else "changed"), DIM_COLOR)
	var count: int = await updater.update(all)
	updater.queue_free()
	_print("Redrew %d icon(s). Reopen the build menu to see them." % count, GOOD_COLOR)


func _give(args: PackedStringArray) -> void:
	if args.is_empty():
		_usage("give")
		return
	var amount := 1
	var name_words := args
	if args.size() > 1 and args[-1].is_valid_int():
		amount = int(args[-1])
		name_words = args.slice(0, args.size() - 1)
	elif args.size() == 1 and args[0].is_valid_int():
		_usage("give")
		return
	if amount < 1:
		_error("The amount must be at least 1.")
		_usage("give")
		return
	var item := find_item(" ".join(name_words))
	if item.is_empty():
		_error("Unknown item '%s'. Tab lists items that start with what you've typed." % " ".join(name_words))
		return
	player.add_item(item, amount)
	_print("Gave %d %s." % [amount, item], GOOD_COLOR)


func _give_all(args: PackedStringArray) -> void:
	var amount := 100
	if args.size() > 1 or (args.size() == 1 and (not args[0].is_valid_int() or int(args[0]) < 1)):
		_usage("give_all")
		return
	if args.size() == 1:
		amount = int(args[0])
	var given: PackedStringArray = []
	for item in resource_items():
		player.inventory[item] = int(player.inventory.get(item, 0)) + amount
		given.append(item)
	player._refresh_inventory_display()
	_print("Gave %d each of %s." % [amount, ", ".join(given)], GOOD_COLOR)


func _unlock_all() -> void:
	var count := 0
	for blueprint in player._all_blueprints():
		if blueprint.starts_locked and not player._unlocked.has(blueprint):
			player._unlocked[blueprint] = true
			count += 1
	player._refresh_inventory_display()
	_print("Unlocked %d blueprints, recipes and plot types (templates unlock with their plot types)." % count, GOOD_COLOR)


func _time(args: PackedStringArray) -> void:
	if args.size() != 1 or not args[0].is_valid_float():
		_usage("time")
		return
	var hours := float(args[0])
	if hours < 0.0 or hours > 24.0:
		_error("The time must be from 0 to 24.")
		_usage("time")
		return
	var sun = get_tree().get_first_node_in_group("sun")
	if sun == null:
		_error("There's no sun to set.")
		return
	sun.time_of_day = fmod(hours / 24.0, 1.0)
	_print("Time set to %02d:%02d." % [int(hours) % 24, int(fmod(hours, 1.0) * 60.0)], GOOD_COLOR)


func _spawn_settlers(args: PackedStringArray) -> void:
	var count := 1
	if args.size() > 1 or (args.size() == 1 and (not args[0].is_valid_int() or int(args[0]) < 1 or int(args[0]) > 30)):
		_usage("spawn_settler")
		_error("The count must be from 1 to 30.")
		return
	if args.size() == 1:
		count = int(args[0])
	var names: PackedStringArray = []
	for i in count:
		var settler: Settler = player._settlers.spawn_debug(player, (i - (count - 1) / 2.0) * 0.9)
		names.append("%s (%s)" % [settler.settler_name, "home: " + player._placer.plots.find(settler.home_id).plot_name if not settler.home_id.is_empty() else "no home"])
	_print("Brought %s." % ", ".join(names), GOOD_COLOR)


func _teleport(args: PackedStringArray) -> void:
	var spot := Vector3.ZERO
	if args.size() == 1 and args[0].to_lower() == "settlement":
		var nearest: Plot = null
		for plot in player._placer.plots.all_plots():
			if nearest == null or plot.global_position.distance_to(player.global_position) < nearest.global_position.distance_to(player.global_position):
				nearest = plot
		if nearest == null:
			_error("There are no plots to go to yet.")
			return
		spot = nearest.global_position
		_print("To %s." % nearest.plot_name, GOOD_COLOR)
	elif args.size() == 2 and args[0].is_valid_float() and args[1].is_valid_float():
		spot = Vector3(float(args[0]), 0.0, float(args[1]))
	else:
		_usage("tp")
		return
	spot.y = Plot.ground_at(player, spot.x, spot.z)
	player.global_position = spot + Vector3.UP * (player._half_height + 0.3)
	player.velocity = Vector3.ZERO
	_print("Now at %.1f, %.1f (ground %.1f m)." % [spot.x, spot.z, spot.y], GOOD_COLOR)


func _save() -> void:
	if not SaveGame.can_save():
		_error("Can't save in a test run (the world was started straight from the editor, so nothing is ever saved).")
		return
	SaveGame.save_manual("")
	_print("Saved (a manual save).", GOOD_COLOR)


func _load() -> void:
	var world := SaveGame.current_world()
	if world.is_empty():
		_error("No saves to load in a test run (started straight from the editor).")
		return
	var saves := SaveGame.saves_in(world)
	if saves.is_empty():
		_error("This world has no saves yet.")
		return
	_print("Loading %s..." % saves[0]["name"], GOOD_COLOR)
	close()
	SaveGame.load_save(saves[0]["path"])


func _toggled(name: String, on: bool) -> void:
	_print("%s %s" % [name, "ON" if on else "off"], GOOD_COLOR if on else DIM_COLOR)


func _usage(command: String) -> void:
	_error("Usage: " + COMMANDS[command][0])


# ---- Items ----

## Every item name the game knows: anything with a picture or placeholder colour, anything a
## recipe makes, and anything a buildable or recipe costs
func known_items() -> PackedStringArray:
	var found := {}
	for item in InventorySlot.ITEM_ICONS:
		found[item] = true
	for item in InventorySlot.ITEM_COLORS:
		found[item] = true
	for recipe in player.inventory_screen.crafting.all_recipes():
		found[recipe.result] = true
		for item in recipe.costs:
			found[item] = true
	for buildable in player.build_menu.all_buildables():
		for cost in buildable.costs:
			for item in cost:
				found[item] = true
	var names := PackedStringArray(found.keys())
	names.sort()
	return names


## The known items that aren't tools (materials, food, ores)
func resource_items() -> PackedStringArray:
	var found: PackedStringArray = []
	for item in known_items():
		if not ToolItem.exists_for(item):
			found.append(item)
	return found


## The item a typed name means ("plant fiber", "plant_fiber", "Plant Fiber"), or empty
func find_item(typed: String) -> String:
	var wanted := _plain(typed)
	for item in known_items():
		if _plain(item) == wanted:
			return item
	return ""


# An item name as typed in the console: "plant_fiber"
static func _typed_form(item: String) -> String:
	return item.to_lower().replace(" ", "_")


static func _plain(text: String) -> String:
	return text.strip_edges().to_lower().replace("_", " ")


# ---- Tab completion ----

func _complete() -> void:
	var text := _entry.text
	var words := text.split(" ", true)
	var options: PackedStringArray = []
	var typed := ""
	if words.size() <= 1:
		typed = words[0] if not words.is_empty() else ""
		for name in COMMANDS:
			if name.begins_with(typed.to_lower()):
				options.append(name)
	elif words[0].to_lower() == "give" and words.size() == 2:
		typed = words[1]
		for item in known_items():
			if _typed_form(item).begins_with(typed.to_lower()):
				options.append(_typed_form(item))
	elif words[0].to_lower() == "tp" and words.size() == 2:
		typed = words[1]
		if "settlement".begins_with(typed.to_lower()):
			options.append("settlement")
	else:
		return
	if options.is_empty():
		return
	var head := " ".join(words.slice(0, words.size() - 1))
	head = head + " " if not head.is_empty() else ""
	if options.size() == 1:
		_entry.text = head + options[0] + " "
	else:
		_print("  " + "   ".join(options), DIM_COLOR)
		_entry.text = head + _common_start(options)
	_entry.caret_column = _entry.text.length()


static func _common_start(options: PackedStringArray) -> String:
	var start := options[0]
	for option in options:
		while not option.begins_with(start):
			start = start.left(start.length() - 1)
	return start


# ---- The log ----

func _print(text: String, color := "") -> void:
	if color.is_empty():
		_log.append_text(text + "\n")
	else:
		_log.append_text("[color=#%s]%s[/color]\n" % [color, text])


func _error(text: String) -> void:
	_print(text, ERROR_COLOR)
