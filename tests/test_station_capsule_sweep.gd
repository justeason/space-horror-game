extends SceneTree
## Whole-station navigation regression: sweeps the real player capsule
## (scripts/player/movement_controller.gd's player_clearance_radius /
## player_clearance_height -- see free_move_controller.gd's class doc
## comment, which explicitly documents these two exports as "a short
## torso-band used only by the authoring-time navigation validation" and
## free_move_controller.gd's set_active(), which explicitly documents
## disabling its own collision "so... navigation validation's capsule
## sweeps... could collide with at rest" -- this test is exactly that
## established, designed-for use case) along every edge of the station's
## MovementNode graph (scripts/navigation/movement_node.gd): both
## explicit `neighbors` links and same-`region` pairs (region siblings
## are documented as "mutually, directly reachable... in addition to
## whatever is listed in neighbors").
##
## A small number of known pre-existing clearance failures (narrow
## elbows -- see MILESTONE1_DESIGN.md Part 1.2) are expected and are
## reported separately below, NOT as new regressions. Any additional
## blocked edge found here that is not in that known list is a real
## regression and fails this test.

var _ok := true

## Edges already known, independently of this task, to fail this sweep
## at narrow elbows (MILESTONE1_DESIGN.md Part 1.2: "5 edges fail that
## sweep today"). Stored as sorted node_id pairs so direction doesn't
## matter. Any edge in this set that passes is fine (an improvement, not
## a failure); any edge NOT in this set that fails is a new regression.
var _known_failures: Array[Array] = [
	["comms_a", "comms_window"],
	["comms_a", "comms_alcove"],
	["junction_node_1", "comms_tunnel_elbow"],
	["engineering_tunnel_1", "engineering_a"],
	["engineering_b", "storage_elbow_e"],
]


func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5:
		await process_frame

	var free_body := main.get_node("FreeMoveBody")
	var movement_controller := main.get_node("Player")
	free_body.set_active(false)
	await process_frame

	var capsule := CapsuleShape3D.new()
	capsule.radius = movement_controller.player_clearance_radius
	capsule.height = movement_controller.player_clearance_height

	var nodes_root := main.get_node("MovementNodes")
	var all_nodes: Array[Node3D] = []
	for child in nodes_root.get_children():
		if child.has_method("get_neighbor_nodes"):
			all_nodes.append(child)

	_check("graph has a reasonable number of nodes", all_nodes.size() > 10)

	# Build the undirected edge set: explicit neighbor links + same-region
	# pairs, deduplicated by sorted node_id.
	var edges := {} # key: "id_a|id_b" (sorted) -> [Node3D, Node3D]
	for node in all_nodes:
		for neighbor in node.get_neighbor_nodes():
			_add_edge(edges, node, neighbor)
		for mate in node.get_region_mates():
			_add_edge(edges, node, mate)

	_check("graph has a reasonable number of edges", edges.size() > 10)

	var space_state := get_root().get_world_3d().direct_space_state
	var new_regressions: Array[String] = []
	var known_failures_seen: Array[String] = []
	var cleared_known_failures: Array[String] = []

	for key in edges.keys():
		var pair: Array = edges[key]
		var a: Node3D = pair[0]
		var b: Node3D = pair[1]
		var blocked := _sweep_blocked(space_state, capsule, a.global_position, b.global_position)
		var id_pair := [a.node_id, b.node_id]
		id_pair.sort()
		var is_known := _is_known_failure(id_pair)
		if blocked and is_known:
			known_failures_seen.append("%s <-> %s" % [a.node_id, b.node_id])
		elif blocked and not is_known:
			new_regressions.append("%s <-> %s" % [a.node_id, b.node_id])
		elif not blocked and is_known:
			cleared_known_failures.append("%s <-> %s" % [a.node_id, b.node_id])

	print("Edges swept: ", edges.size())
	print("Known pre-existing failures still present: ", known_failures_seen.size())
	for e in known_failures_seen:
		print("  (known) ", e)
	if not cleared_known_failures.is_empty():
		print("Known failures that now pass (improvement, not a failure): ", cleared_known_failures.size())
		for e in cleared_known_failures:
			print("  (cleared) ", e)
	print("New regressions: ", new_regressions.size())
	for e in new_regressions:
		print("  (NEW) ", e)

	_check("no new navigation regressions beyond the known baseline", new_regressions.is_empty())

	print("")
	if _ok:
		print("ALL TESTS PASSED")
	else:
		print("SOME TESTS FAILED")
	quit()


func _add_edge(edges: Dictionary, a: Node3D, b: Node3D) -> void:
	if a == b:
		return
	var ids := [a.node_id, b.node_id]
	ids.sort()
	var key: String = "%s|%s" % [ids[0], ids[1]]
	if not edges.has(key):
		edges[key] = [a, b]


func _is_known_failure(sorted_id_pair: Array) -> bool:
	for pair in _known_failures:
		var known := pair.duplicate()
		known.sort()
		if known[0] == sorted_id_pair[0] and known[1] == sorted_id_pair[1]:
			return true
	return false


## Samples the capsule at evenly spaced points along the straight segment
## from `from_pos` to `to_pos` (~0.15m apart) and checks each for
## collision with level geometry. Blocked if ANY sample collides.
func _sweep_blocked(space_state: PhysicsDirectSpaceState3D, capsule: CapsuleShape3D, from_pos: Vector3, to_pos: Vector3) -> bool:
	var dist: float = from_pos.distance_to(to_pos)
	var steps: int = max(2, int(ceil(dist / 0.15)) + 1)
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var pos: Vector3 = from_pos.lerp(to_pos, t)
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = capsule
		params.transform = Transform3D(Basis.IDENTITY, pos)
		params.collide_with_bodies = true
		params.collide_with_areas = false
		var result := space_state.intersect_shape(params, 1)
		if not result.is_empty():
			return true
	return false


func _check(label: String, cond: bool) -> void:
	if cond:
		print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
