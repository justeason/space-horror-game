extends SceneTree
## Regression coverage for this round's workstation camera/framing
## change (scripts/station/workstation_state.gd's sit_position and
## begin_use() aim target): confirms the seated view actually reveals
## the physical switch row (not just the monitor -- player feedback:
## "can only see the monitor"), and that this didn't reintroduce the
## standing-composition bug of a body part sitting near frame-center
## (test_standing_body_composition.gd's technique, applied here to the
## seated pose at its one fixed settled pitch rather than a sweep).
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player := main.get_node("Player")
	var console := main.get_node("Interactables/WorkstationConsole")
	var wstate := main.get_node("WorkstationState")
	var look_pivot := player.get_node("LookPivot")
	var pitch_pivot := look_pivot.get_node("PitchPivot")
	var camera := pitch_pivot.get_node("Camera3D")
	var player_body := player.get_node("PlayerBody")
	var sitting_pose := player_body.get_node("SittingPose")

	var console_pos: Vector3 = console.global_position + Vector3(0, 1.6 - console.global_position.y, 0.6)
	player.global_position = console_pos
	console.interact()
	await create_timer(1.0).timeout
	_check("settled at the workstation", wstate.is_in_use())

	var half_vfov_deg: float = camera.fov / 2.0
	var forward: Vector3 = -camera.global_transform.basis.z

	# ============================================================
	# 1. The switch row is now within the vertical half-FOV (it was
	# geometrically impossible at the previous 0.25m eye-to-screen
	# distance with a near-level pitch -- see workstation_state.gd's
	# sit_position doc comment for the FOV math).
	# ============================================================
	# The two switches nearest the console's own centerline -- Stage
	# 6B asks for "at least some" physical controls in frame, not every
	# one; the outermost switches (Power/Lighting, the far edges of the
	# instrument cluster) are expected to sit near/past the frame edge,
	# same as glancing at the far side of a real desk.
	var switches: Array[Node3D] = [
		main.get_node("Interactables/WsSwitchComms"),
		main.get_node("Interactables/WsRotary"),
	]
	for sw in switches:
		var to_switch: Vector3 = (sw.global_position - camera.global_position).normalized()
		var ang_deg: float = rad_to_deg(forward.angle_to(to_switch))
		_check("%s is within the seated vertical FOV (angle=%.1f, half-fov=%.1f)" % [sw.name, ang_deg, half_vfov_deg], ang_deg <= half_vfov_deg)

	# ============================================================
	# 2. The monitor is still the dominant element: its center is
	# clearly closer to frame-center than the switches are.
	# ============================================================
	var to_screen: Vector3 = (console.get_screen_global_position() - camera.global_position).normalized()
	var screen_ang_deg: float = rad_to_deg(forward.angle_to(to_screen))
	for sw in switches:
		var to_switch: Vector3 = (sw.global_position - camera.global_position).normalized()
		var switch_ang_deg: float = rad_to_deg(forward.angle_to(to_switch))
		_check("monitor stays more central than %s (screen=%.1f deg, switch=%.1f deg)" % [sw.name, screen_ang_deg, switch_ang_deg], screen_ang_deg < switch_ang_deg)

	# ============================================================
	# 3. No seated body part sits near dead-center of the view (same
	# invariant test_standing_body_composition.gd checks for standing).
	# ============================================================
	var min_angle_seen := 9999.0
	for part_name in ["ShoulderL", "ShoulderR", "Chest"]:
		var part: Node3D = sitting_pose.get_node_or_null(part_name)
		if part == null:
			continue
		var to_part: Vector3 = (part.global_position - camera.global_position)
		if to_part.length() < 0.001:
			continue
		var ang_deg: float = rad_to_deg(forward.angle_to(to_part.normalized()))
		min_angle_seen = min(min_angle_seen, ang_deg)
	_check("seated: no near body part close to frame-center (min angle seen=%.1f deg, half-fov=%.1f)" % [min_angle_seen, half_vfov_deg], min_angle_seen > half_vfov_deg * 0.5)

	wstate.end_use()
	await create_timer(1.3).timeout
	_check("stood back up cleanly", not wstate.is_in_use())

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()

func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
