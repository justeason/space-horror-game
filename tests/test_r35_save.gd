extends SceneTree
## Round 35 Priority 13: every new state survives save/load mid-task, into
## a FRESH station, without re-rolling: breakers + lighting, grille dirt /
## cover / clips, power settings and demand, seal faults / inspection,
## the data module (owner + captured payload), environment values, and the
## concurrent orders. Own save path only.
var _ok := true
const PATH := "user://test_r35_save.json"

func _init() -> void:
	for p in [PATH, PATH + ".bak", PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var main: Node = await _fresh()
	var dp: Node = main.get_node("DayPlan")
	for d in 6:
		dp.reset_for_new_day()   # day 7: several orders open
	var br: Node = main.get_node("Equipment/BreakerPanel")
	var v: Node = main.get_node("Equipment/VentGrille")
	var pw: Node = main.get_node("Equipment/PowerDistribution")
	var hs: Node = main.get_node("Equipment/HatchSeal")
	var cap: Node = main.get_node("Equipment/CapturePort")
	var up: Node = main.get_node("Equipment/UploadPort")
	var env: Node = main.get_node("EnvironmentModel")
	var carry: Node = main.get_node("Player/CarrySystem")
	br.trip(2, "surge")
	v.order_rearm(777)
	v.on_part(&"gauge"); v.on_part(&"c0"); v.on_part(&"c1"); v.on_part(&"cover")
	for i in 4:
		if v.dirt[i] > 0.05:
			v.on_part(StringName("s%d" % i))
			break
	pw.order_rearm(999)
	hs.order_rearm(555)
	var port: Node = main.get_node("Interactables/CargoPort")
	if port.state == port.PortState.SECURED:
		hs.on_part(&"mode")
		hs.on_part(&"s0")
	var m: Node3D = up.module()
	m.interact()
	if carry.is_reaching(): carry.complete_grasp()
	carry._carried_item = null; carry._carried_item_id = &""; carry._release_physics(m)
	cap.stow(m)
	cap.on_part(&"capture")
	await create_timer(cap.CAPTURE_S + 0.3).timeout
	m.interact()
	if carry.is_reaching(): carry.complete_grasp()
	env.pressure_kpa = 99.7
	env.o2_kpa = 19.9
	var sg: Node = main.get_node("SaveGame")
	sg.save_path = PATH
	await process_frame
	var expected: Dictionary = sg.collect_state()
	var r: Dictionary = sg.save_game()
	_check("save mid-task with the module in hand ('%s')" % r["message"], r["ok"])
	var lights_off: bool = main.get_node("Lights/Light_Engineering").light_energy == 0.0
	main.queue_free()
	await process_frame
	main = await _fresh()
	sg = main.get_node("SaveGame")
	sg.save_path = PATH
	var ar: Dictionary = sg.apply_state(sg.read_save()["data"])
	await process_frame
	_check("load ok ('%s')" % ar["message"], ar["ok"])
	var got: Dictionary = sg.collect_state()
	for k in expected["equipment2"]:
		var a = JSON.stringify(expected["equipment2"][k])
		var b = JSON.stringify(got["equipment2"].get(k))
		_check("%s state restored exactly (no re-roll)" % k, a == b)
	_check("Engineering lighting outage restored (breaker B-03 tripped, light off)", lights_off and main.get_node("Lights/Light_Engineering").light_energy == 0.0 and not main.get_node("Equipment/BreakerPanel").on[2])
	_check("environment restored (pressure %.1f, O2 %.1f)" % [main.get_node("EnvironmentModel").pressure_kpa, main.get_node("EnvironmentModel").o2_kpa], absf(main.get_node("EnvironmentModel").pressure_kpa - 99.7) < 0.05 and absf(main.get_node("EnvironmentModel").o2_kpa - 19.9) < 0.05)
	var dp2: Node = main.get_node("DayPlan")
	_check("concurrent orders restored (%d open)" % dp2.open_orders().size(), JSON.stringify(dp2.orders) == JSON.stringify(dp.orders) if is_instance_valid(dp) else dp2.open_orders().size() > 0)
	var carry2: Node = main.get_node("Player/CarrySystem")
	var held: Node = carry2._carried_item
	_check("the data module is back in the hand with its captured payload", held != null and held.item_id == &"data_module" and not held.payload.is_empty())
	var up2: Node = main.get_node("Equipment/UploadPort")
	_check("...and its data is still current (signature matches the restored station)", String(held.payload.get("sig", "")) == up2.signature())
	var count := 0
	for n in main.find_children("*", "", true, false):
		if "item_id" in n and n.item_id == &"data_module":
			count += 1
	_check("exactly one data module after loading", count == 1)
	for p in [PATH, PATH + ".bak", PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _fresh() -> Node:
	var m: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(m)
	current_scene = m
	for i in 6: await process_frame
	return m


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
