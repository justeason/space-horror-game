extends SceneTree
## Round 28 Priority 5: a real reach-grasp-carry with the rigged hand.
## Gameplay state (carrying, parenting) stays immediate -- carry_system.gd's
## single-item contract is unchanged -- but the part is not teleported: it
## stays where it was until the hand arrives, then rides in the palm. An
## interrupted reach (drop mid-animation) never loses or duplicates it.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame
	var player: Node3D = main.get_node("Player")
	var body: Node3D = player.get_node("PlayerBody")
	var carry: Node = player.get_node("CarrySystem")
	var cab: Node = main.get_node("Geometry/StorageCabinet1")
	var wire: Node3D = main.get_node("Interactables/WireComponent")
	main.get_node("FreeMoveBody").set_active(false)
	var eye := Vector3(-6.95, 1.6, 7.75)
	main.get_node("FreeMoveBody").sync_to_eye_position(eye)
	player.global_position = eye
	cab.interact()
	await create_timer(0.7).timeout
	var shelf_pos: Vector3 = wire.global_position

	wire.interact()
	await process_frame
	await process_frame
	# Round 31: ownership transfers at the GRASP, not the click.
	_check("click starts a reach; the part is not yet owned (still on its shelf)", carry.is_reaching() and not carry.is_carrying() and wire.get_parent() != body.get_node("CarryAnchor"))
	_check("reach in progress", body.is_reaching())
	_check("the part stays where it was while the hand reaches (no teleport, %.3f m)" % wire.global_position.distance_to(shelf_pos), wire.global_position.distance_to(shelf_pos) < 0.005)
	# Round 30: reach out 0.6s, back to the carry pose by 1.2s.
	await create_timer(1.5).timeout
	_check("reach finished", not body.is_reaching())
	var rig: Node3D = body.rigged_visual()
	var palm: Vector3 = rig.to_global(rig.bone_pos("RightHand") + rig.bone_basis("RightHand") * Vector3(0.0, -0.07, -0.01))
	_check("the part rides in the rig's right palm (%.3f m)" % wire.global_position.distance_to(palm), wire.global_position.distance_to(palm) < 0.01)
	var count := 0
	for n in main.find_children("WireComponent", "", true, false):
		count += 1
	_check("exactly one wire exists (no duplicate)", count == 1)

	# Drop, then pick up again and drop MID-reach: the part must survive.
	carry.drop()
	await process_frame
	_check("drop returns the part to its shelf", wire.global_position.distance_to(shelf_pos) < 0.01 and not carry.is_carrying())
	wire.interact()
	await create_timer(0.7).timeout  # Round 31: the hand owns the part only at the grasp
	await process_frame
	carry.drop()
	await process_frame
	await process_frame
	_check("interrupted reach: part back on its shelf, not lost", wire.is_inside_tree() and wire.global_position.distance_to(shelf_pos) < 0.01)
	_check("carry anchor returned to its authored spot", (body.get_node("CarryAnchor") as Node3D).position.is_equal_approx(Vector3(0.22, -0.35, -0.4)))

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
