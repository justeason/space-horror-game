extends SceneTree
## Round 40 Priority 1-2: EVA clarity and the unified airlock module.
##  - REGRESSION (user report): a suited technician inside the station or
##    the chamber -- doorway gaps, the outer-hatch sill with the hatch
##    shut, far from the tether ring -- must never be put into the EVA
##    state or teleported to a tether point. Round 39 derived "outside"
##    from floor footprints every frame.
##  - The full state sequence station -> chamber -> (cycle) -> outside ->
##    chamber -> station, logged.
##  - Visible tube tether + carabiners, seen by an exterior camera.
##  - Staged re-clip (new cable out, click, both held, old released).
##  - Controls: SPACE pushes toward the crosshair, S brakes, C does nothing.
##  - Compact HUD + first-EVA hint; console lamps / short step text.
var _ok := true
var main: Node
var eva: Node
var al: Node
var fb: CharacterBody3D


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	eva = main.get_node("EvaSystem")
	al = main.get_node("AirlockChamber")
	fb = main.get_node("FreeMoveBody")
	eva.set_suited(true)
	await _no_false_outside()
	await _sequence()
	await _tether_visual_and_switch()
	await _controls_and_hud()
	_console()
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _no_false_outside() -> void:
	var pts: Array = []
	for m in main.get_node("MovementNodes").get_children():
		pts.append([String(m.name), (m as Node3D).global_position])
	pts.append(["Control<->Quarters doorway gap", Vector3(1.55, 1.6, 0.5)])
	pts.append(["chamber, outer-hatch sill (hatch SHUT)", Vector3(-4.8, 1.6, -2.62)])
	pts.append(["chamber, by the inner hatch", Vector3(-4.8, 1.6, -0.62)])
	pts.append(["Life Support (far from every ring)", Vector3(-2.8, 1.6, 11.0)])
	var bad: Array = []
	for p in pts:
		fb.sync_to_eye_position(p[1])
		for i in 5: await physics_frame
		var moved: float = fb.current_eye_position().distance_to(p[1])
		if eva.outside or fb.zero_g or moved > 0.4 or eva.eva_log.any(func(e): return e["event"] == "tether_return"):
			bad.append("%s (outside=%s moved %.2f)" % [p[0], eva.outside, moved])
	_check("suited, inside the station / chamber: never EVA state, never teleported (%d spots) %s" % [pts.size(), str(bad)], bad.is_empty())
	# The chamber in vacuum with the outer hatch OPEN: still inside until
	# the technician actually goes through the hatch.
	fb.sync_to_eye_position(Vector3(-4.8, 1.6, -1.4))
	for i in 4: await physics_frame
	al.inner_open = false
	al.psi = 0.0
	al.outer_open = true
	al.settle()
	for i in 6: await physics_frame
	_check("chamber open to space, standing inside: zone CHAMBER, gravity on", eva.zone == "chamber" and not eva.outside and not fb.zero_g)
	al.reset_default()


func _sequence() -> void:
	eva.eva_log.clear()
	fb.sync_to_eye_position(Vector3(-4.8, 1.6, 0.8))
	for i in 4: await physics_frame
	_check("zone STATION in the tunnel", eva.zone == "station")
	fb.sync_to_eye_position(Vector3(-4.8, 1.6, -1.45))
	for i in 4: await physics_frame
	_check("zone CHAMBER inside it (visor shows CHAMBER)", eva.zone == "chamber" and eva.zone_word().begins_with("CHAMBER"))
	al.begin_cycle_out()
	await _until(func(): return al.sequence == "", 10.0)
	fb.sync_to_eye_position(Vector3(-4.8, 1.6, -3.3))
	for i in 6: await physics_frame
	_check("through the OPEN outer hatch -> zone OUTSIDE (zero-g, tether A1)", eva.zone == "outside" and eva.outside and fb.zero_g and eva.anchor_index == 0)
	fb.sync_to_eye_position(Vector3(-4.8, 1.6, -1.6))
	for i in 6: await physics_frame
	_check("back into the chamber -> zone CHAMBER (gravity, unclipped)", eva.zone == "chamber" and not eva.outside and not fb.zero_g and eva.anchor_index == -1)
	al.begin_cycle_in()
	await _until(func(): return al.sequence == "", 10.0)
	fb.sync_to_eye_position(Vector3(-4.8, 1.6, 0.8))
	for i in 4: await physics_frame
	var zones: Array = eva.eva_log.filter(func(e): return String(e["event"]).begins_with("zone_")).map(func(e): return String(e["event"]).substr(5))
	_check("state sequence logged: %s" % str(zones), zones.slice(-4) == ["chamber", "outside", "chamber", "station"])


func _tether_visual_and_switch() -> void:
	fb.sync_to_eye_position(Vector3(-4.8, 1.6, -1.45))
	for i in 4: await physics_frame
	_check("OUT accepted from inside the chamber", al.begin_cycle_out())
	await _until(func(): return al.sequence == "", 10.0)
	fb.sync_to_eye_position(Vector3(-4.6, 1.6, -3.7))
	await create_timer(0.8).timeout
	var c0: Dictionary = eva._cables[0]
	var hook_suit: Vector3 = (c0["hook_a"] as Node3D).global_position
	var hook_ring: Vector3 = (c0["hook_b"] as Node3D).global_position
	_check("a solid cable (tube segments) from the suit harness to ring A1", (c0["root"] as Node3D).visible and hook_ring.distance_to(eva.ANCHORS[0][0]) < 0.02 and hook_suit.distance_to(eva._harness_point()) < 0.02)
	var seg: MeshInstance3D = c0["segs"][9]
	_check("cable is on the normal + exterior layers (every camera, mirror)", seg.layers & 1 != 0 and seg.layers & (1 << 11) != 0)
	var net: Node = main.get_node("CameraNetwork")
	var mid: Vector3 = seg.global_position
	_check("the exterior hatch camera EXT-02 sees the cable", net.sees("EXT-02", mid, 0.6))
	# Staged re-clip to A2 (move within reach first).
	fb.sync_to_eye_position(Vector3(-3.6, 1.7, -0.75))
	await create_timer(0.3).timeout
	_check("re-clip starts (staged, not instant)", eva.clip_to(1) and eva.is_switching() and eva.anchor_index == 0)
	await create_timer(0.25).timeout
	_check("...new cable reaching out, old still holding", (eva._cables[1]["root"] as Node3D).visible and eva.anchor_index == 0 and eva._clipped_rings() == [0])
	await create_timer(0.45).timeout
	_check("...clicked on: BOTH tethers held (two-tether rule)", eva._clipped_rings().size() == 2)
	await create_timer(0.9).timeout
	_check("...old released: clipped to A2 only, ONE cable (to A2)", not eva.is_switching() and eva.anchor_index == 1 and eva._clipped_rings() == [1] and not (eva._cables[1]["root"] as Node3D).visible and (eva._cables[0]["hook_b"] as Node3D).global_position.distance_to(eva.ANCHORS[1][0]) < 0.02)
	_check("re-clip events logged in order (start, clip, unclip)", _order(["clip_start_1", "clip_1", "unclip_0"]))
	_check("ring A2 lit green (active)", (eva._ring_mats[1] as StandardMaterial3D).albedo_color.g > 0.9 and (eva._ring_mats[0] as StandardMaterial3D).albedo_color.r > 0.9)
	_check("out-of-reach ring refused", not eva.clip_to(2) or eva._harness_point().distance_to(eva.ANCHORS[2][0]) <= eva.CLIP_REACH)


func _controls_and_hud() -> void:
	var cam: Camera3D = main.get_node("Player/LookPivot/PitchPivot/Camera3D")
	fb.velocity = Vector3.ZERO
	_key(KEY_SPACE, true)
	await create_timer(0.6).timeout
	_key(KEY_SPACE, false)
	var fwd: Vector3 = -cam.global_transform.basis.z
	_check("SPACE pushes toward the crosshair (v·forward %.2f)" % (fb.velocity.normalized().dot(fwd)), fb.velocity.length() > 0.2 and fb.velocity.normalized().dot(fwd) > 0.9)
	var v0: float = fb.velocity.length()
	await create_timer(0.5).timeout
	_check("released: you coast (%.2f -> %.2f m/s, no sudden stop)" % [v0, fb.velocity.length()], fb.velocity.length() > v0 * 0.6)
	_key(KEY_S, true)
	await create_timer(1.0).timeout
	_key(KEY_S, false)
	_check("S brakes to a stop (%.2f m/s)" % fb.velocity.length(), fb.velocity.length() < 0.05)
	_key(KEY_C, true)
	await create_timer(0.4).timeout
	_key(KEY_C, false)
	_check("C no longer moves you (it is the wristwatch key)", fb.velocity.length() < 0.05)
	_check("HUD: zone chip, tether ring + range bar, O2", eva._zone_chip.text in ["OUTSIDE", "RETURN"] and eva._teth_label.text == "A2" and eva._teth_bar.value > 0.0 and eva._o2_bar.value > 0.5)
	_check("first-EVA control hint was shown (key caps)", eva._hint_shown and eva._hint.get_child_count() == 4)


func _console() -> void:
	al.reset_default()
	al._refresh()
	_check("console: INNER lamp green (open), OUTER grey, CHAMBER green", (al._lamps["INNER"] as StandardMaterial3D).albedo_color.g > 0.9 and (al._lamps["OUTER"] as StandardMaterial3D).albedo_color.r < 0.3 and (al._lamps["CHAMBER"] as StandardMaterial3D).albedo_color.g > 0.9)
	var hs: Node = main.get_node("Equipment/HatchSeal")
	hs.test_state = "fail"
	al._refresh()
	_check("console: SEAL lamp shows the hatch-seal hold test (fail = red)", (al._lamps["SEAL"] as StandardMaterial3D).albedo_color.r > 0.9 and (al._lamps["SEAL"] as StandardMaterial3D).albedo_color.g < 0.4)
	hs.test_state = ""
	var seal_panel: Vector3 = hs.global_transform * hs.panel_offset
	var ch_panel: Vector3 = (al.get_node("Panel_chamber") as Node3D).global_position
	_check("chamber + seal panels on ONE console (same wall, same height, %.2f m apart)" % seal_panel.distance_to(ch_panel), absf(seal_panel.x - ch_panel.x) < 0.02 and absf(seal_panel.y - ch_panel.y) < 0.02 and seal_panel.distance_to(ch_panel) < 0.7)
	al._start("out", ["close_inner", "depressurize", "open_outer"])
	_check("short step text on the panel ('%s')" % al.step_text(), al.step_text() == "1/3 SEAL INNER")
	al.reset_default()
	var ai: Node = main.get_node("StationAI")
	_check("assistant has short first-time lines: airlock, EVA move, tether ring, re-clip, worksite", ai.LINES.has(&"airlock_intro") and ai.LINES.has(&"eva_outside") and ai.LINES.has(&"tether_intro") and ai.LINES.has(&"tether_switch") and ai.LINES.has(&"eva_repair") and String(ai.LINES[&"eva_outside"][1]).length() < 90)


func _order(keys: Array) -> bool:
	var ev: Array = eva.eva_log.map(func(e): return String(e["event"]))
	var last := -1
	for k in keys:
		var i: int = ev.find(k)
		if i <= last:
			return false
		last = i
	return true


func _until(cond: Callable, seconds: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		await physics_frame


func _key(k: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
