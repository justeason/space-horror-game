extends SceneTree
## Round 35: the five new physical maintenance tasks -- each through its
## real equipment, its real consequences, and automatic order closure.
##   BREAKER  trip -> zone light out + emergency light; wrong breaker;
##            reset refused while the wiring fault is unrepaired.
##   VENT     dirt -> airflow/O2 drop; clips/cover/clean visuals; recovery;
##            reduce-effects accessibility.
##   POWER    imbalance -> bus voltage; overload -> trips B-03 after the
##            delay; balancing + stability verification.
##   SEAL     faults -> cabin pressure leak; inspection; hold test; cargo
##            interlock.
##   DATA     capture real readings -> carry -> upload; stale data rejected.
var _ok := true
var main: Node
var dp: Node
var carry: Node

func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 6: await process_frame
	dp = main.get_node("DayPlan")
	carry = main.get_node("Player/CarrySystem")
	await _breaker()
	await _vent()
	await _power()
	await _seal()
	await _data()
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _open_order(t: StringName) -> Dictionary:
	dp._order_seq += 1
	var o := {"id": "WO-T%d" % dp._order_seq, "type": String(t), "category": dp.ORDER_TYPES[t]["category"], "priority": dp.ORDER_TYPES[t]["priority"], "day": dp.day_number, "seed": 12345, "status": "open", "carried_from": -1}
	dp.orders.append(o)
	dp.order_equipment(t).order_rearm(int(o["seed"]))
	return o


func _breaker() -> void:
	var br: Node = main.get_node("Equipment/BreakerPanel")
	var eng_light: Light3D = main.get_node("Lights/Light_Engineering")
	var e0: float = eng_light.light_energy
	_check("breaker panel: 4 breakers, all on at start", br.on.all(func(v): return v))
	# Real ray: the lever is targetable by the interaction controller.
	var fb: Node = main.get_node("FreeMoveBody")
	var player: Node3D = main.get_node("Player")
	var lp: Node3D = player.get_node("LookPivot")
	var lever: Node3D = br.get_node("Click_b2")
	var eye: Vector3 = lever.global_position + Vector3(0.9, 0.15, 0.0)
	fb.sync_to_eye_position(eye)
	player.global_position = eye
	var d: Vector3 = lever.global_position - eye
	lp.rotation.y = atan2(-d.x, -d.z) - player.rotation.y
	lp._target_yaw = lp.rotation.y
	var pitch: float = atan2(d.y, Vector2(d.x, d.z).length())
	lp.get_node("PitchPivot").rotation.x = pitch
	lp._target_pitch = pitch
	for i in 6: await physics_frame
	var hov: Object = main.get_node("Player/LookPivot/PitchPivot/Camera3D").get_hovered()
	_check("looking at breaker B-03 targets its lever (%s)" % str(hov), hov == lever)
	_check("...with a contextual prompt ('%s')" % hov.get_interact_prompt() if hov != null else "", hov != null and hov.get_interact_prompt().find("B-03") != -1)
	var o := _open_order(&"breaker")
	var i: int = [0, 1, 3, 2][12345 % 4]
	_check("order rearm trips a breaker (%s)" % br.BREAKERS[i]["id"], not br.on[i])
	br.trip(2, "surge")
	_check("B-03 trip: Engineering light OUT, emergency light ON", eng_light.light_energy == 0.0 and br._emergency[2].light_energy > 0.0)
	_check("workstation/readout reflect the outage", main.get_node("EnvironmentReadout").text().find("TRIPPED") != -1)
	# Underlying fault: reset refused while the wiring fault is unrepaired.
	dp.fault_target = &"engineering_power"
	br.on_part(&"b2")
	_check("reset refused (re-trips) while the wiring fault is unrepaired", not br.on[2] and br.cause_active(2))
	main.get_node("Geometry/EngineeringCabinet1")._repair_stage = main.get_node("Geometry/EngineeringCabinet1").RepairStage.REPAIRED
	br.on_part(&"b2")
	_check("after the repair the reset holds: light restored", br.on[2] and absf(eng_light.light_energy - e0) < 0.001 and br._emergency[2].light_energy == 0.0)
	# Wrong breaker: switching an ON breaker off is a real, recoverable act.
	br.on_part(&"b3")
	_check("switching a healthy breaker off cuts its zone (recoverable)", not br.on[3])
	br.on_part(&"b3")
	br.on_part(StringName("b%d" % i))
	await process_frame
	await process_frame
	_check("all on -> breaker order CLOSED automatically", o["status"] == "done")


func _vent() -> void:
	var v: Node = main.get_node("Equipment/VentGrille")
	var env: Node = main.get_node("EnvironmentModel")
	var o := _open_order(&"vent")
	_check("vent order: dirty sections reduce efficiency (%.2f)" % v.efficiency(), v.efficiency() < 0.95 and not v.is_clean())
	_check("environment airflow follows the vent (%.2f)" % env.airflow(), env.airflow() < 0.95)
	var o2_target: float = env.o2_target()
	_check("O2 target drops with airflow (%.2f < 21.2)" % o2_target, o2_target < 21.2)
	env.o2_kpa = 18.5
	env.step(0.0)
	_check("significant degradation is detected (severity %d)" % env.severity, env.severity == 2)
	await process_frame
	var cam: Camera3D = main.get_node("Player/LookPivot/PitchPivot/Camera3D")
	_check("restrained effect: slight view drift only (%.4f)" % absf(cam.h_offset), absf(cam.h_offset) <= 0.0061 and main.get_node("Player/HUD/EnvVignette").visible)
	preload("res://scripts/station/game_settings.gd")._values["reduce_effects"] = true
	await process_frame
	_check("Reduce visual effects: no drift, no vignette (warnings stay)", cam.h_offset == 0.0 and not main.get_node("Player/HUD/EnvVignette").visible)
	preload("res://scripts/station/game_settings.gd")._values["reduce_effects"] = false
	v.on_part(&"cover")
	_check("cover will not open with the clips secured", not v.cover_open)
	v.on_part(&"gauge")
	v.on_part(&"c0"); v.on_part(&"c1"); v.on_part(&"cover")
	_check("clips released -> grille opens", v.cover_open)
	var dirty: int = -1
	for i in 4:
		if v.dirt[i] >= 0.05:
			dirty = i
	var a0: float = (v._dirt_mats[dirty] as StandardMaterial3D).albedo_color.a
	v.on_part(StringName("s%d" % dirty))
	_check("scrubbing visibly cleans the section (alpha %.2f -> %.2f)" % [a0, (v._dirt_mats[dirty] as StandardMaterial3D).albedo_color.a], (v._dirt_mats[dirty] as StandardMaterial3D).albedo_color.a < a0)
	for k in 12:
		for i in 4:
			v.on_part(StringName("s%d" % i))
	_check("all sections clean", v.is_clean())
	_check("not done while the grille is open", not v.order_done())
	v.on_part(&"cover"); v.on_part(&"c0"); v.on_part(&"c1")
	await process_frame
	await process_frame
	_check("closed + clips secured -> vent order CLOSED automatically", o["status"] == "done" and v.efficiency() == 1.0)
	for k in 200:
		env.step(5.0)
	_check("environment recovers (O2 %.2f kPa, severity %d)" % [env.o2_kpa, env.severity], env.o2_kpa > 21.0 and env.severity == 0)


func _power() -> void:
	var p: Node = main.get_node("Equipment/PowerDistribution")
	var br: Node = main.get_node("Equipment/BreakerPanel")
	var o := _open_order(&"power")
	_check("imbalance lowers the bus voltage (%.1f V < 28)" % p.bus_voltage(), not p.balanced() and p.bus_voltage() < 28.0)
	# Force an overload, then show it trips B-03 only after the delay.
	p.setting = [int(p.demand[0]) + 2 if int(p.demand[0]) <= 2 else 4, p.demand[1], p.demand[2]]
	if not p.is_overloaded():
		p.setting = [4, 4, p.demand[2]]
	p._overload_s = 0.0
	_check("overload is reported", p.is_overloaded() and p.bus_voltage() < 27.0)
	_check("no trip before the delay", br.on[2])
	p._overload_s = p.OVERLOAD_TRIP_S + 0.1
	await process_frame
	await process_frame
	_check("sustained overload trips B-03 (Engineering lights out)", not br.on[2])
	br.on_part(&"b2")
	_check("B-03 reset refused while still overloaded", not br.on[2])
	# Balance with the physical controls (always solvable).
	for i in 3:
		for k in 6:
			if int(p.setting[i]) > int(p.demand[i]):
				p.on_part(StringName("dn%d" % i))
			elif int(p.setting[i]) < int(p.demand[i]):
				p.on_part(StringName("up%d" % i))
	_check("balanced via the ▲/▼ controls: bus 28.0 V", p.balanced() and absf(p.bus_voltage() - 28.0) < 0.01)
	_check("not done until stable for the verification time", not p.order_done())
	await create_timer(p.VERIFY_S + 0.5).timeout
	br.on_part(&"b2")
	await process_frame
	await process_frame
	_check("stable -> power order CLOSED; B-03 resets now", o["status"] == "done" and br.on[2])
	_check("LS-FANS under-power reduces the fan factor", (func():
		var keep = p.setting[0]
		p.setting[0] = maxi(int(p.demand[0]) - 1, 0)
		var f: float = p.fan_factor()
		p.setting[0] = keep
		return f < 1.0 or int(p.demand[0]) == 0).call())


func _seal() -> void:
	var s: Node = main.get_node("Equipment/HatchSeal")
	var env: Node = main.get_node("EnvironmentModel")
	var o := _open_order(&"seal")
	_check("seal faults leak (%.1f kPa) and lower the pressure target" % s.leak_kpa(), s.leak_kpa() > 0.0 and env.pressure_target() < 101.3)
	s.on_part(&"s0")
	_check("sections cannot be worked before INSPECT mode", not s.inspected[0])
	# Cargo interlock.
	var port: Node = main.get_node("Interactables/CargoPort")
	port.state = port.PortState.ARRIVED
	s.on_part(&"mode")
	_check("inspection refused during a cargo transfer", not s.inspection_mode)
	port.state = port.PortState.SECURED
	s.on_part(&"mode")
	_check("inspection mode engaged", s.inspection_mode)
	port.state = port.PortState.ARRIVED
	port.interact()
	_check("cargo port refuses to operate while the hatch is in inspection mode", port.state == port.PortState.ARRIVED)
	port.state = port.PortState.SECURED
	s.on_part(&"test")
	_check("pressure test refused while unsecured", s.test_state != "running")
	for i in 4:
		s.on_part(StringName("s%d" % i))
	_check("all four sections inspected", s.inspected.all(func(v): return v))
	for i in 4:
		if s.faults[i] != "":
			s.on_part(StringName("s%d" % i))
	_check("faults corrected -> no leak", s.leak_kpa() == 0.0)
	s.on_part(&"mode")
	s.on_part(&"test")
	await create_timer(s.TEST_S + 0.4).timeout
	await process_frame
	_check("pressure-hold test PASS -> seal order CLOSED", s.test_state == "pass" and o["status"] == "done")


func _data() -> void:
	var up: Node = main.get_node("Equipment/UploadPort")
	var cap: Node = main.get_node("Equipment/CapturePort")
	var o := _open_order(&"data")
	var m: Node3D = up.module()
	_check("module DM-7 starts seated (empty) in the Control Room port", m != null and m.payload.is_empty())
	_check("guidance: take the module to Engineering", up.order_next()["action"] == "Take module to Engineering")
	m.interact()
	if carry.is_reaching(): carry.complete_grasp()
	_check("the module is carried (one item)", carry.is_holding(m))
	carry._carried_item = null; carry._carried_item_id = &""; carry._release_physics(m)
	cap.stow(m)
	_check("seated in the Engineering capture port", cap.module() == m)
	cap.on_part(&"capture")
	await create_timer(cap.CAPTURE_S + 0.3).timeout
	_check("captured REAL readings (bus %.1f V, %d breakers tripped)" % [float(m.payload["values"].get("bus_v", 0)), m.payload["values"].get("breakers_tripped", []).size()], not m.payload.is_empty() and absf(float(m.payload["values"]["bus_v"]) - main.get_node("Equipment/PowerDistribution").bus_voltage()) < 0.05)
	# Station changes after capture -> stale.
	var p: Node = main.get_node("Equipment/PowerDistribution")
	p.on_part(&"up1")
	m.interact()
	if carry.is_reaching(): carry.complete_grasp()
	carry._carried_item = null; carry._carried_item_id = &""; carry._release_physics(m)
	up.stow(m)
	_check("data captured before a station change is rejected as STALE", up.last_result == "STALE" and o["status"] == "open")
	p.on_part(&"dn1")
	m.interact()
	if carry.is_reaching(): carry.complete_grasp()
	carry._carried_item = null; carry._carried_item_id = &""; carry._release_physics(m)
	cap.stow(m)
	cap.on_part(&"capture")
	await create_timer(cap.CAPTURE_S + 0.3).timeout
	m.interact()
	if carry.is_reaching(): carry.complete_grasp()
	carry._carried_item = null; carry._carried_item_id = &""; carry._release_physics(m)
	up.stow(m)
	await create_timer(up.UPLOAD_S + 0.4).timeout
	await process_frame
	_check("fresh capture uploads and the data order CLOSES", up.last_result == "UPLOADED" and o["status"] == "done" and up.history.size() == 1)
	var count := 0
	for n in main.find_children("*", "", true, false):
		if "item_id" in n and n.item_id == &"data_module":
			count += 1
	_check("exactly one data module exists", count == 1)


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
