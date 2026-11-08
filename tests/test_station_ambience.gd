extends SceneTree
## Round 28 Priority 6: ambience beds exist, play, and follow REAL
## equipment state (no scripted horror cues): the Engineering crackle only
## while the power fault is open; Life Support airflow strained only while
## the filter housing is isolated for service.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame
	var amb: Node = main.get_node("StationAmbience")
	var dp: Node = main.get_node("DayPlan")
	var station: Node = main.get_node("Interactables/FilterHousingStation")
	_check("four looping ambience beds built (playing under a real audio driver)", amb.beds_running())
	_check("beds are quiet (<= -24 dB)", amb.vent.volume_db <= -24.0 and amb.engineering.volume_db <= -24.0 and amb.life_support.volume_db <= -24.0)
	_check("no engineering crackle before any fault", not amb.engineering_fault_active() and amb.engineering_fault.volume_db <= -79.0)
	dp.trigger_fault()
	await create_timer(1.0).timeout   # Round 31: fades in (~0.75 s), not a switch
	_check("engineering crackle audible while the power fault is open", amb.engineering_fault_active() and amb.engineering_fault.volume_db > -30.0)
	var normal_ls: float = amb.life_support.volume_db
	station.toggle_isolate()
	await create_timer(0.4).timeout
	_check("airflow is spinning DOWN, not switched off (mid-ramp %.2f)" % amb.life_support_spin(), amb.life_support_spin() > 0.2 and amb.life_support_spin() < 0.95)
	await create_timer(1.4).timeout
	_check("life support airflow strained while the filter housing is isolated", amb.life_support.volume_db < normal_ls and amb.life_support.pitch_scale < 1.0)
	_check("isolation state comes from the real station", station.is_isolated())
	station._stage = station.Stage.RESTORE   # skip the cartridge swap itself
	station.toggle_isolate()                  # the real "restore airflow" step
	await create_timer(1.8).timeout
	_check("airflow spins back up when restored", amb.life_support_spin() > 0.99 and is_equal_approx(amb.life_support.pitch_scale, 1.0))
	# Round 38: room identities; the Comms whine follows the real B-04 circuit.
	_check("Round 38 room beds built (comms / airlock / storage), quiet", amb.comms != null and amb.airlock.volume_db <= -24.0 and amb.storage.volume_db <= -24.0)
	_check("comms whine audible while B-04 is on", amb.comms.volume_db > -40.0)
	var bp: Node = main.get_node("Equipment/BreakerPanel")
	var ci: int = -1
	for i in bp.BREAKERS.size():
		if bp.BREAKERS[i]["zone"] == &"communications": ci = i
	bp.on[ci] = false
	await process_frame
	await process_frame
	_check("comms whine silent when B-04 is switched off", amb.comms.volume_db <= -79.0)
	bp.on[ci] = true
	await process_frame
	await process_frame
	_check("comms whine returns when B-04 is restored", amb.comms.volume_db > -40.0)
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()

func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
