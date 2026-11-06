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
## Round 20 Priority 8: shared procedural sound bank (scripts/audio/
## mechanical_sfx.gd), the same one every focused repair view already
## uses -- picking up or placing a physical item is small mechanical
## feedback of the exact same kind those views already play, so this
## reuses that one bank rather than introducing a second sound system.
## Routed through carry_system.gd itself (not each item's own script)
## so every current and future carryable item gets it for free.
@export var sfx_path: NodePath

@onready var _carry_anchor: Node3D = get_node(carry_anchor_path)
@onready var _player: Node3D = get_node_or_null(player_path)
@onready var _interaction_controller: Node = get_node_or_null(interaction_controller_path)
@onready var _message_label: Label = get_node_or_null("../HUD/TaskMessageLabel")
@onready var _sfx: Node = get_node_or_null(sfx_path)

var _carried_item: Node3D = null
var _carried_item_id: StringName = &""
## Round 29 Priority 1: the held item's own collision layer, saved at
## pickup and restored on every release path (see _release_physics()).
var _held_collision_layer: Dictionary = {}   # item -> its own layer
var _message_timer: float = 0.0


func is_carrying() -> bool:
	return _carried_item != null


func is_holding(item: Node) -> bool:
	return _carried_item != null and _carried_item == item


## Reserved by an in-progress reach (not yet owned by the hand).
func is_reserved(item: Node) -> bool:
	return _pending_item != null and _pending_item == item


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
## Round 28 Priority 5: emitted with the item's world transform just
## BEFORE it is reparented to the carry anchor, so the visible body can
## animate a real reach to where the part actually was. Purely visual;
## carrying state is still immediate.
signal item_picked_up(item: Node3D, from_global: Transform3D)


func pick_up(item: Node3D) -> bool:
	if _carried_item != null or _pending_item != null:
		return false   # one item at a time, reaches included
	_await_clear.erase(item)
	if _settle_tweens.has(item):
		# Caught mid-fall: stop the fall; its layer is still suspended.
		var settler = _settle_tweens[item]
		if settler is Tween and (settler as Tween).is_valid():
			(settler as Tween).kill()
		elif settler is Node and is_instance_valid(settler):
			(settler as Node).queue_free()
		_settle_tweens.erase(item)
		_release_physics(item)
	item_picked_up.emit(item, item.global_transform)
	# Round 31 Priority 7: with the rigged body standing, the hand REACHES
	# first and ownership transfers at the GRASP (player_body.gd calls
	# complete_grasp()). Until then the part stays where it is, still
	# owned by its shelf/floor/crate, and the reach can be cancelled.
	var body: Node = _body()
	if body != null and body.has_method("can_reach") and body.can_reach():
		_pending_item = item
		_pending_t = 0.0
		_pending_start_dist = item.global_position.distance_to(_player.global_position) if _player != null else 0.0
		var c0: Node = item.get_node_or_null("Collision")
		_pending_started_available = item.is_visible_in_tree() and (c0 == null or not c0.disabled)
		_pending_started_interactive = _interaction_controller == null or _interaction_controller.interactions_enabled
		return true
	_claim(item)
	return true


## The moment the hand closes on the part: ownership transfers to the hand.
## Returns false (and cancels) if the part is no longer available.
func complete_grasp() -> bool:
	var item: Node3D = _pending_item
	_pending_item = null
	if item == null or not _still_available(item):
		_notify_reach_cancelled()
		return false
	_claim(item)
	return true


func is_reaching() -> bool:
	return _pending_item != null


func reaching_for() -> Node3D:
	return _pending_item


## Cancels an in-progress reach; the part was never claimed, so it simply
## stays where it is (nothing to restore, nothing lost or duplicated).
func cancel_reach() -> void:
	if _pending_item == null:
		return
	_pending_item = null
	_notify_reach_cancelled()


func _claim(item: Node3D) -> void:
	_carried_item = item
	_carried_item_id = item.item_id
	# A part in the hand is always a visible, collidable object (it may have
	# been taken from behind a gated door): never carry a hidden/disabled
	# part that would later lie invisible and unclickable in the world.
	item.visible = true
	var col: Node = item.get_node_or_null("Collision")
	if col != null and "disabled" in col:
		col.disabled = false
	_suspend_physics(item)
	item.reparent(_carry_anchor, true)
	item.position = held_local_position
	item.rotation_degrees = held_local_rotation_degrees
	if _sfx != null:
		_sfx.play_kind(&"click")


func _still_available(item: Node3D) -> bool:
	if not is_instance_valid(item) or not item.is_inside_tree():
		return false
	if item.has_method("is_installed") and item.is_installed():
		return false
	# Hidden / non-collidable only counts if it BECAME so during the reach
	# (e.g. stowed behind a door that shut); scripted pickups of a gated
	# part are not "interrupted" by a state they started in.
	var col: Node = item.get_node_or_null("Collision")
	var avail_now: bool = item.is_visible_in_tree() and (col == null or not col.disabled)
	if item == _pending_item and _pending_started_available and not avail_now:
		return false
	if _player != null and item == _pending_item and item.global_position.distance_to(_player.global_position) > _pending_start_dist + REACH_WALK_AWAY:
		return false   # the player walked away during the reach
	if item == _pending_item and _pending_started_interactive and _interaction_controller != null and not _interaction_controller.interactions_enabled:
		return false   # entered a seat / focused view / sleep DURING the reach
	return true


func _grasp_time() -> float:
	var body: Node = _body()
	return body.REACH_OUT_S if body != null and "REACH_OUT_S" in body else 0.6


func _body() -> Node:
	return _player.get_node_or_null("PlayerBody") if _player != null else null


func _notify_reach_cancelled() -> void:
	var body: Node = _body()
	if body != null and body.has_method("cancel_reach"):
		body.cancel_reach()


## Cancels a reach when the player moves this much FARTHER from the part
## than when the reach began (any part you can target can be reached).
const REACH_WALK_AWAY: float = 1.0
var _pending_start_dist: float = 0.0
var _pending_started_available: bool = true
var _pending_started_interactive: bool = true
var _pending_item: Node3D = null
var _pending_t: float = 0.0


## Puts the held item back in the world (its own return_to_rest()
## decides where -- normally its original resting spot). Distinct from
## consume_if_matches(): this is the plain "drop" verb from §19, not a
## task successfully using the item up. Kept as the programmatic
## "unconditionally let go of whatever is held" primitive; the Space
## player action below is a separate, safer wrapper
## (_attempt_drop_at_feet()) that places the item on the floor instead.
func drop() -> void:
	if _pending_item != null:
		cancel_reach()
		return
	if _carried_item == null:
		return
	var item := _carried_item
	_carried_item = null
	_carried_item_id = &""
	if item.has_method("is_ejected"):
		# Round 32: a part with no shelf home (the used cartridge) used to stay
		# exactly where the hand was -- floating in mid-air. It falls instead.
		var xf: Transform3D = item.global_transform
		item.place_in_world(xf)
		item.global_transform = xf
		_physics_drop(item, xf, Vector3.ZERO)
		return
	_release_physics(item)
	item.return_to_rest()
	if _sfx != null:
		_sfx.play_kind(&"click")


func _process(delta: float) -> void:
	for it in _await_clear.keys():
		if not is_instance_valid(it) or _carried_item == it:
			_await_clear.erase(it)
		elif not _touches_player(it):
			_await_clear.erase(it)
			_release_physics(it)
	if _pending_item != null:
		_pending_t += delta
		if not _still_available(_pending_item):
			cancel_reach()
		elif _pending_t >= _grasp_time():
			# The hand arrives at the part now (player_body.gd animates the
			# same REACH_OUT_S timeline; this is the one authoritative clock,
			# so a watch raise or other arm pose can never stall a grasp).
			complete_grasp()
	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0 and _message_label != null:
			if _message_label.get_meta(&"msg_owner", 0) == get_instance_id():   # shared HUD label: hide only our own message
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
	if _pending_item != null:
		cancel_reach()   # Space mid-reach: let go of the reach, not a drop
		get_viewport().set_input_as_handled()
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
	if _player == null or _carried_item == null:
		_show_message("Can't drop that right now.")
		return

	var forward := Vector3(0, 0, -1)
	if _interaction_controller != null:
		var f: Vector3 = -_interaction_controller.global_transform.basis.z
		f.y = 0.0
		if f.length() > 0.01:
			forward = f.normalized()

	var item := _carried_item
	# Round 30: facing the OPEN cabinet this part belongs to, Space puts it
	# back on its own shelf slot (restocks it) instead of dropping it.
	var cab: Node = stow_target()
	if cab != null:
		_carried_item = null
		_carried_item_id = &""
		_release_physics(item)
		if cab.has_method("stow"):
			cab.stow(item)
		else:
			item.return_to_rest()
		if _sfx != null:
			_sfx.play_kind(&"click")
		_show_message("Stowed: %s." % (item.get_display_name() if item.has_method("get_display_name") else "Item"))
		return
	# Round 32 Priority 1 ROOT CAUSE FIX ("the filter slides sideways, then
	# falls"): Rounds 30-31 moved the part from the hand to a solver-chosen
	# spot ~0.6 m ahead (a 0.18 s tween, measured: 0.557 m horizontal at
	# constant height over the first 10 ticks) and only then dropped it.
	# Now the part is released WHERE THE HAND IS: physics starts from the
	# hand pose, inheriting the player's motion. If the hand pose is inside
	# something, the smallest separation is tried (lift <= 8 cm, pull back
	# toward the body <= 5 cm); failing that the drop is refused and the
	# part stays in the hand. Never a relocation.
	# Looking at a reachable, near-level surface: the arm PLACES the part
	# there (the hand visibly carries it out, still held), then lets go.
	var place: Variant = _aim_place_point(item)
	var body: Node = _body()
	if place != null and body != null and body.has_method("begin_place"):
		_placing = true
		body.begin_place(place, PLACE_REACH_S)
		await get_tree().create_timer(PLACE_REACH_S).timeout
		_placing = false
		if _carried_item != item:
			return   # consumed/stowed meanwhile
	var release: Variant = _clear_release_pose(item)
	if release == null:
		_show_message("No room to release that here.")
		return
	# Never let a part fall where there is nothing to land on (e.g. off the
	# mapped station): the old solver refused here, and so does this.
	var below: Dictionary = item.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(item.global_position, item.global_position + Vector3(0, -3.0, 0), PLACE_MASK, _exclusions(item)))
	if below.is_empty():
		refused_releases += 1
		_show_message("No safe floor to set that down here.")
		return
	_carried_item = null
	_carried_item_id = &""
	var held_xf: Transform3D = item.global_transform
	if item.has_method("place_in_world"):
		item.place_in_world(held_xf)
	else:
		item.return_to_rest()
		_release_physics(item)
		return
	item.global_transform = held_xf
	var vel := Vector3.ZERO
	var fb: Node = _free_body()
	if fb is CharacterBody3D:
		vel = (fb as CharacterBody3D).get_real_velocity()
	# Only the player's HORIZONTAL walking motion carries over (a settling
	# capsule's vertical correction must never toss the part upward).
	vel.y = 0.0
	vel = vel.limit_length(2.0) + forward * RELEASE_FORWARD_SPEED
	if (release as Transform3D).origin.distance_to(held_xf.origin) > 0.001:
		var tw: Tween = item.create_tween()
		_settle_tweens[item] = tw
		tw.tween_property(item, "global_transform", release, 0.08)
		await tw.finished
		if _settle_tweens.get(item) != tw or not is_instance_valid(item):
			return
	release_count += 1
	_physics_drop(item, item.global_transform, vel)


## Place gesture (Round 32): aim point on a near-level surface within the
## arm's reach -> the hand carries the part out to just above it.
const PLACE_REACH_S: float = 0.35
const PLACE_MAX_FROM_SHOULDER: float = 1.0
var _placing: bool = false


func is_placing() -> bool:
	return _placing


func _aim_place_point(item: Node3D) -> Variant:
	if _interaction_controller == null or _player == null:
		return null
	var o: Vector3 = (_interaction_controller as Node3D).global_position
	var dir: Vector3 = -(_interaction_controller as Node3D).global_basis.z
	var space := item.get_world_3d().direct_space_state
	var h: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(o, o + dir * 1.6, PLACE_MASK, _exclusions(item)))
	if h.is_empty() or (h["normal"] as Vector3).y < SUPPORT_NORMAL_MIN:
		return null
	# Never "place" a part into equipment openings (the waste hatch recess):
	# disposal is its own interaction.
	var c: Node = h["collider"]
	for k in 3:
		if c == null:
			break
		if c.is_in_group(&"no_place"):
			return null
		c = c.get_parent()
	var ext: AABB = item_local_extent(item)
	var target: Vector3 = (h["position"] as Vector3) + Vector3(0, -ext.position.y + 0.04, 0)
	var body: Node3D = _body() as Node3D
	var shoulder: Vector3 = body.to_global(Vector3(0.175, -0.2, 0.14)) if body != null else o
	if target.distance_to(shoulder) > PLACE_MAX_FROM_SHOULDER + 0.12:
		return null   # out of arm's reach: an ordinary release instead
	return target


## Forward speed given to a released part (a gentle let-go, not a throw).
const RELEASE_FORWARD_SPEED: float = 0.15
var release_count: int = 0
var refused_releases: int = 0


func _free_body() -> Node:
	return _player.get_parent().get_node_or_null("FreeMoveBody") if _player != null and _player.get_parent() != null else null


## The held pose if the part fits there (ignoring the player's own capsule
## and hover proxies); otherwise the smallest lift/pull-back that fits;
## null if nothing within a few cm fits (the drop is then refused).
func _clear_release_pose(item: Node3D) -> Variant:
	var xf: Transform3D = Transform3D(item.global_basis.orthonormalized(), item.global_position)
	var back := Vector3.ZERO
	if _player != null:
		back = _player.global_position - xf.origin
		back.y = 0.0
		back = back.normalized() if back.length() > 0.01 else Vector3.ZERO
	for lift in [0.0, 0.02, 0.04, 0.06, 0.08]:
		for pull in [0.0, 0.025, 0.05]:
			var cand := Transform3D(xf.basis, xf.origin + Vector3(0, lift, 0) + back * pull)
			if _fits(item, cand):
				return cand
	refused_releases += 1
	return null


func _fits(item: Node3D, xf: Transform3D) -> bool:
	var ext: AABB = item_local_extent(item)
	var box := BoxShape3D.new()
	box.size = ext.size
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = PLACE_MASK
	q.exclude = _exclusions(item)
	q.margin = 0.002
	q.transform = Transform3D(xf.basis, xf.origin + xf.basis * ext.get_center())
	var space := item.get_world_3d().direct_space_state
	if not space.intersect_shape(q, 1).is_empty():
		return false
	# A shape query cannot see a part FULLY inside a concave solid (a CSG
	# wall): the release point must also be in clear line of sight from the
	# player's eye -- never inside or behind a wall.
	if _interaction_controller != null:
		var eye: Vector3 = (_interaction_controller as Node3D).global_position
		var c: Vector3 = xf.origin + xf.basis * ext.get_center()
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, c, PLACE_MASK, _exclusions(item))).is_empty():
			return false
	return true


# ======================================================================
# Round 30 Priority 3: physical placement solver.
# ======================================================================
## ROOT CAUSES of "dropped items fall inside furniture / clip surfaces":
## (1) most interior props had no collision at all (see
## furniture_contact.gd), so the drop ray went straight through them;
## (2) the old drop was ONE ray at one point: it never asked whether the
## item's whole footprint was supported, whether the item fitted there, or
## whether the path from the hand to that spot was clear, and it put the
## item's origin -- not its underside -- on the hit point.
##
## Now the item's own VISIBLE extent (an upright box fitted to its meshes,
## yawed to the player's facing) is swept: from the hand out to a candidate
## spot (must be clear: no dropping through a wall, a door or into a
## closed cabinet), then straight down onto the first surface it touches
## (floor, shelf, counter, mattress, desk -- layer 1 or FURNITURE_LAYER).
## A rest is accepted only on a near-level surface (normal.y > 0.85), with
## the footprint supported (centre + >= 3 of 4 inset corners on that surface,
## so nothing balances on an edge or straddles a seam/step) and the resting
## box free of interpenetration. An unsupported rest SLIDES toward its
## supported side (up to 3 x 6cm) before the next candidate is tried. The
## accepted drop falls from the hand under gravity and settles.
const PLACE_MASK: int = 1 | 4
const SUPPORT_NORMAL_MIN: float = 0.85
const MAX_FALL: float = 1.6

func _exclusions(item: Node3D) -> Array[RID]:
	var out: Array[RID] = []
	if item is CollisionObject3D:
		out.append((item as CollisionObject3D).get_rid())
	# Hover/click proxy volumes (e.g. the bunk's invisible 0.35m box above
	# the mattress) are not surfaces anything can rest on.
	for n in get_tree().get_nodes_in_group(&"placement_proxy"):
		if n is CollisionObject3D:
			out.append((n as CollisionObject3D).get_rid())
	var fb: Node = _player.get_parent().get_node_or_null("FreeMoveBody") if _player.get_parent() != null else null
	if fb is CollisionObject3D:
		out.append((fb as CollisionObject3D).get_rid())
	return out


## Upright local extent of the item's visible meshes (its own origin, no
## rotation) -- what actually has to rest on a surface. Collision boxes are
## not used for this: the wire's box hangs 3.5cm below its coil.
static func item_local_extent(item: Node3D) -> AABB:
	var inv: Transform3D = Transform3D(item.global_basis.orthonormalized(), item.global_position).affine_inverse()
	var box := AABB()
	var first := true
	for v in item.find_children("*", "VisualInstance3D", true, false):
		var vi := v as VisualInstance3D
		if vi is Label3D:
			continue
		var b: AABB = (inv * vi.global_transform) * vi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		box = AABB(Vector3(-0.05, -0.05, -0.05), Vector3(0.1, 0.1, 0.1))
	return box


var _settle_tweens: Dictionary = {}


## The released part falls from the hand under gravity (~9.8 m/s^2, at
## most 0.5s), turning upright on the way, then settles with a small
## damped bounce. It stays out of the physics world until it has landed
## (so a falling part can never push the player), then collides again.
## Round 31 Priority 5B: the released part FALLS UNDER REAL PHYSICS. A
## temporary RigidBody3D (box fitted to the part's visible extent) starts
## at the hand with a small forward toss and collides with floors and
## furniture (mask 1 | furniture), never with the player capsule or hover
## proxies; the part follows it each physics tick until it sleeps. The rest
## pose is then VALIDATED (no interpenetration, supported underneath,
## within reach); if physics produced anything invalid -- or takes too
## long -- the part settles at the solver's validated rest instead, so it
## can never end up inside furniture or out of reach.
const SETTLE_MAX_S: float = 2.5
## Landings resolved by physics (diagnostics/tests).
var physics_rests: int = 0


func _physics_drop(item: Node3D, from: Transform3D, start_velocity: Vector3) -> void:
	var ext: AABB = item_local_extent(item)
	var proxy := RigidBody3D.new()
	proxy.name = "SettleProxy"
	proxy.collision_layer = 0
	proxy.collision_mask = PLACE_MASK
	proxy.continuous_cd = true
	proxy.linear_damp = 0.6
	proxy.angular_damp = 3.0
	proxy.mass = 1.2
	proxy.can_sleep = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.05
	proxy.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = ext.size
	cs.shape = box
	cs.position = ext.get_center()
	proxy.add_child(cs)
	var parent: Node = item.get_parent() if item.get_parent() != null else get_tree().current_scene
	parent.add_child(proxy)
	proxy.global_transform = Transform3D(from.basis.orthonormalized(), from.origin)
	for rid_owner in get_tree().get_nodes_in_group(&"placement_proxy"):
		if rid_owner is PhysicsBody3D:
			proxy.add_collision_exception_with(rid_owner)
	var fb: Node = _player.get_parent().get_node_or_null("FreeMoveBody") if _player != null and _player.get_parent() != null else null
	if fb is PhysicsBody3D:
		proxy.add_collision_exception_with(fb)
	if item is PhysicsBody3D:
		proxy.add_collision_exception_with(item)
	proxy.linear_velocity = start_velocity
	_settle_tweens[item] = proxy
	_follow_proxy(item, proxy, 0.0)


func _follow_proxy(item: Node3D, proxy: RigidBody3D, t: float) -> void:
	var ext: AABB = item_local_extent(item)
	var last_good: Transform3D = proxy.global_transform
	var violations := 0
	while is_instance_valid(proxy) and _settle_tweens.get(item) == proxy:
		await get_tree().physics_frame
		if not is_instance_valid(item) or not is_instance_valid(proxy):
			return
		t += get_physics_process_delta_time()
		# Round 32 tunneling guard: CSG walls/floors are thin one-sided
		# meshes a tumbling box can punch through. If this tick's motion
		# crossed a surface (or the part clearly sits inside geometry), put it
		# back to the last good pose -- one tick earlier, centimetres away --
		# and kill its velocity; physics then continues from there.
		var xf: Transform3D = proxy.global_transform
		var c0: Vector3 = last_good.origin + last_good.basis.orthonormalized() * ext.get_center()
		var c1: Vector3 = xf.origin + xf.basis.orthonormalized() * ext.get_center()
		var crossed: bool = c0.distance_to(c1) > 0.001 and not item.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(c0, c1, PLACE_MASK, _exclusions(item))).is_empty()
		if crossed or _penetrates(item, xf):
			violations += 1
			proxy.global_transform = last_good
			proxy.linear_velocity = Vector3.ZERO
			proxy.angular_velocity = Vector3.ZERO
			tunnel_saves += 1
			if violations > 6:
				proxy.freeze = true
		else:
			last_good = xf
		item.global_transform = proxy.global_transform
		var resting: bool = proxy.freeze or proxy.sleeping or (t > 0.35 and proxy.linear_velocity.length() < 0.03 and proxy.angular_velocity.length() < 0.1)
		if resting or t > SETTLE_MAX_S:
			var final: Transform3D = _seat_on_surface(item, proxy.global_transform)
			proxy.queue_free()
			# Wherever physics put it stays put (no relocation). Only a rare
			# interpenetration is resolved by the smallest lift that fits.
			if not _fits(item, final):
				for lift in [0.01, 0.02, 0.03]:
					var up := Transform3D(final.basis, final.origin + Vector3(0, lift, 0))
					if _fits(item, up):
						final = up
						break
			physics_rests += 1
			_on_landed(item, final)
			return


func _seat_on_surface(item: Node3D, xf: Transform3D) -> Transform3D:
	var b: Basis = xf.basis.orthonormalized()
	if b.y.dot(Vector3.UP) < 0.97:
		return xf
	var ext: AABB = item_local_extent(item)
	var c: Vector3 = xf.origin + b * ext.get_center()
	var space := item.get_world_3d().direct_space_state
	var h: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(c, c - Vector3(0, ext.size.y * 0.5 + 0.04, 0), PLACE_MASK, _exclusions(item)))
	if h.is_empty():
		return xf
	var bottom: float = xf.origin.y + ext.position.y
	var lift: float = (h["position"] as Vector3).y + 0.001 - bottom
	if absf(lift) < 0.03:
		xf.origin.y += lift
	return xf


func _on_landed(item: Node3D, rest: Transform3D) -> void:
	_settle_tweens.erase(item)
	if not is_instance_valid(item) or _carried_item == item:
		return
	item.global_transform = rest
	# Never let a resting part push the player: if it settled touching the
	# capsule, it becomes solid only once the capsule has moved clear.
	if _touches_player(item):
		_await_clear[item] = true
		if item is CollisionObject3D:
			(item as CollisionObject3D).collision_layer = PICKABLE_ONLY_LAYER
	else:
		_release_physics(item)
	if _sfx != null:
		_sfx.play_kind(&"click")


var _await_clear: Dictionary = {}
## Pickable by the interaction ray (mask 1 | 16) but invisible to the
## player capsule (mask 1 | 4): used while a part rests touching the player.
const PICKABLE_ONLY_LAYER: int = 16


func _touches_player(item: Node3D) -> bool:
	var fb: Node = _free_body()
	if not (fb is CollisionObject3D) or not (fb as CollisionObject3D).get_collision_layer_value(1):
		return false
	var ext: AABB = item_local_extent(item)
	var box := BoxShape3D.new()
	box.size = ext.size + Vector3(0.02, 0.02, 0.02)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = 1
	q.transform = Transform3D(item.global_basis.orthonormalized(), item.global_position + item.global_basis.orthonormalized() * ext.get_center())
	for h in item.get_world_3d().direct_space_state.intersect_shape(q, 8):
		if h["collider"] == fb:
			return true
	return false


## Clearly inside solid geometry (a 1.2 cm-shrunk box still overlaps):
## resting contact never counts.
func _penetrates(item: Node3D, xf: Transform3D) -> bool:
	var ext: AABB = item_local_extent(item)
	var box := BoxShape3D.new()
	box.size = (ext.size - Vector3(0.024, 0.024, 0.024)).max(Vector3(0.01, 0.01, 0.01))
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = PLACE_MASK
	q.exclude = _exclusions(item)
	q.transform = Transform3D(xf.basis.orthonormalized(), xf.origin + xf.basis.orthonormalized() * ext.get_center())
	return not item.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


var tunnel_saves: int = 0


func is_settling(item: Node3D) -> bool:
	return _settle_tweens.has(item)


## The open storage cabinet the player is looking at that owns the carried
## part (null otherwise) -- see storage_cabinet.gd accepts_item().
func stow_target() -> Node:
	if _carried_item == null or _interaction_controller == null:
		return null
	var hovered: Object = _interaction_controller.get_hovered()
	if hovered != null and hovered.has_method("accepts_item") and hovered.accepts_item(_carried_item):
		return hovered as Node
	return null


func _show_message(text: String) -> void:
	if _message_label == null:
		return
	_message_label.text = text
	_message_label.set_meta(&"msg_owner", get_instance_id())
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
	_release_physics(item)
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
	_release_physics(item)
	return item


## Round 29 Priority 1 ROOT-CAUSE FIX ("carrying the filter drives the
## player backward"): every carryable is a StaticBody3D on layer 1, and
## reparenting it under the carry anchor left its collider ENABLED and
## moving with the player. The Round 28 palm-carry pose holds it ~0.36m
## from the capsule axis, so the filter's 0.18m box reached ~0.27m --
## inside FreeMoveBody's 0.30m capsule. move_and_slide()'s depenetration
## then pushed the capsule away (velocity stayed exactly zero), the
## player followed the capsule, the hand followed the player, and the
## item re-overlapped next tick: a self-sustaining ~3 m/s drift that
## stopped the moment the item was dropped. A held item belongs to the
## hand, not the world, so it leaves the physics world entirely while
## carried (collision_layer = 0: nothing collides with or raycasts it,
## and the storage cabinet's own `disabled` gating is untouched).
func _suspend_physics(item: Node3D) -> void:
	if item is CollisionObject3D:
		if not _held_collision_layer.has(item):
			_held_collision_layer[item] = (item as CollisionObject3D).collision_layer
		(item as CollisionObject3D).collision_layer = 0


## Restores the layer saved by _suspend_physics(); called on EVERY path
## that lets go of the item (drop, drop-at-feet, consume, take) before
## the item's own placement code runs.
func _release_physics(item: Node3D) -> void:
	if item is CollisionObject3D and is_instance_valid(item) and _held_collision_layer.has(item):
		(item as CollisionObject3D).collision_layer = _held_collision_layer[item]
		_held_collision_layer.erase(item)
