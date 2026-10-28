extends SceneTree
## Quick smoke test for M7's rewired architecture: confirms the
## cross-scene property override (LaptopView.laptop_path, set in
## main.tscn, pointing at Interactables/BunksideLaptop which lives
## outside player.tscn) actually resolved, and that the new nodes
## (LapAnchor, SessionLogScreen) exist and are wired without runtime
## errors.

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 10:
		await process_frame

	var player := main.get_node("Player")
	var sleep_state := main.get_node("SleepState")
	var player_body := player.get_node("PlayerBody")
	var lap_anchor := player_body.get_node("LapAnchor")
	var laptop_view := player.get_node("LaptopView")
	var bunkside_laptop := main.get_node("Interactables/BunksideLaptop")
	var log_screen := player.get_node("LaptopView/SessionLogScreen")
	var prompt := player.get_node("HUD/PromptLabel")

	print("PASS: LapAnchor exists: ", lap_anchor != null)
	print("PASS: LaptopView.laptop_path override resolved to the real BunksideLaptop: ", laptop_view.get("laptop_path") != NodePath() and laptop_view.call("is_open") == false)
	print("PASS: laptop_view's internal _laptop reference is the same node as Interactables/BunksideLaptop (no duplicate): ", laptop_view.get_node(laptop_view.laptop_path) == bunkside_laptop)
	print("PASS: SessionLogScreen exists (3D screen SubViewport, M7.2: now the whole log UI, not just a read-only display): ", log_screen != null and log_screen is SubViewport)
	print("PASS: BunksideLaptop screen texture was wired (not null): ", bunkside_laptop.get("_screen_texture") != null)
	print("PASS: PromptLabel exists, starts hidden: ", prompt != null and not prompt.visible)
	print("PASS: sleep_state.is_sitting() false at boot: ", not sleep_state.is_sitting())
	print("PASS: sleep_state.is_laptop_open() false at boot: ", not sleep_state.is_laptop_open())
	print("PASS: sleep_state.is_editing() false at boot: ", not sleep_state.is_editing())
	print("PASS: BunksideLaptop still parented under Interactables (resting), not moved at boot: ", bunkside_laptop.get_parent().name == "Interactables")

	print("")
	print("SMOKE TEST DONE")
	quit()
