class_name BlueprintPopup
extends Label
## The "New blueprint" pop-up near the top of the screen: what's just been unlocked (see
## Progress.learned), shown for POPUP_TIME, then faded out. A few are named one per line; many at
## once (the first planks unlock every building piece) are summed up, so they don't fill the screen.

## How long it stays up before fading, in seconds, and how many names it lists before summing up
const POPUP_TIME := 3.0
const POPUP_LINES := 3

var _tween: Tween


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 96)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_theme_font_size_override("font_size", 26)
	add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 7)
	modulate.a = 0.0


## Shows these newly unlocked blueprints (their names)
func show_learned(names: PackedStringArray) -> void:
	if names.size() <= POPUP_LINES:
		text = "\n".join(Array(names).map(func(n): return "New blueprint: %s" % n))
	else:
		text = "%d new blueprints: %s and more\nSee the build menu [Tab]" % [names.size(), ", ".join(names.slice(0, 2))]
	if _tween:
		_tween.kill()
	modulate.a = 1.0
	_tween = create_tween()
	_tween.tween_interval(POPUP_TIME)
	_tween.tween_property(self, "modulate:a", 0.0, 0.6)
