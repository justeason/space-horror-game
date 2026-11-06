extends SceneTree
## Round 31 Priority 5A: substantial furniture blocks the player's body.
## Before this round the furniture contact layer (furniture_contact.gd)
## only stopped dropped parts -- the player capsule (mask 1) walked straight
## through the desk, wash counter, console desk and locker. The capsule now
## collides with that layer (mask 1 | 4); navigation sweeps already queried
## it (baseline unchanged). Real W input, real physics.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame
	var player: Node3D = main.get_node("Player")
	var fb: CharacterBody3D = main.get_node("FreeMoveBody")
	var lp: Node3D = player.get_node("LookPivot")
	_check("player capsule collides with the furniture layer", (fb.collision_mask & 4) != 0 and (fb.collision_mask & 1) != 0)
	# [name, start eye, facing, axis ("x"/"z"), furniture face coordinate, sign of approach]
	var scen := [
		["living desk (beside the stool)", Vector3(3.25, 1.6, 1.15), Vector3(0, 0, 1), "z", 1.92, 1.0],
		["stool", Vector3(3.8, 1.6, 1.0), Vector3(0, 0, 1), "z", 1.6, 1.0],
		["wash counter", Vector3(2.1, 1.6, 1.15), Vector3(0, 0, 1), "z", 1.87, 1.0],
		["console desk", Vector3(-0.5, 1.6, 0.3), Vector3(0, 0, -1), "z", -0.6, -1.0],
		["locker", Vector3(4.2, 1.6, 1.7), Vector3(1, 0, 0), "x", 4.87, 1.0],
	]
	for sc in scen:
		fb.sync_to_eye_position(sc[1])
		var f: Vector3 = (sc[2] as Vector3).normalized()
		lp.rotation.y = atan2(-f.x, -f.z) - player.rotation.y
		lp._target_yaw = lp.rotation.y
		for i in 10: await physics_frame
		var ev := InputEventKey.new()
		ev.keycode = KEY_W
		ev.physical_keycode = KEY_W
		ev.pressed = true
		Input.parse_input_event(ev)
		for i in 110: await physics_frame
		var up := InputEventKey.new()
		up.keycode = KEY_W
		up.physical_keycode = KEY_W
		up.pressed = false
		Input.parse_input_event(up)
		for i in 10: await physics_frame
		var c: float = fb.global_position.x if sc[3] == "x" else fb.global_position.z
		var gap: float = ((sc[4] as float) - c) * (sc[5] as float)   # capsule centre -> furniture face
		_check("%s: the player is stopped at the furniture (capsule centre %.2f m from its face, radius 0.30)" % [sc[0], gap], gap > 0.25 and gap < 0.45)
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
