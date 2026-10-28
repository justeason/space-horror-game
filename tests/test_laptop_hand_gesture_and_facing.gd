extends SceneTree
## Regression for this round's fixes: (1) the laptop screen actually
## faces the seated player instead of away from them (the reported
## bug -- confirmed via a real empirical dot-product measurement, not
## assumed), and (2) opening the laptop visibly moves the sitting
## pose's hand toward the lid and back, instead of the laptop just
## unfolding on its own.

var _ok := true


func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5:
		await process_frame

	var player := main.get_node("Player")
	var free_body := main.get_node("FreeMoveBody")
	var bunk := main.get_node("Interactables/Bunk")
	var laptop := main.get_node("Interactables/BunksideLaptop")
	var laptop_view := player.get_node("LaptopView")
	var player_body := player.get_node("PlayerBody")
	var sitting_pose := player_body.get_node("SittingPose")
	var hand: Node3D = sitting_pose.get_node("HandR")

	var near_pos := Vector3(bunk.global_position.x - 1.0, 1.6, bunk.global_position.z)
	free_body.sync_to_eye_position(near_pos)
	player.global_position = near_pos
	for i in 3:
		await process_frame
	bunk.interact()
	await create_timer(1.6).timeout

	var hand_rest: Vector3 = hand.position
	var upper_arm: Node3D = sitting_pose.get_node("UpperArmR")
	var elbow: Node3D = sitting_pose.get_node("ElbowR")
	var upper_arm_rest: Vector3 = upper_arm.position
	var elbow_rest: Vector3 = elbow.position

	# ============================================================
	# 1. SCREEN FACING: the physical screen's glowing face must point
	# substantially TOWARD the eye, not away from it (the reported
	# bug -- previously measured at dot=-0.91, i.e. facing almost
	# exactly away).
	# ============================================================
	_send_key(KEY_F)

	# ============================================================
	# 2. HAND GESTURE: pressing F should visibly move the hand away
	# from its resting pose during the pickup+hinge animation...
	# ============================================================
	await create_timer(0.55).timeout # mid pickup tween (0.4s) + into the gesture
	var hand_mid: Vector3 = hand.position
	_check("hand gesture: hand has moved away from its resting pose while the laptop opens (moved %.3fm)" % hand.position.distance_to(hand_rest), hand_mid.distance_to(hand_rest) > 0.02)
	_check("arm gesture: upper arm also moved (whole arm, not just the hand floating alone) (moved %.3fm)" % upper_arm.position.distance_to(upper_arm_rest), upper_arm.position.distance_to(upper_arm_rest) > 0.01)
	_check("arm gesture: elbow also moved, and less than the hand did (proportional arm swing, got elbow=%.3fm hand=%.3fm)" % [elbow.position.distance_to(elbow_rest), hand_mid.distance_to(hand_rest)], elbow.position.distance_to(elbow_rest) > 0.01 and elbow.position.distance_to(elbow_rest) < hand_mid.distance_to(hand_rest))

	# ...and then return to rest once the gesture finishes.
	await create_timer(0.6).timeout
	var hand_after: Vector3 = hand.position
	_check("hand gesture: hand returned to its resting pose after the gesture completes (residual %.3fm)" % hand_after.distance_to(hand_rest), hand_after.distance_to(hand_rest) < 0.01)

	_check("precondition: laptop actually open", laptop.is_open)

	var screen = laptop.get_node("HingePivot/LidBack/ScreenGlow")
	var screen_pos: Vector3 = screen.global_position
	var screen_normal: Vector3 = screen.global_transform.basis.y.normalized() * -1.0
	var eye: Vector3 = player.global_position
	var to_eye: Vector3 = (eye - screen_pos).normalized()
	var facing_dot: float = screen_normal.dot(to_eye)
	_check("screen facing: screen normal points substantially toward the eye, not away from it (dot=%.2f, want > 0.6; the reported bug measured -0.91)" % facing_dot, facing_dot > 0.6)

	# ============================================================
	# 3. CLOSING now plays its OWN gesture too (Section 3 of this
	# round's task: previously close_laptop() never animated the arm
	# at all). It must visibly reach, then settle back to rest once
	# that gesture finishes -- not snap to rest instantly.
	# ============================================================
	_send_key(KEY_F) # close
	await create_timer(0.1).timeout
	_check("close: hand is reaching (mid-gesture), not frozen at rest", hand.position.distance_to(hand_rest) > 0.02)
	await create_timer(0.5).timeout
	_check("close: hand settled back to rest once the close gesture finished", hand.position.distance_to(hand_rest) < 0.01)

	# ============================================================
	# 4. REPEATED OPEN/CLOSE, including interrupting one gesture with
	# the other, never leaves the hand stuck away from rest or stacks
	# conflicting gesture tweens -- it must always end up AT rest once
	# everything settles.
	# ============================================================
	_send_key(KEY_F) # open again, quickly
	await create_timer(0.1).timeout
	_send_key(KEY_F) # close again before the open gesture would have finished
	await create_timer(0.6).timeout
	_check("repeat: rapid open/close still settles the hand exactly at rest", hand.position.distance_to(hand_rest) < 0.01)

	print("")
	if _ok:
		print("ALL TESTS PASSED")
	else:
		print("SOME TESTS FAILED")
	quit()


func _send_key(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)


func _check(label: String, cond: bool) -> void:
	if cond:
		print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
