extends SceneTree
## Round 50: L09 RAPID PRESSURE LOSS on the station's pressure network.
##   - the network: Deck A, the Deck B core and three sealable compartments
##     with REAL volumes; leaks to vacuum, hatches, EQ valves, the duct and
##     the make-up gas behave physically (a small leak is held, a big one
##     is not; closing a hatch really splits the volumes);
##   - the three fault types (pipe feedthrough, seal, hull) and their
##     distinct procedures, played on the real controls;
##   - isolation changes the network (the station recovers, the isolated
##     volume falls), a hatch refuses to open against ΔP, EQ repressurises;
##   - stabilised vs repaired vs deferred; a hull defect hands its
##     permanent repair to A06; the hold test cannot pass on a patch;
##   - Deck A's cabin model follows the network; save / load mid-emergency
##     (no duplicate defect, no spontaneous repair); old saves get a
##     healthy hull.
var _ok := true
var main: Node
var dp: Node
var s: Node
var pc: Node
var carry: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	main.get_node("StationAI").set_enabled(false)
	dp = main.get_node("DayPlan")
	s = main.get_node("DeckB/DeckBSystems")
	pc = main.get_node("DeckB/Rooms/PressureControl")
	carry = main.get_node("Player/CarrySystem")
	var clr: Node = main.get_node("DayPlan/Clearance")
	clr.load_dict({"level": 3})
	clr.dev_set_deck_b(4)
	_model()
	await _pipe_leak()
	await _hull_leak()
	await _seal_and_save()
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _check(label: String, cond: bool) -> void:
	if cond:
		print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false


func _run(seconds: float) -> void:
	var n: int = int(seconds / s.TICK_S)
	for i in n:
		s.step(s.TICK_S)


func _order(t: StringName) -> Dictionary:
	for i in range(dp.orders.size() - 1, -1, -1):
		if StringName(dp.orders[i]["type"]) == t:
			return dp.orders[i]
	return {}


func _wait_closed(t: StringName, max_s: float = 3.0) -> Dictionary:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(max_s * 1000.0):
		await process_frame
		if String(_order(t).get("status", "")) == "done":
			break
	return _order(t)


func _hold(kind: StringName) -> Node3D:
	var it: Node3D = null
	for p in get_nodes_in_group(&"deck_b_part"):
		if p.get("item_id") == kind and not p.is_queued_for_deletion():
			it = p
			break
	if it == null:
		return null
	carry._carried_item = it
	carry._carried_item_id = kind
	return it


func _hold_detector() -> Node3D:
	for it in main.find_children("*", "", true, false):
		if it.get("item_id") == &"leak_detector" and it is Node3D:
			carry._carried_item = it
			carry._carried_item_id = &"leak_detector"
			return it
	return null


func _drop() -> void:
	carry._carried_item = null
	carry._carried_item_id = &""


func _model() -> void:
	s.clear_pressure()
	var vt: float = 0.0
	for c in ["A", "BC", "B03", "B04", "B08"]:
		vt += s.comp_volume(c)
	_check("network volumes are real (A %.0f, B core %.0f, B-03 %.0f, B-04 %.0f, B-08 %.0f m³)" % [s.comp_volume("A"), s.comp_volume("BC"), s.comp_volume("B03"), s.comp_volume("B04"), s.comp_volume("B08")],
		s.comp_volume("BC") > 150.0 and s.comp_volume("B04") > 25.0 and s.comp_volume("B04") < 50.0)
	_run(30.0)
	_check("healthy hull: every volume stays at %.1f kPa, no make-up flow" % s.P_NOM, absf(s.pressure("B04") - s.P_NOM) < 0.01 and float(s.press["makeup_flow"]) < 0.001 and int(s.press["alarm"]) == 0)
	# A tiny Deck A seam leak is HELD by make-up gas (no alarm) -- but it
	# costs reserve.
	var res0: float = float(s.press["makeup"])
	s.inject_leak("hull_seam", 2)
	_run(60.0)
	_check("a tiny seam leak is held by the PCS (A %.2f kPa, make-up %.2f, no alarm)" % [s.pressure("A"), float(s.press["makeup_flow"])], s.pressure("A") > 101.0 and float(s.press["makeup_flow"]) > 0.15 and int(s.press["alarm"]) == 0)
	_check("...and it consumes the finite reserve", float(s.press["makeup"]) < res0)
	s.clear_pressure()
	# Isolation is physical: a closed hatch splits the volumes.
	s.inject_leak("hull_b04", 3)
	_run(20.0)
	var tr_open: float = s.trend("BC")
	_check("a large hull leak drags the whole connected station down (B core %+.2f kPa/min)" % tr_open, tr_open < -0.5)
	_check("a pressure ALARM refuses focused laptop / games (a critical timer is never held): '%s'" % dp.entertainment_allowed().get("reason", ""), int(s.press["alarm"]) >= 1 and not bool(dp.entertainment_allowed()["ok"]))
	s.set_hatch("B04", false)
	_run(40.0)
	_check("hatch shut: the station recovers (B core %+.2f/min, make-up %.2f), the isolated B-04 keeps falling (%.1f kPa, %+.2f/min)" % [s.trend("BC"), float(s.press["makeup_flow"]), s.pressure("B04"), s.trend("B04")],
		s.trend("BC") > tr_open + 0.5 and s.trend("B04") < -3.0 and s.pressure("B04") < s.pressure("BC") - 5.0)
	_check("the hatch REFUSES to open against ΔP %.1f kPa" % s.hatch_dp("B04"), s.set_hatch("B04", true) != "" and not s.hatch_open("B04"))
	s.set_eq("B04", true)
	_run(30.0)
	_check("EQ valve: B-04 refills toward the station (ΔP now %.1f kPa) despite the leak" % s.hatch_dp("B04"), absf(s.hatch_dp("B04")) < s.HATCH_DP_MAX)
	_check("...and then the hatch opens", s.set_hatch("B04", true) == "")
	s.clear_pressure()
	# Deck A's cabin model follows the network.
	var env: Node = main.get_node("EnvironmentModel")
	s.press["p"]["A"] = 99.0
	_check("EnvironmentModel's cabin target follows Deck A's network deficit (%.1f kPa)" % env.pressure_target(), absf(env.pressure_target() - (99.0 - (s.P_NOM - 101.3)) ) < 0.5 and env.pressure_target() < 100.0)
	s.clear_pressure()


func _pipe_leak() -> void:
	# A REAL defect raises L09 by itself once the alarm is real.
	s.inject_leak("b03_feed", 3)
	var raised := false
	for k in 40:
		_run(15.0)
		s._check_faults()
		if dp.has_open_order(&"l09_pressure"):
			raised = true
			break
	_check("a real feedthrough leak raises L09 by itself (alarm %s, B core %.1f kPa)" % [s.alarm_word(int(s.press["alarm"])), s.pressure("BC")], raised)
	_check("the order is about the REAL defect (no second leak injected)", pc.leak_id == "b03_feed" and s.active_leaks().size() == 1)
	pc.on_part(&"pcp_read")
	_check("PCP-B read", pc.pcp_read)
	# Diagnose by isolation: shut B-04 first (wrong one -> no evidence),
	# then B-03 (its side keeps falling).
	pc.on_part(&"hatch_B04_BC")
	await _frames(10)
	_run(10.0)
	pc._closed_s["B04"] = 10.0
	pc.on_part(&"gauge_B04_BC")
	_check("closing the WRONG hatch identifies nothing", pc.ident == "")
	pc.on_part(&"hatch_B04_BC")
	pc.on_part(&"hatch_B03_BC")
	_run(12.0)
	pc._closed_s["B03"] = 12.0
	pc.on_part(&"gauge_B03_BC")
	_check("isolation test: B-03 keeps falling with its hatch shut -> source found (%s)" % pc.ident_how, pc.ident == "B03" and pc.ident_how == "isolation test")
	await _frames(100)
	_check("the closed hatch physically blocks the doorway (collision on)", not (pc._leaf["B03"]["cs"] as CollisionShape3D).disabled)
	# Repressurise to work on it: EQ, open, find it with the detector.
	pc.on_part(&"eq_B03_BC_up")
	_run(30.0)
	pc.on_part(&"hatch_B03_BC")
	_check("EQ then the hatch opens", s.hatch_open("B03"))
	pc.on_part(&"eq_B03_BC_up")
	var det: Node3D = _hold_detector()
	_check("Deck A's ultrasonic leak detector is the tool used (one instrument, not a copy)", det != null)
	pc.on_part(&"site_b03_feed")
	_drop()
	_check("leak detector pins the gland", bool(s.leak("b03_feed").get("found", false)))
	# Repair: gland packing from the LEAK KIT is consumed.
	var nkit0: int = _count(&"gland_packing")
	_hold(&"gland_packing")
	pc.on_part(&"site_b03_feed")
	await _frames(2)
	_check("gland repacked: defect repaired, ONE packing set consumed", String(s.leak("b03_feed")["state"]) == "repaired" and _count(&"gland_packing") == nkit0 - 1)
	_drop()
	_run(20.0)
	# Hold test: hatch + EQ shut, 20 s.
	pc.on_part(&"hatch_B03_B03")
	pc.on_part(&"test_B03_B03")
	_check("hold test running", String(pc.hold.get("B03", {}).get("state", "")) == "running")
	for i in 90:
		pc.hold["B03"]["t"] = float(pc.hold["B03"]["t"]) + 0.25
		s.step(0.25)
		await process_frame
		if pc.hold["B03"]["state"] != "running":
			break
	_check("hold test PASSES on a real repair (%+.3f kPa/min)" % float(pc.hold["B03"].get("rate", 0.0)), String(pc.hold["B03"]["state"]) == "pass")
	pc.on_part(&"hatch_B03_B03")
	var o: Dictionary = await _wait_closed(&"l09_pressure")
	_check("L09 closes REPAIRED (outcome %s)" % pc.outcome.get(&"l09_pressure", ""), String(o.get("status", "")) == "done" and pc.outcome.get(&"l09_pressure", "") == "repaired")
	s.clear_pressure()


func _hull_leak() -> void:
	dp.raise_order(&"l09_pressure", "test: hull")
	if pc.leak_id != "hull_b04":
		# The seed picked another site: re-arm on a real hull defect.
		s.clear_pressure()
		s.inject_leak("hull_b04", 2)
		pc.task_rearm(&"l09_pressure", 0)
	_check("hull variant armed on the real B-04 penetration", pc.leak_id == "hull_b04" and s.leak("hull_b04").get("comp", "") == "B04")
	pc.on_part(&"pcp_read")
	_hold_detector()
	pc.on_part(&"site_hull_b04")
	_drop()
	var nkit0: int = _count(&"leak_patch")
	_hold(&"leak_patch")
	pc.on_part(&"site_hull_b04")
	await _frames(2)
	_drop()
	_check("temporary clamp patch: state temp, ONE patch consumed", String(s.leak("hull_b04")["state"]) == "temp" and _count(&"leak_patch") == nkit0 - 1)
	_run(60.0)
	_check("with the patch the station holds (B core %+.2f/min)" % s.trend("BC"), s.trend("BC") > -0.1)
	pc.on_part(&"hatch_B04_BC")
	pc.on_part(&"test_B04_B04")
	for i in 100:
		pc.hold["B04"]["t"] = float(pc.hold["B04"]["t"]) + 0.25
		s.step(0.25)
		await process_frame
		if pc.hold["B04"]["state"] != "running":
			break
	_check("the hold test FAILS on a patch (%+.2f kPa/min) -- stabilised is not repaired" % float(pc.hold["B04"].get("rate", 0.0)), String(pc.hold["B04"]["state"]) == "fail")
	pc.on_part(&"hatch_B04_BC")
	_hold(&"gland_packing")
	pc.on_part(&"site_hull_b04")
	_drop()
	_check("no interior permanent repair of a hull puncture", String(s.leak("hull_b04")["state"]) == "temp")
	pc.on_part(&"log")
	var o: Dictionary = await _wait_closed(&"l09_pressure")
	_check("L09 closes STABILIZED (outcome %s)" % pc.outcome.get(&"l09_pressure", ""), String(o.get("status", "")) == "done" and pc.outcome.get(&"l09_pressure", "") == "stabilized")
	_check("...and hands the permanent repair to A06 (raised)", dp.has_open_order(&"a06_hull"))
	_check("the defect is still there (no spontaneous repair)", String(s.leak("hull_b04").get("state", "")) == "temp")


func _seal_and_save() -> void:
	# Deferral path + mid-emergency save/load.
	var sg: Node = main.get_node("SaveGame")
	s.press["leaks"] = s.press["leaks"].filter(func(x): return String(x["id"]) != "b08_seal")
	s.inject_leak("b08_seal", 2)
	dp.raise_order(&"l09_pressure", "test: seal")
	if pc.leak_id != "b08_seal":
		pc.task_rearm(&"l09_pressure", 0)
		pc.leak_id = "b08_seal"
	pc.on_part(&"pcp_read")
	pc.on_part(&"hatch_B08_BC")
	_run(20.0)
	# In memory, through JSON exactly like the file (never the real save).
	var d: Dictionary = JSON.parse_string(JSON.stringify(sg.collect_state()))
	_check("mid-emergency state captured for save", not d.is_empty())
	var p08: float = s.pressure("B08")
	var nleaks: int = s.press["leaks"].size()
	s.clear_pressure()
	if not d.is_empty():
		sg.apply_state(d)
		await _frames(4)
	_check("load: the leak, its isolation and the low B-08 pressure come back exactly (%.1f kPa, %d defects)" % [s.pressure("B08"), s.press["leaks"].size()],
		absf(s.pressure("B08") - p08) < 0.01 and s.press["leaks"].size() == nleaks and not s.hatch_open("B08") and String(s.leak("b08_seal").get("state", "")) == "active")
	pc.on_part(&"log")
	await _wait_closed(&"l09_pressure")
	_check("left isolated + station holding -> DEFERRED", pc.outcome.get(&"l09_pressure", "") == "deferred")
	# An old (Round 49) save: no "press" -> a healthy hull, no emergency.
	s.load_dict({"water": {}})
	_check("a pre-Round-50 save gets a healthy hull (no leaks, every hatch open)", s.press["leaks"].is_empty() and s.hatch_open("B08") and absf(s.pressure("B08") - s.P_NOM) < 0.01)


func _count(kind: StringName) -> int:
	var n := 0
	for p in get_nodes_in_group(&"deck_b_part"):
		if p.get("item_id") == kind and not p.is_queued_for_deletion():
			n += 1
	return n


func _frames(n: int) -> void:
	for i in n:
		await process_frame
