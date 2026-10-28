extends SceneTree
## Regression for this round's Issue 2/3 (dedicated sitting-on-bed pose,
## laptop repositioning). Reads real transforms off the live scene
## (mattress/headboard geometry from main.tscn, body part positions
## from the actual SittingPose, laptop screen/keyboard positions after
## really opening the laptop through the real F-key input path) rather
## than asserting hand-picked numbers, so this fails if the authored
## geometry actually regresses, not just if some unrelated refactor
## touches unrelated numbers.

var _ok := true


func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5:
		await process_frame

	var player := main.get_node("Player")
	var free_body := main.get_node("FreeMoveBody")
	var sleep_state := main.get_node("SleepState")
	var bunk := main.get_node("Interactables/Bunk")
	var laptop := main.get_node("Interactables/BunksideLaptop")
	var laptop_view := player.get_node("LaptopView")
	var player_body := player.get_node("PlayerBody")
	var sitting_pose := player_body.get_node("SittingPose")
	var mattress: CSGBox3D = main.get_node("Geometry/BunkMattressTop")
	var headboard: CSGBox3D = main.get_node("Geometry/BunkHeadboardInset")

	var mattress_top: float = mattress.global_position.y + mattress.size.y / 2.0
	var headboard_front: float = headboard.global_position.z + headboard.size.z / 2.0

	var near_pos := Vector3(bunk.global_position.x - 1.0, 1.6, bunk.global_position.z)
	free_body.sync_to_eye_position(near_pos)
	player.global_position = near_pos
	for i in 3:
		await process_frame

	bunk.interact()
	await create_timer(1.6).timeout
	_check("precondition: sitting succeeded", sleep_state.is_sitting())

	# ============================================================
	# 1. PELVIS/TORSO ABOVE THE MATTRESS, not sunk into it.
	# ============================================================
	var hips: Node3D = sitting_pose.get_node("Hips")
	var chest: Node3D = sitting_pose.get_node("Chest")
	_check("sitting: hips sit above the real mattress surface (hips.y=%.2f, mattress top=%.2f)" % [hips.global_position.y, mattress_top], hips.global_position.y > mattress_top)
	_check("sitting: chest sits well above the mattress (chest.y=%.2f)" % chest.global_position.y, chest.global_position.y > mattress_top + 0.2)

	# ============================================================
	# 2. LEGS FORM A CONNECTED, NON-CLIPPING SEATED POSTURE: thigh and
	# shin overlap continuously, and the feet rest AT the mattress
	# surface (not floating above it, not sunk below it).
	# ============================================================
	var thigh: CSGCylinder3D = sitting_pose.get_node("UpperLegR")
	var shin: CSGCylinder3D = sitting_pose.get_node("LowerLegR")
	var foot: CSGBox3D = sitting_pose.get_node("FootR")
	_check("sitting: thigh sits above the mattress, not through it (y=%.2f)" % thigh.global_position.y, thigh.global_position.y - thigh.radius > mattress_top - 0.02)
	_check("sitting: shin connects to the thigh (within combined radius of each other in reach)", thigh.global_position.distance_to(shin.global_position) < (thigh.height / 2.0 + shin.height / 2.0 + 0.05))
	var foot_bottom: float = foot.global_position.y - foot.size.y / 2.0
	_check("sitting: foot rests AT the mattress surface (foot bottom=%.2f, mattress top=%.2f)" % [foot_bottom, mattress_top], absf(foot_bottom - mattress_top) < 0.05)

	# ============================================================
	# 3. BACK/TORSO DOES NOT CLIP THROUGH THE HEADBOARD.
	# ============================================================
	_check("sitting: chest sits forward of (clear of) the headboard panel (chest.z=%.2f, headboard front=%.2f)" % [chest.global_position.z, headboard_front], chest.global_position.z > headboard_front)

	# ============================================================
	# 4. REAL LAPTOP-OPEN FLOW: screen/keyboard close enough to be
	# recognizable, and the sightline from the eye to each is not
	# blocked by the torso/shoulders/hips/thighs.
	# ============================================================
	_send_key(KEY_F)
	await create_timer(0.6).timeout
	_check("precondition: laptop open", sleep_state.is_laptop_open())

	var eye: Vector3 = player.global_position
	var screen_pos: Vector3 = laptop_view.get_screen_global_position()
	var keyboard_pos: Vector3 = laptop.get_node("KeyRow2").global_position
	_check("laptop: screen is not floating unrealistically far away (got %.2fm)" % eye.distance_to(screen_pos), eye.distance_to(screen_pos) < 1.0)
	_check("laptop: keyboard is not floating unrealistically far away (got %.2fm)" % eye.distance_to(keyboard_pos), eye.distance_to(keyboard_pos) < 1.0)

	var shoulders_l: Node3D = sitting_pose.get_node("ShoulderL")
	for occluder_data in [
		{"node": shoulders_l, "name": "ShoulderL", "radius": 0.1},
		{"node": chest, "name": "Chest", "radius": chest.radius},
		{"node": hips, "name": "Hips", "radius": hips.radius},
		{"node": thigh, "name": "UpperLegR", "radius": thigh.radius},
	]:
		var occ_pos: Vector3 = occluder_data["node"].global_position
		var occ_radius: float = occluder_data["radius"]
		var occ_name: String = occluder_data["name"]
		var d_screen: float = _point_segment_distance(occ_pos, eye, screen_pos)
		_check("laptop screen sightline clears %s (margin %.2fm)" % [occ_name, d_screen - occ_radius], d_screen > occ_radius)
		var d_kb: float = _point_segment_distance(occ_pos, eye, keyboard_pos)
		_check("laptop keyboard sightline clears %s (margin %.2fm)" % [occ_name, d_kb - occ_radius], d_kb > occ_radius)

	# ============================================================
	# 5. POSE TOGGLE LEAVES NO STALE GEOMETRY after getting up.
	# ============================================================
	sleep_state.end_sitting()
	await create_timer(2.6).timeout
	var standing_pose := player_body.get_node("StandingPose")
	_check("get-up: standing pose restored, sitting pose hidden", standing_pose.visible and not sitting_pose.visible)
	_check("get-up: exactly one PlayerBody (no duplication)", player.get_children().filter(func(c): return c.name == "PlayerBody").size() == 1)

	print("")
	if _ok:
		print("ALL TESTS PASSED")
	else:
		print("SOME TESTS FAILED")
	quit()


func _point_segment_distance(c: Vector3, a: Vector3, b: Vector3) -> float:
	var ab: Vector3 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.0000001:
		return c.distance_to(a)
	var t: float = clampf((c - a).dot(ab) / len_sq, 0.0, 1.0)
	var closest: Vector3 = a + ab * t
	return c.distance_to(closest)


func _send_key(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)


func _check(label: String, cond: bool) -> void:
	if cond:
		print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
