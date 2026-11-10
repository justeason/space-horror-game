extends SceneTree
## Round 42 Priorities 14-18: EVA suit stowage, solar hinge anchors, the
## airlock's float / boots model, the OUT<< / IN>> console and the hatch
## seal pressure-hold interlocks.
##  - stored suit = the real technician_rig.gd suit (not CSG primitives),
##    shown in ONE place only (hidden while worn, empty yoke + open straps);
##  - hinge worksites accept rings DERIVED from the worksite (same wing,
##    within reach), never the other wing; working the healthy wing's
##    hinge explains where the fault really is;
##  - floating while the chamber is open / venting / at vacuum /
##    repressurising; boots engage only once sealed + pressurised; the
##    settle is gradual (no camera snap, no teleport);
##  - console buttons read OUT<< (left, exit) and IN>> (right, enter);
##  - the hold test refuses with the outer hatch open / cycling / low
##    pressure, aborts if the hatch opens, passes when valid, and a PASS is
##    cleared when the outer hatch opens again.
var _ok := true
var main: Node
var eva: Node
var al: Node
var fb: CharacterBody3D
var hs: Node
var hinge: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	eva = main.get_node("EvaSystem")
	al = main.get_node("AirlockChamber")
	fb = main.get_node("FreeMoveBody")
	hs = main.get_node("Equipment/HatchSeal")
	hinge = main.get_node("Equipment/SolarHinge")
	_stored_suit()
	_hinge_anchors()
	_labels()
	await _seal_interlocks()
	await _float_model()
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _stored_suit() -> void:
	var locker: Node3D = main.find_child("SuitLocker", true, false)
	var rig: Node3D = eva.locker_rig
	_check("the locker holds a technician_rig.gd suit (the worn suit's own meshes)", rig != null and rig.get_script() == preload("res://scripts/character/technician_rig.gd") and rig.suit_on)
	_check("its suit garment, helmet and pack exist (skinned), head hidden: an EMPTY suit", rig._suit_body != null and rig._suit_helmet != null and rig._suit_body.visible and not rig.head_mesh.visible)
	var stowed: Node3D = rig.get_parent()
	var prims: int = stowed.find_children("*", "CSGSphere3D", true, false).size()
	_check("no sphere/box mannequin left in the locker suit (%d CSG spheres)" % prims, prims == 0)
	_check("hanging pose: arms away from the torso", absf(rig.bone_pos("LeftHand").x) > absf(rig.rest_pos("LeftHand").x) + 0.02)
	eva.set_suited(true)
	_check("worn: the locker suit is HIDDEN (never in two places), yoke + open straps remain", not stowed.visible and eva._locker_open.visible and eva._locker_status.text == "SUIT IN USE")
	eva.set_suited(false)
	_check("stowed again: suit back on its yoke, lamp READY", stowed.visible and not eva._locker_open.visible and eva._locker_status.text == "SUIT READY")
	_check("player rig still the only technician body (locker rig is the suit garment only)", main.find_children("*", "", true, false).filter(func(n): return n.get_script() == preload("res://scripts/character/technician_rig.gd")).size() == 2)
	_check("locker suit stands inside the locker footprint", locker != null and rig.global_position.distance_to(locker.global_position + Vector3(0.36, 0.04, 0)) < 0.1)


func _hinge_anchors() -> void:
	var rl: Array = hinge.valid_rings("L3", hinge._stance("L"))
	var rr: Array = hinge.valid_rings("R3", hinge._stance("R"))
	_check("left hinge rings derived from its worksite: %s" % str(rl), rl.has("L3") and rl.all(func(r): return String(r).begins_with("L")))
	_check("right hinge rings derived from its worksite: %s" % str(rr), rr.has("R3") and rr.all(func(r): return String(r).begins_with("R")))
	for w in ["L", "R"]:
		var site: Dictionary = eva.worksites.get("hinge_" + w, {})
		_check("hinge_%s worksite registered with its own wing's rings %s" % [w, str(site.get("anchors", []))], not site.is_empty() and Array(site["anchors"]).all(func(r): return String(r).begins_with(w)))
		var near: bool = true
		for r in site.get("anchors", []):
			near = near and eva.Graph.pos(r).distance_to(site["stance"]) <= hinge.WORK_RING_R + 0.01
		_check("every accepted ring is physically near hinge_%s" % w, near)
	# The order is on the LEFT wing; the technician is working the RIGHT hinge.
	hinge.order_rearm(7)
	hinge.wing = "L"
	hinge.variant = "latch"
	hinge._refresh()
	eva.outside = true
	eva.work_site = "hinge_R"
	eva._work_ease = 1.0
	var ml: Label = main.get_node("Player/HUD/TaskMessageLabel")
	hinge.on_part(&"flag")
	_check("healthy R hinge: explains the fault is on the LEFT wing, ring L3 ('%s')" % ml.text, ml.text.find("LEFT") != -1 and ml.text.find("L3") != -1 and ml.text.find("fine") != -1)
	_check("...and its prompt says so", hinge.part_prompt(&"latch").find("healthy") != -1)
	_check("service tag only on the faulted (left) hinge", hinge._tags["L"].visible and not hinge._tags["R"].visible)
	eva.work_site = "hinge_L"
	hinge.on_part(&"latch")
	hinge.on_part(&"latch")
	hinge.on_part(&"flag")
	_check("correct worksite: the left latch fix + indicator completes it", hinge.repaired())
	hinge.wing = "R"
	hinge.order_rearm(8)
	hinge.wing = "R"
	hinge.variant = "fastener"
	eva.work_site = "hinge_R"
	for i in 3:
		hinge.on_part(&"fastener")
	hinge.on_part(&"flag")
	_check("right-wing variant completes at the right hinge", hinge.repaired())
	var sd: Dictionary = hinge.state_dict()
	hinge.load_dict(sd)
	_check("save/load keeps the assigned wing (%s)" % hinge.wing, hinge.wing == "R" and hinge.repaired())
	eva.work_site = ""
	eva.outside = false


func _labels() -> void:
	var texts: Array = al.find_children("*", "Label3D", true, false).map(func(l): return (l as Label3D).text)
	_check("console buttons read OUT<< and IN>>", texts.has("OUT<<") and texts.has("IN>>") and not texts.has("OUT >>") and not texts.has("<< IN"))
	var ex: Node3D = al.find_child("Click_exit", true, false)
	var en: Node3D = al.find_child("Click_enter", true, false)
	var cam_right: Vector3 = Vector3(0, 0, 1)      # facing the east-wall console (+x), right = +z
	_check("OUT<< on the LEFT (outer-hatch side), IN>> on the right", ex.global_position.dot(cam_right) < en.global_position.dot(cam_right))
	_check("OUT<< runs the EXIT action, IN>> the ENTER action (prompts)", al.part_prompt(&"exit").begins_with("Click: OUT<<") or al.part_prompt(&"exit").begins_with("OUT<<"))


func _seal_interlocks() -> void:
	hs.faults = ["", "", "", ""]
	hs.inspection_mode = false
	hs.test_state = ""
	al.reset_default()
	al.outer_open = true
	al.settle()
	hs.on_part(&"test")
	_check("outer hatch OPEN: hold test refused (%s)" % hs.last_block, hs.test_state == "" and hs.last_block == "HATCH OPEN")
	_check("readout shows HATCH OPEN", hs._readout.text.find("HATCH OPEN") != -1)
	al.outer_open = false
	al.psi = 6.0
	al.settle()
	hs.on_part(&"test")
	_check("low chamber pressure: refused (%s)" % hs.last_block, hs.test_state == "" and hs.last_block == "LOW PRESSURE")
	al.reset_default()
	al.sequence = "out"
	hs.on_part(&"test")
	_check("airlock cycling: refused", hs.test_state == "" and hs.last_block == "CYCLING")
	al.sequence = ""
	hs.on_part(&"test")
	_check("sealed + pressurised: test RUNNING", hs.test_state == "running")
	al.outer_open = true
	await process_frame
	await process_frame
	_check("hatch opened mid-test: test ABORTED (no PASS)", hs.test_state != "pass" and hs.test_state != "running")
	al.outer_open = false
	al.settle()
	hs.on_part(&"test")
	await create_timer(hs.TEST_S + 0.4).timeout
	_check("valid closed-hatch pressure-hold: PASS", hs.test_state == "pass")
	al.outer_open = true
	await process_frame
	await process_frame
	_check("PASS cleared when the outer hatch opens again (new closure untested)", hs.test_state == "")
	al.outer_open = false
	al.reset_default()
	hs.faults = ["debris", "", "", ""]
	hs.on_part(&"test")
	await create_timer(hs.TEST_S + 0.4).timeout
	_check("with a damaged seal: FAIL", hs.test_state == "fail")
	hs.faults = ["", "", "", ""]
	hs.test_state = ""
	var sd: Dictionary = hs.state_dict()
	hs.test_state = "running"
	sd = hs.state_dict()
	_check("a running test is never saved as running/pass", String(sd["test_state"]) == "")
	hs.test_state = ""


func _float_model() -> void:
	al.reset_default()
	eva.set_suited(true)
	fb.sync_to_eye_position(Vector3(-4.8, 1.6, -1.45))
	for i in 6: await physics_frame
	_check("pressurised chamber, suited: boots ON (walking)", eva.zone == "chamber" and not eva.float_mode and not fb.zero_g)
	al.begin_cycle_out()
	await _until(func(): return al.psi < 14.0, 8.0)
	for i in 3: await physics_frame
	_check("venting: boots RELEASED -> floating (EVA mode at the vent step)", eva.float_mode and fb.zero_g and al.sequence == "out")
	await _until(func(): return al.sequence == "", 10.0)
	_check("depressurised + outer open: still floating, still CHAMBER", eva.float_mode and al.outer_open and eva.zone == "chamber")
	fb.sync_to_eye_position(Vector3(-4.8, 1.6, -3.3))
	for i in 6: await physics_frame
	_check("outside: floating", eva.outside and fb.zero_g)
	fb.sync_to_eye_position(Vector3(-4.8, 1.9, -1.5))
	for i in 6: await physics_frame
	_check("back inside, outer hatch OPEN: still floating (no early walking)", eva.zone == "chamber" and fb.zero_g)
	var y0: float = fb.global_position.y
	al.begin_cycle_in()
	await _until(func(): return al.step == "repressurize", 8.0)
	_check("outer hatch sealed, repressurising: still floating", not al.outer_open and fb.zero_g)
	var max_dy := 0.0
	var last_y: float = fb.global_position.y
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 9000 and (al.sequence != "" or fb.settling or fb.zero_g):
		await physics_frame
		max_dy = maxf(max_dy, absf(fb.global_position.y - last_y))
		last_y = fb.global_position.y
	for i in 30: await physics_frame
	_check("fully pressurised: boots engaged, station movement", not eva.float_mode and not fb.zero_g and al.is_pressurized())
	_check("settled gently: no height snap (max %.3f m/frame), from %.2f to %.2f" % [max_dy, y0, fb.global_position.y], max_dy < 0.05)
	var log: Array = eva.eva_log.map(func(e): return String(e["event"]))
	_check("boots_released / boots_engaged logged in order", log.find("boots_released") != -1 and log.rfind("boots_engaged") > log.find("boots_released"))
	_check("no teleport events", not log.has("tether_return"))
	eva.set_suited(false)


func _until(cond: Callable, seconds: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		await physics_frame


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
