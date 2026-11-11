extends SceneTree
## Round 39 Priorities 2, 4, 5, 7 (+1 foundation): the daily routine and
## the room fixes.
##  - Living Quarters: the closet (locker) is no longer blocked by the
##    galley counter;
##  - corridor dressing follows the real walls: nothing stands in a
##    walkway or lies across a doorway (the stray bars);
##  - eating / drinking is REQUIRED daily routine (a MEAL row that counts
##    toward the shift), with a visible hand-to-mouth gesture; skipping it
##    leaves the technician underfed (slower) the next day;
##  - the shift is measured by work (progress %), ends after a short
##    wrap-up once the work is done, then the bunk is expected (tiredness);
##  - every new day starts in bed; new state saves / loads.
var _ok := true
var main: Node
var dp: Node
var q: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	dp = main.get_node("DayPlan")
	q = main.get_node("Equipment/QuartersLife")
	_layout()
	await _routine()
	await _shift()
	await _next_day_and_save()
	_files()
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for v in [n] + n.find_children("*", "GeometryInstance3D", true, false):
		if v is GeometryInstance3D and (v as GeometryInstance3D).is_visible_in_tree():
			var gi := v as GeometryInstance3D
			var bb: AABB = gi.global_transform * gi.get_aabb()
			out = bb if first else out.merge(bb)
			first = false
	return out


func _layout() -> void:
	# Closet doors (west face of the locker at x 4.87, z 1.52..2.18): keep a
	# 0.7 m deep swing / access zone clear.
	var access := AABB(Vector3(4.15, 0.05, 1.52), Vector3(0.7, 1.8, 0.66))
	var galley: AABB = _aabb(q.get_node("Galley"))
	_check("closet access zone is clear of the galley (galley %s)" % str(galley), not galley.intersects(access))
	var solid: CollisionShape3D = q.find_child("GalleySolid", true, false).get_child(0)
	var sp: Vector3 = solid.global_position
	_check("galley stands against the south wall (z %.2f), between doorway and bunk" % sp.z, sp.z < -0.9 and sp.x > 2.4 and sp.x < 4.3)
	var space: PhysicsDirectSpaceState3D = (main as Node3D).get_world_3d().direct_space_state
	var pq := PhysicsPointQueryParameters3D.new()
	pq.position = Vector3(4.5, 1.0, 1.85)
	pq.collision_mask = 1
	_check("nothing solid in front of the closet doors", space.intersect_point(pq, 1).is_empty())
	# Decor: no stray bars in walkways / across doorways.
	var decor: Node = main.get_node("StationDecor")
	var walk := AABB(Vector3(-0.45, 0.15, 2.3), Vector3(0.9, 2.0, 1.0))      # main corridor
	var door := AABB(Vector3(1.25, 0.02, 0.0), Vector3(0.6, 0.4, 1.0))       # Control <-> Quarters doorway
	var in_walk := 0
	var in_door := 0
	for v in decor.get_children():
		if v is GeometryInstance3D:
			var bb: AABB = (v as GeometryInstance3D).global_transform * (v as GeometryInstance3D).get_aabb()
			if bb.intersects(walk):
				in_walk += 1
			if bb.intersects(door):
				in_door += 1
	_check("no decor piece stands in the main corridor walkway (%d)" % in_walk, in_walk == 0)
	_check("no kick plate / trim lies across the Control <-> Quarters doorway (%d)" % in_door, in_door == 0)
	var seal: Node = main.get_node("StationSeal")
	_check("the doorway threshold, jambs and seam panels exist and collide (%d panels)" % seal.panels.size(), seal.panels.size() >= 20 and seal.panels.all(func(p): return (p as CSGBox3D).use_collision))


func _routine() -> void:
	dp.mark_done(&"c01")
	var rows: Array = dp.order_rows().filter(func(r): return r["id"] == "MEAL")
	_check("a MEAL routine row (Living Quarters) is part of the day", rows.size() == 1 and rows[0]["room"] == &"living_quarters" and not rows[0]["done"] and rows[0]["progress"] == "0/2")
	_check("the routine counts against completion", not dp.required_work_complete() or dp.order_rows().size() > 1)
	var p0: float = dp.shift_progress()
	_check("shift progress is a share of today's work ('%s'), not a clock" % dp.shift_status_text(), dp.shift_status_text().find("WORK %d%%" % int(round(p0 * 100.0))) != -1 and p0 > 0.0 and p0 < 1.0)
	var stn: Node = main.get_node("StationStatus")
	_check("the map marks the Quarters (routine)", int(stn.room_severity(&"living_quarters")) >= 1)
	# Eat at the galley: a visible gesture with the actual meal pouch.
	var fb: Node = main.get_node("FreeMoveBody")
	fb.sync_to_eye_position(Vector3(3.1, 1.6, -0.3))
	for i in 5: await physics_frame
	var body: Node = main.get_node("Player/PlayerBody")
	var cam: Camera3D = main.get_node("Player/LookPivot/PitchPivot/Camera3D")
	q.on_part(&"meal")
	_check("eating starts a visible gesture (not instant)", body.is_consuming() and not q.ate_today())
	await create_timer(q.EAT_S * 0.5).timeout
	var pp: Vector3 = body.consume_prop_position()
	_check("mid-gesture the meal pouch is at the mouth (%.2f m from the eye)" % pp.distance_to(cam.global_position), pp.distance_to(cam.global_position) < 0.4)
	await create_timer(q.EAT_S * 0.6).timeout
	_check("...then the meal counts", q.ate_today() and not body.is_consuming())
	_check("MEAL row now 1/2 (drink)", dp.order_rows().filter(func(r): return r["id"] == "MEAL")[0]["progress"] == "1/2")
	q.on_part(&"water")
	await create_timer(q.DRINK_S + 0.4).timeout
	_check("drinking water completes the routine", dp.meal_done() and dp.order_rows().filter(func(r): return r["id"] == "MEAL")[0]["done"])
	_check("...and the shift progress rose (%d%% -> %d%%)" % [roundi(p0 * 100.0), roundi(dp.shift_progress() * 100.0)], dp.shift_progress() > p0)


func _shift() -> void:
	# Close everything else so the day's required work is complete.
	dp.orders = dp.orders.filter(func(o): return o["status"] != "open")
	dp.workday = 0
	dp.cargo_duty = ""
	await create_timer(0.3).timeout
	# Round 46: work done no longer ends the shift 45 s later -- the shift
	# runs its full 600 s budget (resting early is the player's choice).
	_check("required work complete -> WORK DONE (no shift end yet)", dp.is_wrapping_up() and not dp.shift_ended and dp.shift_status_text().find("WORK DONE") != -1)
	dp.shift_elapsed_s = dp.work_done_at_s + dp.WRAP_UP_S + 0.1
	await create_timer(0.2).timeout
	_check("Round 46: ...and still no shift end after the old 45 s wrap-up", not dp.shift_ended)
	dp.shift_elapsed_s = dp.shift_duration_s()
	await create_timer(0.2).timeout
	_check("at the end of the budget the shift ends (bunk expected)", dp.shift_ended and dp.bed_required() and dp.shift_status_text().find("REST") != -1)
	await create_timer(1.8).timeout
	_check("Round 40: a warm glow comes on over the bunk (wordless 'go to bed')", q.bunk_glow_energy() > 0.5)
	_check("not tired yet inside the grace period", dp.tiredness() == 0.0 and is_equal_approx(dp.movement_factor(), 1.0))
	dp.awake_after_shift_s = dp.BED_GRACE_S + dp.TIRED_RAMP_S
	await create_timer(0.2).timeout
	var fbm: Node = main.get_node("FreeMoveBody")
	_check("staying up: tired -> slower walking (%.2f) and a closing vignette" % fbm.speed_scale, dp.tiredness() >= 0.99 and fbm.speed_scale < 0.75 and dp.get_node("FatigueVignette").strength > 0.5)


func _next_day_and_save() -> void:
	# A day ending WITHOUT the meal -> underfed next morning.
	q.meal_day = -1
	q.drank_day = -1
	dp.reset_for_new_day()
	await create_timer(0.2).timeout
	_check("skipped meals -> underfed the next day (slower: %.2f)" % dp.movement_factor(), dp.underfed and dp.movement_factor() < 0.9)
	_check("a new day resets the shift (progress, wrap-up, tiredness)", not dp.shift_ended and dp.work_done_at_s < 0.0 and dp.tiredness() == 0.0)
	var sg: Node = main.get_node("SaveGame")
	sg.save_path = "user://test_r39_routine.json"
	var r: Dictionary = sg.save_game()
	_check("save: %s" % r["message"], r["ok"])
	dp.underfed = false
	q.meal_day = 3
	if r["ok"]:
		sg.apply_state(sg.read_save()["data"])
	_check("load restores underfed + the day's meals", dp.underfed and q.meal_day == -1)
	q.on_part(&"meal")
	await create_timer(q.EAT_S + 0.4).timeout
	_check("eating clears underfed", not dp.underfed)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_r39_routine.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_r39_routine.json.bak"))
	# Every new game day starts in the bunk.
	var ss: Node = main.get_node("SleepState")
	ss.start_day_in_bed()
	await process_frame
	_check("a new day starts lying in the bunk", ss.is_lying_in_bed() and ss.is_sleeping())


func _files() -> void:
	var Files = load("res://scripts/ui/laptop_files.gd")
	Files.register("Games", {"name": "test_note.txt", "date": "2026-11-01", "type": "txt", "text": "hi"})
	_check("laptop file registry: new folders / files can be added for future content", "Games" in Files.folders() and Files.list("Games").size() == 1)
	Files.register("Games", {"name": "test_note.txt", "date": "2026-11-01", "type": "txt", "text": "hi"})
	_check("...without duplicates", Files.list("Games").size() == 1)


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
