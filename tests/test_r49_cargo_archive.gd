extends SceneTree
## Round 49: CARGO / DOCKING SUPPORT (B-08) and DATA ARCHIVE (B-09).
##   cargo    a berthed shipment's bags hold exactly its real parts (no
##            duplicate, no conjured stock); a short shipment cannot be
##            confirmed MATCH; the discrepancy is classified from evidence;
##            straps: an unrestrained bag drifts (microgravity) and is
##            locked shut while strapped; the berthing hatch INTERLOCK
##            (vehicle, latches, vestibule pressure, leak check) -- no way
##            to open it to vacuum; sorting to destination bins completes
##            the transfer (the parts are the same instances).
##   archive  daily snapshots are copies of the AUTHORITATIVE logs with a
##            checksum; backup verify never touches the player's save
##            files; cartridge replacement needs the rack isolated, a real
##            blank cartridge, an index rebuild and an integrity check;
##            record correlation reads the real access / service logs;
##            fan service; the previous technician's records are readable.
const L = preload("res://scripts/deck_b/deck_b_layout.gd")
var _ok := true
var main: Node
var dp: Node
var s: Node
var carry: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	main.get_node("StationAI").set_enabled(false)
	dp = main.get_node("DayPlan")
	s = main.get_node("DeckB/DeckBSystems")
	carry = main.get_node("Player/CarrySystem")
	main.get_node("DayPlan/Clearance").load_dict({"level": 3})
	main.get_node("DayPlan/Clearance").dev_set_deck_b(4)
	await _cargo()
	await _archive()
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _order(t: StringName) -> Dictionary:
	for o in dp.orders:
		if StringName(o["type"]) == t:
			return o
	return {}


func _wait_closed(t: StringName, max_s: float = 3.0) -> Dictionary:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(max_s * 1000.0):
		await process_frame
		if String(_order(t).get("status", "")) == "done":
			break
	return _order(t)


func _all_parts() -> int:
	return get_nodes_in_group(&"deck_b_part").size()


func _cargo() -> void:
	var c: Node = main.get_node("DeckB/Rooms/CargoBay")
	# A SHORT shipment (searching real arrivals by seed, deterministic).
	for k in 60:
		c.arrive(k)
		await process_frame
		if c.shipment["seed_kind"] == "short":
			break
	var manifest_total := 0
	for l in c.shipment["lines"]:
		manifest_total += int(l[1])
	var in_bags: int = c._ctb.reduce(func(a, r): return a + r.count(), 0)
	var labelled: int = get_nodes_in_group(&"deck_b_part").filter(func(p): return not p.is_queued_for_deletion() and p.payload.has("label")).size()
	_check("shipment %s (%s): the bags hold %d real parts for a %d-item manifest (no extra copies: %d labelled parts exist)" % [c.shipment["id"], c.shipment["seed_kind"], in_bags, manifest_total, labelled], c.shipment["seed_kind"] == "short" and in_bags == manifest_total - 1 and labelled == in_bags)
	_check("the vehicle raised the manifest order", String(_order(&"b08_manifest").get("status", "")) == "open")
	_check("strapped bags are locked shut", c._ctb.all(func(r): return r.locked))
	c.on_part(&"scan0")
	c.on_part(&"scan1")
	c.on_part(&"open0")
	_check("a bag can't be opened while strapped", not c.opened[0])
	c.on_part(&"strap0")
	c.on_part(&"strap1")
	var y0: float = (c._ctb_roots[0] as Node3D).position.y
	await create_timer(0.6).timeout
	_check("unrestrained, the bag drifts (microgravity: %.3f -> %.3f)" % [y0, (c._ctb_roots[0] as Node3D).position.y], absf((c._ctb_roots[0] as Node3D).position.y - y0) > 0.01)
	c.on_part(&"open0")
	c.on_part(&"open1")
	c.line_i = 0
	c.on_part(&"mark_match")
	var short_refused: bool = c.line_marks[0] == ""
	_check("line 1 is short: MATCH refused (count disagrees)", short_refused)
	c.on_part(&"mark_mismatch")
	for i in range(1, c.shipment["lines"].size()):
		c.line_i = i
		if c._line_truth(i):
			c.on_part(&"mark_match")
		else:
			c.on_part(&"mark_mismatch")
	c.on_part(&"sign")
	var mo: Dictionary = await _wait_closed(&"b08_manifest")
	_check("manifest signed with the mismatch recorded -> %s" % mo.get("outcome", "?"), mo.get("status", "") == "done" and c.signed)
	_check("...which raised the discrepancy order", String(_order(&"b08_discrepancy").get("status", "")) == "open")
	c.disc_type = 1
	c.on_part(&"disc_log")
	_check("discrepancy type must match the evidence (MISLABELLED refused)", c.disc_logged == "")
	c.disc_type = 0
	c.on_part(&"disc_log")
	var dco: Dictionary = await _wait_closed(&"b08_discrepancy")
	_check("logged MISSING -> %s" % dco.get("outcome", "?"), dco.get("outcome", "") == "no_part")
	# Sort everything to its destination bin (same instances).
	var ids_before: Array = []
	for r in c._ctb:
		for it in r.items():
			ids_before.append(String(it.name))
	for r in c._ctb:
		for it in r.items():
			it.interact()
			if carry.is_reaching():
				carry.complete_grasp()
			var h: Node3D = carry._carried_item
			carry._carried_item = null
			var dest: String = c.DEST.get(h.item_id, "WORKSHOP")
			c.part_stow(StringName("rack_Dest" + dest.capitalize()), h)
	c.on_part(&"sign")
	var to: Dictionary = await _wait_closed(&"b08_transfer")
	var ids_after: Array = []
	for d in c._bins:
		for it in c._bins[d].items():
			ids_after.append(String(it.name))
	ids_before.sort()
	ids_after.sort()
	_check("transfer: bags empty, the SAME parts in their destination bins (%d) -> %s" % [ids_after.size(), to.get("outcome", "?")], to.get("status", "") == "done" and ids_before == ids_after and c._containers_empty())
	# ---- Docking interlock.
	dp.raise_order(&"b08_seal", "test")
	c.vehicle = true
	c.latches = [true, false, true, true]
	c.vest_kpa = 0.0
	c.leak_ok = false
	c.on_part(&"hatch")
	_check("hatch interlock: refused with a latch not engaged", not c.hatch_open)
	c.on_part(&"drive_latch")
	c.on_part(&"hatch")
	_check("...refused with the vestibule at vacuum", not c.hatch_open)
	c.on_part(&"equalise_up")
	await create_timer(10.5).timeout
	c.on_part(&"equalise_dn")
	c.on_part(&"hatch")
	_check("...refused until the leak check passes (vestibule %.0f kPa)" % c.vest_kpa, not c.hatch_open and c.vest_kpa > 95.0)
	c.on_part(&"leak_check")
	await create_timer(10.4).timeout
	c.on_part(&"hatch")
	_check("all interlocks satisfied: the hatch opens to the pressurised vehicle", c.hatch_open)
	c.on_part(&"hatch")
	var so: Dictionary = await _wait_closed(&"b08_seal")
	_check("docking seal verification -> %s" % so.get("outcome", "?"), so.get("status", "") == "done")
	c.vehicle = false
	c.on_part(&"hatch")
	_check("no vehicle: PORT CAPPED, hatch never opens", not c.hatch_open)


func _archive() -> void:
	var a: Node = main.get_node("DeckB/Rooms/DataArchive")
	var lg: Node = main.get_node("DayPlan/StationLog")
	lg.record("access", "B-09 ARCHIVE · entered · TECH-1")
	s.record_service({"day": dp.day_number, "t": "10:42", "room": "b02", "equipment": "test", "fault": "none", "action": "check", "verify": "ok", "outcome": "verified_normal"})
	var snap: Dictionary = a.take_snapshot(dp.day_number)
	_check("snapshot = copy of the authoritative logs (%d records, checksum %s)" % [int(snap["count"]), snap["checksum"]], int(snap["count"]) >= 2 and a.snapshot_ok(snap) and snap["lines"].any(func(l): return String(l).find("ARCHIVE · entered") != -1))
	var save_path: String = ProjectSettings.globalize_path("user://savegame.json")
	var mtime0: int = FileAccess.get_modified_time(save_path) if FileAccess.file_exists(save_path) else -1
	dp.raise_order(&"b09_backup", "test")
	a.backup_corrupt = false
	a.page = 2
	a.on_part(&"con2")
	var bo: Dictionary = await _wait_closed(&"b09_backup")
	_check("backup verified (restore eligible) -> %s" % bo.get("outcome", "?"), bo.get("status", "") == "done")
	_check("...and the player's save file was not touched", (FileAccess.get_modified_time(save_path) if FileAccess.file_exists(save_path) else -1) == mtime0)
	# ---- Cartridge replacement.
	dp.raise_order(&"b09_cartridge", "test")
	var tgt: int = a.cart_target
	var r: int = tgt / 6
	a.on_part(StringName("slot%d" % tgt))
	_check("a powered rack refuses removal", a.cart[tgt]["state"] == "failed")
	a.page = 0
	a.sel = r
	a.on_part(&"con2")
	a.on_part(StringName("slot%d" % tgt))
	if carry.is_reaching():
		carry.complete_grasp()
	var failed: Node3D = carry._carried_item
	carry._carried_item = null
	_check("the failed cartridge comes out as a real part (state %s)" % (String(failed.payload["state"]) if failed != null else "-"), failed != null and String(failed.payload["state"]) == "failed")
	_check("a FAILED cartridge is refused in the empty slot", not a.accepts_part(StringName("slot%d" % tgt), failed))
	var blanks: Node = a.find_child("ArchiveBlanks", true, false)
	var nb0: int = blanks.count(&"data_cartridge")
	var blank: Node3D = blanks.items()[0]
	blank.interact()
	if carry.is_reaching():
		carry.complete_grasp()
	carry._carried_item = null
	a.stow_part(StringName("slot%d" % tgt), blank)
	a.page = 1
	a.on_part(&"con2")
	await create_timer(10.4).timeout
	a.on_part(&"con3")
	a.page = 0
	a.sel = r
	a.on_part(&"con2")
	var co: Dictionary = await _wait_closed(&"b09_cartridge")
	_check("isolate, replace (blanks %d -> %d), rebuild, integrity PASS, back on line -> %s" % [nb0, blanks.count(&"data_cartridge"), co.get("outcome", "?")], co.get("status", "") == "done" and blanks.count(&"data_cartridge") == nb0 - 1)
	# ---- Correlation.
	dp.raise_order(&"b09_correlate", "test")
	a.page = 3
	_check("correlation view reads the real logs", a._correlation_rows(dp.day_number).find("ARCHIVE · entered") != -1)
	a.on_part(&"con2")
	var cr: Dictionary = await _wait_closed(&"b09_correlate")
	_check("batched archive write judged LEGITIMATE -> %s" % cr.get("outcome", "?"), cr.get("outcome", "") == "verified_normal")
	# ---- Fans.
	dp.raise_order(&"b09_fans", "test")
	a.fan_seed = "filter"
	a.fan_filter = 0.85
	await create_timer(3.0).timeout
	var slow: float = float(a.fans[0])
	a.on_part(&"filter")
	a.on_part(&"filter")
	a.on_part(&"filter")
	var fo: Dictionary = await _wait_closed(&"b09_fans", 8.0)
	_check("dusty filter slowed the fans (%d rpm); cleaned -> %s" % [int(slow), fo.get("outcome", "?")], slow < 2600.0 and fo.get("status", "") == "done")
	# Previous technician's records.
	a.on_part(&"recorder")
	_check("R.V.'s tapes are readable (rotation 4)", a.tapes_read.has(0))


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
