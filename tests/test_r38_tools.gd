extends SceneTree
## Round 38 Priority 11: AFM-2 airflow meter and LD-5 leak detector --
## pickup, real state-dependent readings, fault detection, return unused,
## persistent ownership, no duplication.
var _ok := true
var main: Node
var rack: Node
var carry: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	rack = main.get_node("Equipment/ToolRack")
	carry = main.get_node("Player/CarrySystem")
	var afm: Node3D = rack.docked(&"airflow_meter")
	var ld: Node3D = rack.docked(&"leak_detector")
	_check("both instruments docked on the rack in Storage", afm != null and ld != null)
	_check("one of each exists", _count(&"airflow_meter") == 1 and _count(&"leak_detector") == 1)
	# Airflow: without the meter -> refused.
	rack.on_part(&"air_vent")
	_check("no meter in hand: no reading", rack.last_reading.is_empty())
	_take(afm)
	_check("airflow meter carried", carry.is_holding(afm))
	var vent: Node = main.get_node("Equipment/VentGrille")
	vent.dirt = [0.0, 0.0, 0.0, 0.0]
	rack.on_part(&"air_vent")
	var clean: float = rack.last_reading[&"air_vent"]
	vent.order_rearm(5)
	vent.airflow_checked = false
	rack.on_part(&"air_vent")
	var dirty: float = rack.last_reading[&"air_vent"]
	_check("vent outlet airflow follows the REAL dirt: clean %.2f > dirty %.2f m/s" % [clean, dirty], clean > dirty + 0.3)
	_check("measuring the vent outlet satisfies the vent order's flow check", vent.airflow_checked)
	var pw: Node = main.get_node("Equipment/PowerDistribution")
	pw.setting = [1, 2, 2]
	pw.demand = [2, 2, 2]
	rack.on_part(&"air_filter")
	var underpowered: float = rack.last_reading[&"air_filter"]
	pw.setting = [2, 2, 2]
	rack.on_part(&"air_filter")
	_check("filter outlet airflow follows LS fan power (%.2f < %.2f)" % [underpowered, rack.last_reading[&"air_filter"]], underpowered < rack.last_reading[&"air_filter"])
	_check("the meter keeps its readings", afm.payload.get("readings", {}).has("air_vent"))
	# Return via the dock (receptacle).
	_stow(afm)
	_check("airflow meter returned to its slot", rack.docked(&"airflow_meter") == afm and not carry.is_carrying())
	# Leak detector: signal from the real seal fault + proximity.
	var hs: Node3D = main.get_node("Equipment/HatchSeal")
	_take(ld)
	_check("leak detector carried", carry.is_holding(ld))
	await process_frame
	_check("no fault anywhere: zero signal (%.2f)" % rack.leak_signal, rack.leak_signal_at(hs.global_position)["signal"] == 0.0)
	hs.faults = ["", "debris", "", ""]
	hs.inspected = [false, false, false, false]
	var right_sec: Vector3 = hs.global_transform * hs.POS[1]
	var near: float = rack.leak_signal_at(right_sec + Vector3(0, 0, 0.15))["signal"]
	var far: float = rack.leak_signal_at(right_sec + Vector3(0, 0, 1.6))["signal"]
	_check("signal strength falls with distance from the faulty section (%.2f near, %.2f far)" % [near, far], near > 0.6 and far < near * 0.3)
	_check("the strongest section is the real fault (RIGHT)", rack.leak_signal_at(right_sec + Vector3(0, 0, 0.15))["section"] == 1)
	# Hold it at the fault: the section is located.
	ld.reparent(main, true)
	ld.global_position = right_sec + Vector3(0, 0, 0.12)
	carry._carried_item = ld   # still "held" (the hand), positioned at the seal
	for i in 4: await process_frame
	_check("holding it at the fault locates the section", hs.inspected[1])
	carry._carried_item = null
	carry._carried_item_id = &""
	ld.reparent(rack.slots[&"leak_detector"], true)
	rack.seat(ld)
	_check("leak detector back in its slot", rack.docked(&"leak_detector") == ld)
	# Return UNUSED, and save/load ownership.
	_take(afm)
	var sg: Node = main.get_node("SaveGame")
	sg.save_path = "user://test_r38_tools.json"
	var r: Dictionary = sg.save_game()
	_check("save with the meter in hand: %s" % r["message"], r["ok"])
	sg.apply_state(sg.read_save()["data"])
	await process_frame
	var afm2: Node3D = rack.tool_anywhere(&"airflow_meter")
	_check("load: meter still in hand, readings kept, no duplicates", carry.is_holding(afm2) and afm2.payload.get("readings", {}).has("air_vent") and _count(&"airflow_meter") == 1)
	_stow(afm2)
	_check("returned after load (unused return path)", rack.docked(&"airflow_meter") != null and not carry.is_carrying())
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_r38_tools.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_r38_tools.json.bak"))
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _count(id: StringName) -> int:
	var n := 0
	for it in main.find_children("*", "", true, false):
		if "item_id" in it and it.item_id == id and not it.is_queued_for_deletion():
			n += 1
	return n


func _take(it: Node3D) -> void:
	carry.pick_up(it)
	if carry.is_reaching():
		carry.complete_grasp()


func _stow(it: Node3D) -> void:
	var i: int = 0 if it.item_id == &"airflow_meter" else 1
	rack.on_part(StringName("dock_%d" % i))


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
