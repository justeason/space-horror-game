extends SceneTree
## Round 49: B-00 VERTICAL SHAFT TRAVERSAL -- real grip-to-grip motion
## both ways, never a teleport, safe in every interruption.
##   - restricted before Deck B access (Chapter One: visible, refused);
##   - descend from Deck A and ascend from Deck B through all six grips,
##     the camera moving smoothly (largest per-frame step bounded), real
##     distance travelled, the hatch lid opened by hand and shut again, the
##     body's hands / feet on the rungs (climb pose), boots release /
##     engage, free walking + interactions restored at the landing;
##   - reversal mid-shaft (S), abort to the nearest landing, an emergency
##     during the climb, saving mid-shaft stores a LANDING;
##   - a bulky part is refused on the ladder and travels on the service
##     hoist instead (one item, never duplicated).
const L = preload("res://scripts/deck_b/deck_b_layout.gd")
var _ok := true
var main: Node
var shaft: Node
var fb: Node
var player: Node3D
var clr: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	main.get_node("StationAI").set_enabled(false)
	shaft = main.get_node("DeckB/VerticalShaft")
	fb = main.get_node("FreeMoveBody")
	player = main.get_node("Player")
	clr = main.get_node("DayPlan/Clearance")
	clr.load_dict({"level": 3})
	await _stand(shaft.grip_eye(0))
	# Restricted.
	_check("Chapter One: shaft refused ('%s')" % shaft.refusal(true), not shaft.begin(true) and shaft.refusal(true).find("RESTRICTED") != -1)
	_check("...the hatch lid is shut and walkable", not shaft.lid_open)
	clr.dev_set_deck_b(1)
	# ---- Descend.
	var r: Dictionary = await _climb(true)
	_check("descended through all grips (%d motions, %.2f m travelled)" % [int(r["motions"]), float(r["dist"])], int(r["motions"]) == 5 and float(r["dist"]) > 4.0)
	_check("no teleport: largest per-frame camera step %.3f m" % float(r["max_step"]), float(r["max_step"]) < 0.2)
	_check("the lid opened on the way in and is shut again", bool(r["lid_seen_open"]) and not shaft.lid_open)
	_check("hands / feet on the rungs mid-shaft (climb pose %.2f)" % float(r["pose"]), float(r["pose"]) > 0.5)
	_check("landed on Deck B at the bottom landing", player.global_position.distance_to(shaft.grip_eye(5)) < 0.02 and shaft.events.any(func(e): return e["event"] == "landed_B"))
	_check("free walking restored (body active, synced, interactions on)", fb.active and fb.current_eye_position().distance_to(player.global_position) < 0.05 and main.get_node("Player/LookPivot/PitchPivot/Camera3D").interactions_enabled)
	var heard: Array = main.get_tree().get_first_node_in_group(&"station_sounds").heard.map(func(h): return String(h["kind"]))
	_check("climb sounds really played (grip, rung, boots, hatch): %s" % ", ".join(heard.filter(func(k): return k.begins_with("shaft_")).slice(0, 8)), heard.has("shaft_grip") and heard.has("shaft_rung") and heard.has("shaft_boot_release") and heard.has("shaft_boot_engage") and heard.has("shaft_hatch_open"))
	for i in 20: await physics_frame
	_check("standing on Deck B's floor (feet y %.2f)" % fb.global_position.y, absf(fb.global_position.y - L.FLOOR_Y) < 0.05)
	# ---- Reverse half-way.
	shaft.begin(false)
	var n := 0
	while shaft.climbing and shaft.grip > 3 and n < 600:
		if not shaft.moving:
			shaft.step(0)
		await process_frame
		n += 1
	shaft.step(1)        # S: back down
	n = 0
	while shaft.climbing and n < 600:
		if not shaft.moving:
			shaft.step(0)
		await process_frame
		n += 1
	_check("reversed mid-shaft back to Deck B", not shaft.climbing and player.global_position.distance_to(shaft.grip_eye(5)) < 0.02)
	# ---- Save mid-shaft, emergency, abort.
	shaft.begin(false)
	n = 0
	while shaft.grip > 3 and n < 600:
		if not shaft.moving:
			shaft.step(0)
		await process_frame
		n += 1
	var sd: Dictionary = main.get_node("SaveGame").collect_state()
	var saved_eye: Vector3 = main.get_node("SaveGame")._dec(sd["player"]["pos"]) + Vector3(0, 1.6, 0)
	_check("saving mid-shaft stores a LANDING, not the tube (%.2f, %.2f, %.2f)" % [saved_eye.x, saved_eye.y, saved_eye.z], saved_eye.distance_to(shaft.grip_eye(0)) < 0.05 or saved_eye.distance_to(shaft.grip_eye(5)) < 0.05)
	main.get_node("DayPlan").fire_emergency("overload", 1)
	n = 0
	while shaft.climbing and n < 900:
		if not shaft.moving:
			shaft.step(0)
		await process_frame
		n += 1
	_check("an emergency during the climb: the climber still reaches Deck A", not shaft.climbing and player.global_position.distance_to(shaft.grip_eye(0)) < 0.02)
	shaft.begin(true)
	n = 0
	while shaft.grip < 2 and n < 600:
		if not shaft.moving:
			shaft.step(0)
		await process_frame
		n += 1
	shaft.abort_to_landing()
	_check("abort mid-shaft puts the technician on a landing, walking", not shaft.climbing and fb.active and (player.global_position.distance_to(shaft.grip_eye(0)) < 0.02 or player.global_position.distance_to(shaft.grip_eye(5)) < 0.02) and not shaft.lid_open)
	# ---- Bulky part: ladder refused, hoist used.
	await _stand(shaft.grip_eye(0))
	var part: Node3D = load("res://scripts/deck_b/deck_b_part.gd").make(&"pump_cartridge", "TestPumpCartridge")
	main.get_node("Interactables").add_child(part)
	part.global_position = shaft.grip_eye(0) + Vector3(0, -0.6, 0.3)
	var carry: Node = main.get_node("Player/CarrySystem")
	carry.pick_up(part)
	if carry.is_reaching():
		carry.complete_grasp()
	_check("a bulky part is refused on the ladder ('%s')" % shaft.refusal(true), carry.is_carrying() and shaft.refusal(true).find("HOIST") != -1 and not shaft.begin(true))
	var stowed: bool = shaft.part_stow(&"hoist_tray_A", part)
	carry._carried_item = null
	_check("...loaded on the service hoist (Deck A tray)", stowed and shaft.hoist_item == part and shaft.hoist_at == "A")
	shaft.hoist_send("A")
	await create_timer(shaft.HOIST_TRAVEL_S + 0.6).timeout
	var copies: int = main.find_children("TestPumpCartridge*", "", true, false).size()
	_check("the hoist delivers it to Deck B (one item, no duplicate: %d)" % copies, shaft.hoist_at == "B" and part.get_parent().name == "HoistTrayB" and copies == 1)
	_check("hoist lands on Deck B physically (tray y %.2f)" % part.global_position.y, part.global_position.y < -2.5)
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _stand(eye: Vector3) -> void:
	fb.sync_to_eye_position(eye)
	player.global_position = eye
	for i in 4: await physics_frame


func _climb(down: bool) -> Dictionary:
	var ok: bool = shaft.begin(down)
	var prev: Vector3 = player.global_position
	var dist := 0.0
	var max_step := 0.0
	var lid_seen := false
	var pose := 0.0
	var start_tr: int = shaft.transitions
	var n := 0
	while ok and shaft.climbing and n < 1200:
		if not shaft.moving:
			shaft.step(0)
		await process_frame
		var p: Vector3 = player.global_position
		max_step = maxf(max_step, p.distance_to(prev))
		dist += p.distance_to(prev)
		prev = p
		lid_seen = lid_seen or shaft.lid_open
		if shaft.grip == 3:
			pose = maxf(pose, main.get_node("Player/PlayerBody").climb_pose_weight())
		n += 1
	return {"motions": shaft.transitions - start_tr, "dist": dist, "max_step": max_step, "lid_seen_open": lid_seen, "pose": pose}


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
