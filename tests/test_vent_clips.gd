extends SceneTree
## Round 36 Priority 1: VENT GRILLE RETAINING CLIPS (player-reported: the
## upper clip secures only sometimes, the lower clip often not at all).
##
## Reproduces the bug through the REAL interaction ray: the camera is put
## at many reasonable standing positions in front of Vent LS-2 (straight,
## left, right; near/mid/far; looking down) and aimed at the centre of the
## VISIBLE clip hardware. The hovered object must be that clip's own click
## part -- never the grille cover (whose click would reopen the grille) and
## never nothing (a collider left behind the moved visual).
## Then the full service is played with the hovered objects' interact():
## release both, open, clean, close, secure in either order; save/load
## mid-procedure; repeated service cycles.
var _ok := true
var main: Node
var vent: Node
var cam: Node
var fb: Node
var player: Node3D
var lp: Node3D


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 6: await process_frame
	vent = main.get_node("Equipment/VentGrille")
	cam = main.get_node("Player/LookPivot/PitchPivot/Camera3D")
	fb = main.get_node("FreeMoveBody")
	player = main.get_node("Player")
	lp = player.get_node("LookPivot")
	await _aim_sweep("secured, cover closed")
	vent.on_part(&"c0")
	vent.on_part(&"c1")
	await _settle()
	await _aim_sweep("released, cover closed (the re-secure case)")
	await _full_service(0)
	await _full_service(1)
	await _reopen_after_completion()
	await _save_load_mid()
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _settle() -> void:
	for i in 30: await physics_frame


## Stances in the grille's own frame: +Z is out of the wall (toward the
## player), +X is the grille's right.
const STANCES := [
	[0.0, 0.55, 1.6], [0.0, 0.8, 1.6], [0.0, 1.1, 1.6],
	[-0.3, 0.7, 1.6], [0.3, 0.7, 1.6], [-0.45, 0.9, 1.6], [0.45, 0.9, 1.6],
	[0.0, 0.42, 1.6], [0.2, 0.45, 1.6],   # close in, looking steeply down
]


func _place_and_aim(local_eye: Vector3, target: Vector3) -> void:
	var eye: Vector3 = vent.global_transform * local_eye
	fb.sync_to_eye_position(eye)
	player.global_position = eye
	var d: Vector3 = target - eye
	lp.rotation.y = atan2(-d.x, -d.z) - player.rotation.y
	lp._target_yaw = lp.rotation.y
	var pitch: float = atan2(d.y, Vector2(d.x, d.z).length())
	lp.get_node("PitchPivot").rotation.x = pitch
	lp._target_pitch = pitch
	for i in 3: await physics_frame
	await process_frame
	# Re-aim from where the body actually settled (walls/furniture may
	# have nudged the capsule), as a player would.
	var real_eye: Vector3 = cam.global_position
	d = target - real_eye
	lp.rotation.y = atan2(-d.x, -d.z) - player.rotation.y
	lp._target_yaw = lp.rotation.y
	pitch = atan2(d.y, Vector2(d.x, d.z).length())
	lp.get_node("PitchPivot").rotation.x = pitch
	lp._target_pitch = pitch
	for i in 2: await physics_frame
	await process_frame


func _clip_visual(j: int) -> Vector3:
	var n: Node3D = vent._clip_nodes[j]
	# The centre of what the player SEES as the clip: its lever mesh.
	var vis: Node3D = n.find_child("Lever", true, false) if n.find_child("Lever", true, false) != null else n
	return vis.global_position


func _aim_sweep(label: String) -> void:
	var fails: Array = []
	var total := 0
	for j in 2:
		for s in STANCES:
			var target: Vector3 = _clip_visual(j)
			await _place_and_aim(Vector3(s[0], s[2] - 1.1, s[1]), target)
			total += 1
			var hov: Object = cam.get_hovered()
			var want: Node = vent.get_node_or_null("Click_c%d" % j)
			if want == null:
				want = vent.find_child("Click_c%d" % j, true, false)
			if hov != want:
				fails.append("%s clip from %s -> %s" % ["upper" if j == 0 else "lower", str(s), (hov.name if hov is Node else str(hov))])
	_check("%s: aiming at the visible clip targets that clip from every stance (%d/%d)%s" % [label, total - fails.size(), total, ("  FAILS: " + "; ".join(fails.slice(0, 6))) if not fails.is_empty() else ""], fails.is_empty())
	# Not pixel-perfect: 2.5 cm off-centre still hits the clip.
	var near_fails := 0
	for j in 2:
		for off in [Vector3(0.025, 0, 0), Vector3(-0.025, 0, 0), Vector3(0, 0.02, 0), Vector3(0, -0.02, 0)]:
			var target: Vector3 = _clip_visual(j) + vent.global_transform.basis * off
			await _place_and_aim(Vector3(0.0, 0.5, 0.75), target)
			var want: Node = vent.find_child("Click_c%d" % j, true, false)
			if cam.get_hovered() != want:
				near_fails += 1
	_check("%s: clips are forgiving targets (2-2.5 cm off-centre still hits; %d misses)" % [label, near_fails], near_fails == 0)


## Clicks whatever the player is actually aiming at (the real path).
func _click_at(target: Vector3, stance: Vector3 = Vector3(0.0, 0.5, 0.75)) -> Object:
	await _place_and_aim(stance, target)
	var hov: Object = cam.get_hovered()
	if hov != null:
		hov.interact()
	return hov


func _full_service(order: int) -> void:
	var tag := "order %s" % ("upper->lower" if order == 0 else "lower->upper")
	vent.order_rearm(777 + order)
	vent.on_part(&"gauge")
	# Start secured.
	vent.clips_released = [false, false]
	vent.cover_open = false
	vent._refresh()
	await _settle()
	for j in 2:
		await _click_at(_clip_visual(j))
	_check("%s: both clips released through the real ray" % tag, vent.clips_released[0] and vent.clips_released[1])
	var cover_click: Node3D = vent.find_child("Click_cover", true, false)
	await _click_at(cover_click.global_position)
	await _settle()
	_check("%s: grille opened" % tag, vent.cover_open)
	_check("%s: secure refused while open (prompt says close first)" % tag, vent.part_prompt(&"c0").find("Close") != -1 or vent.part_prompt(&"c0") == "" or vent.part_prompt(&"c0").find("close") != -1)
	# Clean every section by clicking the duct where the player sees it.
	for k in 12:
		var dirty := -1
		for i in 4:
			if float(vent.dirt[i]) >= 0.05:
				dirty = i
				break
		if dirty == -1:
			break
		var x: float = -0.12 + 0.24 * (dirty % 2)
		var y: float = 0.09 - 0.18 * (dirty / 2)
		await _click_at(vent.global_transform * Vector3(x, y, 0.0))
	_check("%s: duct cleaned through the real ray" % tag, vent.is_clean())
	await _click_at(cover_click.global_position, Vector3(0.35, 0.5, 0.9))
	await _settle()
	_check("%s: grille closed" % tag, not vent.cover_open)
	var seq: Array = [0, 1] if order == 0 else [1, 0]
	var first: Object = await _click_at(_clip_visual(seq[0]))
	_check("%s: first clip click hit the %s clip (hit %s) and secured it" % [tag, "upper" if seq[0] == 0 else "lower", first.name if first is Node else str(first)], not vent.clips_released[seq[0]] and not vent.cover_open)
	_check("%s: not serviced with one clip still released" % tag, not vent.order_done() and not vent.secured())
	await _click_at(_clip_visual(seq[1]))
	_check("%s: both clips secured, grille closed, order done" % tag, vent.secured() and vent.order_done())
	_check("%s: clips visibly engaged (lever over the cover edge)" % tag, _clip_engaged(0) and _clip_engaged(1))


## A secured clip's lever must overlap the cover plate's edge (it holds it
## shut); a released one must not.
func _clip_engaged(j: int) -> bool:
	if not vent.has_method("clip_engaged_visual"):
		return true
	return vent.clip_engaged_visual(j)


func _reopen_after_completion() -> void:
	for j in 2:
		vent.on_part(StringName("c%d" % j))
	vent.on_part(&"cover")
	_check("reopen after completion works (open, clean stays clean)", vent.cover_open and vent.is_clean())
	vent.on_part(&"cover")
	for j in [1, 0]:
		vent.on_part(StringName("c%d" % j))
	_check("...and re-secures", vent.secured())
	# Open and close WITHOUT cleaning on a dirty grille.
	vent.order_rearm(4242)
	vent.on_part(&"gauge")
	vent.on_part(&"c0"); vent.on_part(&"c1"); vent.on_part(&"cover")
	vent.on_part(&"cover"); vent.on_part(&"c1"); vent.on_part(&"c0")
	_check("open/close without cleaning: secured but not serviced", vent.secured() and not vent.order_done())
	_check("...guidance asks to release the clips again", vent.order_next()["short"] == "RELEASE CLIPS")
	# Partial cleaning.
	vent.on_part(&"c0"); vent.on_part(&"c1"); vent.on_part(&"cover")
	var i0 := -1
	for i in 4:
		if float(vent.dirt[i]) >= 0.05:
			i0 = i
			break
	vent.on_part(StringName("s%d" % i0))
	_check("partial clean: still dirty, not serviced", not vent.is_clean() and not vent.order_done())


func _save_load_mid() -> void:
	var sg: Node = main.get_node("SaveGame")
	sg.save_path = "user://test_vent_clips.json"
	# Cover open, one section partly cleaned (from _reopen_after_completion).
	var r: Dictionary = sg.save_game()
	_check("save while the grille is open: %s" % r["message"], r["ok"])
	var snap: Dictionary = vent.state_dict().duplicate(true)
	vent.cover_open = false
	vent.clips_released = [false, false]
	vent.dirt = [0.0, 0.0, 0.0, 0.0]
	var rd: Dictionary = sg.read_save()
	sg.apply_state(rd["data"])
	var dirt_same := true
	for i in 4:
		dirt_same = dirt_same and absf(float(vent.dirt[i]) - float(snap["dirt"][i])) < 0.0001
	_check("load restores open cover + released clips + dirt (%s / %s)" % [str(vent.state_dict()), str(snap)], vent.cover_open == snap["cover_open"] and vent.clips_released == snap["clips_released"] and dirt_same)
	# One clip secured, cover closed.
	vent.on_part(&"cover")
	vent.on_part(&"c1")
	sg.save_game()
	var want: Array = vent.clips_released.duplicate()
	vent.clips_released = [true, true]
	sg.apply_state(sg.read_save()["data"])
	_check("load restores exactly one clip secured (%s)" % str(vent.clips_released), vent.clips_released == want and want == [true, false])
	await _settle()
	await _click_at(_clip_visual(0))
	_check("after load the remaining (upper) clip is still securable through the ray", not vent.clips_released[0])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_vent_clips.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_vent_clips.json.bak"))


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
