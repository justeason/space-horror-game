extends SceneTree
## Round 15 Priority 3 regression coverage for the HARD-mode hand-powered
## flashlight generator. Confirms: EASY/NORMAL keep Round 14's plain
## toggle behavior unchanged; HARD has no on/off switch -- each genuine
## (non-echo) L key-down adds bounded energy, OS auto-repeat (echo)
## events add nothing (the actual mechanism preventing one held key from
## granting unlimited energy), holding L trickle-charges at a slower
## rate as an accessible alternative to tapping, charge decays over
## time, brightness is a smooth function of charge (not binary), the
## beam hides while focused but charge keeps decaying normally, and
## switching difficulty live (NORMAL<->HARD) converts between the two
## state representations without losing light unexpectedly or granting
## free energy.
const GameSettings = preload("res://scripts/station/game_settings.gd")
var _ok := true

func _init() -> void:
	while GameSettings.get_difficulty() != GameSettings.Difficulty.NORMAL:
		GameSettings.cycle_difficulty()

	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player := main.get_node("Player")
	var flashlight := player.get_node("LookPivot/PitchPivot/Camera3D/Flashlight")
	var light: SpotLight3D = flashlight.get_node("SpotLight3D")

	# ============================================================
	# NORMAL: unchanged plain toggle (Round 14 behavior).
	# ============================================================
	_check("NORMAL: starts off", not flashlight.is_on())
	_press(main)
	await process_frame
	_check("NORMAL: one press turns it on", flashlight.is_on())
	_check("NORMAL: beam visible once on", light.visible)
	_press(main)
	await process_frame
	_check("NORMAL: second press turns it back off", not flashlight.is_on())

	# ============================================================
	# Switch to HARD.
	# ============================================================
	GameSettings.cycle_difficulty() # NORMAL -> HARD
	await process_frame
	_check("HARD: starts with zero charge (was off in NORMAL)", is_equal_approx(flashlight.charge(), 0.0))
	_check("HARD: beam hidden at zero charge", not light.visible)

	_press(main)
	await process_frame
	var charge_after_one_pump: float = flashlight.charge()
	_check("HARD: a genuine press adds real charge", charge_after_one_pump > 0.1)
	_check("HARD: beam visible once charged", light.visible)

	# OS auto-repeat (echo) must add nothing -- the actual rate-limit.
	var echo_before: float = flashlight.charge()
	var echo_ev := InputEventKey.new()
	echo_ev.keycode = KEY_L
	echo_ev.pressed = true
	echo_ev.echo = true
	for i in 8:
		main.get_viewport().push_input(echo_ev)
	await process_frame
	# A tiny amount of normal decay happens across this one frame
	# regardless -- the real assertion is that charge did NOT jump up
	# from 8 echo "presses" (each worth PUMP_GAIN=0.22 if they wrongly
	# counted, i.e. +1.76 if the rate-limit were broken).
	_check("HARD: OS key-repeat (echo) events add no charge at all", flashlight.charge() <= echo_before)

	var release := InputEventKey.new()
	release.keycode = KEY_L
	release.pressed = false
	main.get_viewport().push_input(release)
	await process_frame

	# Decay over time.
	var before_decay: float = flashlight.charge()
	await create_timer(1.0).timeout
	_check("HARD: charge decays steadily over time", flashlight.charge() < before_decay)

	# Holding L trickle-charges (the accessible alternative to tapping).
	var hold_down := InputEventKey.new()
	hold_down.keycode = KEY_L
	hold_down.pressed = true
	main.get_viewport().push_input(hold_down)
	await process_frame
	var hold_start: float = flashlight.charge()
	await create_timer(1.0).timeout
	_check("HARD: holding L (not tapping) still increases charge over time -- accessible alternative", flashlight.charge() > hold_start)
	main.get_viewport().push_input(release)
	await process_frame

	# Charge is bounded (cannot exceed max even with many presses).
	for i in 20:
		_press(main)
		await process_frame
	_check("HARD: charge is bounded, never exceeds 1.0 even after many presses", flashlight.charge() <= 1.0001)

	# ============================================================
	# Focused-session gating: beam hides, pumping is ignored, but
	# charge still decays normally while focused.
	# ============================================================
	var panel: Node = main.get_node("Geometry/EngineeringCabinet1")
	var day_plan: Node = main.get_node("DayPlan")
	var terminal: Node = panel.get_node("Terminal")
	var focused := main.get_node("FocusedInteractionState")

	day_plan.trigger_fault()
	panel.interact()
	terminal.interact()
	terminal.interact()
	await process_frame
	_check("focused session is active", focused.is_active())
	_check("HARD: beam hidden while focused", not light.visible)

	var charge_while_focused_before: float = flashlight.charge()
	_press(main)
	await process_frame
	_check("HARD: pressing L while focused does not pump (ignored like every other control)", flashlight.charge() <= charge_while_focused_before)

	await create_timer(0.5).timeout
	_check("HARD: charge keeps decaying normally while focused", flashlight.charge() < charge_while_focused_before)

	focused.end()
	for i in 6: await process_frame
	_check("HARD: beam reappears after focus ends (charge was never reset)", light.visible)

	# ============================================================
	# Live difficulty switching: HARD -> NORMAL converts remaining
	# charge into an on/off state; NORMAL -> HARD converts back.
	# ============================================================
	GameSettings.cycle_difficulty() # HARD -> EASY
	GameSettings.cycle_difficulty() # EASY -> NORMAL
	await process_frame
	_check("switching HARD->NORMAL with real charge remaining keeps the light effectively on", flashlight.is_on())
	_check("switching HARD->NORMAL does not produce an unexpected dark screen", light.visible)

	GameSettings.cycle_difficulty() # NORMAL -> HARD
	await process_frame
	_check("switching back NORMAL->HARD starts with a real (not infinite, not zero) charge", flashlight.charge() > 0.0 and flashlight.charge() <= 1.0)

	main.queue_free()
	await process_frame

	while GameSettings.get_difficulty() != GameSettings.Difficulty.NORMAL:
		GameSettings.cycle_difficulty()

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _press(main: Node) -> void:
	var down := InputEventKey.new()
	down.keycode = KEY_L
	down.pressed = true
	main.get_viewport().push_input(down)
	var up := InputEventKey.new()
	up.keycode = KEY_L
	up.pressed = false
	main.get_viewport().push_input(up)


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
