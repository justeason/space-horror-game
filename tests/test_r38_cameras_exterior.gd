extends SceneTree
## Round 38 Priorities 1-3, 5: camera network, exterior, observation port,
## camera/window discrepancy foundation.
var _ok := true
var main: Node
var net: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	net = main.get_node("CameraNetwork")
	var ids: Array = net.ids()
	_check("Round 41: a CURATED network of 8 feeds (%s)" % ", ".join(ids), ids.size() == 8 and ids == net.CURATED)
	_check("interior + exterior cameras (4 + 4: Round 41 adds EXT-01 overview + EXT-05 solar)", ids.filter(func(i): return i.begins_with("INT")).size() == 4 and ids.filter(func(i): return i.begins_with("EXT")).size() == 4)
	_check("every camera has a physical housing at its mount", ids.all(func(i): return net.camera(i).get_node_or_null("Housing") != null))
	_check("cameras never render their own housings", ids.all(func(i): return (net.camera(i).cull_mask & (1 << 15)) == 0))
	_check("feeds are live viewports of the real world (not textures)", ids.all(func(i): return net.feed(i) is ViewportTexture))
	main.get_node("FreeMoveBody").sync_to_eye_position(Vector3(-4.2, 1.6, 5.0))
	main.get_node("Player").global_position = Vector3(-4.2, 1.6, 5.0)
	await create_timer(0.6).timeout
	_check("idle network (player in Engineering): no camera feed renders", ids.all(func(i): return not net.is_rendering(i)))
	net.request("test", "EXT-03")
	_check("a displayed camera renders; others stay idle", net.is_rendering("EXT-03") and not net.is_rendering("INT-04"))
	net.request("test", "")
	# Exterior geometry.
	var ext: Node = main.get_node("Exterior")
	_check("exterior hull plating built from the real outer walls (%d panels)" % ext.panel_count, ext.panel_count > 40)
	_check("the sun lights only the exterior layer", ext.sun.light_cull_mask == (1 << 11))
	var inside_hits := 0
	for p in ext.get_node("Hull").get_children():
		var q: Vector3 = (p as Node3D).global_position
		# Inside = within a room footprint by more than its wall thickness.
		for r in ext._floor_rects:
			if q.y > 0.3 and q.y < 2.6 and r.grow(-0.35).has_point(Vector2(q.x, q.z)):
				inside_hits += 1
	_check("no hull panel sits inside a room or corridor (%d)" % inside_hits, inside_hits == 0)
	# Coverage: the shared observation region (antenna mast A1).
	var mast: Vector3 = Vector3(-2.85, 1.6, 0.75)
	for id in ["EXT-03"]:
		_check("%s sees antenna mast A1" % id, net.sees(id, mast))
	_check("EXT-02 sees the outer hatch walkway", net.sees("EXT-02", Vector3(-4.8, 0.6, -3.4)))
	_check("INT-04 sees Engineering's power panel", net.sees("INT-04", Vector3(-3.95, 1.4, 3.3)))
	_check("INT-07 (inside the chamber) sees the outer hatch", net.sees("INT-07", Vector3(-4.8, 1.2, -2.45)))
	_check("intentional blind spot: EXT-02 cannot see straight below its mount", not net.sees("EXT-02", Vector3(-3.45, 0.2, -3.95)))
	# The observation port: a direct view of the same exterior.
	var port: Node = main.get_node("Interactables/WallWatchWindow")
	_check("observation port renders the exterior from the player's eye (portal)", port.has_method("portal_camera") and port.portal_camera() != null)
	_check("the port is a DIRECT view (never shows CAMERA_ONLY)", (port.portal_camera().cull_mask & (1 << 18)) == 0)
	_check("cameras never show DIRECT_ONLY", ids.all(func(i): return (net.camera(i).cull_mask & (1 << 19)) == 0))
	var pc: Camera3D = main.get_node("Player/LookPivot/PitchPivot/Camera3D")
	_check("the player's eyes never see CAMERA_ONLY", (pc.cull_mask & (1 << 18)) == 0)
	# Standing in front of the port, its frustum covers the antenna.
	main.get_node("FreeMoveBody").sync_to_eye_position(Vector3(-0.3, 1.6, 1.4))
	main.get_node("Player").global_position = Vector3(-0.3, 1.6, 1.4)
	for i in 6: await process_frame
	var cam: Camera3D = port.portal_camera()
	var sp: Vector2 = cam.unproject_position(mast)
	var vs: Vector2 = Vector2(port.portal_viewport().size)
	_check("through the port the antenna is in view (%s in %s)" % [str(sp.round()), str(vs)], not cam.is_position_behind(mast) and sp.x > 0 and sp.x < vs.x and sp.y > 0 and sp.y < vs.y)
	_check("port renders while the player is in the Control Room", port.portal_viewport().render_target_update_mode == SubViewport.UPDATE_ALWAYS)
	# Discrepancy foundation.
	var disc: Node = main.get_node("Exterior/ObservationDiscrepancy")
	_check("no discrepancy is active in normal play", not disc.is_active())
	_check("an unknown source cannot trigger it", not disc.trigger("camera_figure", 5.0, "random"))
	_check("debug trigger works in a debug build", disc.trigger("camera_figure", 5.0, "debug"))
	var fig: Vector3 = disc.object_position("figure") + Vector3(0, 1.2, 0)
	_check("camera_figure: EXT-02 frames the figure", net.sees("EXT-02", fig))
	var fig_node: Node3D = disc._objs["figure"]
	_check("...but it is on CAMERA_ONLY (invisible to eyes/port)", fig_node.get_child(0).layers & (1 << 18) != 0)
	disc.clear()
	disc.trigger("displaced", 5.0, "debug")
	_check("displaced: direct and camera copies at different positions", disc.object_position("bag_direct").distance_to(disc.object_position("bag_camera")) > 2.0)
	disc.clear()
	_check("cleared", not disc.is_active())
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
