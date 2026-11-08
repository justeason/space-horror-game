extends SceneTree
## Round 39 Priority 6: the REAL two-hatch airlock + tethered zero-g EVA
## (replaces Round 38's test_r38_eva teleport flow). Real W-key movement
## through the inner hatch, the chamber, the open outer hatch and out to
## antenna A1; every sequence step is checked against the hatch / pressure
## safety invariant on EVERY physics frame. Also: the visible EVA suit,
## interlocks (suit, unsuited person, blocked doorway, cargo, seal), the
## tether limit and re-clipping, never-locked-out, the antenna chain,
## save refusal, save/load.
var _ok := true
var main: Node
var eva: Node
var al: Node
var ant: Node
var dp: Node
var fb: CharacterBody3D
var _unsafe_frames := 0


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	eva = main.get_node("EvaSystem")
	al = main.get_node("AirlockChamber")
	ant = main.get_node("Equipment/AntennaMast")
	dp = main.get_node("DayPlan")
	fb = main.get_node("FreeMoveBody")
	var sg: Node = main.get_node("SaveGame")
	var body: Node = main.get_node("Player/PlayerBody")
	physics_frame.connect(func(): if not al.is_safe_state(): _unsafe_frames += 1)
	# --- Default state ---
	_check("default: chamber pressurized (%.1f psi), inner hatch open, outer shut" % al.psi, al.is_default_state() and absf(al.psi - 14.7) < 0.01)
	# Antenna order (the exterior task).
	dp._order_seq += 1
	dp.orders.append({"id": "WO-T%d" % dp._order_seq, "type": "antenna", "category": "D", "priority": 2, "day": dp.day_number, "seed": 1, "status": "open", "carried_from": -1})
	ant.order_rearm(1)
	ant.on_part(&"test")
	_check("chain: suit up first", ant.order_next()["short"] == "SUIT UP")
	# --- Into the chamber unsuited: EXIT refused ---
	fb.sync_to_eye_position(Vector3(-4.8, 1.6, 0.6))
	await _walk([Vector3(-4.8, 0, -1.45)])
	_check("walked through the open inner hatch into the chamber", al.in_chamber(fb.global_position))
	_check("EXIT refused without the suit ('%s')" % al.exit_blocker(), not al.begin_cycle_out() and al.inner_open)
	# --- Suit ---
	await _walk([Vector3(-4.8, 0, 0.9)])
	eva.on_part(&"locker")
	for i in 3: await process_frame
	_check("suit on: the body wears the EVA suit (rig suit + helmet mesh, mirror/camera-only helmet)", eva.suited and body.eva_suit and body._rig.suit_on and body._rig._suit_helmet.visible and body._rig._suit_helmet.layers == 4)
	_check("visor frame + suit status (4.3 psi O2) in view", eva._visor.visible and eva._visor_label.text.find("4.3 psi O2") != -1)
	_check("chain: airlock EXIT", ant.order_next()["short"] == "AIRLOCK EXIT")
	_check("EXIT refused from outside the chamber ('%s')" % al.exit_blocker(), al.exit_blocker() != "" and not al.begin_cycle_out())
	# --- Interlocks inside the chamber ---
	await _walk([Vector3(-4.8, 0, -1.45)])
	var port: Node = main.get_node("Interactables/CargoPort")
	port.state = port.PortState.ARRIVED
	_check("cargo transfer in progress blocks EXIT", not al.begin_cycle_out())
	port.state = port.PortState.SECURED
	var hs: Node = main.get_node("Equipment/HatchSeal")
	hs.inspection_mode = true
	_check("seal inspection blocks EXIT", not al.begin_cycle_out())
	hs.inspection_mode = false
	# Blocked doorway: standing in the inner hatch's swing.
	await _walk([Vector3(-4.8, 0, -0.62)])
	_check("EXIT from the doorway edge accepted", al.begin_cycle_out())
	await create_timer(0.5).timeout
	_check("inner hatch will not close on the technician ('%s')" % al.waiting, al.waiting.find("Clear") != -1 and al.step == "close_inner")
	await _walk([Vector3(-4.8, 0, -1.5)])
	# --- The EXIT sequence, step by step ---
	await _until(func(): return not al.inner_open and al._inner_k <= 0.001, 4.0)
	_check("step 1: inner hatch closed", not al.inner_open)
	_check("saving refused while cycling ('%s')" % sg.save_blocker(), sg.save_blocker() != "")
	await create_timer(1.5).timeout
	_check("step 2: depressurizing (%.1f psi, falling)" % al.psi, al.step == "depressurize" and al.psi < 14.0 and al.psi > 0.2)
	_check("chamber light amber while cycling", al._light.light_color.r > 0.9 and al._light.light_color.g > 0.5)
	await _until(func(): return al.sequence == "", 8.0)
	_check("step 3: vacuum (%.1f psi) and outer hatch OPEN; inner still shut" % al.psi, al.is_vacuum() and al.outer_open and not al.inner_open)
	_check("vacuum in the chamber: ambience muffled", eva._lowpass_added)
	# --- Out through the open outer hatch ---
	await _walk([Vector3(-4.8, 0, -3.25)])
	await create_timer(0.2).timeout
	_check("outside: EVA active, ZERO-G (no gravity), body floating", eva.outside and fb.zero_g and body.floating)
	_check("tether auto-clipped to ring A1, visible cable", eva.anchor_index == 0 and (eva._tether_mesh.mesh as ImmediateMesh).get_surface_count() > 0)
	var y0: float = fb.global_position.y
	await create_timer(1.0).timeout
	_check("no gravity: no fall in 1 s (%.2f -> %.2f)" % [y0, fb.global_position.y], absf(fb.global_position.y - y0) < 0.1)
	_check("saving refused outside", sg.save_blocker() != "")
	_check("cargo port refuses to operate during EVA", _cargo_refuses(port))
	_check("chain: fix the feed box", ant.order_next()["short"] == "FIX FEED A1")
	# Float to the walkway ring A2 and re-clip.
	# (Clear the open outer hatch leaf -- it swings out to z ~ -3.3.)
	await _walk([Vector3(-4.8, 0.05, -3.75), Vector3(-3.75, 0.05, -3.75), Vector3(-3.75, 0.05, -0.6)])
	_check("re-clip tether to ring A2 within reach", eva.clip_to(1) and eva.anchor_index == 1)
	# Tether limit: try to drift far away.
	await _walk([Vector3(1.5, 0.05, -4.0)], 4000)
	_check("tether holds: %.2f m <= %.1f m from the ring" % [eva.tether_length, eva.TETHER_LEN], eva.tether_length <= eva.TETHER_LEN + 0.25)
	# To the antenna feed box and repair it through the real ray.
	await _walk([Vector3(-3.75, 0.05, -0.6), Vector3(-3.45, 0.05, 0.75)])
	_check("reached the antenna (%s)" % str(fb.global_position.snapped(Vector3(0.1, 0.1, 0.1))), fb.global_position.distance_to(Vector3(-3.45, fb.global_position.y, 0.75)) < 0.6)
	var cam: Camera3D = main.get_node("Player/LookPivot/PitchPivot/Camera3D")
	for id in ["cover", "connector", "connector", "cover"]:
		var target: Node3D = ant.find_child("Click_%s" % id, true, false)
		await _look(cam, target.global_position)
		var h: Object = cam.get_hovered()
		if h != null:
			h.interact()
		await process_frame
		if ant.feed == "ok" and id == "connector":
			break
	if ant.cover_open:
		var cv: Node3D = ant.find_child("Click_cover", true, false)
		await _look(cam, cv.global_position)
		if cam.get_hovered() != null:
			cam.get_hovered().interact()
	_check("feed A1 repaired outside (link %d %%)" % roundi(ant.link_quality() * 100), ant.feed_ok() and ant.link_quality() >= 0.99)
	_check("chain: back to the airlock (ENTER)", ant.order_next()["short"] == "AIRLOCK ENTER")
	# --- Back into the chamber and ENTER ---
	if fb.global_position.distance_to(eva.ANCHORS[1][0]) < 1.8:
		eva.clip_to(1)
	await _walk([Vector3(-3.75, 0.05, -0.6), Vector3(-3.75, 0.05, -3.75), Vector3(-4.8, 0.05, -3.75), Vector3(-4.8, 0.05, -1.5)])
	await create_timer(0.6).timeout
	_check("back inside the chamber: gravity again, tether unclipped", not eva.outside and not fb.zero_g and eva.anchor_index == -1 and al.in_chamber(fb.global_position))
	al.on_part(&"enter")
	_check("ENTER starts", al.sequence == "in")
	await _until(func(): return al.sequence == "", 10.0)
	_check("ENTER done: outer shut, %.1f psi, inner hatch open" % al.psi, not al.outer_open and al.is_pressurized() and al.inner_open)
	_check("chain: verify the link in Comms", ant.order_next()["short"] == "VERIFY LINK")
	ant.on_part(&"test")
	for i in 3: await process_frame
	_check("antenna order verified and closed", ant.order_done())
	# Dynamic dependency (kept from the replaced Round 38 EVA test): no
	# Comms power -> no link, even with a healthy antenna.
	var br: Node = main.get_node("Equipment/BreakerPanel")
	br.trip(3, "surge")
	_check("Comms breaker B-04 off -> link 0 %", ant.link_quality() == 0.0)
	br.on_part(&"b3")
	_check("B-04 reset -> link back to %d %%" % roundi(ant.link_quality() * 100), ant.link_quality() >= 0.99)
	# --- Unsuited person in the chamber during venting: abort, safe ---
	await _walk([Vector3(-4.8, 0, -1.5)])
	al.begin_cycle_out()
	await _until(func(): return al.step == "depressurize", 3.0)
	eva.suited = false                       # suit removed mid-cycle (forced)
	await create_timer(0.3).timeout
	_check("unsuited person in the chamber: venting aborted (%.1f psi)" % al.psi, al.sequence == "" and al.events.any(func(e): return e["event"] == "abort") and not al.outer_open)
	eva.set_suited(true)
	al.begin_cycle_in()
	await _until(func(): return al.sequence == "", 10.0)
	_check("recovered to the default state", al.is_default_state())
	# --- Never locked out: outside panel works even if the inner hatch was left open ---
	al.inner_open = true
	al.outer_open = false
	al.psi = 14.7
	al.settle()
	_check("outside panel: opens the outer hatch (closing inner + venting first)", al.begin_open_from_outside())
	await _until(func(): return al.sequence == "", 10.0)
	_check("...outer open, inner shut, vacuum", al.outer_open and not al.inner_open and al.is_vacuum())
	al.begin_cycle_in()
	await _until(func(): return al.sequence == "", 10.0)
	_check("NO frame ever had both hatches open or a hatch open at the wrong pressure (%d unsafe frames)" % _unsafe_frames, _unsafe_frames == 0)
	# --- Save / load ---
	await _walk([Vector3(-4.8, 0, 0.6)])
	sg.save_path = "user://test_r39_airlock.json"
	var r: Dictionary = sg.save_game()
	_check("save inside, chamber at rest, suit on: %s" % r["message"], r["ok"])
	eva.set_suited(false)
	if r["ok"]:
		sg.apply_state(sg.read_save()["data"])
	_check("load restores the suit (and its look) and a default airlock", eva.suited and body.eva_suit and al.is_default_state())
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_r39_airlock.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_r39_airlock.json.bak"))
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _cargo_refuses(port: Node) -> bool:
	port.state = port.PortState.ARRIVED
	port.interact()
	var ok: bool = port.state == port.PortState.ARRIVED
	port.state = port.PortState.SECURED
	return ok


func _until(cond: Callable, seconds: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		await physics_frame


## Real movement: face the waypoint (pitch too, for zero-g) and hold W.
func _walk(pts: Array, max_ms: int = 9000) -> void:
	var player: Node3D = main.get_node("Player")
	var lp: Node3D = player.get_node("LookPivot")
	for p in pts:
		var t0 := Time.get_ticks_msec()
		_key(KEY_W, true)
		while Time.get_ticks_msec() - t0 < max_ms:
			var d: Vector3 = p - fb.global_position
			if not fb.zero_g:
				d.y = 0.0
			if d.length() < 0.15:
				break
			lp.rotation.y = atan2(-d.x, -d.z) - player.rotation.y
			lp._target_yaw = lp.rotation.y
			var pitch: float = atan2(d.y, Vector2(d.x, d.z).length()) if fb.zero_g else 0.0
			lp.get_node("PitchPivot").rotation.x = pitch
			lp._target_pitch = pitch
			if fb.zero_g and d.length() < 0.6 and fb.velocity.length() > 0.5:
				_key(KEY_W, false)
			elif fb.zero_g:
				_key(KEY_W, true)
			await physics_frame
		_key(KEY_W, false)
		if fb.zero_g:
			fb.velocity = Vector3.ZERO     # a test-only full stop at each waypoint
		for i in 10: await physics_frame


func _key(k: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)


func _look(cam: Camera3D, target: Vector3) -> void:
	var player: Node3D = main.get_node("Player")
	var lp: Node3D = player.get_node("LookPivot")
	var d: Vector3 = target - cam.global_position
	lp.rotation.y = atan2(-d.x, -d.z) - player.rotation.y
	lp._target_yaw = lp.rotation.y
	lp.get_node("PitchPivot").rotation.x = atan2(d.y, Vector2(d.x, d.z).length())
	lp._target_pitch = lp.get_node("PitchPivot").rotation.x
	for i in 3: await physics_frame
	await process_frame


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
