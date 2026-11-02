extends SceneTree
## Round 23 Priority 1 regression coverage: player feedback was "cabinet
## doors must open outward in a sensible way, the current inward-
## opening behavior does not make sense." Root cause (confirmed by
## computing the actual swept rotation, not guessed): both cabinets'
## door_open_degrees had the wrong sign for their hinge position, so
## the door swung AWAY from the room and back into the cabinet's own
## recess/the solid wall behind it -- never visible as a real opening
## door from the player's side. Fixed by flipping both signs
## (StorageCabinet1: -110 -> +110, StorageCabinet2: +110 -> -110,
## mirrored because the two cabinets sit on opposite walls). This
## confirms the actual swept door panel ends up on the ROOM side of its
## own hinge, not swung back past the cabinet's own back wall.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var geometry: Node = main.get_node("Geometry")

	# Cabinet1 (west wall): room is toward +X from the hinge; the back
	# wall sits at a more-negative X than the hinge. A correctly
	# outward-swinging door's far tip must end up at a GREATER x than
	# the hinge itself (into the room), never less (back into the
	# recess/wall).
	var cab1 := geometry.get_node("StorageCabinet1")
	var hinge1: Node3D = geometry.get_node("StorageCabinet1/DoorHinge")
	var panel1: Node3D = geometry.get_node("StorageCabinet1/DoorHinge/DoorPanel")
	var back1: Node3D = geometry.get_node("StorageCabinet1/Back")
	var hinge1_x: float = hinge1.global_position.x
	cab1.interact()
	await create_timer(0.7).timeout
	var tip1_x: float = panel1.global_position.x + panel1.global_transform.basis.z.x * (panel1.size.z * 0.5)
	_check("cabinet1 reports open", cab1.is_open())
	_check("cabinet1's open door tip swings toward the room (x=%.2f) rather than back past its own hinge (x=%.2f)" % [tip1_x, hinge1_x], tip1_x > hinge1_x)
	_check("cabinet1's open door tip does not swing back past its own back wall (x=%.2f vs back x=%.2f)" % [tip1_x, back1.global_position.x], tip1_x > back1.global_position.x)
	cab1.interact()
	await create_timer(0.7).timeout

	# Cabinet2 (east wall): mirrored -- room is toward -X from the
	# hinge, so a correctly outward-swinging door's tip must end up at
	# a SMALLER x than the hinge.
	var cab2 := geometry.get_node("StorageCabinet2")
	var hinge2: Node3D = geometry.get_node("StorageCabinet2/DoorHinge")
	var panel2: Node3D = geometry.get_node("StorageCabinet2/DoorHinge/DoorPanel")
	var back2: Node3D = geometry.get_node("StorageCabinet2/Back")
	var hinge2_x: float = hinge2.global_position.x
	cab2.interact()
	await create_timer(0.7).timeout
	var tip2_x: float = panel2.global_position.x + panel2.global_transform.basis.z.x * (panel2.size.z * 0.5)
	_check("cabinet2 reports open", cab2.is_open())
	_check("cabinet2's open door tip swings toward the room (x=%.2f) rather than back past its own hinge (x=%.2f)" % [tip2_x, hinge2_x], tip2_x < hinge2_x)
	_check("cabinet2's open door tip does not swing back past its own back wall (x=%.2f vs back x=%.2f)" % [tip2_x, back2.global_position.x], tip2_x < back2.global_position.x)
	cab2.interact()
	await create_timer(0.7).timeout

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
