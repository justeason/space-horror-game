extends SceneTree
## Round 32 Priority 2: reusable rendered-verification harness.
##
## Round 31's movie-mode renders twice stopped advancing with NO error:
## the movie writer kept producing frames while the script never reached
## its next step. The stall could not be reproduced in Round 32 (both
## sequences -- take/stow and the lying-down sleep -- complete in 118 and
## 403 frames), so this harness makes any future stall LOUD and BOUNDED
## instead of silent:
##   - step(label) logs progress and feeds a watchdog;
##   - a watchdog node (process_mode ALWAYS) quits with exit code 2 and a
##     "STALL at step ..." report (engine frames, pause, time scale) if no
##     step happens for WATCHDOG_S of real time;
##   - wait(s) is a bounded timer; snap() saves a SubViewport and/or the
##     main viewport after frame_post_draw.
##
## ROOT CAUSE FOUND (Round 33): RenderingServer.frame_post_draw is NOT
## emitted while macOS is not drawing the window (minimized / occluded /
## display asleep) -- process frames keep running (measured: +435 process
## frames, +0 post-draw signals in 3 s minimized), so any `await
## frame_post_draw` hangs silently. snap() now waits for post-draw for a
## bounded time, then calls RenderingServer.force_draw() (verified to
## produce a frame while minimized) and logs it; the stall report includes
## the window mode.
## Usage (non-headless):
##   godot --path . --write-movie <dir>/frame.png --fixed-fps 30 --script <your_script>.gd
## where your script `extends "res://tools/render_harness.gd"` and calls
## start(), step(), wait(), snap(), finish(). Not part of tests/run_tests.sh
## (it needs a real renderer).

var watchdog_s: float = 45.0
var out_dir: String = "user://renders/"
var _last_step_ms: int = 0
var _last_step: String = "(start)"
var _dog: Node
var post_draw_timeouts: int = 0
var post_draw_wait_s: float = 2.0


class _Watchdog extends Node:
	var harness
	func _process(_d: float) -> void:
		harness._check_watchdog()


func start(dir: String) -> void:
	out_dir = dir
	DirAccess.make_dir_recursive_absolute(out_dir)
	_dog = _Watchdog.new()
	_dog.harness = self
	_dog.process_mode = Node.PROCESS_MODE_ALWAYS
	get_root().add_child(_dog)
	step("start")


func step(label: String) -> void:
	_last_step = label
	_last_step_ms = Time.get_ticks_msec()
	print("HARNESS STEP: ", label)


func _check_watchdog() -> void:
	if _last_step_ms > 0 and Time.get_ticks_msec() - _last_step_ms > watchdog_s * 1000.0:
		push_error("RENDER HARNESS STALL at step '%s': no progress for %.0fs (engine frames=%d, paused=%s, time_scale=%.2f, window mode=%d, focused=%s, forced draws so far=%d)" % [_last_step, watchdog_s, Engine.get_process_frames(), paused, Engine.time_scale, DisplayServer.window_get_mode(), DisplayServer.window_is_focused(), post_draw_timeouts])
		print("RENDER HARNESS STALL at step '", _last_step, "'")
		quit(2)


## Bounded wait in game time (the watchdog still guards real time).
func wait(seconds: float) -> void:
	await create_timer(seconds).timeout


## Waits for the next rendered frame -- bounded: if the OS is not drawing
## the window, forces a draw instead of hanging.
func await_post_draw() -> void:
	var got := [false]
	var cb := func(): got[0] = true
	RenderingServer.frame_post_draw.connect(cb, CONNECT_ONE_SHOT)
	var t0 := Time.get_ticks_msec()
	while not got[0] and Time.get_ticks_msec() - t0 < int(post_draw_wait_s * 1000.0):
		await process_frame
	if not got[0]:
		if RenderingServer.frame_post_draw.is_connected(cb):
			RenderingServer.frame_post_draw.disconnect(cb)
		post_draw_timeouts += 1
		print("HARNESS: frame_post_draw not delivered for %.1fs (window mode %d -- minimized/occluded?); forcing a draw" % [post_draw_wait_s, DisplayServer.window_get_mode()])
		RenderingServer.force_draw()


func snap(name: String, vp: SubViewport = null, main_too: bool = true) -> void:
	await await_post_draw()
	if vp != null:
		vp.get_texture().get_image().save_png(out_dir + name + "_ext.png")
	if main_too:
		get_root().get_texture().get_image().save_png(out_dir + name + "_pov.png")
	step("saved " + name)


func finish() -> void:
	step("RENDER DONE")
	quit(0)
