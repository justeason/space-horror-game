extends "res://scripts/deck_b/deck_b_room.gd"
## Round 49: B-09 DATA ARCHIVE AND LONG-TERM STORAGE -- the most isolated
## room (end of the east branch, behind its own access hatch). A plausible
## technical facility, not a shrine:
##   three storage racks R1-R3 (six cartridge slots each, status LEDs, a
##   rack isolate switch at the console), the backup server assembly, the
##   maintenance console (RACKS / INDEX / BACKUP / CORRELATE / RECORDS),
##   the cooling fan tray (three fans, a filter mat), a lockable cabinet of
##   physical media (blank cartridges are real parts), the UPS module, the
##   local recorder with the previous technician's tapes.
## RECORD SEPARATION (authoritative data is never altered here):
##   ACTIVE LOGS     the station log / DayPlan / service history (live);
##   ARCHIVED LOGS   daily SNAPSHOTS copied from those at each new day
##                   (checksummed) -- what B09-03 verifies;
##   PERSONNEL       rotation-4 records of the previous technician (R.V.);
##   PRESENTATION    a registered story event may show an extra / altered
##                   line on the console (`overlay`); it is never stored in
##                   the snapshots and disappears when the event ends.
## The in-game "restore eligibility" is fiction: it NEVER touches the
## player's save files.
## Tasks: b09_racks, b09_cartridge, b09_backup, b09_correlate (C07),
## b09_fans, b09_unknown (story-gated).

const PAGES := ["RACKS", "INDEX", "BACKUP", "CORRELATE", "RECORDS"]
## Rotation-4 records (fixed fiction, before day 1 = 2026-10-01).
const PERSONNEL := [
	["2026-08-30 22:14", "R.V.", "WRS P-201 found running at shift start, raw tank low. Auto-cycle log empty. Bled the pump (air in the line again). Note: check the auto-cycle logger."],
	["2026-09-02 09:40", "R.V.", "Coolant V2 creeping open after power cycles. Re-set 50 %. Ticket to the ground."],
	["2026-09-09 15:05", "R.V.", "Archive R3 fan slow. Cleaned the filter mat. Dust is mostly lint from the cargo bags."],
	["2026-09-14 03:12", "R.V.", "Woke to the hoist motor. Hoist at Deck B, tray empty. Sent it back up. Probably a stuck call button."],
	["2026-09-21 11:30", "R.V.", "Lab specimen S-102 re-catalogued CR-4472 (was CR-4427, transcription error on the payload sheet)."],
]
## The second copy (the alternate record a later Chapter Two beat can show;
## presentation only -- see deck_b_story.gd).
const PERSONNEL_ALT := {
	0: ["2026-08-30 22:14", "R.V.", "WRS P-201 found running at shift start. Raw tank low. Nobody started it. The auto-cycle log is empty because there was no cycle."],
}
var cart: Array = []                # 18 x {label, health, state}
var isolated: Array = [false, false, false]
var index_ok: bool = true
var rebuild_t: float = -1.0
var verified_integrity: bool = false
var snapshots: Array = []           # [{day, checksum, count, lines}]
var page: int = 0
var sel: int = 0
var racks_seen: Array = [false, false, false]
var racks_logged: bool = false
var cart_target: int = -1
var cart_replaced: bool = false
var backup_verified: bool = false
var backup_corrupt: bool = false
var corr_question: Dictionary = {}
var corr_answer: String = ""
var fans: Array = [3000.0, 3000.0, 3000.0]
var fan_filter: float = 0.1
var filter_out: bool = false
var fan_seed: String = ""
var fan_spare: int = 1
var unknown_entry: Dictionary = {}  # story presentation (b09_unknown)
var unknown_checks: Dictionary = {}
var unknown_logged: bool = false
var personnel_alt: bool = false     # story: show the alternate copy
var tapes_read: Array = []

var _slots: Array = []              # MeshInstance LED per slot
var _slot_carts: Array = []
var _screen: Label3D
var _fan_blades: Array = []
var _fan_lbl: Label3D
var _filter_mat: MeshInstance3D
var _cabinet: Rack
var _rec_lbl: Label3D
var _fan_loop: AudioStreamPlayer3D
var _drive_loop: AudioStreamPlayer3D


func _ready() -> void:
	_room_ready([&"b09_racks", &"b09_cartridge", &"b09_backup", &"b09_correlate", &"b09_fans", &"b09_unknown"])
	for r in 3:
		for k in 6:
			cart.append({"label": "R%d-%d" % [r + 1, k + 1], "health": 1.0, "state": "ok"})
	_build_racks()
	_build_console()
	_build_south()
	text("B-09  DATA ARCHIVE", Vector3(6.6, L.FLOOR_Y + 2.7, 10.68), 18, Color(0.75, 0.82, 0.95), self, 180.0)
	if _dp != null and _dp.has_signal(&"day_started"):
		_dp.day_started.connect(_on_day)
	_fan_loop = machine_loop(_fan_stream(false), Vector3(6.6, L.FLOOR_Y + 2.2, 7.95), -15.0)
	_drive_loop = machine_loop(loop_stream(2.0, func(t, i): return (fmod(sin(float(i) * 12.9898) * 43758.5453, 1.0) - 0.5) * 0.05 + sin(TAU * 7200.0 / 60.0 * t) * 0.03 + (0.2 if fmod(t * 3.0, 1.0) < 0.01 else 0.0)), Vector3(7.6, L.FLOOR_Y + 1.2, 9.1), -22.0)
	_refresh()


var _fan_streams: Dictionary = {}


func _fan_stream(rough: bool) -> AudioStream:
	if not _fan_streams.has(rough):
		_fan_streams[rough] = _make_fan_stream(rough)
	return _fan_streams[rough]


func _make_fan_stream(rough: bool) -> AudioStream:
	return loop_stream(2.0, func(t, i):
		var base: float = (fmod(sin(float(i) * 78.233) * 43758.5453, 1.0) - 0.5) * 0.25
		var tone: float = sin(TAU * 250.0 * t) * 0.05
		var r: float = sin(TAU * 1700.0 * t) * 0.06 * (0.5 + 0.5 * sin(TAU * 11.0 * t)) if rough else 0.0
		return base + tone + r)


# ------------------------------------------------------------- geometry
func _build_racks() -> void:
	for r in 3:
		var rk := Node3D.new()
		rk.name = "StorageRack%d" % (r + 1)
		rk.position = Vector3(7.6, L.FLOOR_Y, 8.3 + r * 0.8)
		rk.rotation_degrees.y = -90.0
		add_child(rk)
		dbox(Vector3(0.6, 2.0, 0.5), Vector3(0, 1.0, 0), Color(0.12, 0.13, 0.16), rk, 0.4, true)
		text("R%d" % (r + 1), Vector3(0, 1.92, 0.252), 14, Color(0.75, 0.82, 0.95), rk)
		for k in 6:
			var x: float = -0.14 + (k % 2) * 0.28
			var y: float = 1.55 - int(k / 2) * 0.32
			dbox(Vector3(0.22, 0.05, 0.02), Vector3(x, y, 0.252), Color(0.05, 0.05, 0.06), rk)
			var cm := dbox(Vector3(0.1, 0.03, 0.03), Vector3(x - 0.04, y, 0.26), Color(0.12, 0.13, 0.16), rk)
			_slot_carts.append(cm)
			var led := dbox(Vector3(0.015, 0.015, 0.01), Vector3(x + 0.08, y, 0.262), Color(0.2, 0.2, 0.2), rk)
			_slots.append(led.material_override)
			part(StringName("slot%d" % (r * 6 + k)), Vector3(0.24, 0.08, 0.06), Vector3(x, y, 0.27), rk)
		part(StringName("rackplate%d" % r), Vector3(0.3, 0.1, 0.05), Vector3(0, 1.92, 0.27), rk)
		# Ventilation grilles (lit by the rack's own status glow).
		for g in 3:
			dbox(Vector3(0.5, 0.01, 0.01), Vector3(0, 0.3 + g * 0.06, 0.252), Color(0.25, 0.27, 0.3), rk)
	# Small rack-indicator glow (Deck B layer only).
	var o := OmniLight3D.new()
	o.position = Vector3(7.2, L.FLOOR_Y + 1.4, 9.1)
	o.omni_range = 1.4
	o.light_energy = 0.35
	o.light_color = Color(0.3, 0.8, 0.5)
	o.light_cull_mask = LAYER
	add_child(o)


func _build_console() -> void:
	var c := Node3D.new()
	c.name = "ArchiveConsole"
	c.position = Vector3(6.2, L.FLOOR_Y, 10.55)
	c.rotation_degrees.y = 180.0
	add_child(c)
	dbox(Vector3(1.1, 0.75, 0.3), Vector3(0, 0.375, 0), Color(0.18, 0.2, 0.24), c, 0.4, true)
	dbox(Vector3(1.0, 0.6, 0.03), Vector3(0, 1.35, 0.05), Color(0.02, 0.03, 0.04), c)
	_screen = text("", Vector3(0, 1.36, 0.068), 7, Color(0.55, 0.95, 0.75), c)
	_screen.width = 1100.0
	_screen.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var names := ["PAGE", "SELECT", "ACTION", "ALT"]
	for k in 4:
		button("con%d" % k, Vector3(-0.3 + k * 0.2, 0.8, 0.16), [Color(0.3, 0.8, 0.95), Color(0.95, 0.85, 0.3), Color(0.3, 0.9, 0.4), Color(0.95, 0.5, 0.15)][k], c, Vector3(0.12, 0.04, 0.02))
		text(names[k], Vector3(-0.3 + k * 0.2, 0.85, 0.16), 7, Color(0.95, 0.95, 0.9), c)
	# The local recorder (tapes of the previous rotation).
	dbox(Vector3(0.22, 0.08, 0.16), Vector3(0.42, 0.79, 0.0), Color(0.3, 0.3, 0.32), c)
	for s in [-1.0, 1.0]:
		dcyl(0.04, 0.012, Vector3(0.42 + s * 0.05, 0.84, 0.0), Color(0.15, 0.15, 0.16), c)
	_rec_lbl = text("RECORDER · TAPES R.V.", Vector3(0.42, 0.9, 0.09), 6, Color(0.95, 0.95, 0.9), c)
	part(&"recorder", Vector3(0.22, 0.1, 0.16), Vector3(0.42, 0.8, 0.0), c)
	# Backup server assembly beside the console.
	var b := Node3D.new()
	b.name = "BackupServer"
	b.position = Vector3(5.55, L.FLOOR_Y, 10.45)
	b.rotation_degrees.y = 180.0
	add_child(b)
	dbox(Vector3(0.45, 1.6, 0.45), Vector3(0, 0.8, 0), Color(0.16, 0.17, 0.2), b, 0.4, true)
	for k in 8:
		var led := dbox(Vector3(0.012, 0.012, 0.01), Vector3(-0.15 + k * 0.04, 1.4, 0.228), Color(0.2, 0.9, 0.4), b)
		glow(led, Color(0.2, 0.9, 0.4), 1.0)
	text("BACKUP SRV", Vector3(0, 1.52, 0.23), 8, Color(0.75, 0.82, 0.95), b)


func _build_south() -> void:
	# Fan tray (high on the south wall) + filter mat.
	var f := Node3D.new()
	f.name = "FanTray"
	f.position = Vector3(6.6, L.FLOOR_Y + 2.15, 7.91)
	add_child(f)
	dbox(Vector3(0.9, 0.3, 0.1), Vector3(0, 0, 0.05), Color(0.25, 0.27, 0.3), f)
	for k in 3:
		var hub := Node3D.new()
		hub.position = Vector3(-0.28 + k * 0.28, 0, 0.11)
		f.add_child(hub)
		for bl in 4:
			var m := dbox(Vector3(0.1, 0.03, 0.006), Vector3(cos(bl * PI * 0.5) * 0.05, sin(bl * PI * 0.5) * 0.05, 0), Color(0.1, 0.1, 0.11), hub)
			m.rotation.z = bl * PI * 0.5
		_fan_blades.append(hub)
		part(StringName("fan%d" % k), Vector3(0.24, 0.24, 0.06), Vector3(-0.28 + k * 0.28, 0, 0.12), f)
	_filter_mat = dbox(Vector3(0.86, 0.26, 0.01), Vector3(0, 0, 0.13), Color(0.6, 0.58, 0.5), f)
	(_filter_mat.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	part(&"filter", Vector3(0.86, 0.28, 0.04), Vector3(0, 0, 0.15), f)
	_fan_lbl = readout(Vector3(0, -0.24, 0.06), Vector2(0.8, 0.08), f, 8)
	# Lockable cabinet of physical media (blank cartridges are real).
	dbox(Vector3(0.7, 1.2, 0.35), Vector3(5.75, L.FLOOR_Y + 0.6, 8.08), Color(0.22, 0.24, 0.28), self, 0.4, true)
	text("MEDIA CABINET · BLANK CARTRIDGES · LOGBOOKS", Vector3(5.75, L.FLOOR_Y + 1.25, 8.26), 7, Color(0.75, 0.82, 0.95))
	_cabinet = rack("ArchiveBlanks", Vector3(5.55, L.FLOOR_Y + 1.32, 8.12), 3, 0.15, [&"data_cartridge"], "BLANK CARTRIDGES", self, 0.0)
	spawn_part.call_deferred(&"data_cartridge", _cabinet, {"condition": 1.0, "state": "new", "grade": "A", "calibrated": true, "history": []})
	spawn_part.call_deferred(&"data_cartridge", _cabinet, {"condition": 1.0, "state": "new", "grade": "A", "calibrated": true, "history": []})
	# UPS module.
	dbox(Vector3(0.4, 0.5, 0.3), Vector3(7.5, L.FLOOR_Y + 0.25, 8.08), Color(0.3, 0.32, 0.35), self, 0.4, true)
	var upsl := dbox(Vector3(0.02, 0.02, 0.01), Vector3(7.5, L.FLOOR_Y + 0.42, 8.24), Color(0.2, 0.9, 0.4), self)
	glow(upsl, Color(0.2, 0.9, 0.4), 1.2)
	text("UPS-9 · 100 %", Vector3(7.5, L.FLOOR_Y + 0.55, 8.24), 7, Color(0.75, 0.82, 0.95))


# ------------------------------------------------------------ snapshots
func _on_day(d: int) -> void:
	take_snapshot(d - 1)


## Copies the AUTHORITATIVE records of day `d` (station log, closed
## orders, service history) into a checksummed archive snapshot.
func take_snapshot(d: int) -> Dictionary:
	if d < 1:
		return {}
	for sn in snapshots:
		if int(sn["day"]) == d:
			return sn
	var lines: Array = []
	var lg: Node = get_tree().get_first_node_in_group(&"station_log") if is_inside_tree() else null
	if lg != null:
		for k in lg.KINDS:
			for e in lg.entries.get(k, []):
				if int(e["day"]) == d:
					lines.append("%s %s %s" % [e["t"], k.to_upper(), e["text"]])
	if _dp != null:
		for o in _dp.orders:
			if int(o.get("done_day", -1)) == d:
				lines.append("ORDER %s %s %s" % [o["id"], o["type"], String(o.get("outcome", "closed"))])
	var s: Node = sys()
	if s != null:
		for e in s.service_log:
			if int(e.get("day", -1)) == d:
				lines.append("%s SERVICE %s %s %s" % [e.get("t", ""), e.get("equipment", ""), e.get("action", ""), e.get("outcome", "")])
	var snap := {"day": d, "checksum": "%08X" % (hash(JSON.stringify(lines)) & 0xFFFFFFFF), "count": lines.size(), "lines": lines.slice(0, 60)}
	snapshots.append(snap)
	if snapshots.size() > 30:
		snapshots.pop_front()
	return snap


func snapshot_ok(sn: Dictionary) -> bool:
	return "%08X" % (hash(JSON.stringify(sn["lines"])) & 0xFFFFFFFF) == String(sn["checksum"]) if int(sn["count"]) <= 60 else true


# --------------------------------------------------------------- clicks
func on_part(id: StringName) -> void:
	var sid: String = String(id)
	match sid:
		"con0":
			page = (page + 1) % PAGES.size()
			sel = 0
			sfx(&"click")
		"con1":
			sel += 1
			sfx(&"click")
		"con2":
			_action(false)
		"con3":
			_action(true)
		"filter":
			if not filter_out:
				filter_out = true
				say("Filter mat out: %s" % ("thick grey lint" if fan_filter > 0.5 else "light dust"))
			elif fan_filter > 0.1:
				fan_filter = 0.05
				sfx(&"ratchet")
				say("Filter mat cleaned.")
			else:
				filter_out = false
				sfx(&"click")
				say("Filter mat refitted.")
		"recorder":
			var i: int = tapes_read.size() % PERSONNEL.size()
			var rec: Array = PERSONNEL_ALT[i] if (personnel_alt and PERSONNEL_ALT.has(i)) else PERSONNEL[i]
			if not tapes_read.has(i):
				tapes_read.append(i)
			say("TAPE %s · %s: %s" % [rec[0], rec[1], rec[2]], 7.0)
			get_tree().call_group(&"story_events", &"on_record_checked", "archive_tape_%d" % i)
		_:
			if sid.begins_with("slot"):
				_slot(int(sid.substr(4)))
			elif sid.begins_with("rackplate"):
				var r: int = int(sid.substr(9))
				racks_seen[r] = true
				var st: Array = []
				for k in 6:
					var c: Dictionary = cart[r * 6 + k]
					if c["state"] != "ok":
						st.append("%s %s" % [c["label"], String(c["state"]).to_upper()])
				say("Rack R%d: %s%s" % [r + 1, "all slots OK" if st.is_empty() else ", ".join(st), " · ISOLATED" if isolated[r] else ""])
			elif sid.begins_with("fan"):
				var k2: int = int(sid.substr(3))
				say("Fan %d: %d rpm%s" % [k2 + 1, int(fans[k2]), "  SLOW" if fans[k2] < 2400.0 else ""])
				if fan_seed == "bearing" and fans[k2] < 1500.0 and fan_spare > 0:
					fans[k2] = 3000.0
					fan_spare -= 1
					fan_seed = ""
					sfx(&"ratchet")
					say("Fan %d swapped for the cabinet spare." % (k2 + 1))
	_refresh()


func _slot(i: int) -> void:
	var r: int = i / 6
	var c: Dictionary = cart[i]
	if c["state"] == "empty":
		say("%s empty — insert a blank cartridge (Space)." % c["label"])
		return
	if not isolated[r]:
		say("%s: %s, health %d %%. (Isolate R%d at the console before removing.)" % [c["label"], String(c["state"]).to_upper(), int(float(c["health"]) * 100.0), r + 1])
		return
	if held() != null:
		return
	var p: Node3D = spawn_part(&"data_cartridge", null, {"condition": float(c["health"]), "state": "failed" if c["state"] == "failed" else "serviceable", "label": c["label"], "history": [{"day": day(), "text": "removed from %s" % c["label"]}]})
	p.global_position = (_slot_carts[i] as Node3D).global_position
	c["state"] = "empty"
	index_ok = false
	var cr: Node = _carry()
	if cr != null:
		cr.pick_up(p)
	sfx(&"click")
	say("%s removed. The index needs a rebuild after the replacement." % c["label"])


func accepts_part(id: StringName, item: Node) -> bool:
	var sid: String = String(id)
	if not sid.begins_with("slot") or item == null or item.item_id != &"data_cartridge":
		return false
	var i: int = int(sid.substr(4))
	return cart[i]["state"] == "empty" and isolated[i / 6] and String(item.payload.get("state", "")) != "failed"


func stow_part(id: StringName, item: Node3D) -> bool:
	if not accepts_part(id, item):
		return false
	var i: int = int(String(id).substr(4))
	cart[i] = {"label": cart[i]["label"], "health": 1.0, "state": "ok"}
	consume_part(item)
	if i == cart_target:
		cart_replaced = true
	sfx(&"clunk")
	say("Blank cartridge seated in %s. REBUILD the index at the console." % cart[i]["label"])
	_refresh()
	return true


func stow_hint(id: StringName, _item: Node) -> String:
	return "Seat the cartridge in %s" % cart[int(String(id).substr(4))]["label"]


func _action(alt: bool) -> void:
	match PAGES[page]:
		"RACKS":
			var r: int = sel % 3
			isolated[r] = not isolated[r]
			sfx(&"clunk")
			say("Rack R%d %s" % [r + 1, "ISOLATED" if isolated[r] else "on line"])
			if not alt and not isolated[r]:
				racks_logged = racks_seen.all(func(v): return v)
		"INDEX":
			if alt:
				if rebuild_t >= 0.0 or not index_ok:
					say("Index not ready.")
					return
				verified_integrity = cart.all(func(c): return c["state"] != "failed" and c["state"] != "empty")
				say("Integrity check: %s" % ("PASS — all cartridges, checksums match" if verified_integrity else "FAIL — a slot is failed / empty"))
			else:
				if isolated.any(func(v): return v) and cart.any(func(c): return c["state"] == "empty"):
					say("Fill the empty slot before rebuilding.")
					return
				rebuild_t = 0.0
				sfx(&"click")
				say("Rebuilding the index (10 s)…")
		"BACKUP":
			if snapshots.size() < 1:
				take_snapshot(maxi(day() - 1, 1))
			if not index_ok:
				say("Index damaged — rebuild it before verifying backups.")
				return
			var cur: Dictionary = snapshots.back()
			var ok: bool = snapshot_ok(cur) and not backup_corrupt
			backup_verified = ok
			say("Snapshot D%d · %d records · checksum %s · %s · RESTORE ELIGIBLE: %s (station records only — never your save)" % [int(cur["day"]), int(cur["count"]), cur["checksum"], "MATCH" if ok else "MISMATCH", "YES" if ok else "NO"])
			if backup_corrupt and not ok:
				backup_corrupt = false
				index_ok = false
				say("Snapshot index damaged — rebuild the index, then verify again.")
		"CORRELATE":
			if corr_question.is_empty():
				say("No record discrepancy queued.")
				return
			corr_answer = "UNEXPLAINED" if alt else "LEGITIMATE"
			sfx(&"click")
			say("Recorded: %s." % corr_answer)
		"RECORDS":
			if alt and not unknown_entry.is_empty():
				unknown_logged = true
				say("Unknown entry logged for review: UNEXPLAINED.")
			else:
				say("Personnel records: rotation 4 (R.V.) — %d entries. Use the recorder for the tapes." % PERSONNEL.size())
	_refresh()


func part_prompt(id: StringName) -> String:
	var sid: String = String(id)
	match sid:
		"con0": return "Click: console PAGE (%s)" % PAGES[page]
		"con1": return "Click: console SELECT"
		"con2": return "Click: console ACTION — %s" % {"RACKS": "isolate / restore R%d" % (sel % 3 + 1), "INDEX": "REBUILD index", "BACKUP": "VERIFY snapshot", "CORRELATE": "LEGITIMATE", "RECORDS": "read"}[PAGES[page]]
		"con3": return "Click: console ALT — %s" % {"RACKS": "isolate / restore", "INDEX": "INTEGRITY check", "BACKUP": "verify", "CORRELATE": "UNEXPLAINED", "RECORDS": "log unknown entry"}[PAGES[page]]
		"filter": return "Click: fan filter mat"
		"recorder": return "Click: play the next tape"
	if sid.begins_with("slot"): return "Click: cartridge %s" % cart[int(sid.substr(4))]["label"]
	if sid.begins_with("rackplate"): return "Click: rack R%d status" % (int(sid.substr(9)) + 1)
	if sid.begins_with("fan"): return "Click: fan %d" % (int(sid.substr(3)) + 1)
	return ""


# --------------------------------------------------------------- update
func _process(delta: float) -> void:
	_update_occlusion(delta)
	if rebuild_t >= 0.0:
		rebuild_t += delta
		if rebuild_t >= 10.0:
			rebuild_t = -1.0
			index_ok = true
			sfx(&"success")
			say("Index rebuilt.")
	var dusty: float = fan_filter if not filter_out else 0.0
	for k in 3:
		var target: float = 3000.0 * (1.0 - dusty * 0.55)
		if fan_seed == "bearing" and k == 2:
			target = 1200.0
		fans[k] = move_toward(float(fans[k]), target, delta * 400.0)
		(_fan_blades[k] as Node3D).rotation.z += float(fans[k]) / 3000.0 * 0.6
	set_loop(_fan_loop, _fan_stream(fan_seed == "bearing" or fan_filter > 0.5), true)
	if Engine.get_process_frames() % 6 == 0 and is_visible_in_tree():
		_refresh()


func _refresh() -> void:
	for i in _slots.size():
		var st: String = cart[i]["state"]
		var c: Color = {"ok": Color(0.2, 0.9, 0.4), "degraded": Color(1.0, 0.65, 0.1), "failed": Color(1.0, 0.15, 0.1), "empty": Color(0.1, 0.1, 0.1)}.get(st, Color(0.2, 0.9, 0.4))
		light(_slots[i], c, st != "empty" and not isolated[i / 6])
		(_slot_carts[i] as Node3D).visible = st != "empty"
	if _filter_mat != null:
		(_filter_mat.material_override as StandardMaterial3D).albedo_color = Color(0.55, 0.53, 0.45, 0.4 + fan_filter * 0.5)
		_filter_mat.visible = not filter_out
	if _fan_lbl != null:
		_fan_lbl.text = "FANS %d / %d / %d rpm · FILTER %s · ARCHIVE %.1f °C" % [int(fans[0]), int(fans[1]), int(fans[2]), "OUT" if filter_out else ("DUSTY" if fan_filter > 0.5 else "OK"), _arch_t()]
	if _screen != null:
		_screen.text = _page_text()


func _arch_t() -> float:
	var s: Node = sys()
	var t: float = float(s.thermal["arch_T"]) if s != null else 22.0
	return t + (float(3000.0 - (fans[0] + fans[1] + fans[2]) / 3.0) / 3000.0) * 8.0


func _page_text() -> String:
	var hdr: String = "ARCHIVE CONSOLE · %s · INDEX %s%s\n" % [PAGES[page], "OK" if index_ok else ("REBUILDING %d s" % int(rebuild_t) if rebuild_t >= 0.0 else "DAMAGED"), "  [UNKNOWN ENTRY]" if not unknown_entry.is_empty() else ""]
	match PAGES[page]:
		"RACKS":
			var rows: Array = []
			for r in 3:
				var bad: Array = []
				for k in 6:
					if cart[r * 6 + k]["state"] != "ok":
						bad.append("%s %s" % [cart[r * 6 + k]["label"], String(cart[r * 6 + k]["state"]).to_upper()])
				rows.append("%s R%d %s %s" % ["▶" if sel % 3 == r else " ", r + 1, "ISOLATED" if isolated[r] else "ON LINE ", ", ".join(bad) if not bad.is_empty() else "6/6 OK"])
			return hdr + "\n".join(rows) + "\nACTION/ALT: isolate / restore the selected rack"
		"INDEX":
			return hdr + "CARTRIDGES %d/18 OK\nACTION: REBUILD INDEX   ALT: INTEGRITY CHECK %s" % [cart.filter(func(c): return c["state"] == "ok").size(), "PASS" if verified_integrity else ""]
		"BACKUP":
			var lines: Array = []
			for sn in snapshots.slice(maxi(snapshots.size() - 3, 0)):
				lines.append("D%d  %d records  %s" % [int(sn["day"]), int(sn["count"]), sn["checksum"]])
			return hdr + ("\n".join(lines) if not lines.is_empty() else "(no snapshots yet)") + "\nREQUIRED: WRS cfg, coolant cfg, Bus B cfg\nACTION: VERIFY latest %s" % ("✓" if backup_verified else "")
		"CORRELATE":
			if corr_question.is_empty():
				return hdr + _correlation_rows(maxi(day() - 1, 1))
			return hdr + "%s\n%s\nACTION: LEGITIMATE   ALT: UNEXPLAINED   %s" % [corr_question["text"], _correlation_rows(int(corr_question["day"])), ("→ " + corr_answer) if corr_answer != "" else ""]
		"RECORDS":
			var out: Array = []
			if not unknown_entry.is_empty():
				out.append("! %s" % unknown_entry["text"])
			for i in mini(PERSONNEL.size(), 3 + sel % 3):
				var rec: Array = PERSONNEL_ALT[i] if (personnel_alt and PERSONNEL_ALT.has(i)) else PERSONNEL[i]
				out.append("%s %s  %s" % [rec[0], rec[1], String(rec[2]).left(130)])
			return hdr + "\n".join(out)
	return hdr


## Aligned rows from the AUTHORITATIVE logs for one day (access, service,
## camera, closed orders) -- what the technician compares.
func _correlation_rows(d: int) -> String:
	var rows: Array = []
	var lg: Node = get_tree().get_first_node_in_group(&"station_log") if is_inside_tree() else null
	if lg != null:
		for k in ["access", "maintenance", "camera"]:
			for e in lg.entries.get(k, []):
				if int(e["day"]) == d:
					rows.append("%s %-6s %s" % [e["t"], k.left(6).to_upper(), String(e["text"]).left(52)])
	rows.sort()
	return "D%d\n%s" % [d, "\n".join(rows.slice(maxi(rows.size() - 6, 0))) if not rows.is_empty() else "(no records)"]


# ------------------------------------------------------------ orders
func task_rearm(t: StringName, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	match t:
		&"b09_racks":
			racks_seen = [false, false, false]
			racks_logged = false
			if rng.randf() < 0.4:
				var i: int = rng.randi() % 18
				cart[i]["state"] = "degraded"
				cart[i]["health"] = 0.6
		&"b09_cartridge":
			cart_target = rng.randi() % 18
			cart[cart_target]["state"] = "failed"
			cart[cart_target]["health"] = 0.1
			cart_replaced = false
			verified_integrity = false
		&"b09_backup":
			backup_verified = false
			backup_corrupt = rng.randf() < 0.4
			if snapshots.is_empty():
				take_snapshot(maxi(day() - 1, 1))
		&"b09_correlate":
			var d: int = maxi(day() - 1, 1)
			var m: int = 9 * 60 + rng.randi() % 300
			var delay: int = 3 + rng.randi() % 6
			corr_question = {"day": d, "truth": "LEGITIMATE", "text": "CONTROL LOG: order closed %02d:%02d · ARCHIVE write %02d:%02d (Δ %d min)\nArchive writes are batched every 10 min." % [m / 60, m % 60, (m + delay) / 60, (m + delay) % 60, delay]}
			corr_answer = ""
		&"b09_fans":
			fan_seed = "bearing" if rng.randf() < 0.25 else "filter"
			fan_filter = 0.85 if fan_seed == "filter" else 0.2
			filter_out = false
			if fan_seed == "bearing":
				fan_spare = maxi(fan_spare, 1)
		&"b09_unknown":
			unknown_checks = {}
			unknown_logged = false
			if unknown_entry.is_empty():
				unknown_entry = {"text": "D%d 03:12 · B-09 · cartridge R3-6 WRITTEN · TECH-1" % maxi(day() - 1, 1), "day": maxi(day() - 1, 1)}
	_refresh()


func task_done(t: StringName) -> bool:
	var done := false
	match t:
		&"b09_racks":
			done = racks_seen.all(func(v): return v) and isolated.all(func(v): return not v)
			if done and not outcome.has(t):
				var degraded: bool = cart.any(func(c): return c["state"] == "degraded")
				close_task(t, "inconclusive" if degraded else "verified_normal", "storage racks R1-R3", "degraded cartridge" if degraded else "none", "rack status checked", "LEDs and console agree")
				if degraded and _dp != null:
					_dp.raise_order(&"b09_cartridge", "degraded cartridge found")
		&"b09_cartridge":
			done = cart_replaced and index_ok and verified_integrity and isolated.all(func(v): return not v)
			if done and not outcome.has(t):
				close_task(t, "repaired", "archive cartridge %s" % cart[cart_target]["label"], "cartridge failed", "rack isolated, cartridge replaced, index rebuilt", "integrity PASS")
		&"b09_backup":
			done = backup_verified
			if done and not outcome.has(t):
				close_task(t, "verified_normal", "backup snapshots", "index damage" if backup_corrupt else "none", "checksums compared", "latest snapshot MATCH, restore eligible")
		&"b09_correlate":
			done = corr_answer != ""
			if done and not outcome.has(t):
				var right: bool = corr_answer == String(corr_question.get("truth", "LEGITIMATE"))
				close_task(t, "verified_normal" if right else "inconclusive", "record correlation D%d" % int(corr_question.get("day", 0)), "timestamp difference", "records aligned", "batched archive write (Δ ≤ 10 min)" if right else "flagged for review")
				corr_question = {}
		&"b09_fans":
			done = not filter_out and fan_filter < 0.2 and fans.all(func(v): return v > 2600.0)
			if done and not outcome.has(t):
				close_task(t, "repaired", "archive fan tray", "dusty filter" if fan_seed != "" else "slow fan (bearing)", "filter cleaned / fan swapped", "fans ≥ 2600 rpm")
		&"b09_unknown":
			done = unknown_logged
			if done and not outcome.has(t):
				close_task(t, "inconclusive", "archive index", "entry with no matching access / camera record", "compared access, camera and rack logs", "UNEXPLAINED — logged for review")
	return done


func task_next(t: StringName) -> Dictionary:
	match t:
		&"b09_racks":
			return next("Check each storage rack's status (R1-R3), all racks on line", "RACKS")
		&"b09_cartridge":
			if not cart_replaced:
				return next("Isolate the rack, remove the failed cartridge %s, seat a blank" % (cart[cart_target]["label"] if cart_target >= 0 else ""), "CARTRIDGE")
			return next("Rebuild the index, integrity check, rack back on line", "REBUILD")
		&"b09_backup":
			return next("Verify the latest archive snapshot (console BACKUP)", "BACKUP")
		&"b09_correlate":
			return next("Correlate the records (console CORRELATE): legitimate or unexplained?", "CORRELATE")
		&"b09_fans":
			return next("Archive fans slow: check the fans and the filter mat", "FANS")
		&"b09_unknown":
			return next("An archive entry nobody made: compare the access, camera and rack records", "UNKNOWN")
	return {}


func task_feasible(t: StringName) -> bool:
	if t == &"b09_cartridge":
		return _cabinet == null or _cabinet.count(&"data_cartridge") > 0
	return true


func state_dict() -> Dictionary:
	return {"cart": cart.duplicate(true), "isolated": isolated.duplicate(), "index_ok": index_ok, "verified_integrity": verified_integrity, "snapshots": snapshots.duplicate(true),
		"page": page, "racks_seen": racks_seen.duplicate(), "cart_target": cart_target, "cart_replaced": cart_replaced, "backup_verified": backup_verified,
		"backup_corrupt": backup_corrupt, "corr_question": corr_question.duplicate(), "corr_answer": corr_answer, "fan_filter": fan_filter, "filter_out": filter_out,
		"fan_seed": fan_seed, "fan_spare": fan_spare, "unknown_entry": unknown_entry.duplicate() if String(unknown_entry.get("story", "")) == "" else {}, "unknown_logged": unknown_logged,
		"tapes_read": tapes_read.duplicate(), "outcome": outcome.duplicate()}


func load_dict(d: Dictionary) -> void:
	for k in d:
		if k == "outcome":
			outcome = {}
			for ok in d[k]:
				outcome[StringName(ok)] = d[k][ok]
		elif k in self:
			set(k, d[k])
	rebuild_t = -1.0
	_refresh()
