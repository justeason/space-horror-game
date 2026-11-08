extends SceneTree
## Round 33 Priority 6: the Control Room environment readout shows values
## DERIVED from real equipment state and follows every change.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame
	var r: Node = main.get_node("EnvironmentReadout")
	var dp: Node = main.get_node("DayPlan")
	var f: Node = main.get_node("Interactables/FilterHousingStation")
	var panel: Node = main.get_node("Geometry/EngineeringCabinet1")
	var valve: Node = main.get_node("Interactables/ValveRoutingStation")
	var t: String = r.text()
	_check("day 1 nominal readings ('%s')" % t.replace("\n", " | "), t.find("CABIN AIRFLOW   100 %") != -1 and t.find("FILTER dP       0.7 kPa") != -1 and t.find("MAIN BUS T-2    24.1 V") != -1 and t.find("CARGO PORT      SECURED") != -1)
	dp.trigger_fault()
	_check("open Engineering power fault -> bus reads LOW", r.text().find("11.4 V  LOW") != -1)
	panel._repair_stage = panel.RepairStage.REPAIRED
	_check("repaired panel -> bus back to 24.1 V", r.text().find("MAIN BUS T-2    24.1 V") != -1)
	dp.reset_for_new_day()   # day 2: filter due
	var brk: Node = main.get_node("Equipment/BreakerPanel")
	for i in 4:   # Round 35: the day's breaker order -- reset it at the panel
		if not brk.on[i]:
			brk.on_part(StringName("b%d" % i))
	_check("filter service due -> airflow 86 %, dP HIGH", r.text().find("CABIN AIRFLOW    86 %") != -1 and r.text().find("1.9 kPa  HIGH") != -1)
	f.toggle_isolate()
	_check("isolated housing -> airflow 0 %, dP --", r.text().find("CABIN AIRFLOW     0 %") != -1 and r.text().find("FILTER dP       --") != -1)
	f.toggle_isolate()
	var before: String = r.text().get_slice("COOLANT LOOP", 1).get_slice("\n", 0)
	valve.toggle_valve(1)
	var after: String = r.text().get_slice("COOLANT LOOP", 1).get_slice("\n", 0)
	_check("coolant loop line follows the real valves ('%s' -> '%s')" % [before.strip_edges(), after.strip_edges()], before != after)
	main.get_node("Interactables/SensorCalibrationStation")._rearm_for_service(7)
	_check("recorded sensor drift is shown", r.text().find("SENSOR ARRAY    DRIFT") != -1)
	dp.reset_for_new_day()   # day 3 cargo
	_check("cargo port status is live", r.text().find("CARGO PORT      SHIPMENT ARRIVED") != -1)
	for i in 3: await process_frame
	await create_timer(0.6).timeout
	_check("the wall label itself refreshes (twice a second)", r._label.text == r.text())
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
