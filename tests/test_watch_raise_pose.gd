extends SceneTree
## Round 25 Priority 6: regression coverage for the world-body watch-
## inspection pose (player_body.gd set_watch_raise_pose()/
## _apply_watch_raise()).
##
## Root cause this guards against (measured, see MILESTONE1_DESIGN.md
## Round 25): the old pose TRANSLATED each arm anchor toward one hand target
## by different fractions, so shoulder->elbow collapsed 0.377 -> 0.143m,
## elbow->wrist 0.300 -> 0.193m, the elbow barely bent and the forearm
## pointed straight forward -- the "unnaturally long arm" in the mirror.
## Everything is driven through the REAL input path (KEY_C ->
## wristwatch_view.gd) and sampled DURING the tween, not only at its ends.
var _ok := true
var _main: Node
var _sp: Node3D
var _body: Node3D

func _init() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(_main)
	current_scene = _main
	for i in 5: await process_frame
	var player: Node3D = _main.get_node("Player")
	_main.get_node("FreeMoveBody").set_active(false)
	player.global_position = Vector3(2.15, 1.6, 1.55)
	_body = player.get_node("PlayerBody")
	_sp = _body.get_node("StandingPose")
	var rig: Node = player.get_node("LookPivot/PitchPivot/Camera3D/FirstPersonWatchRig")
	var player_cam: Camera3D = player.get_node("LookPivot/PitchPivot/Camera3D")
	var mirror_cam: Camera3D = _main.get_node("Mirrors/LivingQuartersMirror/Camera3D")
	var hand: Node3D = _sp.get_node("HandR")
	var watch: Node3D = hand.get_node("WristWatch")
	for i in 3: await process_frame

	var rest := _measure()
	var rest_hand_q: Quaternion = hand.quaternion
	var watch_local: Transform3D = watch.transform
	var watch_rest_p: Vector3 = _sp.global_transform.affine_inverse() * watch.global_position
	var rest_watch_to_wrist: float = watch_rest_p.distance_to(rest["w"])
	var rest_watch_to_elbow: float = watch_rest_p.distance_to(rest["e"])
	var body_pos: Vector3 = _body.global_position
	var player_pos: Vector3 = player.global_position

	# ---- Real input: hold C, sample through the tween. ----
	_key_c(true)
	var max_len_err: float = 0.0
	var max_cap_err: float = 0.0
	var samples: int = 0
	var t_end: int = Time.get_ticks_msec() + 900
	while Time.get_ticks_msec() < t_end:
		await process_frame
		var m := _measure()
		max_len_err = maxf(max_len_err, maxf(absf(m["upper"] - rest["upper"]), absf(m["fore"] - rest["fore"])))
		max_cap_err = maxf(max_cap_err, absf(m["cap"] - rest["cap"]))
		samples += 1
	var up := _measure()
	_check("C raised the first-person rig", rig.is_raised())
	_check("C raised the world body (progress %.2f)" % _body.watch_raise_progress(), is_equal_approx(_body.watch_raise_progress(), 1.0))
	_check("shoulder->elbow AND elbow->wrist lengths constant through the whole raise (%d samples, max error %.5f m)" % [samples, max_len_err], samples > 5 and max_len_err < 0.0005)
	# Round 27: the shoulder pivot may rise/protract by the bounded clavicle
	# lift when the watch is held high, but it must stay inside the shoulder
	# pad (attached to the torso -- no shrug, no detachment).
	_check("shoulder pivot stays attached (clavicle lift %.3f m <= 0.03)" % up["s"].distance_to(rest["s"]), up["s"].distance_to(rest["s"]) <= 0.03)
	var shoulder_rot: float = rad_to_deg((rest["e"] - rest["s"]).angle_to(up["e"] - up["s"]))
	_check("upper arm genuinely rotates at the shoulder (%.0f deg)" % shoulder_rot, shoulder_rot > 40.0)
	_check("elbow genuinely flexes (interior %.0f -> %.0f deg)" % [rest["angle"], up["angle"]], rest["angle"] - up["angle"] > 60.0 and up["angle"] < 95.0)
	_check("forearm does not point straight at the mirror (|forward| %.2f < 0.6)" % absf(up["fore_dir"].z), absf(up["fore_dir"].z) < 0.6)
	_check("deltoid cap moves with the upper arm (max shoulder-distance error %.5f)" % max_cap_err, max_cap_err < 0.0005)
	# Round 27: the hand now bends at the wrist; the watch is counter-rotated
	# so it stays fixed on the FOREARM -- its distances to the wrist and to
	# the elbow are what must not change.
	var watch_p: Vector3 = _sp.global_transform.affine_inverse() * watch.global_position
	var to_wrist: float = watch_p.distance_to(up["w"])
	var to_elbow: float = watch_p.distance_to(up["e"])
	_check("watch stays fixed on the forearm (wrist %.4f vs %.4f, elbow %.4f vs %.4f)" % [to_wrist, rest_watch_to_wrist, to_elbow, rest_watch_to_elbow], absf(to_wrist - rest_watch_to_wrist) < 0.002 and absf(to_elbow - rest_watch_to_elbow) < 0.002 and watch.get_parent() == hand)
	var roll_deg: float = rad_to_deg(absf(_body.watch_raise_rig()["roll"]))
	_check("no near-180 wrist twist (forearm roll %.0f deg <= 100)" % roll_deg, roll_deg <= 100.0)
	var face_off: float = _face_angle_to_eye()
	_check("watch face turned toward the eyes (%.0f deg off)" % face_off, face_off < 25.0)
	var watch_count: int = 0
	for n in _sp.find_children("WristWatch", "", true, false):
		watch_count += 1
	_check("exactly one world-body watch on the standing pose (no duplicate)", watch_count == 1)
	# Round 28: the visible world body is the rigged character.
	_check("world body still visible while raised", _body.visible and _body.rigged_visual().body_mesh.is_visible_in_tree())
	_check("body not moved/rotated to force the watch into view", _body.global_position.is_equal_approx(body_pos) and player.global_position.is_equal_approx(player_pos))
	# Render-layer isolation.
	_check("first-person rig is on layer 2 and excluded from the mirror camera", (rig.get_node("ArmGroup") as VisualInstance3D).layers == 2 and (mirror_cam.cull_mask & 2) == 0)
	var arm_mesh: VisualInstance3D = _sp.get_node("ArmMeshR")
	_check("raised world arm is mirror-only (layer 4: hidden from the player's own camera, seen by the mirror)", arm_mesh.layers == 4 and (player_cam.cull_mask & 4) == 0 and (mirror_cam.cull_mask & 4) != 0)
	_check("raised world watch is mirror-only too", (watch.get_node("WatchCase") as VisualInstance3D).layers == 4)

	# ---- Release C: reversible. ----
	_key_c(false)
	await create_timer(0.9).timeout
	var back := _measure()
	_check("C release lowers the world body to rest", is_equal_approx(_body.watch_raise_progress(), 0.0))
	_check("joints return exactly to rest", back["e"].is_equal_approx(rest["e"]) and back["w"].is_equal_approx(rest["w"]))
	_check("hand returns to its rest orientation", hand.quaternion.is_equal_approx(rest_hand_q))
	# Round 27 follow-up: legs-only self view -- the standing arms are always
	# mirror-only (rendered for the mirror/other players, not the player's
	# own camera, where they appeared as floating shoulder "stumps").
	_check("arm stays mirror-only at rest too (legs-only self view)", arm_mesh.layers == 4)

	# ---- Reverse mid-raise: no snap. ----
	_body.set_watch_raise_pose(true, 0.4)
	await create_timer(0.25).timeout
	var mid_p: float = _body.watch_raise_progress()
	_body.set_watch_raise_pose(false, 0.4)
	var start_p: float = _body.watch_raise_progress()
	var monotonic := true
	var last_p: float = start_p
	for i in 60:
		await process_frame
		var cur: float = _body.watch_raise_progress()
		if cur > last_p + 0.0001:
			monotonic = false
		last_p = cur
	_check("reversing mid-raise starts from the CURRENT pose, not a snap (p=%.2f -> start %.2f)" % [mid_p, start_p], mid_p > 0.1 and mid_p < 0.95 and is_equal_approx(start_p, mid_p))
	_check("and lowers monotonically back to rest (end p=%.2f)" % last_p, monotonic and is_equal_approx(last_p, 0.0))

	# ---- Sitting / lying: no regression, arm reset. ----
	_body.set_watch_raise_pose(true, 0.0)
	_body.set_sitting(true)
	_check("sitting while raised resets the standing arm to rest instantly", is_equal_approx(_body.watch_raise_progress(), 0.0) and _measure()["e"].is_equal_approx(rest["e"]))
	_body.set_watch_raise_pose(true, 0.0)
	_check("watch raise is a no-op while sitting", is_equal_approx(_body.watch_raise_progress(), 0.0))
	_check("sitting pose keeps its own (rebuilt) wristwatch", _body.get_node("SittingPose/HandR/WristWatch") != null)
	_body.set_sitting(false)
	_body.set_lying(true)
	_body.set_watch_raise_pose(true, 0.0)
	_check("watch raise is a no-op while lying", is_equal_approx(_body.watch_raise_progress(), 0.0))
	_body.set_lying(false)
	_check("standing again after lying", not _body.is_lying() and not _body.is_sitting())

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _measure() -> Dictionary:
	var s: Vector3 = _sp.get_node("ShoulderR").position
	var e: Vector3 = _sp.get_node("ElbowR").position
	var w: Vector3 = _sp.get_node("HandR").position
	var cap: Vector3 = _sp.get_node("ShoulderCapR").position
	return {
		"s": s, "e": e, "w": w,
		"upper": s.distance_to(e), "fore": e.distance_to(w), "cap": s.distance_to(cap),
		"angle": rad_to_deg((s - e).angle_to(w - e)),
		"fore_dir": (w - e).normalized(),
	}


## Angle between the watch face's outward normal and the direction to the
## eye (body origin), in body space.
func _face_angle_to_eye() -> float:
	var inv: Transform3D = _body.global_transform.affine_inverse()
	var case_p: Vector3 = inv * _sp.get_node("HandR/WristWatch/WatchCase").global_position
	var face_p: Vector3 = inv * _sp.get_node("HandR/WristWatch/WatchCase/FacePlate").global_position
	return rad_to_deg((face_p - case_p).angle_to(-face_p))


func _key_c(pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_C
	ev.physical_keycode = KEY_C
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
