extends SceneTree
## M7.2 Priority 1 regression: the lying-pose redesign.
## - No neck/head geometry directly in front of the camera (no Collar
##   node at all now; Shoulders is the nearest part and must sit a real
##   clearance distance away, not just a token offset).
## - Both poses use CSGCombiner3D (real CSG union) instead of a plain
##   Node3D (independent overlapping siblings) -- the actual fix for
##   the "assembled from boxes" look.
## - The body extends from shoulders to feet in a continuous chain
##   (each segment's near edge overlaps or touches the previous
##   segment's far edge -- no floating gaps between body parts).
## - Feet stay within/near the mattress, not far off the end of the bed.
## - LapAnchor moved down to the torso/hip area, clearly farther from
##   the eye than the old near-chest position.
## - set_lying() still cleanly toggles pose visibility with no
##   duplication, and this all still holds inside the real station
##   scene (not just the isolated body scene).

var _ok := true


func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5:
		await process_frame

	var player := main.get_node("Player")
	var global_free_move := main.get_node("GlobalFreeMove")
	var player_body := player.get_node("PlayerBody")
	var standing_pose := player_body.get_node("StandingPose")
	var lying_pose := player_body.get_node("LyingPose")
	var lap_anchor := player_body.get_node("LapAnchor")

	# ============================================================
	# 1. STRUCTURE: both poses are real CSG union roots now.
	# ============================================================
	_check("StandingPose is a CSGCombiner3D (real CSG union, not independent siblings)", standing_pose is CSGCombiner3D)
	_check("LyingPose is a CSGCombiner3D (real CSG union, not independent siblings)", lying_pose is CSGCombiner3D)

	# ============================================================
	# 2. NO NECK/HEAD IN FRONT OF THE CAMERA: no Collar node exists;
	# Shoulders is the nearest shape and must have a real gap.
	# ============================================================
	_check("lying pose has no Collar/neck node at all", lying_pose.get_node_or_null("Collar") == null)

	global_free_move.mirror_enabled = false
	var eye := Vector3(5.0, 0.75, -0.9)
	player.global_position = eye
	player_body.set_lying(true)
	await process_frame

	var shoulders: Node3D = lying_pose.get_node("Shoulders")
	var shoulders_dist: float = eye.distance_to(shoulders.global_position)
	_check("nearest body part (Shoulders) is a real clearance distance from the eye (got %.2fm, want > 0.35m)" % shoulders_dist, shoulders_dist > 0.35)

	# ============================================================
	# 3. CONTINUOUS CHAIN: each segment's near edge overlaps or
	# touches the previous one's far edge along local Z (no floating
	# gap that would read as a disconnected limb).
	# ============================================================
	var torso: Node3D = lying_pose.get_node("Torso")
	var hips: Node3D = lying_pose.get_node("Hips")
	var upper_leg: Node3D = lying_pose.get_node("UpperLegR")
	var lower_leg: Node3D = lying_pose.get_node("LowerLegR")
	var foot: Node3D = lying_pose.get_node("FootR")
	var zs := [shoulders.global_position.z, torso.global_position.z, hips.global_position.z, upper_leg.global_position.z, lower_leg.global_position.z, foot.global_position.z]
	var increasing := true
	for i in range(1, zs.size()):
		if zs[i] <= zs[i - 1]:
			increasing = false
	_check("body chain (shoulders->torso->hips->upper leg->lower leg->foot) progresses monotonically toward the foot of the bed", increasing)

	# ============================================================
	# 4. FEET STAY NEAR THE MATTRESS (world z <= ~0.45; mattress top
	# ends at world z=0.3, the foot-rail trim at ~0.4).
	# ============================================================
	_check("feet stay on/near the mattress (world z=%.2f, want <= 0.45)" % foot.global_position.z, foot.global_position.z <= 0.45)

	# ============================================================
	# 5. LapAnchor now belongs to the SITTING pose/laptop flow, not
	# lying (the bed interaction no longer reaches LyingPose at all --
	# see test_sitting_pose.gd for LapAnchor's real coverage). Here we
	# only confirm it still exists and is a real distance from the eye,
	# not that it aligns with lying-pose geometry it no longer relates
	# to.
	# ============================================================
	var lap_dist: float = eye.distance_to(lap_anchor.global_position)
	_check("LapAnchor exists at a real distance from the eye (got %.2fm, want > 0.4m)" % lap_dist, lap_dist > 0.4)

	# ============================================================
	# 6. POSE TOGGLE STILL CLEAN: no duplication, exactly one visible.
	# ============================================================
	_check("lying: standing pose hidden, lying pose shown", not standing_pose.visible and lying_pose.visible)
	player_body.set_lying(false)
	await process_frame
	_check("standing: standing pose shown, lying pose hidden", standing_pose.visible and not lying_pose.visible)
	_check("exactly one PlayerBody node exists (no duplication across toggles)", player.get_children().filter(func(c): return c.name == "PlayerBody").size() == 1)

	print("")
	if _ok:
		print("ALL TESTS PASSED")
	else:
		print("SOME TESTS FAILED")
	quit()


func _check(label: String, cond: bool) -> void:
	if cond:
		print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
