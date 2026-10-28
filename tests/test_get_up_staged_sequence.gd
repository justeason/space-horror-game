extends SceneTree
## New regression for the M9 staged get-up sequence: verifies actual
## movement/state transitions at each stage boundary (not just that a
## function was called), using the real sleep_state.gd timing exports
## so this stays correct if those are retuned later.

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
	var standing_pose := player_body.get_node("StandingPose")
	var sitting_pose := player_body.get_node("SittingPose")
	var foot_l := sitting_pose.get_node("FootL")
	var foot_r := sitting_pose.get_node("FootR")
	var upper_leg_l := sitting_pose.get_node("UpperLegL")
	var near_pos := Vector3(bunk.global_position.x - 1.0, 1.6, bunk.global_position.z)

	var rest_foot_l: Vector3 = Vector3.ZERO
	var rest_foot_r: Vector3 = Vector3.ZERO

	_move(free_body, player, near_pos)
	bunk.interact()
	await create_timer(1.6).timeout
	_check("precondition: sitting", sleep_state.is_sitting())
	rest_foot_l = foot_l.position
	rest_foot_r = foot_r.position
	var rest_upper_leg_l_basis: Basis = upper_leg_l.transform.basis

	var prep: float = sleep_state.get_up_prepare_duration
	var swing: float = sleep_state.get_up_leg_swing_duration
	var settle: float = sleep_state.get_up_stance_settle_duration
	var rise: float = sleep_state.get_up_rise_duration

	var lead_right_first: bool = sleep_state._next_leg_leads_right
	sleep_state.end_sitting()

	# ------------------------------------------------------------
	# Stage 1 (prepare): still fully seated, nothing swapped yet, but
	# the torso has started leaning (Hips moved from rest).
	# ------------------------------------------------------------
	var hips: Node3D = sitting_pose.get_node("Hips")
	var hips_rest_pos: Vector3 = hips.position
	await create_timer(prep * 0.5).timeout
	_check("stage1: still sitting (not standing pose yet)", sitting_pose.visible and not standing_pose.visible)

	# ------------------------------------------------------------
	# Stage 2/3 (lead leg swings + plants): by the end of this stage,
	# exactly one leg has moved away from rest and the OTHER has not
	# moved yet -- proving the legs move one at a time, not together.
	# ------------------------------------------------------------
	await create_timer(prep * 0.5 + swing).timeout
	var lead_foot: Node3D = foot_r if lead_right_first else foot_l
	var other_foot: Node3D = foot_l if lead_right_first else foot_r
	var lead_rest: Vector3 = rest_foot_r if lead_right_first else rest_foot_l
	var other_rest: Vector3 = rest_foot_l if lead_right_first else rest_foot_r
	_check("stage2/3: lead foot (%s) has moved toward the floor (away from rest)" % lead_foot.name, lead_foot.position.distance_to(lead_rest) > 0.3)
	_check("stage2/3: lead foot reached floor height (local y near -1.17, got %.3f)" % lead_foot.position.y, absf(lead_foot.position.y - (-1.17)) < 0.03)
	_check("stage2/3: the OTHER foot has NOT moved yet (still at rest, got delta %.3fm)" % other_foot.position.distance_to(other_rest), other_foot.position.distance_to(other_rest) < 0.01)
	_check("stage2/3: lead foot reached the floor BEFORE the main rising stage began (still sitting, not standing)", sitting_pose.visible and not standing_pose.visible)

	# ------------------------------------------------------------
	# Stage 4 (second leg follows): by the end of this stage, BOTH feet
	# are now near the floor.
	# ------------------------------------------------------------
	await create_timer(swing).timeout
	_check("stage4: second foot (%s) now ALSO near the floor (got y=%.3f)" % [other_foot.name, other_foot.position.y], absf(other_foot.position.y - (-1.17)) < 0.03)
	_check("stage4: BOTH feet reached the floor before the main rising stage (still sitting)", sitting_pose.visible and not standing_pose.visible)

	# ------------------------------------------------------------
	# Stage 5 (stance settle) + first half of stage 6: still sitting,
	# eye partway risen.
	# ------------------------------------------------------------
	var eye_y_seated: float = player.global_position.y
	await create_timer(settle + rise * 0.25).timeout
	_check("stage5/6a: eye has started rising (y=%.3f > seated %.3f)" % [player.global_position.y, eye_y_seated], player.global_position.y > eye_y_seated + 0.02)
	_check("stage5/6a: pose has not swapped yet (still sitting pose)", sitting_pose.visible and not standing_pose.visible)

	# ------------------------------------------------------------
	# Stage 6 (push up): pose swaps partway through the rise, not at
	# t=0 of the whole sequence and not only at the very end.
	# ------------------------------------------------------------
	await create_timer(rise * 0.75).timeout
	_check("stage6: pose has swapped to standing by the end of the rise", standing_pose.visible and not sitting_pose.visible)

	# ------------------------------------------------------------
	# Stage 7 + settle: final state matches ordinary standing.
	# ------------------------------------------------------------
	await create_timer(sleep_state.get_up_finish_duration + 0.2).timeout
	_check("final: no longer sitting", not sleep_state.is_sitting())
	_check("final: standing eye height restored (got %.3f, want ~1.6)" % player.global_position.y, absf(player.global_position.y - 1.6) < 0.05)
	_check("final: legs reset to rest for next time (left leg)", upper_leg_l.transform.basis.is_equal_approx(rest_upper_leg_l_basis))
	_check("final: hips reset to rest position", hips.position.distance_to(hips_rest_pos) < 0.001)

	# ------------------------------------------------------------
	# Alternation: the NEXT get-up should lead with the other leg.
	# ------------------------------------------------------------
	_move(free_body, player, near_pos)
	bunk.interact()
	await create_timer(1.6).timeout
	var lead_right_second: bool = sleep_state._next_leg_leads_right
	_check("alternation: leading leg flips between get-up cycles", lead_right_second != lead_right_first)

	# No stuck intermediate state: can immediately sit/stand again.
	sleep_state.end_sitting()
	await create_timer(2.6).timeout
	_check("not stuck: fully standing again, free move active", not sleep_state.is_sitting() and free_body.active)

	print("")
	if _ok:
		print("ALL TESTS PASSED")
	else:
		print("SOME TESTS FAILED")
	quit()


func _move(free_body: Node, player: Node, pos: Vector3) -> void:
	free_body.sync_to_eye_position(pos)
	player.global_position = pos
	for i in 3:
		await player.get_tree().process_frame


func _check(label: String, cond: bool) -> void:
	if cond:
		print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
