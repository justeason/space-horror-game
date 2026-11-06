extends SceneTree
## Round 20 Priority 4 regression coverage: the Life Support filter
## cartridge's own storage cabinet (StorageCabinet2) -- mirrors
## test_storage_cabinet.gd's coverage of the electrical wire's cabinet,
## for the second, independent carryable item this round adds. Confirms
## the door gate (closed = hidden/non-raycastable, open = visible/
## raycastable) works identically for this second cabinet instance,
## and that the two cabinets/items are genuinely independent (opening
## one does not affect the other).
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var cabinet: Node = main.get_node("Geometry/StorageCabinet2")
	var cartridge: Node3D = main.get_node("Interactables/FilterCartridge")
	var other_cabinet: Node = main.get_node("Geometry/StorageCabinet1")
	var wire: Node3D = main.get_node("Interactables/WireComponent")
	var space_state := get_root().get_world_3d().direct_space_state

	_check("cabinet2 starts closed", not cabinet.is_open())
	_check("filter cartridge starts hidden (inside the closed cabinet)", not cartridge.visible)

	var eye: Vector3 = cartridge.global_position + Vector3(-0.3, 0, 0)
	var query := PhysicsRayQueryParameters3D.create(eye, cartridge.global_position)
	var hit: Dictionary = space_state.intersect_ray(query)
	_check("a raycast aimed at the cartridge does NOT hit it while cabinet2 is closed", hit.get("collider") != cartridge)

	cabinet.interact()
	await create_timer(0.7).timeout

	_check("cabinet2 reports open after interact()", cabinet.is_open())
	_check("filter cartridge becomes visible once cabinet2 is open", cartridge.visible)
	_check("cabinet1 (wire's own cabinet) is unaffected -- still closed", not other_cabinet.is_open())
	_check("wire is unaffected -- still hidden", not wire.visible)

	query = PhysicsRayQueryParameters3D.create(eye, cartridge.global_position)
	hit = space_state.intersect_ray(query)
	_check("a raycast aimed at the cartridge DOES hit it once cabinet2 is open", hit.get("collider") == cartridge)

	var carry := main.get_node("Player/CarrySystem")
	cartridge.interact()
	await create_timer(0.7).timeout  # Round 31: the hand owns the part only at the grasp
	_check("filter cartridge can be picked up normally once cabinet2 is open", carry.is_carrying() and carry.carried_item_id() == &"filter_cartridge")

	cabinet.interact()
	await create_timer(0.7).timeout
	_check("cabinet2 reports closed again", not cabinet.is_open())
	_check("the carried cartridge is unaffected by closing the (now-empty) cabinet", carry.is_carrying())

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
