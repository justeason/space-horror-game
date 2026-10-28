extends SceneTree
## Round 16 Priority 7 regression coverage for M02 Signal Calibration
## (Communications) -- the new maintenance mechanic this round adds:
## continuous TWO-PARAMETER tuning (frequency + gain) toward a fixed,
## hidden target, with completion requiring signal quality to stay
## above threshold for a SUSTAINED real-time period, not an instant
## threshold crossing. Genuinely different in kind from every other
## task in this project (not a discrete sequence, not a single toggle,
## not alignment/insertion, not evidence-based point-and-diagnose).
##
## Covers: starting state is deliberately far from the solution (real
## work required); frequency alone cannot reach full quality (gain
## matters too -- a real two-parameter problem, not "turn one knob");
## tuning both dials via REAL diorama clicks (raycast-resolved L/R
## halves) reaches a high-quality state; dropping below threshold
## resets the sustain timer (recoverable, never a hard failure);
## holding a good tune for the full sustain period (a genuine wall-
## clock timer, not a frame-count proxy -- headless frame deltas are
## not fixed to 1/60s) completes the task; HARD difficulty hides the
## numeric readout; the world-view twin stays in sync; and reopening
## after completion shows the done state immediately.
const GameSettings = preload("res://scripts/station/game_settings.gd")

var _ok := true

func _init() -> void:
	while GameSettings.get_difficulty() != GameSettings.Difficulty.NORMAL: GameSettings.cycle_difficulty()

	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player := main.get_node("Player")
	var free_body := main.get_node("FreeMoveBody")
	free_body.set_active(false)
	var day_plan := main.get_node("DayPlan")
	var station := main.get_node("Interactables/SignalCalibrationStation")
	var view := player.get_node("HUD/SignalCalibrationView")
	var focused := main.get_node("FocusedInteractionState")
	# Round 17 Priority 3: lock the pre-Round-17 fixed profile before
	# anything else (frequency()/target_frequency() below) can trigger
	# _ensure_profile()'s random pick -- every assertion in this file
	# hardcodes the "default" profile's exact numbers.
	station.debug_force_profile(&"default")

	_check("m02 not done at start", not day_plan.is_task_done(&"m02"))
	_check("prompt invites calibration before completion", station.get_interact_prompt().findn("Calibrate") != -1)
	_check("starting frequency is far from the target (real work required)", absf(station.frequency() - station.target_frequency()) > 20.0)
	_check("starting quality is low", station.signal_quality() < 0.2)

	station.interact()
	await process_frame
	_check("focused session active", focused.is_active())
	_check("signal view visible", view.visible)

	var diorama: Node3D = view.get_node("Panel/VBox/DioramaContainer/DioramaViewport/SignalCalibrationDiorama")

	# ============================================================
	# Frequency alone (gain left at its low starting value) must NOT
	# reach full quality -- a genuine two-parameter problem.
	# ============================================================
	for i in 26: # 12 -> ~64, step 2
		_click(diorama, &"freq", 1)
		await physics_frame
	_check("frequency reaches near the target", absf(station.frequency() - station.target_frequency()) <= 2.0)
	_check("quality still low with gain untouched (frequency alone is not enough)", station.signal_quality() < 0.3)

	for i in 10: # 0.2 -> 0.7, step 0.05
		_click(diorama, &"gain", 1)
		await physics_frame
	_check("gain reaches the target", is_equal_approx(station.gain(), 0.7))
	_check("quality now high with both dials tuned", station.signal_quality() >= station.quality_threshold())

	# ============================================================
	# Dropping below threshold (detune gain away) resets the sustain
	# timer -- recoverable, not a hard failure.
	# ============================================================
	await create_timer(0.4).timeout # partial hold
	_check("partial hold accumulated some progress", station.sustain_progress() > 0.0)
	for i in 4: # detune enough to actually cross below threshold (one
		# step alone is too small a change at this falloff -- see
		# signal_calibration_station.gd's _gain_factor())
		_click(diorama, &"gain", -1)
		await physics_frame
	_check("quality dropped below threshold after detuning", station.signal_quality() < station.quality_threshold())
	await create_timer(0.3).timeout
	_check("sustain progress reset while below threshold", station.sustain_progress() == 0.0)
	_check("task not complete yet", not day_plan.is_task_done(&"m02"))

	# Re-tune back to the good state and hold for the FULL sustain
	# period this time (a real wall-clock wait -- headless frame deltas
	# are not fixed to 1/60s, so a frame-count loop would not reliably
	# represent real elapsed time here).
	for i in 4:
		_click(diorama, &"gain", 1)
		await physics_frame
	_check("quality back above threshold", station.signal_quality() >= station.quality_threshold())
	await create_timer(station.sustain_seconds() + 0.3).timeout
	_check("task completes once quality is sustained for the full period", day_plan.is_task_done(&"m02"))
	_check("station reports complete", station.is_complete())

	# World-view twin must reflect the exact same state.
	var world_diorama := station.get_node("WorldDiorama")
	_check("world diorama needle matches focused needle rotation", is_equal_approx(world_diorama.get_node("Meter/Needle").rotation.z, diorama.get_node("Meter/Needle").rotation.z))

	focused.end()
	await process_frame
	_check("prompt reflects nominal status", station.get_interact_prompt().findn("Nominal") != -1)
	station.interact()
	await process_frame
	_check("reopening after completion still shows complete", station.is_complete())
	_check("m02 still done on reopen (not reset)", day_plan.is_task_done(&"m02"))
	focused.end()
	await process_frame

	main.queue_free()
	await process_frame
	await create_timer(0.2).timeout

	# ============================================================
	# HARD difficulty: no numeric readout.
	# ============================================================
	while GameSettings.get_difficulty() != GameSettings.Difficulty.HARD: GameSettings.cycle_difficulty()
	var main2: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main2)
	current_scene = main2
	for i in 5: await process_frame
	var station2 := main2.get_node("Interactables/SignalCalibrationStation")
	station2.interact()
	await process_frame
	_check("HARD: numeric readout hidden", not station2.show_numeric_readout())
	_check("HARD: no target marker either", not station2.show_target_marker())
	main2.get_node("FocusedInteractionState").end()
	await process_frame
	main2.queue_free()
	await process_frame

	while GameSettings.get_difficulty() != GameSettings.Difficulty.NORMAL: GameSettings.cycle_difficulty()

	await _test_keyboard_input_and_alternate_profile()
	await _test_tuning_state_progression()

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


## Round 17 Priority 3 coverage: (a) the keyboard IS now a real, primary
## control path -- Left/Right/Up/Down real key events, routed through
## SignalCalibrationView._unhandled_input(), actually move the dials,
## not just the diorama's own mouse-raycast path; (b) a genuinely
## different profile ("low_band") reaches completion on its own correct
## target/falloff/sustain values, proving the per-attempt variation
## mechanic actually drives the puzzle, not just cosmetic labeling.
func _test_keyboard_input_and_alternate_profile() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player := main.get_node("Player")
	var free_body := main.get_node("FreeMoveBody")
	free_body.set_active(false)
	var day_plan := main.get_node("DayPlan")
	var station := main.get_node("Interactables/SignalCalibrationStation")
	var view := player.get_node("HUD/SignalCalibrationView")
	var focused := main.get_node("FocusedInteractionState")
	station.debug_force_profile(&"low_band")

	_check("[low_band] profile actually locked to low_band", station.active_profile_label() == "low_band")
	_check("[low_band] target is the low_band target, not default's", is_equal_approx(station.target_frequency(), 28.0))
	_check("[low_band] starting frequency is far from this profile's own target", absf(station.frequency() - station.target_frequency()) > 20.0)

	station.interact()
	await process_frame
	_check("[low_band] focused session active", focused.is_active())

	# Starting freq=82 -> target=28: 27 steps of -2 lands at 28 exactly.
	for i in 27:
		_key(view, KEY_LEFT)
		await physics_frame
	_check("[low_band] frequency reaches this profile's own target via REAL KEYBOARD input", is_equal_approx(station.frequency(), 28.0))
	_check("[low_band] quality still low with gain untouched", station.signal_quality() < 0.3)

	# Starting gain=0.85 -> target=0.45: 8 steps of -0.05 lands at 0.45.
	for i in 8:
		_key(view, KEY_DOWN)
		await physics_frame
	_check("[low_band] gain reaches this profile's own target via REAL KEYBOARD input", is_equal_approx(station.gain(), 0.45))
	_check("[low_band] quality now high with both dials tuned", station.signal_quality() >= station.quality_threshold())

	await create_timer(station.sustain_seconds() + 0.3).timeout
	_check("[low_band] task completes on this profile's own (longer, 2.2s) sustain duration", day_plan.is_task_done(&"m02"))

	focused.end()
	await process_frame
	main.queue_free()
	await process_frame
	await create_timer(0.2).timeout


## Dispatches a real InputEventKey through the view's own
## _unhandled_input(), the same entry point a real keypress reaches --
## not a direct _on_freq_nudge()/_on_gain_nudge() call.
## Round 18 Priority 4 coverage: the named tuning-state progression
## (SEARCHING -> SIGNAL ACQUIRED -> FINE TUNING -> STABILIZING -> SIGNAL
## LOCKED) actually reflects real frequency_accuracy()/gain_accuracy()/
## signal_quality() state, driven via real keyboard input end to end --
## not merely that five strings exist somewhere, but that the state
## machine transitions at the right moments as the player actually
## tunes, including losing STABILIZING when quality drops back out of
## range (the brief's own "make failure/lost lock understandable").
func _test_tuning_state_progression() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player := main.get_node("Player")
	var free_body := main.get_node("FreeMoveBody")
	free_body.set_active(false)
	var day_plan := main.get_node("DayPlan")
	var station := main.get_node("Interactables/SignalCalibrationStation")
	var view := player.get_node("HUD/SignalCalibrationView")
	station.debug_force_profile(&"default")
	station.interact()
	await process_frame

	_check("[state] starts SEARCHING (far from target on both axes)", view._current_state() == view._TuneState.SEARCHING)
	_check("[state] SEARCHING status text names the state", view._status_label.text.findn("SEARCHING") != -1)

	# Freq 12 -> 56 (22 steps of +2): within frequency_accuracy()'s own
	# >= 0.5 threshold, gain untouched -- exactly ONE axis close.
	for i in 22:
		_key(view, KEY_RIGHT)
	view._refresh()
	_check("[state] frequency_accuracy alone crosses the axis-ok threshold", station.frequency_accuracy() >= 0.5)
	_check("[state] gain_accuracy still far below it (gain untouched)", station.gain_accuracy() < 0.5)
	_check("[state] -> SIGNAL ACQUIRED once exactly one axis is close", view._current_state() == view._TuneState.ACQUIRED)
	_check("[state] ACQUIRED status text names frequency specifically as the close axis", view._status_label.text.findn("frequency is close") != -1)

	# Gain 0.2 -> 0.55 (7 steps of +0.05): now BOTH axes close, but
	# combined quality (~0.53*0.625=0.33) is still well under NORMAL's
	# 0.72 completion threshold -- FINE TUNING, not yet STABILIZING.
	for i in 7:
		_key(view, KEY_UP)
	view._refresh()
	_check("[state] gain_accuracy now also crosses the axis-ok threshold", station.gain_accuracy() >= 0.5)
	_check("[state] combined quality is still below the completion threshold", station.signal_quality() < station.quality_threshold())
	_check("[state] -> FINE TUNING once both axes are close but quality isn't there yet", view._current_state() == view._TuneState.FINE_TUNING)

	# Drive both all the way to their exact targets -> full quality ->
	# STABILIZING.
	for i in 4: _key(view, KEY_RIGHT) # freq 56 -> 64 (target 63, within step)
	for i in 3: _key(view, KEY_UP) # gain 0.55 -> 0.70 (exact target)
	view._refresh()
	_check("[state] combined quality now meets the completion threshold", station.signal_quality() >= station.quality_threshold())
	_check("[state] -> STABILIZING once quality meets the threshold", view._current_state() == view._TuneState.STABILIZING)
	_check("[state] STABILIZING status text shows a holding percentage", view._status_label.text.findn("STABILIZING") != -1)

	# Detune gain hard -> quality drops back out of range -> state falls
	# back (the brief's own "make failure/lost lock understandable").
	for i in 10: _key(view, KEY_DOWN)
	view._refresh()
	_check("[state] losing quality drops OUT of STABILIZING (lost-lock is understandable, not stuck)", view._current_state() != view._TuneState.STABILIZING)

	# Re-tune and actually hold for the full real sustain duration ->
	# LOCKED, with the color-coded status label reflecting it.
	for i in 10: _key(view, KEY_UP)
	await create_timer(station.sustain_seconds() + 0.3).timeout
	_check("[state] -> SIGNAL LOCKED once held for the full sustain duration", view._current_state() == view._TuneState.LOCKED)
	_check("[state] LOCKED status text says SIGNAL LOCKED", view._status_label.text.findn("SIGNAL LOCKED") != -1)
	_check("[state] LOCKED status label is modulated the distinct LOCKED color", view._status_label.modulate.is_equal_approx(view._STATE_COLOR[view._TuneState.LOCKED]))
	_check("m02 marked done", day_plan.is_task_done(&"m02"))

	main.get_node("FocusedInteractionState").end()
	await process_frame
	main.queue_free()
	await create_timer(0.2).timeout


func _key(view: Control, keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	view._unhandled_input(ev)


func _click(diorama: Node3D, action: StringName, direction: int) -> void:
	var pos: Vector2 = diorama.dial_half_screen_position(action, direction)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	diorama._unhandled_input(down)


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
