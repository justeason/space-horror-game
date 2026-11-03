extends SceneTree
## Round 25 Priority 5 coverage for the EXPERIMENTAL rigged technician
## (scenes/dev/rigged_technician_prototype.tscn) -- the staging step toward
## replacing PlayerBody's procedural visual with a Skeleton3D + skinned
## mesh. Asserts the migration-relevant contract, not the stand-in mesh's
## exact geometry: humanoid-profile bone names exist, the mesh really is
## skinned to the skeleton, the watch-inspection gesture is produced by
## bone ROTATIONS with limb lengths constant, the elbow genuinely flexes,
## the gesture is reversible, and the prototype is NOT wired into the game.
var _ok := true

func _init() -> void:
	var proto: Node3D = (load("res://scenes/dev/rigged_technician_prototype.tscn") as PackedScene).instantiate()
	get_root().add_child(proto)
	for i in 3: await process_frame
	var sk: Skeleton3D = proto.skeleton
	for b in ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand", "LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperLeg", "RightLowerLeg", "RightFoot", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot"]:
		_check("humanoid-profile bone exists: " + b, sk.find_bone(b) != -1)
	var mi: MeshInstance3D = proto.mesh_instance
	_check("technician mesh is skinned (has a Skin bound to the skeleton)", mi.skin != null and mi.get_node_or_null(mi.skeleton) == sk)
	var arrays: Array = mi.mesh.surface_get_arrays(0)
	_check("mesh carries per-vertex bone indices and weights", arrays[Mesh.ARRAY_BONES] != null and (arrays[Mesh.ARRAY_BONES] as PackedInt32Array).size() > 0)

	var rest_upper: float = proto.bone_global_position("RightUpperArm").distance_to(proto.bone_global_position("RightLowerArm"))
	var rest_fore: float = proto.bone_global_position("RightLowerArm").distance_to(proto.bone_global_position("RightHand"))
	var rest_angle: float = _elbow_angle(proto)
	_check("anthropometric upper arm (%.3f m in 0.28..0.34)" % rest_upper, rest_upper > 0.28 and rest_upper < 0.34)
	_check("anthropometric forearm (%.3f m in 0.22..0.28)" % rest_fore, rest_fore > 0.22 and rest_fore < 0.28)
	var hand_rest: Vector3 = proto.bone_global_position("RightHand")
	for p in [0.25, 0.5, 0.75, 1.0]:
		proto.set_watch_inspection(p)
		var up: float = proto.bone_global_position("RightUpperArm").distance_to(proto.bone_global_position("RightLowerArm"))
		var fo: float = proto.bone_global_position("RightLowerArm").distance_to(proto.bone_global_position("RightHand"))
		_check("p=%.2f limb lengths constant (upper %.4f, fore %.4f)" % [p, up, fo], absf(up - rest_upper) < 0.001 and absf(fo - rest_fore) < 0.001)
	var raised_angle: float = _elbow_angle(proto)
	_check("elbow genuinely flexes (interior %.0f -> %.0f deg)" % [rest_angle, raised_angle], rest_angle - raised_angle > 60.0)
	var wrist: Vector3 = proto.bone_global_position("RightHand")
	_check("wrist raised in front of the chest (%s)" % str(wrist.snapped(Vector3.ONE * 0.01)), wrist.y > 1.1 and wrist.z < -0.25)
	proto.set_watch_inspection(0.0)
	_check("gesture is reversible (hand back at rest)", proto.bone_global_position("RightHand").is_equal_approx(hand_rest))

	var main_text: String = FileAccess.get_file_as_string("res://scenes/main.tscn") + FileAccess.get_file_as_string("res://scenes/player.tscn")
	_check("prototype is NOT wired into the live game scenes", main_text.find("rigged_technician_prototype") == -1)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _elbow_angle(proto: Node3D) -> float:
	var s: Vector3 = proto.bone_global_position("RightUpperArm")
	var e: Vector3 = proto.bone_global_position("RightLowerArm")
	var w: Vector3 = proto.bone_global_position("RightHand")
	return rad_to_deg((s - e).angle_to(w - e))


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
