extends SceneTree
## Round 11 rewrite: regression coverage for "the player's body
## disappears when the watch is raised, and returns when C is
## released."
##
## ROOT CAUSE (confirmed by reading player_body.gd's _process(), not
## assumed): the previous architecture eased PlayerBody's OWN pitch
## follow toward a full 1.0 while the watch was raised, so the ENTIRE
## body (StandingPose -- torso, hips, legs, both arms) rotated in
## lockstep with the camera's pitch around the eye-point pivot. That
## is the correct transform for a small FIXED offset close to the
## pivot (the old watch), but wrong for a body extending ~1.6m below
## it -- at any real pitch, most of the body swings outside the
## frustum or behind the camera. This test file previously only
## checked the WATCH's own screen stability; it now ALSO verifies the
## thing the player actually reported: that PlayerBody's pitch follow
## stays at its ordinary partial value and the body stays visible
## REGARDLESS of whether the watch is raised, across a real pitch
## sweep -- the actual regression, not a proxy for it.
##
## The watch inspection presentation itself now lives in
## scripts/player/first_person_watch_rig.gd, a plain child of
## Camera3D -- verified here via genuine frustum containment (near
## plane + fov-derived half-angle at distance, NOT
## unproject_position() alone, which does not clamp to the frustum --
## see Round 10's own investigation for why that check was previously
## insufficient) across a yaw+pitch sweep including steep angles.
##
## Still verified via geometry/transform math, not a rendered pixel
## comparison -- no headless rendering is available in this
## environment. See the final report's manual playtest checklist for
## the remaining actual-visual confirmation this cannot replace.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player := main.get_node("Player")
	var free_body := main.get_node("FreeMoveBody")
	free_body.set_active(false)
	var look_pivot := player.get_node("LookPivot")
	var pitch_pivot := look_pivot.get_node("PitchPivot")
	var cam := pitch_pivot.get_node("Camera3D")
	var body := player.get_node("PlayerBody")
	var rig := cam.get_node("FirstPersonWatchRig")
	var watch_case: Node3D = rig.get_node("ArmGroup/WatchAssembly/WatchCase")
	var hand: Node3D = rig.get_node("ArmGroup/Palm")

	# ============================================================
	# 1. Baseline: PlayerBody's pitch follow is ALWAYS the ordinary
	# partial value now -- there is no longer a "while raised" mode to
	# even check, which is itself the fix. Confirmed both before and
	# after raising.
	# ============================================================
	_check("pitch follow is the normal standing value before raising", is_equal_approx(body._pitch_follow_current, body.standing_pitch_follow))

	var ev := InputEventKey.new()
	ev.keycode = KEY_C
	ev.pressed = true
	Input.parse_input_event(ev)
	await create_timer(0.6).timeout

	_check("watch actually raised", rig.is_raised())
	_check("pitch follow STILL the normal partial value while raised (the actual fix)", is_equal_approx(body._pitch_follow_current, body.standing_pitch_follow))

	# ============================================================
	# 2. THE ACTUAL REGRESSION TEST: sweep a real pitch/yaw range with
	# the watch raised and confirm the world body's own key points
	# (hips, chest, a foot) are where plain geometry says they should
	# be -- i.e. the body was never rotated away to satisfy watch
	# positioning. Compares against the SAME sweep with the watch
	# NOT raised: the body's pose must be identical either way.
	# ============================================================
	var standing_pose: Node3D = body.get_node("StandingPose")
	var hips: Node3D = standing_pose.get_node("Hips")
	var chest: Node3D = standing_pose.get_node("Chest")
	var foot_r: Node3D = standing_pose.get_node("FootR")

	var raised_positions: Dictionary = {}
	for pitch_deg in [-50.0, -20.0, 0.0, 20.0, 50.0, 70.0]:
		look_pivot.rotation.y = 0.0
		look_pivot._target_yaw = 0.0
		pitch_pivot.rotation.x = deg_to_rad(pitch_deg)
		look_pivot._target_pitch = deg_to_rad(pitch_deg)
		await create_timer(0.25).timeout
		raised_positions[pitch_deg] = [hips.global_position, chest.global_position, foot_r.global_position]

	# Release and re-measure the SAME sweep with the watch down.
	var ev_up := InputEventKey.new()
	ev_up.keycode = KEY_C
	ev_up.pressed = false
	Input.parse_input_event(ev_up)
	await create_timer(0.6).timeout
	_check("watch lowered after release", not rig.is_raised())

	var all_match := true
	var worst_detail := ""
	for pitch_deg in [-50.0, -20.0, 0.0, 20.0, 50.0, 70.0]:
		pitch_pivot.rotation.x = deg_to_rad(pitch_deg)
		look_pivot._target_pitch = deg_to_rad(pitch_deg)
		await create_timer(0.25).timeout
		var before: Array = raised_positions[pitch_deg]
		var after: Array = [hips.global_position, chest.global_position, foot_r.global_position]
		for i in 3:
			if not before[i].is_equal_approx(after[i]):
				all_match = false
				worst_detail = "pitch=%.0f part=%d raised_pos=%s lowered_pos=%s" % [pitch_deg, i, before[i], after[i]]
	_check(
		"world body pose is IDENTICAL whether the watch is raised or lowered, across a full pitch sweep (the actual reported bug)" + (" (first mismatch: %s)" % worst_detail if not all_match else ""),
		all_match
	)

	# ============================================================
	# 2b. The body must also never become literally invisible (the
	# `visible` flag itself) while the watch is raised.
	# ============================================================
	Input.parse_input_event(ev)
	await create_timer(0.6).timeout
	_check("body.visible stays true while watch is raised", body.visible)
	_check("StandingPose stays visible while watch is raised", standing_pose.visible)

	# ============================================================
	# 3. The watch rig itself (first-person-only, camera-child) stays
	# genuinely inside the camera frustum across a real yaw+pitch
	# sweep, including steep angles -- near plane AND fov-derived
	# half-angle bound, not merely a stable projected pixel (which
	# unproject_position() alone would not guarantee -- see Round 10's
	# investigation).
	# ============================================================
	var all_in_frustum := true
	var worst_rig_detail := ""
	for yaw_deg in [0.0, 40.0, -70.0, 120.0, -150.0]:
		for pitch_deg in [-60.0, -20.0, 0.0, 20.0, 60.0, 75.0]:
			look_pivot.rotation.y = deg_to_rad(yaw_deg)
			look_pivot._target_yaw = deg_to_rad(yaw_deg)
			pitch_pivot.rotation.x = deg_to_rad(pitch_deg)
			look_pivot._target_pitch = deg_to_rad(pitch_deg)
			await create_timer(0.15).timeout
			for node in [watch_case, hand]:
				if not _in_frustum(cam, node.global_position):
					all_in_frustum = false
					worst_rig_detail = "%s at yaw=%.0f pitch=%.0f" % [node.name, yaw_deg, pitch_deg]
	_check("watch rig (case and hand) stays genuinely inside the camera frustum across steep yaw+pitch combinations" + (" (first failure: %s)" % worst_rig_detail if not all_in_frustum else ""), all_in_frustum)

	# Reset to neutral before the release/cycle checks below.
	look_pivot.rotation.y = 0.0
	look_pivot._target_yaw = 0.0
	pitch_pivot.rotation.x = 0.0
	look_pivot._target_pitch = 0.0
	await create_timer(0.3).timeout

	# ============================================================
	# 4. Releasing hides the rig; repeated press/release cycles don't
	# accumulate drift or get stuck.
	# ============================================================
	Input.parse_input_event(ev_up)
	await create_timer(0.6).timeout
	_check("rig hidden after release", not rig.visible)

	var rest_arm_pos: Vector3 = rig.get_node("ArmGroup").position
	for cycle in 4:
		Input.parse_input_event(ev)
		await create_timer(0.35).timeout
		Input.parse_input_event(ev_up)
		await create_timer(0.35).timeout
	_check("arm group returns to the exact rest (lowered) position after 4 repeated press/release cycles", rig.get_node("ArmGroup").position.is_equal_approx(rest_arm_pos))
	_check("not stuck raised after repeated cycles", not rig.is_raised())
	_check("not stuck visible after repeated cycles", not rig.visible)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()

## Real frustum containment: beyond the near plane, and within the
## fov-derived half-angle bound at that distance on both axes.
func _in_frustum(cam: Camera3D, world_pos: Vector3) -> bool:
	var local_pos: Vector3 = cam.global_transform.affine_inverse() * world_pos
	var dist: float = -local_pos.z
	if dist <= cam.near:
		return false
	var half: float = dist * tan(deg_to_rad(cam.fov * 0.5))
	return absf(local_pos.y) < half and absf(local_pos.x) < half


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
