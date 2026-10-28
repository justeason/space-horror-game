extends Node
## Minimal one-item carrying system (Approved Decision A.10 /
## GAME_DESIGN.md Section 19: "pick up / carry / place / drop /
## return" -- one item at a time, no slots, no weight, no stacking).
##
## A carryable item is any Node3D with an `item_id: StringName`
## property and a `return_to_rest()` method -- the same duck-typed
## contract convention interaction_controller.gd already uses for
## `interact()` (see wire_component.gd for the first real
## implementation).

@export var carry_anchor_path: NodePath
@export var held_local_position: Vector3 = Vector3(0.22, -0.35, -0.4)
@export var held_local_rotation_degrees: Vector3 = Vector3(0, 0, 0)

## For the Space pickup/drop action below.
@export var player_path: NodePath
@export var interaction_controller_path: NodePath
## How far in front of the player (horizontally) to try placing a
## dropped item.
@export var drop_forward_distance: float = 0.7
## If the nearest floor found below the drop point is farther from the
## player's current floor than this, treat it as "no safe floor here"
## (e.g. the edge of a pit) rather than dropping the item down into it.
@export var drop_max_floor_drop: float = 1.0
## Radius of the clearance check at the candidate landing spot (catches
## "that point is inside a wall/prop", not just "is there a floor").
@export var drop_clearance_radius: float = 0.12

@onready var _carry_anchor: Node3D = get_node(carry_anchor_path)
@onready var _player: Node3D = get_node_or_null(player_path)
@onready var _interaction_controller: Node = get_node_or_null(interaction_controller_path)
@onready var _message_label: Label = get_node_or_null("../HUD/TaskMessageLabel")

var _carried_item: Node3D = null
var _carried_item_id: StringName = &""
var _message_timer: float = 0.0


func is_carrying() -> bool:
	return _carried_item != null


func carried_item_id() -> StringName:
	return _carried_item_id


## Display name of whatever is currently carried, for the contextual
## drop prompt (e.g. "Space: Drop Wire Component"). "" if not carrying.
func carried_item_display_name() -> String:
	if _carried_item == null:
		return ""
	if _carried_item.has_method("get_display_name"):
		return _carried_item.get_display_name()
	return "Item"


## False if the player's hands are already full -- §19 is strict about
## one item at a time, so a second pickup attempt is simply ignored,
## not queued or swapped.
func pick_up(item: Node3D) -> bool:
	if _carried_item != null:
		return false
	_carried_item = item
	_carried_item_id = item.item_id
	item.reparent(_carry_anchor, true)
	item.position = held_local_position
	item.rotation_degrees = held_local_rotation_degrees
	return true


## Puts the held item back in the world (its own return_to_rest()
## decides where -- normally its original resting spot). Distinct from
## consume_if_matches(): this is the plain "drop" verb from §19, not a
## task successfully using the item up. Kept as the programmatic
## "unconditionally let go of whatever is held" primitive; the Space
## player action below is a separate, safer wrapper
## (_attempt_drop_at_feet()) that places the item on the floor instead.
func drop() -> void:
	if _carried_item == null:
		return
	var item := _carried_item
	_carried_item = null
	_carried_item_id = &""
	item.return_to_rest()


func _process(delta: float) -> void:
	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0 and _message_label != null:
			_message_label.visible = false


## The player's unified Space pickup/drop action: empty-handed, Space
## picks up whatever interaction_controller.gd currently has hovered
## (if it's actually a carryable item -- the same duck-typed
## item_id/return_to_rest() contract this whole script already uses,
## checked via has_method() below); carrying something, Space drops it
## at the player's feet (Stage 5's existing placement geometry, a clear
## patch of floor a short distance in front of the player, rather than
## teleporting back to the original resting spot).
##
## Replaces the previous round's separate G-drop-only key: reusing
## interaction_controller.gd's OWN hover target (rather than this
## script deriving a second independent raycast) is what satisfies
## "prioritize the item the player is actually targeting" and "prevent
## pickup through walls" for free -- that raycast already stops at the
## first physical collider in the way, same as every other
## interactable in this project.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and event.keycode == KEY_SPACE):
		return
	# Same exclusive-state signal workstation_state.gd/sleep_state.gd
	# already drive (begin_use()/begin_sitting() set this false) -- see
	# interaction_controller.gd's class doc comment. Reusing it here is
	# what satisfies "cannot trigger while seated/editing/sleeping/a
	# focused minigame" without this script needing to know about every
	# exclusive state individually.
	if _interaction_controller != null and not _interaction_controller.interactions_enabled:
		return
	if _carried_item != null:
		_attempt_drop_at_feet()
		get_viewport().set_input_as_handled()
		return
	if _interaction_controller == null:
		return
	var hovered: Object = _interaction_controller.get_hovered()
	if hovered != null and hovered.has_method("return_to_rest"):
		hovered.interact()
		get_viewport().set_input_as_handled()
	# No valid item hovered: deliberately silent (no message spam for
	# every ordinary Space press while just walking/looking around) --
	# this project's own "do nothing, or subtle feedback" allowance.


func _attempt_drop_at_feet() -> void:
	if _player == null:
		_show_message("Can't drop that right now.")
		return

	var forward := Vector3(0, 0, -1)
	if _interaction_controller != null:
		var f: Vector3 = -_interaction_controller.global_transform.basis.z
		f.y = 0.0
		if f.length() > 0.01:
			forward = f.normalized()

	var eye_pos: Vector3 = _player.global_position
	var candidate_xz := Vector2(eye_pos.x + forward.x * drop_forward_distance, eye_pos.z + forward.z * drop_forward_distance)

	var space_state := _player.get_world_3d().direct_space_state
	var ray_start := Vector3(candidate_xz.x, eye_pos.y + 0.3, candidate_xz.y)
	var ray_end := Vector3(candidate_xz.x, eye_pos.y - 2.5, candidate_xz.y)
	var ray_params := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	var hit := space_state.intersect_ray(ray_params)

	if hit.is_empty():
		_show_message("No safe place to drop that here.")
		return

	var floor_y: float = (hit["position"] as Vector3).y
	if eye_pos.y - floor_y > drop_max_floor_drop + 1.6:
		# Found a "floor" implausibly far below the player's own eye
		# height for a normal standing floor (1.6 is the standard eye
		# height, so this means a floor more than drop_max_floor_drop
		# below the floor the player is actually standing on) -- almost
		# certainly a lower surface through a gap, not a safe spot.
		_show_message("No safe place to drop that here.")
		return

	var landing := Vector3(candidate_xz.x, floor_y + 0.03, candidate_xz.y)

	# Clearance check: the landing spot itself must not be inside a wall
	# or prop. A thin floor slab a few cm below this check point won't
	# trigger it (checked well above the floor's own thickness).
	var sphere := SphereShape3D.new()
	sphere.radius = drop_clearance_radius
	var clearance_params := PhysicsShapeQueryParameters3D.new()
	clearance_params.shape = sphere
	clearance_params.transform = Transform3D(Basis.IDENTITY, landing + Vector3(0, drop_clearance_radius + 0.02, 0))
	clearance_params.collide_with_bodies = true
	var obstruction := space_state.intersect_shape(clearance_params, 1)
	if not obstruction.is_empty():
		_show_message("No safe place to drop that here.")
		return

	var item := _carried_item
	_carried_item = null
	_carried_item_id = &""
	if item.has_method("place_in_world"):
		item.place_in_world(Transform3D(Basis.IDENTITY, landing))
	else:
		item.return_to_rest()


func _show_message(text: String) -> void:
	if _message_label == null:
		return
	_message_label.text = text
	_message_label.visible = true
	_message_timer = 2.0


## Called by a task that successfully uses the held item (e.g. E05
## installing the wire). Only succeeds if the carried item's id matches
## expected_id. Callers MUST treat a false return as a normal, expected
## outcome (Approved Decision A.10: a wrong item produces a clear,
## nonpunishing response -- no progress lost, no penalty) -- never as
## an error.
func consume_if_matches(expected_id: StringName) -> bool:
	if _carried_item == null or _carried_item_id != expected_id:
		return false
	var item := _carried_item
	_carried_item = null
	_carried_item_id = &""
	item.queue_free()
	return true


## Like consume_if_matches(), but for a caller that wants to give the
## item a new, persistent place in the world (e.g.
## electrical_panel.gd's wire installation) instead of destroying it --
## returns the actual node so the caller can reparent/reposition it.
## Same nonpunishing "wrong item" contract: returns null (and touches
## nothing) if not carrying, or carrying the wrong item, so callers can
## tell "installed" apart from "wrong/missing part" without this method
## ever silently losing or duplicating the carried item.
func take_carried_item_if_matches(expected_id: StringName) -> Node3D:
	if _carried_item == null or _carried_item_id != expected_id:
		return null
	var item := _carried_item
	_carried_item = null
	_carried_item_id = &""
	return item
