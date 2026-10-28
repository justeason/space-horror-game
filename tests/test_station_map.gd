extends SceneTree
## Milestone coverage for the Control Room station map (Phase 4):
## topology matches the actual verified MovementNode graph (not an
## invented shortcut), task-outstanding highlighting tracks real
## DayPlan state, Left/Right selection cycles and reads back the
## correct per-room info (including explaining an unmet dependency),
## and none of this duplicates task state of its own.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player := main.get_node("Player")
	var console := main.get_node("Interactables/WorkstationConsole")
	var wstate := main.get_node("WorkstationState")
	var screen := console.get_node("WorkstationScreen")
	var dp := main.get_node("DayPlan")

	var console_pos: Vector3 = console.global_position + Vector3(0, 1.6 - console.global_position.y, 0.6)
	player.global_position = console_pos
	console.interact()
	await create_timer(1.0).timeout
	_send_key(KEY_1) # Overview
	await create_timer(0.05).timeout
	_check("overview shown", screen.current_section() == screen.Section.OVERVIEW)

	# ============================================================
	# 1. Topology: exactly the 8 verified room-level edges, derived
	# from the real MovementNode graph -- no invented direct Life
	# Support <-> Engineering shortcut even though the task brief's
	# prose suggested one (the real graph only connects them via
	# Main Junction or via Storage).
	# ============================================================
	var map := screen.get_node("Control/VBox/Content/Overview/Map")
	var expected_rooms := ["RoomLivingQuarters", "RoomControlRoom", "RoomMainJunction", "RoomCommunications", "RoomLifeSupport", "RoomEngineering", "RoomStorage", "RoomAirlock"]
	for n in expected_rooms:
		_check("map has a %s box" % n, map.get_node_or_null(n) != null)
	var expected_edges := ["EdgeLqCr", "EdgeCrMj", "EdgeMjComms", "EdgeMjLs", "EdgeMjEng", "EdgeEngStorage", "EdgeEngAirlock", "EdgeStorageLs"]
	for n in expected_edges:
		_check("map draws the %s edge" % n, map.get_node_or_null(n) != null)
	_check("map does not draw a direct Life Support <-> Engineering edge (none exists in the real graph)", map.get_node_or_null("EdgeLsEng") == null)

	# ============================================================
	# 1b. Visual arrangement matches the requested redesign (not just
	# topology): Life Support and Engineering are in SWAPPED positions
	# relative to the old layout (Life Support now shares Main
	# Junction's row; Engineering is now in the row below), Airlock
	# sits downstream of Engineering (below it, not above/beside Main
	# Junction), Storage sits between Engineering and Life Support's
	# real access routes, and Communications stays its own branch
	# above Main Junction. Geometric, not pixel-exact, so a minor
	# authoring tweak doesn't false-positive this test.
	# ============================================================
	var mj_rect: Rect2 = _rect_of(map, "RoomMainJunction")
	var ls_rect: Rect2 = _rect_of(map, "RoomLifeSupport")
	var eng_rect: Rect2 = _rect_of(map, "RoomEngineering")
	var storage_rect: Rect2 = _rect_of(map, "RoomStorage")
	var airlock_rect: Rect2 = _rect_of(map, "RoomAirlock")
	var comms_rect: Rect2 = _rect_of(map, "RoomCommunications")

	_check("Life Support shares Main Junction's row (swapped into Engineering's old spot)", absf(ls_rect.position.y - mj_rect.position.y) < 1.0)
	_check("Life Support is to the right of Main Junction", ls_rect.position.x > mj_rect.position.x)
	_check("Engineering is in the row below Main Junction (swapped into Life Support's old spot)", eng_rect.position.y > mj_rect.position.y)
	_check("Engineering is NOT in Main Junction's own row", absf(eng_rect.position.y - mj_rect.position.y) > 1.0)
	_check("Airlock is downstream of (below) Engineering, not above/beside it", airlock_rect.position.y > eng_rect.position.y)
	_check("Airlock shares Engineering's column (a branch straight off it)", absf(airlock_rect.position.x - eng_rect.position.x) < 1.0)
	_check("Storage sits in Engineering's row, to its right (between Engineering and Life Support)", absf(storage_rect.position.y - eng_rect.position.y) < 1.0)
	_check("Storage is directly below Life Support (the other end of its access route)", absf(storage_rect.position.x - ls_rect.position.x) < 1.0)
	_check("Communications remains its own branch above Main Junction", comms_rect.position.y < mj_rect.position.y and absf(comms_rect.position.x - mj_rect.position.x) < 1.0)

	# ============================================================
	# 2. Selection cycles with Left/Right and updates the info text.
	# ============================================================
	_check("default selection is Control Room", screen.get_node("Control/VBox/Content/Overview/RoomInfo").text.begins_with("Control Room"))
	_send_key(KEY_RIGHT)
	await create_timer(0.05).timeout
	_check("right arrow advances selection (now Main Junction)", screen.get_node("Control/VBox/Content/Overview/RoomInfo").text.begins_with("Main Junction"))
	_send_key(KEY_LEFT)
	await create_timer(0.05).timeout
	_check("left arrow moves back (Control Room again)", screen.get_node("Control/VBox/Content/Overview/RoomInfo").text.begins_with("Control Room"))

	# ============================================================
	# 3. Outstanding-task highlight tracks real DayPlan state, and
	# the info text explains an unmet dependency (Storage before the
	# circuit is traced) rather than looking inertly blank.
	# ============================================================
	_check("storage info explains the missing dependency before tracing", _room_info_for(screen, "RoomStorage").findn("trace") != -1)

	_send_key(KEY_2) # Work Orders (not required, just confirms section switch doesn't break anything)
	await create_timer(0.05).timeout
	_send_key(KEY_1) # back to Overview
	await create_timer(0.05).timeout
	_send_key(KEY_R) # C01
	await create_timer(0.05).timeout
	_check("C01 done, assignment pinned to e06", dp.is_task_done(&"c01") and dp.assignment_task_id == &"e06")
	_check("outstanding room is now Engineering (E06 assigned)", dp.get_outstanding_task_room() == &"engineering")
	_check("Engineering box is highlighted as the outstanding-task room", map.get_node("RoomEngineering").color == Color(0.5, 0.38, 0.12))

	# Complete E06 directly on the real world object (same pattern as
	# test_carry_and_e06.gd) -- the map must reflect it without any
	# separate map-only bookkeeping.
	var loose := main.get_node("Interactables/LooseConnection")
	for i in 6:
		loose.interact()
	_check("E06 actually done", dp.is_task_done(&"e06"))
	_check("outstanding room moves to Control Room (verification pending)", dp.get_outstanding_task_room() == &"control_room")

	_send_key(KEY_2) # Work Orders
	await create_timer(0.05).timeout
	_send_key(KEY_R) # C05 verify
	await create_timer(0.05).timeout
	_check("C05 verified", dp.is_task_done(&"c05"))
	_send_key(KEY_1) # back to Overview to re-check the map
	await create_timer(0.05).timeout
	_check("no outstanding room once C05 is verified", dp.get_outstanding_task_room() == &"")

	_send_key(KEY_ESCAPE)
	await create_timer(1.3).timeout
	_check("player back in control after using the map", not wstate.is_in_use())

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()

func _rect_of(map: Node, room_node_name: String) -> Rect2:
	var box: Control = map.get_node(room_node_name)
	return Rect2(box.offset_left, box.offset_top, box.offset_right - box.offset_left, box.offset_bottom - box.offset_top)

func _room_info_for(screen: Node, room_node_name: String) -> String:
	var map := screen.get_node("Control/VBox/Content/Overview/Map")
	var names := ["RoomLivingQuarters", "RoomControlRoom", "RoomMainJunction", "RoomCommunications", "RoomLifeSupport", "RoomEngineering", "RoomStorage", "RoomAirlock"]
	var idx: int = names.find(room_node_name)
	while screen.get("_selected_room_index") != idx:
		screen.select_next_room()
	return screen.get_node("Control/VBox/Content/Overview/RoomInfo").text

func _send_key(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)

func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
