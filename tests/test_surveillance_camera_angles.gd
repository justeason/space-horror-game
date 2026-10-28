extends SceneTree
## Regression coverage for this round's surveillance camera pitch fix.
## All three cameras were previously aimed perfectly level (0 pitch)
## while mounted near the ceiling, which put the horizon at frame-center
## and filled roughly the top half of the feed with ceiling (player
## feedback). Deliberately checks DIRECTION, not exact angle constants
## (avoiding a brittle test tied to one specific tuning value): each
## camera must now look meaningfully downward, but not so steeply that
## it's effectively a straight-down shot, and must still face
## approximately the same horizontal direction it always did (same
## general area covered, not repointed somewhere else).
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var cams := {
		"CameraControlRoom": Vector3(0.7071068, 0, 0.7071068),
		"CameraCorridor": Vector3(0, 0, 1),
		"CameraCorridorEnd": Vector3(0, 0, -1),
	}

	for cam_name in cams.keys():
		var cam3d: Camera3D = main.get_node("Surveillance/%s/Camera3D" % cam_name)
		var forward: Vector3 = -cam3d.global_transform.basis.z
		var original_horizontal: Vector3 = cams[cam_name]

		_check("%s: pitched meaningfully downward (forward.y=%.3f)" % [cam_name, forward.y], forward.y < -0.15)
		_check("%s: not pointed almost straight down (forward.y=%.3f)" % [cam_name, forward.y], forward.y > -0.85)

		var horiz: Vector3 = Vector3(forward.x, 0, forward.z).normalized()
		var dot: float = horiz.dot(original_horizontal)
		_check("%s: still faces its original horizontal direction (dot=%.3f)" % [cam_name, dot], dot > 0.9)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()

func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
