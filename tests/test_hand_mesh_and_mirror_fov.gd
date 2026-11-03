extends SceneTree
## Round 20 Priority 1/2 regression coverage:
## 1. The mirror's off-axis near-plane depth no longer produces a
##    fisheye-level field of view (the actual confirmed cause of
##    "stretched, elongated, skewed" -- see mirror.gd's own doc comment
##    on _VIRTUAL_EYE_DEPTH_BEHIND_GLASS), and the SubViewport's own
##    aspect ratio now exactly matches the physical glass rectangle's.
## 2. The world-body and first-person hands are built from genuine
##    lofted MeshInstance3D tubes (hand_mesh_builder.gd), not CSG
##    sphere+cylinder+sphere chains -- the literal "looks like several
##    cylinders connected together" complaint.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	# ============================================================
	# 1. Mirror FOV / aspect.
	# ============================================================
	var mirror_vp: Node = main.get_node("Mirrors/LivingQuartersMirror")
	var glass: GeometryInstance3D = main.get_node("Geometry/WashMirrorGlass")
	_check("mirror SubViewport's aspect ratio matches the physical glass rectangle's own aspect ratio (no texture-stretch mismatch)", is_equal_approx(float(mirror_vp.size.x) / float(mirror_vp.size.y), glass.size.x / glass.size.y))

	var player: Node = main.get_node("Player")
	var free_body: Node = main.get_node("FreeMoveBody")
	free_body.set_active(false)
	var look_pivot: Node3D = player.get_node("LookPivot")
	look_pivot.rotation.y = 0.0
	look_pivot._target_yaw = 0.0
	var probe_pos := Vector3(2.15, 1.6, 1.6)
	free_body.sync_to_eye_position(probe_pos)
	player.global_position = probe_pos
	for i in 5: await process_frame

	var mirror_cam: Camera3D = mirror_vp.get_node("Camera3D")
	# Half-vertical-FOV = atan((size/2) / near). A fisheye-level frustum
	# (the Round 19 bug: ~77 deg half-angle at depth=0.05) must not
	# recur -- assert a normal, camera-like half-angle instead (roughly
	# 15-40 degrees is a believable photographic range; the old bug's
	# 77 degrees is nowhere near this band).
	var half_angle_deg: float = rad_to_deg(atan((mirror_cam.size * 0.5) / mirror_cam.near))
	_check("mirror frustum's effective half-angle is a normal, photographic field of view, not fisheye (got %.1f deg, want < 45 deg)" % half_angle_deg, half_angle_deg < 45.0)
	_check("mirror frustum's effective half-angle is not absurdly narrow either (got %.1f deg, want > 10 deg)" % half_angle_deg, half_angle_deg > 10.0)

	# ============================================================
	# 2. Hand mesh architecture: genuine lofted tubes, not CSG chains.
	# ============================================================
	var player_body: Node3D = main.get_node("Player/PlayerBody")
	var hand_r: Node3D = player_body.get_node("StandingPose/HandR")
	_check("world-body hand has no leftover CSG knuckle-sphere nodes (old architecture)", hand_r.get_node_or_null("KnuckleIndex") == null)
	var finger_index: Node = hand_r.get_node_or_null("FingerIndex")
	_check("world-body hand has a single FingerIndex mesh node (new lofted-tube architecture)", finger_index != null)
	_check("FingerIndex is a real MeshInstance3D with actual geometry (not a CSG primitive)", finger_index is MeshInstance3D and finger_index.mesh != null)
	var finger_mesh: ArrayMesh = finger_index.mesh
	_check("the finger mesh has multiple surfaces worth of real triangle geometry (a lofted tube, not a single box/sphere primitive)", finger_mesh.get_surface_count() > 0 and finger_mesh.surface_get_array_len(0) > 50)
	var thumb: Node = hand_r.get_node_or_null("Thumb")
	_check("world-body hand has a single Thumb mesh node, separately articulated from the fingers", thumb != null and thumb is MeshInstance3D)

	var watch_rig: Node = player.find_child("FirstPersonWatchRig", true, false)
	var arm_group: Node3D = watch_rig.get_node("ArmGroup")
	_check("first-person rig has no leftover CSG KnuckleIndex node (old architecture)", arm_group.get_node_or_null("KnuckleIndex") == null)
	var fp_finger: Node = arm_group.get_node_or_null("FingerIndex")
	_check("first-person rig has a single FingerIndex mesh node (shares the same new architecture as the world body)", fp_finger != null and fp_finger is MeshInstance3D)
	var fp_thumb: Node = arm_group.get_node_or_null("Thumb")
	_check("first-person rig has a single Thumb mesh node", fp_thumb != null and fp_thumb is MeshInstance3D)

	# ============================================================
	# Round 21 Priority 1 regression: the first-person rig's own
	# render layer (2, set on ArmGroup/WatchAssembly) must ALSO be set
	# explicitly on every non-CSG VisualInstance3D child -- a
	# CSGCombiner3D's `layers` only covers CSGShape3D children folded
	# into its own combined render instance; a plain MeshInstance3D or
	# Label3D child renders as its own independent VisualInstance3D
	# with layers defaulting to 1 unless set. Confirmed by render: the
	# finger/thumb meshes and the watch face text silently leaked onto
	# the default layer and appeared in the mirror (and any other non-
	# player camera) even after excluding layer 2 from its cull_mask,
	# which is the actual root cause behind "the reflected hand still
	# looks wrong" -- see mirror.gd's own doc comment.
	# ============================================================
	_check("first-person rig's FingerIndex is on the rig's own layer (2), not leaking onto the default layer", fp_finger.layers == 2)
	_check("first-person rig's Thumb is on the rig's own layer (2), not leaking onto the default layer", fp_thumb.layers == 2)
	var fp_watch_text: Node = arm_group.find_child("WatchFaceText", true, false)
	_check("first-person rig's WatchFaceText is on the rig's own layer (2), not leaking onto the default layer", fp_watch_text != null and fp_watch_text.layers == 2)

	# ============================================================
	# Round 21 Priority 1: the mirror camera must exclude the first-
	# person rig's layer entirely -- that rig is a child of the
	# PLAYER'S OWN Camera3D, positioned at the eye point, meant for the
	# player's own first-person view only. Without this, the mirror
	# renders that separate (and, before this round, unimproved) rig
	# instead of (or on top of) the real world-body arm this round's
	# work actually went into.
	# ============================================================
	_check("the mirror camera excludes the first-person watch rig's layer (2)", (mirror_cam.cull_mask & 2) == 0)

	# ============================================================
	# Round 21 Priority 1: the world-body arm (StandingPose/SittingPose
	# x L/R) is now a single lofted MeshInstance3D per arm (ArmMeshL/R),
	# not three separate CSG primitives (UpperArm cylinder + Elbow
	# sphere + LowerArm cylinder) unioned together -- the literal "still
	# looks like a bunch of cylinders" complaint, now fixed for the ARM
	# the same way Round 20 already fixed the fingers.
	# ============================================================
	var standing_pose: Node3D = player_body.get_node("StandingPose")
	var arm_mesh_r: Node = standing_pose.get_node_or_null("ArmMeshR")
	_check("world body has a single ArmMeshR lofted-tube node (new architecture)", arm_mesh_r != null and arm_mesh_r is MeshInstance3D and arm_mesh_r.mesh != null)
	_check("the old UpperArmR CSG primitive is hidden (geometry replaced, not duplicated)", not standing_pose.get_node("UpperArmR").visible)
	_check("the old ElbowR CSG primitive is hidden (geometry replaced, not duplicated)", not standing_pose.get_node("ElbowR").visible)
	_check("the old LowerArmR CSG primitive is hidden (geometry replaced, not duplicated)", not standing_pose.get_node("LowerArmR").visible)

	# ============================================================
	# Round 21 Priority 1: the wristwatch must move WITH the hand when
	# the arm raises (it is now a CHILD of HandR, not a sibling fixed at
	# a pose-root-relative position -- see player_body.gd's own doc
	# comment on why the old sibling placement was the actual cause of
	# "the watch looks floating/clipped").
	# ============================================================
	var hand_r_node: Node3D = standing_pose.get_node("HandR")
	var wrist_watch: Node = hand_r_node.get_node_or_null("WristWatch")
	_check("the world-body wristwatch is a CHILD of HandR (moves with the hand), not a sibling fixed in pose-root space", wrist_watch != null)
	if wrist_watch != null:
		var watch_before: Vector3 = wrist_watch.global_position
		# Round 25: the standing hand's REST orientation is now neutral
		# (palm toward the thigh, see player_body.gd's
		# _setup_watch_raise_rig()), so "back to rest" means back to this
		# captured quaternion, not literally identity.
		var hand_rest_quat: Quaternion = hand_r_node.quaternion
		player_body.set_watch_raise_pose(true, 0.01)
		for i in 10: await process_frame
		var watch_after: Vector3 = wrist_watch.global_position
		_check("the wristwatch's world position actually moves when the arm raises (was previously stuck in place)", watch_before.distance_to(watch_after) > 0.05)

		# ============================================================
		# Round 23 Priority 3 regression: set_watch_raise_pose() used to
		# tween ONLY each arm joint's position -- HandR (and therefore
		# the rigid Palm/fingers/WristWatch it parents) kept its REST
		# rotation even once dragged up near the chest, so the hand/
		# watch assembly pointed the same direction it does hanging at
		# the side instead of following the raised forearm -- the
		# actual root cause of "the raised watch pose looks awkward".
		# Fixed by rotating HandR to the forearm's new direction
		# (shortest-arc quaternion from the rest Elbow->Hand direction
		# to the raised one). Confirms the rotation actually changed,
		# not just the position.
		# ============================================================
		_check("HandR's rotation actually changes when the arm raises, not just its position (the fix for the awkward-looking raised pose)", not hand_r_node.quaternion.is_equal_approx(hand_rest_quat))

		player_body.set_watch_raise_pose(false, 0.01)
		for i in 10: await process_frame
		_check("HandR's rotation returns to its rest orientation once the arm lowers back to rest", hand_r_node.quaternion.is_equal_approx(hand_rest_quat))

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
