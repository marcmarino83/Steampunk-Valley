class_name Campfire
extends StaticBody3D

## How long one lump of coal keeps the fire going, in seconds
@export var burn_time_per_coal := 60.0
## The most fuel the fire can hold at once, in seconds
@export var max_fuel := 300.0
## How close you need to be to feel the heat
@export var warmth_radius := 6.0

@onready var flame: Node3D = $Flame
@onready var light: OmniLight3D = $Light

## Seconds of burning left
var fuel := 0.0


func _ready() -> void:
	add_to_group("campfires")


func is_lit() -> bool:
	return fuel > 0.0


func can_interact() -> bool:
	return true


func get_prompt() -> String:
	if is_lit():
		return "Add Coal (%ds left)" % ceili(fuel)
	return "Light with Coal"


func interact(player) -> void:
	if fuel + burn_time_per_coal > max_fuel:
		player.flash("The fire can't take any more coal yet")
	elif player.remove_item("Coal", 1):
		fuel += burn_time_per_coal
	else:
		player.flash("You need Coal to fuel the fire")


func _process(delta: float) -> void:
	fuel = maxf(fuel - delta, 0.0)
	flame.visible = is_lit()
	light.visible = is_lit()

	if is_lit():
		# Flicker: two wobbles at different speeds so it never looks regular
		var t := Time.get_ticks_msec() * 0.001
		var flicker := sin(t * 13.0) * 0.5 + sin(t * 7.3) * 0.5
		light.light_energy = 2.0 + flicker * 0.4
		flame.scale = Vector3(1.0, 1.0 + flicker * 0.12, 1.0)
