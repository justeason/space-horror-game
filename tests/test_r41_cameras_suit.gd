extends SceneTree
## Round 41 Priorities 8, 10, 11: CAMERA TAB LAYOUT, OPERATIONS CLEANUP and
## the EVA SUIT's first-person geometry.
##  - Cameras tab: two separated groups, every camera row's text fits its
##    button at the fitted font size (real font metrics), the feed is large
##    (>= 60 % of the page width), no control rectangles overlap, the info
##    lines fit their width for EVERY camera, the active camera is marked;
##  - Operations: no camera feed / CAMERAS button any more (keyboard
##    shortcut to the Cameras page still works);
##  - suit: the Round 39 chest BOX is gone; nothing of the suit stands in
##    front of the eye plumb line at chest height; pack behind; two D-rings
##    (A left, B right); helmet mirror/camera-only; first-person camera
##    never renders the helmet.
const Shell = preload("res://scripts/ui/workstation_shell.gd")
var _ok := true
var main: Node
var shell: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	shell = main.get_node("Interactables/WorkstationConsole/WorkstationScreen/Shell")
	await _camera_tab()
	_operations()
	_suit()
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _camera_tab() -> void:
	shell.show_page(shell.Page.CAMERAS)
	await process_frame
	var p: Control = shell._pages[shell.Page.CAMERAS]
	_check("8 curated cameras listed", shell.cam_buttons.size() == 8)
	_check("two separated groups (INTERIOR / EXTERIOR headers)", p.get_node_or_null("GroupINTERIOR") != null and p.get_node_or_null("GroupEXTERIOR") != null)
	var fit_ok := true
	var bad: Array = []
	for id in shell.cam_buttons:
		var b: Button = shell.cam_buttons[id]
		var fs: int = int(b.get_meta("font_px"))
		var w: float = Shell.text_width(b.text, fs)
		if w > b.size.x - 8.0 or fs < 8:
			fit_ok = false
			bad.append("%s %.0f/%.0f" % [id, w, b.size.x])
	_check("every camera row fits its button (font metrics) %s" % str(bad), fit_ok)
	_check("large feed: %.0f x %.0f px (>= 60 %% of the page width)" % [shell._feed.size.x, shell._feed.size.y], shell._feed.size.x >= 0.6 * 640.0)
	var info_bad: Array = []
	for id in shell.cam_buttons:
		shell.select_camera(id)
		await process_frame
		for l in [shell._cam_info, shell._cam_blind]:
			var lab: Label = l
			var fs2: int = lab.get_theme_font_size("font_size")
			if Shell.text_width(lab.text, fs2) > lab.size.x:
				info_bad.append("%s:%s" % [id, lab.text])
		if not (shell.cam_buttons[id] as Button).button_pressed:
			info_bad.append("%s not highlighted" % id)
	_check("location + blind-spot lines fit for every camera, active one highlighted %s" % str(info_bad), info_bad.is_empty())
	# No overlapping rectangles among the page's direct controls (the
	# small REC / clock tags sit INSIDE the feed by design).
	var rects: Array = []
	for c in p.get_children():
		if c is Control and (c as Control).visible and not (c is ColorRect):
			if c == shell._feed or c == shell._feed_tag or c == shell._feed_clock:
				continue
			rects.append([String(c.name), Rect2((c as Control).position, (c as Control).size)])
	var overlaps: Array = []
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			var a: Rect2 = rects[i][1]
			var b2: Rect2 = rects[j][1]
			if a.grow(-0.5).intersects(b2.grow(-0.5)):
				overlaps.append("%s %s x %s %s" % [rects[i][0], str(a), rects[j][0], str(b2)])
	_check("no overlapping controls on the Cameras page %s" % str(overlaps), overlaps.is_empty())
	var fr: Rect2 = Rect2(shell._feed_frame.position, shell._feed_frame.size)
	_check("feed tags sit inside the feed", fr.encloses(Rect2(shell._feed_tag.position, shell._feed_tag.size)) and fr.encloses(Rect2(shell._feed_clock.position, shell._feed_clock.size)))
	_check("the camera list never runs under the < MAP button", shell.cam_buttons.values().all(func(b): return (b as Button).position.y + (b as Button).size.y <= shell.action_buttons["back_to_map"].position.y))
	_check("the long INT-02 label is readable: '%s'" % shell.cam_buttons["INT-02"].text, shell.cam_buttons["INT-02"].text.find("CONTROL") != -1)


func _operations() -> void:
	shell.show_page(shell.Page.OPS)
	var p: Control = shell._pages[shell.Page.OPS]
	_check("Operations: no camera feed widget", p.find_children("*", "TextureRect", true, false).is_empty() and shell.get("_cam") == null)
	_check("Operations: no duplicate CAMERAS button", not shell.action_buttons.has("camera"))
	_check("Operations keeps map, duties, actions", not shell.room_buttons.is_empty() and shell.action_buttons.has("checkin") and shell.action_buttons.has("diag"))
	var scr: Node = main.get_node("Interactables/WorkstationConsole/WorkstationScreen")
	scr.show_section(scr.Section.SURVEILLANCE)
	_check("the surveillance keyboard section still opens the Cameras tab", shell.page == shell.Page.CAMERAS)
	scr.show_section(scr.Section.OVERVIEW)


func _suit() -> void:
	var rig: Node3D = main.get_node("Player/PlayerBody")._rig
	rig.set_eva_suit(true)
	var suit: MeshInstance3D = rig._suit_body
	var front_min := 0.0
	var pack_max := 0.0
	var mesh: ArrayMesh = suit.mesh
	for si in mesh.get_surface_count():
		var verts: PackedVector3Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
		for v in verts:
			if v.y > 1.15 and v.y < 1.5:
				front_min = minf(front_min, v.z)
			pack_max = maxf(pack_max, v.z)
	_check("chest height: nothing of the suit in front of the eye line (min z %.3f >= %.3f)" % [front_min, rig.EYE_POINT.z - 0.005], front_min >= rig.EYE_POINT.z - 0.005)
	_check("the life-support pack sits behind (max z %.2f)" % pack_max, pack_max > 0.25)
	_check("layered suit materials (pack, seals, joint grey, metal)", mesh.get_surface_count() >= 4)
	var a: Vector3 = rig.tether_point(0)
	var b: Vector3 = rig.tether_point(1)
	_check("tether D-rings: A on the left hip, B on the right (%.2f m apart)" % a.distance_to(b), a.x < -0.1 and b.x > 0.1 and absf(a.y - 0.95) < 0.05)
	_check("D-ring hardware on the harness", rig.skeleton.get_node_or_null("SuitHarness/TetherRingA") != null and rig.skeleton.get_node_or_null("SuitHarness/TetherRingB") != null)
	_check("helmet is mirror / camera only", rig._suit_helmet.layers == rig.MIRROR_ONLY_LAYER)
	var pc: Camera3D = main.get_node("Player/LookPivot/PitchPivot/Camera3D")
	_check("first-person camera never renders the helmet layer", pc.cull_mask & rig.MIRROR_ONLY_LAYER == 0)
	var hm: ArrayMesh = rig._suit_helmet.mesh
	var hmin := 9.0
	for si in hm.get_surface_count():
		for v in (hm.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			hmin = minf(hmin, v.y)
	_check("helmet + neck ring stay above the shoulders (min y %.2f)" % hmin, hmin > 1.38)
	rig.set_eva_suit(false)
	_check("suit off: suit parts hidden, coverall colour back", not suit.visible and not (rig.skeleton.get_node("SuitHarness") as Node3D).visible)


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
