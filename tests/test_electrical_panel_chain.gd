extends SceneTree
const GameSettings = preload("res://scripts/station/game_settings.gd")
var _ok := true
func _init() -> void:
	while GameSettings.get_difficulty() != GameSettings.Difficulty.NORMAL: GameSettings.cycle_difficulty() # isolate from any stray persisted difficulty
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player := main.get_node("Player")
	var carry := player.get_node("CarrySystem")
	var wire := main.get_node("Interactables/WireComponent")
	var dp := main.get_node("DayPlan")
	var panel := main.get_node("Geometry/EngineeringCabinet1")

	_check("panel starts not repaired", not panel.is_repaired())

	# ============================================================
	# Visual-identity regression (Stage 3 of this round): the panel
	# previously shared the exact same material as every other
	# decorative cabinet/machinery box in the room, which was the
	# player's actual reported reason they couldn't find it. Can't
	# render to confirm the result LOOKS right, but can confirm the
	# underlying data is no longer identical to its decorative
	# neighbors, and that the visible collider is still this one node
	# (no separate hidden prop, no duplicate panel).
	# ============================================================
	var decorative_neighbor := main.get_node("Geometry/EngineeringCabinet2")
	_check("panel material is no longer identical to a decorative neighbor's", panel.material != decorative_neighbor.material)
	_check("panel still has its own collider (not hidden behind another prop)", panel.use_collision)
	_check("panel has dressing children (compartment covers/hazard/switches/label) without their own collision", panel.get_node("UpperCover") != null and not panel.get_node("UpperCover").use_collision)

	# This round split the cabinet's own click (door open/close only --
	# panel.interact()) from the actual inspect/trace/install
	# progression, which now lives on the separate Terminal collider
	# (panel.terminal_interact(), reached via terminal_connector.gd in
	# the real game). Open the door first -- it must not, by itself,
	# touch any task flag.
	panel.interact()
	_check("opening the door does not by itself advance any task", not dp.is_task_done(&"e01"))
	_check("panel reports open after interact()", panel.is_door_open())
	# Round 16 Priority 3: force the deterministic default config (this
	# file hardcodes the fixed supply/return/service order) -- see
	# tests/test_electrical_wire_randomization.gd for the alternate one.
	panel.debug_force_fault_role(&"service")

	# E01: first terminal interact = inspect
	panel.terminal_interact(&"damaged")
	_check("e01 marked done after first terminal interact", dp.is_task_done(&"e01"))
	_check("e02 not yet done", not dp.is_task_done(&"e02"))

	# E02: second terminal interact = trace
	panel.terminal_interact(&"damaged")
	_check("e02 marked done after second terminal interact", dp.is_task_done(&"e02"))
	_check("required component set by trace", dp.required_component_id == &"wire_control_16ga")

	# ============================================================
	# Round 15 Priority 1 fix: the task fiction previously called the
	# required part "blue" while the diorama's own service-wire slot
	# (the one it actually becomes once installed) is YELLOW -- and the
	# player separately carries a visually BLUE coiled spare, since
	# "return" already owns blue in the 3-way red/blue/yellow wire-color
	# puzzle. That mismatch read as a fourth, unrelated wire. Fixed by
	# recoloring the carried WireComponent to the same yellow and
	# correcting every "16-gauge, blue" message to "16-gauge, yellow".
	# ============================================================
	var wire_mat: StandardMaterial3D = wire.get_node("CoilLoopA").material
	var view := player.get_node("HUD/ElectricalRepairView")
	var diorama := view.get_node("Panel/VBox/DioramaContainer/DioramaViewport/ElectricalRepairDiorama")
	var service_wire_mat: StandardMaterial3D = diorama._replacement_wire.get_node("VisualGroup_service/Run").material
	_check("carried spare wire's color matches the installed replacement wire's color (no more color mismatch)", wire_mat.albedo_color.is_equal_approx(service_wire_mat.albedo_color))
	var message_label: Label = player.get_node("HUD/TaskMessageLabel")
	_check("circuit-traced message describes the required part as yellow", message_label.text.findn("yellow") != -1)
	_check("circuit-traced message no longer describes the part as blue", message_label.text.findn("blue") == -1)

	# Attempt E05 (third terminal interact) while carrying NOTHING: must
	# fail cleanly, nonpunishingly -- no progress lost, panel still open.
	_check("not carrying anything yet", not carry.is_carrying())
	panel.terminal_interact(&"damaged")
	_check("repair attempt with empty hands fails without penalty", not panel.is_repaired())
	_check("e02/trace state untouched by the failed attempt", dp.is_task_done(&"e02"))

	# Pick up the correct wire and retry -- this now OPENS the focused
	# multi-stage repair procedure (scripts/ui/electrical_repair_view.gd)
	# instead of installing immediately. Drive the procedure directly
	# through the panel's own methods (same "call the object's methods
	# directly, bypass the view" technique this whole test already
	# uses) to confirm it reaches the same end state this test has
	# always checked for.
	wire.interact()
	_check("wire picked up", carry.is_carrying())
	panel.terminal_interact(&"damaged")
	_check("terminal click opens the procedure, not an immediate install", panel.procedure_stage() == &"isolate")
	_check("not repaired just from opening the procedure", not panel.is_repaired())

	panel.toggle_isolation()
	panel.disconnect_wire(&"supply")
	panel.disconnect_wire(&"return")
	panel.disconnect_wire(&"service")
	_check("all three wires disconnected", panel.disconnected_roles().size() == 3)
	var install_result: Dictionary = panel.install_replacement_wire()
	_check("install succeeds once disconnected and carrying the right part", install_result.get("ok", false))
	panel.reconnect_wire(&"service")
	panel.reconnect_wire(&"return")
	panel.reconnect_wire(&"supply")
	var restore_result: Dictionary = panel.restore_power()
	_check("restore succeeds once all three are reconnected", restore_result.get("ok", false))
	# terminal_interact() -> _open_procedure() opened a real focused
	# session (scripts/player/focused_interaction_state.gd) -- close it
	# now that the procedure is complete, same as a player pressing
	# Enter/Escape, so interactions_enabled/free movement/look input end
	# up properly restored rather than left stuck for the rest of this
	# test (or any test that runs after this file in the same process).
	main.get_node("FocusedInteractionState").end()

	_check("panel repaired once the full procedure completes", panel.is_repaired())
	_check("e05 marked done", dp.is_task_done(&"e05"))
	_check("wire consumed (no longer carrying)", not carry.is_carrying())
	_check("installed wire is marked installed, not freed", wire.is_installed())
	_check("installed wire is now parented under the Terminal", wire.get_parent() == panel.get_node("Terminal"))
	# ============================================================
	# Round 16 Priority 2 fix: the carried wire's own COILED geometry
	# (a shape authored for a pickup prop, nothing like the diorama's
	# smooth curved service wire) used to stay VISIBLE here, reparented
	# right into the cabinet's recessed service bay alongside the
	# diorama's own `_replacement_wire` -- the real "extra object
	# sitting next to the three main wires" the player kept reporting.
	# Round 15 only recolored this node to match (blue -> yellow),
	# which fixed the color mismatch but left the actual duplicate
	# object in place. The diorama's own replacement wire is now the
	# ONE visible "installed wire" representation; this node still
	# exists (is_installed()/get_parent() above) but must no longer
	# render as a second one.
	# ============================================================
	_check("installed wire's own coiled-prop geometry is no longer visible (no duplicate wire object)", not wire.visible)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()

func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
