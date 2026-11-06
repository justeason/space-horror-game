extends StaticBody3D
## Round 20 Priority 4: the physical replacement filter cartridge for
## L02 Filter Replacement -- normally resting in its own Storage
## compartment (StorageCabinet2), picked up via the same Space pickup/
## drop carry system every other carryable component in this project
## uses (wire_component.gd is the closest sibling; this is a simpler
## version with no fault-color variant, since the filter task has no
## per-attempt color/role randomization).
##
## Duck-typed contracts satisfied: `interact()`
## (interaction_controller.gd), `item_id` + `return_to_rest()`
## (scripts/player/carry_system.gd).

@export var carry_system_path: NodePath
@export var item_id: StringName = &"filter_cartridge"
@export var message_label_path: NodePath
@export var message_duration: float = 1.5

@onready var _carry_system: Node = get_node(carry_system_path)
@onready var _message_label: Label = get_node_or_null(message_label_path)

var _resting_parent: Node
var _resting_transform: Transform3D
var _message_timer: float = 0.0
## Set once by mark_installed() -- a permanently-installed cartridge is
## no longer a loose pickup, same contract as wire_component.gd's own
## _installed flag.
var _installed: bool = false


func _ready() -> void:
	_resting_parent = get_parent()
	_resting_transform = transform


func _process(delta: float) -> void:
	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0 and _message_label != null:
			if _message_label.get_meta(&"msg_owner", 0) == get_instance_id():   # shared HUD label: hide only our own message
				_message_label.visible = false


func interact() -> void:
	if _installed:
		return
	if _carry_system.is_carrying():
		return
	if _carry_system.pick_up(self):
		_show_message("Picked up: Replacement Filter Cartridge.")


func get_interact_prompt() -> String:
	if _installed:
		return ""
	if _carry_system.is_carrying():
		return ""
	return "Click: Pick Up Filter Cartridge"


func is_installed() -> bool:
	return _installed


func _show_message(text: String) -> void:
	if _message_label == null:
		return
	_message_label.text = text
	_message_label.set_meta(&"msg_owner", get_instance_id())
	_message_label.visible = true
	_message_timer = message_duration


## Called by carry_system.gd's drop() -- puts this cartridge back
## exactly where it started, parented back under its Storage shelf.
## Round 31: a storage cabinet (or the reserve crate) assigning this part
## a new home slot -- where return_to_rest() puts it from now on.
func set_rest_global(global_xf: Transform3D, parent: Node = null) -> void:
	if parent != null:
		_resting_parent = parent
	var p3: Node3D = _resting_parent as Node3D
	_resting_transform = p3.global_transform.affine_inverse() * global_xf if p3 != null else global_xf


func return_to_rest() -> void:
	reparent(_resting_parent, false)
	transform = _resting_transform


## Called by carry_system.gd's Space drop action: places this cartridge
## at an arbitrary world position/orientation (e.g. on the floor near
## the player) rather than snapping back to its Storage resting spot.
func place_in_world(world_transform: Transform3D) -> void:
	reparent(_resting_parent, false)
	global_transform = world_transform


func get_display_name() -> String:
	return "Filter Cartridge"


## Called once by filter_housing_station.gd once the new cartridge is
## successfully seated -- reparents under the housing at a fixed local
## pose and disables collision, same "stays a real, addressable object,
## just no longer a loose pickup" contract as wire_component.gd's own
## mark_installed().
##
## Round 24 Priority 2 ROOT-CAUSE FIX for the "floating decorative
## duplicate cartridge": this used to leave the cartridge VISIBLE at
## whatever local pose the station passed in -- which was a hard-coded
## Vector3(0, -0.6, 0), i.e. 0.6m straight BELOW the station anchor, out
## in open air in front of the Life Support wall, nowhere near the
## housing. Confirmed by render (it hung there under the housing panel)
## and by enumerating every visible cylinder near the station. Now:
## the station passes a pose INSIDE its own housing tube, and the
## cartridge goes invisible on seating -- exactly the contract
## wire_component.gd's own mark_installed() already uses: a seated part
## is enclosed by the housing, and the housing (latches, valve, gauge)
## is the one visible representation of "installed".
func mark_installed(parent_node: Node, local_transform: Transform3D) -> void:
	if _installed:
		return
	_installed = true
	reparent(parent_node, false)
	transform = local_transform
	visible = false
	var collision := get_node_or_null("Collision")
	if collision != null:
		collision.disabled = true
	if _message_label != null:
		_message_timer = 0.0
		if _message_label.get_meta(&"msg_owner", 0) == get_instance_id():   # shared HUD label: hide only our own message
			_message_label.visible = false
