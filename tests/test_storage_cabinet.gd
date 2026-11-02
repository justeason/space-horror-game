extends SceneTree
## Round 19 Priority 3 regression coverage: the Storage room's spare-
## parts locker (scripts/interactables/storage_cabinet.gd). Player
## feedback was that replacement parts "feel like they appear magically
## on countertops" -- investigation found WireComponent was ALREADY
## physically located in the Storage room (on Geometry/
## StorageRack1Shelf), but nothing enclosed it: it sat on an open shelf
## next to a solid decorative rack, directly raycast-hittable with no
## door, drawer, or opening ritual of any kind. StorageCabinet1 adds
## that missing layer -- a real hinged door that must be opened before
## the wire becomes visible or raycast-hittable at all, closed again
## the same way, with the contained item's own interact()/pickup logic
## (wire_component.gd) completely untouched.
##
## This specifically verifies the REAL raycast path (not just calling
## wire.interact() directly, which every other wire-related test here
## already does and which deliberately bypasses this gate, same as
## calling any object's own method directly always has in this
## project) -- a genuine PhysicsRayQueryParameters3D query aimed at the
## wire's own position, exactly what interaction_controller.gd's real
## click-to-interact path would resolve.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var cabinet: Node = main.get_node("Geometry/StorageCabinet1")
	var wire: Node3D = main.get_node("Interactables/WireComponent")
	var space_state := get_root().get_world_3d().direct_space_state

	_check("cabinet starts closed", not cabinet.is_open())
	_check("wire starts hidden (inside the closed cabinet)", not wire.visible)

	var eye: Vector3 = wire.global_position + Vector3(0.3, 0, 0)
	var query := PhysicsRayQueryParameters3D.create(eye, wire.global_position)
	var hit: Dictionary = space_state.intersect_ray(query)
	_check("a raycast aimed at the wire's position does NOT hit the wire while the cabinet is closed", hit.get("collider") != wire)

	cabinet.interact()
	await create_timer(0.7).timeout

	_check("cabinet reports open after interact()", cabinet.is_open())
	_check("wire becomes visible once the door is open", wire.visible)
	_check("get_interact_prompt() now offers to close it", cabinet.get_interact_prompt().findn("close") != -1)

	query = PhysicsRayQueryParameters3D.create(eye, wire.global_position)
	hit = space_state.intersect_ray(query)
	_check("a raycast aimed at the wire's position DOES hit the wire once the cabinet is open (the real interaction path)", hit.get("collider") == wire)

	# The wire's own pickup logic is completely untouched by the cabinet
	# -- picking it up through the normal path still works exactly as
	# every other wire-related test already proves, confirmed once more
	# here specifically through an opened cabinet.
	var carry := main.get_node("Player/CarrySystem")
	wire.interact()
	_check("wire can still be picked up normally once the cabinet is open", carry.is_carrying())

	# Closing the cabinet while the wire is OUT (already carried) must
	# not do anything destructive to the carried item -- the gating only
	# ever applies to the wire's OWN resting position inside the
	# cabinet, never to an item the player is already holding.
	cabinet.interact()
	await create_timer(0.7).timeout
	_check("cabinet reports closed again", not cabinet.is_open())
	_check("the carried wire is unaffected by closing the (now-empty) cabinet", carry.is_carrying())

	# A second open/close cycle doesn't desync or break anything.
	cabinet.interact()
	await create_timer(0.7).timeout
	cabinet.interact()
	await create_timer(0.7).timeout
	_check("repeated open/close cycles leave the cabinet closed and consistent", not cabinet.is_open())

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
