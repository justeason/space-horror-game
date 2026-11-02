extends StaticBody3D
## Round 21 Priority 4: the physical OLD/dirty filter cartridge ejected
## from the Life Support filter housing once a replacement is actually
## removed -- the "used filter/used part is not just magically deleted"
## requirement. There is no used cartridge in the world until a real
## repair produces one: this node starts hidden and non-collidable,
## and filter_housing_station.gd's own remove_old_cartridge() calls
## eject_at() the moment the old cartridge physically comes out,
## placing it at a real, visible, carryable position (on the floor
## near the housing) rather than silently discarding it.
##
## Duck-typed contracts satisfied: `interact()`
## (interaction_controller.gd), `item_id` + `return_to_rest()`
## (scripts/player/carry_system.gd) -- same convention as
## filter_cartridge.gd, its clean-cartridge sibling. Unlike that
## sibling, this item has no fixed "Storage shelf" resting spot (it did
## not come FROM storage), so a plain drop (return_to_rest()) simply
## leaves it exactly where it was let go, not snapped back anywhere.
## It is only ever actually removed from the game once thrown into the
## Storage disposal container -- see trash_disposal.gd's dispose_item()
## and this script's own dispose().

@export var carry_system_path: NodePath
@export var item_id: StringName = &"used_filter_cartridge"
@export var message_label_path: NodePath
@export var message_duration: float = 1.5

@onready var _carry_system: Node = get_node(carry_system_path)
@onready var _message_label: Label = get_node_or_null(message_label_path)
@onready var _collision: CollisionShape3D = $Collision

var _message_timer: float = 0.0
var _resting_parent: Node
var _ejected: bool = false


func _ready() -> void:
	_resting_parent = get_parent()
	visible = false
	_collision.disabled = true


func _process(delta: float) -> void:
	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0 and _message_label != null:
			_message_label.visible = false


## Called once by filter_housing_station.gd the moment the old
## cartridge actually comes out of the housing -- makes this a real,
## visible, collidable object at the given world transform. Idempotent:
## a second call is a harmless no-op, matching the station's own stage
## machine already preventing "remove the old cartridge" from running
## twice in one repair.
func eject_at(world_transform: Transform3D) -> void:
	if _ejected:
		return
	_ejected = true
	visible = true
	_collision.disabled = false
	global_transform = world_transform


func is_ejected() -> bool:
	return _ejected


func interact() -> void:
	if not _ejected:
		return
	if _carry_system.is_carrying():
		return
	if _carry_system.pick_up(self):
		_show_message("Picked up: Used Filter Cartridge. Dispose of it in Storage.")


func get_interact_prompt() -> String:
	if not _ejected or _carry_system.is_carrying():
		return ""
	return "Click: Pick Up Used Filter Cartridge"


func _show_message(text: String) -> void:
	if _message_label == null:
		return
	_message_label.text = text
	_message_label.visible = true
	_message_timer = message_duration


## Plain drop (carry_system.gd's drop(), e.g. forced by sitting down
## with it held): keeps the item's CURRENT world position -- unlike
## filter_cartridge.gd's own return_to_rest(), there is no fixed home
## to snap back to.
func return_to_rest() -> void:
	reparent(_resting_parent, true)


func place_in_world(world_transform: Transform3D) -> void:
	reparent(_resting_parent, false)
	global_transform = world_transform


func get_display_name() -> String:
	return "Used Filter Cartridge"


## Called by trash_disposal.gd once actually thrown away -- the one
## place this object is ever removed from the game, and only reachable
## after it has been ejected, picked up, and carried to the disposal
## point for real.
func dispose() -> void:
	queue_free()
