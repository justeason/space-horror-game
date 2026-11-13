extends SceneTree
## Round 50: A01 EVA SUIT INSPECTION and A06 HULL DAMAGE, end to end on the
## real suit, airlock, tethers, worksites and pressure network.
##   A01  the suit's own state (O2, battery, seals, comms, hooks) gates
##        donning; each fault has its own physical fix; the pressure test
##        reads the real seal, the comms check the real comm cap; O2 / battery
##        change only through the umbilical (never reset on opening); the
##        full check is not demanded for every EVA; save / load mid-check.
##   A06  three real sites within tether reach; LOCATE inside; the caddy
##        part is consumed once; cross-pattern torque; the exterior patch
##        repairs the SAME network leak L09 isolated; VERIFY from inside;
##        deferral when EVA / parts are unavailable; save / load mid-repair.
const Graph = preload("res://scripts/exterior/eva_anchor_graph.gd")
var _ok := true
var main: Node
var dp: Node
var s: Node
var ss: Node
var hr: Node
var pc: Node
var eva: Node
var fb: Node
var carry: Node
var clr: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 12: await process_frame
	main.get_node("StationAI").set_enabled(false)
	dp = main.get_node("DayPlan")
	s = main.get_node("DeckB/DeckBSystems")
	ss = main.get_node("DeckB/DeckALinks/SuitService")
	hr = main.get_node("DeckB/DeckALinks/HullRepair")
	pc = main.get_node("DeckB/Rooms/PressureControl")
	eva = main.get_node("EVASystem") if main.has_node("EVASystem") else main.find_child("EVASystem", true, false)
	if eva == null:
		eva = get_first_node_in_group(&"eva_system")
	fb = main.get_node("FreeMoveBody")
	carry = main.get_node("Player/CarrySystem")
	clr = main.get_node("DayPlan/Clearance")
	clr.load_dict({"level": 3})
	clr.dev_set_deck_b(4)
	await _reach()
	await _suit()
	await _hull_lower()
	await _hull_impact_and_defer()
	await _dev_controls()
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _check(label: String, cond: bool) -> void:
	if cond:
		print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false


func _until(cond: Callable, max_s: float) -> bool:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(max_s * 1000.0):
		if cond.call():
			return true
		await process_frame
	return bool(cond.call())


func _order(t: StringName) -> Dictionary:
	for i in range(dp.orders.size() - 1, -1, -1):
		if StringName(dp.orders[i]["type"]) == t:
			return dp.orders[i]
	return {}


func _count(kind: StringName) -> int:
	var n := 0
	for p in get_nodes_in_group(&"deck_b_part"):
		if p.get("item_id") == kind and not p.is_queued_for_deletion():
			n += 1
	return n


func _item(kind: StringName) -> Node3D:
	for p in get_nodes_in_group(&"deck_b_part"):
		if p.get("item_id") == kind and not p.is_queued_for_deletion():
			return p
	return null


# ---------------------------------------------------------------- reach
func _reach() -> void:
	_check("ring D1 is on the anchor graph, linked from A3 (%.2f m <= 3.8)" % Graph.pos("A3").distance_to(Graph.pos("D1")), Graph.index_of("D1") >= 0 and Graph.route("A1", "D1").size() > 0 and Graph.pos("A3").distance_to(Graph.pos("D1")) <= 3.8)
	for site in hr.SITES:
		var d: Array = hr.SITES[site]
		var ring: Vector3 = Graph.pos(String(d[4]))
		_check("hull site %s: stance %.2f m from ring %s (tether 5.5), %.2f m from the work point" % [site, (d[3] as Vector3).distance_to(ring), d[4], (d[3] as Vector3).distance_to(d[1])],
			(d[3] as Vector3).distance_to(ring) < 5.0 and (d[3] as Vector3).distance_to(d[1]) < 1.0 and eva.worksites.has("hull_" + site))
	# The lower site's stance and the route to it are clear of structure
	# (no point inside the hull's interior footprint, no collision there).
	var space: PhysicsDirectSpaceState3D = main.get_viewport().world_3d.direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.3
	q.shape = sph
	q.collision_mask = 1
	var blocked: Array = []
	for site in hr.SITES:
		q.transform = Transform3D(Basis(), hr.SITES[site][3])
		if not space.intersect_shape(q, 4).is_empty():
			blocked.append(site)
	_check("every hull worksite stance is free space (blocked: %s)" % str(blocked), blocked.is_empty())


# ----------------------------------------------------------------- A01
func _suit() -> void:
	_check("Chapter-One default: a healthy suit, nothing due, donning allowed", ss.don_blocker() == "" and ss.status_word() == "GO")
	ss.inject_fault("seal_neck")
	_check("a seal fault flags FULL INSPECTION DUE and blocks donning", ss.don_blocker().find("INSPECTION") != -1)
	eva.on_part(&"locker")
	_check("...the real locker refuses the suit", not eva.suited)
	dp.raise_order(&"a01_suit", "test")
	_check("A01 raised", dp.has_open_order(&"a01_suit"))
	_check("the existing seal fault stays THE fault (no second one injected)", ss.suit["seal"] == "neck" and ss.suit["comms"] == "" and ss.suit["hooks"][0] and ss.suit["hooks"][1])
	# Panel tests need the diagnostic umbilical.
	ss.on_part(&"ptest")
	_check("P-TEST refused before the diagnostic umbilical is connected", ss.ptest_t < 0.0)
	for t in [&"t_helmet", &"t_neck", &"t_glove_L", &"t_glove_R", &"t_boots", &"t_hook_0", &"t_hook_1", &"t_diag"]:
		ss.on_part(t)
	_check("physical inspection of helmet, neck ring, gloves, boots, hooks + diag", ss._done(ss.insp.get("helmet")) and ss._done(ss.insp.get("gloves")) and ss._done(ss.insp.get("boots")) and ss._done(ss.insp.get("hooks")) and ss._done(ss.insp.get("diag")))
	ss.on_part(&"ptest")
	ss.ptest_t = ss.PTEST_S
	await process_frame
	await process_frame
	_check("the pressure test FAILS on the real nicked O-ring", ss.insp.get("ptest", "") == "fail")
	ss.on_part(&"signoff")
	_check("sign-off refused with a failed test", not ss._done(ss.insp.get("signed", false)))
	var kits0: int = _count(&"suit_seal_kit")
	carry._carried_item = _item(&"suit_seal_kit")
	carry._carried_item_id = &"suit_seal_kit"
	ss.on_part(&"t_neck")
	carry._carried_item = null
	carry._carried_item_id = &""
	await process_frame
	_check("O-ring replaced with ONE suit seal kit from the EVA stock", ss.suit["seal"] == "" and _count(&"suit_seal_kit") == kits0 - 1)
	ss.on_part(&"ptest")
	ss.ptest_t = ss.PTEST_S
	await process_frame
	await process_frame
	_check("the re-test PASSES", ss.insp.get("ptest", "") == "pass")
	# O2: opening the panel / reading does NOT refill; FILL does, over time.
	ss.suit["o2"] = 0.5
	ss.on_part(&"panel_read")
	_check("reading the panel never resets the reserve (O2 still %d%%)" % roundi(ss.suit["o2"] * 100.0), absf(ss.suit["o2"] - 0.5) < 0.01 and not ss._done(ss.insp.get("o2")))
	var mk0: float = float(s.press["makeup"])
	ss.on_part(&"fill")
	await _until(func(): return float(ss.suit["o2"]) >= 0.99, 70.0 if false else 0.1)
	ss.suit["o2"] = minf(float(ss.suit["o2"]) + 0.0, 1.0)
	for i in 240:
		ss._process(0.25)
	_check("FILL raises the real reserve over time (now %d%%), drawing station gas (reserve %.0f -> %.0f)" % [roundi(ss.suit["o2"] * 100.0), mk0, float(s.press["makeup"])], float(ss.suit["o2"]) >= 0.99 and float(s.press["makeup"]) < mk0)
	ss.on_part(&"panel_read")
	ss.on_part(&"comms")
	_check("O2 / battery / comms checks", ss._done(ss.insp.get("o2")) and ss._done(ss.insp.get("batt")) and ss._done(ss.insp.get("comms")))
	ss.on_part(&"signoff")
	var o: Dictionary = await _wait_closed(&"a01_suit")
	_check("signed off GO; A01 closes REPAIRED (outcome %s)" % ss.outcome.get(&"a01_suit", ""), String(o.get("status", "")) == "done" and ss.outcome.get(&"a01_suit", "") == "repaired" and ss.don_blocker() == "")
	# Each other fault has its own fix.
	ss.inject_fault("comms")
	for t in [&"t_diag"]:
		ss.on_part(t)
	ss.on_part(&"comms")
	_check("COMMS check fails on the unseated comm cap", ss.insp.get("comms", "") == "fail")
	ss.on_part(&"t_helmet")
	ss.on_part(&"t_helmet")
	ss.on_part(&"comms")
	_check("reseating the comm cap fixes it (check passes)", ss.suit["comms"] == "" and ss.insp.get("comms", "") == "pass")
	ss.inject_fault("o2")
	ss.on_part(&"t_diag")
	ss.on_part(&"fill")
	_check("LOW O2 (supply closed): FILL refused until the supply valve opens", not ss.filling)
	ss.on_part(&"supply")
	ss.on_part(&"fill")
	_check("...supply open: filling", ss.filling)
	ss.inject_fault("batt")
	ss.on_part(&"t_diag")
	ss.on_part(&"charge")
	_check("LOW BATTERY (charger tripped): CHARGE refused until reset", not ss.charging)
	ss.on_part(&"charger")
	ss.on_part(&"charge")
	_check("...charger reset: charging", ss.charging)
	ss.inject_fault("hook")
	var bad: int = 0 if not ss.suit["hooks"][0] else 1
	ss.on_part(StringName("t_hook_%d" % bad))
	ss.on_part(StringName("t_hook_%d" % bad))
	_check("a sticking tether hook gate is serviced at the hook", ss.suit["hooks"][bad])
	# Save / load mid-check.
	var sg: Node = main.get_node("SaveGame")
	ss.suit["o2"] = 0.73
	var d: Dictionary = JSON.parse_string(JSON.stringify(sg.collect_state()))
	ss.clear_faults()
	sg.apply_state(d)
	for i in 4: await process_frame
	clr.load_dict({"level": 3})
	clr.dev_set_deck_b(4)              # the developer tier override is not saved
	_check("save / load: suit reserve and flags restored (O2 %d%%, full due %s)" % [roundi(ss.suit["o2"] * 100.0), str(ss.suit["full_due"])], absf(float(ss.suit["o2"]) - 0.73) < 0.02 and bool(ss.suit["full_due"]))
	ss.clear_faults()
	ss.suit["last_full_day"] = dp.day_number
	_check("a healthy, recently checked suit needs only the short status (no full checklist)", ss.don_blocker() == "")


func _wait_closed(t: StringName, max_s: float = 3.0) -> Dictionary:
	await _until(func(): return String(_order(t).get("status", "")) == "done", max_s)
	return _order(t)


# ----------------------------------------------------------------- A06
func _go_outside() -> void:
	var al: Node = main.get_node("AirlockChamber")
	if not eva.suited:
		eva.set_suited(true)
	fb.sync_to_eye_position(Vector3(-4.8, 1.6, -1.45))
	for i in 4: await physics_frame
	al.begin_cycle_out()
	await _until(func(): return al.sequence == "", 12.0)
	fb.sync_to_eye_position(Vector3(-4.8, 1.6, -3.3))
	for i in 6: await physics_frame


func _at(site: String, ring: String) -> void:
	var w: Dictionary = eva.worksites["hull_" + site]
	fb.sync_to_eye_position((w["stance"] as Vector3) + Vector3(0.2, 0.15, 0.2))
	fb.velocity = Vector3.ZERO
	eva.leave_worksite()
	eva.tethers = [{"ring": Graph.index_of(ring), "state": "secured", "t": 1.0, "seq": 50, "target": -1}, eva._new_tether()]
	eva.anchor_index = Graph.index_of(ring)
	await create_timer(0.15).timeout


func _go_inside() -> void:
	var al: Node = main.get_node("AirlockChamber")
	eva.leave_worksite()
	eva.tethers = [eva._new_tether(), eva._new_tether()]
	fb.sync_to_eye_position(Vector3(-4.8, 1.6, -3.3))
	for i in 4: await physics_frame
	eva.request_cycle_in()
	await _until(func(): return al.sequence == "" and al.outer_open == false, 6.0)
	fb.sync_to_eye_position(Vector3(-4.8, 1.6, -1.45))
	for i in 6: await physics_frame
	await _until(func(): return al.sequence == "", 12.0)
	if eva.outside:
		eva._set_outside(false)
		eva.zone = "station"
	eva.set_suited(false)
	for i in 4: await process_frame


func _hull_lower() -> void:
	# L09 already stabilised the B-04 puncture with a temporary patch.
	s.clear_pressure()
	hr.clear_damage()
	hr.strike("lower", 2)
	_check("one physical defect: the hull strike IS the network leak (no duplicate)", s.leak("hull_b04").get("comp", "") == "B04" and s.press["leaks"].filter(func(x): return x["id"] == "hull_b04").size() == 1)
	s.set_leak_state("hull_b04", "temp")
	dp.raise_order(&"a06_hull", "test lower")
	_check("A06 armed on the lower site (site %s, order %s)" % [hr.active_site, str(_order(&"a06_hull"))], hr.active_site == "lower" and dp.has_open_order(&"a06_hull"))
	hr.on_part(&"locate")
	_check("LOCATE inside: site found", bool(hr.dmg["lower"]["found"]))
	# Load the caddy with ONE patch kit from the EVA stock.
	var kit: Node3D = _item(&"hull_patch_kit")
	var kits0: int = _count(&"hull_patch_kit")
	ss.caddy.stow(kit)
	_check("hull patch kit in the suit caddy (a real item)", hr._caddy_item([&"hull_patch_kit"]) != null)
	ss.suit["last_full_day"] = dp.day_number
	await _go_outside()
	_check("outside for the hull work", eva.outside)
	await _at("lower", "D1")
	hr.on_part(&"x_lower_work")
	_check("hardware refuses until stabilised at the handhold", not bool(hr.dmg["lower"]["inspected"]))
	_check("stabilise at the lower handhold on ring D1", eva.stabilize("hull_lower"))
	await create_timer(0.8).timeout
	for i in 3:
		hr.on_part(&"x_lower_work")            # probe, prep, fit
	_check("probe, surface prep, patch fitted from the caddy (ONE kit consumed)", bool(hr.dmg["lower"]["fitted"]) and _count(&"hull_patch_kit") == kits0 - 1)
	var guard: int = 0
	while int(hr.dmg["lower"]["align"]) != 0 and guard < 4:
		hr.on_part(&"x_lower_work")
		guard += 1
	hr.on_part(&"x_lower_work")
	_check("patch slid into line and seated", int(hr.dmg["lower"]["align"]) == 0 and bool(hr.dmg["lower"]["seated"]))
	hr.on_part(&"x_lower_bolt0")
	hr.on_part(&"x_lower_bolt1")
	_check("a non-cross torque order is REFUSED (plate rocks, fasteners reset)", (hr.dmg["lower"]["bolts"] as Array).is_empty())
	for k in [0, 2, 1, 3]:
		hr.on_part(StringName("x_lower_bolt%d" % k))
	_check("cross-pattern torque: 4/4", (hr.dmg["lower"]["bolts"] as Array).size() == 4)
	hr.on_part(&"x_lower_work")
	_check("seal probe: the exterior patch REPAIRS the same network leak", hr.dmg["lower"]["state"] == "repaired" and String(s.leak("hull_b04")["state"]) == "repaired")
	hr.on_part(&"verify")
	_check("VERIFY refused while still outside", not hr.verified)
	await _go_inside()
	s.set_hatch("B04", true)
	for i in 40: s.step(0.25)
	hr.on_part(&"verify")
	var o: Dictionary = await _wait_closed(&"a06_hull")
	_check("VERIFY inside (B-04 %.1f kPa, no flow); A06 closes REPAIRED (outcome %s)" % [s.pressure("B04"), hr.outcome.get(&"a06_hull", "")], String(o.get("status", "")) == "done" and hr.outcome.get(&"a06_hull", "") == "repaired")
	_check("no phantom kit: still exactly one fewer patch kit", _count(&"hull_patch_kit") == kits0 - 1)


func _hull_impact_and_defer() -> void:
	hr.clear_damage()
	hr.strike("impact", 3)
	dp.raise_order(&"a06_hull", "test impact")
	if hr.active_site != "impact":
		hr.active_site = "impact"
	hr.on_part(&"locate")
	# Save / load mid-repair: no duplicate damage, no spontaneous repair.
	var sg: Node = main.get_node("SaveGame")
	hr.dmg["impact"]["inspected"] = true
	hr.dmg["impact"]["bolts"] = [0, 2]
	var d: Dictionary = JSON.parse_string(JSON.stringify(sg.collect_state()))
	hr.clear_damage()
	sg.apply_state(d)
	for i in 4: await process_frame
	clr.load_dict({"level": 3})
	clr.dev_set_deck_b(4)
	_check("load mid-repair: the impact damage and its progress come back (2 fasteners out), not repaired, one site", hr.dmg["impact"]["state"] == "damaged" and (hr.dmg["impact"]["bolts"] as Array).size() == 2 and hr.find_children("HullSite_impact", "", false, false).size() == 1)
	# No EVA authorisation -> deferred pending EVA.
	clr.load_dict({"level": 2})
	clr.dev_set_deck_b(4)
	hr.on_part(&"defer")
	await _wait_closed(&"a06_hull")
	_check("no EVA clearance -> DEFERRED pending EVA (outcome %s)" % hr.outcome.get(&"a06_hull", ""), hr.outcome.get(&"a06_hull", "") == "deferred_eva")
	_check("the damage stays on the hull (deferred, not repaired)", hr.dmg["impact"]["state"] == "damaged")
	clr.load_dict({"level": 3})
	clr.dev_set_deck_b(4)
	# Severity-1 impact: inspected, no structural breach.
	hr.clear_damage()
	hr.strike("seam", 1)
	hr.dmg["impact"] = hr._fresh("impact")
	hr.strike("impact", 1)
	dp.raise_order(&"a06_hull", "test sev1")
	hr.active_site = "impact"
	hr.on_part(&"locate")
	await _go_outside()
	await _at("impact", "A3")
	_check("stabilise at the Engineering panel (ring A3)", eva.stabilize("hull_impact"))
	await create_timer(0.8).timeout
	hr.on_part(&"x_impact_work")
	hr.on_part(&"x_impact_work")
	await _go_inside()
	hr.on_part(&"verify")
	await _wait_closed(&"a06_hull")
	_check("severity-1 impact: INSPECTED, NO STRUCTURAL BREACH (outcome %s)" % hr.outcome.get(&"a06_hull", ""), hr.outcome.get(&"a06_hull", "") == "inspected_no_breach")
	hr.clear_damage()
	s.clear_pressure()


# ------------------------------------------------------- F8 developer
func _dev_controls() -> void:
	var panel: Node = main.get_node_or_null("DevPanel")
	_check("developer panel present in the debug test build", panel != null)
	if panel == null:
		return
	var parts0: int = get_nodes_in_group(&"deck_b_part").size()
	var mil0: Array = main.get_node("StoryEvents").milestones.duplicate() if main.has_node("StoryEvents") else []
	var p_before: float = s.pressure("B04")
	var r1: String = str(s.pressure_anomaly(true))
	var r2: String = str(ss.record_anomaly(true))
	var r3: String = str(hr.repaired_by_unknown("seam", true))
	_check("story-hook PREVIEWS return a record but write nothing (pressure %.1f unchanged, no ghosts / anomaly logs)" % s.pressure("B04"),
		r1.find("TRANSIENT") != -1 and absf(s.pressure("B04") - p_before) < 0.001 and s.press_ghosts.is_empty() and ss.anomaly_log.is_empty() and hr.anomaly_log.is_empty() and r2 != "" and r3 != "")
	s.inject_leak("b08_seal", 3)
	hr.strike("seam", 2)
	ss.inject_fault("comms")
	var txt: String = panel.deck_b_text()
	_check("F8 status shows the pressure, suit and hull state", txt.find("Pressure") != -1 and txt.find("Suit A-1") != -1 and txt.find("Hull:") != -1)
	panel.reset_pressure()
	ss.clear_faults()
	hr.clear_damage()
	_check("F8 resets: healthy network, suit and hull; inventory untouched (%d parts); story milestones untouched" % get_nodes_in_group(&"deck_b_part").size(),
		s.active_leaks().is_empty() and ss.status_word() == "GO" and hr._first_damaged() == "" and get_nodes_in_group(&"deck_b_part").size() == parts0
		and (mil0 == (main.get_node("StoryEvents").milestones if main.has_node("StoryEvents") else [])))
