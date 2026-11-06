extends SceneTree
## Round 29 Priority 3 + 4 regression.
##
## P4 ROOT CAUSE: CharacterPoseState clamped the watch elevation at eye
## level, so above ~24 deg up the target became "eye height, ~0.33m
## straight ahead" -- ~0.53m from the shoulder for a 0.565m arm: a locked,
## nearly straight arm reaching forward (measured 39 deg elbow flexion at
## 35 deg up). Now the watch keeps rising (capped where the forearm would
## otherwise go overhead), the reading distance follows the arm's reach,
## the clavicle shrugs/protracts and the wrist relaxes forward, so the
## elbow stays bent ~80 deg all the way to 70 deg up. At/below a level look
## the pose is EXACTLY Round 28's (approved downward watch check).
##
## P3 ROOT CAUSE: technician_rig.gd's _ellipsoid() was wound opposite to
## _loft(), so every ellipsoid (helmet, chin, visor, shoulder deltoids)
## rendered inside-out -- back faces only: a featureless glossy black ball
## for a head and dark holes on the shoulders. Checked here via the built
## mesh's normals.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame
	var player: Node3D = main.get_node("Player")
	var body: Node3D = player.get_node("PlayerBody")
	var lp: Node3D = player.get_node("LookPivot")
	var cam: Camera3D = lp.get_node("PitchPivot/Camera3D")
	var rig: Node3D = body.rigged_visual()
	var ps_script = load("res://scripts/player/character_pose_state.gd")
	main.get_node("FreeMoveBody").set_active(false)

	# ---- Downward / level: the shared target is byte-for-byte Round 28's. ----
	var max_err := 0.0
	for deg in range(-85, 1, 5):
		var p: float = deg_to_rad(deg)
		max_err = maxf(max_err, ps_script.watch_target_for_pitch(p).distance_to(_r28_target(p)))
	_check("pitch <= 0: shared watch target identical to Round 28 (max err %.6f m)" % max_err, max_err < 1e-6)

	body.set_watch_raise_pose(true, 0.0)
	for deg in [-80.0, -60.0, -30.0, 0.0]:
		_set_pitch(lp, deg)
		for i in 6: await process_frame
		var lift: float = rig.get_local("RightShoulder").get_angle()
		_check("pitch %d: Round 28 path (no clavicle shrug, %.2f deg)" % [deg, rad_to_deg(lift)], lift < deg_to_rad(0.5))

	# ---- Upward: bent elbow, clavicle helps, face toward the eye, in view. ----
	for deg in [20.0, 35.0, 45.0, 60.0, 70.0]:
		_set_pitch(lp, deg)
		for i in 6: await process_frame
		var s: Vector3 = rig.bone_pos("RightUpperArm")
		var e: Vector3 = rig.bone_pos("RightLowerArm")
		var w: Vector3 = rig.bone_pos("RightHand")
		var flex: float = 180.0 - rad_to_deg((s - e).angle_to(w - e))
		_check("up %d: elbow meaningfully bent (%.0f deg flexion, was 39 at 35 up)" % [deg, flex], flex > 60.0)
		_check("up %d: wrist well within reach (%.3f m of 0.565)" % [deg, s.distance_to(w)], s.distance_to(w) < 0.47)
		if deg >= 35.0:
			_check("up %d: clavicle shrugs/protracts to help lift" % deg, rig.get_local("RightShoulder").get_angle() > deg_to_rad(8.0))
		var face: Node3D = rig.watch_face_node()
		var n: Vector3 = face.global_basis.y.normalized()
		var to_eye: Vector3 = (cam.global_position - face.global_position).normalized()
		_check("up %d: dial faces the eye (%.2f)" % [deg, n.dot(to_eye)], n.dot(to_eye) > 0.9)
		var off: float = rad_to_deg((-cam.global_basis.z).angle_to(face.global_position - cam.global_position))
		if deg <= 56.0:
			_check("up %d: watch in view (%.0f deg below centre, half-fov %.0f)" % [deg, off, cam.fov * 0.5], off < cam.fov * 0.5 - 2.0)
		_check("up %d: watch never behind/inside the face (%.2f m)" % [deg, face.global_position.distance_to(cam.global_position)], face.global_position.distance_to(cam.global_position) > 0.15)
	body.set_watch_raise_pose(false, 0.0)

	# ---- P3: helmet/visor surfaces face OUTWARD (winding fix). ----
	var arrays: Array = rig.head_mesh.mesh.surface_get_arrays(0)   # helmet surface
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var centre := Vector3(0, 1.6, -0.02)
	var outward := 0
	for i in verts.size():
		if norms[i].dot(verts[i] - centre) > 0.0:
			outward += 1
	_check("helmet normals face outward (%d/%d)" % [outward, verts.size()], outward > verts.size() * 0.9)
	_check("helmet is a matte grey shell, not black gloss", (rig._mats["helmet"] as StandardMaterial3D).albedo_color.v > 0.2 and (rig._mats["helmet"] as StandardMaterial3D).roughness >= 0.5)

	# ---- P3: head/neck bone positions stay human across the look range. ----
	for deg in [-80.0, -40.0, 0.0, 40.0, 70.0]:
		_set_pitch(lp, deg)
		for i in 6: await process_frame
		var head: Vector3 = rig.bone_pos("Head")
		var neck: Vector3 = rig.bone_pos("Neck")
		var chest: Vector3 = rig.bone_pos("UpperChest")
		_check("look %d: head stays above the neck base (%.3f > %.3f)" % [deg, head.y, neck.y], head.y > neck.y + 0.03)
		_check("look %d: neck flexion within anatomical limits (%.0f deg)" % [deg, rad_to_deg(rig.get_local("Neck").get_angle())], rig.get_local("Neck").get_angle() <= deg_to_rad(45.5))
		_check("look %d: head never sinks into the chest (head %.3fm above upper chest)" % [deg, head.y - chest.y], head.y - chest.y > 0.15)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


## Verbatim Round 28 watch_target_for_pitch() (pitch <= 0 branch).
func _r28_target(pitch: float) -> Vector3:
	var e: float = clampf(pitch + deg_to_rad(-24.0), deg_to_rad(-52.0), deg_to_rad(0.0))
	var e_deg: float = rad_to_deg(e)
	var d: float = 0.35
	if e_deg < -30.0:
		d += 0.06 * clampf((-e_deg - 30.0) / 22.0, 0.0, 1.0)
	elif e_deg > -10.0:
		d -= 0.02 * clampf((e_deg + 10.0) / 10.0, 0.0, 1.0)
	return Vector3(0.04, d * sin(e), -d * cos(e))


func _set_pitch(lp: Node3D, deg: float) -> void:
	lp._target_pitch = deg_to_rad(deg)
	lp.get_node("PitchPivot").rotation.x = deg_to_rad(deg)


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
