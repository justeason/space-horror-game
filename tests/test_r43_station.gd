extends SceneTree
## Round 43 Priorities 6 / 8 / 14-20 / 23A: station life and visuals.
##  - routines: toothbrushing (gesture with a real toothbrush prop), TWO
##    separate meals (one interaction never satisfies both; dinner is later),
##    drinking, basil watering with a visible condition; a new day resets
##    them; a skipped dinner is remembered mildly; save/load;
##  - Communications: the PHYSICAL console faces into the room (it used to
##    face the wall -- mirrored readout, dials hidden), shows the shared
##    tuning, keeps it after the focused view closes, goes dark with B-04;
##  - the stored EVA suit is drawn on a layer the player's camera renders
##    (helmet included) and disappears / returns with the worn suit;
##  - storage floor guidance light; exterior hull finishing pass clear of
##    windows / cameras / anchors; decor adds no collision.
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
	await _routines()
	await _comms()
	await _suit()
	await _visuals()
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _stand_at(p: Vector3) -> void:
	var fb: Node = main.get_node("FreeMoveBody")
	fb.sync_to_eye_position(p)
	for i in 4: await physics_frame


func _wait_consume() -> void:
	var body: Node = main.get_node("Player/PlayerBody")
	for i in 120:
		if not body.is_consuming() and q._pending == "":
			return
		await create_timer(0.1).timeout


func _routines() -> void:
	var body: Node = main.get_node("Player/PlayerBody")
	await _stand_at(Vector3(2.5, 1.6, -0.2))
	_check("hygiene niche with a toothbrush exists in the quarters", q.get_node_or_null("HygieneNiche") != null and q._brush_holder != null)
	q.on_part(&"brush")
	await process_frame
	_check("brushing plays the hand gesture with the toothbrush prop", body.is_consuming() and body._consume_kind == "brush" and not q._brush_holder.visible)
	await _wait_consume()
	_check("teeth brushed; brush back in its holder", q.brushed_today() and q._brush_holder.visible)
	q.on_part(&"meal")
	await process_frame
	_check("first meal = BREAKFAST (pouch gesture)", body._consume_kind == "meal")
	await _wait_consume()
	_check("breakfast counted, dinner NOT", q.breakfast_today() and not q.dinner_today())
	q.on_part(&"meal")
	await process_frame
	_check("dinner refused in the morning (one meal never satisfies both)", not body.is_consuming() and not q.dinner_today() and q.dinner_refusal() != "")
	_check("the shift's MEAL row is breakfast + drink (dinner is evening)", dp._meal_row()["action"].find("Drink") != -1)
	q.on_part(&"water")
	await _wait_consume()
	_check("drinking still works", q.drank_today() and dp.meal_done())
	dp.shift_elapsed_s = dp.shift_duration_s() * 0.9
	q.on_part(&"meal")
	await process_frame
	_check("evening: DINNER with its own tray prop", body._consume_kind == "dinner")
	await _wait_consume()
	_check("dinner counted separately", q.dinner_today())
	q.on_part(&"meal")
	await process_frame
	_check("no third meal", not body.is_consuming())
	q.on_part(&"basil")
	_check("basil watered (once a day)", q.basil_watered_today() and q.basil_health() == 1.0)
	var sd: Dictionary = JSON.parse_string(JSON.stringify(q.state_dict()))
	q.load_dict({})
	q.load_dict(sd)
	_check("routine survives save/load", q.brushed_today() and q.breakfast_today() and q.dinner_today() and q.basil_watered_today())
	dp.end_shift_now()
	dp.reset_for_new_day()
	_check("new day: routine resets", not q.brushed_today() and not q.breakfast_today() and not q.dinner_today() and not q.missed_dinner)
	q.meal_day = dp.day_number
	dp.end_shift_now()
	dp.reset_for_new_day()
	_check("skipped dinner: remembered mildly (no penalty)", q.missed_dinner and not dp.underfed)
	_check("forgotten basil droops a little (health %.2f)" % q.basil_health(), q.basil_health() < 1.0 and q.basil_health() > 0.0)
	var note: Array = load("res://scripts/ui/daily_note.gd").lines(load("res://scripts/ui/daily_note.gd").build(dp, q))
	_check("the daily note mentions the skipped dinner", "\n".join(note).find("skipped dinner") != -1)
	dp.end_shift_now()
	dp.reset_for_new_day()
	_check("no meal at all -> underfed (existing mild penalty)", dp.underfed)


func _comms() -> void:
	var st: Node3D = main.get_node("Interactables/SignalCalibrationStation")
	var wd: Node3D = st.get_node("WorldDiorama")
	var room_ctr := Vector3(2.0, 1.6, 7.1)
	var facing: Vector3 = wd.global_basis.z.normalized()
	_check("physical console FACES INTO THE ROOM (front %s)" % facing, facing.dot((room_ctr - st.global_position).normalized()) > 0.9)
	st._ensure_profile()
	var f0: float = st.frequency()
	st.nudge_frequency(1)
	st.nudge_frequency(1)
	await create_timer(0.4).timeout
	var dial: Node3D = wd.get_node("Dials/FreqDial")
	var expect: float = deg_to_rad(lerpf(-120.0, 120.0, st.frequency() / 100.0))
	_check("world dial shows the tuned frequency (%.2f rad)" % dial.rotation.z, absf(dial.rotation.z - expect) < 0.01 and st.frequency() != f0)
	_check("world readout shows the values ('%s')" % (wd.get_node("Labels/ReadoutText") as Label3D).text.replace("\n", " | "), (wd.get_node("Labels/ReadoutText") as Label3D).text.find("F %.0f" % st.frequency()) != -1)
	var view: Node = main.get_node("Player/HUD/SignalCalibrationView")
	view.open_station(st)
	await create_timer(0.3).timeout
	st.nudge_gain(1)
	var fis: Node = main.find_child("FocusedInteractionState", true, false)
	if fis != null:
		fis.end()
	await create_timer(0.4).timeout
	var gd: Node3D = wd.get_node("Dials/GainDial")
	_check("closing the focused view keeps the state on the world dials", absf(gd.rotation.z - deg_to_rad(lerpf(-120.0, 120.0, st.gain()))) < 0.01)
	var br: Node = main.get_node("Equipment/BreakerPanel")
	var br_snap: Dictionary = br.state_dict()
	br.trip(3, "TEST")
	await create_timer(0.4).timeout
	_check("B-04 off: console dead (RX OFF, needle at rest, bars unlit)", (wd.get_node("Labels/ReadoutText") as Label3D).text.find("RX OFF") != -1 and not wd.powered and absf(wd.get_node("Meter/Needle").rotation.z + deg_to_rad(120.0)) < 0.01)
	br.load_dict(br_snap)
	await create_timer(0.4).timeout
	_check("B-04 restored: readout back ('%s')" % (wd.get_node("Labels/ReadoutText") as Label3D).text.replace("\n", " | "), wd.powered and (wd.get_node("Labels/ReadoutText") as Label3D).text.find("LINK") != -1)
	var sd: Dictionary = JSON.parse_string(JSON.stringify(st.state_dict()))
	var fsave: float = st.frequency()
	st.nudge_frequency(1)
	st.load_dict(sd)
	await create_timer(0.3).timeout
	_check("save/load restores the world display", absf(dial.rotation.z - deg_to_rad(lerpf(-120.0, 120.0, fsave / 100.0))) < 0.01)


func _suit() -> void:
	var eva: Node = main.get_node("EvaSystem")
	var cam: Camera3D = main.get_node("Player/LookPivot/PitchPivot/Camera3D")
	var rig: Node = eva.locker_rig
	var hidden := 0
	for v in rig.find_children("*", "VisualInstance3D", true, false):
		if (v as VisualInstance3D).visible and ((v as VisualInstance3D).layers & cam.cull_mask) == 0:
			hidden += 1
	_check("stored suit: every visible part (helmet too) on a layer the player camera renders (%d hidden)" % hidden, hidden == 0)
	_check("stored suit HAS its helmet", rig._suit_helmet != null and rig._suit_helmet.is_visible_in_tree())
	eva.set_suited(true)
	_check("worn: the suit leaves the locker (empty yoke)", not eva._locker_suit.visible and eva._locker_open.visible)
	eva.set_suited(false)
	_check("returned: the full suit, helmet included, is back", eva._locker_suit.visible and rig._suit_helmet.is_visible_in_tree())


func _visuals() -> void:
	var decor: Node = main.find_child("StationDecor", true, false)
	if decor == null:
		decor = get_root().get_tree().get_first_node_in_group(&"station_decor")
	_check("storage floor guidance: low fill lights at floor level", decor.storage_lights.size() == 2 and decor.storage_lights.all(func(l): return (l as OmniLight3D).global_position.y < 0.4 and (l as OmniLight3D).light_energy < 0.8))
	var floor_strips: int = decor.strips.filter(func(s): return (s["color"] as Color).is_equal_approx(Color(0.55, 0.85, 1.0))).size()
	_check("storage floor-edge LED strips (%d)" % floor_strips, floor_strips >= 2)
	var colliders := 0
	for n in decor.find_children("*", "CollisionObject3D", true, false):
		colliders += 1
	_check("decor adds no collision (interior access unchanged)", colliders == 0)
	var ext: Node = get_root().get_tree().get_first_node_in_group(&"exterior")
	await process_frame
	_check("exterior finishing pass: %d details, %d hull lights over %d wall plates" % [ext.finish_count, ext.hull_lights, ext._wall_plates.size()], ext.finish_count > 150 and ext.hull_lights >= 6 and ext._wall_plates.size() > 20)
	var fin: Node3D = ext.get_node("HullFinish")
	var keep: Array = ext._keep_outs()
	var bad := 0
	for g in fin.find_children("*", "MeshInstance3D", true, false):
		var gp: Vector3 = (g as Node3D).global_position
		var big: bool = (g as MeshInstance3D).get_aabb().size.length() > 0.5
		if not big and not ext._clear_of(gp, keep, 0.4):
			bad += 1
	_check("small hull details kept clear of window / hatch / cameras / anchors (%d)" % bad, bad == 0)
	var lights_ok: bool = fin.find_children("*", "OmniLight3D", true, false).all(func(l): return (l as OmniLight3D).light_cull_mask == ext.EXTERIOR)
	_check("hull lights only light the exterior layer (never interiors)", lights_ok)
	_check("finishing geometry is visual only (no collision)", fin.find_children("*", "CollisionObject3D", true, false).is_empty())


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
