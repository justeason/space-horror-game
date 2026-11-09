extends SceneTree
## Round 40 Priority 3: WALKWAY OBSTRUCTION AUDIT. The capsule sweep
## (test_station_capsule_sweep) only sees COLLISION; decorative geometry
## has none, so a trim bar or rib post standing in a doorway was walk-
## through but still looked like a blocking bar (Round 39 user report:
## Junction -> Comms). This sweeps a person-sized volume (0.44 m wide,
## knee to head height) along EVERY navigation edge (same edge set as the
## capsule sweep) and checks it against all VISUAL geometry that is not
## the walls/floors/ceilings themselves: station decor, seal panels, scene
## trim without collision, airlock parts, hull dressing, quarters props.
## Any overlap is a walkway obstruction and is listed with its node path.
var _ok := true
const HALF_W := 0.22
const Y_LO := 0.25
const Y_HI := 1.95


func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 6: await process_frame
	main.get_node("FreeMoveBody").set_active(false)
	# Candidate obstructions: visual instances in these subtrees.
	var cands: Array = []
	for root_name in ["StationDecor", "StationSeal", "AirlockChamber", "Exterior", "Equipment/QuartersLife/LivedIn", "TetherAnchors"]:
		var r: Node = main.get_node_or_null(root_name)
		if r == null:
			continue
		for v in [r] + r.find_children("*", "GeometryInstance3D", true, false):
			if v is GeometryInstance3D and (v as GeometryInstance3D).is_visible_in_tree() and not (v is Label3D):
				cands.append(v)
	# Scene trim WITHOUT collision (decorative CSG / meshes in Geometry).
	for v in main.get_node("Geometry").get_children():
		if v is CSGShape3D and not (v as CSGShape3D).use_collision and (v as CSGShape3D).is_visible_in_tree():
			cands.append(v)
		elif v is MeshInstance3D and (v as MeshInstance3D).is_visible_in_tree():
			cands.append(v)
	# Deliberate furniture, not trim: the operator stool in front of the
	# workstation (its seat is part of the seated-workstation pose).
	const FURNITURE := ["Geometry/OperatorStoolSeat", "Geometry/OperatorStoolPost", "Geometry/OperatorStoolBase"]
	var boxes: Array = []
	for v in cands:
		if String(main.get_path_to(v)) in FURNITURE:
			continue
		var gi := v as GeometryInstance3D
		var bb: AABB = gi.global_transform * gi.get_aabb()
		if bb.size.length() < 60.0:
			boxes.append([bb, String(main.get_path_to(gi))])
	_check("audited %d decorative / non-colliding geometry pieces" % boxes.size(), boxes.size() > 300)
	# Edges = the navigation graph (as the capsule sweep).
	var nodes: Array = []
	for c in main.get_node("MovementNodes").get_children():
		if c.has_method("get_neighbor_nodes"):
			nodes.append(c)
	var edges := {}
	for n in nodes:
		for m in n.get_neighbor_nodes() + n.get_region_mates():
			var k: String = "|".join([String(n.name), String(m.name)] if String(n.name) < String(m.name) else [String(m.name), String(n.name)])
			edges[k] = [n, m]
	_check("navigation edges (%d)" % edges.size(), edges.size() > 20)
	var space: PhysicsDirectSpaceState3D = (main as Node3D).get_world_3d().direct_space_state
	var hits := {}
	for k in edges:
		var a: Vector3 = (edges[k][0] as Node3D).global_position
		var b: Vector3 = (edges[k][1] as Node3D).global_position
		var steps: int = maxi(int(a.distance_to(b) / 0.1), 2)
		for i in steps + 1:
			var p: Vector3 = a.lerp(b, float(i) / steps)
			var vol := AABB(Vector3(p.x - HALF_W, Y_LO, p.z - HALF_W), Vector3(HALF_W * 2.0, Y_HI - Y_LO, HALF_W * 2.0))
			for bx in boxes:
				if (bx[0] as AABB).intersects(vol):
					# Pieces buried inside a solid wall are invisible: only an
					# overlap the walker can actually SEE counts.
					var c: Vector3 = (bx[0] as AABB).intersection(vol).get_center()
					var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, c.y, p.z), c, 1)
					var hit: Dictionary = space.intersect_ray(q)
					if hit.is_empty() or (hit["position"] as Vector3).distance_to(c) < 0.03:
						hits["%s %s on %s" % [bx[1], str(bx[0]), k]] = true
	for h in hits:
		print("  OBSTRUCTION ", h)
	_check("no decorative geometry obstructs any walkway (%d)" % hits.size(), hits.is_empty())
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
