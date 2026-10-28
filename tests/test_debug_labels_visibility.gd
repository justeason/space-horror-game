extends SceneTree
## Round 12 Workstream C regression coverage: the big yellow room/
## tunnel-name dev labels (main.tscn's "DevLabels" node, each a
## dev_label.tscn instance -- a billboarded, no_depth_test Label3D with
## no visibility gating of its own) used to render PERMANENTLY over
## normal gameplay -- confirmed via an actual rendered screenshot (not
## merely inferred from code): overlapping "CORRIDOR" / "MAIN JUNCTION"
## / "AIRLOCK" text filled a third of the frame during ordinary play.
##
## Fix: DevLabels now defaults to invisible, and
## scripts/dev/nav_debug_overlay.gd -- the project's EXISTING,
## already-gated (enabled defaults to false) station-topology debug
## tool -- now also owns this node's visibility via a new
## `room_labels_path` export, toggled together with its own ring/edge
## overlay on F3. One toggle, not two, per the brief's own "if the
## project already has a debug toggle, integrate these labels with it
## instead of adding another."
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var dev_labels: Node3D = main.get_node("DevLabels")
	var overlay: Node3D = main.get_node("NavDebugOverlay")

	# ============================================================
	# 1. Normal gameplay (the actual default this project ships with --
	# NavDebugOverlay.enabled is false in main.tscn): the giant labels
	# are hidden.
	# ============================================================
	_check("NavDebugOverlay defaults to disabled (normal gameplay)", not overlay.enabled)
	_check("DevLabels are hidden during normal gameplay", not dev_labels.visible)

	# ============================================================
	# 2. Enabling the existing debug overlay (the same flag a developer
	# would flip to diagnose station topology) also reveals the room
	# labels -- integrated with the SAME toggle, not a second one.
	# ============================================================
	overlay.enabled = true
	overlay._room_labels = dev_labels # re-resolve since @onready already ran with enabled=false
	overlay._ready()
	_check("enabling the existing debug overlay also reveals the room labels", dev_labels.visible)

	# ============================================================
	# 3. F3 toggles both the overlay's own visuals AND the room labels
	# together, in lockstep -- one shared state, not two independent
	# ones that could drift apart.
	# ============================================================
	var ev := InputEventKey.new()
	ev.keycode = KEY_F3
	ev.pressed = true
	overlay._unhandled_input(ev)
	_check("F3 hides both together", not dev_labels.visible)
	overlay._unhandled_input(ev)
	_check("F3 shows both together again", dev_labels.visible)

	# ============================================================
	# 4. Real station-topology diagnosis (what this overlay is FOR)
	# still works once enabled -- this fix didn't disable the actual
	# diagnostic, only the always-on labels.
	# ============================================================
	_check("the overlay still builds its real nav ring/edge mesh when enabled", overlay._mesh_instance != null)
	_check("the overlay still builds its own per-node labels when enabled", overlay._labels.size() > 0)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()

func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
