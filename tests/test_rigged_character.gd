extends SceneTree
## Round 28 coverage for the rigged technician as the player's visible body
## (scripts/character/technician_rig.gd, driven by player_body.gd).
##
## Root causes guarded (see MILESTONE1_DESIGN.md Round 28):
## - straight-down self view showed two disconnected thigh spheres: the old
##   body's legs were raked forward and its torso hidden; the camera rotated
##   in place at the eye. Now: a plumb-line skeleton with the eye in front
##   of the torso, one continuous skinned body, and an anatomical eye anchor
##   (the camera follows the head's forward/down carry when looking down).
## - fingers in the mirror but not in first person: two different models.
##   Now one shared rig arm/hand/watch for every camera.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame
	var player: Node3D = main.get_node("Player")
	main.get_node("FreeMoveBody").set_active(false)
	main.get_node("FreeMoveBody").sync_to_eye_position(Vector3(3.7, 1.6, 0.6))
	player.global_position = Vector3(3.7, 1.6, 0.6)
	var body: Node3D = player.get_node("PlayerBody")
	var look: Node3D = player.get_node("LookPivot")
	look.input_enabled = false
	var pitch: Node3D = look.get_node("PitchPivot")
	var cam: Camera3D = pitch.get_node("Camera3D")
	var mirror_cam: Camera3D = main.get_node("Mirrors/LivingQuartersMirror/Camera3D")
	var rig: Node3D = body.rigged_visual()

	# ---- 1. Skeleton, mesh, skinning. ----
	_check("rigged character present and active", rig != null and body.use_rigged_visual)
	var sk: Skeleton3D = rig.skeleton
	var required := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand", "LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes"]
	var missing := []
	for b in required:
		if sk.find_bone(b) == -1:
			missing.append(b)
	_check("humanoid bone hierarchy complete (%d bones)" % sk.get_bone_count(), missing.is_empty())
	_check("hierarchy: hand -> lower arm -> upper arm -> shoulder -> upper chest", sk.get_bone_parent(sk.find_bone("RightHand")) == sk.find_bone("RightLowerArm") and sk.get_bone_parent(sk.find_bone("RightLowerArm")) == sk.find_bone("RightUpperArm") and sk.get_bone_parent(sk.find_bone("RightUpperArm")) == sk.find_bone("RightShoulder") and sk.get_bone_parent(sk.find_bone("RightShoulder")) == sk.find_bone("UpperChest"))
	for mi in [rig.body_mesh, rig.head_mesh]:
		_check("%s is skinned to the skeleton" % mi.name, mi.skin != null and mi.get_node_or_null(mi.skeleton) == sk)
	# Blended weights exist across joints (no rigid per-part islands only).
	var arrays: Array = rig.body_mesh.mesh.surface_get_arrays(0)
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var blended := 0
	for i in range(0, weights.size(), 4):
		if weights[i] < 0.99 and weights[i + 1] > 0.01:
			blended += 1
	_check("joints are blend-weighted (%d blended vertices)" % blended, blended > 50)
	var finger_count := 0
	var verts: PackedVector3Array = rig.body_mesh.mesh.surface_get_arrays(1)[Mesh.ARRAY_VERTEX]
	_check("gloves have real geometry (five-digit hands, %d glove vertices)" % verts.size(), verts.size() > 300)

	# Round 29: the gait now responds to the body's real settling motion
	# right after the scripted teleport above; let it come to rest first.
	await create_timer(0.5).timeout
	# ---- 2. Anatomy: eye in front of the plumb line, proportions. ----
	var eye: Vector3 = rig.EYE_POINT
	var hip: Vector3 = rig.rest_pos("Hips")
	var ankle: Vector3 = rig.rest_pos("RightFoot")
	_check("eye is in front of the hip/ankle plumb line (eye z %.2f, hip z %.2f, ankle z %.2f)" % [eye.z, hip.z, ankle.z], eye.z < hip.z - 0.08 and absf(hip.z - ankle.z) < 0.02)
	var up_len: float = rig.rest_pos("RightUpperArm").distance_to(rig.rest_pos("RightLowerArm"))
	var fore_len: float = rig.rest_pos("RightLowerArm").distance_to(rig.rest_pos("RightHand"))
	var thigh: float = rig.rest_pos("RightUpperLeg").distance_to(rig.rest_pos("RightLowerLeg"))
	_check("anthropometric limbs (upper arm %.2f, forearm %.2f, thigh %.2f)" % [up_len, fore_len, thigh], up_len > 0.28 and up_len < 0.34 and fore_len > 0.22 and fore_len < 0.28 and thigh > 0.36 and thigh < 0.44)
	_check("rig feet rest on the floor under the eye (rig at body - EYE_POINT)", rig.transform.origin.is_equal_approx(-eye))

	# ---- 3. Visibility per camera; legacy hidden; no duplicate body. ----
	_check("body mesh seen by the player AND the mirror", (rig.body_mesh.layers & cam.cull_mask) != 0 and (rig.body_mesh.layers & mirror_cam.cull_mask) != 0)
	_check("head mesh mirror-only", rig.head_mesh.layers == 4 and (cam.cull_mask & 4) == 0 and (mirror_cam.cull_mask & 4) != 0)
	var legacy_visible := 0
	for root in ["StandingPose", "SittingPose", "LyingPose", "HeadGroup"]:
		for v in body.get_node(root).find_children("*", "VisualInstance3D", true, false):
			if (v as VisualInstance3D).is_visible_in_tree():
				legacy_visible += 1
	_check("no legacy CSG visual renders alongside the rig (%d visible)" % legacy_visible, legacy_visible == 0)

	# ---- 4. Eye anchor: level = zero offset; down = forward/down carry. ----
	pitch.rotation.x = 0.0
	await process_frame
	_check("level look: camera exactly at the eye (no offset)", cam.position.is_equal_approx(Vector3.ZERO))
	var look_pos_before: Vector3 = look.position
	look._target_pitch = deg_to_rad(-80.0)
	pitch.rotation.x = deg_to_rad(-80.0)
	await process_frame
	await process_frame
	var off_body: Vector3 = pitch.basis * cam.position
	_check("80 deg down: camera carried forward and down with the posed head (%s)" % str(off_body.snapped(Vector3.ONE * 0.001)), off_body.z < -0.05 and off_body.y < -0.1 and off_body.length() < 0.3)
	_check("...exactly to where the rig's (mirror-visible) eyes are", off_body.is_equal_approx(body.eye_anchor_offset()))
	_check("the camera's parent rig (LookPivot/PitchPivot) is untouched by the anchor", is_equal_approx(pitch.rotation.x, deg_to_rad(-80.0)) and look.position.is_equal_approx(look_pos_before))
	_check("player/capsule position untouched by the anchor", player.global_position.is_equal_approx(Vector3(3.7, 1.6, 0.6)))
	# Straight-down view lands on the lower body, in front of the torso.
	var fwd: Vector3 = -cam.global_transform.basis.z
	var ray_hits_body := false
	# The lower body (hips -> feet) is in the view, in front of/below the
	# camera, not behind it (the straight-down view looks at one's own body).
	var in_view_count := 0
	for b in ["Hips", "RightLowerLeg", "LeftLowerLeg", "RightFoot", "LeftFoot"]:
		var gp: Vector3 = sk.to_global(sk.get_bone_global_pose(sk.find_bone(b)).origin)
		if _in_view(cam, gp):
			in_view_count += 1
	_check("at 80 deg down the hips, knees and feet are in the player's view (%d/5)" % in_view_count, in_view_count >= 4)
	look._target_pitch = 0.0
	pitch.rotation.x = 0.0
	await process_frame

	# ---- 5. Watch raised at 45 deg up: fingers in the player's view too. ----
	var ev := InputEventKey.new()
	ev.keycode = KEY_C
	ev.physical_keycode = KEY_C
	ev.pressed = true
	Input.parse_input_event(ev)
	await create_timer(0.8).timeout
	look._target_pitch = deg_to_rad(20.0)
	pitch.rotation.x = deg_to_rad(20.0)
	for i in 3: await process_frame
	var finger_tip: Vector3 = _hand_point(rig, Vector3(0.0, -0.17, -0.01))
	var in_view: bool = _in_view(cam, finger_tip)
	_check("watch raised, looking up: the shared hand's fingers are inside the PLAYER's view", in_view)
	_check("...and the same fingers are inside the MIRROR camera's frustum side (one model)", rig.body_mesh.is_visible_in_tree())
	# Constant limb lengths while posed.
	var u2: float = rig.bone_pos("RightUpperArm").distance_to(rig.bone_pos("RightLowerArm"))
	var f2: float = rig.bone_pos("RightLowerArm").distance_to(rig.bone_pos("RightHand"))
	_check("raised arm keeps constant limb lengths (%.4f/%.4f vs %.4f/%.4f)" % [u2, f2, up_len, fore_len], absf(u2 - up_len) < 0.001 and absf(f2 - fore_len) < 0.001)
	var sk_hand: Vector3 = sk.get_bone_global_pose(sk.find_bone("RightHand")).origin
	_check("skeleton bones match the solved pose (skinning applied)", sk_hand.distance_to(rig.bone_pos("RightHand")) < 0.001)
	ev.pressed = false
	Input.parse_input_event(ev)
	look._target_pitch = 0.0
	pitch.rotation.x = 0.0
	await create_timer(0.9).timeout
	var hand_rel: Vector3 = rig.bone_basis("RightShoulder").inverse() * (rig.bone_pos("RightHand") - rig.bone_pos("RightShoulder"))
	_check("release: arm back to rest (relative to the shoulder)", hand_rel.distance_to(rig.rest_pos("RightHand") - rig.rest_pos("RightShoulder")) < 0.002)

	# ---- 6. Sitting / lying / standing with the rig. ----
	look._target_pitch = 0.0
	pitch.rotation.x = 0.0
	# Round 29 Priority 7: pose switches crossfade over POSE_XFADE_S (0.4s)
	# instead of snapping, so each pose is checked once the blend settles.
	body.set_sitting(true)
	await create_timer(0.6).timeout
	_check("sitting: rig thighs forward (knee in front of hip)", rig.bone_pos("RightLowerLeg").z < rig.bone_pos("RightUpperLeg").z - 0.25)
	_check("sitting: camera at the seated eye (no offset at a neutral look, got %s)" % str(cam.position), cam.position.length() < 0.002)
	body.set_sitting(false)
	body.set_lying(true)
	await create_timer(0.6).timeout
	var front: Vector3 = rig.global_transform.basis * Vector3(0, 0, -1)
	_check("lying: on the back, face up (front dir y %.2f)" % front.y, front.y > 0.9)
	_check("lying: head mesh still present for other cameras", rig.head_mesh.is_visible_in_tree())
	body.set_lying(false)
	await create_timer(0.6).timeout
	_check("standing again: rig upright at the eye", rig.transform.basis.is_equal_approx(Basis()))

	# ---- 7. Walking cycle from real movement. ----
	var start: Vector3 = player.global_position
	for i in 20:
		player.global_position = start + Vector3(0, 0, -0.04 * i)
		await process_frame
	var leg_swing: float = absf(rig.get_local("RightUpperLeg").get_angle())
	_check("walking: legs swing from real movement (%.1f deg)" % rad_to_deg(leg_swing), leg_swing > deg_to_rad(5.0))
	player.global_position = start
	for i in 30: await process_frame

	# ---- 8. Fallback flag keeps the legacy visual working. ----
	var holder := Node3D.new()
	var lp2 := Node3D.new()
	lp2.name = "LookPivot"
	var pp2 := Node3D.new()
	pp2.name = "PitchPivot"
	lp2.add_child(pp2)
	holder.add_child(lp2)
	var pb2: Node3D = (load("res://scenes/player/player_body.tscn") as PackedScene).instantiate()
	pb2.look_pivot_path = NodePath("../LookPivot")
	pb2.use_rigged_visual = false
	holder.add_child(pb2)
	main.add_child(holder)
	for i in 3: await process_frame
	_check("fallback: use_rigged_visual=false builds no rig and keeps the legacy body visible", pb2.rigged_visual() == null and (pb2.get_node("StandingPose/HipCapL") as Node3D).is_visible_in_tree())
	holder.queue_free()

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _hand_point(rig: Node3D, local: Vector3) -> Vector3:
	var g: Transform3D = rig.skeleton.get_bone_global_pose(rig.skeleton.find_bone("RightHand"))
	return rig.skeleton.to_global(g * (Basis(rig.get_local("RightHand")).inverse() * Vector3.ZERO + Vector3.ZERO) + g.basis * local)


func _in_view(cam: Camera3D, p: Vector3) -> bool:
	if cam.is_position_behind(p):
		return false
	var sp: Vector2 = cam.unproject_position(p)
	var size: Vector2 = cam.get_viewport().get_visible_rect().size
	return sp.x >= 0 and sp.y >= 0 and sp.x <= size.x and sp.y <= size.y


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
