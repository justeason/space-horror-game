extends SceneTree
## Round 29 Priority 1 regression: carrying an item must never move the
## player. ROOT CAUSE found this round: every carryable is a StaticBody3D on
## collision layer 1, and its collider stayed ENABLED while parented to the
## carry anchor. The Round 28 palm-carry pose holds the filter ~0.36m from
## the capsule axis, so its 0.18m box reached inside FreeMoveBody's 0.30m
## capsule; move_and_slide() depenetrated the capsule every tick (velocity
## stayed exactly 0), the player followed the capsule, the hand followed
## the player -- a self-sustaining ~3 m/s backward drift that stopped the
## moment the item was dropped. Measured before the fix: 3.4m of drift in
## 3s of carrying the filter with no input.
##
## Covers (real physics ticks, real carry_system calls, real W key):
## filter + wire pickup and carrying for seconds with zero input, turning
## while carrying, walking and stopping, dropping, rapid pickup/drop, an
## interrupted reach, collision-layer suspension/restoration, ownership/no
## duplicates, and Priority 6's dropped-item floor contact.
var _ok := true
var main: Node
var fb: CharacterBody3D
var player: Node3D
var carry: Node

func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame
	player = main.get_node("Player")
	fb = main.get_node("FreeMoveBody")
	carry = player.get_node("CarrySystem")
	var lp: Node3D = player.get_node("LookPivot")
	var body: Node3D = player.get_node("PlayerBody")

	# [item, its cabinet, start eye, world yaw that walks AWAY from the cabinet]
	for spec in [["FilterCartridge", "StorageCabinet2", Vector3(-6.0, 1.6, 8.0), PI], ["WireComponent", "StorageCabinet1", Vector3(-6.95, 1.6, 7.75), 0.0]]:
		var item: StaticBody3D = main.get_node("Interactables/" + spec[0])
		var tag: String = spec[0]
		fb.sync_to_eye_position(spec[2])
		for i in 20: await physics_frame
		main.get_node("Geometry/" + spec[1]).interact()
		await create_timer(0.8).timeout
		var layer_before: int = item.collision_layer
		var p0: Vector3 = fb.global_position
		item.interact()
		await create_timer(0.7).timeout  # Round 31: the hand owns the part only at the grasp
		_check("%s: picked up" % tag, carry.is_carrying() and carry.carried_item_id() == item.item_id)
		_check("%s: held item leaves the physics world (layer 0)" % tag, item.collision_layer == 0)
		# Pickup + reach + several seconds of carrying, no input.
		var max_speed := 0.0
		for i in 180:
			await physics_frame
			max_speed = maxf(max_speed, fb.get_real_velocity().length())
		var drift: float = fb.global_position.distance_to(p0)
		_check("%s: 3s carried with no input -> no displacement (%.4f m)" % [tag, drift], drift < 0.005)
		_check("%s: ... and no velocity (max %.4f m/s)" % [tag, max_speed], max_speed < 0.01)
		# Turning the camera while carrying.
		var p1: Vector3 = fb.global_position
		for i in 60:
			lp._target_yaw += 0.05
			lp._target_pitch = sin(i * 0.2) * 0.6
			await physics_frame
		_check("%s: turning/looking while carrying does not move the player (%.4f m)" % [tag, fb.global_position.distance_to(p1)], fb.global_position.distance_to(p1) < 0.005)
		_check("%s: the part rides in the hand (not left behind)" % tag, item.global_position.distance_to(player.global_position) < 1.0)
		# Walk forward, release, stop.
		lp._target_yaw = -player.rotation.y + spec[3]   # face away from the cabinet, into the room
		lp.rotation.y = lp._target_yaw
		for i in 10: await physics_frame
		var ev := InputEventKey.new()
		ev.keycode = KEY_W
		ev.physical_keycode = KEY_W
		ev.pressed = true
		Input.parse_input_event(ev)
		var pw: Vector3 = fb.global_position
		for i in 30: await physics_frame
		var ev2 := ev.duplicate()
		ev2.pressed = false
		Input.parse_input_event(ev2)
		var moved: float = fb.global_position.distance_to(pw)
		_check("%s: walking while carrying still moves the player (%.2f m)" % [tag, moved], moved > 0.3)
		for i in 40: await physics_frame
		var ps: Vector3 = fb.global_position
		for i in 60: await physics_frame
		_check("%s: after releasing W the player stops and STAYS stopped (%.4f m)" % [tag, fb.global_position.distance_to(ps)], fb.global_position.distance_to(ps) < 0.005)
		# Drop at the feet (Space path): collision restored, rests ON the floor.
		# Drop from the known-good spot, facing open floor (-Z from both
		# start points has 3m of clear floor; the walk end point above can
		# sit over a floor gap where drop safety correctly refuses).
		fb.sync_to_eye_position(spec[2])
		lp._target_yaw = -player.rotation.y
		lp.rotation.y = lp._target_yaw
		# Look at the floor: facing the part's own OPEN cabinet, Space would
		# (correctly, since Round 30) stow it back on its shelf instead.
		lp._target_pitch = deg_to_rad(-60.0)
		lp.get_node("PitchPivot").rotation.x = deg_to_rad(-60.0)
		for i in 10: await physics_frame
		_check("%s: aiming at open floor, not a stow target" % tag, carry.stow_target() == null)
		carry._attempt_drop_at_feet()
		# Round 30: a dropped part falls from the hand and settles (~0.6s).
		await create_timer(0.9).timeout
		var msg: Label = player.get_node_or_null("HUD/TaskMessageLabel")
		_check("%s: dropped at the feet (not carrying)%s" % [tag, "" if not carry.is_carrying() or msg == null else " -- refused: " + msg.text], not carry.is_carrying())
		_check("%s: drop restores the item's collision layer" % tag, item.collision_layer == layer_before)
		var floor_hit: Dictionary = item.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(item.global_position + Vector3(0, 0.3, 0), item.global_position - Vector3(0, 1.0, 0), 1, [item.get_rid()]))
		# The VISIBLE underside rests on the floor (Round 30 solver; the
		# wire's collision box hangs 3.5cm below its coil by design).
		var bottom: float = item.global_position.y + carry.item_local_extent(item).position.y
		if not floor_hit.is_empty():
			var fy: float = (floor_hit["position"] as Vector3).y
			_check("%s: dropped item rests ON the floor (bottom %.3f vs floor %.3f)" % [tag, bottom, fy], bottom >= fy - 0.002 and bottom < fy + 0.02)
		else:
			_check("%s: a floor exists under the dropped item" % tag, false)
		var pd: Vector3 = fb.global_position
		for i in 60: await physics_frame
		_check("%s: after dropping, still no drift (%.4f m)" % [tag, fb.global_position.distance_to(pd)], fb.global_position.distance_to(pd) < 0.005)
		# Rapid pickup/drop cycles, and an interrupted reach.
		var pr: Vector3 = fb.global_position
		for k in 6:
			item.interact()
			await create_timer(0.7).timeout  # Round 31: the hand owns the part only at the grasp
			await physics_frame
			carry.drop()
			await physics_frame
		_check("%s: rapid pickup/drop leaves the item resting, collidable, not carried" % tag, not carry.is_carrying() and item.collision_layer == layer_before and item.is_inside_tree())
		item.interact()
		await create_timer(0.7).timeout  # Round 31: the hand owns the part only at the grasp
		for i in 4: await physics_frame
		_check("%s: reach in progress" % tag, body.is_reaching())
		carry.drop()
		for i in 30: await physics_frame
		_check("%s: interrupted reach resolves deterministically (back at rest, layer restored)" % tag, not carry.is_carrying() and item.collision_layer == layer_before)
		_check("%s: rapid cycles + interruption caused no drift (%.4f m)" % [tag, fb.global_position.distance_to(pr)], fb.global_position.distance_to(pr) < 0.005)
		var count := 0
		for n in main.find_children(spec[0], "", true, false):
			count += 1
		_check("%s: exactly one instance exists (no duplicate)" % tag, count == 1)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
