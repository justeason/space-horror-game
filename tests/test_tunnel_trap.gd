extends SceneTree
## Regression test for a real fall-through/wedge trap found at the
## Storage<->Engineering elbow connector (the turn joining
## StorageConnectorA and StorageConnectorB): the two existing floor
## slabs (StorageConnectorAFloor / StorageConnectorBFloor) didn't
## together cover the full L-shaped turn footprint, leaving two
## uncovered notches a player could step into -- one a bottomless
## fall-through, the other a wedge pocket the body settled into without
## being on a floor. Fixed by extending StorageConnectorASouthWall and
## StorageConnectorBWestWall to the true outer corner and adding
## StorageEngineeringElbowFloor/Ceiling to cover both notches.
##
## This is a DIFFERENT defect from the known, pre-existing
## engineering_b <-> storage_elbow_e capsule-sweep failure (a narrow
## direct-line clearance issue between those two exact MovementNode
## points, unaffected by this fix and still separately tracked by
## tests/test_station_capsule_sweep.gd) -- this test exercises two
## specific off-path corner positions near that same general area, not
## the node-to-node sweep itself.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var free_body := main.get_node("FreeMoveBody")
	var eb: Node3D = main.get_node("MovementNodes/EngineeringB")
	var se: Node3D = main.get_node("MovementNodes/StorageElbowE")
	free_body.set_active(true)

	var trap_points := [
		{"name": "outer corner (ConnectorA/B west notch)", "pos": Vector3(-7.25, 2.5, 4.65)},
		{"name": "inner corner (ConnectorA/B north notch)", "pos": Vector3(-6.42, 2.5, 6.0)},
	]

	for tp in trap_points:
		free_body.global_position = (tp["pos"] as Vector3) - Vector3(0, free_body.eye_height, 0)
		free_body.velocity = Vector3.ZERO
		var last_y: float = free_body.global_position.y
		var settled := false
		for step in range(180): # 3s at 60fps -- comfortably more than a ~2.5m fall needs
			await physics_frame
			var y: float = free_body.global_position.y
			if step > 10 and absf(y - last_y) < 0.001:
				settled = true
				break
			last_y = y
		_check("%s: settles (not an endless fall)" % tp["name"], settled)
		_check("%s: settles on a real floor" % tp["name"], free_body.is_on_floor())
		_check("%s: settles near floor level, not fallen through (y=%.2f)" % [tp["name"], free_body.global_position.y], absf(free_body.global_position.y) < 0.3)

		# Not just "landed somewhere" -- actually reachable back to
		# StorageElbowE, i.e. not walled into a pocket. Deliberately
		# stops at StorageElbowE rather than continuing on to
		# EngineeringB: that final leg IS the known, pre-existing
		# engineering_b <-> storage_elbow_e capsule-sweep failure
		# (narrow clearance, tracked separately by
		# tests/test_station_capsule_sweep.gd) -- a different condition
		# this fix does not touch, so it must not be required here.
		var capsule := CapsuleShape3D.new()
		capsule.radius = main.get_node("Player").player_clearance_radius
		capsule.height = main.get_node("Player").player_clearance_height
		var space_state := get_root().get_world_3d().direct_space_state
		var from_pos: Vector3 = free_body.global_position + Vector3(0, free_body.eye_height, 0)
		var to_pos: Vector3 = se.global_position
		# Disable the real body's own collision for the sweep query --
		# otherwise it collides with itself sitting right there (same
		# established pattern as test_station_capsule_sweep.gd).
		free_body.set_active(false)
		var blocked := false
		var dist: float = from_pos.distance_to(to_pos)
		var steps: int = max(2, int(ceil(dist / 0.15)) + 1)
		for i in range(steps + 1):
			var t: float = float(i) / float(steps)
			var pos: Vector3 = from_pos.lerp(to_pos, t)
			var params := PhysicsShapeQueryParameters3D.new()
			params.shape = capsule
			params.transform = Transform3D(Basis.IDENTITY, pos)
			params.collide_with_bodies = true
			var result := space_state.intersect_shape(params, 1)
			if not result.is_empty():
				blocked = true
				break
		_check("%s: a clear route exists back to StorageElbowE (not walled in)" % tp["name"], not blocked)
		free_body.set_active(true)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()

func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
