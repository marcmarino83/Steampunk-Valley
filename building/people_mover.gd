class_name PeopleMover
extends RefCounted
## Nobody standing in the way stops building: a piece, furniture item, workbench, chest or campfire,
## a ghost being built, or a moved plot's pieces go down anyway, and you or a settler standing where
## one lands glides to the nearest open spot beside it.
##
## The nearest open spot: rings round where the person stands, STEP apart out to MAX_REACH, 16
## directions each, the first where a person-sized capsule fits standing on whatever is below (the
## ground, a floor, a foundation; no more than MAX_DROP up or down from where they were), touching
## nothing solid but the ground.

## The physics layers people are on: the player (1) and settlers (Settler.LAYER)
const PERSON_LAYERS := 1 | 4
## A person's size, for the room they need
const RADIUS := 0.4
const HEIGHT := 1.8
const STEP := 0.4
const MAX_REACH := 8.0
const MAX_DROP := 2.0
## How long the glide aside takes, in seconds
const GLIDE := 0.25
const MAX_OVERLAPS := 16


## After `things` are in the world (pieces, furniture, buildings), anyone standing inside one glides
## aside. Waits two physics frames first, so their collision is in place (and counts when looking
## for room).
static func clear_from(things: Array) -> void:
	var solid := things.filter(func(t): return is_instance_valid(t) and t is Node3D and (t as Node3D).is_inside_tree() and not (t is BuildPiece and t.is_ghost()))
	if solid.is_empty():
		return
	var tree := (solid[0] as Node).get_tree()
	for i in 2:
		await tree.physics_frame
	# What was just put down: looking for room, the ground under it doesn't count as somewhere to
	# stand (beside it, not on top of it)
	var put_down: Array[RID] = []
	for thing in solid:
		if is_instance_valid(thing) and thing is CollisionObject3D:
			put_down.append((thing as CollisionObject3D).get_rid())
		if is_instance_valid(thing):
			for body in (thing as Node).find_children("*", "CollisionObject3D", true, false):
				put_down.append((body as CollisionObject3D).get_rid())
	var moved := {}
	for thing in solid:
		if not is_instance_valid(thing):
			continue
		for person in _people_in(thing):
			if not moved.has(person):
				moved[person] = true
				_move_aside(person, put_down)


# You or settlers inside something's solid shapes
static func _people_in(thing: Node3D) -> Array:
	var found: Array = []
	var space := thing.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = PERSON_LAYERS
	for node in [thing] + thing.find_children("*", "CollisionShape3D", true, false):
		var holder := node as CollisionShape3D
		if holder == null or holder.shape == null or holder.disabled:
			continue
		query.shape = holder.shape
		query.transform = holder.global_transform
		for hit in space.intersect_shape(query, MAX_OVERLAPS):
			var other: Object = hit["collider"]
			if (other is Settler or (other is Node and (other as Node).is_in_group("player"))) and not found.has(other):
				found.append(other)
	return found


# Glides a person to the nearest open spot (see the top), if there's one in reach
static func _move_aside(person: Node3D, put_down: Array[RID]) -> void:
	var spot = nearest_open_spot(person, put_down)
	if spot == null:
		return
	var glide := person.create_tween()
	glide.tween_property(person, "global_position", spot, GLIDE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Where a person (their feet) could stand nearest where they are now, out of everything solid, or
## null if there's nowhere within MAX_REACH. `not_on` is what they may not be stood on top of (what
## was just put down where they were): the look down for somewhere to stand passes through it, and
## the room check still counts it, so they end up beside it.
static func nearest_open_spot(person: Node3D, not_on: Array[RID] = []):
	var space := person.get_world_3d().direct_space_state
	var from := person.global_position
	var skip: Array[RID] = []
	if person is CollisionObject3D:
		skip.append((person as CollisionObject3D).get_rid())
	var look_through: Array[RID] = skip.duplicate()
	look_through.append_array(not_on)
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	var room := PhysicsShapeQueryParameters3D.new()
	room.shape = capsule
	room.exclude = skip
	var rings := int(MAX_REACH / STEP)
	for r in range(1, rings + 1):
		for k in 16:
			var dir := Vector3(cos(k * TAU / 16.0), 0.0, sin(k * TAU / 16.0))
			var at := from + dir * (r * STEP)
			var down := PhysicsRayQueryParameters3D.create(at + Vector3.UP * (MAX_DROP + 0.5), at + Vector3.DOWN * (MAX_DROP + 0.5))
			down.exclude = look_through
			var below := space.intersect_ray(down)
			if below.is_empty():
				continue
			var feet: Vector3 = below["position"]
			if absf(feet.y - from.y) > MAX_DROP:
				continue
			room.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * (HEIGHT / 2.0 + 0.05))
			var clear := true
			for hit in space.intersect_shape(room, MAX_OVERLAPS):
				var other: Object = hit["collider"]
				if not (other is Node and (other as Node).is_in_group("terrain_ground")):
					clear = false
					break
			if clear:
				return feet + Vector3.UP * 0.02
	return null
