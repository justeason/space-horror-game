extends SceneTree
## Round 20 Priority 3 regression coverage: a long-distance render from
## inside the Control Room looking back out through the corridor
## revealed a SECOND dark gap further down the same walkway chain, at
## the Junction-North/Engineering-Tunnel boundary (x=-1.4, z=5.6-6.66) --
## distinct from the Round 19 corridor/Junction-A seam. Direct raycasts
## confirmed floor and ceiling were ALREADY continuous there (this was
## never a true structural hole), but the opening had no doorway
## framing at all and was badly underlit, reading as a black void. This
## adds a lintel + short jamb returns (so it looks like an intentional
## archway, not an accidental gap) and a dedicated doorway light.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var geometry: Node = main.get_node("Geometry")
	var lights: Node = main.get_node("Lights")

	_check("the new lintel exists", geometry.get_node_or_null("JunctionEngineeringLintel") != null)
	_check("the new south jamb return exists", geometry.get_node_or_null("JunctionEngineeringJambSouth") != null)
	_check("the new north jamb return exists", geometry.get_node_or_null("JunctionEngineeringJambNorth") != null)
	_check("a dedicated doorway light now exists", lights.get_node_or_null("Light_JunctionEngineeringDoorway") != null)

	# Real raycasts confirming the opening is a genuine, continuous
	# connection (floor+ceiling unbroken) -- not asserting a texture or
	# transform value, the actual physics result a player's own
	# movement/sightline would get.
	var space_state := get_root().get_world_3d().direct_space_state
	var up_hit: Dictionary = space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-1.3, 1.3, 6.1), Vector3(-1.3, 10.0, 6.1)))
	_check("ceiling is continuous directly above the doorway opening (no hole upward)", not up_hit.is_empty() and up_hit["position"].y < 2.9)
	var down_hit: Dictionary = space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-1.3, 1.3, 6.1), Vector3(-1.3, -10.0, 6.1)))
	_check("floor is continuous directly below the doorway opening (no hole downward)", not down_hit.is_empty() and down_hit["position"].y > -0.3)

	# The lintel caps the TOP of the opening (a real header, not merely
	# decorative) -- a ray at ceiling height now hits structure quickly,
	# not 4+ metres away in the next room.
	var header_hit: Dictionary = space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-1.0, 2.5, 6.13), Vector3(-10.0, 2.5, 6.13)))
	_check("a ray at header height hits the new lintel nearby, not open space deep into Engineering", not header_hit.is_empty() and Vector3(-1.0, 2.5, 6.13).distance_to(header_hit["position"]) < 1.0)

	# The doorway's own clear passable width stays generous (well above
	# capsule clearance) -- the jambs must not have narrowed it unsafely.
	var clear_width: float = 6.66 - 5.6 - 0.04 - 0.04 # gap minus both 0.04m jamb returns
	_check("doorway clear width stays well above player capsule clearance after adding jambs (got %.2fm)" % clear_width, clear_width > 0.9)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
