extends SceneTree
## Round 36 Priority 3: FILTER SERVICE VARIANTS. The housing is fixed; each
## service event finds it in one of four legitimate mechanical conditions
## (standard / loose latch L2 / seized latch L1 / cocked old cartridge),
## with a different replacement-cartridge start rotation and contamination.
## Proves: four distinct starting configurations exist; every one is
## solvable through the real procedure (with the physical cartridge from
## Storage, used-cartridge ejection, disposal and automatic closure);
## deterministic selection; no re-roll on reopen or save/load (with
## partial progress); no immediate repeats across recurring services.
const Solver = preload("res://tests/filter_service_solver.gd")
var _ok := true
var main: Node
var dp: Node
var station: Node
var carry: Node
var view: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 6: await process_frame
	dp = main.get_node("DayPlan")
	station = main.get_node("Interactables/FilterHousingStation")
	carry = main.get_node("Player/CarrySystem")
	view = station._filter_view
	_distinct_configs()
	_each_variant_solvable()
	_selection_rules()
	await _reopen_and_save_load()
	await _dayplan_generates_variant()
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _cart() -> Node3D:
	for c in get_nodes_in_group(&"storage_cabinet"):
		for it in c._items:
			if is_instance_valid(it) and c.is_item_stowed(it) and it.item_id == &"filter_cartridge":
				return it
	for r in get_nodes_in_group(&"supply_reserve"):
		for it in r.find_children("*", "", true, false):
			if "item_id" in it and it.item_id == &"filter_cartridge" and r.is_in_reserve(it):
				return it
	return null


func _take(item: Node3D) -> void:
	if carry.is_carrying():
		carry.drop()
	carry.pick_up(item)
	if carry.is_reaching():
		carry.complete_grasp()


func _distinct_configs() -> void:
	var sigs := {}
	for v in 4:
		station.apply_variant(v)
		var sig: String = "%s|L1=%s L2=%s|seize=%d|old=%d|start=%d" % [station.variant_name(), station.latch_open(1), station.latch_open(2), station.seized_pulls_left(), roundi(station.old_cartridge_angle_deg()), roundi(station._VARIANT_NEW_START[v])]
		sigs[sig.get_slice("|", 1) + sig.get_slice("|", 2) + sig.get_slice("|", 3) + sig.get_slice("|", 4)] = true
		print("  variant %d: %s  -- %s" % [v, sig, station.variant_observation()])
	_check("four mechanically distinct starting configurations (%d)" % sigs.size(), sigs.size() == 4)
	station.apply_variant(1)
	_check("LOOSE_LATCH: L2 starts released, visibly (diorama latch rotated)", station.latch_open(2) and absf(station._world_diorama._latch_bodies[2].get_parent().rotation.x) > 0.5)
	station.apply_variant(2)
	_check("SEIZED_LATCH: residue shown on latch L1", station._world_diorama._residue[0].visible)
	station.apply_variant(3)
	_check("COCKED: the old cartridge tab sits off the keyway (45 deg vs 135)", not station.old_cartridge_aligned() and absf(rad_to_deg(station._world_diorama._old_tab_root.rotation.x) - 45.0) < 1.0)


func _each_variant_solvable() -> void:
	for v in 4:
		station.apply_variant(v)
		var c: Node3D = _cart()
		if c == null:
			_check("variant %d: a clean cartridge is available" % v, false)
			continue
		_take(c)
		var S = station.Stage
		# Variant-specific mechanics, step by step.
		station.toggle_isolate()
		if v == 2:
			for k in 3:
				var r: Dictionary = station.toggle_latch(1)
				_check("SEIZED: pull %d works it looser without releasing (%d left)" % [k + 1, r.get("pulls_left", -1)], r.get("seized", false) and not station.latch_open(1))
		if v == 1:
			var r1: Dictionary = station.toggle_latch(2)
			_check("LOOSE: clicking the already-released L2 does not re-latch it", r1.get("already_open", false) and station.latch_open(2))
		if v == 3:
			station.toggle_latch(1); station.toggle_latch(2)
			_check("COCKED: latches released", station.stage() == S.REMOVE_OLD)
			var turns := 0
			while not station.old_cartridge_aligned() and turns < 8:
				var rr: Dictionary = station.remove_old_cartridge()
				_check("COCKED: a pull attempt turns it instead of removing it", rr.get("turned", false) and station.stage() == S.REMOVE_OLD)
				turns += 1
			_check("COCKED: back on its keyway after %d turn(s)" % turns, station.old_cartridge_aligned() and turns == 2)
		var n: int = Solver.solve(station)
		_check("variant %d (%s) completes through the real procedure (%d actions)" % [v, station.variant_name(), n], n > 0 and station.stage() == S.COMPLETE)
		_check("variant %d: the new cartridge is installed, the old one ejected as a real used item" % v, is_instance_valid(station._installed_cartridge) and station._installed_cartridge.is_installed() and is_instance_valid(station._used_cartridge) and station._used_cartridge.is_ejected())
		# Dispose of the used cartridge (the next service ejects a new one).
		var used: Node3D = station._used_cartridge
		_take(used)
		main.get_node("Interactables/TrashDisposal").interact()
		_check("variant %d: used cartridge disposed (not carried)" % v, not carry.is_carrying())
		dp.l02_status = dp.TaskStatus.PENDING
		await_frame_noop()


func await_frame_noop() -> void:
	pass


func _selection_rules() -> void:
	# Round 38: seized / cocked conditions need life-support experience.
	dp.proficiency["life_support"] = 1
	station.apply_variant(0)
	station.select_variant(1234)
	var a: int = station.variant()
	station._last_variant = 0
	station.apply_variant(0)
	station.select_variant(1234)
	_check("deterministic: the same seed gives the same variant (%d)" % a, station.variant() == a)
	var seen := {}
	var prev: int = station.variant()
	var repeats := 0
	for day in range(2, 26):
		station._stage = station.Stage.COMPLETE
		station.select_variant(hash([day, 2]))
		if station.variant() == prev:
			repeats += 1
		prev = station.variant()
		seen[prev] = true
	_check("recurring services: never the same variant twice in a row (%d repeats)" % repeats, repeats == 0)
	_check("recurring services: all four variants occur (%s)" % str(seen.keys()), seen.size() == 4)
	station.apply_variant(2)
	station._stage = station.Stage.OPEN_LATCHES
	station.select_variant(99)
	_check("a procedure in progress is never re-rolled", station.variant() == 2)
	station._stage = station.Stage.ISOLATE


func _reopen_and_save_load() -> void:
	station.apply_variant(2)
	station.toggle_isolate()
	station.toggle_latch(1)   # 2 pulls left
	station.interact()
	await process_frame
	_check("opening the focused view shows the variant (residue on L1) without re-rolling", station.variant() == 2 and station.seized_pulls_left() == 2 and view._diorama._residue[0].visible)
	main.get_node("FocusedInteractionState").end()
	await process_frame
	station.interact()
	await process_frame
	main.get_node("FocusedInteractionState").end()
	await process_frame
	_check("reopening: same variant, same partial progress", station.variant() == 2 and station.seized_pulls_left() == 2)
	var sg: Node = main.get_node("SaveGame")
	sg.save_path = "user://test_filter_variants.json"
	if carry.is_carrying():
		carry.drop()
	var r: Dictionary = sg.save_game()
	_check("save mid-procedure: %s" % r["message"], r["ok"])
	station.apply_variant(0)
	sg.apply_state(sg.read_save()["data"])
	_check("load: variant, stage and seized-latch progress restored (v=%d stage=%d pulls=%d)" % [station.variant(), station.stage(), station.seized_pulls_left()], station.variant() == 2 and station.stage() == station.Stage.OPEN_LATCHES and station.seized_pulls_left() == 2)
	# Cocked + one turn done.
	station.apply_variant(3)
	station.toggle_isolate(); station.toggle_latch(1); station.toggle_latch(2)
	station.remove_old_cartridge()
	sg.save_game()
	station.apply_variant(0)
	sg.apply_state(sg.read_save()["data"])
	_check("load: cocked cartridge keeps its partial turn (%d deg)" % roundi(station.old_cartridge_angle_deg()), station.variant() == 3 and roundi(station.old_cartridge_angle_deg()) == 90 and station.stage() == station.Stage.REMOVE_OLD)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_filter_variants.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_filter_variants.json.bak"))
	station.apply_variant(0)


func _dayplan_generates_variant() -> void:
	# Day 2 is the first filter service: DayPlan generates the event and
	# the housing's variant is chosen then (deterministically by day seed).
	station._stage = station.Stage.ISOLATE
	dp._serviced.clear()   # the sections above serviced the housing on day 1
	dp.service_history.clear()
	dp.reset_for_new_day()
	_check("day 2 is a filter service", dp.workday == dp.Workday.FILTER_SERVICE)
	var expect_seed: int = dp.daily_variant_seed(dp.Workday.FILTER_SERVICE)
	_check("the variant was chosen for the new service event (day %d)" % station._variant_day, station._variant_day == 2)
	var v: int = station.variant()
	dp.day_started.emit(dp.day_number)
	_check("re-emitting day_started (as a load does) does not re-roll", station.variant() == v)
	print("  day-2 seed %d -> variant %s" % [expect_seed, station.variant_name()])


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
