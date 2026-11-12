extends SceneTree
## Round 49: FABRICATION WORKSHOP (B-04) and PAYLOAD LABORATORY (B-05).
##   workshop  bench test (wrong leads / wrong range refused; the reading
##             comes from the part's real condition; sorted to the matching
##             tray); reconditioning a damaged bearing cartridge (vise,
##             screws, cover order enforced, the worn sub-component found
##             and replaced) -> a SERVICEABLE part instance; torque cross
##             pattern (adjacent final -> uneven gap -> back off -> redo);
##             fabricator refuses flight-critical templates, an unlevelled
##             bed prints a failed part, a levelled bed a good one
##             (material consumed); tool calibration check.
##   lab       glovebox interlocks (inner door before purge, both doors
##             open), sealed-container transfer; leak test finds a loose
##             clamp ring; optical alignment converges on the real spot;
##             incubator drift traced to the LAB COOLANT BRANCH and fixed at
##             Thermal Control (cross-room); payload power: FEED-1 chatter
##             (intermittent) -> reroute B2 at Engineering (E10) -> stable;
##             the transient variant closes as NOT REPRODUCED.
const L = preload("res://scripts/deck_b/deck_b_layout.gd")
var _ok := true
var main: Node
var dp: Node
var s: Node
var carry: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	main.get_node("StationAI").set_enabled(false)
	dp = main.get_node("DayPlan")
	s = main.get_node("DeckB/DeckBSystems")
	carry = main.get_node("Player/CarrySystem")
	main.get_node("DayPlan/Clearance").load_dict({"level": 3})
	main.get_node("DayPlan/Clearance").dev_set_deck_b(4)
	await _workshop()
	await _lab()
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _take(it: Node3D) -> Node3D:
	it.interact()
	if carry.is_reaching():
		carry.complete_grasp()
	var h: Node3D = carry._carried_item
	carry._carried_item = null
	return h


func _order(t: StringName) -> Dictionary:
	for o in dp.orders:
		if StringName(o["type"]) == t:
			return o
	return {}


func _wait_closed(t: StringName, max_s: float = 3.0) -> Dictionary:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(max_s * 1000.0):
		await process_frame
		if String(_order(t).get("status", "")) == "done":
			break
	return _order(t)


func _workshop() -> void:
	var w: Node = main.get_node("DeckB/Rooms/Workshop")
	var inbox: Node = w.find_child("BenchInbox", true, false)
	# ---- Bench test.
	dp.raise_order(&"b04_bench", "test")
	var part: Node3D = inbox.items()[0]
	var good: bool = float(part.payload["condition"]) >= 0.7
	var kind: StringName = part.item_id
	w.stow_part(&"fixture", _take(part))
	w.on_part(&"power")
	_check("no reading without the leads", not w.powered)
	var terms: Array = w._need_terms()
	w.on_part(StringName("term%d" % ["+", "-", "SIG"].find(terms[0])))
	w.on_part(StringName("term%d" % ["+", "-", "SIG"].find(terms[1])))
	w.rng_i = (w._need_range() + 1) % 3
	w.on_part(&"power")
	_check("wrong test range refused (current-limited, no damage)", not w.powered)
	w.rng_i = w._need_range()
	w.on_part(&"power")
	_check("%s reading from its real condition: '%s'" % [kind, w.reading.replace("\n", " · ")], w.powered and (w.reading.find("DRIFT") == -1 and w.reading.find("186") == -1) == good)
	w.on_part(&"pass" if good else &"fail")
	w.on_part(&"release")
	if carry.is_reaching():
		carry.complete_grasp()
	var tested: Node3D = carry._carried_item
	carry._carried_item = null
	w.part_stow(&"rack_TrayServiceable" if good else &"rack_TrayRepair", tested)
	var bo: Dictionary = await _wait_closed(&"b04_bench")
	_check("bench test sorted to the %s tray -> %s" % ["SERVICEABLE" if good else "REPAIR", bo.get("outcome", "?")], bo.get("status", "") == "done" and String(tested.payload["state"]) == ("serviceable" if good else "repair"))
	# ---- Recondition.
	dp.raise_order(&"b04_recondition", "test")
	var bc: Node3D = null
	for it in inbox.items():
		if it.item_id == &"bearing_cartridge":
			bc = it
	var serial: String = String(bc.payload.get("serial", ""))
	w.stow_part(&"vise", _take(bc))
	w.on_part(&"cover")
	_check("cover stays on until the part is clamped", w.cover_on)
	w.on_part(&"vise_lever")
	w.on_part(&"cover")
	_check("cover stays on until the four screws are out", w.cover_on)
	for k in 4:
		w.on_part(StringName("screw%d" % k))
	w.on_part(&"cover")
	w.on_part(&"magnifier")
	var worn: int = w.sub_state.find("worn")
	_check("the worn sub-component is found (%s)" % (w.SUBS[&"bearing_cartridge"][worn] if worn >= 0 else "none"), worn >= 0)
	w.on_part(StringName("sub%d" % worn))
	w.on_part(&"cover")
	_check("cover won't seat with a sub-component missing", not w.cover_on)
	w.on_part(StringName("drawer%d" % ((worn + 1) % 3)))
	w.on_part(StringName("sub%d" % worn))
	_check("a wrong spare doesn't fit its seat", w.sub_state[worn] == "out")
	w.on_part(StringName("drawer%d" % worn))
	w.on_part(StringName("sub%d" % worn))
	w.on_part(&"cover")
	for k in 4:
		w.on_part(StringName("screw%d" % k))
	w.on_part(&"vise_lever")
	await process_frame
	var serv: Node = w.find_child("TrayServiceable", true, false)
	var out: Node3D = null
	for it in serv.items():
		if it.item_id == &"bearing_cartridge":
			out = it
	_check("reconditioned: the SAME instance (serial %s) is serviceable, condition 1.0" % serial, out != null and String(out.payload["serial"]) == serial and String(out.payload["state"]) == "serviceable" and float(out.payload["condition"]) == 1.0)
	var ro: Dictionary = await _wait_closed(&"b04_recondition")
	_check("recondition order -> %s" % ro.get("outcome", "?"), ro.get("status", "") == "done")
	# ---- Torque.
	dp.raise_order(&"b04_torque", "test")
	for k in 4:
		w.on_part(StringName("tbolt%d" % k))
	w.on_part(&"tbolt0")
	w.on_part(&"tbolt1")
	_check("adjacent final torque -> gap uneven", w.gap_uneven)
	w.on_part(&"tverify")
	_check("verification refused while uneven", not w.torque_verified)
	w.on_part(&"backoff")
	for k in 4:
		w.on_part(StringName("tbolt%d" % k))
	for k in [0, 2, 1, 3]:
		w.on_part(StringName("tbolt%d" % k))
	w.on_part(&"tverify")
	_check("cross pattern 1-3-2-4: gap even, verified", w.torque_verified and not w.gap_uneven)
	# ---- Fabricator.
	dp.raise_order(&"b04_fab", "test")
	w.tpl = 3
	w.on_part(&"fab_start")
	_check("EVA suit part refused (not certified)", w.printing < 0.0)
	w.tpl = 0
	var spool0: float = w.spool
	w.on_part(&"fab_start")
	await create_timer(10.4).timeout
	var outt: Node = w.find_child("FabOutput", true, false)
	_check("an unlevelled bed prints a FAILED part (material used %.0f %%)" % ((spool0 - w.spool) * 100.0), outt.count() == 1 and String(outt.items()[0].payload["state"]) == "failed" and w.spool < spool0)
	w.bed_off = [0.0, 0.025, -0.025]
	w.on_part(&"fab_start")
	await create_timer(10.4).timeout
	w.on_part(&"fab_inspect")
	var fo: Dictionary = await _wait_closed(&"b04_fab")
	_check("levelled bed -> a good bracket, inspected -> %s" % fo.get("outcome", "?"), fo.get("status", "") == "done")
	# ---- Tools.
	dp.raise_order(&"b04_tools", "test")
	w.td_offset = 0.06
	w.mm_leads_ok = false
	w.on_part(&"tool0")
	w.on_part(&"td_adjust")
	w.on_part(&"tool0")
	w.on_part(&"tool1")
	w.on_part(&"mm_leads")
	w.on_part(&"tool1")
	w.on_part(&"tool2")
	var to: Dictionary = await _wait_closed(&"b04_tools")
	_check("tool inspection: driver re-calibrated, meter leads replaced -> %s" % to.get("outcome", "?"), to.get("status", "") == "done")


func _lab() -> void:
	var lab: Node = main.get_node("DeckB/Rooms/PayloadLab")
	# ---- Glovebox transfer interlocks.
	dp.raise_order(&"b05_transfer", "test")
	var rk: Node = lab.find_child("LabSampleCarriers", true, false)
	var sc: Node3D = _take(rk.items()[0])
	lab.on_part(&"outer_door")
	lab.stow_part(&"chamber", sc)
	lab.on_part(&"inner_door")
	_check("interlock: inner door refused while the outer is open", not lab.inner_open)
	lab.on_part(&"outer_door")
	lab.on_part(&"inner_door")
	_check("interlock: inner door refused before PURGE", not lab.inner_open)
	lab.on_part(&"purge")
	await create_timer(8.3).timeout
	lab.on_part(&"inner_door")
	lab.on_part(&"glove_l")
	lab.on_part(&"chamber")
	lab.on_part(&"inner_door")
	lab.on_part(&"glove_l")
	var tro: Dictionary = await _wait_closed(&"b05_transfer")
	_check("sealed container transferred through a purged chamber -> %s" % tro.get("outcome", "?"), tro.get("status", "") == "done" and lab.tray_has)
	# ---- Leak test.
	dp.raise_order(&"b05_seal", "test")
	lab.gb_leak = "clamp_r"
	lab.on_part(&"leak_test")
	await create_timer(15.3).timeout
	_check("leak test FAILS with a loose clamp ring (decay %.2f kPa)" % (lab.gb_dp + 0.5), not lab.gb_passed)
	lab.on_part(&"glove_r")
	lab.on_part(&"clamp_r")
	lab.on_part(&"leak_test")
	await create_timer(15.3).timeout
	var so: Dictionary = await _wait_closed(&"b05_seal")
	_check("clamp tightened, leak test PASS -> %s" % so.get("outcome", "?"), so.get("status", "") == "done" and so.get("outcome", "") == "repaired")
	# ---- Optics.
	dp.raise_order(&"b05_optics", "test")
	lab.opt = [0.3, -0.2, 0.25, 0.1]
	var sig0: float = lab._signal()
	for k in 4:
		var v: float = float(lab.opt[k])
		var steps: int = int(round(absf(v) / 0.05))
		for i in steps:
			lab.on_part(StringName("opt%d_%s" % [k, "dn" if v > 0.0 else "up"]))
	_check("optical alignment converges on the real spot (%d %% -> %d %%)" % [int(sig0 * 100.0), int(lab._signal() * 100.0)], lab._signal() >= 0.95 and sig0 < 0.5)
	var oo: Dictionary = await _wait_closed(&"b05_optics", 5.0)
	_check("...held -> %s" % oo.get("outcome", "?"), oo.get("status", "") == "done")
	# ---- Incubator drift caused by the lab coolant branch (cross-room).
	dp.raise_order(&"b05_incubator", "test")
	lab.inc_cause = "overcool"
	s.lab["fuse"][0] = true
	s.thermal["v2"] = 1.0
	s.thermal["v1"] = 0.5
	s.thermal["v3"] = 0.0
	for i in 800:
		s.step(0.25)
	_check("over-fed lab coolant branch (%.1f L/min) drags INC-3 off setpoint (%.1f °C)" % [float(s.branch_flows()[1]), float(s.lab["incubator_T"])], absf(float(s.lab["incubator_T"]) - 37.0) > 0.5)
	lab.diag_i = 0
	lab.on_part(&"term_ok")
	_check("HEATER diagnosis refused (heater duty 100 %, branch cold)", lab.inc_diag == "")
	lab.diag_i = 1
	lab.on_part(&"term_ok")
	var thp: Node = main.get_node("DeckB/Rooms/ThermalPlant")
	for i in 2:
		thp.on_part(&"v2_dn")
	thp.on_part(&"v1_up")
	thp.on_part(&"v3_up")
	for i in 800:
		s.step(0.25)
	var io: Dictionary = await _wait_closed(&"b05_incubator", 8.0)
	_check("V2 reduced at Thermal Control -> INC-3 %.1f °C -> %s" % [float(s.lab["incubator_T"]), io.get("outcome", "?")], io.get("status", "") == "done")
	# ---- Payload power: intermittent FEED-1 -> reroute at Engineering.
	dp.raise_order(&"b05_power", "test")
	lab.pwr_variant = "chatter"
	s.power["feed1_fault"] = "chatter"
	s.power["b2_source"] = "F1"
	var drops0: int = lab.pdu_drops
	await create_timer(8.0).timeout
	_check("intermittent: payload input drops out now and then (%d dropouts in 8 s)" % (lab.pdu_drops - drops0), lab.pdu_drops > drops0)
	var link: Node = main.get_node("DeckB/DeckALinks/EngineeringBusLink")
	link.on_part(&"bus_read")
	link.on_part(&"b2_source")
	_check("E10: B2 rerouted to FEED-2 on the real bus (FEED-2 %.2f / %.1f kW)" % [s.feed2_load(), s.FEED2_RATING], s.power["b2_source"] == "F2" and s.feed2_load() <= s.FEED2_RATING)
	var pwo: Dictionary = await _wait_closed(&"b05_power", 14.0)
	_check("payload stable 10 s on FEED-2 -> %s" % pwo.get("outcome", "?"), pwo.get("status", "") == "done" and pwo.get("outcome", "") == "repaired")
	# Transient: not reproduced.
	pwo["status"] = "cancelled"
	lab.outcome.erase(&"b05_power")
	dp.raise_order(&"b05_power", "test2")
	lab.pwr_variant = "transient"
	s.power["feed1_fault"] = ""
	s.power["b2_source"] = "F1"
	lab.pwr_hold = 0.0
	lab.on_part(&"nff")
	_check("NFF refused before watching long enough", not lab.pwr_logged_nff)
	await create_timer(20.5).timeout
	lab.on_part(&"nff")
	await create_timer(0.5).timeout
	var last: Dictionary = {}
	for o in dp.orders:
		if StringName(o["type"]) == &"b05_power" and o["status"] == "done":
			last = o
	_check("transient variant closes as NOT REPRODUCED ('%s')" % last.get("outcome", "?"), last.get("outcome", "") == "not_reproduced")


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
