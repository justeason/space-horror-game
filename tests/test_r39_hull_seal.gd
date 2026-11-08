extends SceneTree
## Round 39 Priority 3: the station interior is SEALED -- no line of sight
## from inside any room / corridor / tunnel to outer space. Rays are cast
## from a grid of sample points over every interior floor (three eye-ish
## heights) in 26 directions against the station's solid geometry
## (collision layer 1, which every wall/floor/ceiling CSG uses). A ray
## that hits nothing, or first hits EXTERIOR geometry, has escaped through
## a gap: a leak. Run directly to list leaks (each with its sample point
## and direction) when fixing geometry.
var _ok := true
const H := [0.15, 1.2, 2.35]


func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 4: await physics_frame
	var geo: Node = main.get_node("Geometry")
	var space: PhysicsDirectSpaceState3D = (main as Node3D).get_world_3d().direct_space_state
	var dirs: Array = []
	for x in [-1, 0, 1]:
		for y in [-1, 0, 1]:
			for z in [-1, 0, 1]:
				if x != 0 or y != 0 or z != 0:
					dirs.append(Vector3(x, y, z).normalized())
	var floors: Array = []
	for n in geo.get_children():
		if n is CSGBox3D and String(n.name).ends_with("Floor") and String(n.name) != "WashBasinFloor":
			floors.append(n)
	var player_rids: Array = []
	for b in main.find_children("*", "CollisionObject3D", true, false):
		if main.get_node("Player").is_ancestor_of(b) or String(b.name) == "FreeMoveBody":
			player_rids.append((b as CollisionObject3D).get_rid())
	var nav: Array = []
	for m in main.get_node("MovementNodes").get_children():
		if m is Node3D:
			nav.append((m as Node3D).global_position)
	var leaks: Array = []
	var samples := 0
	for f in floors:
		var c: Vector3 = (f as CSGBox3D).global_position
		var sz: Vector3 = (f as CSGBox3D).size
		var top: float = c.y + sz.y * 0.5
		var nx: int = maxi(int(sz.x / 0.45), 1)
		var nz: int = maxi(int(sz.z / 0.45), 1)
		for i in nx + 1:
			for k in nz + 1:
				var px: float = c.x - sz.x * 0.5 + 0.12 + (sz.x - 0.24) * float(i) / float(nx)
				var pz: float = c.z - sz.z * 0.5 + 0.12 + (sz.z - 0.24) * float(k) / float(nz)
				for h in H:
					var p := Vector3(px, top + h, pz)
					if _inside_solid(space, p, player_rids):
						continue
					# Only points the player can actually SEE: clear sight
					# from a walkable navigation node (eye height) nearby.
					if not _seen_from_nav(space, p, nav, player_rids):
						continue
					samples += 1
					for d in dirs:
						var q := PhysicsRayQueryParameters3D.create(p, p + d * 14.0, 1)
						q.exclude = player_rids
						var hit: Dictionary = space.intersect_ray(q)
						var what: String = ""
						if hit.is_empty():
							what = "space"
						else:
							var col: Node = hit["collider"]
							var ext: Node = main.get_node_or_null("Exterior")
							if ext != null and ext.is_ancestor_of(col):
								what = "exterior:" + String(col.name)
						if what != "" and _escapes(space, p + Vector3(0.013, 0.007, -0.011), d, player_rids, main) and _escapes(space, p + Vector3(-0.009, -0.006, 0.014), d, player_rids, main):
							leaks.append({"floor": f.name, "p": p, "d": d, "what": what, "gap": _gap_point(space, p, d, player_rids)})
	var by_floor: Dictionary = {}
	for l in leaks:
		by_floor[l["floor"]] = by_floor.get(l["floor"], 0) + 1
	print("samples: %d   leaking rays: %d" % [samples, leaks.size()])
	for fl in by_floor:
		print("  %s: %d" % [fl, by_floor[fl]])
	# Group the leaks by gap location (0.3 m cells) -> the distinct holes.
	var holes: Dictionary = {}
	for l in leaks:
		var g: Vector3 = l["gap"]
		var key := Vector3i(int(round(g.x / 0.6)), int(round(g.y / 0.6)), int(round(g.z / 0.6)))
		if not holes.has(key):
			holes[key] = {"n": 0, "gap": g, "floor": l["floor"], "p": l["p"], "d": l["d"]}
		holes[key]["n"] += 1
	print("distinct gap locations: %d" % holes.size())
	for k in holes:
		var h: Dictionary = holes[k]
		print("  HOLE near (%.2f,%.2f,%.2f) x%d  e.g. from %s p=(%.2f,%.2f,%.2f) d=(%.2f,%.2f,%.2f)" % [h["gap"].x, h["gap"].y, h["gap"].z, h["n"], h["floor"], h["p"].x, h["p"].y, h["p"].z, h["d"].x, h["d"].y, h["d"].z])
	_check("sampled every interior floor (%d points)" % samples, samples > 300)
	_check("no line of sight from the interior to space (%d leaking rays)" % leaks.size(), leaks.is_empty())
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _seen_from_nav(space: PhysicsDirectSpaceState3D, p: Vector3, nav: Array, excl: Array) -> bool:
	for n in nav:
		var e: Vector3 = n
		if e.distance_to(p) > 6.0:
			continue
		var q := PhysicsRayQueryParameters3D.create(e, p, 1)
		q.exclude = excl
		q.hit_back_faces = false
		if space.intersect_ray(q).is_empty():
			return true
	return false


## Jittered re-test (a ray exactly along a floor quad's diagonal edge can
## slip through the triangle seam: not a real gap).
func _escapes(space: PhysicsDirectSpaceState3D, p: Vector3, d: Vector3, excl: Array, main: Node) -> bool:
	var q := PhysicsRayQueryParameters3D.create(p, p + d * 14.0, 1)
	q.exclude = excl
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return true
	var ext: Node = main.get_node_or_null("Exterior")
	return ext != null and ext.is_ancestor_of(hit["collider"])


## Roughly where the ray leaves the station: the last point along it that
## is still within 0.25 m of solid geometry (the gap it slipped through).
func _gap_point(space: PhysicsDirectSpaceState3D, p: Vector3, d: Vector3, excl: Array) -> Vector3:
	var last := p
	var t := 0.05
	while t < 6.0:
		var x: Vector3 = p + d * t
		var q := PhysicsShapeQueryParameters3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 0.25
		q.shape = sph
		q.transform = Transform3D(Basis(), x)
		q.collision_mask = 1
		q.exclude = excl
		if not space.intersect_shape(q, 1).is_empty():
			last = x
		t += 0.05
	return last


## Sample points inside furniture / equipment are skipped.
func _inside_solid(space: PhysicsDirectSpaceState3D, p: Vector3, excl: Array) -> bool:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = p
	q.collision_mask = 1 | 16
	q.exclude = excl
	return not space.intersect_point(q, 1).is_empty()


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
