extends SceneTree
## Round 29 Priority 5 regression: visible gait vs. footstep sounds.
##
## ROOT CAUSES (measured with real W input before the change): the rig's
## walk cycle advanced one step per 0.75m while footstep sounds play every
## 0.85m of real displacement, so contacts drifted against the sounds (hip
## angle at successive sounds: +12, -1, -8 deg); the legs swung +/-24 deg
## with 38 deg pendulum knees; and the "planted" foot slid at 1.38 m/s in
## the world (77% of walking speed). Also, at render rates above the 60Hz
## physics rate most frames saw zero displacement, collapsing the walk
## blend (amount 0 at every sound in a free-running headless run).
##
## Now the legs are locked to free_move_controller.gd's own footstep
## accumulator (gait_position(): a heel strike at every footstep), feet are
## placed by IK on a shorter sweep, and speed is low-passed. Movement speed
## (1.8 m/s) and step distance (0.85m) are unchanged.
var _ok := true

class Rec:
	var times: Array = []
	var gait_at: Array = []
	var body: Node
	func play_step() -> void:
		times.append(Time.get_ticks_msec())

var rec := Rec.new()
var main: Node
var player: Node3D
var body: Node3D
var rig: Node3D
var fb: CharacterBody3D
var lp: Node3D

func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame
	player = main.get_node("Player")
	body = player.get_node("PlayerBody")
	rig = body.rigged_visual()
	fb = main.get_node("FreeMoveBody")
	lp = player.get_node("LookPivot")
	fb.footsteps = rec
	_check("approved move speed unchanged (1.8 m/s)", is_equal_approx(fb.move_speed, 1.8))
	_check("footstep stride distance unchanged (0.85 m)", is_equal_approx(fb.step_distance, 0.85))
	_check("the visible gait is wired to the footstep accumulator", body.gait_source == fb)

	# Living Quarters: open floor along -Z from (3.2, z=2.0).
	for spec in [["forward", KEY_W, Vector2(0, -1)], ["backward", KEY_S, Vector2(0, 1)], ["sideways", KEY_D, Vector2(1, 0)]]:
		var start := Vector3(3.2, 1.6, 2.0) if spec[0] != "backward" else Vector3(3.2, 1.6, -0.3)
		if spec[0] == "sideways":
			start = Vector3(2.6, 1.6, 1.2)
		fb.sync_to_eye_position(start)
		var yaw: float = -player.rotation.y if spec[0] != "sideways" else -player.rotation.y + PI * 0.5
		lp._target_yaw = yaw
		lp.rotation.y = yaw
		for i in 20: await physics_frame
		await _walk(spec[0], spec[1], 1.6)

	# Turning while moving: contacts still lock to the sounds.
	fb.sync_to_eye_position(Vector3(3.2, 1.6, 2.0))
	lp._target_yaw = -player.rotation.y
	lp.rotation.y = lp._target_yaw
	for i in 20: await physics_frame
	rec.times.clear()
	var ev := _key(KEY_W, true)
	var phases: Array = []
	var n0 := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1400:
		lp._target_yaw += 0.01
		await physics_frame
		if rec.times.size() > n0:
			n0 = rec.times.size()
			await process_frame
			phases.append(body.gait_position())
	_key(KEY_W, false)
	var locked := not phases.is_empty()
	for g in phases:
		locked = locked and absf(g - roundf(g)) < 0.12
	_check("turning while walking: every footstep still lands on a heel strike %s" % str(phases), locked)

	# Stopping: the legs settle back under the body.
	var ts := Time.get_ticks_msec()
	while Time.get_ticks_msec() - ts < 900:
		await process_frame
	_check("stopping: walk blend returns to 0 (%.2f)" % body.walk_amount(), body.walk_amount() < 0.02)
	var fr: Vector3 = rig.bone_pos("RightFoot")
	_check("stopping: feet back under the body at rest (%.3f m from rest)" % fr.distance_to(rig.rest_pos("RightFoot")), fr.distance_to(rig.rest_pos("RightFoot")) < 0.02)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _walk(tag: String, key: int, seconds: float) -> void:
	rec.times.clear()
	var start: Vector3 = fb.global_position
	_key(key, true)
	var t0 := Time.get_ticks_msec()
	var n0 := 0
	var at_sound: Array = []
	var slide_sum := 0.0
	var slide_n := 0
	var max_thigh := 0.0
	var prev := {}
	var prev_t := t0
	var min_sep := INF
	while Time.get_ticks_msec() - t0 < seconds * 1000.0:
		await physics_frame
		await process_frame
		var now := Time.get_ticks_msec()
		var dt: float = maxf((now - prev_t) / 1000.0, 0.001)
		prev_t = now
		var g: float = body.gait_position()
		var feet := {}
		for side in ["Right", "Left"]:
			feet[side] = rig.to_global(rig.bone_pos(side + "Foot"))
			var p: float = fposmod(g - (0.0 if side == "Right" else 1.0), 2.0)
			if body.walk_amount() > 0.95 and p > 0.1 and p < 0.65 and prev.has(side):
				var d: Vector3 = feet[side] - prev[side]
				d.y = 0.0
				slide_sum += d.length() / dt
				slide_n += 1
			# Reach: how far the foot gets AHEAD of its hip joint along the
			# travel direction (rig space, -Z forward).
			max_thigh = maxf(max_thigh, -(rig.bone_pos(side + "Foot").z - rig.bone_pos(side + "UpperLeg").z))
		var lr: Vector3 = rig.bone_pos("RightFoot") - rig.bone_pos("LeftFoot")
		min_sep = minf(min_sep, lr.x)
		prev = feet
		if rec.times.size() > n0:
			n0 = rec.times.size()
			at_sound.append(g)
	_key(key, false)
	for i in 30: await physics_frame
	var dist: float = (fb.global_position - start).length()
	_check("%s: footsteps still play at the approved cadence (%d sounds over %.2f m)" % [tag, rec.times.size(), dist], rec.times.size() >= int(dist / 0.85) - 1 and rec.times.size() <= int(dist / 0.85) + 1)
	var locked := not at_sound.is_empty()
	for g in at_sound:
		locked = locked and absf(g - roundf(g)) < 0.12
	_check("%s: every footstep sound coincides with a heel strike (gait at sounds %s)" % [tag, str(at_sound)], locked)
	var slide: float = slide_sum / maxf(slide_n, 1)
	if tag == "forward":
		_check("%s: planted foot barely slides (%.2f m/s; was 1.38 m/s)" % [tag, slide], slide_n > 5 and slide < 0.45)
		_check("%s: shorter visible step (foot reaches %.2f m ahead of the hip; the old +/-24 deg swing reached 0.33 m)" % [tag, max_thigh], max_thigh < 0.28)
	if tag == "sideways":
		_check("%s: legs never cross (min L/R foot separation %.3f m)" % [tag, min_sep], min_sep > 0.04)


func _key(code: int, pressed: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	return ev


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
