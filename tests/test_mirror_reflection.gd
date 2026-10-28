extends SceneTree
## Round 17 Priority 5 regression coverage for the Living Quarters wash-
## station mirror (scripts/interactables/mirror.gd) -- a live SubViewport
## reflection feed, same "a SubViewport is a real, continuously-updating
## texture" pattern as scripts/surveillance/surveillance_camera.gd, but
## with a Camera3D repositioned every frame to track the player across
## the mirror's own plane instead of sitting fixed.
##
## Headless rendering cannot verify PIXEL content (see
## test_electrical_repair_diorama.gd's own class doc comment on this
## project's general headless-vs-rendered split) -- actual visual
## verification (the glass legibly shows a head/neck/shoulders silhouette
## that tracks the player, not a void or solid geometry) was performed
## via real --write-movie rendering this round and is documented in the
## final report, not re-derived here. This file covers what headless
## logic CAN prove: the feed texture exists and is wired onto the glass,
## the mirror camera's position/orientation responds correctly to the
## player moving to different lateral (X) positions in front of the
## glass (proving _update_reflection() is actually live, not a static
## pose), and the new HeadGroup node is genuinely absent from the
## player's own first-person camera's cull_mask while present on every
## other camera's default mask (the mechanism that keeps the player's
## own view headless while the mirror/other cameras see a full body).
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player: Node = main.get_node("Player")
	var free_body: Node = main.get_node("FreeMoveBody")
	free_body.set_active(false)
	var look_pivot: Node3D = player.get_node("LookPivot")
	var cam: Camera3D = look_pivot.get_node("PitchPivot/Camera3D")
	var mirror_vp: Node = main.get_node("Mirrors/LivingQuartersMirror")
	var mirror_cam: Camera3D = mirror_vp.get_node("Camera3D")
	var glass: GeometryInstance3D = main.get_node("Geometry/WashMirrorGlass")

	_check("mirror feed texture exists", mirror_vp.get_feed_texture() != null)
	_check("glass material_override uses the mirror's own feed texture", glass.material_override != null and glass.material_override.albedo_texture == mirror_vp.get_feed_texture())
	_check("mirror viewport renders continuously (not only when visible)", mirror_vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS)

	# ============================================================
	# The mirror camera must genuinely track the player: standing
	# slightly LEFT of the glass's own X should put the mirror camera on
	# the opposite lateral side from standing slightly RIGHT -- proving
	# _update_reflection() runs every frame from the player's REAL
	# position, not a fixed authored pose.
	# ============================================================
	look_pivot.rotation.y = 0.0
	look_pivot._target_yaw = 0.0
	look_pivot.get_node("PitchPivot").rotation.x = 0.0

	var left_pos := Vector3(1.9, 1.6, 1.6)
	free_body.sync_to_eye_position(left_pos)
	player.global_position = left_pos
	for i in 3: await process_frame
	var mirror_x_left: float = mirror_cam.global_position.x

	var right_pos := Vector3(2.4, 1.6, 1.6)
	free_body.sync_to_eye_position(right_pos)
	player.global_position = right_pos
	for i in 3: await process_frame
	var mirror_x_right: float = mirror_cam.global_position.x

	_check("mirror camera's own lateral position shifted when the player moved sideways", not is_equal_approx(mirror_x_left, mirror_x_right))
	_check("mirror camera stays on the correct (same) lateral side as the player (tracks, not inverts)", mirror_x_left < mirror_x_right)

	_check("mirror camera always stays in front of the glass, never behind it (see honest-limitation doc comment)", mirror_cam.global_position.z < glass.global_position.z)

	# ============================================================
	# HeadGroup render-layer gating: present (layers bit 2 only) and
	# excluded from the PLAYER's own camera cull_mask, included in every
	# other camera's default cull_mask (e.g. the mirror's own camera).
	# ============================================================
	var body: Node3D = player.get_node("PlayerBody")
	var head_group: Node3D = body.get_node("HeadGroup")
	_check("HeadGroup is on its own dedicated render layer (bit 3 / value 4), not the default layer 1", head_group.layers == 4)
	_check("player's own first-person camera excludes HeadGroup's layer", (cam.cull_mask & 4) == 0)
	_check("the mirror's own camera uses the default cull_mask (sees every layer)", (mirror_cam.cull_mask & 4) != 0)
	_check("player's own camera still sees the watch rig's layer (2) -- a pre-existing, unrelated layer this change must not collide with", (cam.cull_mask & 2) != 0)
	_check("HeadGroup is visible while standing", head_group.visible)

	main.queue_free()
	await process_frame
	await create_timer(0.2).timeout

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
