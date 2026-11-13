class_name SleepFade
extends ColorRect
## The black screen sleep fades through (see Survival.sleep): over the whole screen, above the HUD
## and every menu, letting clicks through, clear until it plays.


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	color = Color.BLACK
	modulate.a = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Fades to black over `fade` seconds, calls `at_dark`, stays dark `dark` seconds, fades back over
## `fade` seconds, then calls `at_end`
func play(fade: float, dark: float, at_dark: Callable, at_end: Callable) -> void:
	var night := create_tween()
	night.tween_property(self, "modulate:a", 1.0, fade)
	night.tween_callback(at_dark)
	night.tween_interval(dark)
	night.tween_property(self, "modulate:a", 0.0, fade)
	night.tween_callback(at_end)
