extends SceneTree
## Round 42 Priorities 19-20, 28-30: maintenance.
##  - four new PHYSICAL tasks (Junction emergency lighting test, Junction
##    distribution panel, Comms patch bay, Comms backup receiver test):
##    seeded faults (no re-roll), partial progress survives save/load, each
##    work order closes itself only when the real requirements are met;
##  - Communications ONE authoritative state: the physical console twin and
##    the focused view show the same frequency / gain / link; opening and
##    closing never resets; B-04 off = receiver dark (dials refuse); antenna
##    and patch-bay faults lower the real link; the day's profile is
##    deterministic and saved;
##  - the hi-DPI driver is attached to every focused 3D view and is inert at
##    scale 1 (headless) -- input and layout unchanged.
var _ok := true
var main: Node
var dp: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	dp = main.get_node("DayPlan")
	_registry()
	await _emergency_lights()
	await _distribution()
	await _patch_bay()
	await _backup_rx()
	await _comms_sync()
	_hidpi()
	await _orbit()
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _open(t: StringName, seed: int) -> void:
	dp._order_seq += 1
	dp.orders.append({"id": "WO-T%d" % dp._order_seq, "type": String(t), "category": "B", "priority": int(dp.ORDER_TYPES[t]["priority"]), "day": dp.day_number, "seed": seed, "status": "open", "carried_from": -1})
	dp.order_equipment(t).order_rearm(seed)


func _closed(t: StringName) -> bool:
	return dp.orders.any(func(o): return String(o["type"]) == String(t) and o["status"] == "done")


func _registry() -> void:
	for t in [&"emerg_lights", &"junction_panel", &"patch_bay", &"backup_rx"]:
		_check("%s registered as a work order with real equipment" % t, dp.ORDER_TYPES.has(t) and dp.order_equipment(t) != null)
	var rooms: Array = [&"emerg_lights", &"junction_panel"].map(func(t): return dp.order_equipment(t).order_next()["room"]) + [&"patch_bay", &"backup_rx"].map(func(t): return dp.order_equipment(t).order_next()["room"])
	_check("two in the Junction, two in Communications (%s)" % str(rooms), rooms.count(&"main_junction") == 2 and rooms.count(&"communications") == 2)


func _emergency_lights() -> void:
	var eq: Node = main.get_node("Equipment/JunctionEmergencyLights")
	_open(&"emerg_lights", 4242)
	var bad: int = eq.failed
	eq.order_rearm(4242)
	_check("seeded fault, never re-rolled (EL-J%d)" % (bad + 1), eq.failed == bad)
	eq.on_part(&"fx0")
	_check("fixtures refuse checks until the TEST switch is on", not eq.checked[0])
	eq.on_part(&"test")
	_check("TEST on: all but the failed fixture glow", eq.fixture_lit((bad + 1) % 4) and not eq.fixture_lit(bad) and eq._glow[bad].light_energy == 0.0)
	for i in 4:
		eq.on_part(StringName("fx%d" % i))
	_check("every fixture checked; the dead one identified, not yet fixed", eq.checked.all(func(c): return c) and not eq.replaced)
	var sd: Dictionary = eq.state_dict()
	eq.load_dict({"test_on": false, "checked": [false, false, false, false], "failed": -1, "replaced": true})
	eq.load_dict(sd)
	_check("partial progress survives save/load", eq.checked.all(func(c): return c) and eq.failed == bad and eq.test_on)
	eq.on_part(StringName("fx%d" % bad))
	_check("module swapped: it lights", eq.fixture_lit(bad))
	await process_frame
	_check("not closed while still in TEST mode", not _closed(&"emerg_lights"))
	eq.on_part(&"test")
	await create_timer(0.2).timeout
	_check("back to NORMAL: the order closes itself", _closed(&"emerg_lights"))


func _distribution() -> void:
	var eq: Node = main.get_node("Equipment/JunctionDistribution")
	_open(&"junction_panel", 77)
	var l: int = eq.loose
	eq.on_part(StringName("c%d" % l))
	_check("connectors need the cover open", not eq.reseated)
	eq.on_part(&"cover")
	_check("cover open: the meter reads the selected circuit", eq.measured[eq.sel])
	while eq.sel != l:
		eq.on_part(&"knob")
	_check("the loose circuit reads LOW (%.1f V)" % eq.voltage(l), eq.voltage(l) < 20.0)
	for i in 3:
		if not eq.measured[i]:
			eq.on_part(&"knob")
	eq.on_part(StringName("c%d" % l))
	_check("reseated: %.1f V on that circuit" % eq.voltage(l), eq.reseated and eq.voltage(l) > 24.0)
	await process_frame
	_check("not closed before re-measuring + closing the cover", not _closed(&"junction_panel"))
	for i in 3:
		eq.on_part(&"knob")
	eq.on_part(&"cover")
	await create_timer(0.2).timeout
	_check("re-measured, cover closed: order closes", eq.remeasured and not eq.cover_open and _closed(&"junction_panel"))


func _patch_bay() -> void:
	var eq: Node = main.get_node("Equipment/CommsPatchBay")
	var ss: Node = main.get_node("Interactables/SignalCalibrationStation")
	ss._ensure_profile()
	ss._frequency = ss._target_freq          # a well-tuned receiver first
	ss._gain = ss._target_gain
	var link0: float = ss.link_quality()
	_open(&"patch_bay", 31)
	var l: int = eq.loose
	_check("loose plug lowers the station's REAL comms link (%.2f -> %.2f)" % [link0, ss.link_quality()], link0 > 0.9 and ss.link_quality() < link0 - 0.2)
	eq.on_part(StringName("p%d" % ((l + 1) % 6)))
	_check("a good port stays good", eq.stage == 0)
	for i in 3:
		eq.on_part(StringName("p%d" % l))
	_check("identify -> pull -> reseat", eq.stage == 2 and eq.found)
	await process_frame
	_check("not closed before the LINK TEST", not _closed(&"patch_bay"))
	eq.on_part(&"test")
	await create_timer(0.2).timeout
	_check("LINK TEST pass closes the order; link factor restored", _closed(&"patch_bay") and eq.link_factor() == 1.0)


func _backup_rx() -> void:
	var eq: Node = main.get_node("Equipment/CommsBackupReceiver")
	_open(&"backup_rx", 5)
	eq.on_part(&"log")
	_check("LOG refused on the MAIN path", not eq.logged.any(func(v): return v))
	eq.on_part(&"mode")
	eq.on_part(&"log")
	_check("backup not yet locked: LOG refused", not eq.logged.any(func(v): return v))
	await create_timer(eq.LOCK_S + 0.3).timeout
	for i in 3:
		eq.on_part(&"log")
		_check("CH %s logged (noise %.1f dB%s)" % [eq.CHANNELS[eq.chan], eq.reading()[1], ", the degraded one" if eq.chan == eq.degraded else ""], eq.logged[eq.chan] and (eq.reading()[1] > 10.0) == (eq.chan == eq.degraded))
		eq.on_part(&"chan")
	await process_frame
	_check("not closed while still on BACKUP", not _closed(&"backup_rx"))
	eq.on_part(&"mode")
	await create_timer(0.2).timeout
	_check("MAIN restored: order closes", _closed(&"backup_rx"))


func _comms_sync() -> void:
	var ss: Node = main.get_node("Interactables/SignalCalibrationStation")
	var world: Node = ss.get_node("WorldDiorama")
	await create_timer(0.4).timeout
	_check("day profile chosen deterministically (%s)" % ss.active_profile_label(), ss._profile_index == absi(hash([dp.day_number, "m02"])) % 3)
	var f0: float = ss.frequency()
	ss.nudge_frequency(1)
	ss.nudge_gain(-1)
	await create_timer(0.4).timeout
	var txt: String = world._readout.text
	_check("the PHYSICAL console shows the same values ('%s')" % txt.replace("\n", " / "), txt.find("F %.0f" % ss.frequency()) != -1 and txt.find("G %.2f" % ss.gain()) != -1 and txt.find("LINK") != -1)
	var view: Node = main.get_node("Player/HUD/SignalCalibrationView")
	view.open_station(ss)
	await process_frame
	_check("opening the focused view does not reset the tuning", is_equal_approx(ss.frequency(), f0 + 2.0))
	view.cancel_requested()
	await process_frame
	_check("closing keeps it", is_equal_approx(ss.frequency(), f0 + 2.0))
	var sd: Dictionary = ss.state_dict()
	ss.load_dict({"profile": (ss._profile_index + 1) % 3, "freq": 50.0, "gain": 0.5})
	ss.load_dict(sd)
	_check("save/load restores frequency / gain / profile", is_equal_approx(ss.frequency(), f0 + 2.0) and ss._profile_index == int(sd["profile"]))
	var ant: Node = main.get_node("Equipment/AntennaMast")
	var keep: Dictionary = ss.state_dict()
	ss._frequency = ss._target_freq
	ss._gain = ss._target_gain
	var q0: float = ss.link_quality()
	ant.feed = "loose"
	_check("antenna feed fault lowers the link (%.2f -> %.2f)" % [q0, ss.link_quality()], q0 > 0.9 and ss.link_quality() < q0 - 0.3)
	ant.feed = "ok"
	ss.load_dict(keep)
	var br: Node = main.get_node("Equipment/BreakerPanel")
	br.trip(3, "test")
	var r: Dictionary = ss.nudge_frequency(1)
	await create_timer(0.4).timeout
	_check("B-04 off: receiver dark, dials refuse, console says RX OFF", not r.get("ok", true) and ss.link_quality() == 0.0 and world._readout.text.find("RX OFF") != -1)
	br.load_dict({"on": [true, true, true, true], "cause": ["", "", "", ""]})


func _hidpi() -> void:
	var n := 0
	for v in ["ElectricalRepairView", "ValveRoutingView", "FilterHousingView", "CircuitTracerView", "SignalCalibrationView"]:
		var d: Node = main.get_node("Player/HUD/%s" % v).get_node_or_null("HiDpiDriver")
		if d != null and d.container != null:
			n += 1
	_check("hi-DPI render driver attached to all five focused 3D views (%d)" % n, n == 5)
	var drv: Node = main.get_node("Player/HUD/ElectricalRepairView/HiDpiDriver")
	_check("scale 1 (headless): inert -- the original container/viewport path is untouched", drv.scale_k <= 1.01 and not drv.active and main.get_node("Player/HUD/ElectricalRepairView/Panel/VBox/DioramaContainer").stretch)


## Round 42 Priority 34: orbital day / night drives the sun and solar power.
func _orbit() -> void:
	var oc: Node = main.get_node("Equipment/OrbitalCycle")
	var sa: Node = main.get_node("Equipment/SolarArrays")
	var sun: DirectionalLight3D = main.get_tree().get_first_node_in_group(&"exterior").get("sun")
	oc.load_dict({"phase_s": 60.0})
	_check("sunlit pass: full sun, both wings generating (%.1f kW)" % sa.generation(), oc.sun_factor() == 1.0 and sun.light_energy > 1.0 and absf(sa.generation() - 2.0 * sa.WING_KW) < 0.01)
	var dir0: Vector3 = sun.global_basis.z
	oc.load_dict({"phase_s": 200.0})
	_check("the sun moves gradually across the pass", sun.global_basis.z.angle_to(dir0) > 0.1)
	oc.load_dict({"phase_s": oc.ORBIT_S - oc.ECLIPSE_S - oc.PENUMBRA_S * 0.5})
	_check("penumbra: partial light (%.2f)" % oc.sun_factor(), oc.sun_factor() > 0.2 and oc.sun_factor() < 0.8)
	oc.load_dict({"phase_s": oc.ORBIT_S - oc.ECLIPSE_S * 0.5})
	_check("ECLIPSE: no sunlight, no generation, readout says ECLIPSE", oc.in_eclipse() and sun.light_energy < 0.01 and sa.generation() < 0.01 and sa.readout().find("ECLIPSE") != -1)
	sa.reserve = 1.0
	await create_timer(1.0).timeout
	_check("eclipse: the battery reserve carries the load (%.3f), no droop" % sa.reserve, sa.reserve < 1.0 and sa.reserve > 0.95 and sa.bus_droop() == 0.0)
	var lights: Node = main.get_node("Lights")
	_check("interior lights stay on their normal circuits", (lights.get_node("Light_ControlRoom") as OmniLight3D).light_energy > 0.5)
	var drain_full_eclipse: float = sa.load_kw() * sa.DRAIN_PER_KW_S * oc.ECLIPSE_S
	_check("a whole eclipse costs %.0f %% of the reserve (never a blackout)" % (drain_full_eclipse * 100.0), drain_full_eclipse < 0.5)
	var sd: Dictionary = oc.state_dict()
	oc.load_dict({"phase_s": 10.0})
	oc.load_dict(sd)
	_check("orbit saved / restored (derived from the saved clock: same sunlight on load)", absf(oc.offset_s - float(sd["offset_s"])) < 0.01 and oc.in_eclipse())
	oc.load_dict({"phase_s": 0.0})
	sa.reserve = 1.0


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
