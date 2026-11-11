extends SceneTree
## Round 41 Priorities 3, 5, 6, 20, 21: SOLAR ARRAYS, SOLAR POWER and the
## THREE SOLAR EVA TASKS.
##  - geometry: two long wings on a truss bolted to the hull, framed cell
##    sections, render-efficient (MultiMesh), exterior cameras see them;
##  - power model: wing faults lower generation; reserve drains slowly on a
##    deficit and charges on a surplus; Bus A droops only at low reserve;
##    the power panel shows it; StationStatus warns; save/load;
##  - tasks: scheduling (gradual, deterministic, one long EVA at a time),
##    each procedure performed at its REAL worksite with its safety rules,
##    the real output change, automatic completion credited once, save/load
##    mid-task without re-rolling.
const Graph = preload("res://scripts/exterior/eva_anchor_graph.gd")
var _ok := true
var main: Node
var dp: Node
var eva: Node
var fb: CharacterBody3D
var sa: Node
var pw: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	# Round 45: this suite tests mechanics, not story access -- full
	# technician clearance (EVA / Comms gates open; gating has its own test).
	main.get_node("DayPlan/Clearance").load_dict({"level": 3})
	dp = main.get_node("DayPlan")
	eva = main.get_node("EvaSystem")
	fb = main.get_node("FreeMoveBody")
	sa = main.get_node("Equipment/SolarArrays")
	pw = main.get_node("Equipment/PowerDistribution")
	_geometry()
	_power_model()
	_schedule()
	eva.set_suited(true)
	await _go_outside()
	await _coupler()
	await _hinge()
	await _clean()
	await _save_load()
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _geometry() -> void:
	var span: float = Graph.RIGHT_WING[1] - Graph.LEFT_WING[1]
	var modules: float = 5.7 - (-7.6)
	_check("span %.1f m vs %.1f m of modules (>= 3x wider)" % [span, modules], span >= 3.0 * modules)
	_check("left and right wings built (%d / %d framed sections)" % [sa.sections["L"].size(), sa.sections["R"].size()], sa.sections["L"].size() >= 12 and sa.sections["R"].size() >= 12)
	var sec: Node3D = sa.sections["L"][0]
	var cells: MeshInstance3D = sec.get_child(0)
	_check("cell surfaces: dark blue cell-grid texture (not a flat black box)", cells.material_override is StandardMaterial3D and (cells.material_override as StandardMaterial3D).albedo_texture != null and sec.get_child_count() >= 6)
	var mm: Array = sa.find_children("*", "MultiMeshInstance3D", true, false)
	var inst := 0
	for m in mm:
		inst += (m as MultiMeshInstance3D).multimesh.instance_count
	_check("truss battens / posts / diagonals / hinges as MultiMesh (%d meshes, %d instances)" % [mm.size(), inst], mm.size() >= 5 and inst > 200)
	_check("node count bounded (%d nodes for the whole array)" % sa.built_nodes, sa.built_nodes < 900)
	_check("collision: ONE static body (truss + 4 blanket boxes), no per-section bodies", sa.find_children("*", "CollisionObject3D", true, false).size() == 1 and sa.get_node("ArrayCollision").get_child_count() == 5)
	_check("wings attach to the hull (truss struts reach the Control Room north face)", sa.find_children("*", "MeshInstance3D", true, false).any(func(m): return absf((m as Node3D).global_position.z + 1.35) < 0.05))
	var net: Node = main.get_node("CameraNetwork")
	_check("Round 42: EXT-01 retired; EXT-05 (solar truss) still watches the left wing route", not net.ids().has("EXT-01") and net.sees("EXT-05", Vector3(-11.3, 1.62, -4.88), 0.6))
	_check("EXT-05 (solar truss) sees the left wing and the mid hinge", net.sees("EXT-05", Vector3(-12.0, 1.12, -4.0), 0.6) and net.sees("EXT-05", Vector3(-15.35, 1.45, -5.2), 0.6))
	var lay_ok := true
	for v in sa.find_children("*", "VisualInstance3D", true, false):
		lay_ok = lay_ok and ((v as VisualInstance3D).layers & (1 << 11)) != 0
	_check("array geometry is on the sunlit EXTERIOR layer", lay_ok)


func _power_model() -> void:
	_check("healthy: 2 x %.1f kW = %.1f kW" % [sa.WING_KW, sa.generation()], absf(sa.generation() - 2.0 * sa.WING_KW) < 0.01)
	_check("load from the real Bus A settings (%.1f kW)" % sa.load_kw(), sa.load_kw() > 5.0 and sa.load_kw() < 12.0)
	var cp: Node = main.get_node("Equipment/SolarCoupler")
	cp.order_rearm(hash([11, "solar_coupler"]))
	var w: String = cp.wing
	var expect: float = 0.35 if cp.fault == "loose" else 0.55
	_check("coupler fault (%s, wing %s) cuts that wing to %.0f %%" % [cp.fault, w, expect * 100.0], absf(sa.wing_output(w) - sa.WING_KW * expect) < 0.01 and absf(sa.wing_output("R" if w == "L" else "L") - sa.WING_KW) < 0.01)
	sa.reserve = 0.8
	for i in 60:
		sa._process(1.0)
	var drained: float = 0.8 - sa.reserve
	_check("deficit drains the reserve GRADUALLY (%.1f %% per minute)" % (drained * 100.0), sa.margin() >= 0.0 or (drained > 0.0 and drained < 0.08))
	_check("no Bus A droop while the reserve is healthy", sa.bus_droop() == 0.0)
	var set0: Array = pw.setting.duplicate()
	pw.setting = [4, 4, 4]                      # a heavy load: a real deficit
	var v_hi: float = pw.bus_voltage()
	sa.reserve = 0.1
	var v_low: float = pw.bus_voltage()
	var st: Node = main.get_node("StationStatus")
	_check("low reserve + deficit: Bus A droops (%.1f -> %.1f V)" % [v_hi, v_low], sa.margin() < 0.0 and v_low < v_hi - 0.3)
	_check("...and StationStatus raises an Engineering WARNING", st.duties().any(func(d): return d["id"] == "COND-solar" and int(d["severity"]) == 2))
	pw.setting = set0
	cp.load_dict({})
	_check("repaired: full generation, surplus recharges", absf(sa.generation() - 12.0) < 0.01 and sa.margin() > 0.0)
	var r0: float = sa.reserve
	sa._process(10.0)
	_check("surplus charges the reserve", sa.reserve > r0)
	sa.reserve = 0.9
	pw._refresh()
	_check("power panel shows SOLAR / LOAD / RES (%s)" % pw._solar.text, pw._solar.text.begins_with("SOLAR") and pw._solar.text.find("RES") != -1)


func _schedule() -> void:
	_check("solar orders introduced gradually (day 10 / 11 / 13)", dp.ORDER_TYPES[&"solar_clean"]["intro_day"] == 10 and dp.ORDER_TYPES[&"solar_coupler"]["intro_day"] == 11 and dp.ORDER_TYPES[&"solar_hinge"]["intro_day"] == 13)
	var max_long := 0
	var seen := {}
	var first_two := []
	for run in 2:
		dp.orders = []
		var days: Array = []
		for d in range(9, 22):
			dp.day_number = d
			dp._schedule_orders()
			var open_long: int = dp.open_orders().filter(func(o): return StringName(o["type"]) in dp.LONG_EVA).size()
			max_long = maxi(max_long, open_long)
			for o in dp.open_orders():
				seen[String(o["type"])] = true
			days.append(dp.open_orders().map(func(o): return String(o["type"])))
			for o in dp.open_orders():
				o["status"] = "done"
		first_two.append(days)
	_check("never more than one long EVA job open (max %d)" % max_long, max_long <= 1)
	var det := true
	for n in ["SolarCoupler", "SolarHinge", "SolarClean"]:
		var t: Node = main.get_node("Equipment/" + n)
		t.order_rearm(4242)
		var a: Dictionary = t.state_dict()
		t.order_rearm(4242)
		det = det and a == t.state_dict()
		t.load_dict({})
	_check("same order seed -> same fault (never re-rolled)", det)
	_check("solar jobs do appear over days 10-21 %s" % str(seen.keys().filter(func(k): return k.begins_with("solar"))), seen.keys().filter(func(k): return k.begins_with("solar")).size() >= 2)
	dp.orders = []
	dp.day_number = 11
	for n in ["SolarCoupler", "SolarHinge", "SolarClean"]:
		main.get_node("Equipment/" + n).load_dict({})     # clear the sweep's faults


func _go_outside() -> void:
	var al: Node = main.get_node("AirlockChamber")
	fb.sync_to_eye_position(Vector3(-4.8, 1.6, -1.45))
	for i in 4: await physics_frame
	al.begin_cycle_out()
	await _until(func(): return al.sequence == "", 10.0)
	fb.sync_to_eye_position(Vector3(-4.8, 1.6, -3.3))
	for i in 6: await physics_frame
	_check("outside for the solar work", eva.outside)


## Test setup: put the technician beside a worksite with tether A secured
## on its ring (the hop-by-hop traversal itself is covered by
## test_r41_eva_dual_tether).
func _at(site: String, ring: String) -> void:
	var w: Dictionary = eva.worksites[site]
	fb.sync_to_eye_position((w["stance"] as Vector3) + Vector3(0.3, 0.2, 0.4))
	fb.velocity = Vector3.ZERO
	eva.leave_worksite()
	eva.tethers = [{"ring": Graph.index_of(ring), "state": "secured", "t": 1.0, "seq": 50, "target": -1}, eva._new_tether()]
	eva.anchor_index = Graph.index_of(ring)
	await create_timer(0.15).timeout


func _click(task: Node, id: StringName) -> void:
	task.on_part(id)


func _coupler() -> void:
	var cp: Node = main.get_node("Equipment/SolarCoupler")
	dp.day_number = 11
	cp.order_rearm(hash([11, "solar_coupler"]))
	var w: String = cp.wing
	var site: String = "coupler_" + w
	_check("coupler worksite registered with a handhold on the truss", eva.worksites.has(site))
	var before: float = sa.wing_output(w)
	# Not stabilised -> nothing happens.
	await _at(site, "T0")
	_check("worksite refuses without a tether on %s" % cp.RING[w], not eva.stabilize(site))
	await _at(site, cp.RING[w])
	cp.on_part(&"isolate")
	_check("hardware refuses until stabilised", not cp.isolated)
	_check("stabilise at the handhold (tether on %s)" % cp.RING[w], eva.stabilize(site))
	await create_timer(0.8).timeout
	_check("work position held: thrust locked, body pose WORK", eva.at_worksite(site) and fb.work_locked and eva.eva_pose == "work")
	_check("stance eased in from close by (no long teleport)", fb.current_eye_position().distance_to(eva.worksites[site]["stance"]) < 0.05)
	_click(cp, &"window")
	_check("inspect: fault identified", cp.inspected)
	_click(cp, &"latch")
	_check("SAFETY: latch refused while the coupler is LIVE", not cp.latch_open)
	_click(cp, &"plug")
	_check("SAFETY: plug refused while LIVE", not cp.plug_out)
	_click(cp, &"isolate")
	_check("isolated: wing output 0 (string safe)", cp.isolated and sa.wing_output(w) == 0.0)
	_click(cp, &"latch")
	_click(cp, &"plug")
	_check("latch open, plug out", cp.latch_open and cp.plug_out)
	_click(cp, &"isolate")
	_check("SAFETY: re-energising refused with the plug out", cp.isolated)
	if cp.fault == "degraded":
		_click(cp, &"plug")
		_check("degraded: new insert fitted", cp.insert_new)
	_click(cp, &"plug")
	_click(cp, &"latch")
	_click(cp, &"isolate")
	_click(cp, &"test")
	_check("seated, latched, re-energised, continuity OK", cp.fault == "ok" and cp.tested and not cp.isolated and not cp.latch_open)
	_check("wing %s output restored (%.1f -> %.1f kW)" % [w, before, sa.wing_output(w)], sa.wing_output(w) > before and absf(sa.wing_output(w) - sa.WING_KW) < 0.01)
	_check("order not done before the indoor VERIFY OUTPUT", not cp.order_done())
	eva.leave_worksite()
	cp.on_output_checked()
	_check("verify refused while still outside", not cp.order_done())


func _hinge() -> void:
	var hg: Node = main.get_node("Equipment/SolarHinge")
	dp.day_number = 13
	var variants := {}
	for sd in range(1, 40):
		hg.order_rearm(sd)
		variants[hg.variant] = true
	_check("hinge fault variants: latch / fastener / bracket %s" % str(variants.keys()), variants.size() == 3)
	hg.order_rearm(hash([13, "solar_hinge"]))
	var w: String = hg.wing
	var v: String = hg.variant
	await create_timer(2.0).timeout
	_check("restricted deployment: the section sits %.1f deg off-plane, wing at 78 %%" % hg.section_tilt(), hg.section_tilt() > 5.0 and absf(sa.wing_output(w) - sa.WING_KW * 0.78) < 0.01)
	await _at("hinge_" + w, hg.RING[w])
	_check("stabilise at the hinge worksite", eva.stabilize("hinge_" + w))
	await create_timer(0.8).timeout
	_click(hg, &"flag")
	_check("inspect the lock indicator (red)", hg.inspected and hg.variant == v)
	var part: StringName = {"latch": &"latch", "fastener": &"fastener", "bracket": &"bracket"}[v]
	var wrong: StringName = &"bracket" if v != "bracket" else &"latch"
	_click(hg, wrong)
	_check("working the wrong part changes nothing", hg.variant == v)
	for i in 3:
		if hg.variant != "ok":
			_click(hg, part)
	_check("%s fixed" % v, hg.variant == "ok" and not hg.order_done())
	_click(hg, &"flag")
	_check("final inspection verifies the mechanical state -> order done", hg.mech_verified and hg.order_done())
	await create_timer(2.5).timeout
	_check("section back in plane, full output", hg.section_tilt() < 0.5 and absf(sa.wing_output(w) - sa.WING_KW) < 0.01)
	eva.leave_worksite()


func _clean() -> void:
	var cl: Node = main.get_node("Equipment/SolarClean")
	dp.day_number = 10
	cl.order_rearm(hash([10, "solar_clean"]))
	var w: String = cl.wing
	var site: String = "outer_" + w
	_check("film on the outer panel: wing at %.0f %%, sensor reads %d %%" % [sa.wing_factor(w) * 100.0, cl.sensor_reading()], sa.wing_factor(w) < 0.8 and cl.sensor_reading() < 90)
	var patch: Node3D = cl._patch_nodes[w][0]
	_check("patches lie ON the outer cell surface near the tip", patch.visible and absf(patch.global_position.y - 1.125) < 0.01 and absf(patch.global_position.x - cl.TIP[w]) < 2.0)
	var l4: String = "L4" if w == "L" else "R4"
	await _at(site, l4)
	_check("outer worksite REFUSES a tether on %s (needs the outer ring)" % l4, not eva.stabilize(site))
	await _at(site, cl.RING[w])
	_check("outer worksite accepts a tether on %s" % cl.RING[w], eva.stabilize(site))
	await create_timer(0.8).timeout
	for i in 3:
		_click(cl, StringName("patch%d" % i))
	_check("three patches wiped -> panel clean, wing output restored", cl.soil() == 0.0 and absf(sa.wing_output(w) - sa.WING_KW) < 0.01)
	_click(cl, &"sensor")
	_check("sensor lens wiped", not cl.sensor_dirty and not cl.sensor_read)
	_click(cl, &"sensor")
	_check("sensor read: %d %% (verified)" % cl.sensor_reading(), cl.sensor_read and cl.sensor_reading() >= 95)
	_check("order waits for the technician to get back inside", not cl.order_done())
	eva.leave_worksite()


func _save_load() -> void:
	# Back inside: coupler VERIFY OUTPUT at the power panel; orders close.
	var al: Node = main.get_node("AirlockChamber")
	eva.tethers = [{"ring": 0, "state": "secured", "t": 1.0, "seq": 60, "target": -1}, eva._new_tether()]
	fb.sync_to_eye_position(Vector3(-4.8, 1.6, -1.6))
	for i in 6: await physics_frame
	al.begin_cycle_in()
	await _until(func(): return al.sequence == "", 10.0)
	fb.sync_to_eye_position(Vector3(-4.8, 1.6, 0.8))
	for i in 4: await physics_frame
	var cp: Node = main.get_node("Equipment/SolarCoupler")
	var cl: Node = main.get_node("Equipment/SolarClean")
	_check("clean order closes once back inside", cl.order_done())
	dp.day_number = 11                          # the coupler order's day
	pw.on_part(&"solar")
	_check("power panel SOLAR check verifies the coupler output -> done", cp.order_done())
	# Automatic completion through DayPlan, credited once.
	dp.orders = [{"id": "WO-T1", "type": "solar_coupler", "category": "D", "priority": 2, "day": dp.day_number, "seed": 1, "status": "open", "carried_from": -1}]
	var p0: int = dp.proficiency_level("eva")
	dp._poll_orders()
	dp._poll_orders()
	_check("order closed automatically, proficiency credited once (eva %d -> %d)" % [p0, dp.proficiency_level("eva")], dp.orders[0]["status"] == "done" and dp.proficiency_level("eva") == p0 + 1)
	# Mid-task save/load: no re-roll, state exact.
	var hg: Node = main.get_node("Equipment/SolarHinge")
	hg.order_rearm(12345)
	hg.stage = 1
	var snap: Dictionary = {"cp": cp.state_dict(), "hg": hg.state_dict(), "cl": cl.state_dict(), "res": sa.state_dict()}
	sa.reserve = 0.42
	var sg: Node = main.get_node("SaveGame")
	sg.save_path = "user://test_r41_solar.json"
	var r: Dictionary = sg.save_game()
	_check("save inside the station works (%s)" % r.get("message", ""), r.get("ok", false))
	hg.order_rearm(999)
	sa.reserve = 0.99
	sg.apply_state(sg.read_save()["data"])
	_check("load: hinge fault + stage exact (no re-roll)", hg.variant == snap["hg"]["variant"] and hg.stage == 1 and hg.wing == snap["hg"]["wing"])
	_check("load: reserve restored (%.2f)" % sa.reserve, absf(sa.reserve - 0.42) < 0.001)
	_check("load: derived output rebuilt from saved faults", absf(sa.wing_output(hg.wing) - sa.WING_KW * 0.78) < 0.01)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_r41_solar.json"))


func _until(cond: Callable, seconds: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		await physics_frame


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
