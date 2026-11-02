extends SceneTree
## Round 17 Priority 5 / Round 18 Priority 1 regression coverage for the
## Living Quarters wash-station mirror (scripts/interactables/mirror.gd)
## -- a live SubViewport reflection feed, same "a SubViewport is a real,
## continuously-updating texture" pattern as
## scripts/surveillance/surveillance_camera.gd, but with a Camera3D
## repositioned every frame to track the player across the mirror's own
## plane instead of sitting fixed.
##
## Headless rendering cannot verify PIXEL content (see
## test_electrical_repair_diorama.gd's own class doc comment on this
## project's general headless-vs-rendered split) -- actual visual
## verification (orientation, with asymmetric marker cubes specifically
## so a roughly-symmetric reflected body couldn't hide a flip; zoom
## behavior at multiple player distances) was performed via real
## --write-movie rendering this round and is documented in the Round 18
## final report, not re-derived here. This file covers what headless
## logic CAN prove: the feed texture exists and is wired onto the glass
## WITH the exact UV correction the render-verified fix needs (not just
## "some" texture); the mirror camera's position tracks the player's
## REAL lateral (X) and vertical (Y) position by the exact expected
## reflection math, not merely "some" response; and the HeadGroup
## render-layer gating that keeps the player's own first-person view
## headless while every other camera sees a full body.
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
	# Round 18 Priority 1: the exact UV correction render-verified with
	# asymmetric marker cubes (see the final report) -- both axes
	# flipped. Asserting the EXACT values, not just "a flip exists",
	# so a future edit that reintroduces only one of the two axis bugs
	# (e.g. someone "simplifies" this back to Round 17's X-only fix)
	# fails loudly here instead of waiting for another player report.
	# ============================================================
	var glass_mat: StandardMaterial3D = glass.material_override
	_check("glass material flips BOTH UV axes (the render-verified upside-down + left-right fix)", glass_mat.uv1_scale.is_equal_approx(Vector3(-1.0, -1.0, 1.0)))
	_check("glass material's UV offset compensates the flip (keeps the image on-screen, not off to one side)", glass_mat.uv1_offset.is_equal_approx(Vector3(1.0, 1.0, 0.0)))
	_check("glass material is unshaded (reads correctly regardless of local room lighting)", glass_mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)

	# ============================================================
	# The mirror camera must genuinely track the player by the EXACT
	# expected reflection math (not just "some" response): its own X
	# and Y must equal the glass's X/Y plus the player's own in-plane
	# offset from the glass's center -- proving _update_reflection()
	# runs every frame from the player's REAL position with the correct
	# formula, not a fixed authored pose or an approximate one.
	# ============================================================
	look_pivot.rotation.y = 0.0
	look_pivot._target_yaw = 0.0
	look_pivot.get_node("PitchPivot").rotation.x = 0.0

	var glass_pos: Vector3 = glass.global_position
	var probe_pos := Vector3(1.85, 1.72, 1.6)
	free_body.sync_to_eye_position(probe_pos)
	player.global_position = probe_pos
	for i in 3: await process_frame
	var expected_x: float = glass_pos.x + (probe_pos.x - glass_pos.x)
	var expected_y: float = glass_pos.y + (probe_pos.y - glass_pos.y)
	_check("mirror camera's X exactly matches the glass-plane reflection math for this player position", is_equal_approx(mirror_cam.global_position.x, expected_x))
	_check("mirror camera's Y exactly matches the glass-plane reflection math for this player position (the Round 18 upside-down fix's own axis)", is_equal_approx(mirror_cam.global_position.y, expected_y))

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

	# ============================================================
	# Round 19 Priority 1: the camera model was rebuilt around a genuine
	# off-axis (asymmetric-frustum) portal projection -- the virtual eye
	# now deliberately sits BEHIND the glass (see mirror.gd's own doc
	# comment on why: it looks back THROUGH the glass at the room, which
	# off-axis framing requires, and a solid single-sided CSGBox3D is
	# backface-culled from the inside so this doesn't actually occlude
	# anything). This is the OPPOSITE of the Round 18 approach (camera
	# held in front of the glass) -- asserting it explicitly so a future
	# edit that silently reverts to "in front" (plausible-looking, but
	# breaks the off-axis math entirely) fails loudly here.
	# ============================================================
	var plane_normal_for_test: Vector3 = -glass.global_transform.basis.z.normalized()
	_check("mirror camera's virtual eye sits BEHIND the glass (off-axis portal projection, not a camera floating in front)", (glass.global_position - mirror_cam.global_position).dot(plane_normal_for_test) > 0.0)
	_check("mirror camera uses an asymmetric (off-axis) frustum projection, not a plain symmetric one", mirror_cam.projection == Camera3D.PROJECTION_FRUSTUM)
	# Round 21 Priority 2: depth raised 0.4 -> 0.8 (see mirror.gd's own
	# doc comment) to narrow the effective FOV and reduce near-field
	# stretching -- the upper bound here widened to match; still well
	# under 1.0 (the near plane stays "small", not accidentally plain-
	# symmetric-camera-sized).
	_check("mirror camera's near plane distance is positive and small (the virtual eye's fixed depth behind the glass)", mirror_cam.near > 0.0 and mirror_cam.near < 1.0)
	_check("mirror camera's frustum vertical size matches the physical glass rectangle's full height", is_equal_approx(mirror_cam.size, 0.42))

	# The off-axis frustum's own asymmetry (frustum_offset) must shift
	# with the player's lateral position -- this is the actual mechanism
	# that produces real, oblique-angle-correct parallax (a FIXED offset
	# would mean the window is not responding to where the real viewer
	# stands at all).
	free_body.sync_to_eye_position(left_pos)
	player.global_position = left_pos
	for i in 3: await process_frame
	var offset_left: float = mirror_cam.frustum_offset.x
	free_body.sync_to_eye_position(right_pos)
	player.global_position = right_pos
	for i in 3: await process_frame
	var offset_right: float = mirror_cam.frustum_offset.x
	_check("mirror camera's off-axis frustum offset shifts when the player moves sideways (real window-style asymmetry, not a fixed frustum)", not is_equal_approx(offset_left, offset_right))

	# ============================================================
	# Round 19 Priority 1: camera ORIENTATION is now fixed to the
	# glass's own plane basis (a portal's viewing axis doesn't rotate
	# with the viewer -- only the frustum's asymmetry does), a deliberate
	# change from the player-gaze-reflecting orientation tried earlier
	# this round. Confirm it stays fixed even as the player turns their
	# head, so a future regression back to gaze-following orientation
	# (which double-counts with the off-axis offset) is caught here.
	# ============================================================
	var basis_before: Basis = mirror_cam.global_transform.basis
	look_pivot.rotation.y = 0.6
	look_pivot._target_yaw = 0.6
	for i in 3: await process_frame
	_check("mirror camera's orientation stays fixed to the glass plane regardless of player look direction (off-axis offset carries the viewpoint, not camera rotation)", mirror_cam.global_transform.basis.is_equal_approx(basis_before))
	look_pivot.rotation.y = 0.0
	look_pivot._target_yaw = 0.0
	for i in 3: await process_frame

	# ============================================================
	# Round 18 Priority 1 requirement #5: apparent zoom with distance.
	# The camera-to-player distance (what drives apparent size) must
	# shrink as the player approaches the glass and grow as they back
	# away -- render-verified visually in the final report; this proves
	# the same monotonic relationship holds analytically across a wider
	# sweep of positions than the two frames that were actually rendered.
	# ============================================================
	var distances: Array = []
	for z in [1.2, 1.5, 1.8, 2.1]:
		var p := Vector3(2.15, 1.6, z)
		free_body.sync_to_eye_position(p)
		player.global_position = p
		for i in 3: await process_frame
		distances.append(mirror_cam.global_position.distance_to(p))
	var monotonic: bool = true
	for i in range(1, distances.size()):
		if distances[i] >= distances[i - 1]:
			monotonic = false
	_check("camera-to-player distance shrinks monotonically as the player approaches the glass (zoom tracks distance)", monotonic)

	# ============================================================
	# HeadGroup render-layer gating: present (layers bit 2 only) and
	# excluded from the PLAYER's own camera cull_mask, included in every
	# other camera's default cull_mask (e.g. the mirror's own camera).
	# ============================================================
	var body: Node3D = player.get_node("PlayerBody")
	var head_group: Node3D = body.get_node("HeadGroup")
	_check("HeadGroup is on its own dedicated render layer (bit 3 / value 4), not the default layer 1", head_group.layers == 4)
	_check("player's own first-person camera excludes HeadGroup's layer", (cam.cull_mask & 4) == 0)
	_check("the mirror's own camera still sees HeadGroup's layer (4) -- only the first-person rig's layer is excluded, not this one", (mirror_cam.cull_mask & 4) != 0)
	_check("player's own camera still sees the watch rig's layer (2) -- a pre-existing, unrelated layer this change must not collide with", (cam.cull_mask & 2) != 0)
	_check("HeadGroup is visible while standing", head_group.visible)

	# ============================================================
	# Round 21 Priority 1: the mirror must NOT render the first-person
	# watch rig (first_person_watch_rig.tscn's ArmGroup/WatchAssembly,
	# layer 2) -- that rig is a plain child of the PLAYER's own
	# Camera3D, positioned at the eye point, meant for the player's own
	# first-person view only. Before this fix, the mirror's camera used
	# Camera3D's own default cull_mask (every layer), so it rendered
	# that rig too -- its own separate, never-upgraded, literally
	# skin-colored cylinder arm sitting right at the reflection's head/
	# chest position, which is what was actually being seen and
	# reported as "still looks like cylinders," not the (already
	# improved) world-body arm. See mirror.gd's own doc comment.
	# ============================================================
	_check("the mirror's own camera EXCLUDES the first-person watch rig's layer (2) -- that rig belongs to the player's own view only", (mirror_cam.cull_mask & 2) == 0)

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
