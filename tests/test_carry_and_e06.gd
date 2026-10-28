extends SceneTree
var _ok := true
func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player := main.get_node("Player")
	var carry := player.get_node("CarrySystem")
	var wire := main.get_node("Interactables/WireComponent")
	var dp := main.get_node("DayPlan")
	var loose := main.get_node("Interactables/LooseConnection")

	_check("starts not carrying", not carry.is_carrying())
	wire.interact()
	_check("picking up wire works", carry.is_carrying() and carry.carried_item_id() == &"wire_control_16ga")
	_check("wire reparented to carry anchor", wire.get_parent() == player.get_node("PlayerBody/CarryAnchor"))

	# Simulate clicking some OTHER carryable while hands are already
	# full -- reuse the same wire node as a stand-in "another item"
	# since it still has interact(); hands-full should be a no-op.
	wire.interact()
	_check("re-clicking while already carrying is a no-op", carry.is_carrying())

	_check("consume with wrong id fails, nonpunishing (still carrying)", not carry.consume_if_matches(&"something_else"))
	_check("still carrying after failed consume", carry.is_carrying())
	_check("consume with correct id succeeds", carry.consume_if_matches(&"wire_control_16ga"))
	_check("no longer carrying after consume", not carry.is_carrying())

	# E06 loose connection: repeated clicks
	for i in 5:
		loose.interact()
	_check("not done before required clicks", not loose.is_done())
	_check("e06 day_plan not yet marked", not dp.is_task_done(&"e06"))
	loose.interact() # 6th click
	_check("done after required clicks", loose.is_done())
	_check("e06 day_plan marked done", dp.is_task_done(&"e06"))

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()

func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
