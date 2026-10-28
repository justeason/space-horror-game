extends SceneTree
## Regression for Section 3: "the arm moves when the laptop opens, but
## does not move correctly when the laptop closes." Root cause: close_
## laptop() never called the gesture animation at all -- there was no
## closing gesture to be wrong; there simply wasn't one. Fixed by
## calling the same animate_hand_laptop_gesture() from both open_laptop()
## and close_laptop(), both referencing the same fixed rest transforms
## cached once in player_body.gd's _ready(), so open and close are
## symmetric by construction.

var _ok := true


func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5:
		await process_frame

	var player := main.get_node("Player")
	var free_body := main.get_node("FreeMoveBody")
	var sleep_state := main.get_node("SleepState")
	var bunk := main.get_node("Interactables/Bunk")
	var player_body := player.get_node("PlayerBody")
	var sitting_pose := player_body.get_node("SittingPose")

	var hand: Node3D = sitting_pose.get_node("HandR")
	var upper_arm: Node3D = sitting_pose.get_node("UpperArmR")
	var elbow: Node3D = sitting_pose.get_node("ElbowR")
	var lower_arm: Node3D = sitting_pose.get_node("LowerArmR")

	var near_pos := Vector3(bunk.global_position.x - 1.0, 1.6, bunk.global_position.z)
	free_body.sync_to_eye_position(near_pos)
	player.global_position = near_pos
	for i in 3:
		await process_frame
	bunk.interact()
	await create_timer(1.6).timeout

	var hand_rest: Vector3 = hand.position
	var upper_arm_rest: Vector3 = upper_arm.position
	var elbow_rest: Vector3 = elbow.position
	var lower_arm_rest: Vector3 = lower_arm.position

	# ============================================================
	# 1. OPENING: whole arm moves out and back.
	# ============================================================
	_send_key(KEY_F)
	await create_timer(0.55).timeout # mid pickup (0.4s) + into the gesture
	_check("open: hand moved away from rest", hand.position.distance_to(hand_rest) > 0.02)
	_check("open: upper arm also moved (whole arm, not hand alone)", upper_arm.position.distance_to(upper_arm_rest) > 0.01)
	await create_timer(0.6).timeout # gesture (hinge duration window) finishes
	_check("open: hand returned to rest after the gesture (residual %.4fm)" % hand.position.distance_to(hand_rest), hand.position.distance_to(hand_rest) < 0.001)
	_check("open: upper arm returned to rest (residual %.4fm)" % upper_arm.position.distance_to(upper_arm_rest), upper_arm.position.distance_to(upper_arm_rest) < 0.001)
	_check("precondition: laptop actually open", sleep_state.is_laptop_open())

	# ============================================================
	# 2. CLOSING: this is the actual regression -- the arm must ALSO
	# visibly move (reach, then return) when closing, not stay frozen
	# at rest while only the lid animates.
	# ============================================================
	_send_key(KEY_F)
	await create_timer(0.15).timeout
	var hand_mid_close: Vector3 = hand.position
	var elbow_mid_close: Vector3 = elbow.position
	var lower_arm_mid_close: Vector3 = lower_arm.position
	_check("close: hand moved away from rest during the close gesture (moved %.3fm)" % hand_mid_close.distance_to(hand_rest), hand_mid_close.distance_to(hand_rest) > 0.02)
	_check("close: elbow also moved (whole arm)", elbow_mid_close.distance_to(elbow_rest) > 0.01)
	_check("close: lower arm also moved (whole arm)", lower_arm_mid_close.distance_to(lower_arm_rest) > 0.01)
	_check("close: elbow moved less than the hand (proportional swing, elbow=%.3fm hand=%.3fm)" % [elbow_mid_close.distance_to(elbow_rest), hand_mid_close.distance_to(hand_rest)], elbow_mid_close.distance_to(elbow_rest) < hand_mid_close.distance_to(hand_rest))

	await create_timer(0.5).timeout
	_check("close: hand returned EXACTLY to its original resting transform (residual %.4fm)" % hand.position.distance_to(hand_rest), hand.position.distance_to(hand_rest) < 0.001)
	_check("close: upper arm returned exactly to rest (residual %.4fm)" % upper_arm.position.distance_to(upper_arm_rest), upper_arm.position.distance_to(upper_arm_rest) < 0.001)
	_check("close: elbow returned exactly to rest (residual %.4fm)" % elbow.position.distance_to(elbow_rest), elbow.position.distance_to(elbow_rest) < 0.001)
	_check("close: lower arm returned exactly to rest (residual %.4fm)" % lower_arm.position.distance_to(lower_arm_rest), lower_arm.position.distance_to(lower_arm_rest) < 0.001)
	_check("precondition: laptop actually closed", not sleep_state.is_laptop_open())

	# ============================================================
	# 3. REPEATED open/close cycles never accumulate drift (every
	# gesture starts and ends at the SAME fixed rest transform).
	# ============================================================
	for cycle in range(3):
		_send_key(KEY_F)
		await create_timer(0.7).timeout
		_send_key(KEY_F)
		await create_timer(0.7).timeout
	_check("repeated cycles: hand still exactly at original rest (no cumulative drift, residual %.5fm)" % hand.position.distance_to(hand_rest), hand.position.distance_to(hand_rest) < 0.001)
	_check("repeated cycles: upper arm still exactly at original rest (residual %.5fm)" % upper_arm.position.distance_to(upper_arm_rest), upper_arm.position.distance_to(upper_arm_rest) < 0.001)

	# ============================================================
	# 4. INTERRUPTED transition: close while the open gesture is still
	# mid-flight -- must not leave two tweens fighting, and must still
	# end up exactly at rest.
	# ============================================================
	_send_key(KEY_F) # open
	await create_timer(0.1).timeout # still early in the pickup tween
	_send_key(KEY_F) # close immediately, interrupting
	await create_timer(0.7).timeout
	_check("interrupted: hand ends at rest despite interrupting mid-open (residual %.4fm)" % hand.position.distance_to(hand_rest), hand.position.distance_to(hand_rest) < 0.001)
	_check("interrupted: laptop ended up closed", not sleep_state.is_laptop_open())

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
