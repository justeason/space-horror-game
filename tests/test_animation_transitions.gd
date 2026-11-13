extends SceneTree
## Round 29 Priority 7: one owner per joint (player_body.gd composes every
## bone each frame from the shared pose state) with blended transitions:
## walk amount ramps, watch raise progress, carry blend/reach, and the
## technician_rig.gd pose-switch crossfade (stand/sit/lie, 0.4s, started at
## the switch itself and never completed by an out-of-frame refresh).
## Sampled once per physics tick (60Hz): no bone may jump.
var _ok := true
var rig: Node3D
const JUMP := 0.1   # m per 1/60 s = 6 m/s -- far above any limb speed here

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame
	var player: Node3D = main.get_node("Player")
	var body: Node3D = player.get_node("PlayerBody")
	var lp: Node3D = player.get_node("LookPivot")
	var fb: Node = main.get_node("FreeMoveBody")
	var carry: Node = player.get_node("CarrySystem")
	rig = body.rigged_visual()

	# idle -> walk -> idle (real input).
	fb.sync_to_eye_position(Vector3(3.2, 1.6, 2.0))
	lp._target_yaw = -player.rotation.y
	lp.rotation.y = lp._target_yaw
	for i in 20: await physics_frame
	var ev := InputEventKey.new()
	ev.keycode = KEY_W
	ev.physical_keycode = KEY_W
	ev.pressed = true
	Input.parse_input_event(ev)
	var j1: float = await _max_jump(50)
	var ev2 := InputEventKey.new()
	ev2.keycode = KEY_W
	ev2.physical_keycode = KEY_W
	ev2.pressed = false
	Input.parse_input_event(ev2)
	var j2: float = await _max_jump(50)
	_check("idle -> walking blends (max %.3f m/tick)" % j1, j1 < JUMP)
	_check("walking -> idle blends (max %.3f m/tick)" % j2, j2 < JUMP)

	# standing -> watch inspection -> idle.
	body.set_watch_raise_pose(true, 0.35)
	var j3: float = await _max_jump(40)
	body.set_watch_raise_pose(false, 0.35)
	var j4: float = await _max_jump(40)
	_check("standing -> watch inspection blends (max %.3f m/tick)" % j3, j3 < JUMP)
	_check("watch inspection -> idle blends (max %.3f m/tick)" % j4, j4 < JUMP)

	# reach -> carry -> idle (Storage cabinet wire).
	fb.sync_to_eye_position(Vector3(-6.95, 1.6, 7.75))
	for i in 10: await physics_frame
	main.get_node("Geometry/StorageCabinet1").interact()
	await create_timer(0.8).timeout
	main.get_node("Interactables/WireComponent").interact()
	var j5: float = await _max_jump(60)
	carry.drop()
	var j6: float = await _max_jump(40)
	_check("reach -> grasp -> carry blends (max %.3f m/tick)" % j5, j5 < JUMP)
	_check("carrying -> idle blends (max %.3f m/tick)" % j6, j6 < JUMP)

	# standing -> lying -> standing (pose-switch crossfade).
	main.get_node("GlobalFreeMove").mirror_enabled = false
	fb.set_active(false)
	body.set_lying(true)
	var j7: float = await _max_jump(40, 0.25)
	body.set_lying(false)
	var j8: float = await _max_jump(40, 0.25)
	_check("standing -> lying crossfades, no snap (max %.3f m/tick incl. a 0.8m body rotation)" % j7, j7 < 0.25)
	_check("lying -> standing crossfades, no snap (max %.3f m/tick)" % j8, j8 < 0.25)
	_check("crossfade weight completes (no stuck half-blend)", body._rig_xfade_t >= 1.0)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


## Fastest bone speed seen over ~`ticks` physics ticks, reported as metres
## per 1/60 s so the thresholds read as a per-60Hz-tick move.
## Round 35: under load Godot runs CATCH-UP physics ticks (two 60 Hz ticks in
## one render frame), so the probe COUNTS the ticks in each frame.
## Round 50 ROOT CAUSE of the remaining intermittent failure (one loaded
## full-suite run: "idle -> walking 0.162 m/tick", normally 0.075): the
## test sampled the bones right after `await process_frame` -- a signal
## SceneTree emits BEFORE the nodes' _process(). So each sample held the
## PREVIOUS frame's pose composition (player_body.gd composes in _process)
## plus THIS frame's physics ticks, while the divisor was the previous
## frame's delta. After a stalled frame the two windows differ and the
## motion of ~two frames was divided by one frame's time (~2x too fast).
## The probe now SAMPLES ITSELF at the very end of each frame
## (process_priority last, after every pose / follow update) and divides by
## THAT SAME frame's own delta (or its physics ticks, whichever is longer):
## every sample covers exactly one frame of motion over that frame's time.
class DeltaProbe extends Node:
	var ticks: int = 0
	var sampler: Callable
	var samples: Array = []       # [{dt, bones}]
	var active: bool = false
	func _init() -> void:
		process_priority = 1000000
		process_physics_priority = -1000000
	func _process(delta: float) -> void:
		if not active:
			ticks = 0
			return
		var dt: float = maxf(delta, 1.0 / 1000.0)
		if ticks > 0:
			dt = maxf(dt, ticks / 60.0)
		ticks = 0
		samples.append({"dt": dt, "bones": sampler.call()})
	func _physics_process(_delta: float) -> void:
		ticks += 1

var _probe: DeltaProbe


func _max_jump(ticks: int, _scale: float = 0.1) -> float:
	if _probe == null:
		_probe = DeltaProbe.new()
		_probe.sampler = _bones
		get_root().add_child(_probe)
	_probe.samples = [{"dt": 0.0, "bones": _bones()}]
	_probe.ticks = 0
	_probe.active = true
	var t_end: float = ticks / 60.0
	var t := 0.0
	while t < t_end:
		await process_frame
		t = 0.0
		for sm in _probe.samples:
			t += float(sm["dt"])
	await process_frame
	_probe.active = false
	var m := 0.0
	var smp: Array = _probe.samples
	for i in range(1, smp.size()):
		var a: Dictionary = smp[i - 1]["bones"]
		var b: Dictionary = smp[i]["bones"]
		var dt: float = float(smp[i]["dt"])
		for k in b:
			m = maxf(m, (b[k] as Vector3).distance_to(a[k]) / dt / 60.0)
	return m


func _bones() -> Dictionary:
	var d := {}
	for b in ["Head", "RightHand", "LeftHand", "RightFoot", "LeftFoot", "Hips", "RightLowerArm"]:
		d[b] = rig.to_global(rig.bone_pos(b))
	return d


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
