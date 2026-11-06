extends SceneTree
## Round 26 regression coverage: shared look/pose synchronization between the
## authoritative camera, the world character (mirror) and the first-person
## watch rig, via scripts/player/character_pose_state.gd.
##
## Root cause guarded against (measured/rendered, see MILESTONE1_DESIGN.md
## Round 26): the two representations used unrelated pose rules -- the
## first-person rig followed 100% of camera pitch while the world body tilted
## as one rigid piece by 30% (legs included), its head had no look response,
## and the raised watch arm was a fixed body-space target; the camera-locked
## first-person forearm also entered the frame from under the camera, i.e.
## through the player's own chest, when looking down.
var _ok := true
var _main: Node
var _player: Node3D
var _body: Node3D
var _sp: Node3D
var _look: Node3D
var _pitch: Node3D
var _state: Node
var _rig: Node3D
var _cam: Camera3D

func _init() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(_main)
	current_scene = _main
	for i in 5: await process_frame
	_player = _main.get_node("Player")
	_main.get_node("FreeMoveBody").set_active(false)
	_main.get_node("FreeMoveBody").sync_to_eye_position(Vector3(3.3, 1.6, 1.2))
	_player.global_position = Vector3(3.3, 1.6, 1.2)
	_body = _player.get_node("PlayerBody")
	_sp = _body.get_node("StandingPose")
	_look = _player.get_node("LookPivot")
	_look.input_enabled = false
	_pitch = _look.get_node("PitchPivot")
	_state = _player.get_node("PoseState")
	_cam = _pitch.get_node("Camera3D")
	_rig = _cam.get_node("FirstPersonWatchRig")
	var PoseState = load("res://scripts/player/character_pose_state.gd")

	# ---- 1. State transmission from the authoritative camera. ----
	await _set_pitch(-35.0)
	_check("pose state reads the camera's real pitch (%.1f vs %.1f)" % [rad_to_deg(_state.look_pitch), rad_to_deg(_pitch.rotation.x)], is_equal_approx(_state.look_pitch, _pitch.rotation.x))
	_check("pose state reads the camera's real yaw", is_equal_approx(_state.look_yaw, _look.rotation.y))
	_check("pose state runs before its consumers (process_priority)", _state.process_priority < _body.process_priority and _state.process_priority < _rig.process_priority)

	# ---- 2. Anatomical distribution (pure function). ----
	var ok_limits := true
	var ok_sum := true
	for deg in range(-80, 81, 5):
		var d: Dictionary = PoseState.distribute_look_pitch(deg_to_rad(deg), PoseState.Posture.STANDING)
		if rad_to_deg(d["neck"]) < PoseState.NECK_MIN_DEG - 0.01 or rad_to_deg(d["neck"]) > PoseState.NECK_MAX_DEG + 0.01 or absf(rad_to_deg(d["head"])) > 25.01 or rad_to_deg(d["spine"]) < PoseState.SPINE_MIN_DEG - 0.01 or rad_to_deg(d["spine"]) > PoseState.SPINE_MAX_DEG + 0.01:
			ok_limits = false
		if deg >= -80 and deg <= 70 and absf(rad_to_deg(d["spine"] + d["neck"] + d["head"]) - deg) > 0.5:
			ok_sum = false
	_check("spine/neck/head shares always within anatomical limits", ok_limits)
	_check("the shares add up to the look pitch inside the reachable range (-80..+70 deg)", ok_sum)
	var lying: Dictionary = PoseState.distribute_look_pitch(deg_to_rad(-60), PoseState.Posture.LYING)
	_check("lying: only a small head nod, no neck/spine", lying["spine"] == 0.0 and lying["neck"] == 0.0 and absf(rad_to_deg(lying["head"])) <= 20.01)

	# ---- 3. World head follows the look; body stays planted. ----
	var hips_level: Vector3 = _sp.get_node("Hips").global_position
	var foot_level: Vector3 = _sp.get_node("FootR").global_position
	await _set_pitch(-50.0)
	var head_down: float = _head_pitch_deg()
	await _set_pitch(40.0)
	var head_up: float = _head_pitch_deg()
	await _set_pitch(0.0)
	var head_level: float = _head_pitch_deg()
	_check("world head looks DOWN when the player looks down (head pitch %.1f deg)" % head_down, head_down < -35.0)
	_check("world head looks UP when the player looks up (head pitch %.1f deg)" % head_up, head_up > 28.0)
	_check("world head level when looking level (%.1f deg)" % head_level, absf(head_level) < 1.0)
	await _set_pitch(-70.0)
	_check("whole body never tilts with pitch (rotation.x = %.3f)" % _body.rotation.x, is_equal_approx(_body.rotation.x, 0.0))
	_check("pelvis and feet stay planted while looking down", _sp.get_node("Hips").global_position.is_equal_approx(hips_level) and _sp.get_node("FootR").global_position.is_equal_approx(foot_level))
	_check("collar stays on the torso (does not rotate with the head)", is_equal_approx(_body.get_node("HeadGroup/Collar").rotation.x, 0.0))

	# ---- 4. Raised watch + pitch: bounded adjustment, rigid limbs. ----
	await _set_pitch(0.0)
	_key_c(true)
	# Real time, not a frame count: headless frames can be milliseconds.
	await create_timer(0.8).timeout
	_check("C raised both representations", _rig.is_raised() and is_equal_approx(_body.watch_raise_progress(), 1.0))
	var rest_upper: float = _body.watch_raise_rig()["upper_len"]
	var rest_fore: float = _body.watch_raise_rig()["fore_len"]
	var max_err := 0.0
	var wrist_y := {}
	var clear := true
	var bent := true
	for deg in [-60.0, -30.0, 0.0, 30.0, 60.0, 75.0]:
		await _set_pitch(deg)
		var s: Vector3 = _sp.get_node("ShoulderR").position
		var e: Vector3 = _sp.get_node("ElbowR").position
		var w: Vector3 = _sp.get_node("HandR").position
		max_err = maxf(max_err, maxf(absf(s.distance_to(e) - rest_upper), absf(e.distance_to(w) - rest_fore)))
		wrist_y[deg] = w.y
		# Outside the torso volume (|x| < 0.21, y -0.9..-0.28, z > -0.23) and
		# clear of the head (centre ~(0,-0.07,-0.04), radius 0.1 + arm 0.04).
		for pt in [e, w]:
			var in_torso: bool = absf(pt.x) < 0.21 and pt.y > -0.9 and pt.y < -0.28 and pt.z > -0.23
			var in_head: bool = pt.distance_to(Vector3(0, -0.07, -0.04)) < 0.14
			if in_torso or in_head:
				clear = false
		if rad_to_deg((s - e).angle_to(w - e)) > 140.0:
			bent = false
	_check("limb lengths constant at every look pitch while raised (max error %.5f m)" % max_err, max_err < 0.0005)
	_check("elbow and wrist stay outside the torso and clear of the head at every pitch", clear)
	_check("elbow never locks straight at any pitch (interior < 140 deg)", bent)
	# Wrist flexion must bring the fingers TOWARD horizontal (a sign error
	# here bent them further up -- a salute, caught by render in Round 27).
	var fingers_ok := true
	for deg in [0.0, 30.0]:
		await _set_pitch(deg)
		var e2: Vector3 = _sp.get_node("ElbowR").position
		var w2: Vector3 = _sp.get_node("HandR").position
		var forearm_y: float = (w2 - e2).normalized().y
		var finger_y: float = (_sp.get_node("HandR").basis * Vector3(0, -1, 0)).normalized().y
		if finger_y > forearm_y + 0.02:
			fingers_ok = false
	_check("wrist bends the fingers toward horizontal, never further up than the forearm", fingers_ok)
	# Round 27: the raised watch follows look pitch 1:1 (shared
	# CharacterPoseState.watch_target_for_pitch) -- a large, clearly visible
	# arm motion in the mirror, not Round 26's bounded few-cm nudge.
	_check("looking up raises the world arm clearly, to eye level (wrist %.3f -> %.3f m)" % [wrist_y[0.0], wrist_y[30.0]], wrist_y[30.0] - wrist_y[0.0] > 0.12 and wrist_y[30.0] > -0.06)
	# Round 29 Priority 4: above eye level the watch keeps rising with the
	# look (bent elbow, clavicle shrug) up to a CAPPED high hold in front of
	# the brow -- never an overhead wave.
	_check("above eye level the watch rises to a capped high hold, never overhead (wrist %.3f at 60, %.3f at 75 m)" % [wrist_y[60.0], wrist_y[75.0]], wrist_y[60.0] >= wrist_y[30.0] - 0.001 and wrist_y[75.0] < 0.2 and absf(wrist_y[75.0] - wrist_y[60.0]) < 0.03)
	_check("looking down lowers it clearly (%.3f m from level to 30 deg down)" % (wrist_y[0.0] - wrist_y[-30.0]), wrist_y[0.0] - wrist_y[-30.0] > 0.12)
	_check("wrist height rises monotonically with look pitch", wrist_y[-60.0] <= wrist_y[-30.0] + 0.001 and wrist_y[-30.0] < wrist_y[0.0] and wrist_y[0.0] < wrist_y[30.0] and wrist_y[30.0] < wrist_y[60.0] + 0.001)
	_check("below the chest limit (-30 deg) the arm holds and the head bows instead", is_equal_approx(wrist_y[-60.0], wrist_y[-30.0]))
	_check("watch stays attached to the hand", _sp.get_node("HandR/WristWatch").get_parent() == _sp.get_node("HandR"))

	# ---- 5. First person and world are the SAME model at every pitch. ----
	# Round 28: the player and every other camera now see ONE rigged
	# character (technician_rig.gd); the old camera-attached first-person
	# rig is suppressed. So the old "FP rig equals world arm + framing lift"
	# checks become: the separate rig is never shown, and the rig's own
	# wrist follows the shared target (rig space = body space + EYE_POINT) at
	# every pitch, with its watch inside the player's view where the shared
	# rule holds it in view.
	var tech: Node3D = _body.rigged_visual()
	_check("the rigged character is the visible body", tech != null and tech.body_mesh.is_visible_in_tree())
	var offs := []
	for deg in [-78.0, -60.0, -45.0, -30.0, 0.0, 30.0, 60.0]:
		await _set_pitch(deg)
		_check("at %d deg the separate first-person rig is NOT shown (single shared arm)" % int(deg), not _rig.visible)
		var tgt_body: Vector3 = _state.watch_target
		var wrist_rig: Vector3 = tech.bone_pos("RightHand")
		var expected_rig: Vector3 = tgt_body + tech.EYE_POINT
		if deg > 0.0:
			# Round 29: high holds are measured from the POSED eye (looking up
			# carries the eye back/down) and shaped by the clavicle shrug.
			var eye_posed: Vector3 = tech.bone_pos("Head") + tech.bone_basis("Head") * (tech.EYE_POINT - tech.rest_pos("Head"))
			_check("at %d deg the rig wrist is near the shared target from the posed eye (%.3f m)" % [int(deg), wrist_rig.distance_to(tgt_body + eye_posed)], wrist_rig.distance_to(tgt_body + eye_posed) < 0.15)
		elif tgt_body.y > -0.25:
			# High holds are swung out/forward on purpose (forearm across the
			# face, player_body.gd _update_rig) -- bounded offset.
			_check("at %d deg the rig wrist is at the (high-hold adjusted) shared target (%.3f m)" % [int(deg), wrist_rig.distance_to(expected_rig)], wrist_rig.distance_to(expected_rig) < 0.15)
		else:
			_check("at %d deg the rig wrist IS at the shared target (%.3f m)" % [int(deg), wrist_rig.distance_to(expected_rig)], wrist_rig.distance_to(expected_rig) < 0.01)
		var watch_face: Vector3 = tech.watch_face_node().global_position
		var local: Vector3 = _cam.global_transform.affine_inverse() * watch_face
		var off_centre: float = rad_to_deg(Vector3(0, 0, -1).angle_to(local.normalized()))
		# The shared hold reaches eye level at +24 deg (WATCH_LEVEL_ELEVATION_DEG
		# -24); beyond that the player looks above the held watch.
		if deg <= 0.0 and deg >= -60.0:
			_check("at %d deg the watch face is inside the view (%.0f deg off centre)" % [int(deg), off_centre], off_centre < 36.0 and local.z < 0.0)
		elif deg >= 30.0:
			_check("at %d deg the player looks above the held watch (%.0f deg below centre)" % [int(deg), off_centre], local.y < 0.0)
		if deg >= -30.0 and deg <= 0.0:
			offs.append(off_centre)
	_check("watch framing steady from 30 deg down to level while the arm follows 1:1 (spread %.1f deg)" % (offs.max() - offs.min()), offs.max() - offs.min() < 8.0)

	# ---- 6. Visibility isolation. ----
	var mirror_cam: Camera3D = _main.get_node("Mirrors/LivingQuartersMirror/Camera3D")
	_check("first-person rig (if ever shown) stays on layer 2, excluded from the mirror", (_rig.get_node("ArmGroup") as VisualInstance3D).layers == 2 and mirror_cam.cull_mask & 2 == 0)
	_check("rig body (torso/arms/hands/legs) is seen by BOTH the player and the mirror", (tech.body_mesh.layers & _cam.cull_mask) != 0 and (tech.body_mesh.layers & mirror_cam.cull_mask) != 0)
	_check("rig head is mirror-only (the eye is inside it)", tech.head_mesh.layers == 4 and (_cam.cull_mask & 4) == 0 and (mirror_cam.cull_mask & 4) != 0)
	_check("legacy CSG visuals are not rendered (no duplicate body)", not _sp.get_node("Chest").is_visible_in_tree() and not (_sp.get_node("ArmMeshR") as Node3D).is_visible_in_tree())

	# ---- 7. Release while the look sweeps: no snap, monotonic. ----
	_key_c(false)
	var last: float = _body.watch_raise_progress()
	var mono := true
	# Real time (0.8s > the world arm's 0.42s lowering), not a frame count:
	# headless frames can be milliseconds.
	var t_end: int = Time.get_ticks_msec() + 800
	var step := 0
	while Time.get_ticks_msec() < t_end:
		_look._target_pitch = deg_to_rad(clampf(-60.0 + step * 2.0, -60.0, 30.0))
		step += 1
		await process_frame
		var cur: float = _body.watch_raise_progress()
		if cur > last + 0.0001:
			mono = false
			print("  non-monotonic at step %d: %.5f -> %.5f (rig raised=%s)" % [step, last, cur, str(_rig.is_raised())])
		last = cur
	_check("release while the look changes lowers monotonically to rest (end %.2f)" % last, mono and is_equal_approx(last, 0.0))
	await _set_pitch(0.0)
	for i in 10: await process_frame
	_check("first-person rig never shown after release either", not _rig.visible)

	# ---- 8. Sitting / lying. ----
	_body.set_sitting(true)
	await process_frame
	await process_frame
	_check("pose state reports SITTING", _state.posture == PoseState.Posture.SITTING)
	_check("watch target ignores look pitch while sitting", _state.watch_target.is_equal_approx(PoseState.watch_target_for_pitch(0.0)))
	_check("head pivots neutral while sitting (head group hidden)", is_equal_approx(_body.get_node("HeadGroup/NeckPivot").rotation.x, 0.0))
	_body.set_sitting(false)
	_body.set_lying(true)
	await process_frame
	await process_frame
	_check("pose state reports LYING", _state.posture == PoseState.Posture.LYING)
	_body.set_lying(false)
	await process_frame
	_check("back to STANDING", _state.posture == PoseState.Posture.STANDING)

	# ---- 9. Replicable form drives the Skeleton3D prototype (no camera). ----
	var proto: Node3D = (load("res://scenes/dev/rigged_technician_prototype.tscn") as PackedScene).instantiate()
	get_root().add_child(proto)
	await process_frame
	var remote: Node = PoseState.new()
	get_root().add_child(remote)
	remote.from_dict({"yaw": 0.0, "pitch": deg_to_rad(-45.0), "watch": 1.0, "posture": PoseState.Posture.STANDING})
	_check("replicated state derives the same joint angles as the local one", is_equal_approx(remote.neck_pitch, PoseState.distribute_look_pitch(deg_to_rad(-45.0), 0)["neck"]))
	proto.apply_pose_state(remote.to_dict())
	var fwd_down: Vector3 = proto.head_forward()
	var hand_raised: Vector3 = proto.bone_global_position("RightHand")
	proto.apply_pose_state({"pitch": deg_to_rad(30.0), "watch": 1.0, "posture": 0})
	var fwd_up: Vector3 = proto.head_forward()
	_check("prototype skeleton head looks down/up from the shared data (y %.2f / %.2f)" % [fwd_down.y, fwd_up.y], fwd_down.y < -0.5 and fwd_up.y > 0.3)
	_check("prototype raises its watch arm from the shared data", hand_raised.y > 1.1)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _set_pitch(deg: float) -> void:
	_look._target_pitch = deg_to_rad(deg)
	_pitch.rotation.x = deg_to_rad(deg)
	await process_frame
	await process_frame


## World head pitch (deg, + up) read from the actual HeadPivot transform.
func _head_pitch_deg() -> float:
	var hp: Node3D = _body.get_node("HeadGroup/NeckPivot/HeadPivot")
	var fwd: Vector3 = _body.global_transform.basis.inverse() * (hp.global_transform.basis * Vector3(0, 0, -1))
	return rad_to_deg(asin(clampf(fwd.normalized().y, -1.0, 1.0)))


## First-person rig sample points inside the world body's visible-to-anyone
## StandingPose primitives (anchors included -- they mark the real torso).
func _rig_torso_hits() -> int:
	var prims: Array = []
	for c in _sp.get_children():
		if c is CSGShape3D and c.name in ["Chest", "TrapeziusBase", "ChestYoke", "ShoulderL", "ShoulderR", "TorsoBridgeUpper", "Waist"]:
			prims.append(c)
	var n := 0
	for v in _rig.find_children("*", "VisualInstance3D", true, false):
		if not (v as Node3D).is_visible_in_tree():
			continue
		var aabb: AABB = v.get_aabb()
		for p in [aabb.get_center(), aabb.position + aabb.size * 0.25, aabb.end - aabb.size * 0.25]:
			var gp: Vector3 = v.global_transform * p
			for prim in prims:
				var lp: Vector3 = prim.global_transform.affine_inverse() * gp
				var inside := false
				if prim is CSGSphere3D:
					inside = lp.length() < prim.radius
				elif prim is CSGCylinder3D:
					inside = absf(lp.y) < prim.height * 0.5 and Vector2(lp.x, lp.z).length() < prim.radius
				if inside:
					n += 1
					break
	return n


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
