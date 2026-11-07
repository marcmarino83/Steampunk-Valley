class_name Campfire
extends StaticBody3D
## A campfire. It's built already laid with some fuel but unlit. Light it with a handful of
## plant fiber as tinder, then keep it going by feeding it: sticks burn quickly, wood lasts
## longer, and coal lasts longest and burns hottest, warming you from further away.

## Seconds of fuel the fire is built with, ready to light
@export var starting_fuel := 120.0
## Seconds each piece of fuel adds
@export var stick_burn := 20.0
@export var wood_burn := 75.0
@export var coal_burn := 150.0
## The most fuel the fire can hold at once, in seconds
@export var max_fuel := 600.0
## How close you need to be to feel the heat, normally and while coal is burning
@export var warmth_radius := 6.0
@export var coal_warmth_radius := 10.0

## Fuel, in the order E reaches for it: wood first, then sticks, and coal last,
## since it's precious once the forge needs it
const FUELS := [["Wood", "wood_burn"], ["Sticks", "stick_burn"], ["Coal", "coal_burn"]]

@onready var flame: Node3D = $Flame
@onready var light: OmniLight3D = $Light

## Seconds of burning left in the fire (lit or not)
var fuel := 0.0
## True once it's been lit, until the fuel runs out
var lit := false
# Seconds of that fuel that's coal, burning hot
var _coal_left := 0.0


func _ready() -> void:
	add_to_group("campfires")
	fuel = starting_fuel


func is_lit() -> bool:
	return lit


## How close you need to be to feel the heat right now
func heat_radius() -> float:
	return coal_warmth_radius if _coal_left > 0.0 else warmth_radius


func can_interact() -> bool:
	return true


func get_prompt() -> String:
	if lit:
		var piece := _next_fuel(null)
		var line := "Add fuel (Wood, Sticks or Coal)" if piece.is_empty() else "Add %s (+%s)" % [piece[0], _clock(get(piece[1]))]
		return "%s\nBurning%s: %s" % [line, " hot" if _coal_left > 0.0 else "", _clock(fuel)]
	if fuel <= 0.0:
		return "Add fuel (Wood, Sticks or Coal)"
	return "Light fire (1 Plant Fiber)"


func interact(player) -> void:
	# A laid but unlit fire: light it with tinder
	if not lit and fuel > 0.0:
		if player.remove_item("Plant Fiber", 1):
			lit = true
		else:
			player.flash("You need Plant Fiber to light the fire")
		return

	# Otherwise, feed it
	var piece := _next_fuel(player)
	if piece.is_empty():
		player.flash("You have nothing to burn. Sticks, Wood or Coal will do")
		return
	var seconds: float = get(piece[1])
	if fuel + seconds > max_fuel:
		player.flash("The fire can't take any more yet")
		return
	player.remove_item(piece[0], 1)
	fuel += seconds
	if piece[0] == "Coal":
		_coal_left += seconds


# Which fuel E would use: the first one in FUELS that the player is carrying.
# With no player given, it asks the player currently looking at the fire.
func _next_fuel(player) -> Array:
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	if player == null:
		return []
	for piece in FUELS:
		if player.inventory.get(piece[0], 0) > 0:
			return piece
	return []


# 150 seconds -> "2:30"
func _clock(seconds: float) -> String:
	var whole := ceili(seconds)
	@warning_ignore("integer_division")
	var minutes := whole / 60
	return "%d:%02d" % [minutes, whole % 60]


func _process(delta: float) -> void:
	if lit:
		fuel = maxf(fuel - delta, 0.0)
		_coal_left = minf(maxf(_coal_left - delta, 0.0), fuel)
		if fuel <= 0.0:
			lit = false
	flame.visible = lit
	light.visible = lit

	if lit:
		# Flicker: two wobbles at different speeds so it never looks regular.
		# Coal burns bigger and brighter, and lights up further.
		var hot := _coal_left > 0.0
		var t := Time.get_ticks_msec() * 0.001
		var flicker := sin(t * 13.0) * 0.5 + sin(t * 7.3) * 0.5
		light.light_energy = (3.2 if hot else 2.0) + flicker * 0.4
		light.omni_range = 13.0 if hot else 9.0
		var size := 1.35 if hot else 1.0
		flame.scale = Vector3(size, size * (1.0 + flicker * 0.12), size)
