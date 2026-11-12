extends SceneTree
## Round 49: the Deck B WORK-ORDER registry in DayPlan's one schedule.
##   - every registered type is playable (real equipment), ids never
##     collide with Deck A's, families / rooms valid;
##   - CHAPTER ONE IS PROTECTED: with Chapter One incomplete no Deck B (or
##     Deck-B-dependent) order is ever scheduled or raised, even at L3;
##   - Deck B access tiers gate types; at most one new Deck B order a day,
##     never more than two open; the first order is the practical utility
##     check; cooldowns respected; a fault raises its own order once;
##   - closing a job credits proficiency once and counts toward the next
##     access tier; outcomes are stored on the order;
##   - Lower Junction procedures: Bus B verification (a tripped breaker
##     really unpowers the habitat circuit), emergency lighting test (the
##     deck's lights really switch over), condensation (L06) found by
##     surface temperature vs dew point.
const L = preload("res://scripts/deck_b/deck_b_layout.gd")
const T = preload("res://scripts/deck_b/deck_b_tasks.gd")
var _ok := true
var main: Node
var dp: Node
var clr: Node
var se: Node
var s: Node
var carry: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	main.get_node("StationAI").set_enabled(false)
	dp = main.get_node("DayPlan")
	clr = main.get_node("DayPlan/Clearance")
	se = main.get_node("StoryEvents")
	s = main.get_node("DeckB/DeckBSystems")
	carry = main.get_node("Player/CarrySystem")
	_registry()
	_chapter_one()
	await _schedule()
	await _junction()
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _registry() -> void:
	var missing: Array = []
	for t in T.TYPES:
		if dp.order_equipment(t) == null:
			missing.append(String(t))
	_check("all %d Deck B / design-gap order types have real equipment%s" % [T.TYPES.size(), (" (missing " + ", ".join(missing) + ")") if not missing.is_empty() else ""], missing.is_empty() and T.TYPES.size() >= 45)
	_check("no id collides with a Deck A order type", T.TYPES.keys().all(func(t): return not dp.ORDER_TYPES.has(t)))
	_check("families valid, rooms valid", T.TYPES.keys().all(func(t): return dp.FAMILIES.has(String(T.TYPES[t]["family"])) and (L.ROOMS.has(StringName(T.TYPES[t]["room"])) or dp.ROOM_SHORT.has(StringName(T.TYPES[t]["room"])))))
	_check("order_type() serves both registries", dp.order_type(&"vent").get("tag", "") == "VENT" and dp.order_type(&"b02_filter").get("tag", "") == "WATER FLT")
	var per_room := {}
	for t in T.TYPES:
		var r: String = String(T.TYPES[t]["room"])
		per_room[r] = int(per_room.get(r, 0)) + 1
	_check("every principal room has several jobs (%s)" % str(per_room), ["b01", "b02", "b03", "b04", "b05", "b06", "b07", "b08", "b09"].all(func(r): return int(per_room.get(r, 0)) >= 3))


func _chapter_one() -> void:
	clr.load_dict({"level": 3})
	_check("Chapter One incomplete: no Deck B access even at L3 (tier %d)" % clr.deck_b_tier(), clr.deck_b_tier() == 0 and not se.chapter_one_complete())
	var leaked: Array = []
	for d in range(2, 16):
		dp.day_number = d
		dp._schedule_orders()
		for o in dp.open_orders():
			if T.is_deck_b(StringName(o["type"])):
				leaked.append(o["type"])
	_check("14 scheduled days at L3 in Chapter One: no lower-deck order (%s)" % ", ".join(leaked), leaked.is_empty())
	_check("a REAL fault cannot raise a gated order either", dp.raise_order(&"b02_filter", "test").is_empty())
	_check("...nor a design-gap job that needs the deck (E11)", dp.raise_order(&"e11_battery", "test").is_empty())
	dp.orders = []


func _schedule() -> void:
	se._add_milestone("chapter_1")
	clr.refresh()
	_check("Chapter One complete + L3 -> Lower Service Deck T1 (UTILITIES) granted", clr.deck_b_tier() == 1 and se.has_milestone("ch2_opened"))
	_check("...rooms: B-01/02/03 open, workshop / lab / archive still closed", clr.deck_b_room_open(&"b02") and clr.deck_b_room_open(&"b03") and not clr.deck_b_room_open(&"b04") and not clr.deck_b_room_open(&"b05") and not clr.deck_b_room_open(&"b09"))
	var first: String = ""
	var max_open := 0
	var max_new := 0
	var tiers_ok := true
	var seen_days := {}
	for d in range(16, 36):
		dp.day_number = d
		var before: Array = dp.orders.map(func(o): return o["id"])
		dp._schedule_orders()
		var new_b: Array = dp.orders.filter(func(o): return not before.has(o["id"]) and T.is_deck_b(StringName(o["type"])))
		if first == "" and not new_b.is_empty():
			first = String(new_b[0]["type"])
		max_new = maxi(max_new, new_b.size())
		var open_b: Array = dp.open_orders().filter(func(o): return T.is_deck_b(StringName(o["type"])))
		max_open = maxi(max_open, open_b.size())
		for o in new_b:
			if int(T.TYPES[StringName(o["type"])]["tier"]) > 1:
				tiers_ok = false
			if String(T.TYPES[StringName(o["type"])]["freq"]) in ["fault", "story"]:
				tiers_ok = false
			var key: String = String(o["type"])
			if seen_days.has(key) and d - int(seen_days[key]) < int(T.TYPES[StringName(o["type"])]["cooldown"]):
				tiers_ok = false
			seen_days[key] = d
		# Close the day's lower-deck work (as if done) to keep the schedule moving.
		for o in open_b:
			o["status"] = "done"
			o["done_day"] = d
	_check("the practical first lower-deck order is the utility check (%s)" % first, first == "b01_utility")
	_check("workload: at most 1 new Deck B order a day (max %d), at most 2 open (max %d)" % [max_new, max_open], max_new <= 1 and max_open <= 2)
	_check("only T1 routine / occasional types, cooldowns respected", tiers_ok)
	dp.orders = []
	# Jobs count toward the next tier; proficiency credited once.
	var prof0: int = int(dp.proficiency.get("life_support", 0))
	var o2: Dictionary = dp.raise_order(&"b02_tank", "test")
	_check("a raised order (outside the budget)", not o2.is_empty() and dp.raise_order(&"b02_tank", "again").is_empty())
	var water: Node = main.get_node("DeckB/Rooms/WaterRecovery")
	s.water["level_bias"] = 0.0
	water.on_part(&"glass0")
	water.on_part(&"glass1")
	water.on_part(&"panel")
	water.on_part(&"tank_ok")
	for i in 30: await process_frame
	_check("tank inspection closed with its OUTCOME stored ('%s')" % String(o2.get("outcome", "")), o2["status"] == "done" and String(o2.get("outcome", "")) == "verified_normal")
	_check("proficiency credited once (life support %d -> %d)" % [prof0, int(dp.proficiency.get("life_support", 0))], int(dp.proficiency.get("life_support", 0)) == prof0 + 1)
	clr.deck_b_jobs = 1
	clr._on_order_closed_b(&"b02_sample")
	_check("two Deck B jobs -> T2 LOGISTICS (workshop / cargo open)", clr.deck_b_tier() == 2 and clr.deck_b_room_open(&"b04") and clr.deck_b_room_open(&"b08"))


func _junction() -> void:
	clr.dev_set_deck_b(4)
	var j: Node = main.get_node("DeckB/Rooms/LowerJunction")
	# ---- Bus B verification with a tripped breaker.
	dp.raise_order(&"b01_utility", "test")
	j.util_seed = "tripped"
	j.util_trip = 2
	s.power["on"][2] = false
	_check("a tripped B3 really unpowers the habitat (grow lights %.2f)" % s.light_output(0), not s.powered(2) and s.light_output(0) == 0.0)
	j.on_part(&"brk2")
	_check("breaker can't be reset with the cover closed", not s.power["on"][2])
	j.on_part(&"ldp_cover")
	for k in 5:
		j.sel = k
		j._read()
	j.on_part(&"brk2")
	j.sel = 2
	j._read()
	j.on_part(&"ldp_cover")
	var uo: Dictionary = {}
	for i in 30:
		await process_frame
	for o in dp.orders:
		if o["type"] == "b01_utility":
			uo = o
	_check("all circuits read, B3 reset and re-read -> %s; habitat powered again" % uo.get("outcome", "?"), uo.get("status", "") == "done" and uo.get("outcome", "") == "repaired" and s.powered(2))
	# ---- Emergency lighting.
	dp.raise_order(&"b01_lights", "test")
	j.em_failed = 1
	j.em_replaced = false
	j.em_tests = 0
	j.on_part(&"em_test")
	await create_timer(0.3).timeout
	var spot: Light3D = get_nodes_in_group(&"deck_b_light")[0]
	var dim: bool = spot.light_energy < float(spot.get_meta(&"base_energy")) * 0.2
	var lit_z0 := false
	var lit_z1 := false
	for st in get_nodes_in_group(&"deck_b_em_strip"):
		var m: StandardMaterial3D = (st as MeshInstance3D).material_override
		if int(st.get_meta(&"zone")) == 0 and m.emission_energy_multiplier > 1.0:
			lit_z0 = true
		if int(st.get_meta(&"zone")) == 1 and m.emission_energy_multiplier > 1.0:
			lit_z1 = true
	_check("TEST: Deck B lights really dim, zone strips glow, the failed zone stays dark", dim and lit_z0 and not lit_z1)
	await create_timer(6.0).timeout
	var clip: Node = j.find_child("EmSpareClip", true, false)
	var mod: Node3D = clip.items()[0]
	mod.interact()
	if carry.is_reaching():
		carry.complete_grasp()
	j.on_part(&"em_mod1")
	j.on_part(&"em_test")
	await create_timer(6.3).timeout
	j.on_part(&"em_reset")
	var lo: Dictionary = {}
	for i in 30:
		await process_frame
	for o in dp.orders:
		if o["type"] == "b01_lights":
			lo = o
	_check("module replaced from the spare clip, retest OK, RESET -> %s" % lo.get("outcome", "?"), lo.get("status", "") == "done" and lo.get("outcome", "") == "repaired" and clip.count(&"lamp_module") == 1)
	# ---- Condensation (L06).
	dp.raise_order(&"l06_condensation", "test")
	j.cond_cause = "insulation"
	j.wrap_ok = false
	j.vent_on = true
	j.wet = 0.5
	_check("bare supply riser below the dew point condenses (dew %.1f °C)" % j._dew(), j._condensing())
	j.on_part(&"wrap")
	_check("the jacket is not closed before the surface is measured", not j.wrap_ok)
	j.on_part(&"riser")
	j.on_part(&"hum")
	j.on_part(&"wrap")
	j.wet = 0.08
	var co: Dictionary = {}
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000:
		await process_frame
		for o in dp.orders:
			if o["type"] == "l06_condensation" and o["status"] == "done":
				co = o
		if not co.is_empty():
			break
	_check("insulation closed, riser dries -> L06 %s" % co.get("outcome", "?"), co.get("outcome", "") == "repaired")


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
