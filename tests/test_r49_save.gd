extends SceneTree
## Round 49: SAVE / LOAD of the Lower Service Deck.
##   - every Deck B state survives a save -> fresh station -> load exactly:
##     the systems (water / thermal / Bus B / hydro / lab / medical /
##     service history / visits / player stows), every room's procedure
##     state, every rack's REAL parts (same names, same payloads), the
##     service hoist's cargo (Deck B tray), a part in the hand, a part
##     loose on the Deck B floor, access tier + Deck B job count;
##   - no inventory duplication (same number of parts, same names);
##   - an OLD save (made before Deck B existed: no "deck_b" section, no
##     Deck B parts, no Deck B equipment) still loads: the fresh lower-deck
##     parts stay in their racks (they are not "consumed"), the models
##     start from their defaults, nothing is stranded;
##   - a save made mid-shaft loads standing on a landing.
const PATH := "user://test_r49_save.json"
const L = preload("res://scripts/deck_b/deck_b_layout.gd")
var _ok := true
var main: Node


func _init() -> void:
	_cleanup()
	main = await _fresh()
	var clr: Node = main.get_node("DayPlan/Clearance")
	clr.load_dict({"level": 3, "deck_b_level": 2, "deck_b_jobs": 3})
	var s: Node = main.get_node("DeckB/DeckBSystems")
	s.water["filter_life"] = 0.41
	s.thermal["v2"] = 0.75
	s.power["on"] = [true, true, false, true]
	s.hydro["ec"] = 1.33
	s.visits = {3: ["b01", "b02"]}
	s.record_service({"day": 3, "t": "10:00", "room": "b02", "equipment": "x", "fault": "y", "action": "z", "verify": "ok", "outcome": "repaired"})
	var water: Node = main.get_node("DeckB/Rooms/WaterRecovery")
	water.clamp_open = true
	water.dp_read = true
	var carry: Node = main.get_node("Player/CarrySystem")
	var spares: Node = water.find_child("WaterSpareBeds", true, false)
	# One part to the hoist (Deck B), one loose on the floor, one in the hand.
	var shaft: Node = main.get_node("DeckB/VerticalShaft")
	var p_hoist: Node3D = spares.items()[0]
	shaft.put_on_tray(p_hoist, "B")
	var p_loose: Node3D = spares.items()[0]
	p_loose.place_in_world(Transform3D(Basis(), Vector3(-0.1, L.FLOOR_Y + 0.05, 9.4)))
	var thermal: Node = main.get_node("DeckB/Rooms/ThermalPlant")
	var p_held: Node3D = thermal.find_child("ThermalSpares", true, false).items()[0]
	p_held.payload["condition"] = 0.77
	p_held.interact()
	if carry.is_reaching():
		carry.complete_grasp()
	var fb: Node = main.get_node("FreeMoveBody")
	fb.sync_to_eye_position(Vector3(-3.2, L.EYE_Y, 8.0))
	for i in 4: await physics_frame
	var sg: Node = main.get_node("SaveGame")
	sg.save_path = PATH
	var expected: Dictionary = sg.collect_state()
	var names_before: Array = _part_names()
	var n_hoist: String = String(p_hoist.name)
	var n_loose: String = String(p_loose.name)
	var n_held: String = String(p_held.name)
	var r: Dictionary = sg.save_game()
	_check("saved with Deck B state ('%s')" % r["message"], r["ok"] and expected.has("deck_b"))
	main.queue_free()
	await process_frame
	main = await _fresh()
	sg = main.get_node("SaveGame")
	sg.save_path = PATH
	var ar: Dictionary = sg.apply_state(sg.read_save()["data"])
	await process_frame
	_check("loaded ('%s')" % ar["message"], ar["ok"])
	var got: Dictionary = sg.collect_state()
	for k in ["DeckBSystems", "WaterRecovery", "ThermalPlant", "LowerJunction", "Workshop", "PayloadLab", "Hydroponics", "MedicalBay", "CargoBay", "DataArchive", "VerticalShaft", "EngineeringBusLink", "Clearance"]:
		var a: String = JSON.stringify(expected["equipment2"].get(k))
		var b: String = JSON.stringify(got["equipment2"].get(k))
		if a != b:
			var ea: Dictionary = sg._dec(expected["equipment2"].get(k, {})) if expected["equipment2"].has(k) else {}
			var eb: Dictionary = sg._dec(got["equipment2"].get(k, {})) if got["equipment2"].has(k) else {}
			for kk in ea:
				if JSON.stringify(ea[kk]) != JSON.stringify(eb.get(kk)):
					print("  DIFF %s.%s: %s | %s" % [k, kk, JSON.stringify(ea[kk]).left(300), JSON.stringify(eb.get(kk)).left(300)])
		_check("%s restored exactly" % k, a == b and a != "null")
	_check("no inventory duplication (%d parts, same names)" % _part_names().size(), _part_names() == names_before)
	var s2: Node = main.get_node("DeckB/DeckBSystems")
	_check("model values back (bed life %.2f, V2 %.2f, B3 %s)" % [float(s2.water["filter_life"]), float(s2.thermal["v2"]), s2.power["on"][2]], absf(float(s2.water["filter_life"]) - 0.41) < 0.001 and float(s2.thermal["v2"]) == 0.75 and not s2.power["on"][2])
	var sh2: Node = main.get_node("DeckB/VerticalShaft")
	_check("the hoist still carries its part on Deck B", sh2.hoist_item != null and String(sh2.hoist_item.name) == n_hoist and sh2.hoist_at == "B")
	var held: Node = main.get_node("Player/CarrySystem")._carried_item
	_check("the part in the hand is back in the hand, its instance state intact (condition %.2f)" % (float(held.payload["condition"]) if held != null else -1.0), held != null and String(held.name) == n_held and absf(float(held.payload["condition"]) - 0.77) < 0.001)
	var loose: Node3D = main.find_child(n_loose, true, false) as Node3D
	_check("the loose part lies where it was on Deck B", loose != null and loose.global_position.distance_to(Vector3(-0.1, L.FLOOR_Y + 0.05, 9.4)) < 0.02)
	_check("access tier + Deck B jobs restored (T%d, %d jobs)" % [main.get_node("DayPlan/Clearance").deck_b_level, main.get_node("DayPlan/Clearance").deck_b_jobs], main.get_node("DayPlan/Clearance").deck_b_level == 2 and main.get_node("DayPlan/Clearance").deck_b_jobs == 3)
	_check("the technician stands on Deck B again", L.is_lower(main.get_node("FreeMoveBody").global_position))
	# ---- An OLD save (before Deck B existed).
	var old: Dictionary = expected.duplicate(true)
	old.erase("deck_b")
	old["items"] = old["items"].filter(func(rec): return not load("res://scripts/deck_b/deck_b_part.gd").KINDS.has(StringName(rec["type"])))
	for k in old["equipment2"].keys():
		if k in ["DeckBSystems", "WaterRecovery", "ThermalPlant", "LowerJunction", "Workshop", "PayloadLab", "Hydroponics", "MedicalBay", "CargoBay", "DataArchive", "VerticalShaft", "EngineeringBusLink"]:
			old["equipment2"].erase(k)
	old["equipment2"]["Clearance"] = {"level": 3}
	old["player"]["pos"] = sg._enc(Vector3(0, 0, 4.5))
	main.queue_free()
	await process_frame
	main = await _fresh()
	var fresh_parts: Array = _part_names()
	sg = main.get_node("SaveGame")
	var ar2: Dictionary = sg.apply_state(old)
	await process_frame
	_check("a pre-Deck-B save loads ('%s')" % ar2["message"], ar2["ok"])
	_check("...the lower deck's parts are NOT treated as consumed (%d -> %d)" % [fresh_parts.size(), _part_names().size()], _part_names() == fresh_parts and fresh_parts.size() > 10)
	_check("...racks still hold them (water spares %d)" % main.get_node("DeckB/Rooms/WaterRecovery").find_child("WaterSpareBeds", true, false).count(), main.get_node("DeckB/Rooms/WaterRecovery").find_child("WaterSpareBeds", true, false).count() == 3)
	_check("...no Deck B access granted by the migration itself (tier %d)" % main.get_node("DayPlan/Clearance").deck_b_tier(), main.get_node("DayPlan/Clearance").deck_b_tier() == 0)
	# ---- A save made mid-shaft.
	main.get_node("DayPlan/Clearance").dev_set_deck_b(1)
	var shaft3: Node = main.get_node("DeckB/VerticalShaft")
	main.get_node("FreeMoveBody").sync_to_eye_position(shaft3.grip_eye(0))
	main.get_node("Player").global_position = shaft3.grip_eye(0)
	for i in 3: await physics_frame
	shaft3.begin(true)
	var n := 0
	while shaft3.grip < 3 and n < 900:
		if not shaft3.moving:
			shaft3.step(0)
		await process_frame
		n += 1
	sg = main.get_node("SaveGame")
	sg.save_path = PATH
	sg.save_game()
	main.queue_free()
	await process_frame
	main = await _fresh()
	sg = main.get_node("SaveGame")
	sg.save_path = PATH
	sg.apply_state(sg.read_save()["data"])
	for i in 6: await physics_frame
	var eye: Vector3 = main.get_node("FreeMoveBody").current_eye_position()
	var sh4: Node = main.get_node("DeckB/VerticalShaft")
	_check("mid-shaft save loads standing on a landing (eye %.2f), not climbing" % eye.y, not sh4.climbing and (eye.distance_to(sh4.grip_eye(0)) < 0.1 or eye.distance_to(sh4.grip_eye(5)) < 0.1))
	_cleanup()
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _part_names() -> Array:
	var out: Array = get_nodes_in_group(&"deck_b_part").filter(func(p): return not p.is_queued_for_deletion()).map(func(p): return String(p.name))
	out.sort()
	return out


func _fresh() -> Node:
	var m: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(m)
	current_scene = m
	for i in 8: await process_frame
	m.get_node("StationAI").set_enabled(false)
	return m


func _cleanup() -> void:
	for p in [PATH, PATH + ".bak", PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _check(label: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + label)
	if not cond:
		_ok = false
