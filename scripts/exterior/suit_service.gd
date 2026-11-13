extends "res://scripts/deck_b/deck_b_room.gd"
## Round 50 -- A01 EVA SUIT INSPECTION on the station's ONE suit (the
## stowed EVA suit A-1 in the airlock tunnel locker, eva_system.gd). This
## node owns the suit's AUTHORITATIVE condition (saved):
##   o2 / batt     reserve 0..1 -- used up outside (real gameplay time),
##                 topped up ONLY through the locker umbilical (a slow
##                 trickle while stowed, or FILL / CHARGE at the panel)
##   seal          "" | neck (O-ring nick: needs a suit seal kit) |
##                 glove_L / glove_R (wrist disconnect not fully locked)
##   comms         "" | connector (helmet comm-cap connector unseated)
##   hooks         [ok, ok] -- a tether hook gate that sticks needs service
##   supply        the O2 supply valve to the umbilical (a closed supply
##                 = the LOW OXYGEN fault: no trickle, FILL refused)
##   charger       the umbilical charger breaker (tripped = LOW BATTERY)
## Physical inspection targets ON the stowed suit (helmet / neck ring, both
## gloves, both boots, both tether hooks, the chest diagnostic connector)
## and the SUIT SERVICE PANEL beside the locker (pressure-hold test, O2 and
## battery, comms check, supply valve, charger reset, SIGN OFF). The
## pressure test uses the real seal state; the comms check the real comm
## state. Any fault flags FULL INSPECTION DUE (the suit's own telemetry),
## so a faulty suit is never worn by accident; a healthy suit only needs
## the short pre-EVA status (O2 / battery) -- not the whole checklist every
## time. The full check is also due every FULL_DAYS days / FULL_EVAS EVAs.
## Also here: the EVA REPAIR STOCK shelf and the SUIT TOOL CADDY (the
## parts an exterior repair takes outside -- real items, consumed there).

const FULL_DAYS := 7
const FULL_EVAS := 5
const O2_USE_S := 720.0            # a full reserve lasts 12 min outside
const BATT_USE_S := 1500.0
const TRICKLE_S := 900.0           # stowed on the umbilical: empty -> full
const FILL_S := 60.0               # FILL / CHARGE at the panel: empty -> full
const PTEST_S := 6.0
const STEPS := ["helmet", "gloves", "boots", "hooks", "diag", "ptest", "o2", "batt", "comms"]

var suit := {"o2": 1.0, "batt": 1.0, "seal": "", "comms": "", "hooks": [true, true], "supply": true, "charger": true,
	"full_due": false, "last_full_day": 0, "evas_since": 0, "status": "GO"}
var insp := {}                     # step -> true / "pass" / "fail"
var seen := {}                     # target -> inspected this cycle
var filling: bool = false
var charging: bool = false
var ptest_t: float = -1.0
var anomaly_log: Array = []        # story-gated hook (never written by normal play)
var _was_outside: bool = false
var _panel_lbl: Label3D
var _marks := {}                   # visual fault markers on the stowed suit
var _built: bool = false
var caddy: Rack
var stock: Rack


func _ready() -> void:
	room_id = &"airlock"
	add_to_group(&"suit_service")
	_room_ready([&"a01_suit"])
	_build_panel()
	_build_racks()
	_build_on_suit.call_deferred()
	_reset_insp()


func _eva() -> Node:
	return get_tree().get_first_node_in_group(&"eva_system") if is_inside_tree() else null


func _layer_a(n: Node) -> void:
	for c in n.get_children():
		if c is VisualInstance3D:
			(c as VisualInstance3D).layers = 1
		_layer_a(c)


## Tunnel corridor edge for pick boxes on the stowed suit (path x ~ -4.8,
## player clearance radius 0.3).
const SUIT_PICK_MAX_X := -5.115


static func _done(v) -> bool:
	return (v is bool and v) or (v is String and v == "pass")


func _reset_insp() -> void:
	insp = {}
	seen = {}
	ptest_t = -1.0


# ------------------------------------------------------------ geometry
func _build_panel() -> void:
	var p := Node3D.new()
	p.name = "SuitServicePanel"
	p.position = Vector3(-5.198, 1.35, 1.78)
	p.rotation_degrees.y = 90.0                    # faces +x into the tunnel
	add_child(p)
	dbox(Vector3(0.44, 0.46, 0.04), Vector3(0, 0, 0.02), Color(0.2, 0.22, 0.25), p)
	dbox(Vector3(0.46, 0.035, 0.05), Vector3(0, 0.235, 0.02), Color(0.95, 0.72, 0.1), p)
	text("SUIT SERVICE · A-1 UMBILICAL", Vector3(0, 0.2, 0.042), 8, Color(0.95, 0.95, 0.9), p)
	_panel_lbl = readout(Vector3(-0.05, 0.07, 0.042), Vector2(0.32, 0.2), p, 7)
	part(&"panel_read", Vector3(0.32, 0.2, 0.05), Vector3(-0.05, 0.07, 0.05), p)
	var bx: Array = [["ptest", "P-TEST", Color(0.2, 0.55, 0.3)], ["fill", "O2 FILL", Color(0.3, 0.8, 0.9)], ["charge", "CHARGE", Color(0.9, 0.75, 0.2)], ["comms", "COMMS", Color(0.35, 0.55, 0.95)], ["signoff", "SIGN OFF", Color(0.25, 0.9, 0.4)]]
	for i in bx.size():
		var x: float = -0.17 + i * 0.085
		button(bx[i][0], Vector3(x, -0.1, 0.045), bx[i][2], p, Vector3(0.06, 0.035, 0.02))
		text(bx[i][1], Vector3(x, -0.135, 0.042), 5, Color(0.9, 0.9, 0.9), p)
	# O2 supply valve (quarter-turn handle) and the charger breaker.
	var hv := dbox(Vector3(0.09, 0.02, 0.02), Vector3(0.16, 0.12, 0.05), Color(0.3, 0.8, 0.9), p)
	hv.name = "SupplyHandle"
	part(&"supply", Vector3(0.1, 0.08, 0.06), Vector3(0.16, 0.12, 0.05), p)
	text("O2 SUPPLY", Vector3(0.16, 0.08, 0.042), 5, Color(0.9, 0.9, 0.9), p)
	var cb := dbox(Vector3(0.025, 0.05, 0.02), Vector3(0.16, -0.0, 0.05), Color(0.15, 0.15, 0.15), p)
	cb.name = "ChargerBreaker"
	part(&"charger", Vector3(0.08, 0.08, 0.06), Vector3(0.16, 0.0, 0.05), p)
	text("CHGR CB", Vector3(0.16, -0.04, 0.042), 5, Color(0.9, 0.9, 0.9), p)
	# The umbilical from the panel to the locker's service port.
	dcyl(0.012, 0.6, Vector3(-0.2, -0.22, 0.05), Color(0.2, 0.22, 0.26), p, Vector3(0, 0, 90), 0.2)
	_layer_a(p)
	flush_clicks(p, 0.045)                      # out of the tunnel's walking band


func _build_racks() -> void:
	# EVA repair stock: a shelf under the panel. The caddy: a small tray on
	# the locker's side frame -- what is in it goes outside with the suit.
	stock = rack("EvaRepairStock", Vector3(-5.17, 0.78, 2.365), 5, 0.17, [&"hull_patch_kit", &"seam_seal_kit", &"hull_panel", &"suit_seal_kit", &"hull_panel_damaged"], "EVA REPAIR STOCK", self, 90.0)
	caddy = rack("SuitCaddy", Vector3(-5.17, 1.02, 0.56), 2, 0.17, [&"hull_patch_kit", &"seam_seal_kit", &"hull_panel", &"hull_panel_damaged"], "SUIT CADDY", self, 90.0)
	_layer_a(stock)
	_layer_a(caddy)
	_stock.call_deferred()


func _stock() -> void:
	for kind in [&"hull_patch_kit", &"hull_patch_kit", &"seam_seal_kit", &"suit_seal_kit"]:
		var it: Node3D = spawn_part(kind, stock, {"history": [{"day": day(), "text": "EVA repair stock"}]})
		it.add_to_group(&"r50_stock")
	# The spare MMOD cover panel takes the fifth (end) slot.
	var pn: Node3D = spawn_part(&"hull_panel", stock, {"history": [{"day": day(), "text": "EVA repair stock"}]})
	pn.add_to_group(&"r50_stock")


## Inspection targets ON the stowed suit, placed from the rig's own bones
## (after the locker has built it).
func _build_on_suit() -> void:
	var e: Node = _eva()
	for i in 30:
		if e != null and e.get("locker_rig") != null and (e.locker_rig as Node3D).is_inside_tree():
			break
		await get_tree().process_frame
		e = _eva()
	if e == null or e.get("locker_rig") == null or not (e.locker_rig as Node3D).is_inside_tree() or _built:
		return
	_built = true
	var rig: Node3D = e.locker_rig
	var host := Node3D.new()
	host.name = "SuitTargets"
	add_child(host)
	var g := func(b: String, off: Vector3 = Vector3.ZERO) -> Vector3:
		return rig.to_global(rig.bone_pos(b)) + off
	var out := Vector3(0.1, 0, 0)                 # toward the tunnel
	_target(host, &"t_helmet", g.call("Head", Vector3(0.05, 0.08, 0)), Vector3(0.28, 0.26, 0.3))
	_target(host, &"t_neck", g.call("Neck", Vector3(0.12, -0.02, 0)), Vector3(0.12, 0.08, 0.3))
	_target(host, &"t_glove_L", g.call("LeftHand", out), Vector3(0.14, 0.16, 0.14))
	_target(host, &"t_glove_R", g.call("RightHand", out), Vector3(0.14, 0.16, 0.14))
	_target(host, &"t_boots", (g.call("LeftFoot") + g.call("RightFoot")) * 0.5 + Vector3(0.12, 0.05, 0), Vector3(0.2, 0.18, 0.4))
	_target(host, &"t_diag", g.call("Chest", Vector3(0.16, 0.02, 0.0)), Vector3(0.08, 0.1, 0.12))
	var hips: Vector3 = g.call("Hips")
	for k in 2:
		var hp: Vector3 = hips + Vector3(0.16, -0.02, -0.16 if k == 0 else 0.16)
		_target(host, StringName("t_hook_%d" % k), hp, Vector3(0.1, 0.12, 0.1))
		# The hook itself (a carabiner on the harness D-ring) + its tag.
		var hk := Node3D.new()
		hk.position = hp
		host.add_child(hk)
		dbox(Vector3(0.02, 0.07, 0.035), Vector3.ZERO, Color(0.8, 0.8, 0.82), hk, 0.8)
		dbox(Vector3(0.012, 0.03, 0.012), Vector3(0.0, -0.045, 0.0), Color(0.6, 0.6, 0.62), hk, 0.8)
		var tag := dbox(Vector3(0.006, 0.05, 0.035), Vector3(0.02, -0.06, 0.0), Color(1.0, 0.45, 0.05), hk, 0.1)
		_marks["hook_%d" % k] = tag
	# Wrist lock indicator bands (green = locked, red = not) and the comm cap.
	for side in ["L", "R"]:
		var wp: Vector3 = g.call("LeftHand" if side == "L" else "RightHand", Vector3(0.0, 0.07, 0))
		var band := dcyl(0.045, 0.02, wp, Color(0.2, 0.9, 0.3), host, Vector3.ZERO, 0.2)
		_marks["wrist_" + side] = band
	var cap := dbox(Vector3(0.04, 0.05, 0.03), g.call("Head", Vector3(0.0, 0.0, 0.15)), Color(0.2, 0.2, 0.22), host, 0.4)
	_marks["comm_cap"] = cap
	var ring := dcyl(0.13, 0.025, g.call("Neck", Vector3(0.0, -0.03, 0.0)), Color(0.75, 0.75, 0.78), host, Vector3.ZERO, 0.8)
	_marks["neck_ring"] = ring
	_layer_a(host)
	_refresh()


func _target(host: Node3D, id: StringName, pos: Vector3, size: Vector3) -> void:
	var n := Node3D.new()
	# The stowed suit hangs out into the tunnel; a pick box that reaches into
	# the walking band (y > ~1.1) is pushed back behind the suit's surface
	# (rays pass through the suit's meshes) so it stays out of the corridor.
	if pos.y + size.y * 0.5 > 1.1 and pos.x + size.x * 0.5 > SUIT_PICK_MAX_X:
		var lo: float = minf(pos.x - size.x * 0.5, SUIT_PICK_MAX_X - 0.06)
		size.x = SUIT_PICK_MAX_X - lo
		pos.x = (SUIT_PICK_MAX_X + lo) * 0.5
	n.position = pos
	host.add_child(n)
	part(id, size, Vector3.ZERO, n)


# -------------------------------------------------------- interaction
func on_part(id: StringName) -> void:
	var e: Node = _eva()
	if e != null and e.suited and String(id).begins_with("t_"):
		say("The suit is being worn — inspect it when it is stowed.")
		return
	match String(id):
		"t_helmet": _helmet()
		"t_neck": _neck()
		"t_glove_L": _glove("L")
		"t_glove_R": _glove("R")
		"t_boots":
			seen["boots"] = true
			insp["boots"] = true
			sfx(&"click")
			say("Boots: heel and toe interfaces locked, soles intact, restraint cleats clean.")
		"t_hook_0": _hook(0)
		"t_hook_1": _hook(1)
		"t_diag":
			insp["diag"] = true
			sfx(&"latch")
			say("Diagnostic umbilical connected to the chest port — panel tests available.")
		"panel_read": _read_panel()
		"ptest": _ptest()
		"fill": _fill()
		"charge": _charge()
		"comms": _comms()
		"supply":
			suit["supply"] = not bool(suit["supply"])
			sfx(&"ratchet")
			say("O2 supply valve %s." % ("OPEN" if suit["supply"] else "CLOSED"))
		"charger":
			if not bool(suit["charger"]):
				suit["charger"] = true
				sfx(&"breaker")
				say("Charger breaker reset — CHARGE available.")
			else:
				say("Charger breaker: ON.")
		"signoff": _signoff()
	_refresh()


func part_prompt(id: StringName) -> String:
	var e: Node = _eva()
	if e != null and e.suited and String(id).begins_with("t_"):
		return ""
	match String(id):
		"t_helmet": return "Click: %s" % ("Reseat the comm-cap connector" if seen.get("helmet", false) and suit["comms"] == "connector" else "Inspect helmet, visor and comm cap")
		"t_neck": return "Click: %s" % ("Replace the neck-ring O-ring (suit seal kit)" if held_kind() == &"suit_seal_kit" else "Inspect the neck ring seal")
		"t_glove_L", "t_glove_R":
			var sd: String = String(id).right(1)
			return "Click: %s %s glove" % ["Lock the wrist disconnect on the" if seen.get("glove_" + sd, false) and suit["seal"] == "glove_" + sd else "Inspect the", "left" if sd == "L" else "right"]
		"t_boots": return "Click: Inspect boot interfaces"
		"t_hook_0", "t_hook_1":
			var k: int = int(String(id).right(1))
			return "Click: %s tether hook %s" % ["Clean and cycle the gate of" if seen.get("hook_%d" % k, false) and not suit["hooks"][k] else "Inspect", "AB"[k]]
		"t_diag": return "Click: Connect the diagnostic umbilical"
		"panel_read": return "Click: Read suit status"
		"ptest": return "Click: Suit pressure-integrity test"
		"fill": return "Click: %s O2 fill" % ("Stop" if filling else "Start")
		"charge": return "Click: %s battery charge" % ("Stop" if charging else "Start")
		"comms": return "Click: Suit radio check with the station"
		"supply": return "Click: %s the O2 supply valve" % ("Close" if suit["supply"] else "Open")
		"charger": return "Click: Charger breaker"
		"signoff": return "Click: Sign off the suit inspection"
	return ""


func _helmet() -> void:
	if seen.get("helmet", false) and suit["comms"] == "connector":
		suit["comms"] = ""
		sfx(&"latch")
		say("Comm-cap connector reseated and latched. Re-run the comms check.")
		insp.erase("comms")
		return
	seen["helmet"] = true
	sfx(&"click")
	var notes: Array = ["visor clean, no crazing"]
	notes.append("comm-cap connector UNSEATED (bent latch)" if suit["comms"] == "connector" else "comm cap seated")
	if seen.get("neck", false):
		insp["helmet"] = true
	say("Helmet: %s. Check the neck ring too." % ", ".join(notes) if not seen.get("neck", false) else "Helmet: %s." % ", ".join(notes), 4.0)


func _neck() -> void:
	if held_kind() == &"suit_seal_kit" and suit["seal"] == "neck" and seen.get("neck", false):
		consume_part(held())
		suit["seal"] = ""
		sfx(&"success")
		say("Neck-ring O-ring replaced and lubricated. Re-run the pressure test.")
		insp.erase("ptest")
		return
	seen["neck"] = true
	sfx(&"click")
	if suit["seal"] == "neck":
		say("Neck ring: a NICK in the O-ring at 4 o'clock — it will leak. Replace it (suit seal kit, EVA repair stock).", 4.5)
	else:
		say("Neck ring: O-ring intact and lubricated, bearing turns freely.")
	if seen.get("helmet", false):
		insp["helmet"] = true


func _glove(sd: String) -> void:
	var key: String = "glove_" + sd
	if seen.get(key, false) and suit["seal"] == key:
		suit["seal"] = ""
		sfx(&"latch")
		say("%s wrist disconnect pushed home — lock indicator GREEN. Re-run the pressure test." % ("Left" if sd == "L" else "Right"))
		insp.erase("ptest")
		return
	seen[key] = true
	sfx(&"click")
	say("%s glove: %s." % ["Left" if sd == "L" else "Right", "wrist disconnect NOT fully locked — red band showing" if suit["seal"] == key else "wrist lock green, fingertips and palm bladder intact"])
	if seen.get("glove_L", false) and seen.get("glove_R", false):
		insp["gloves"] = true


func _hook(k: int) -> void:
	var key: String = "hook_%d" % k
	if seen.get(key, false) and not suit["hooks"][k]:
		suit["hooks"][k] = true
		sfx(&"ratchet")
		say("Tether hook %s: gate cleaned, cycled ten times — snaps shut, locks." % "AB"[k])
		return
	seen[key] = true
	sfx(&"click")
	say("Tether hook %s: %s." % ["AB"[k], "gate STICKS half-open — grit in the hinge" if not suit["hooks"][k] else "gate snaps shut, lock sleeve turns, cable and D-ring sound"])
	if seen.get("hook_0", false) and seen.get("hook_1", false):
		insp["hooks"] = true


func _need_diag() -> bool:
	if not bool(insp.get("diag", false)):
		sfx(&"fail")
		say("Connect the diagnostic umbilical to the suit's chest port first.")
		return false
	return true


func _ptest() -> void:
	if not _need_diag() or ptest_t >= 0.0:
		return
	ptest_t = 0.0
	sfx(&"hiss")
	say("Suit pressure test: pressurising to %.1f psi, holding %d s…" % [4.3, int(PTEST_S)])


func _fill() -> void:
	if not _need_diag():
		return
	if not bool(suit["supply"]):
		sfx(&"fail")
		say("O2 FILL: no supply pressure — the O2 supply valve is closed.")
		filling = false
		return
	filling = not filling
	sfx(&"hiss" if filling else &"click")


func _charge() -> void:
	if not _need_diag():
		return
	if not bool(suit["charger"]):
		sfx(&"fail")
		say("CHARGE: charger breaker TRIPPED — reset it first.")
		charging = false
		return
	charging = not charging
	sfx(&"relay")


func _comms() -> void:
	if not _need_diag():
		return
	var ok: bool = suit["comms"] == "" and _station_comms_ok()
	insp["comms"] = "pass" if ok else "fail"
	sfx(&"success" if ok else &"fail")
	if ok:
		say("Radio check: \"Station, suit A-1, how do you read?\" — loud and clear both ways.")
	elif suit["comms"] != "":
		say("Radio check: carrier only, no audio in the helmet. Inspect the helmet comm cap.", 4.0)
	else:
		say("Radio check: no station loopback — the station comms link itself is down.", 4.0)


func _station_comms_ok() -> bool:
	return true      # the suit talks to the station's internal UHF; the S-band link is not in the loop


func _read_panel() -> void:
	sfx(&"click")
	if float(suit["o2"]) >= 0.9:
		insp["o2"] = true
	if float(suit["batt"]) >= 0.9:
		insp["batt"] = true
	say("Suit A-1: O2 %d%% · battery %d%% · %s · supply %s · charger %s" % [roundi(float(suit["o2"]) * 100.0), roundi(float(suit["batt"]) * 100.0), status_word(),
		"OPEN" if suit["supply"] else "CLOSED", "ON" if suit["charger"] else "TRIPPED"], 4.5)


func _signoff() -> void:
	var missing: Array = []
	for st in STEPS:
		if not _done(insp.get(st, false)):
			missing.append(st.to_upper())
	if not suit["hooks"][0] or not suit["hooks"][1]:
		missing.append("HOOK SERVICE")
	if not missing.is_empty():
		sfx(&"fail")
		say("Sign-off refused — not yet: %s." % ", ".join(missing), 4.5)
		_ai(&"suit_nogo")
		return
	suit["full_due"] = false
	suit["last_full_day"] = day()
	suit["evas_since"] = 0
	insp["signed"] = true
	sfx(&"success")
	say("Suit A-1 inspected and signed off: GO for EVA.")
	_ai(&"suit_go")


func _ai(key: StringName) -> void:
	for a in get_tree().get_nodes_in_group(&"station_ai"):
		a.event(key)


# ---------------------------------------------------------- the model
## The suit's measured pressure: a seal fault bleeds it down in the test
## (and outside, if it ever went out with one -- it cannot: see don_blocker).
func suit_psi() -> float:
	return 4.3 if suit["seal"] == "" else 3.6


func status_word() -> String:
	if suit["seal"] != "" or suit["comms"] != "" or not suit["hooks"][0] or not suit["hooks"][1] or not bool(suit["supply"]) or not bool(suit["charger"]):
		return "NO-GO" if bool(suit["full_due"]) and not insp.is_empty() else "CHECK DUE"
	if bool(suit["full_due"]) or full_inspection_due():
		return "CHECK DUE"
	if float(suit["o2"]) < 0.6 or float(suit["batt"]) < 0.5:
		return "LOW"
	return "GO"


func full_inspection_due() -> bool:
	return bool(suit["full_due"]) or (int(suit["last_full_day"]) > 0 and day() - int(suit["last_full_day"]) >= FULL_DAYS) or int(suit["evas_since"]) >= FULL_EVAS


## "" = the suit may be put on. Otherwise the reason (the short pre-EVA
## status check, or a full inspection that is due).
func don_blocker() -> String:
	if full_inspection_due() and not bool(insp.get("signed", false)):
		return "Suit A-1: FULL INSPECTION DUE — use the suit service panel beside the locker (A01)."
	if float(suit["o2"]) < 0.6:
		return "Suit A-1: O2 %d%% — fill it at the suit service panel first." % roundi(float(suit["o2"]) * 100.0)
	if float(suit["batt"]) < 0.5:
		return "Suit A-1: battery %d%% — charge it at the suit service panel first." % roundi(float(suit["batt"]) * 100.0)
	return ""


## A real suit fault (A01 rearm, daily roll, the developer). The suit's own
## telemetry flags it: a full inspection becomes due.
func inject_fault(kind: String) -> void:
	match kind:
		"o2":
			suit["o2"] = 0.32
			suit["supply"] = false
		"batt":
			suit["batt"] = 0.28
			suit["charger"] = false
		"seal":
			suit["seal"] = ["neck", "glove_L", "glove_R"][absi(hash([day(), "sealk"])) % 3]
		"seal_neck":
			suit["seal"] = "neck"
		"comms":
			suit["comms"] = "connector"
		"hook":
			suit["hooks"][absi(hash([day(), "hook"])) % 2] = false
	suit["full_due"] = true
	_reset_insp()
	_refresh()


func clear_faults() -> void:
	suit = {"o2": 1.0, "batt": 1.0, "seal": "", "comms": "", "hooks": [true, true], "supply": true, "charger": true,
		"full_due": false, "last_full_day": int(suit.get("last_full_day", 0)), "evas_since": 0, "status": "GO"}
	filling = false
	charging = false
	_reset_insp()
	_refresh()


func _process(delta: float) -> void:
	var e: Node = _eva()
	var out: bool = e != null and e.outside
	var gd: float = delta if out else (_dp.gameplay_delta(delta) if _dp != null and _dp.has_method("gameplay_delta") else delta)
	if out:
		suit["o2"] = maxf(float(suit["o2"]) - gd / O2_USE_S, 0.0)
		suit["batt"] = maxf(float(suit["batt"]) - gd / BATT_USE_S, 0.0)
	elif e == null or not e.suited:
		# On the umbilical in the locker.
		var rate_o2: float = (1.0 / FILL_S if filling else 1.0 / TRICKLE_S) if bool(suit["supply"]) else 0.0
		var rate_b: float = (1.0 / FILL_S if charging else 1.0 / TRICKLE_S) if bool(suit["charger"]) else 0.0
		var before: float = float(suit["o2"])
		suit["o2"] = minf(float(suit["o2"]) + gd * rate_o2, 1.0)
		suit["batt"] = minf(float(suit["batt"]) + gd * rate_b, 1.0)
		# O2 comes from the station's own gas supply (the make-up reserve).
		var net: Node = sys()
		if net != null and float(suit["o2"]) > before:
			net.press["makeup"] = maxf(float(net.press["makeup"]) - (float(suit["o2"]) - before) * 40.0, 0.0)
		if filling and float(suit["o2"]) >= 1.0:
			filling = false
		if charging and float(suit["batt"]) >= 1.0:
			charging = false
	if ptest_t >= 0.0:
		ptest_t += gd
		if ptest_t >= PTEST_S:
			ptest_t = -1.0
			var ok: bool = suit["seal"] == ""
			insp["ptest"] = "pass" if ok else "fail"
			sfx(&"success" if ok else &"fail")
			say("Suit pressure test %s: %.1f -> %.1f psi in %d s%s." % ["PASSED" if ok else "FAILED", 4.3, 4.3 if ok else 3.6, int(PTEST_S), "" if ok else " — find the leaking seal (neck ring, gloves)"], 4.5)
	# Count EVAs (for the periodic full inspection).
	if out and not _was_outside:
		suit["evas_since"] = int(suit["evas_since"]) + 1
		insp.erase("signed")
	_was_outside = out
	_poll_t += delta
	if _poll_t > 0.3:
		_poll_t = 0.0
		_refresh()
var _poll_t: float = 0.0


func _refresh() -> void:
	suit["status"] = status_word()
	if _panel_lbl != null:
		var rows: Array = []
		for st in STEPS:
			var v = insp.get(st, false)
			rows.append("%s%s" % [st.to_upper().left(5), "✓" if _done(v) else ("✗" if str(v) == "fail" else "·")])
		_panel_lbl.text = "A-1 %s  O2 %d%%%s  BAT %d%%%s\n%s\n%s\n%s" % [status_word(), roundi(float(suit["o2"]) * 100.0), "↑" if filling else "", roundi(float(suit["batt"]) * 100.0), "↑" if charging else "",
			" ".join(rows.slice(0, 5)), " ".join(rows.slice(5)), "PTEST %s" % ("%d s" % int(PTEST_S - ptest_t) if ptest_t >= 0.0 else "—")]
	if _marks.has("wrist_L"):
		for sd in ["L", "R"]:
			var bad: bool = suit["seal"] == "glove_" + sd
			var m: StandardMaterial3D = (_marks["wrist_" + sd] as MeshInstance3D).material_override
			m.albedo_color = Color(1.0, 0.15, 0.1) if bad else Color(0.2, 0.9, 0.3)
		for k in 2:
			(_marks["hook_%d" % k] as Node3D).visible = not suit["hooks"][k]
		var cm: StandardMaterial3D = (_marks["comm_cap"] as MeshInstance3D).material_override
		cm.albedo_color = Color(0.85, 0.3, 0.1) if suit["comms"] != "" else Color(0.2, 0.2, 0.22)
		(_marks["comm_cap"] as Node3D).rotation_degrees.z = 25.0 if suit["comms"] != "" else 0.0
		var nm: StandardMaterial3D = (_marks["neck_ring"] as MeshInstance3D).material_override
		nm.albedo_color = Color(0.75, 0.55, 0.35) if suit["seal"] == "neck" and seen.get("neck", false) else Color(0.75, 0.75, 0.78)
	var e: Node = _eva()
	if e != null and e.has_method("_refresh") and is_inside_tree():
		pass


# ------------------------------------------------------------ A01 order
var fault_at_rearm: String = ""


func task_rearm(t: StringName, seed: int) -> void:
	if t != &"a01_suit":
		return
	_reset_insp()
	# A scheduled inspection: the suit may (or may not) have a real fault;
	# one that already exists stays the fault.
	if suit["seal"] == "" and suit["comms"] == "" and suit["hooks"][0] and suit["hooks"][1] and bool(suit["supply"]) and bool(suit["charger"]):
		var r: int = absi(seed) % 7
		if r < 5:
			inject_fault(["o2", "batt", "seal", "comms", "hook"][r])
	suit["full_due"] = true
	fault_at_rearm = _fault_list()


func _fault_list() -> String:
	var f: Array = []
	if not bool(suit["supply"]):
		f.append("O2 supply closed / low O2")
	if not bool(suit["charger"]):
		f.append("charger tripped / low battery")
	if suit["seal"] != "":
		f.append("seal leak (%s)" % suit["seal"])
	if suit["comms"] != "":
		f.append("comm-cap connector")
	for k in 2:
		if not suit["hooks"][k]:
			f.append("tether hook %s gate" % "AB"[k])
	return ", ".join(f)


func task_done(t: StringName) -> bool:
	if t != &"a01_suit":
		return true
	if bool(insp.get("signed", false)):
		close_task(t, "verified_normal" if fault_at_rearm == "" else "repaired", "EVA suit A-1", fault_at_rearm if fault_at_rearm != "" else "none found", "full inspection: helmet, neck ring, gloves, boots, hooks, P-test, O2, battery, comms", "signed off GO")
		return true
	return false


func task_next(t: StringName) -> Dictionary:
	if t != &"a01_suit":
		return {}
	var e: Node = _eva()
	if e != null and e.suited:
		return next("Stow the suit in the locker (airlock tunnel) to inspect it", "STOW SUIT")
	for st in ["helmet", "gloves", "boots", "hooks"]:
		if not bool(insp.get(st, false)):
			return next("Suit locker: inspect the %s" % {"helmet": "helmet and neck ring", "gloves": "both gloves", "boots": "boots", "hooks": "both tether hooks"}[st], st.to_upper())
	if not suit["hooks"][0] or not suit["hooks"][1]:
		return next("Service the sticking tether hook (click it again)", "HOOK")
	if not bool(insp.get("diag", false)):
		return next("Connect the diagnostic umbilical (suit chest port)", "DIAG")
	if insp.get("ptest", "") != "pass":
		return next("Suit service panel: P-TEST (fix the seal first if it fails)", "P-TEST")
	if not bool(insp.get("o2", false)):
		return next("O2 %d%%: %sFILL, then read the panel" % [roundi(float(suit["o2"]) * 100.0), "" if suit["supply"] else "open the O2 SUPPLY valve, "], "O2")
	if not bool(insp.get("batt", false)):
		return next("Battery %d%%: %sCHARGE, then read the panel" % [roundi(float(suit["batt"]) * 100.0), "" if suit["charger"] else "reset the charger breaker, "], "BATTERY")
	if insp.get("comms", "") != "pass":
		return next("COMMS check with the station (fix the comm cap if it fails)", "COMMS")
	return next("SIGN OFF the suit inspection", "SIGN OFF")


func task_progress(t: StringName) -> String:
	if t != &"a01_suit":
		return ""
	var n := 0
	for st in STEPS:
		if _done(insp.get(st, false)):
			n += 1
	return "%d/%d checks · %s" % [n, STEPS.size(), status_word()]


func task_detail(t: StringName) -> Array:
	if t != &"a01_suit":
		return []
	return ["Suit A-1: O2 %d%%, battery %d%%, %s" % [roundi(float(suit["o2"]) * 100.0), roundi(float(suit["batt"]) * 100.0), status_word()],
		"Inspect on the suit; test on the suit service panel; sign off."]


func task_feasible(_t: StringName) -> bool:
	return true


## Story-gated anomaly hook (Round 50 foundation, NEVER active in normal
## play): a suit-inspection record with a time the technician was asleep.
## Only a registered story beat / the developer preview may call this; the
## suit itself is untouched.
func record_anomaly(preview: bool) -> Dictionary:
	var rec := {"day": day(), "t": "03:12", "text": "A-1 inspection SIGNED (technician ID —)", "preview": preview}
	if not preview:
		anomaly_log.append(rec)
	return rec


func state_dict() -> Dictionary:
	return {"outcome": outcome.duplicate(), "fault_at_rearm": fault_at_rearm, "suit": suit.duplicate(true), "insp": insp.duplicate(true), "seen": seen.duplicate(true), "anomaly_log": anomaly_log.duplicate(true)}


func load_dict(d: Dictionary) -> void:
	outcome = d.get("outcome", {})
	var su: Dictionary = d.get("suit", {})
	clear_faults()
	for k in su:
		suit[k] = su[k]
	insp = d.get("insp", {})
	seen = d.get("seen", {})
	anomaly_log = Array(d.get("anomaly_log", []))
	fault_at_rearm = String(d.get("fault_at_rearm", ""))
	filling = false
	charging = false
	ptest_t = -1.0                 # a test never resumes half-way
	_refresh()
