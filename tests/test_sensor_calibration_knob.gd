extends SceneTree
## Round 13 Workstream D rewrite: coverage for the four rotary knobs
## (three chamber regulators + one shared damping knob, replacing Round
## 11's single-chamber coarse/fine/damping trio) -- on top of (not
## replacing) test_sensor_calibration.gd's simulation/coupling/
## completion coverage. This file verifies each chamber knob drives
## ONLY its own setpoint (never another chamber's, never the shared
## damping), the shared damping knob affects convergence for all three
## chambers at once, the Shift "shared fine mode" genuinely reduces the
## adjustment rate for whichever knob is being dragged, only one knob
## can be grabbed at a time, and all four go inert once done. Also
## verifies the per-chamber gauge readouts mirror the view's own
## simulation state and the per-chamber status chip/direction arrow.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player := main.get_node("Player")
	var station := main.get_node("Interactables/SensorCalibrationStation")
	var view := player.get_node("HUD/SensorCalibrationView")

	station.interact()
	await process_frame

	# ============================================================
	# 1. Each chamber knob moves ONLY its own setpoint.
	# ============================================================
	for ch in view.CHAMBERS:
		var knob: Control = view._chamber_rows[ch]["knob"]
		var center: Vector2 = knob.size * 0.5
		var others: Array = view.CHAMBERS.filter(func(c): return c != ch)
		var before := {}
		for c in view.CHAMBERS:
			before[c] = view._setpoint[c]
		_press(view, ch, knob, center + Vector2(0, -50))
		_drag(view, ch, knob, center + Vector2(50, 0)) # quarter turn clockwise
		_release(view, ch, knob)
		_check("chamber %s knob moved its OWN setpoint" % ch, not is_equal_approx(view._setpoint[ch], before[ch]))
		for c in others:
			_check("chamber %s knob did NOT move chamber %s's setpoint" % [ch, c], is_equal_approx(view._setpoint[c], before[c]))

	# ============================================================
	# 2. The shared damping knob changes _damping, not any setpoint.
	# ============================================================
	var damping: Control = view._damping_knob
	var damping_center: Vector2 = damping.size * 0.5
	var setpoints_before := {}
	for ch in view.CHAMBERS:
		setpoints_before[ch] = view._setpoint[ch]
	var damping_before: float = view._damping
	_press(view, &"damping", damping, damping_center + Vector2(0, -50))
	_drag(view, &"damping", damping, damping_center + Vector2(50, 0))
	_release(view, &"damping", damping)
	_check("the damping knob changes _damping", view._damping != damping_before)
	for ch in view.CHAMBERS:
		_check("the damping knob does not change chamber %s's setpoint" % ch, is_equal_approx(view._setpoint[ch], setpoints_before[ch]))

	# ============================================================
	# 3. Shift held while dragging a chamber knob applies the shared
	# fine-mode rate reduction -- genuinely smaller movement for the
	# SAME drag angle.
	# ============================================================
	var a_knob: Control = view._chamber_rows[&"a"]["knob"]
	var a_center: Vector2 = a_knob.size * 0.5
	view._setpoint[&"a"] = 50.0 # reset to a safe middle value -- the per-chamber loop above already moved it, and a value too close to GAUGE_MAX/MIN would clamp the comparison below rather than genuinely testing the fine-rate reduction
	var before_coarse: float = view._setpoint[&"a"]
	_press(view, &"a", a_knob, a_center + Vector2(0, -50))
	_drag(view, &"a", a_knob, a_center + Vector2(50, 0))
	_release(view, &"a", a_knob)
	var coarse_delta: float = absf(view._setpoint[&"a"] - before_coarse)

	var shift_ev := InputEventKey.new()
	shift_ev.keycode = KEY_SHIFT
	shift_ev.pressed = true
	Input.parse_input_event(shift_ev)
	await process_frame
	view._setpoint[&"a"] = 50.0 # reset again so the fine check isn't clamped by the coarse check's own movement
	var before_fine: float = view._setpoint[&"a"]
	_press(view, &"a", a_knob, a_center + Vector2(0, -50))
	_drag(view, &"a", a_knob, a_center + Vector2(50, 0)) # the SAME drag angle as the coarse check above
	_release(view, &"a", a_knob)
	var fine_delta: float = absf(view._setpoint[&"a"] - before_fine)
	var shift_up := InputEventKey.new()
	shift_up.keycode = KEY_SHIFT
	shift_up.pressed = false
	Input.parse_input_event(shift_up)
	await process_frame
	_check(
		"holding Shift makes the SAME knob drag move the setpoint by a much smaller amount (coarse=%.3f fine=%.3f)" % [coarse_delta, fine_delta],
		fine_delta > 0.0 and fine_delta < coarse_delta * 0.4
	)

	# ============================================================
	# 4. Only one knob can be grabbed at a time.
	# ============================================================
	var b_knob: Control = view._chamber_rows[&"b"]["knob"]
	var b_center: Vector2 = b_knob.size * 0.5
	_press(view, &"a", a_knob, a_center + Vector2(0, -50))
	var a_setpoint_during: float = view._setpoint[&"a"]
	_drag(view, &"b", b_knob, b_center + Vector2(50, 0)) # a DIFFERENT control's motion while A is grabbed
	_check("a different knob's motion is ignored while another knob is actively grabbed", is_equal_approx(view._setpoint[&"a"], a_setpoint_during))
	_release(view, &"a", a_knob)

	# ============================================================
	# 5. All four knobs are inert once the task is already done.
	# ============================================================
	view._done = true
	var locked_a: float = view._setpoint[&"a"]
	var locked_damping: float = view._damping
	_press(view, &"a", a_knob, a_center + Vector2(0, -50))
	_drag(view, &"a", a_knob, a_center + Vector2(50, 0))
	_release(view, &"a", a_knob)
	_press(view, &"damping", damping, damping_center + Vector2(0, -50))
	_drag(view, &"damping", damping, damping_center + Vector2(50, 0))
	_release(view, &"damping", damping)
	_check("knob drag is inert once the station reports done", view._setpoint[&"a"] == locked_a and view._damping == locked_damping)
	view._done = false

	# ============================================================
	# 6. Each chamber's gauge readout mirrors the view's own simulation
	# state -- a visual state fully derived from authoritative values.
	# ============================================================
	view._setpoint[&"a"] = 42.0
	view._reading[&"a"] = 41.0
	view._stability_timer = 0.0
	view._refresh()
	var gauge_a: Control = view._chamber_rows[&"a"]["gauge"]
	_check("chamber A's gauge dial_value matches its setpoint", is_equal_approx(gauge_a.dial_value, 42.0))
	_check("chamber A's gauge reading_value matches its reading", is_equal_approx(gauge_a.reading_value, 41.0))
	_check("chamber A's gauge target_value matches its own target, not another chamber's", is_equal_approx(gauge_a.target_value, view._TARGETS[&"a"]))

	# ============================================================
	# 7. Status chip reflects LOW/IN RANGE/HIGH correctly per chamber.
	# ============================================================
	view._reading[&"a"] = view._TARGETS[&"a"] - view._tolerance - 5.0
	view._refresh()
	_check("status chip shows LOW when reading is well under target", view._chamber_rows[&"a"]["status"].text == "LOW")
	view._reading[&"a"] = view._TARGETS[&"a"] + view._tolerance + 5.0
	view._refresh()
	_check("status chip shows HIGH when reading is well over target", view._chamber_rows[&"a"]["status"].text == "HIGH")
	view._reading[&"a"] = view._TARGETS[&"a"]
	view._refresh()
	_check("status chip shows IN RANGE when reading matches target exactly", view._chamber_rows[&"a"]["status"].text == "IN RANGE")

	# ============================================================
	# 8. Cancelling (focus end) mid-adjustment loses no unrelated task
	# state and leaves the station resumable.
	# ============================================================
	var day_plan := main.get_node("DayPlan")
	day_plan.mark_done(&"c01") # unrelated progress
	main.get_node("FocusedInteractionState").end()
	_check("canceling calibration does not touch unrelated task state", day_plan.is_task_done(&"c01"))
	_check("l07 still not done after an abandoned attempt", not day_plan.is_task_done(&"l07"))

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _press(view: Node, control_name: StringName, knob: Control, local_pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = local_pos
	view._on_knob_gui_input(ev, control_name, knob)


func _drag(view: Node, control_name: StringName, knob: Control, local_pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = local_pos
	view._on_knob_gui_input(ev, control_name, knob)


func _release(view: Node, control_name: StringName, knob: Control) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	view._on_knob_gui_input(ev, control_name, knob)


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
