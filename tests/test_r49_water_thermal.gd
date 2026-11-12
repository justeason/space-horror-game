extends SceneTree
## Round 49: WATER RECOVERY (B-02) and THERMAL CONTROL (B-03) -- real
## procedures on real equipment, driving the authoritative models.
##   water   consumption from the Living Quarters routine draws the potable
##           tank; the raw tank's level starts an automatic cycle (logged);
##           FILTER SERVICE end to end (ΔP, isolation interlock, spent bed
##           out as a real part, IX-1 rejected by the fit check, MF-2 from
##           the finite spares rack, product sample PASS) -> real recovery;
##           PUMP DIAGNOSIS by evidence (wrong diagnosis refused) + priming;
##           the pump's sound is built from its condition.
##   thermal FLOW BALANCING with real handwheels (branch returns move into
##           band); ACOUSTIC PUMP DIAGNOSIS (restriction -> standby pump,
##           strainer cleaned); OVERHEAT (speed fault -> Engineering heats ->
##           standby, controller reset -> primary); BATTERY OVERHEATING
##           (E11) raised by the real battery temperature and closed after
##           the Engineering mitigation + the V1 fix at B-03; radiator trace.
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
	var clr: Node = main.get_node("DayPlan/Clearance")
	clr.load_dict({"level": 3})
	clr.dev_set_deck_b(4)
	await _water()
	await _thermal()
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _take(it: Node3D) -> void:
	it.interact()
	if carry.is_reaching():
		carry.complete_grasp()


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


func _water() -> void:
	var w: Node = main.get_node("DeckB/Rooms/WaterRecovery")
	var wt: Dictionary = s.water
	var p0: float = float(wt["potable_l"])
	s.on_consumed("water")
	_check("drinking draws the potable tank (%.2f -> %.2f L), hygiene water returns to raw" % [p0, float(wt["potable_l"])], absf(p0 - float(wt["potable_l"]) - 0.35) < 0.001)
	wt["raw_l"] = 30.0
	wt["processing"] = false
	s.step(0.25)
	_check("a full raw tank starts an AUTOMATIC cycle (logged: '%s')" % String(wt["starts"].back()["why"]) if not wt["starts"].is_empty() else "none", wt["processing"] and String(wt["starts"].back()["why"]).begins_with("auto"))
	# ---- Filter service.
	var o: Dictionary = dp.raise_order(&"b02_filter", "test")
	_check("filter order raised by a spent bed (life %d %%)" % int(float(wt["filter_life"]) * 100.0), not o.is_empty() and float(wt["filter_life"]) <= 0.36 and s.filter_dp() > 62.0)
	var spares: Node = w.find_child("WaterSpareBeds", true, false)
	var n_mf: int = spares.count(&"mf_bed")
	w.on_part(&"dp")
	w.on_part(&"clamp")
	_check("interlock: the clamp stays shut while the bed is pressurised", not w.clamp_open)
	for i in 4:
		w.on_part(&"v_in_dn")
	w.on_part(&"clamp")
	_check("isolated (V-IN closed) -> clamp opens", w.clamp_open and float(wt["v_in"]) == 0.0)
	w.on_part(&"bed")
	if carry.is_reaching():
		carry.complete_grasp()
	var spent: Node3D = carry._carried_item
	_check("the spent bed comes out as a real part in the hand (%s)" % (spent.get_display_name() if spent != null else "none"), spent != null and spent.item_id == &"mf_bed_spent" and not w.bed_seated)
	carry._carried_item = null
	w.part_stow(&"rack_SpentBedBin", spent)
	_check("...and goes in the spent-bed bin", w.find_child("SpentBedBin", true, false).count(&"mf_bed_spent") == 1)
	var ix: Node3D = null
	var mf: Node3D = null
	for it in spares.items():
		if it.item_id == &"ix_bed":
			ix = it
		elif it.item_id == &"mf_bed" and mf == null:
			mf = it
	_take(ix)
	carry._carried_item = null
	w.stow_part(&"bed", ix)
	if carry.is_reaching():
		carry.complete_grasp()
	_check("fit check: an IX-1 bed will not seat in the MF-2 housing", not w.bed_seated)
	if carry.is_carrying():
		var h: Node3D = carry._carried_item
		carry._carried_item = null
		w.part_stow(&"rack_WaterSpareBeds", h)
	_take(mf)
	carry._carried_item = null
	w.stow_part(&"bed", mf)
	_check("MF-2 bed seated from the finite spares (%d -> %d)" % [n_mf, spares.count(&"mf_bed")], w.bed_seated and spares.count(&"mf_bed") == n_mf - 1 and float(wt["filter_life"]) > 0.95)
	w.on_part(&"clamp")
	for i in 4:
		w.on_part(&"v_in_up")
	wt["processing"] = true
	wt["pump_on"] = true
	w.on_part(&"port")
	w.on_part(&"an_slot")
	for i in 3:
		w.on_part(&"an_mode")
	w.on_part(&"an_pass")
	var oc: Dictionary = await _wait_closed(&"b02_filter")
	_check("product sample PASS (%.0f µS/cm) closes the order: %s" % [w.vial_cond, oc.get("outcome", "?")], oc.get("status", "") == "done" and oc.get("outcome", "") == "repaired" and w.vial_cond <= 30.0)
	_check("service history recorded (station log SERVICE)", main.get_node("DayPlan/StationLog").has_entry("maintenance", "MF-2"))
	# ---- Pump diagnosis + priming.
	dp.raise_order(&"b02_pump", "test")
	wt["pump_fault"] = "air_lock"
	w.pump_seed = "air_lock"
	wt["processing"] = true
	wt["pump_on"] = true
	_check("the pump sounds like its fault (air-lock loop differs from healthy)", w._pump_stream("air_lock") != w._pump_stream(""))
	_check("air lock: outlet pressure low and erratic (%.0f kPa)" % s.water_pressure(), s.water_pressure() < 80.0)
	w.on_part(&"vib")
	w.diag_choice = 1     # SEAL LEAK
	w.on_part(&"diag_ok")
	_check("a diagnosis the evidence doesn't support is refused", w.diag_confirmed == "")
	w.diag_choice = 0     # AIR LOCK
	w.on_part(&"diag_ok")
	w.on_part(&"pump_switch")       # off
	for i in 4:
		w.on_part(&"v_out_dn")
	w.on_part(&"bleed")             # open
	await create_timer(4.4).timeout
	_check("priming: bleeding with the pump stopped vents the air", wt["pump_fault"] == "")
	w.on_part(&"bleed")
	w.on_part(&"pump_switch")
	for i in 4:
		w.on_part(&"v_out_up")
	var po: Dictionary = await _wait_closed(&"b02_pump")
	_check("pump order closed (%s), outlet %.0f kPa" % [po.get("outcome", "?"), s.water_pressure()], po.get("status", "") == "done" and s.water_pressure() > 150.0)


func _thermal() -> void:
	var th: Node = main.get_node("DeckB/Rooms/ThermalPlant")
	var t: Dictionary = s.thermal
	# ---- Balance.
	dp.raise_order(&"b03_balance", "test")
	t["v1"] = 0.25
	t["v2"] = 1.0
	t["v3"] = 0.5
	for i in 600:
		s.step(0.25)
	var hot: float = float(t["ret_eng"])
	_check("misbalanced: the Engineering branch return runs hot (%.1f °C)" % hot, hot > 14.0)
	for i in 2:
		th.on_part(&"v1_up")
	for i in 2:
		th.on_part(&"v2_dn")
	th.on_part(&"v3_dn")
	for i in 600:
		s.step(0.25)
	_check("valves moved the REAL loop: V1 return %.1f °C, V2 return %.1f °C" % [float(t["ret_eng"]), float(t["ret_lab"])], th._in_band())
	var bo: Dictionary = await _wait_closed(&"b03_balance", 8.0)
	_check("balanced and held -> order closed (%s)" % bo.get("outcome", "?"), bo.get("status", "") == "done")
	# ---- Acoustic diagnosis.
	dp.raise_order(&"b03_pump", "test")
	t["fault"] = "restriction"
	th.basket_clean = false
	th.diag_confirmed = ""
	th.probe = {}
	th.on_part(&"pt_bearing")
	th.on_part(&"pt_casing")
	th.diag_choice = 0
	th.on_part(&"diag_ok")
	_check("acoustic diagnosis: BEARING refused for a restriction", th.diag_confirmed == "")
	th.diag_choice = 1
	th.on_part(&"diag_ok")
	th.on_part(&"strainer_cap")
	_check("interlock: strainer stays shut while P-301 runs", not th.strainer_open)
	th.on_part(&"changeover")
	th.on_part(&"strainer_cap")
	th.on_part(&"basket")
	th.on_part(&"basket")
	th.on_part(&"basket")
	th.on_part(&"strainer_cap")
	th.on_part(&"changeover")
	var po: Dictionary = await _wait_closed(&"b03_pump")
	_check("strainer cleaned on the standby pump, primary restored -> %s" % po.get("outcome", "?"), po.get("status", "") == "done" and t["fault"] == "" and not t["standby"])
	# ---- Overheat.
	t["fault"] = "speed_drop"
	for i in 800:
		s.step(0.25)
	_check("a P-301 speed fault heats Engineering (%.1f °C) and the battery (%.1f °C)" % [float(t["eng_T"]), float(t["batt_T"])], float(t["eng_T"]) > 32.0)
	await create_timer(0.7).timeout
	_check("...the model raises the overheat order itself", String(_order(&"b03_overheat").get("status", "")) == "open")
	th.on_part(&"p301_reset")
	_check("controller reset refused while P-301 carries the loop", t["fault"] == "speed_drop")
	th.on_part(&"changeover")
	th.on_part(&"p301_reset")
	th.on_part(&"changeover")
	for i in 800:
		s.step(0.25)
	var oo: Dictionary = await _wait_closed(&"b03_overheat", 8.0)
	_check("stabilised (ENG %.1f, BATT %.1f °C) -> %s" % [float(t["eng_T"]), float(t["batt_T"]), oo.get("outcome", "?")], oo.get("status", "") == "done")
	# ---- Battery overheating (E11) across Engineering and B-03.
	var link: Node = main.get_node("DeckB/DeckALinks/EngineeringBusLink")
	t["v1"] = 0.0
	for i in 1000:
		s.step(0.25)
	await create_timer(0.7).timeout
	_check("V1 shut: battery %.1f °C -> E11 battery overheating raised" % float(t["batt_T"]), String(_order(&"e11_battery").get("status", "")) == "open")
	link.on_part(&"batt_read")
	link.on_part(&"charge_limit")
	_check("charge limit really lowers the battery's heat load", float(t["charge_limit"]) == 0.5 and s.heat_loads()[0] < 3.9)
	for i in 3:
		th.on_part(&"v1_up")
	for i in 800:
		s.step(0.25)
	link.on_part(&"charge_limit")
	for i in 200:
		s.step(0.25)
	var eo: Dictionary = await _wait_closed(&"e11_battery", 8.0)
	_check("battery %.1f °C after the V1 fix at B-03 -> E11 %s" % [float(t["batt_T"]), eo.get("outcome", "?")], eo.get("status", "") == "done")
	# ---- Radiator trace (actuator).
	dp.raise_order(&"b03_radiator", "test")
	t["rad_fault"] = "actuator"
	t["rad"] = [1.0, 0.35]
	for i in 400:
		s.step(0.25)
	_check("a stuck RAD-2 actuator raises the supply temperature (%.1f °C)" % float(t["supply"]), float(t["supply"]) > 9.0)
	th.on_part(&"rad_sel")
	th.on_part(&"actuator")
	_check("actuator swap refused before isolating RAD-2", t["rad_fault"] == "actuator")
	th.on_part(&"rad_iso_dn")
	var spares: Node = th.find_child("ThermalSpares", true, false)
	var va: Node3D = null
	for it in spares.items():
		if it.item_id == &"valve_actuator":
			va = it
	_take(va)
	th.on_part(&"actuator")
	th.on_part(&"rad_iso_up")
	var ro: Dictionary = await _wait_closed(&"b03_radiator")
	_check("actuator replaced from the spares (consumed), RAD-2 restored -> %s" % ro.get("outcome", "?"), ro.get("status", "") == "done" and t["rad_fault"] == "" and spares.count(&"valve_actuator") == 0)


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
