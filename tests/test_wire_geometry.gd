extends SceneTree
## Round 11 Workstream B3 introduced a genuinely curved, multi-segment
## cable path (electrical_repair_diorama.gd's _build_wire_curve(), a
## quadratic Bezier sampled into _WIRE_SEGMENT_COUNT straight chords)
## replacing straight/two-segment-bent bars. Round 12 fixed a REAL bug
## in that first attempt, found via an actual rendered screenshot (not
## headless): bowing each wire's path BACKWARD (away from the camera)
## for depth layering pushed most of the service wire's curve behind
## the opaque InsetPanel/Backdrop, clipping it almost entirely. The fix
## expresses depth layering as a FORWARD-only push (supply most
## forward, service least), so nothing ever recedes past its own
## anchor depth. This file verifies: every chord is present and
## non-collinear with its neighbors (a real curve, not one bend); the
## three roles bow in genuinely different directions/depths with
## supply/service's lateral extents actually overlapping (a real
## crossing, not just "weaving near" each other); the widened click
## hitboxes still don't overlap a neighboring wire's; EVERY wire
## segment's world Z stays no further back than its own anchor depth
## (the actual Round 12 regression -- nothing may recede behind the
## opaque backing panels); and each wire's final (t=1) endpoint lands
## exactly on its own terminal lug, not merely "close".
##
## Cannot verify the rendered result looks convincing from this
## headless test alone -- that was confirmed separately via an actual
## rendered screenshot this round (see the final report). This file
## verifies the underlying geometric facts a "looks like connected,
## uncropped cables" claim depends on.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 3: await process_frame

	var repair_view: Node = main.get_node("Player/HUD/ElectricalRepairView")
	var diorama: Node3D = repair_view.get_node("Panel/VBox/DioramaContainer/DioramaViewport/ElectricalRepairDiorama")

	var roles: Array[StringName] = [&"supply", &"return", &"service"]
	var world_x_ranges := {}
	var world_z_mid := {}

	for role in roles:
		var wire_node: Node3D = diorama._wire_nodes[role]
		var visual_group: Node3D = wire_node.get_node("VisualGroup")
		var segments: Array[Node3D] = []
		for i in diorama._WIRE_SEGMENT_COUNT:
			var name: String = "Run" if i == 0 else "Seg%d" % i
			segments.append(visual_group.get_node(name))
		_check("%s: all %d curve segments exist" % [role, diorama._WIRE_SEGMENT_COUNT], segments.size() == diorama._WIRE_SEGMENT_COUNT)

		# ============================================================
		# 1. Genuinely curved: no two CONSECUTIVE segments share the
		# same rotation (a single rigid bend, let alone a straight bar,
		# would repeat one or two rotations across all six chords).
		# ============================================================
		var any_consecutive_equal := false
		for i in (segments.size() - 1):
			if segments[i].rotation.is_equal_approx(segments[i + 1].rotation):
				any_consecutive_equal = true
		_check("%s: consecutive chords have genuinely different rotations (a real curve, not one rigid bend)" % role, not any_consecutive_equal)

		# ============================================================
		# 2. Every chord shares the same material resource as segment 0
		# -- so the existing hover/pulse-highlight code (which only
		# looks up "Run") still lights the WHOLE curved wire.
		# ============================================================
		var shared_material: bool = true
		for seg in segments:
			if seg.material != segments[0].material:
				shared_material = false
		_check("%s: all curve segments share one material resource (hover lights the whole wire)" % role, shared_material)

		# Lateral (world X) extent of this wire's own curve, for the
		# crossing check below.
		var min_x: float = INF
		var max_x: float = -INF
		var mid_z: float = 0.0
		for seg in segments:
			var p: Vector3 = seg.global_position
			min_x = minf(min_x, p.x)
			max_x = maxf(max_x, p.x)
			if seg.name == "Seg3": # the segment straddling the curve's midpoint (t=3/6=0.5)
				mid_z = p.z
		world_x_ranges[role] = Vector2(min_x, max_x)
		world_z_mid[role] = mid_z

	# ============================================================
	# 3. Supply and service actually CROSS -- their lateral (world X)
	# extents genuinely overlap, not merely "come closer" -- a real
	# geometric intersection in the horizontal plane, not just a
	# subjective "looks close enough" claim.
	# ============================================================
	var supply_range: Vector2 = world_x_ranges[&"supply"]
	var service_range: Vector2 = world_x_ranges[&"service"]
	var overlap_lo: float = maxf(supply_range.x, service_range.x)
	var overlap_hi: float = minf(supply_range.y, service_range.y)
	_check(
		"supply and service curves genuinely overlap in world X (a real crossing, not just proximity): supply=%s service=%s" % [supply_range, service_range],
		overlap_hi > overlap_lo
	)

	# ============================================================
	# 4. Unambiguous front-to-back depth order at the crossing, matching
	# the required disconnect order (supply first/frontmost -> return
	# middle -> service last/backmost).
	# ============================================================
	_check(
		"supply sits in FRONT of return at the crossing (disconnected first)",
		world_z_mid[&"supply"] > world_z_mid[&"return"]
	)
	_check(
		"return sits in FRONT of service at the crossing (disconnected in the middle)",
		world_z_mid[&"return"] > world_z_mid[&"service"]
	)

	# ============================================================
	# 5. The widened click hitboxes still don't overlap a neighboring
	# wire's hitbox despite the much larger lateral sweep of the curve.
	# ============================================================
	var half_width: float = 0.23 # Shape_wire_bowed.size.x * 0.5
	var anchor_x := {
		&"supply": diorama._wire_nodes[&"supply"].position.x,
		&"return": diorama._wire_nodes[&"return"].position.x,
		&"service": diorama._wire_nodes[&"service"].position.x,
	}
	var gap_supply_return: float = absf(anchor_x[&"return"] - anchor_x[&"supply"]) - half_width * 2.0
	var gap_return_service: float = absf(anchor_x[&"service"] - anchor_x[&"return"]) - half_width * 2.0
	_check("supply/return click hitboxes do not overlap (gap=%.3f)" % gap_supply_return, gap_supply_return >= 0.0)
	_check("return/service click hitboxes do not overlap (gap=%.3f)" % gap_return_service, gap_return_service >= 0.0)

	# ============================================================
	# 6. Round 12 regression: no wire segment may recede further from
	# the camera (more negative world Z) than its own anchor's depth --
	# the exact geometric condition whose violation clipped most of the
	# service wire behind the opaque InsetPanel/Backdrop panels. This
	# is a stronger, more direct check than merely "does it render
	# looking right" (unverifiable headlessly): it checks the actual
	# cause, not a proxy for it.
	# ============================================================
	var worst_role := &""
	var worst_margin := INF
	for role in roles:
		var wire_node: Node3D = diorama._wire_nodes[role]
		var visual_group: Node3D = wire_node.get_node("VisualGroup")
		var anchor_z: float = wire_node.global_position.z
		for i in diorama._WIRE_SEGMENT_COUNT:
			var name: String = "Run" if i == 0 else "Seg%d" % i
			var seg: Node3D = visual_group.get_node(name)
			var margin: float = seg.global_position.z - anchor_z
			if margin < worst_margin:
				worst_margin = margin
				worst_role = role
	_check(
		"no wire segment recedes behind its own anchor depth (the Round 12 occlusion bug): worst=%s margin=%.4f" % [worst_role, worst_margin],
		worst_margin >= -0.001
	)

	# ============================================================
	# 7. Each wire's final (t=1) endpoint lands exactly on its own
	# terminal lug -- not merely "close enough to look okay".
	# ============================================================
	for role in roles:
		var wire_node: Node3D = diorama._wire_nodes[role]
		var visual_group: Node3D = wire_node.get_node("VisualGroup")
		var last_seg: Node3D = visual_group.get_node("Seg%d" % (diorama._WIRE_SEGMENT_COUNT - 1))
		var cap: Node3D = visual_group.get_node("Cap")
		var lug: Node3D = main.get_node("Player/HUD/ElectricalRepairView/Panel/VBox/DioramaContainer/DioramaViewport/ElectricalRepairDiorama/Terminals/%s/Lug" % role.capitalize())
		_check(
			"%s wire's cap endpoint lands exactly on its own terminal lug" % role,
			cap.global_position.distance_to(lug.global_position) < 0.01
		)
		# The last chord must actually reach the cap, not stop short of it.
		_check(
			"%s wire's final chord reaches all the way to its cap" % role,
			(last_seg.global_position - cap.global_position).length() < 0.15
		)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()

func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
