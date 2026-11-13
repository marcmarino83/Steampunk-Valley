class_name ContainerSession
extends Node
## What's open beside the inventory, if anything: a chest, or town storage (see TownStorage), and the
## thing in the world it was opened at (the chest itself, or the Storehouse Storage), which closes it
## when you walk away. Moves whole stacks between the backpack and it, and deposits every material
## and food into town storage. A child of the player (see player.gd, which forwards open_chest and
## open_town_storage here).
##
## It never opens or closes the inventory itself: it asks (`open_requested`, `walked_away`), and
## messages for the player go out as `message`.

## Something was opened while the inventory is closed: the inventory should open
signal open_requested
## You walked away from what's open (or town storage lost its last working Storehouse): close it
## (closing the inventory closes it too)
signal walked_away
## A short message for the player ("The chest is full")
signal message(text: String)

## An open chest closes once you're this far from it, in meters
const CHEST_RANGE := 4.0

## Where you stand (the player), what you own, the inventory screen (its chest panel) and the action
## bar (what's on it is never deposited). Set by the player.
var body: Node3D
var inventory: PlayerInventory
var inventory_screen: Control
var action_bar: ActionBar

# What's open (a chest or town storage), and what it was opened at
var _open: Node
var _near: Node3D


## Opens a container (a chest, or town storage) beside the inventory, opened at `near`
func open(container: Node, near: Node3D) -> void:
	close()
	_open = container
	_near = near
	if not inventory_screen.visible:
		open_requested.emit()
	show_contents()
	# A day's output going in, or a settler eating from it, shows while it's open
	if container.has_signal("changed") and not container.changed.is_connected(_on_changed):
		container.changed.connect(_on_changed)


## True while something is open (and still there)
func is_open() -> bool:
	return _open != null and is_instance_valid(_open)


## Brings the open chest's (or town storage's) panel up to date
func show_contents() -> void:
	if _open is TownStorage:
		var town := _open as TownStorage
		inventory_screen.show_town_storage(town.sorted_contents(), town.capacity(), town.category_totals())
	else:
		inventory_screen.show_chest(_open.contents)


## Brings the open panel up to date, if something's open (after the backpack changed)
func refresh() -> void:
	if is_open():
		show_contents()


func _on_changed() -> void:
	if is_open() and inventory_screen.visible:
		show_contents()


## Closes whatever's open (its panel too)
func close() -> void:
	if is_open() and _open.has_signal("changed") and _open.changed.is_connected(_on_changed):
		_open.changed.disconnect(_on_changed)
	_open = null
	_near = null
	inventory_screen.hide_chest()


## Each frame: says `walked_away` once you're out of reach of what's open, or town storage has no
## working Storehouse left
func follow() -> void:
	if _open and (not is_instance_valid(_open) or not is_instance_valid(_near) \
			or body.global_position.distance_to(_near.global_position) > CHEST_RANGE \
			or (_open is TownStorage and not (_open as TownStorage).is_open())):
		walked_away.emit()


## A whole stack moving between the backpack and the open chest (or town storage), if there's room
func move_item(item: String, from: String) -> void:
	if not is_open():
		return
	if from == "chest":
		if inventory.backpack_contents().size() >= inventory.backpack_slots() and not inventory.items.has(item):
			message.emit("Inventory full")
			return
		inventory.add(item, _open.take_all(item))
	else:
		if not _open.can_take(item):
			message.emit("Town storage is full" if _open is TownStorage else "The chest is full")
			return
		var amount: int = inventory.items.get(item, 0)
		if inventory.remove(item, amount):
			_open.put(item, amount)
	if _open is TownStorage:
		_open.changed.emit()
	inventory.notify()


## Deposit resources: every material and food in the backpack goes into town storage (as much as
## there's room for); tools and whatever's on the action bar stay
func deposit() -> void:
	if not _open is TownStorage:
		return
	var town := _open as TownStorage
	var moved := 0
	var no_room: PackedStringArray = []
	for item in inventory.items.keys():
		if action_bar.has_item(item) or not ["Food", "Materials"].has(TownStorage.category_of(item)):
			continue
		if not town.can_take(item):
			no_room.append(item)
			continue
		var amount: int = inventory.items[item]
		inventory.items.erase(item)
		town.put(item, amount)
		moved += amount
	town.changed.emit()
	inventory.notify()
	if moved == 0 and no_room.is_empty():
		message.emit("No materials or food to deposit")
	elif no_room.is_empty():
		message.emit("Deposited %d items in town storage" % moved)
	else:
		message.emit("Deposited %d items; town storage is full (%s stayed with you)" % [moved, ", ".join(no_room)])
