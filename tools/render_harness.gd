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
		push_error("RENDER HARNESS STALL at step '%s': no progress for %.0fs (engine frames=%d, paused=%s, time_scale=%.2f)" % [_last_step, watchdog_s, Engine.get_process_frames(), paused, Engine.time_scale])
		print("RENDER HARNESS STALL at step '", _last_step, "'")
		quit(2)


## Bounded wait in game time (the watchdog still guards real time).
func wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func snap(name: String, vp: SubViewport = null, main_too: bool = true) -> void:
	await RenderingServer.frame_post_draw
	if vp != null:
		vp.get_texture().get_image().save_png(out_dir + name + "_ext.png")
	if main_too:
		get_root().get_texture().get_image().save_png(out_dir + name + "_pov.png")
	step("saved " + name)


func finish() -> void:
	step("RENDER DONE")
	quit(0)
