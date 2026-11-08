extends SceneTree
## Round 29 Priority 2 + 7 regression: bed sitting / lying / getting up with
## the rigged character, through the REAL SleepState flow.
##
## ROOT CAUSE (measured): the legacy SittingPose anchors describe a
## reclined sitter (hips 0.20m in front of and 0.56m below the eye) but the
## Round 28 rig sat bolt upright on those hips, so its eye was 0.38m IN
## FRONT of the camera -- the camera sat behind the character's head, with
## its neck/shoulders/upper back 0.22-0.29m ahead of the lens filling the
## frame. Now the rig reclines from its pelvis (seat height constrained to
## the mattress), its eye is placed ON the seat camera, and the camera
## follows the posed head (pelvis planted). Lying: the camera sits on the
## lying rig's eye and looking toward the feet lifts the head.
##
## Checks: eye/camera coincidence; no torso bone close in front of the
## lens at several seated pitches; pelvis resting at mattress height and
## planted while looking around; sit-down / get-up camera continuity (no
## per-frame jump) and body continuity (no bone snapping); feet planted
## BESIDE the bunk (not through the mattress) during get-up; final standing
## position restored; sleep/wake timing unchanged; lying camera on the
## rig's eye with a clear view along the body.
var _ok := true
const MATTRESS_TOP := 0.535
## BunkPlatform footprint (main.tscn): x 4.5..5.5, z -1.4..0.4.
const BUNK_MIN := Vector2(4.5, -1.4)
const BUNK_MAX := Vector2(5.5, 0.4)
var rig: Node3D
var cam: Camera3D

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame
	var player: Node3D = main.get_node("Player")
	var body: Node3D = player.get_node("PlayerBody")
	var lp: Node3D = player.get_node("LookPivot")
	var ss: Node = main.get_node("SleepState")
	cam = lp.get_node("PitchPivot/Camera3D")
	rig = body.rigged_visual()
	var start := Vector3(4.0, 1.6, -0.3)
	main.get_node("FreeMoveBody").sync_to_eye_position(start)
	player.global_position = start
	for i in 10: await physics_frame

	# ---- Sit down: continuity of camera and body every frame. ----
	ss.begin_sitting()
	var cam_jump := 0.0
	var bone_jump := 0.0
	var prev_cam: Vector3 = cam.global_position
	var prev_bones: Dictionary = _bones()
	var preview_seen := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1500:
		await process_frame
		cam_jump = maxf(cam_jump, cam.global_position.distance_to(prev_cam))
		bone_jump = maxf(bone_jump, _max_delta(prev_bones, _bones()))
		preview_seen = preview_seen or body.sit_down_preview_weight() > 0.3
		prev_cam = cam.global_position
		prev_bones = _bones()
	_check("sit-down: seated", ss.is_sitting() and body.is_sitting())
	_check("sit-down: the body eases into the seat during the camera move (preview seen)", preview_seen)
	_check("sit-down: no camera jump (max %.3f m/frame)" % cam_jump, cam_jump < 0.06)
	_check("sit-down: no body snapping (max bone move %.3f m/frame)" % bone_jump, bone_jump < 0.12)

	# ---- Seated view: eye on the camera, torso never in front of the lens. ----
	for deg in [-12.0, -45.0, -70.0, 0.0, 25.0]:
		lp._target_pitch = deg_to_rad(deg)
		lp.get_node("PitchPivot").rotation.x = deg_to_rad(deg)
		await create_timer(0.3).timeout
		var eye: Vector3 = _rig_eye()
		_check("seated %d deg: camera on the rig's posed eye (%.4f m)" % [deg, cam.global_position.distance_to(eye)], cam.global_position.distance_to(eye) < 0.01)
		var near: Array = _torso_in_front(0.16)
		_check("seated %d deg: no torso/neck bone within 0.16m in front of the lens %s" % [deg, str(near)], near.is_empty())
		var hips: Vector3 = rig.to_global(rig.bone_pos("Hips"))
		_check("seated %d deg: pelvis rests at mattress height (hips bone %.3f, mattress %.3f)" % [deg, hips.y, MATTRESS_TOP], hips.y > MATTRESS_TOP + 0.06 and hips.y < MATTRESS_TOP + 0.2)
	lp._target_pitch = deg_to_rad(-60.0)
	lp.get_node("PitchPivot").rotation.x = deg_to_rad(-60.0)
	await create_timer(0.3).timeout
	var hips_a: Vector3 = rig.to_global(rig.bone_pos("Hips"))
	lp._target_pitch = deg_to_rad(20.0)
	lp.get_node("PitchPivot").rotation.x = deg_to_rad(20.0)
	await create_timer(0.3).timeout
	var hips_b: Vector3 = rig.to_global(rig.bone_pos("Hips"))
	_check("seated: pelvis stays planted while looking down/up (%.4f m)" % hips_a.distance_to(hips_b), hips_a.distance_to(hips_b) < 0.005)
	lp._target_pitch = deg_to_rad(-12.0)
	lp.get_node("PitchPivot").rotation.x = deg_to_rad(-12.0)
	await create_timer(0.3).timeout

	# ---- Sleep / wake timing unchanged (eyes 0.35 + 0.9 + 0.35s). ----
	get_root().find_child("DayPlan", true, false).end_shift_now()   # Round 34: sleep only after the shift
	ss.begin_sleep()
	# Round 31: lie down first (1.1s), then the unchanged eyes sequence.
	await create_timer(1.2).timeout
	_check("sleep: lying on the mattress before the eyes close", body.is_lying())
	var eye_l0: Vector3 = _rig_eye()
	_check("sleep: camera on the lying eye (%.4f m)" % cam.global_position.distance_to(eye_l0), cam.global_position.distance_to(eye_l0) < 0.02)
	_check("sleep: no torso bone close in front of the lens while lying %s" % str(_torso_in_front(0.2)), _torso_in_front(0.2).is_empty())
	var hips_l: Vector3 = rig.to_global(rig.bone_pos("Hips"))
	_check("sleep: pelvis on the mattress (%.3f)" % hips_l.y, hips_l.y > MATTRESS_TOP and hips_l.y < MATTRESS_TOP + 0.25)
	await create_timer(1.2).timeout
	_check("sleep: still sleeping before the eyes have reopened", ss.is_sleeping())
	await create_timer(0.5).timeout
	_check("wake: awake, still lying on the bed", ss.is_sitting() and not ss.is_sleeping() and body.is_lying())

	# ---- Get up: legs swing off the OPEN edge, feet on the floor beside the
	# bunk, camera continuous, standing at the pre-sit spot at the end. ----
	ss.end_sitting()
	prev_cam = cam.global_position
	prev_bones = _bones()
	cam_jump = 0.0
	bone_jump = 0.0
	var feet_outside_at_rise := false
	var t := 0.0
	var tg0 := Time.get_ticks_msec()
	while t < 3.8:
		await process_frame
		t = (Time.get_ticks_msec() - tg0) / 1000.0
		cam_jump = maxf(cam_jump, cam.global_position.distance_to(prev_cam))
		bone_jump = maxf(bone_jump, _max_delta(prev_bones, _bones()))
		prev_cam = cam.global_position
		prev_bones = _bones()
		if t > 2.3 and t < 2.5:   # + 1.0s sit-up from lying (Round 31)
			feet_outside_at_rise = _foot_outside_bunk("Right") and _foot_outside_bunk("Left")
	_check("get-up: feet planted BESIDE the bunk before rising (not through the mattress)", feet_outside_at_rise)
	_check("get-up: no camera jump (max %.3f m/frame; the authored 0.35s walk-back stage moves ~0.07m/frame)" % cam_jump, cam_jump < 0.085)
	_check("get-up: no body snapping (max bone move %.3f m/frame)" % bone_jump, bone_jump < 0.12)
	_check("get-up: standing again", not ss.is_sitting() and not body.is_sitting())
	_check("get-up: back where the player stood (%.3f m)" % player.global_position.distance_to(start), player.global_position.distance_to(start) < 0.02)
	await create_timer(0.5).timeout
	_check("standing: rig upright on the floor (feet at %.3f)" % rig.to_global(rig.bone_pos("RightFoot")).y, absf(rig.to_global(rig.bone_pos("RightFoot")).y - 0.08) < 0.03)

	# ---- Lying (set_lying API). ----
	main.get_node("GlobalFreeMove").mirror_enabled = false
	main.get_node("FreeMoveBody").set_active(false)
	player.global_position = Vector3(5.0, 1.2, -1.1)
	body.set_lying(true)
	await process_frame
	player.global_position.y += MATTRESS_TOP + 0.02 - body.get_node("LyingPose/Hips").global_position.y
	for deg in [70.0, -5.0]:
		lp._target_pitch = deg_to_rad(deg)
		lp.get_node("PitchPivot").rotation.x = deg_to_rad(deg)
		await create_timer(0.7).timeout
		var eye_l: Vector3 = _rig_eye()
		_check("lying %d deg: camera on the lying rig's eye (%.4f m)" % [deg, cam.global_position.distance_to(eye_l)], cam.global_position.distance_to(eye_l) < 0.01)
		var near_l: Array = _torso_in_front(0.2)
		_check("lying %d deg: no torso bone within 0.20m in front of the lens %s" % [deg, str(near_l)], near_l.is_empty())
	var head_flex: float = rig.get_local("Neck").get_angle() + rig.get_local("Head").get_angle()
	_check("lying, looking toward the feet: the head lifts (chin toward chest, %.0f deg)" % rad_to_deg(head_flex), head_flex > deg_to_rad(25.0))
	body.set_lying(false)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _rig_eye() -> Vector3:
	return rig.to_global(rig.bone_pos("Head") + rig.bone_basis("Head") * (rig.EYE_POINT - rig.rest_pos("Head")))


## Torso/neck joints (and points along the spine) within `dist` of the lens
## and inside its forward cone.
func _torso_in_front(dist: float) -> Array:
	var out: Array = []
	var fwd: Vector3 = -cam.global_basis.z
	for b in ["Hips", "Spine", "Chest", "UpperChest", "Neck", "RightShoulder", "LeftShoulder", "RightUpperArm", "LeftUpperArm"]:
		var v: Vector3 = rig.to_global(rig.bone_pos(b)) - cam.global_position
		if v.length() < dist and v.normalized().dot(fwd) > 0.5:
			out.append(b)
	return out


func _foot_outside_bunk(side: String) -> bool:
	var p: Vector3 = rig.to_global(rig.bone_pos(side + "Foot"))
	var inside: bool = p.x > BUNK_MIN.x and p.x < BUNK_MAX.x and p.z > BUNK_MIN.y and p.z < BUNK_MAX.y
	return not inside and p.y < 0.2


func _bones() -> Dictionary:
	var d := {}
	for b in ["Head", "RightHand", "LeftHand", "RightFoot", "LeftFoot", "Hips"]:
		d[b] = rig.to_global(rig.bone_pos(b))
	return d


func _max_delta(a: Dictionary, b: Dictionary) -> float:
	var m := 0.0
	for k in a:
		m = maxf(m, (a[k] as Vector3).distance_to(b[k]))
	return m


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
