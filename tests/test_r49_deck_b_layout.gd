extends SceneTree
## Round 49: DECK B -- the Lower Service Deck exists as real, sealed,
## walkable architecture under the (unchanged) upper deck, joined only by
## the B-00 shaft; the one movement graph knows both decks.
##   - every principal room B-01..B-09 + the reserved B-10 / B-11: floor
##     under it, ceiling over it, walls around it (rays), lights;
##   - pressure hull: from inside every module, rays in 16 directions plus
##     up / down all hit Deck B structure before leaving the module (no
##     open seam to vacuum); B-10's hatch is a closed wall; B-11 ends in a
##     bulkhead; exterior plating exists;
##   - the shaft: a collidable tube from Deck A's floor to Deck B; the
##     vestibule off Engineering (Deck A) and its doorway are real;
##   - graph: deck ids, no walking link between decks, the LADDER link,
##     shortest cross-deck routes (Control Room -> Archive), access
##     restrictions, emergency egress from every Deck B node;
##   - the upper deck is intact (its rooms / nodes / key walls).
const L = preload("res://scripts/deck_b/deck_b_layout.gd")
const G = preload("res://scripts/navigation/station_graph.gd")
var _ok := true
var main: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	main.get_node("FreeMoveBody").set_active(false)
	for i in 2: await physics_frame
	var sp: PhysicsDirectSpaceState3D = get_root().get_world_3d().direct_space_state
	var db: Node = main.get_node("DeckB")
	_check("Deck B built (%d wall segments, %d hull plates)" % [db.wall_segments.size(), db.plate_count], db.wall_segments.size() > 60 and db.plate_count > 60)
	# Rooms.
	for room in [&"b01", &"b02", &"b03", &"b04", &"b05", &"b06", &"b07", &"b08", &"b09"]:
		var n: Node = db.room_node(room)
		_check("%s %s has its equipment node" % [room, L.room_name(room)], n != null and n.get_child_count() > 10)
	for sp_def in L.SPACES:
		var c := Vector3((float(sp_def[2]) + float(sp_def[3])) * 0.5, L.FLOOR_Y + 1.2, (float(sp_def[4]) + float(sp_def[5])) * 0.5)
		var down: Dictionary = _ray(sp, c, c + Vector3(0, -3, 0))
		var up: Dictionary = _ray(sp, c, c + Vector3(0, 4, 0))
		var floor_ok: bool = not down.is_empty() and absf((down["position"] as Vector3).y - L.FLOOR_Y) < 0.02
		var ceil_ok: bool = not up.is_empty() and absf((up["position"] as Vector3).y - float(sp_def[6])) < 0.02
		var sealed := true
		var leak_dir := ""
		for k in 16:
			var a: float = TAU * k / 16.0
			var d := Vector3(cos(a), 0, sin(a))
			var hit: Dictionary = _ray(sp, c, c + d * 14.0)
			var end: Vector3 = hit["position"] if not hit.is_empty() else c + d * 14.0
			# Every point the ray travels before its first hit must still be
			# INSIDE the deck (through a doorway into the next module is
			# fine; out through a seam into vacuum is a leak).
			var steps: int = int(c.distance_to(end) / 0.1)
			for st in steps:
				var q: Vector3 = c + d * (float(st) * 0.1)
				if not _inside_deck(q):
					sealed = false
					leak_dir = "%d deg at (%.2f, %.2f)" % [int(rad_to_deg(a)), q.x, q.z]
					break
			if not sealed:
				break
		_check("%s: floor at Deck B level, ceiling %.1f, sealed all round%s" % [sp_def[0], float(sp_def[6]), "" if sealed else " -- LEAK " + leak_dir], floor_ok and ceil_ok and sealed)
	# B-10 sealed: from ARCH_A you cannot see into B-10 through its hatch.
	var into_b10: Dictionary = _ray(sp, Vector3(3.1, L.FLOOR_Y + 1.0, 7.9), Vector3(3.1, L.FLOOR_Y + 1.0, 6.0))
	_check("B-10 hatch is a closed bulkhead (no opening)", not into_b10.is_empty() and (into_b10["position"] as Vector3).z > 7.25)
	var stub: Dictionary = _ray(sp, Vector3(-8.0, L.FLOOR_Y + 1.0, 9.6), Vector3(-8.0, L.FLOOR_Y + 1.0, 11.5))
	_check("B-11 ends in a sealed bulkhead", not stub.is_empty() and (stub["position"] as Vector3).z < 10.35)
	# Shaft and vestibule.
	var tube_hit: Dictionary = _ray(sp, Vector3(L.SHAFT_X, -1.5, L.SHAFT_Z), Vector3(L.SHAFT_X - 1.5, -1.5, L.SHAFT_Z))
	_check("shaft tube wall is solid (inner radius ~%.2f)" % L.SHAFT_R, not tube_hit.is_empty() and absf((tube_hit["position"] as Vector3).x - L.SHAFT_X) < L.SHAFT_R + 0.12)
	var lid: Dictionary = _ray(sp, Vector3(L.SHAFT_X, 1.0, L.SHAFT_Z), Vector3(L.SHAFT_X, -1.0, L.SHAFT_Z))
	_check("the hatch lid closes the Deck A floor (walkable, y %.2f)" % ((lid["position"] as Vector3).y if not lid.is_empty() else -99.0), not lid.is_empty() and (lid["position"] as Vector3).y > -0.08)
	var door: Dictionary = _ray(sp, Vector3(-4.65, 1.0, 6.5), Vector3(-4.65, 1.0, 7.4))
	_check("Engineering -> shaft vestibule doorway is open", door.is_empty() or (door["position"] as Vector3).z > 7.3)
	_check("upper deck intact: Engineering / Storage / Control floors and walls present", main.has_node("Geometry/EngineeringFloor") and main.has_node("Geometry/StorageFloor") and main.has_node("Geometry/ControlRoomFloor") and main.has_node("Geometry/EngineeringNorthWall") and main.has_node("Geometry/ShaftVestibuleFloor"))
	_check("upper deck movement nodes intact (Control, Junction, Storage, Life Support, Comms, Airlock)", ["ControlRoomFrontLeft", "JunctionNode1", "StorageA", "LifeSupportA", "CommsA", "AirlockStub"].all(func(n): return main.has_node("MovementNodes/" + n)))
	# Lights: Deck B lights cannot reach Deck A (downward spots / own layer).
	var leak_light := false
	for l in get_nodes_in_group(&"deck_b_light"):
		if l is OmniLight3D and ((l as OmniLight3D).light_cull_mask & 1) != 0:
			leak_light = true
		if l is SpotLight3D and (l as SpotLight3D).global_transform.basis.z.y < 0.9:
			leak_light = true
	_check("Deck B lighting: downward spots + Deck-B-layer fills only (%d lights)" % get_nodes_in_group(&"deck_b_light").size(), not leak_light and get_nodes_in_group(&"deck_b_light").size() > 20)
	var upper_lit_b := false
	for l in main.get_node("Lights").get_children():
		if l is Light3D and ((l as Light3D).light_cull_mask & L.LAYER) != 0:
			upper_lit_b = true
	_check("Deck A lights ignore Deck B's layer (no light through the floors)", not upper_lit_b)
	# Graph.
	var nodes: Array = G.nodes(main)
	var b_nodes: Array = nodes.filter(func(n): return n.deck == &"B")
	_check("graph has %d Deck B nodes, each at Deck B eye height" % b_nodes.size(), b_nodes.size() == L.NODES.size() and b_nodes.all(func(n): return absf((n as Node3D).global_position.y - L.EYE_Y) < 0.01))
	var cross_walk := false
	for n in nodes:
		for m in n.get_movement_candidates():
			if m.deck != n.deck:
				cross_walk = true
	_check("no WALKING link between decks (only the ladder)", not cross_walk)
	var top: Node = G.find(main, "ShaftTop")
	var bot: Node = G.find(main, "BShaftBottom")
	_check("ladder link ShaftTop <-> BShaftBottom", top != null and bot != null and top.get_ladder_nodes().has(bot) and bot.get_ladder_nodes().has(top))
	var r: Array = G.route(main, "ControlRoomFrontLeft", "BArchiveA")
	_check("cross-deck route Control Room -> Archive (%d nodes, %.1f m)" % [r.size(), G.route_length(main, r) if not r.is_empty() else -1.0], r.has("ShaftTop") and r.has("BShaftBottom") and r.find("ShaftTop") + 1 == r.find("BShaftBottom"))
	var r2: Array = G.route(main, "BWaterA", "BThermalA")
	_check("same-deck route stays on Deck B (Water -> Thermal: %s)" % " ".join(r2), not r2.is_empty() and not r2.has("ShaftTop"))
	var gated: Callable = func(n): return String(n.name) != "BArchiveDoor"
	_check("access restriction: no route into the Archive past its closed door", G.route(main, "BJunctionC", "BArchiveA", gated).is_empty())
	var egress_ok := true
	for n in b_nodes:
		var e: Array = G.egress(main, (n as Node3D).global_position)
		if e.is_empty() or e.back() != "ShaftTop":
			egress_ok = false
	_check("emergency egress: every Deck B node has a route up the shaft", egress_ok)
	_check("room lookup: B-02 / B-09 / Deck A", L.room_at(Vector3(-0.1, L.EYE_Y, 9.6)) == &"b02" and L.room_at(Vector3(6.0, L.EYE_Y, 9.4)) == &"b09" and L.room_at(Vector3(0, 1.6, 4.5)) == &"")
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _inside_deck(q: Vector3) -> bool:
	for s2 in L.SPACES:
		if q.x > float(s2[2]) - 0.12 and q.x < float(s2[3]) + 0.12 and q.z > float(s2[4]) - 0.12 and q.z < float(s2[5]) + 0.12:
			return true
	return false


func _ray(sp: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	q.exclude = [main.get_node("FreeMoveBody").get_rid()]
	return sp.intersect_ray(q)


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
