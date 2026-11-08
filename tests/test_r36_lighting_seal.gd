extends SceneTree
## Round 36 Priorities 4 and 6.
## LIGHTING: a tripped lighting breaker removes EVERY normal light of its
## room, overrides that room's ambient fill (zone ReflectionProbe) to a
## fraction, keeps a restrained red emergency light and the panel locator
## light; other rooms are untouched; restore returns the exact authored
## state; save/load during an outage. (Pixel brightness is measured in the
## rendered verification, not here -- the headless renderer draws nothing.)
## SEAL: every seal order has >= 1 real fault; faults are physical, visible
## hardware (debris / twisted clip / rolled lip) distinguishable by kind;
## inspection lamp; repair -> pressure test reflects condition; cargo
## interlock; no re-roll on reopen; save/load exact; variety over orders.
var _ok := true
var main: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 6: await process_frame
	_lighting()
	await _seal()
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _lighting() -> void:
	var br: Node = main.get_node("Equipment/BreakerPanel")
	var lights: Node = main.get_node("Lights")
	var authored := {}
	for l in lights.get_children():
		authored[l.name] = l.light_energy
	_check("normal: no outage override active anywhere", br._dark_probes.all(func(p): return not p.visible))
	br.trip(0, "surge")   # B-01 Quarters
	_check("Quarters out: main AND bunk lights off", lights.get_node("Light_Living").light_energy == 0.0 and lights.get_node("Light_LivingBed").light_energy == 0.0)
	_check("Quarters ambient overridden to %.3f (normal %.3f)" % [br.zone_ambient_energy(&"living_quarters"), br._env_ambient_energy], br._dark_probes[0].visible and br.zone_ambient_energy(&"living_quarters") < br._env_ambient_energy * 0.25)
	_check("restrained red emergency light on (%.2f)" % br._emergency[0].light_energy, br._emergency[0].light_energy > 0.0 and br._emergency[0].light_energy <= 0.5 and br._emergency[0].light_color.r > 0.9)
	_check("panel locator light on (breaker stays findable)", br._locator.light_energy > 0.0)
	var others_ok := true
	for n in ["Light_ControlRoom", "Light_Engineering", "Light_LifeSupport", "Light_Comms", "Light_Corridor"]:
		others_ok = others_ok and lights.get_node(n).light_energy == authored[n]
	_check("other rooms' lights untouched", others_ok and br.zone_ambient_energy(&"engineering") == br._env_ambient_energy)
	_check("outage volume covers only its room (quarters yes, control room no)", br.zone_at(Vector3(3.7, 1.2, 0.5)) == &"living_quarters" and br.zone_at(Vector3(0, 1.2, -0.5)) == &"")
	var sg: Node = main.get_node("SaveGame")
	sg.save_path = "user://test_r36_lighting.json"
	sg.save_game()
	br.on_part(&"b0")
	_check("restored: authored energies exactly, overrides off, emergency off", lights.get_node("Light_Living").light_energy == authored["Light_Living"] and lights.get_node("Light_LivingBed").light_energy == authored["Light_LivingBed"] and not br._dark_probes[0].visible and br._emergency[0].light_energy == 0.0 and br._locator.light_energy == 0.0)
	sg.apply_state(sg.read_save()["data"])
	_check("load during an outage: dark again (lights off, override on)", not br.on[0] and lights.get_node("Light_Living").light_energy == 0.0 and br._dark_probes[0].visible)
	br.on_part(&"b0")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_r36_lighting.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_r36_lighting.json.bak"))


func _seal() -> void:
	var hs: Node = main.get_node("Equipment/HatchSeal")
	var kinds := {}
	var all_have_fault := true
	for seed in range(1, 61):
		hs.faults = ["", "", "", ""]
		hs.order_rearm(seed * 7919)
		var n: int = hs.faults.filter(func(f): return f != "").size()
		all_have_fault = all_have_fault and n >= 1
		for f in hs.faults:
			if f != "":
				kinds[f] = true
	_check("60 generated seal orders all have >= 1 real fault", all_have_fault)
	_check("all three fault kinds occur (%s)" % str(kinds.keys()), kinds.size() == 3)
	hs.faults = ["debris", "clip", "", "rolled"]
	hs.inspected = [false, false, false, false]
	hs._refresh()
	_check("faults are physical hardware, visible BEFORE inspection", hs._hw[0]["debris"].visible and hs._hw[1]["clip_gap"].visible and hs._hw[3]["rolled"].visible)
	_check("healthy section shows none of it", not hs._hw[2]["debris"].visible and not hs._hw[2]["rolled"].visible and not hs._hw[2]["clip_gap"].visible)
	_check("twisted clip is visibly out of line (%.0f deg)" % hs._hw[1]["brackets"][0].rotation_degrees.z, absf(hs._hw[1]["brackets"][0].rotation_degrees.z) > 30.0 and hs._hw[2]["brackets"][0].rotation_degrees.z == 0.0)
	_check("kinds are distinguishable (only the matching hardware shows)", not hs._hw[0]["rolled"].visible and not hs._hw[3]["debris"].visible and not hs._hw[0]["clip_gap"].visible)
	# Interactable through the real ray: the faulty section is a target.
	var cam: Node = main.get_node("Player/LookPivot/PitchPivot/Camera3D")
	var fb: Node = main.get_node("FreeMoveBody")
	var player: Node3D = main.get_node("Player")
	var lp: Node3D = player.get_node("LookPivot")
	var tgt: Vector3 = hs.global_transform * Vector3(0.37, -0.2, 0.08)
	var eye: Vector3 = hs.global_transform * Vector3(0.0, 0.25, 0.75)
	fb.sync_to_eye_position(eye)
	player.global_position = eye
	for i in 4: await physics_frame
	var d: Vector3 = tgt - cam.global_position
	lp.rotation.y = atan2(-d.x, -d.z) - player.rotation.y
	lp._target_yaw = lp.rotation.y
	lp.get_node("PitchPivot").rotation.x = atan2(d.y, Vector2(d.x, d.z).length())
	lp._target_pitch = lp.get_node("PitchPivot").rotation.x
	for i in 3: await physics_frame
	await process_frame
	_check("standing in the tunnel, the RIGHT section is targetable", cam.get_hovered() != null and cam.get_hovered().name == "Click_s1")
	# Test fails while faulty.
	hs.on_part(&"test")
	await create_timer(3.3).timeout
	_check("pressure test FAILS with faults (%s)" % hs.test_state, hs.test_state == "fail")
	hs.on_part(&"mode")
	_check("inspection lamp on in INSPECT mode", hs._inspect_light.light_energy > 0.0)
	# Cargo interlock both ways.
	var port: Node = main.get_node("Interactables/CargoPort")
	port.state = port.PortState.ARRIVED
	port.interact()
	_check("cargo port refuses while the hatch is in INSPECT mode", port.state == port.PortState.ARRIVED)
	port.state = port.PortState.SECURED
	hs.on_part(&"s0")
	hs.on_part(&"s1")
	var sg: Node = main.get_node("SaveGame")
	sg.save_path = "user://test_r36_seal.json"
	sg.save_game()
	var want: Dictionary = hs.state_dict()
	hs.faults = ["", "", "", ""]
	sg.apply_state(sg.read_save()["data"])
	_check("load: exact fault state + inspection progress (%s)" % str(hs.faults), hs.faults == want["faults"] and hs.inspected == want["inspected"] and hs.inspection_mode)
	_check("no re-roll: same faults after reload", hs.faults == ["debris", "clip", "", "rolled"])
	for i in 4:
		hs.on_part(StringName("s%d" % i))
		hs.on_part(StringName("s%d" % i))
	_check("all faults corrected; hardware back in line", hs.leak_kpa() == 0.0 and not hs._hw[0]["debris"].visible and hs._hw[1]["brackets"][0].rotation_degrees.z == 0.0 and not hs._hw[3]["rolled"].visible)
	hs.on_part(&"mode")
	_check("inspection lamp off when secured", hs._inspect_light.light_energy == 0.0)
	hs.on_part(&"test")
	await create_timer(3.3).timeout
	_check("pressure test PASSES once repaired", hs.test_state == "pass")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_r36_seal.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_r36_seal.json.bak"))


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
