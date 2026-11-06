extends SceneTree
## Round 31 Priority 7: ownership transfers at the GRASP, not the click.
## Before: pick_up() claimed the part the instant it was clicked (reparented
## to the hand, out of shelf stock) while the hand only visibly arrived
## 0.6 s later. Now the click starts a reach; the part stays where it is --
## still owned by its shelf -- until player_body.gd's hand arrives and calls
## carry_system.complete_grasp(). Interruptions (door closed, walked away,
## Space, entering a seat/focused view) cancel the reach and leave the part
## exactly where it was: nothing lost, nothing duplicated.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame
	var player: Node3D = main.get_node("Player")
	var fb: Node = main.get_node("FreeMoveBody")
	var carry: Node = player.get_node("CarrySystem")
	var ic: Node = carry._interaction_controller
	var cab: Node = main.get_node("Geometry/StorageCabinet1")
	var w1: Node3D = main.get_node("Interactables/WireComponent")
	var w2: Node3D = main.get_node("Interactables/WireComponent2")
	fb.sync_to_eye_position(Vector3(-6.95, 1.6, 7.75))
	for i in 10: await physics_frame
	cab.interact()
	await create_timer(0.8).timeout
	var rest: Vector3 = w1.global_position

	# ---- Reach, then grasp. ----
	w1.interact()
	await process_frame
	_check("click starts a reach, not ownership", carry.is_reaching() and not carry.is_carrying())
	_check("during the reach the part is untouched and still shelf stock", w1.global_position.distance_to(rest) < 0.001 and cab.stock_count(&"wire_control_16ga") == 4 and w1.get_parent().name == "Interactables")
	_check("one item at a time: a second pickup is refused during the reach", not carry.pick_up(w2) and carry.reaching_for() == w1)
	await create_timer(0.75).timeout
	_check("the hand grasped it: now owned by the hand", carry.is_holding(w1) and not carry.is_reaching())
	_check("stock drops only at the grasp (4 -> 3)", cab.stock_count(&"wire_control_16ga") == 3)
	carry.drop()
	await process_frame

	# ---- Interruptions. ----
	for case in ["door closed", "walked away", "space", "interactions disabled"]:
		_check("[%s] precondition: part on its shelf" % case, w1.global_position.distance_to(rest) < 0.01 and not carry.is_carrying())
		if not cab.is_open():
			cab.interact()
			await create_timer(0.8).timeout
		w1.interact()
		await create_timer(0.15).timeout
		match case:
			"door closed":
				cab.interact()
				await create_timer(0.8).timeout
			"walked away":
				fb.sync_to_eye_position(Vector3(-6.0, 1.6, 6.0) + Vector3(-1.0, 0, -1.6))
				player.global_position = fb.current_eye_position()
				await create_timer(0.1).timeout
			"space":
				var ev := InputEventKey.new()
				ev.keycode = KEY_SPACE
				ev.physical_keycode = KEY_SPACE
				ev.pressed = true
				Input.parse_input_event(ev)
				await process_frame
			"interactions disabled":
				ic.interactions_enabled = false   # e.g. sat down / focused view
				await create_timer(0.2).timeout
				ic.interactions_enabled = true
		await create_timer(0.9).timeout
		_check("[%s] the reach is cancelled, nothing owned" % case, not carry.is_reaching() and not carry.is_carrying())
		_check("[%s] the part never moved and is still stocked" % case, w1.global_position.distance_to(rest) < 0.01 and w1.get_parent().name == "Interactables" and cab.is_item_stowed(w1))
		if case == "walked away":
			fb.sync_to_eye_position(Vector3(-6.95, 1.6, 7.75))
			for i in 10: await physics_frame
	var count := 0
	for n in main.find_children("WireComponent*", "", true, false):
		count += 1
	_check("no duplicates: still exactly 4 shelf harnesses", count == 4)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
