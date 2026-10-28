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
	# 4. THE ACTUAL COMPOSITION INVARIANT: sweep the whole reachable
	# downward pitch range (0 to -pitch_limit_degrees) and confirm no
	# near body part's angular position ever approaches frame-center.
	# At pitch 0 (looking at the horizon) nothing should be visible at
	# all (not even near the FOV edge). At the steepest reachable
	# pitch, the nearest part must still sit meaningfully off-center,
	# not dead in the middle of the view.
	# ============================================================
	var half_fov_deg: float = camera.fov / 2.0
	var limit_deg: float = look_pivot.pitch_limit_degrees
	var min_angle_seen: float = 9999.0
	var visible_at_level: bool = false

	var p: float = 0.0
	while p >= -limit_deg:
		pitch_pivot.rotation.x = deg_to_rad(p)
		await process_frame # let player_body._process() apply standing_pitch_follow
		var forward: Vector3 = -camera.global_transform.basis.z
		for part_name in ["ShoulderL", "ShoulderR", "Chest"]:
			var part: Node3D = standing_pose.get_node(part_name)
			var to_part: Vector3 = (part.global_position - camera.global_position)
			if to_part.length() < 0.001:
				continue
			var ang_deg: float = rad_to_deg(forward.angle_to(to_part.normalized()))
			if p == 0.0 and ang_deg <= half_fov_deg:
				visible_at_level = true
			if ang_deg < min_angle_seen:
				min_angle_seen = ang_deg
		p -= 2.0

	_check("composition: nothing is visible at all when looking at the horizon (pitch 0)", not visible_at_level)
	_check("composition: no near body part ever gets close to frame-center across the WHOLE reachable downward pitch sweep (min angle-to-forward seen = %.1f deg, want > 10 deg out of a %.0f deg half-FOV)" % [min_angle_seen, half_fov_deg], min_angle_seen > 10.0)

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
