extends Node
## The dowsing rod's pulse. The player only creates this while IronTier.ENABLED is true.

## How far a dowsing pulse reaches, how long what it finds stays revealed (seconds),
## and how long before the rod can be used again (seconds)
const DOWSING_RANGE = 30.0
const DOWSING_REVEAL = 60.0
const DOWSING_COOLDOWN = 2.0

# Seconds until the dowsing rod can pulse again
var _wait := 0.0
var _player: CharacterBody3D


func _ready() -> void:
	_player = get_parent()


func _process(delta: float) -> void:
	_wait = maxf(_wait - delta, 0.0)


## Sends out a pulse from the dowsing rod. Every hidden deposit within range shows itself
## for a while: a dig spot on the ground with a faint marker floating above it.
func pulse() -> void:
	if _player.held_item != "Dowsing Rod":
		if _player.inventory.has("Dowsing Rod"):
			_player.flash("Equip the dowsing rod to search for buried ore")
		return
	if _wait > 0.0:
		return
	_wait = DOWSING_COOLDOWN
	var found := 0
	for deposit in get_tree().get_nodes_in_group("hidden_deposits"):
		if deposit.gathers_left > 0 and _player.global_position.distance_to(deposit.global_position) <= DOWSING_RANGE:
			deposit.reveal(DOWSING_REVEAL)
			found += 1
	_show_ring()
	if found == 0:
		_player.flash("The rod stays still. Nothing buried nearby")
	elif found == 1:
		_player.flash("The rod tugs. Something is buried nearby")
	else:
		_player.flash("The rod tugs hard. %d deposits buried nearby" % found)


# A faint golden ring that sweeps out across the ground from your feet
func _show_ring() -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 0.96
	ring.outer_radius = 1.0
	ring.rings = 64
	ring.ring_segments = 4
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.albedo_color = Color(2.0, 1.6, 0.6, 0.6)
	ring.material = glow
	var sweep_mesh := MeshInstance3D.new()
	sweep_mesh.mesh = ring
	sweep_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_player.get_parent().add_child(sweep_mesh)
	sweep_mesh.global_position = _player.global_position + Vector3.DOWN * 0.8
	var sweep := sweep_mesh.create_tween().set_parallel()
	sweep.tween_property(sweep_mesh, "scale", Vector3(DOWSING_RANGE, 1.0, DOWSING_RANGE), 1.2).from(Vector3.ONE)
	sweep.tween_property(glow, "albedo_color:a", 0.0, 1.2)
	sweep.chain().tween_callback(sweep_mesh.queue_free)
