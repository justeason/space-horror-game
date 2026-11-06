extends SceneTree
## Round 30 Priority 2 regression: the laptop on the bed sits ON the lap.
##
## ROOT CAUSE (rendered + measured): after Round 29's reclined bed pose, the
## rig's pelvis sits ~10 cm forward of the legacy hip anchor while the legs
## still IK'd to the legacy ankle anchors, folding the knees UP; the laptop
## stayed on the fixed legacy LapAnchor -- now BETWEEN/under the thighs, with
## the raised knees standing in front of the screen (in the editing view
## they covered most of it). Now on the bunk the legs lie out along the
## mattress, LapAnchor rides on top of the actual thighs, and the hands rest
## on the keyboard while it is open. The workstation chair is unchanged.
var _ok := true
var rig: Node3D
var cam: Camera3D

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame
	var player: Node3D = main.get_node("Player")
	var body: Node3D = player.get_node("PlayerBody")
	var ss: Node = main.get_node("SleepState")
	var lv: Node = player.get_node("LaptopView")
	var laptop: Node3D = main.get_node("Interactables/BunksideLaptop")
	var lap_anchor: Node3D = body.get_node("LapAnchor")
	cam = player.get_node("LookPivot/PitchPivot/Camera3D")
	rig = body.rigged_visual()
	var authored_lap: Vector3 = lap_anchor.position
	main.get_node("FreeMoveBody").sync_to_eye_position(Vector3(4.0, 1.6, -0.3))
	player.global_position = Vector3(4.0, 1.6, -0.3)
	for i in 10: await physics_frame

	ss.begin_sitting()
	await create_timer(1.6).timeout
	_check("seated on the bunk (bed seat style)", ss.is_sitting() and body.seated_on_bed)
	var hip: Vector3 = rig.to_global(rig.bone_pos("RightUpperLeg"))
	var knee: Vector3 = rig.to_global(rig.bone_pos("RightLowerLeg"))
	_check("bed legs lie out along the mattress (knee only %.2f m above the hip joint)" % (knee.y - hip.y), knee.y - hip.y < 0.12)

	for phase in ["open", "editing"]:
		if phase == "open":
			ss.open_laptop()
		else:
			ss.begin_editing()
		await create_timer(1.4).timeout
		var tag: String = "laptop %s" % phase
		_check("%s: the laptop is on the lap anchor (single instance)" % tag, laptop.get_parent() == lap_anchor)
		var base: Node3D = laptop.get_node("Base")
		var base_bb: AABB = (base as VisualInstance3D).global_transform * (base as VisualInstance3D).get_aabb()
		# Penetration is tested in the BASE's own frame (a tilted box's
		# world AABB includes empty space under it).
		var base_inv: Transform3D = (base as Node3D).global_transform.affine_inverse()
		var base_local: AABB = (base as VisualInstance3D).get_aabb().grow(-0.003)
		var thigh_top := -INF
		var inside := 0
		for side in ["Left", "Right"]:
			var a: Vector3 = rig.to_global(rig.bone_pos(side + "UpperLeg"))
			var b: Vector3 = rig.to_global(rig.bone_pos(side + "LowerLeg"))
			for k in 11:
				var p: Vector3 = a.lerp(b, k / 10.0)
				# Thigh surface (radius ~0.085 m) must stay below the base.
				if base_local.has_point(base_inv * (p + Vector3(0, 0.08, 0))):
					inside += 1
			thigh_top = maxf(thigh_top, a.lerp(b, 0.62).y + 0.085)
		_check("%s: thighs never pass through the laptop (%d samples inside)" % [tag, inside], inside == 0)
		var la: AABB = (base as VisualInstance3D).get_aabb()
		var under: Vector3 = (base as Node3D).global_transform * Vector3(la.get_center().x, la.position.y, la.get_center().z)
		_check("%s: laptop rests ON the thighs (underside centre %.3f vs thigh top %.3f)" % [tag, under.y, thigh_top], under.y > thigh_top - 0.02 and under.y < thigh_top + 0.05)
		var lap_xz := Vector2(base_bb.get_center().x, base_bb.get_center().z)
		var lr := rig.to_global(rig.bone_pos("RightUpperLeg")).lerp(rig.to_global(rig.bone_pos("LeftUpperLeg")), 0.5)
		var kmid := rig.to_global(rig.bone_pos("RightLowerLeg")).lerp(rig.to_global(rig.bone_pos("LeftLowerLeg")), 0.5)
		var along: float = (Vector2(kmid.x, kmid.z) - Vector2(lr.x, lr.z)).normalized().dot(lap_xz - Vector2(lr.x, lr.z))
		_check("%s: laptop centred over the thighs, between hips and knees (%.2f m along)" % [tag, along], along > 0.12 and along < 0.42)
		var screen: Vector3 = lv.get_screen_global_position()
		_check("%s: screen in view" % tag, cam.is_position_in_frustum(screen) and not cam.is_position_behind(screen))
		var blockers: Array = []
		for bn in ["RightLowerLeg", "LeftLowerLeg", "RightUpperLeg", "LeftUpperLeg", "RightLowerArm", "LeftLowerArm"]:
			var bp: Vector3 = rig.to_global(rig.bone_pos(bn))
			var seg: Vector3 = screen - cam.global_position
			var t: float = clampf((bp - cam.global_position).dot(seg) / seg.length_squared(), 0.0, 1.0)
			if t > 0.05 and t < 0.95 and (cam.global_position + seg * t).distance_to(bp) < 0.07:
				blockers.append(bn)
		_check("%s: no knee/leg/forearm between the eye and the screen %s" % [tag, str(blockers)], blockers.is_empty())
		for side in ["Right", "Left"]:
			var kb: Vector3 = laptop.to_global(Vector3(0.075 if side == "Right" else -0.075, 0.03, 0.06))
			var hd: float = rig.to_global(rig.bone_pos(side + "Hand")).distance_to(kb)
			_check("%s: %s hand on the keyboard (%.3f m)" % [tag, side.to_lower(), hd], hd < 0.06)
	# The laptop must not drift as the player looks around.
	ss.end_editing()
	await create_timer(0.6).timeout
	var lp0: Vector3 = laptop.global_position
	var lpv: Node3D = player.get_node("LookPivot")
	for deg in [-60.0, 10.0, -30.0]:
		lpv._target_pitch = deg_to_rad(deg)
		lpv.get_node("PitchPivot").rotation.x = deg_to_rad(deg)
		await create_timer(0.3).timeout
	_check("open laptop stays put while looking around (%.4f m)" % laptop.global_position.distance_to(lp0), laptop.global_position.distance_to(lp0) < 0.005)
	ss.close_laptop()
	await create_timer(0.8).timeout
	_check("close: laptop still safely on the lap", laptop.get_parent() == lap_anchor)
	ss.end_sitting()
	await create_timer(3.0).timeout
	_check("get-up: laptop back on the bunk, not left floating at the lap", laptop.get_parent().name == "Interactables")
	_check("standing: lap anchor back at its authored spot", lap_anchor.position.is_equal_approx(authored_lap))

	# Workstation chair: legacy seat geometry, lap anchor untouched.
	body.set_seat_style(false)
	body.set_sitting(true)
	await create_timer(0.6).timeout
	_check("chair seat: lap anchor stays at the authored spot", lap_anchor.position.is_equal_approx(authored_lap))
	body.set_sitting(false)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
