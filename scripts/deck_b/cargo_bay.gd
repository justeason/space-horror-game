extends "res://scripts/deck_b/deck_b_room.gd"
## Round 49: B-08 CARGO HANDLING AND DOCKING SUPPORT -- where shipments for
## the lower deck are RECEIVED, checked, sorted and transferred (upper
## Storage keeps the usable parts; this room is not a second Storage).
##   berthing port (west wall): docking status panel, four latch sensors,
##     vestibule pressure gauge, equalisation valve, a hatch handle behind
##     an INTERLOCK (vehicle berthed + all latches + vestibule ≥ 95 kPa +
##     leak check) -- no decorative button can ever depressurise anything;
##   two cargo transfer bags (CTB-1 hard case, CTB-2 soft bag) in restraint
##     frames with straps (microgravity: an unrestrained load drifts);
##     their contents are REAL parts, exactly the shipment, nothing more;
##   the manifest terminal (short codes, one line each), a handheld scanner;
##   the sorting rack: one destination bin per room + QUARANTINE.
## Shipments arrive on a schedule once logistics access exists (resupply
## vehicle LV-B); seeded realistically: sometimes short, sometimes a
## mislabelled item, sometimes a damaged case.
## Tasks: b08_manifest, b08_restraint, b08_discrepancy (S03), b08_seal,
## b08_transfer (component sorting / S02), b08_damaged.

const CODES := {"MF2": &"mf_bed", "IX1": &"ix_bed", "PS7": &"pump_seal_kit", "GL6": &"grow_light_module", "DC": &"data_cartridge", "RM2": &"relay_module", "MED": &"med_pack", "VA3": &"valve_actuator", "LM": &"lamp_module"}
const DEST := {&"mf_bed": "WATER", &"ix_bed": "WATER", &"pump_seal_kit": "WATER", &"grow_light_module": "BOTANY", &"data_cartridge": "ARCHIVE", &"relay_module": "WORKSHOP", &"med_pack": "MEDICAL", &"valve_actuator": "THERMAL", &"lamp_module": "WORKSHOP"}
const DESTS := ["WATER", "THERMAL", "WORKSHOP", "BOTANY", "MEDICAL", "ARCHIVE", "QUARANTINE"]
var shipment: Dictionary = {}       # {id, day, lines: [[code, qty]], seed_kind, damaged_case}
var vehicle: bool = false
var next_arrival: int = -1
var shipments_received: int = 0
var straps: Array = [true, true]    # restrained?
var strap_tension: Array = [3, 3]   # ratchet clicks 0..3
var opened: Array = [false, false]
var scanned: Array = [false, false]
var line_i: int = 0
var line_marks: Array = []          # "" | match | mismatch
var signed: bool = false
var disc_type: int = 0
var disc_logged: String = ""
var latches: Array = [true, true, true, true]
var vest_kpa: float = 0.0
var equalising: bool = false
var leak_t: float = -1.0
var leak_ok: bool = false
var hatch_open: bool = false
var port_checked: bool = false
var damaged_logged: bool = false
var transfer_signed: bool = false

var _ctb: Array = []                # Rack
var _ctb_roots: Array = []
var _strap_nodes: Array = []
var _bins := {}
var _term: Label3D
var _dock: Label3D
var _latch_mats: Array = []
var _vest: Label3D
var _hatch: Node3D
var _eq_wheel: Node3D
var _scan_lbl: Label3D
var _drift_t: float = 0.0


func _ready() -> void:
	_room_ready([&"b08_manifest", &"b08_restraint", &"b08_discrepancy", &"b08_seal", &"b08_transfer", &"b08_damaged"])
	_build_port()
	_build_containers()
	_build_sorting()
	_build_terminal()
	text("B-08  CARGO / DOCKING SUPPORT", Vector3(-6.72, L.FLOOR_Y + 2.75, 7.95), 18, Color(1.0, 0.95, 0.8), self, -90.0)
	if _dp != null and _dp.has_signal(&"day_started"):
		_dp.day_started.connect(_on_day)
	_refresh()


# ------------------------------------------------------------- geometry
func _build_port() -> void:
	var p := Node3D.new()
	p.name = "BerthingPort"
	p.position = Vector3(-9.49, L.FLOOR_Y + 1.25, 7.0)
	p.rotation_degrees.y = 90.0            # faces +x into the room
	add_child(p)
	dcyl(0.6, 0.08, Vector3(0, 0, 0.04), Color(0.55, 0.57, 0.6), p, Vector3(90, 0, 0), 0.6)
	_hatch = Node3D.new()
	_hatch.position = Vector3(-0.5, 0, 0.09)
	p.add_child(_hatch)
	dcyl(0.48, 0.05, Vector3(0.5, 0, 0), Color(0.42, 0.44, 0.47), _hatch, Vector3(90, 0, 0), 0.5)
	dbox(Vector3(0.3, 0.04, 0.05), Vector3(0.5, 0, 0.04), Color(0.95, 0.72, 0.1), _hatch)
	part(&"hatch", Vector3(0.6, 0.6, 0.1), Vector3(0, 0, 0.12), p)
	for k in 4:
		var a: float = TAU * k / 4.0 + PI * 0.25
		var lm := dbox(Vector3(0.04, 0.04, 0.02), Vector3(cos(a) * 0.68, sin(a) * 0.68, 0.06), Color(0.2, 0.2, 0.2), p)
		_latch_mats.append(lm.material_override)
	text("BERTHING PORT CBP-1 · CARGO TRANSFER HATCH", Vector3(0, 0.78, 0.06), 9, Color(0.95, 0.95, 0.9), p)
	var panel := Node3D.new()
	panel.position = Vector3(1.05, 0.2, 0.0)
	p.add_child(panel)
	dbox(Vector3(0.4, 0.5, 0.04), Vector3(0, 0, 0.02), Color(0.2, 0.22, 0.25), panel)
	_dock = readout(Vector3(0, 0.1, 0.042), Vector2(0.36, 0.22), panel, 8)
	button("drive_latch", Vector3(-0.1, -0.16, 0.042), Color(0.95, 0.75, 0.2), panel, Vector3(0.05, 0.03, 0.012))
	button("leak_check", Vector3(0.1, -0.16, 0.042), Color(0.3, 0.8, 0.95), panel, Vector3(0.05, 0.03, 0.012))
	text("DRIVE LATCHES   LEAK CHECK", Vector3(0, -0.2, 0.042), 6, Color(0.95, 0.95, 0.9), panel)
	_vest = readout(Vector3(-1.0, 0.45, 0.02), Vector2(0.18, 0.08), p, 9)
	_eq_wheel = handwheel("equalise", Vector3(-1.0, 0.25, 0.04), 0.06, p, true, Color(0.2, 0.45, 0.75))
	text("VESTIBULE\nEQUALISE", Vector3(-1.0, 0.1, 0.03), 7, Color(0.95, 0.95, 0.9), p)


func _build_containers() -> void:
	for k in 2:
		var root := Node3D.new()
		root.name = "CTB%d" % (k + 1)
		root.position = Vector3(-8.85 + k * 1.15, L.FLOOR_Y + 0.05, 5.4)
		add_child(root)
		_ctb_roots.append(root)
		var col: Color = Color(0.32, 0.35, 0.4) if k == 0 else Color(0.85, 0.82, 0.7)
		dbox(Vector3(0.75, 0.5, 0.45), Vector3(0, 0.25, 0), col, root, 0.3)
		text("CTB-%d %s" % [k + 1, "HARD CASE" if k == 0 else "SOFT BAG"], Vector3(0, 0.42, 0.226), 8, Color(0.95, 0.95, 0.9) if k == 0 else Color(0.1, 0.1, 0.1), root)
		var r: Rack = rack("CargoCTB%d" % (k + 1), Vector3(-0.27, 0.62, 0.0), 4, 0.18, [], "", root, 0.0, false)
		_ctb.append(r)
		var st := dbox(Vector3(0.8, 0.03, 0.04), Vector3(0, 0.52, 0.0), Color(0.95, 0.72, 0.1), root)
		_strap_nodes.append(st)
		part(StringName("strap%d" % k), Vector3(0.2, 0.1, 0.5), Vector3(0.3, 0.45, 0.0), root)
		part(StringName("scan%d" % k), Vector3(0.3, 0.2, 0.06), Vector3(-0.15, 0.3, 0.24), root)
		part(StringName("open%d" % k), Vector3(0.3, 0.1, 0.4), Vector3(-0.15, 0.52, 0.0), root)
	# The restraint frame (fixed), fully collidable.
	dbox(Vector3(2.5, 0.06, 0.6), Vector3(-8.25, L.FLOOR_Y + 0.03, 5.4), Color(0.3, 0.32, 0.34), self, 0.5, true)
	for x in [-9.5, -7.05]:
		dbox(Vector3(0.05, 0.9, 0.05), Vector3(x, L.FLOOR_Y + 0.45, 5.15), Color(0.6, 0.62, 0.65), self)
	text("RESTRAINT FRAME · STRAP EVERY LOAD", Vector3(-8.25, L.FLOOR_Y + 1.0, 5.13), 9, Color(0.95, 0.95, 0.9))


func _build_sorting() -> void:
	var left := ["WATER", "THERMAL", "WORKSHOP"]
	var right := ["BOTANY", "MEDICAL", "ARCHIVE", "QUARANTINE"]
	for k in left.size():
		_bins[left[k]] = rack("Dest" + left[k].capitalize(), Vector3(-9.35 + k * 0.0, L.FLOOR_Y + 0.55 + k * 0.45, 8.75), 3, 0.2, [], "→ " + left[k], self, 180.0)
	for k in right.size():
		_bins[right[k]] = rack("Dest" + right[k].capitalize(), Vector3(-6.85, L.FLOOR_Y + 0.45 + k * 0.42, 8.75), 2, 0.2, [], "→ " + right[k], self, 180.0)


func _build_terminal() -> void:
	var t := Node3D.new()
	t.name = "ManifestTerminal"
	t.position = Vector3(-6.71, L.FLOOR_Y + 1.4, 8.05)
	t.rotation_degrees.y = -90.0
	add_child(t)
	dbox(Vector3(0.5, 0.36, 0.04), Vector3(0, 0, 0.02), Color(0.05, 0.06, 0.07), t)
	_term = text("", Vector3(0, 0.02, 0.042), 7, Color(0.55, 0.95, 0.75), t)
	for k in 4:
		var nm: String = ["next_line", "mark_match", "mark_mismatch", "sign"][k]
		button(nm, Vector3(-0.18 + k * 0.12, -0.21, 0.04), [Color(0.3, 0.8, 0.95), Color(0.3, 0.9, 0.4), Color(0.95, 0.4, 0.2), Color(0.95, 0.85, 0.3)][k], t, Vector3(0.08, 0.03, 0.012))
	text("NEXT   MATCH   DIFFERS   SIGN", Vector3(0, -0.245, 0.04), 6, Color(0.95, 0.95, 0.9), t)
	part(&"disc_type", Vector3(0.2, 0.06, 0.04), Vector3(0.15, 0.14, 0.04), t)
	button("disc_log", Vector3(0.22, 0.2, 0.04), Color(0.95, 0.6, 0.15), t, Vector3(0.05, 0.025, 0.012))
	_scan_lbl = text("", Vector3(-0.9, 0.0, 0.01), 8, Color(0.95, 0.85, 0.5), t)


# --------------------------------------------------------- shipments
var day_handled: int = 0


## Only a REAL new day (DayPlan also emits day_started after a load).
func _on_day(_d: int) -> void:
	if day() <= day_handled:
		return
	var first: bool = day_handled == 0
	day_handled = day()
	if first:
		return
	var clr: Node = get_tree().get_first_node_in_group(&"clearance") if is_inside_tree() else null
	if clr == null or int(clr.deck_b_tier()) < 2:
		return
	if next_arrival < 0:
		next_arrival = day() + 1
	if day() >= next_arrival and shipment.is_empty():
		arrive(hash([day(), "lvb"]))
	elif vehicle and not shipment.is_empty() and transfer_signed:
		vehicle = false            # the vehicle departed overnight


## A resupply vehicle berths; its bags hold exactly the shipment.
func arrive(seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for r in _ctb:
		for it in (r as Rack).items():
			consume_part(it)
	var pool := ["MF2", "PS7", "GL6", "DC", "RM2", "MED", "VA3", "LM"]
	var lines: Array = []
	for k in 4:
		var code: String = pool[rng.randi() % pool.size()]
		if lines.any(func(l): return l[0] == code):
			continue
		lines.append([code, 1 + rng.randi() % 2])
	var kind_roll: int = rng.randi() % 4      # 0 ok, 1 short, 2 mislabel, 3 damaged
	shipments_received += 1
	shipment = {"id": "LV-B%02d" % shipments_received, "day": day(), "lines": lines, "seed_kind": ["ok", "short", "mislabel", "damaged"][kind_roll], "damaged_case": 0}
	# Pack the real items (manifest -> bags), applying the seeded truth.
	var slot := 0
	for li in lines.size():
		var code2: String = lines[li][0]
		var qty: int = int(lines[li][1])
		if shipment["seed_kind"] == "short" and li == 0:
			qty -= 1
		for q in qty:
			var kind: StringName = CODES[code2]
			if shipment["seed_kind"] == "mislabel" and li == 0 and q == 0:
				kind = &"ix_bed" if kind != &"ix_bed" else &"mf_bed"
			var cond: float = 1.0
			if shipment["seed_kind"] == "damaged" and slot == 0:
				cond = 0.3
			var r2: Rack = _ctb[0 if slot < 4 else 1]
			if r2.free_slot() != -1:
				spawn_part(kind, r2, {"condition": cond, "state": "new" if cond > 0.5 else "damaged", "label": code2, "grade": "A", "calibrated": true, "history": [{"day": day(), "text": "received %s" % shipment["id"]}]})
			slot += 1
	line_marks = []
	for l in lines:
		line_marks.append("")
	line_i = 0
	signed = false
	disc_logged = ""
	transfer_signed = false
	damaged_logged = false
	opened = [false, false]
	scanned = [false, false]
	straps = [true, true]
	strap_tension = [3, 3]
	vehicle = true
	for r3 in _ctb:
		(r3 as Rack).locked = true
	next_arrival = day() + 6
	var lg: Node = get_tree().get_first_node_in_group(&"station_log")
	if lg != null:
		lg.record("airlock", "CBP-1 · resupply vehicle %s berthed (lower deck)" % shipment["id"])
	if _dp != null and _dp.has_method("raise_order"):
		_dp.raise_order(&"b08_manifest", "shipment %s berthed" % shipment["id"])
		if shipment["seed_kind"] == "damaged":
			_dp.raise_order(&"b08_damaged", "damaged case reported")
	_refresh()


## The REAL contents of the bags: kind -> count, and labels.
func contents() -> Dictionary:
	var by: Dictionary = {}
	for r in _ctb:
		for it in (r as Rack).items():
			var code: String = String(it.payload.get("label", ""))
			by[code] = int(by.get(code, 0)) + 1
	return by


func _line_truth(i: int) -> bool:
	var l: Array = shipment["lines"][i]
	var code: String = l[0]
	var n := 0
	for r in _ctb:
		for it in (r as Rack).items():
			if String(it.payload.get("label", "")) == code and it.item_id == CODES[code]:
				n += 1
	return n == int(l[1])


# --------------------------------------------------------------- clicks
func on_part(id: StringName) -> void:
	var sid: String = String(id)
	if sid == "equalise_up" or sid == "equalise_dn":
		equalising = sid == "equalise_up" and vehicle
		sfx(&"ratchet")
		say("Equalisation valve %s" % ("OPEN — vestibule filling from the cabin" if equalising else "closed"))
		if not vehicle and sid == "equalise_up":
			say("PORT CAPPED (no vehicle): the equalisation valve is locked out.")
		_refresh()
		return
	match sid:
		"hatch":
			_hatch_click()
		"drive_latch":
			if not vehicle:
				say("No vehicle berthed: latches stowed.")
			else:
				latches = [true, true, true, true]
				sfx(&"clunk")
				say("Latches driven: 4/4 ENGAGED.")
		"leak_check":
			if not vehicle:
				port_checked = true
				say("PORT CAPPED · cabin-side seal: no pressure change in 10 s. OK.")
			elif equalising:
				say("Close the equalisation valve before a leak check.")
			elif vest_kpa < 95.0:
				say("Vestibule at %.0f kPa — equalise first." % vest_kpa)
			else:
				leak_t = 0.0
				say("Leak check: holding vestibule pressure for 10 s…")
		"next_line":
			if not shipment.is_empty():
				line_i = (line_i + 1) % shipment["lines"].size()
				sfx(&"click")
		"mark_match", "mark_mismatch":
			_mark(sid == "mark_match")
		"sign":
			_sign()
		"disc_type":
			disc_type = (disc_type + 1) % 4
			sfx(&"click")
		"disc_log":
			_disc_log()
		_:
			if sid.begins_with("strap"):
				var k: int = int(sid.substr(5))
				if straps[k] and strap_tension[k] >= 3:
					straps[k] = false
					strap_tension[k] = 0
					(_ctb[k] as Rack).locked = false
					sfx(&"ratchet")
					say("CTB-%d strap released." % (k + 1))
				else:
					strap_tension[k] = mini(strap_tension[k] + 1, 3)
					straps[k] = true
					(_ctb[k] as Rack).locked = strap_tension[k] >= 3 and not opened[k]
					sfx(&"ratchet")
					say("CTB-%d strap: %s" % [k + 1, "TIGHT — restrained" if strap_tension[k] >= 3 else "tension %d/3" % strap_tension[k]])
			elif sid.begins_with("scan"):
				var k2: int = int(sid.substr(4))
				scanned[k2] = true
				var items: Array = (_ctb[k2] as Rack).items()
				var labels: Array = items.map(func(it): return String(it.payload.get("label", "?")))
				say("SCAN CTB-%d (%s): %d item(s) %s" % [k2 + 1, shipment.get("id", "-"), items.size(), " ".join(labels)])
			elif sid.begins_with("open"):
				var k3: int = int(sid.substr(4))
				if straps[k3] and strap_tension[k3] >= 3:
					say("Release CTB-%d's restraint before opening it." % (k3 + 1))
					return
				opened[k3] = not opened[k3]
				(_ctb[k3] as Rack).locked = not opened[k3]
				sfx(&"latch")
	_refresh()


func _mark(match_btn: bool) -> void:
	if shipment.is_empty() or signed:
		return
	if not (scanned[0] and scanned[1] and opened[0] and opened[1]):
		say("Scan and open both bags before confirming lines.")
		return
	var truth: bool = _line_truth(line_i)
	if match_btn and not truth:
		say("The bag contents disagree with line %d — count again (labels and parts)." % (line_i + 1))
		sfx(&"fail")
		return
	line_marks[line_i] = "match" if match_btn else "mismatch"
	sfx(&"click")
	if not match_btn:
		say("Line %d marked MISMATCH." % (line_i + 1))
		if _dp != null:
			_dp.raise_order(&"b08_discrepancy", "manifest line %d" % (line_i + 1))
	line_i = (line_i + 1) % shipment["lines"].size()


func _sign() -> void:
	if shipment.is_empty():
		return
	if line_marks.has(""):
		say("Confirm every manifest line first.")
		return
	if not signed:
		signed = true
		sfx(&"success")
		say("Manifest %s signed. Sort the parts to their destinations." % shipment["id"])
		if _dp != null:
			_dp.raise_order(&"b08_transfer", "manifest %s accepted" % shipment["id"])
	elif _containers_empty() and _sorted_ok():
		transfer_signed = true
		sfx(&"success")
		say("Transfer complete.")


func _disc_log() -> void:
	var types := ["MISSING", "MISLABELLED", "DAMAGED", "COUNT ERROR"]
	var truth: String = {"short": "MISSING", "mislabel": "MISLABELLED", "damaged": "DAMAGED", "ok": "COUNT ERROR"}.get(String(shipment.get("seed_kind", "ok")), "COUNT ERROR")
	if types[disc_type] != truth:
		say("Logged %s — but the evidence (scanner labels / counts / packing) doesn't show that." % types[disc_type])
		sfx(&"fail")
		return
	disc_logged = truth
	sfx(&"success")
	say("Discrepancy recorded: %s." % truth)


func _hatch_click() -> void:
	if hatch_open:
		hatch_open = false
		sfx(&"clunk")
		return
	var why: String = ""
	if not vehicle:
		why = "PORT CAPPED — no vehicle berthed."
	elif not latches.all(func(v): return v):
		why = "INTERLOCK: latches not engaged."
	elif vest_kpa < 95.0:
		why = "INTERLOCK: vestibule %.0f kPa (needs ≥ 95)." % vest_kpa
	elif not leak_ok:
		why = "INTERLOCK: leak check not passed."
	var clr: Node = _dp.clearance() if _dp != null else null
	if why == "" and clr != null and not clr.deck_b_room_open(&"b08"):
		why = "Not authorised."
	if why != "":
		say(why)
		sfx(&"fail")
		return
	hatch_open = true
	sfx(&"clunk")
	say("Hatch open to the vehicle (pressurised).")


func part_prompt(id: StringName) -> String:
	var sid: String = String(id)
	match sid:
		"equalise_up": return "Click: open equalisation valve"
		"equalise_dn": return "Click: close equalisation valve"
		"hatch": return "Click: %s transfer hatch" % ("close" if hatch_open else "open")
		"drive_latch": return "Click: DRIVE LATCHES"
		"leak_check": return "Click: LEAK CHECK"
		"next_line": return "Click: next manifest line"
		"mark_match": return "Click: line MATCHES the bags"
		"mark_mismatch": return "Click: line MISMATCH"
		"sign": return "Click: SIGN (manifest / transfer)"
		"disc_type": return "Click: discrepancy type"
		"disc_log": return "Click: log discrepancy"
	if sid.begins_with("strap"): return "Click: CTB-%d restraint strap" % (int(sid.substr(5)) + 1)
	if sid.begins_with("scan"): return "Click: scan CTB-%d label" % (int(sid.substr(4)) + 1)
	if sid.begins_with("open"): return "Click: %s CTB-%d" % ["close" if opened[int(sid.substr(4))] else "open", int(sid.substr(4)) + 1]
	return ""


func on_rack_stowed(r: Rack, item: Node3D) -> void:
	if r == _bins.get("QUARANTINE") and float(item.payload.get("condition", 1.0)) < 0.5:
		damaged_logged = true
		item.payload["state"] = "quarantined"
		if item.has_method("refresh"):
			item.refresh()
		say("Damaged part quarantined.")


func _containers_empty() -> bool:
	return _ctb.all(func(r): return (r as Rack).count() == 0)


func _sorted_ok() -> bool:
	for d in _bins:
		for it in (_bins[d] as Rack).items():
			var want: String = "QUARANTINE" if float(it.payload.get("condition", 1.0)) < 0.5 else String(DEST.get(it.item_id, ""))
			if want != d:
				return false
	return true


# --------------------------------------------------------------- update
func _process(delta: float) -> void:
	_update_occlusion(delta)
	if equalising and vehicle:
		vest_kpa = minf(vest_kpa + delta * 10.0, 101.3)
		var env: Node = _dp.get_parent().get_node_or_null("EnvironmentModel") if _dp != null else null
		if env != null and vest_kpa < 101.0:
			env.pressure_kpa = maxf(float(env.pressure_kpa) - delta * 0.004, 99.0)
	if leak_t >= 0.0:
		leak_t += delta
		if leak_t >= 10.0:
			leak_t = -1.0
			leak_ok = true
			port_checked = true
			say("Leak check PASS (vestibule steady).")
	_drift_t += delta
	for k in 2:
		var loose: bool = not straps[k] or strap_tension[k] < 3
		var root: Node3D = _ctb_roots[k]
		root.position.y = L.FLOOR_Y + 0.05 + (sin(_drift_t * 0.7 + k) * 0.03 + 0.04 if loose else 0.0)
		root.rotation.z = sin(_drift_t * 0.5 + k) * 0.05 if loose else 0.0
	if Engine.get_process_frames() % 6 == 0 and is_visible_in_tree():
		_refresh()


func _refresh() -> void:
	for k in _latch_mats.size():
		light(_latch_mats[k], Color(0.3, 0.95, 0.4) if latches[k] else Color(1.0, 0.25, 0.15), vehicle)
	if _hatch != null:
		_hatch.rotation_degrees.y = -95.0 if hatch_open else 0.0
	set_wheel(_eq_wheel, 1.0 if equalising else 0.0)
	if _vest != null:
		_vest.text = "%.0f kPa" % vest_kpa
	if _dock != null:
		_dock.text = "VEHICLE %s\nLATCHES %d/4  VEST %.0f kPa\nLEAK %s  HATCH %s" % [shipment.get("id", "") + " BERTHED" if vehicle else "NONE · PORT CAPPED", latches.count(true) if vehicle else 0, vest_kpa,
			"PASS" if leak_ok else ("TESTING" if leak_t >= 0.0 else "-"), "OPEN" if hatch_open else "LOCKED"]
	for k in _strap_nodes.size():
		(_strap_nodes[k] as Node3D).visible = straps[k]
		((_strap_nodes[k] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = Color(0.95, 0.72, 0.1) if strap_tension[k] >= 3 else Color(0.95, 0.4, 0.15)
	if _term != null:
		if shipment.is_empty():
			_term.text = "MANIFEST — NO SHIPMENT\nNEXT LV-B: DAY %s" % (str(next_arrival) if next_arrival > 0 else "-")
		else:
			var rows: Array = ["%s  DAY %d  %s" % [shipment["id"], int(shipment["day"]), "SIGNED" if signed else "OPEN"]]
			for i in shipment["lines"].size():
				var l: Array = shipment["lines"][i]
				rows.append("%s %-4s x%d  → %-9s %s" % ["▶" if i == line_i else " ", l[0], int(l[1]), DEST.get(CODES[l[0]], ""), {"": "", "match": "✓", "mismatch": "✗"}[line_marks[i]]])
			rows.append("DISCREP ▶ %s %s" % [["MISSING", "MISLABELLED", "DAMAGED", "COUNT ERROR"][disc_type], ("· LOGGED " + disc_logged) if disc_logged != "" else ""])
			_term.text = "\n".join(rows)


# ------------------------------------------------------------ orders
func task_rearm(t: StringName, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	match t:
		&"b08_manifest":
			if shipment.is_empty() or signed:
				arrive(seed)
		&"b08_restraint":
			var k: int = rng.randi() % 2
			strap_tension[k] = 1
			straps[k] = true
			(_ctb[k] as Rack).locked = false
		&"b08_discrepancy":
			disc_logged = ""
		&"b08_seal":
			port_checked = false
			leak_ok = false
			vest_kpa = 0.0
			equalising = false
			if vehicle:
				latches[rng.randi() % 4] = false
		&"b08_transfer":
			transfer_signed = false
		&"b08_damaged":
			damaged_logged = false
	_refresh()


func task_done(t: StringName) -> bool:
	var done := false
	match t:
		&"b08_manifest":
			done = signed
			if done and not outcome.has(t):
				close_task(t, "verified_normal" if not line_marks.has("mismatch") else "inconclusive", "manifest %s" % shipment.get("id", ""), "none" if not line_marks.has("mismatch") else "line mismatch", "bags scanned, opened, lines confirmed", "manifest signed")
		&"b08_restraint":
			done = straps.all(func(v): return v) and strap_tension.all(func(v): return v >= 3) and opened.all(func(v): return not v)
			if done and not outcome.has(t):
				close_task(t, "repaired", "cargo restraint frame", "loose strap (load drifting)", "straps tensioned", "both bags restrained")
		&"b08_discrepancy":
			done = disc_logged != ""
			if done and not outcome.has(t):
				close_task(t, {"MISSING": "no_part", "MISLABELLED": "repaired", "DAMAGED": "deferred", "COUNT ERROR": "verified_normal"}.get(disc_logged, "inconclusive"), "shipment %s" % shipment.get("id", ""), disc_logged.to_lower(), "recount / scan / packing check", "discrepancy logged")
		&"b08_seal":
			done = port_checked and (not vehicle or (latches.all(func(v): return v) and leak_ok))
			if done and not outcome.has(t):
				close_task(t, "verified_normal", "berthing port CBP-1", "latch sensor" if vehicle else "none", "latches driven, vestibule equalised, leak check" if vehicle else "cap seal check", "interlocks satisfied")
		&"b08_transfer":
			done = transfer_signed
			if done and not outcome.has(t):
				close_task(t, "verified_normal", "sorting rack", "none", "parts sorted to destination bins", "bags empty, transfer signed")
		&"b08_damaged":
			done = damaged_logged
			if done and not outcome.has(t):
				close_task(t, "deferred", "CTB-1 (dented case)", "damaged part", "quarantined", "workshop bench test pending")
	return done


func task_next(t: StringName) -> Dictionary:
	match t:
		&"b08_manifest":
			if not (scanned[0] and scanned[1]):
				return next("Scan both cargo bags (Cargo, restraint frame)", "SCAN")
			if not (opened[0] and opened[1]):
				return next("Release the straps and open both bags", "OPEN")
			return next("Confirm each manifest line (MATCH / MISMATCH), then SIGN", "MANIFEST")
		&"b08_restraint":
			return next("Tension every cargo strap (3 clicks), bags closed", "RESTRAIN")
		&"b08_discrepancy":
			return next("Investigate the mismatch (recount, scan labels, packing) and log its type", "DISCREPANCY")
		&"b08_seal":
			return next("Docking seal: latches, equalise the vestibule, leak check" if vehicle else "Check the capped berthing port's seal", "BERTH SEAL")
		&"b08_transfer":
			return next("Sort every received part to its destination bin, then SIGN the transfer", "SORT")
		&"b08_damaged":
			return next("Find the damaged part in CTB-1 and put it in QUARANTINE", "QUARANTINE")
	return {}


func task_feasible(t: StringName) -> bool:
	if t in [&"b08_restraint"]:
		return not shipment.is_empty()
	return true


func state_dict() -> Dictionary:
	return {"shipment": shipment.duplicate(true), "vehicle": vehicle, "next_arrival": next_arrival, "shipments_received": shipments_received, "straps": straps.duplicate(),
		"strap_tension": strap_tension.duplicate(), "opened": opened.duplicate(), "scanned": scanned.duplicate(), "line_i": line_i, "line_marks": line_marks.duplicate(),
		"signed": signed, "disc_logged": disc_logged, "latches": latches.duplicate(), "vest_kpa": vest_kpa, "leak_ok": leak_ok, "hatch_open": hatch_open,
		"port_checked": port_checked, "damaged_logged": damaged_logged, "transfer_signed": transfer_signed, "outcome": outcome.duplicate()}


func load_dict(d: Dictionary) -> void:
	for k in d:
		if k == "outcome":
			outcome = {}
			for ok in d[k]:
				outcome[StringName(ok)] = d[k][ok]
		elif k in self:
			set(k, d[k])
	equalising = false
	leak_t = -1.0
	day_handled = day()
	for k2 in _ctb.size():
		(_ctb[k2] as Rack).locked = straps[k2] and strap_tension[k2] >= 3 and not opened[k2]
	_refresh()
