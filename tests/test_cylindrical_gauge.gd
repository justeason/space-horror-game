extends SceneTree
## Coverage for the second, visually distinct calibration-instrument
## style (scripts/ui/cylindrical_gauge.gd, a drum/scrolling-scale
## readout) alongside the existing circular analog_gauge.gd dial --
## toggled with Tab inside scripts/ui/sensor_calibration_view.gd.
## Round 13 Workstream D update: L07 now has THREE chambers, each with
## its own circular+cylindrical gauge PAIR -- Tab must switch ALL THREE
## chambers' displayed style TOGETHER (one consistent design, never a
## mixed mode where some chambers show circular and others cylindrical)
## while every chamber still reflects the same live per-chamber
## simulation state regardless of which style is shown, and toggling
## never touches L07's authoritative task state.
var _ok := true

func _init() -> void:
	# ============================================================
	# 1. The cylindrical gauge is a genuinely standalone, reusable
	# component -- works with no calibration station/view/task
	# wiring at all, just like analog_gauge.gd.
	# ============================================================
	var standalone := Control.new()
	standalone.set_script(load("res://scripts/ui/cylindrical_gauge.gd"))
	standalone.size = Vector2(230, 230)
	get_root().add_child(standalone)
	for i in 2: await process_frame
	standalone.set_readout(42.0, 47.0, 0.6, true)
	_check("standalone cylindrical gauge accepts set_readout() with no station/view", is_equal_approx(standalone.dial_value, 42.0))
	_check("standalone cylindrical gauge stores the reading value", is_equal_approx(standalone.reading_value, 47.0))
	_check("standalone cylindrical gauge stores in_tolerance", standalone.in_tolerance)
	standalone.queue_free()

	# ============================================================
	# 2. Inside the real focused view: circular is the default/primary
	# instrument for all three chambers; Tab toggles ALL THREE to the
	# cylindrical style TOGETHER (never a mixed mode) and back, driving
	# the SAME per-chamber simulation state either way.
	# ============================================================
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player := main.get_node("Player")
	var station := main.get_node("Interactables/SensorCalibrationStation")
	var view := player.get_node("HUD/SensorCalibrationView")
	var day_plan := main.get_node("DayPlan")

	station.interact()
	await process_frame
	for ch in view.CHAMBERS:
		_check("chamber %s: circular gauge visible by default" % ch, view._chamber_rows[ch]["gauge"].visible)
		_check("chamber %s: cylindrical gauge hidden by default" % ch, not view._chamber_rows[ch]["cylgauge"].visible)
	_check("not using cylinder display by default", not view._use_cylinder_display)

	await _press(KEY_TAB)
	_check("Tab switches to the cylindrical display", view._use_cylinder_display)
	for ch in view.CHAMBERS:
		_check("chamber %s: cylindrical gauge now visible" % ch, view._chamber_rows[ch]["cylgauge"].visible)
		_check("chamber %s: circular gauge now hidden" % ch, not view._chamber_rows[ch]["gauge"].visible)
	_check("the two gauge scripts are genuinely distinct instruments", view._chamber_rows[&"a"]["gauge"].get_script() != view._chamber_rows[&"a"]["cylgauge"].get_script())

	# The displayed instrument must reflect the SAME live per-chamber
	# simulation state as the circular one did -- not a second
	# independent copy, and not another chamber's values.
	view._setpoint[&"a"] = 33.0
	view._reading[&"a"] = 38.0
	view._setpoint[&"b"] = 70.0
	view._reading[&"b"] = 72.0
	view._refresh()
	_check("chamber A's cylindrical gauge reflects chamber A's real setpoint", is_equal_approx(view._chamber_rows[&"a"]["cylgauge"].dial_value, 33.0))
	_check("chamber A's cylindrical gauge reflects chamber A's real reading", is_equal_approx(view._chamber_rows[&"a"]["cylgauge"].reading_value, 38.0))
	_check("chamber B's cylindrical gauge reflects chamber B's OWN real setpoint, not chamber A's", is_equal_approx(view._chamber_rows[&"b"]["cylgauge"].dial_value, 70.0))

	await _press(KEY_TAB)
	_check("Tab switches back to the circular display", not view._use_cylinder_display)
	for ch in view.CHAMBERS:
		_check("chamber %s: circular gauge visible again" % ch, view._chamber_rows[ch]["gauge"].visible)
		_check("chamber %s: cylindrical gauge hidden again" % ch, not view._chamber_rows[ch]["cylgauge"].visible)

	# ============================================================
	# 3. Toggling the display style never touches task state, and
	# reopening resets to the circular default (not whatever was left
	# selected last time -- a purely session-local cosmetic choice).
	# ============================================================
	_check("l07 still not done after toggling display styles", not day_plan.is_task_done(&"l07"))
	await _press(KEY_TAB) # leave it on cylindrical
	_check("left on cylindrical for this session", view._use_cylinder_display)
	main.get_node("FocusedInteractionState").end()
	station.interact()
	await process_frame
	_check("reopening resets to the circular default regardless of the prior session's choice", not view._use_cylinder_display)
	for ch in view.CHAMBERS:
		_check("chamber %s: circular gauge visible again on reopen" % ch, view._chamber_rows[ch]["gauge"].visible)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()

func _press(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame

func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
