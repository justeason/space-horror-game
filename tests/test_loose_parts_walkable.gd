extends SceneTree
## Round 34 Priority 7: small loose parts dropped on the floor never block
## the player. ROOT CAUSE: a landed part went back to collision layer 1,
## which the player capsule collides with (mask 1|4) and the capsule has no
## step-up, so a 9 cm filter cartridge was an impassable wall. Loose parts
## now rest on the pickable-only layer (16): the interaction ray still
## hits them (pickup works), the drop proxy still lands on floors/furniture.
## Walks with REAL key input (W held) straight across each part.
var _ok := true
var main: Node
var fb: CharacterBody3D
var player: Node3D
var lp: Node3D
var carry: Node

func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame
	fb = main.get_node("FreeMoveBody")
	player = main.get_node("Player")
	lp = player.get_node("LookPivot")
	carry = player.get_node("CarrySystem")
	main.get_node("Geometry/StorageCabinet1").interact()
	main.get_node("Geometry/StorageCabinet2").interact()
	await create_timer(0.9).timeout
	var used: Node3D = main.get_node("Interactables/UsedFilterCartridge")
	used.eject_at(Transform3D(Basis(), Vector3(-6.9, 0.1, 7.1)))
	var parts := {
		"clean filter": main.get_node("Interactables/FilterCartridge"),
		"used filter": used,
		"16GA harness": main.get_node("Interactables/WireComponent2"),
		"22GA signal cable": main.get_node("Interactables/WireSignal1"),
	}
	var lane_x := 2.6
	for tag in parts:
		var item: Node3D = parts[tag]
		# Place the part on the open Living Quarters floor, then walk over it.
		_take(item)
		carry._carried_item = null; carry._carried_item_id = &""; carry._release_physics(item)
		item.place_in_world(Transform3D(Basis(), Vector3(lane_x, 0.3, -0.3)))
		carry._physics_drop(item, item.global_transform, Vector3.ZERO)
		var t0 := Time.get_ticks_msec()
		while carry.is_settling(item) and Time.get_ticks_msec() - t0 < 3000:
			await physics_frame
		_check("%s: landed on the floor (y %.3f), on the loose-part layer (%d)" % [tag, item.global_position.y, (item as CollisionObject3D).collision_layer], item.global_position.y < 0.2 and (item as CollisionObject3D).collision_layer == 16)
		var passed: bool = await _walk_across(Vector3(lane_x, 1.6, 0.6), item.global_position)
		_check("%s: the player walks straight over it (no blockage)" % tag, passed)
		# Pickup still works after walking past: turn around and click it.
		await _face(fb.current_eye_position(), item.global_position)
		for i in 6: await physics_frame
		var hovered: Object = carry._interaction_controller.get_hovered()
		_check("%s: still targetable by the interaction ray after passing (%s)" % [tag, str(hovered)], hovered == item)
		lane_x += 0.0
		_take(item)
		_check("%s: picked up again" % tag, carry.is_holding(item))
		carry._carried_item = null; carry._carried_item_id = &""; carry._release_physics(item)
		item.place_in_world(Transform3D(Basis(), Vector3(4.4, 0.2, 0.9)))
		carry._physics_drop(item, item.global_transform, Vector3.ZERO)
		var t1 := Time.get_ticks_msec()
		while carry.is_settling(item) and Time.get_ticks_msec() - t1 < 3000:
			await physics_frame
	# A cluster of several loose parts in one lane.
	var xs := [2.55, 2.65, 2.6]
	var zs := [-0.2, -0.35, -0.5]
	var i2 := 0
	for tag in ["clean filter", "16GA harness", "22GA signal cable"]:
		var it: Node3D = parts[tag]
		_take(it)
		carry._carried_item = null; carry._carried_item_id = &""; carry._release_physics(it)
		it.place_in_world(Transform3D(Basis(), Vector3(xs[i2], 0.25, zs[i2])))
		carry._physics_drop(it, it.global_transform, Vector3.ZERO)
		i2 += 1
	await create_timer(1.5).timeout
	_check("a cluster of three loose parts does not block either", await _walk_across(Vector3(2.6, 1.6, 0.6), Vector3(2.6, 0.1, -0.35)))
	# Furniture still blocks: walk into the bunk.
	var bed_block: bool = not await _walk_across(Vector3(3.6, 1.6, -0.55), Vector3(4.6, 0.5, -0.55), 1.2)
	_check("furniture (the bunk) still blocks the player", bed_block)
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


## Holds W toward `target` for up to `seconds`; true if the player got at
## least 0.5 m past the target point along the walking direction.
func _walk_across(start_eye: Vector3, target: Vector3, seconds: float = 2.0) -> bool:
	await _face(start_eye, Vector3(target.x, start_eye.y, target.z))
	var dir: Vector3 = Vector3(target.x - start_eye.x, 0, target.z - start_eye.z).normalized()
	var need: float = Vector2(target.x - start_eye.x, target.z - start_eye.z).length() + 0.5
	for i in 4: await physics_frame
	var p0: Vector3 = fb.global_position
	_key(KEY_W, true)
	var t0 := Time.get_ticks_msec()
	var travelled := 0.0
	while Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		await physics_frame
		travelled = (fb.global_position - p0).dot(dir)
		if travelled >= need:
			break
	_key(KEY_W, false)
	for i in 3: await physics_frame
	return travelled >= need


func _face(eye: Vector3, look: Vector3) -> void:
	fb.sync_to_eye_position(eye)
	player.global_position = eye
	var d: Vector3 = look - eye
	lp.rotation.y = atan2(-d.x, -d.z) - player.rotation.y
	lp._target_yaw = lp.rotation.y
	var pitch: float = atan2(d.y, Vector2(d.x, d.z).length())
	lp._target_pitch = pitch
	lp.get_node("PitchPivot").rotation.x = pitch
	for i in 3: await physics_frame


func _take(item: Node3D) -> void:
	if carry.is_carrying():
		carry.drop()
	carry.pick_up(item)
	if carry.is_reaching():
		carry.complete_grasp()


func _key(k: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
