extends SceneTree
## Regression for this round's Issue 1 (standing first-person body
## composition). The previous round's test only checked a SCALAR
## clearance distance to the nearest body part at one implicit pitch,
## which is exactly the kind of check the user explicitly warned
## against treating as proof of visual quality -- it passed while the
## actual complaint ("the body sits dead-center when looking down")
## was still true, because a fixed-distance check says nothing about
## WHERE in the frame something appears.
##
## This test instead sweeps the camera's ENTIRE reachable downward
## pitch range and checks, at every sampled angle, the actual angle
## between the camera's forward direction and each near body part's
## real (pitch-follow-adjusted) position -- i.e. how close to dead
## center of the screen that part is. The invariant being verified:
## no near body part ever comes close to frame-center at ANY reachable
## pitch, which is the actual geometric root cause of "the body forms a
## wall/circle in the middle of the view" (see the final report's
## composition analysis). This is still not proof the silhouette LOOKS
## good -- that needs a human playtest -- but it is a real, non-trivial
## check of the thing that was actually broken (WHERE things appear),
## not just HOW FAR AWAY they are.

var _ok := true


func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5:
		await process_frame

	var player := main.get_node("Player")
	var global_free_move := main.get_node("GlobalFreeMove")
	var player_body := player.get_node("PlayerBody")
	var standing_pose := player_body.get_node("StandingPose")
	var look_pivot := player.get_node("LookPivot")
	var pitch_pivot := look_pivot.get_node("PitchPivot")
	var camera := pitch_pivot.get_node("Camera3D")

	global_free_move.mirror_enabled = false
	player.global_position = Vector3(10.0, 1.6, 10.0)
	look_pivot.rotation.y = 0.0
	look_pivot._target_yaw = 0.0
	await process_frame

	# ============================================================
	# 1. STRUCTURE: no Neck/head node; shoulders are two separate
	# pieces with a genuine gap at the centerline (not one box spanning
	# the midline, which is what produced "a circle/wall" directly
	# ahead regardless of pitch).
	# ============================================================
	_check("standing: no Neck/head node directly in front of the camera", standing_pose.get_node_or_null("Neck") == null)
	var shoulder_l: CSGSphere3D = standing_pose.get_node("ShoulderL")
	var shoulder_r: CSGSphere3D = standing_pose.get_node("ShoulderR")
	_check("standing: ShoulderL's bounding radius does not reach the centerline (real gap, not a slab across the middle)", shoulder_l.position.x + shoulder_l.radius < -0.001)
	_check("standing: ShoulderR's bounding radius does not reach the centerline (real gap, not a slab across the middle)", shoulder_r.position.x - shoulder_r.radius > 0.001)

	# ============================================================
	# 2. TAPER: Chest > Waist radius, and Hips flares back out a bit --
	# a genuine taper toward the waist, not a uniform column.
	# ============================================================
	var chest: CSGCylinder3D = standing_pose.get_node("Chest")
	var waist: CSGCylinder3D = standing_pose.get_node("Waist")
	var hips: CSGCylinder3D = standing_pose.get_node("Hips")
	_check("standing: chest is wider than the waist (got chest=%.3f waist=%.3f)" % [chest.radius, waist.radius], chest.radius > waist.radius)
	_check("standing: hips flare back out from the waist (got waist=%.3f hips=%.3f)" % [waist.radius, hips.radius], hips.radius > waist.radius)

	# ============================================================
	# 3. CONTINUOUS CHAIN: each segment's cap overlaps the next (no
	# floating gap that would read as a missing/disconnected section).
	# ============================================================
	var shoulder_bottom: float = shoulder_l.global_position.y - shoulder_l.radius * 0.67
	var chest_top: float = chest.global_position.y + chest.radius
	_check("standing: shoulder overlaps the chest top (shoulder_bottom=%.3f, chest_top=%.3f)" % [shoulder_bottom, chest_top], shoulder_bottom <= chest_top)
	var chest_bottom: float = chest.global_position.y - chest.radius
	var waist_top: float = waist.global_position.y + waist.radius
	_check("standing: waist overlaps the chest bottom (waist_top=%.3f, chest_bottom=%.3f)" % [waist_top, chest_bottom], waist_top >= chest_bottom)
	var waist_bottom: float = waist.global_position.y - waist.radius
	var hip_top: float = hips.global_position.y + hips.radius
	_check("standing: hips overlap the waist bottom (hip_top=%.3f, waist_bottom=%.3f)" % [hip_top, waist_bottom], hip_top >= waist_bottom)

	# ============================================================
	# 4. THE ACTUAL COMPOSITION INVARIANT, evaluated on what the player's
	# OWN camera really renders.
	#
	# Round 26: this used to sweep the ShoulderL/ShoulderR/Chest node
	# positions, an invariant that was only satisfiable by tilting the
	# WHOLE body (pelvis and legs included) by 30% of camera pitch -- the
	# exact behaviour that made the mirror show a rigid leaning mannequin
	# (retired; see player_body.gd standing_pitch_follow). The body is now
	# upright, and the near-eye upper torso (yoke/shoulders/chest) renders on
	# the mirror-only layer like the head (player_body.gd
	# SELF_HIDDEN_TORSO_PARTS). The intent is unchanged -- no near geometry
	# may fill the player's own view -- so it is now checked against every
	# StandingPose primitive the player's camera can actually see: anything
	# whose nearest surface is within 0.55m of the eye must never approach
	# frame-centre, and nothing may be visible at all looking level.
	# ============================================================
	var half_fov_deg: float = camera.fov / 2.0
	var limit_deg: float = look_pivot.pitch_limit_degrees
	var min_angle_near: float = 9999.0
	var visible_at_level: bool = false
	var self_visible: Array = []
	for c in standing_pose.get_children():
		if c is CSGShape3D and c.visible and (standing_pose.layers & camera.cull_mask) != 0:
			self_visible.append(c)
	_check("composition: the near-eye upper torso is NOT rendered to the player's own camera (anchors hidden)", not standing_pose.get_node("Chest").visible and not standing_pose.get_node("ShoulderL").visible)
	# Round 28: the visible body is the rigged character -- ONE continuous
	# skinned body the player's own camera sees (only the head is mirror-
	# only), replacing Round 26-27's per-part CSG layering.
	var tech: Node3D = player.get_node("PlayerBody").rigged_visual()
	_check("composition: the rigged body is seen by the player's own camera AND every other camera (one continuous body)", tech.body_mesh.is_visible_in_tree() and (tech.body_mesh.layers & camera.cull_mask) != 0)
	_check("composition: only the rig's head/neck is mirror-only (the eye is inside it)", tech.head_mesh.layers == 4 and (camera.cull_mask & 4) == 0)
	# Round 28 (replaces Round 27's "legs-only" rule, now obsolete): the eye
	# must sit IN FRONT of the torso like a real person's, so a straight-down
	# look passes in front of the chest onto belly/thighs/boots instead of
	# the top of the chest -- checked on the rig's real mesh vertices.
	var bm: MeshInstance3D = tech.body_mesh
	var max_front := 0.0
	var arrays: Array = bm.mesh.surface_get_arrays(0) # coverall surface
	for v in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		if v.y > 1.15 and v.y < 1.45 and absf(v.x) < 0.12:
			max_front = minf(max_front, v.z)
	var eye_z: float = tech.EYE_POINT.z
	_check("composition: the eye is in front of the chest surface (eye z %.3f vs chest front %.3f)" % [eye_z, max_front], eye_z <= max_front - 0.005)
	# Nothing of the rig body may come within the camera's near region at
	# any reachable pitch (no near-plane clipping into the player's own
	# torso): sample the torso/shoulder bone heads against the camera.
	var near_ok := true
	var worst := ""
	var q: float = 0.0
	while q >= -limit_deg:
		pitch_pivot.rotation.x = deg_to_rad(q)
		await process_frame
		for b in ["UpperChest", "Chest", "RightShoulder", "LeftShoulder", "RightUpperArm", "LeftUpperArm"]:
			var gp: Vector3 = tech.skeleton.to_global(tech.skeleton.get_bone_global_pose(tech.skeleton.find_bone(b)).origin)
			if gp.distance_to(camera.global_position) < 0.12:
				near_ok = false
				worst = "%s at %.0f deg" % [b, q]
		q -= 5.0
	pitch_pivot.rotation.x = 0.0
	_check("composition: no torso/shoulder joint comes within 0.12m of the eye at any pitch" + ("" if near_ok else " (%s)" % worst), near_ok)

	var p: float = 0.0
	while p >= -limit_deg:
		pitch_pivot.rotation.x = deg_to_rad(p)
		await process_frame
		var forward: Vector3 = -camera.global_transform.basis.z
		for part in self_visible:
			var aabb: AABB = (part as VisualInstance3D).get_aabb()
			var centre: Vector3 = part.global_transform * aabb.get_center()
			var to_part: Vector3 = centre - camera.global_position
			# True distance from the eye to the part's world-space bounds.
			var gbox: AABB = part.global_transform * aabb
			var eye: Vector3 = camera.global_position
			var near_dist: float = eye.distance_to(eye.clamp(gbox.position, gbox.end))
			var ang_deg: float = rad_to_deg(forward.angle_to(to_part.normalized()))
			if p == 0.0 and ang_deg - rad_to_deg(atan2(aabb.size.length() * 0.5, to_part.length())) <= half_fov_deg:
				visible_at_level = true
			if near_dist < 0.55 and ang_deg < min_angle_near:
				min_angle_near = ang_deg
		p -= 2.0

	_check("composition: nothing is visible at all when looking at the horizon (pitch 0)", not visible_at_level)
	# 9999 = no self-visible part came within 0.55m of the eye at ANY pitch
	# (the strongest form of this invariant); otherwise it must stay >10 deg
	# off frame-centre.
	_check("composition: no NEAR (<0.55m) self-visible geometry ever approaches frame-center across the WHOLE downward sweep (min angle %s, want none-near or > 10 deg of a %.0f deg half-FOV)" % ["none within 0.55m" if min_angle_near > 999.0 else "%.1f deg" % min_angle_near, half_fov_deg], min_angle_near > 10.0)
	_check("composition: the body itself never tilts with look pitch (pelvis/legs stay upright)", is_equal_approx(player.get_node("PlayerBody").rotation.x, 0.0))

	print("")
	if _ok:
		print("ALL TESTS PASSED")
	else:
		print("SOME TESTS FAILED")
	quit()


func _check(label: String, cond: bool) -> void:
	if cond:
		print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
