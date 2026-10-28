extends SceneTree
## Sitting-pose bed/laptop/editor flow test (supersedes the old
## lying-pose version of this test): the dedicated SittingPose (not
## LyingPose) swap, the camera yaw/pitch snap into a seated orientation
## that matches where the frozen body/laptop actually are, the single
## reparented laptop (open/close/return-to-rest, no duplication), the
## LAPTOP vs EDITING split (free-look-enabled viewing AND editing
## alike), the editor zoom-in/zoom-out transition, the soft focus-assist
## return and its mouse-interrupt, the log rendered entirely on the
## laptop's physical SubViewport screen, Esc/Ctrl+S editor controls, and
## rejection of invalid/repeated transitions.

var _ok := true


func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5:
		await process_frame

	var player := main.get_node("Player")
	var sleep_state := main.get_node("SleepState")
	var bunk := main.get_node("Interactables/Bunk")
	var bunkside_laptop := main.get_node("Interactables/BunksideLaptop")
	var player_body := player.get_node("PlayerBody")
	var standing_pose := player_body.get_node("StandingPose")
	var sitting_pose := player_body.get_node("SittingPose")
	var lap_anchor := player_body.get_node("LapAnchor")
	var log_screen := player.get_node("LaptopView/SessionLogScreen")
	var laptop_view := player.get_node("LaptopView")
	var prompt := player.get_node("HUD/PromptLabel")
	var look_controller := player.get_node("LookPivot")
	var camera := player.get_node("LookPivot/PitchPivot/Camera3D")
	var pitch_pivot := player.get_node("LookPivot/PitchPivot")
	var free_body := main.get_node("FreeMoveBody")

	# bunk.interact() requires proximity -- move the free body too, or
	# GlobalFreeMove's per-physics-tick mirror undoes a plain
	# Player.global_position assignment on the very next tick.
	free_body.sync_to_eye_position(Vector3(bunk.global_position.x - 1.0, 1.6, bunk.global_position.z))
	player.global_position = Vector3(bunk.global_position.x - 1.0, 1.6, bunk.global_position.z)
	# Start facing an arbitrary, deliberately "wrong" direction, so the
	# sit-down camera-yaw snap (see player_body.gd's
	# sitting_world_yaw_degrees) is actually exercised, not vacuously
	# true because the player happened to already face the right way.
	look_controller.rotation.y = deg_to_rad(137.0)
	look_controller._target_yaw = look_controller.rotation.y
	await process_frame

	# ============================================================
	# 0. BODY: exactly one PlayerBody, standing pose at boot.
	# ============================================================
	_check("body: exactly one PlayerBody under Player", player.get_children().filter(func(c): return c.name == "PlayerBody").size() == 1)
	_check("body: standing pose visible at boot", standing_pose.visible)
	_check("body: sitting pose hidden at boot", not sitting_pose.visible)

	# ============================================================
	# 1. SIT DOWN -> pose swap, camera yaw/pitch snap to match the
	# frozen seated body (not a teleport -- this runs over
	# transition_duration via the same tween as the position move).
	# ============================================================
	bunk.interact()
	await create_timer(1.6).timeout
	_check("body: sitting pose visible after settling onto the bed", sitting_pose.visible)
	_check("body: standing pose hidden while sitting", not standing_pose.visible)
	_check("pitch: settled sitting pitch is a shallow downward glance, not staring at the ceiling -- got %.1f deg" % rad_to_deg(pitch_pivot.rotation.x), rad_to_deg(pitch_pivot.rotation.x) < 0.0 and rad_to_deg(pitch_pivot.rotation.x) > -30.0)
	_check("yaw: camera eased to face the same direction the frozen seated body faces, not left at the pre-sit 137 deg -- got %.1f deg" % rad_to_deg(wrapf(look_controller.rotation.y, -PI, PI)), absf(wrapf(look_controller.rotation.y, -PI, PI)) < 1.0)
	_check("yaw: look_controller's own _target_yaw was updated too (won't drift back next frame)", absf(wrapf(look_controller._target_yaw - look_controller.rotation.y, -PI, PI)) < 0.01)

	var foot_r_world: Vector3 = sitting_pose.get_node("FootR").global_position
	var hips_world: Vector3 = sitting_pose.get_node("Hips").global_position
	_check("sitting: hips sit above the mattress top (~0.58), not sunk into it -- got y=%.2f" % hips_world.y, hips_world.y > 0.58)
	_check("sitting: feet rest at mattress height, not floating or sunk -- got y=%.2f" % foot_r_world.y, absf(foot_r_world.y - 0.62) < 0.05)

	_check("prompt: shows get-up/laptop prompt while sitting", prompt.visible and prompt.text.find("Get Up") != -1 and prompt.text.find("Laptop") != -1)
	_check("laptop: still resting near the bed, not yet picked up", bunkside_laptop.get_parent().name == "Interactables")

	# ============================================================
	# 2. OPEN THE LAPTOP -- single reparented instance, free-look stays
	# ENABLED, focus-assist armed at the lap anchor, screen recognizable
	# but not huge (ordinary laptop-on-lap framing, not the editor zoom).
	# ============================================================
	_send_key(KEY_F)
	await create_timer(0.6).timeout
	_check("laptop: F key opens the laptop while sitting", sleep_state.is_laptop_open())
	_check("laptop: reparented onto the lap anchor (no duplicate instance)", bunkside_laptop.get_parent() == lap_anchor)
	_check("laptop: open after the pickup+hinge animation settles", bunkside_laptop.is_open)
	_check("laptop: free-look stays enabled while just viewing it", look_controller.input_enabled)
	_check("laptop: soft focus-assist armed", look_controller.focus_assist_enabled)
	# focus_target_point/the screen-aim are only finalized once the
	# hinge has ALSO finished opening (see open_laptop()'s comment on
	# why the screen position isn't final right when the pickup tween
	# alone settles) -- wait for that too before checking.
	await create_timer(0.8).timeout
	# Target is the SCREEN now, not the lap anchor -- aiming the idle
	# focus-assist at the low anchor required an extreme ~62 degree
	# pitch in practice, putting the torso dead-center; the screen sits
	# higher (the open hinge tilts it toward the face) and is also the
	# thing actually worth looking at. See sleep_state.gd's open_laptop().
	_check("laptop: focus target is the screen's position", look_controller.focus_target_point.distance_to(laptop_view.get_screen_global_position()) < 0.02)
	_check("prompt: shows edit/close prompt", prompt.text.find("Edit Log") != -1 and prompt.text.find("Close Laptop") != -1)

	var screen_pos: Vector3 = laptop_view.get_screen_global_position()
	var ordinary_dist: float = camera.global_position.distance_to(screen_pos)
	_check("laptop: ordinary viewing distance to the screen is recognizable-but-not-huge (got %.2fm, want 0.3-1.0m)" % ordinary_dist, ordinary_dist > 0.3 and ordinary_dist < 1.0)

	# ============================================================
	# 3. LOOK AWAY, then let the soft return ease back, then interrupt
	# the return by moving the mouse again.
	# ============================================================
	var yaw_before_look_away: float = look_controller._target_yaw
	look_controller._target_yaw += 2.0 # simulate glancing toward the room
	look_controller._focus_idle_time = 0.0
	await process_frame
	var yaw_after_look_away: float = look_controller._target_yaw
	_check("look-away: look target changed", absf(yaw_after_look_away - yaw_before_look_away) > 0.05)

	await create_timer(1.6).timeout # longer than focus_assist_idle_delay (1.2s default)
	var yaw_after_idle: float = look_controller._target_yaw
	_check("soft-return: after idle, the view eased back toward the laptop (yaw moved back from the look-away value)", absf(yaw_after_idle - yaw_after_look_away) > 0.02)

	look_controller._target_yaw += 2.0
	look_controller._focus_idle_time = 0.0
	var yaw_right_after_interrupt: float = look_controller._target_yaw
	await process_frame
	_check("soft-return: a fresh interrupt is not immediately overridden by the ease", absf(look_controller._target_yaw - yaw_right_after_interrupt) < 0.01)

	# ============================================================
	# 4. E gets the player up directly from LAPTOP, then re-enter for
	# the rest of this flow (dedicated get-up-from-every-state coverage
	# lives in test_get_up_from_any_state.gd).
	# ============================================================
	_send_key(KEY_E)
	await create_timer(2.6).timeout
	_check("E from LAPTOP gets the player up", not sleep_state.is_sitting())
	bunk.interact()
	await create_timer(1.6).timeout
	_send_key(KEY_F)
	await create_timer(0.6).timeout
	_check("precondition: back in LAPTOP for the rest of this test", sleep_state.is_laptop_open() and not sleep_state.is_editing())

	# ============================================================
	# 5. EDIT THE LOG: T key enters EDITING and eases the camera INTO
	# the editor zoom (closer to the screen than the ordinary laptop
	# view) -- not a teleport, and free-look/focus-assist stay exactly
	# as they were.
	# ============================================================
	var pos_before_zoom: Vector3 = camera.global_position
	_send_key(KEY_T)
	await create_timer(0.05).timeout
	_check("editing: T key enters EDITING from LAPTOP", sleep_state.is_editing())
	# Mid-tween: not yet at the final zoomed position, not still at the
	# starting position either -- this is a real eased transition.
	var mid_zoom_pos: Vector3 = camera.global_position
	_check("editing: zoom is mid-transition shortly after pressing T, not an instant jump", mid_zoom_pos.distance_to(pos_before_zoom) > 0.001 and mid_zoom_pos.distance_to(pos_before_zoom) < pos_before_zoom.distance_to(screen_pos))

	await create_timer(0.6).timeout
	var zoomed_dist: float = camera.global_position.distance_to(screen_pos)
	_check("editing: zoom settled meaningfully closer to the screen than the ordinary laptop view (got %.2fm vs ordinary %.2fm)" % [zoomed_dist, ordinary_dist], zoomed_dist < ordinary_dist * 0.75)
	_check("editing: mouse-look is LOCKED while editing (current design: camera stays exactly on the screen)", not look_controller.input_enabled)
	# EDITING now explicitly DISABLES focus-assist (the actual fix for
	# the "camera reverses toward the body shortly after zooming in"
	# bug -- the idle system, still targeting ordinary-viewing framing,
	# was fighting the editor's own screen-aim). See sleep_state.gd's
	# begin_editing()/end_editing() and test_editor_camera_no_reversal.gd
	# for the dedicated regression coverage.
	_check("editing: focus-assist is OFF while editing (no competing idle camera authority)", not look_controller.focus_assist_enabled)
	_check("editing: still seated (zoom never stands the player up)", sleep_state.is_sitting())

	# ============================================================
	# 6. TYPING: characters are forwarded into the laptop screen's
	# SubViewport and land in its text field, including letters that
	# double as gameplay shortcuts elsewhere (e/f/t). A previous round
	# made bare T a second "exit editing" toggle, which silently ate
	# every literal "t" typed into an entry -- removed (see
	# test_daily_log_behavior.gd); T must be ordinary typing like any
	# other letter now. Esc is the only exit key.
	# ============================================================
	_send_typed_key(KEY_E, 101)
	_send_typed_key(KEY_F, 102)
	_send_typed_key(KEY_T, 116)
	await create_timer(0.1).timeout
	var typed_text: String = log_screen.get_entry_text()
	_check("typing: forwarded characters landed in the laptop screen's text field (got '%s')" % typed_text, typed_text.find("e") != -1 and typed_text.find("f") != -1 and typed_text.find("t") != -1)
	_check("typing: still editing (none of E/F/T kicked us out)", sleep_state.is_editing())

	log_screen.show_entry("Routine shift, quiet night.")

	# ============================================================
	# 7. CTRL+S SAVES WITHOUT EXITING.
	# ============================================================
	var saved_text: String = log_screen.get_entry_text()
	_send_ctrl_s()
	await create_timer(0.1).timeout
	_check("Ctrl+S: still editing (did not exit)", sleep_state.is_editing())

	# ============================================================
	# 8. ESC EXITS THE EDITOR back to LAPTOP, easing the zoom back out,
	# saving as it goes, without closing the laptop or standing up.
	# ============================================================
	_send_key(KEY_ESCAPE)
	await create_timer(0.6).timeout
	_check("Esc: back in LAPTOP (not EDITING, not standing)", sleep_state.is_laptop_open() and not sleep_state.is_editing())
	_check("Esc: still seated", sleep_state.is_sitting())
	_check("Esc: does not close the laptop", bunkside_laptop.is_open)
	_check("Esc: free-look still enabled", look_controller.input_enabled)
	_check("Esc: 3D screen reflects the saved entry", log_screen.get_entry_text() == saved_text)
	_check("Esc: zoom eased back out to the ordinary laptop-viewing distance (got %.2fm, ordinary was %.2fm)" % [camera.global_position.distance_to(screen_pos), ordinary_dist], absf(camera.global_position.distance_to(screen_pos) - ordinary_dist) < 0.05)

	# ============================================================
	# 9. REOPEN EDITING: saved entry reappears; repeated enter/exit
	# does not stack conflicting zoom tweens or leave the view stuck
	# somewhere between the two framings.
	# ============================================================
	_send_key(KEY_T)
	await create_timer(0.6).timeout
	_check("retention: reopened editor shows the previously saved entry", log_screen.get_entry_text() == saved_text)
	_check("repeat: zoomed back in cleanly on re-entry (got %.2fm)" % camera.global_position.distance_to(screen_pos), camera.global_position.distance_to(screen_pos) < ordinary_dist * 0.75)
	_send_key(KEY_ESCAPE)
	await create_timer(0.6).timeout
	_check("editing: Esc exits editing back to LAPTOP", sleep_state.is_laptop_open() and not sleep_state.is_editing())
	_check("repeat: zoomed back out cleanly on exit (got %.2fm)" % camera.global_position.distance_to(screen_pos), absf(camera.global_position.distance_to(screen_pos) - ordinary_dist) < 0.05)

	# ============================================================
	# 10. INVALID: F key must not close the laptop while EDITING (it is
	# ordinary typing while editing, not a shortcut).
	# ============================================================
	_send_key(KEY_T)
	await create_timer(0.6).timeout
	_check("precondition: back in EDITING", sleep_state.is_editing())
	_send_key(KEY_F)
	await create_timer(0.1).timeout
	_check("invalid: F key while EDITING does not close the laptop (typed instead)", sleep_state.is_editing())
	_send_key(KEY_ESCAPE)
	await create_timer(0.6).timeout
	_check("cleanup: back to LAPTOP before continuing", sleep_state.is_laptop_open() and not sleep_state.is_editing())

	# ============================================================
	# 11. CLOSE THE LAPTOP (F key): laptop stays on the lap anchor,
	# closed, until get-up -- the documented simplest-reliable choice.
	# ============================================================
	_send_key(KEY_F)
	await create_timer(0.5).timeout
	_check("close: laptop closed, back to plain SITTING", not sleep_state.is_laptop_open() and sleep_state.is_sitting())
	_check("close: laptop lid is shut", not bunkside_laptop.is_open)
	_check("close: laptop left safely on the lap anchor (not yet back on the bed)", bunkside_laptop.get_parent() == lap_anchor)
	_check("prompt: back to get-up/laptop prompt", prompt.text.find("Get Up") != -1)

	# ============================================================
	# 12. INVALID: T key while plain SITTING (laptop not open) is a no-op.
	# ============================================================
	_send_key(KEY_T)
	await create_timer(0.1).timeout
	_check("invalid: T key while sitting (laptop closed) does not open editing", not sleep_state.is_laptop_open() and not sleep_state.is_editing())

	# ============================================================
	# 13. GET UP: laptop is put back to rest exactly as get-up begins.
	# ============================================================
	_send_key(KEY_E)
	await create_timer(0.2).timeout
	_check("get-up: laptop returned to its resting parent promptly", bunkside_laptop.get_parent().name == "Interactables")
	await create_timer(2.4).timeout
	_check("get-up: fully awake again", not sleep_state.is_sitting())
	_check("body: standing pose restored", standing_pose.visible and not sitting_pose.visible)
	_check("prompt: shows the near-bed sit-down prompt again once awake (player is still next to the bed)", prompt.visible and prompt.text.find("Sit Down") != -1)

	# ============================================================
	# 14. INVALID: F/T while awake do nothing.
	# ============================================================
	var pos_before: Vector3 = player.global_position
	_send_key(KEY_F)
	_send_key(KEY_T)
	await create_timer(0.1).timeout
	_check("invalid: F/T while awake do not open the laptop", not sleep_state.is_laptop_open())
	_check("invalid: F/T while awake did not move the player", player.global_position.distance_to(pos_before) < 0.01)

	print("")
	if _ok:
		print("ALL TESTS PASSED")
	else:
		print("SOME TESTS FAILED")
	quit()


func _send_key(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)


func _send_typed_key(keycode: int, unicode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.unicode = unicode
	ev.pressed = true
	Input.parse_input_event(ev)


func _send_ctrl_s() -> void:
	var down := InputEventKey.new()
	down.keycode = KEY_S
	down.physical_keycode = KEY_S
	down.ctrl_pressed = true
	down.pressed = true
	Input.parse_input_event(down)

	var up := InputEventKey.new()
	up.keycode = KEY_S
	up.physical_keycode = KEY_S
	up.pressed = false
	Input.parse_input_event(up)


func _check(label: String, cond: bool) -> void:
	if cond:
		print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
