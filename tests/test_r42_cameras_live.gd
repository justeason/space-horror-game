extends SceneTree
## Round 42 Priorities 6-10: surveillance.
##  - INT-02 relocated to the Life Support approach (bend ceiling), looking
##    down the Junction and corridor to the Control Room seat -- real
##    sightlines (physics rays), a mount arm up to the ceiling;
##  - STALE FEED BUG: the monitor's Cameras page stopped rendering the
##    moment the technician stood up, freezing a frame with them SEATED.
##    Now a displayed feed renders whenever the monitor can be seen (Control
##    Room / corridor / Junction A), stops when nobody can see it, and
##    renders again (fresh frames) on return;
##  - no duplicate technician models; the player's own body is what the
##    camera sees (seated -> at the seat; standing -> wherever they are);
##  - resolution: 1280x720 for the inspected (seated) feed, 640x360
##    otherwise, only demanded feeds render; the monitor UI renders at 2x;
##    INSPECT mode gives the feed the whole monitor and leans the view in;
##  - EXT-01 retired from every list (stable ids not renumbered).
var _ok := true
var main: Node
var net: Node
var ws: Node
var shell: Node
var screen: SubViewport
var fb: Node
var pc: Camera3D


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	net = main.get_node("CameraNetwork")
	ws = main.get_node("WorkstationState")
	shell = main.get_node("Interactables/WorkstationConsole/WorkstationScreen/Shell")
	screen = main.get_node("Interactables/WorkstationConsole/WorkstationScreen")
	fb = main.get_node("FreeMoveBody")
	pc = main.get_node("Player/LookPivot/PitchPivot/Camera3D")
	_placement()
	_inventory()
	await _stale_feed()
	await _inspect()
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _placement() -> void:
	var cam: Camera3D = net.camera("INT-02")
	var p: Vector3 = cam.global_position
	var fwd: Vector3 = -cam.global_basis.z
	# Round 46: remounted on the Junction side of the Life Support doorway
	# header, looking north into the Junction (test_r46_horror: sightlines).
	_check("INT-02 on the Life Support doorway header (%.2f, %.2f, %.2f), under the ceiling" % [p.x, p.y, p.z], p.z > 6.9 and p.z < 7.4 and p.x > -0.9 and p.x < -0.2 and p.y < 2.6 and p.y > 2.2)
	_check("faces north into the Junction (forward z %.2f)" % fwd.z, fwd.z < -0.7)
	_check("sightline: Junction A, corridor, doorway and the seat (physics rays)", net.sees("INT-02", Vector3(-0.2, 1.2, 4.9)) and net.sees("INT-02", Vector3(0, 1.2, 2.9)) and net.sees("INT-02", Vector3(0, 1.2, 2.1)) and net.sees("INT-02", Vector3(0, 1.15, -0.45), 0.4))
	_check("does NOT look through walls: the Engineering side room is out of sight", not net.sees("INT-02", Vector3(-4.2, 1.2, 5.0)))
	var arm: CSGBox3D = null
	for n in cam.find_children("*", "CSGBox3D", true, false):
		if (n as CSGBox3D).size.y > 0.2:
			arm = n
	_check("physical housing with a drop arm reaching the ceiling", arm != null and arm.global_position.y + arm.size.y * 0.5 > 2.55)
	_check("blind spot documented (%s)" % net.info("INT-02")["blind"], String(net.info("INT-02")["blind"]).length() > 10)


func _inventory() -> void:
	var ids: Array = net.ids()
	_check("EXT-01 retired: not built, not listed (%s)" % ", ".join(ids), not ids.has("EXT-01") and net.RETIRED.has("EXT-01") and main.find_child("CamExtHull", true, false) == null)
	_check("remaining ids keep their numbers (EXT-02/03/05 still there)", ids.has("EXT-02") and ids.has("EXT-03") and ids.has("EXT-05"))
	shell.show_page(shell.Page.CAMERAS)
	_check("no EXT-01 button on the Cameras page", not shell.cam_buttons.has("EXT-01"))
	var rigs: Array = main.find_children("*", "", true, false).filter(func(n): return n.get_script() == preload("res://scripts/character/technician_rig.gd"))
	_check("exactly one technician body + the stowed suit garment (%d rigs), no seated proxy" % rigs.size(), rigs.size() == 2)
	var legacy_ok := true
	for vp in main.get_node("Surveillance").get_children():
		if vp is SubViewport and not net._is_network_vp(vp):
			legacy_ok = legacy_ok and (vp as SubViewport).render_target_update_mode == SubViewport.UPDATE_DISABLED
	_check("legacy cameras outside the network no longer render every frame", legacy_ok)
	_check("monitor UI renders at 2x (1280x800 for a 640x400 layout)", screen.size == Vector2i(1280, 800) and screen.size_2d_override == Vector2i(640, 400))


func _stale_feed() -> void:
	ws.begin_use()
	await _until(func(): return ws.is_in_use(), 5.0)
	shell.show_page(shell.Page.CAMERAS)
	shell.select_camera("INT-02")
	await create_timer(0.4).timeout
	_check("seated on the Cameras page: INT-02 LIVE at HI %s" % str(net.feed_size("INT-02")), net.is_rendering("INT-02") and net.feed_size("INT-02") == net.FEED_HI)
	var rig: Node3D = main.get_node("Player/PlayerBody").rigged_visual()
	_check("the seated body is at the seat, in front of INT-02's sightline", rig.global_position.distance_to(Vector3(0, 0, -0.45)) < 0.9 and net.sees("INT-02", Vector3(0, 1.15, -0.45), 0.4))
	var only: bool = net.ids().filter(func(i): return net.is_rendering(i)).size() == 1
	_check("only the shown feed renders", only)
	ws.end_use()
	await _until(func(): return not ws._transitioning and not ws.is_in_use(), 5.0)
	var f0: int = int(net.frames.get("INT-02", 0))
	await create_timer(0.6).timeout
	_check("STANDING in the Control Room: the monitor feed is still LIVE (frames %d -> %d) at LO" % [f0, int(net.frames["INT-02"])], net.is_rendering("INT-02") and int(net.frames["INT-02"]) > f0 and net.feed_size("INT-02") == net.FEED_LO)
	_check("standing: the body left the seat", rig.global_position.distance_to(Vector3(0, 0, -0.45)) > 0.3)
	fb.sync_to_eye_position(Vector3(0.0, 1.6, 2.8))
	await create_timer(0.6).timeout
	_check("in the corridor (monitor still visible through the doorway): still live", net.is_rendering("INT-02"))
	fb.sync_to_eye_position(Vector3(-2.9, 1.6, 10.8))
	await create_timer(0.6).timeout
	_check("away in Life Support (nobody can see the monitor): feed stops rendering", not net.is_rendering("INT-02"))
	var f1: int = int(net.frames["INT-02"])
	fb.sync_to_eye_position(Vector3(0.0, 1.6, 0.8))
	await create_timer(0.6).timeout
	_check("back in the Control Room: FRESH frames again (%d -> %d)" % [f1, int(net.frames["INT-02"])], net.is_rendering("INT-02") and int(net.frames["INT-02"]) > f1)
	_check("the body is where the player is, not at the seat", rig.global_position.distance_to(Vector3(0, 0, 0.8)) < 0.6)
	shell.show_page(shell.Page.OPS)
	await create_timer(0.4).timeout
	_check("Operations page: no camera renders for the monitor", not net.demanded().has("workstation"))


func _inspect() -> void:
	ws.begin_use()
	await _until(func(): return ws.is_in_use(), 5.0)
	shell.show_page(shell.Page.CAMERAS)
	var fov0: float = pc.fov
	var w0: float = shell._feed.size.x
	shell.toggle_inspect()
	await process_frame
	_check("INSPECT: the feed fills the monitor (%.0f -> %.0f px of 640)" % [w0, shell._feed.size.x], shell._feed.size.x > 600.0 and shell.cam_inspect)
	_check("INSPECT: the seated view leans in (fov %.1f -> %.1f)" % [fov0, pc.fov], pc.fov < fov0 - 5.0)
	_check("INSPECT: the list is hidden, prev / next / back shown", not (shell.cam_buttons["INT-02"] as Button).visible and shell.action_buttons["cam_next"].visible)
	var before: String = shell.selected_cam
	shell.step_camera(1)
	_check("next camera from inspect mode (%s -> %s)" % [before, shell.selected_cam], shell.selected_cam != before)
	shell.show_page(shell.Page.OPS)
	await process_frame
	_check("leaving the page ends INSPECT and restores the view (fov %.1f)" % pc.fov, not shell.cam_inspect and absf(pc.fov - fov0) < 0.5)
	ws.end_use()
	await _until(func(): return not ws._transitioning and not ws.is_in_use(), 5.0)


func _until(cond: Callable, seconds: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		await physics_frame


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
