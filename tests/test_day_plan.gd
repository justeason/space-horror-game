extends SceneTree
var _ok := true
func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame
	var dp := main.get_node("DayPlan")

	_check("c01 starts pending", not dp.is_task_done(&"c01"))
	dp.mark_done(&"c01")
	_check("c01 marked done", dp.is_task_done(&"c01"))
	dp.assign_daily_task()
	_check("assignment pinned to e06", dp.assignment_task_id == &"e06")
	dp.assign_daily_task()
	_check("assign is idempotent", dp.assignment_task_id == &"e06")

	dp.mark_done(&"e06")
	_check("e06 done, c01 unaffected by unrelated field", dp.is_task_done(&"e06") and dp.is_task_done(&"c01"))

	dp.trigger_fault()
	_check("fault pinned", dp.fault_target == &"engineering_power")
	dp.set_required_component(&"wire_control_16ga")
	_check("required component set", dp.required_component_id == &"wire_control_16ga")
	_check("hint visible by default (no difficulty system yet)", dp.show_component_hint())

	dp.reset_for_new_day()
	_check("reset clears c01", not dp.is_task_done(&"c01"))
	_check("reset clears assignment", dp.assignment_task_id == &"")
	_check("reset clears e06", not dp.is_task_done(&"e06"))
	_check("reset clears fault", dp.fault_target == &"")
	_check("reset clears required component", dp.required_component_id == &"")

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()

func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
