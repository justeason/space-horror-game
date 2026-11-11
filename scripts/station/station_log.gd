extends Node
## Round 44 Priority 9: the station's CONSULTABLE RECORDS -- four concise,
## timestamped logs the technician can read on the workstation (RECORDS):
##   AIRLOCK      hatch open / close, pressure transitions, cycle start /
##                complete, seal-test outcomes, interlock refusals;
##   CAMERAS      feed offline / online, the daily recording check;
##   ENVIRONMENT  one line per station hour (cabin pressure, O2, air
##                quality, power bus), plus real fan-speed changes;
##   ACCESS       a few meaningful accesses: workstation login, first entry
##                into a room each day, breaker panel / storage / cargo /
##                airlock hatch operations.
## AUTHORITATIVE: entries are written only by real equipment state changes
## (polled here, no second simulation). Story anomalies never edit these
## entries -- story_events.gd may add PRESENTATION lines (record_overlays())
## that lines() merges for display, flagged so tests / tools can tell them
## apart; the stored history stays true and saveable.

const KINDS := ["airlock", "camera", "environment", "access"]
const TITLES := {"airlock": "AIRLOCK ACTIVITY", "camera": "CAMERA LOG", "environment": "ENVIRONMENT LOG", "access": "ACCESS LOG"}
const CAP := 80
const ROOM_NAMES := {&"control_room": "CONTROL", &"living_quarters": "QUARTERS", &"engineering": "ENGINEERING", &"life_support": "LIFE SUPPORT", &"storage": "STORAGE", &"communications": "COMMS", &"airlock": "AIRLOCK"}

var entries: Dictionary = {}       # kind -> [{day, t, text}]
var rooms_today: Dictionary = {}   # room -> true (first-entry access lines)
var _dp: Node
var _poll: float = 0.0
var _last_hour: int = -1
var _air: Dictionary = {}
var _cam_off: Dictionary = {}
var _seal_state: String = ""
var _room: StringName = &""
var _cam_check_day: int = -1


func _ready() -> void:
	add_to_group(&"station_log")
	add_to_group(&"r35_equipment")
	_dp = get_parent()
	for k in KINDS:
		entries[k] = []
	if _dp != null and _dp.has_signal(&"day_started"):
		_dp.day_started.connect(func(_d): rooms_today = {})
	if _dp != null and _dp.has_signal(&"task_completed"):
		_dp.task_completed.connect(func(t): if t == &"c01": record("access", "CONTROL · workstation login · TECH-1"))


func _main() -> Node:
	return _dp.get_parent() if _dp != null else null


func now_text() -> String:
	return _dp.clock_text_hhmm() if _dp != null and _dp.has_method("clock_text_hhmm") else "--:--"


func day() -> int:
	return int(_dp.day_number) if _dp != null else 1


func record(kind: String, text: String) -> void:
	if not entries.has(kind):
		return
	var arr: Array = entries[kind]
	arr.append({"day": day(), "t": now_text(), "text": text, "m": _dp.clock_minutes() if _dp != null and _dp.has_method("clock_minutes") else 0})
	while arr.size() > CAP:
		arr.pop_front()


## Did a real entry containing `needle` happen on `on_day` (-1 = any)?
func has_entry(kind: String, needle: String, on_day: int = -1) -> bool:
	for e in entries.get(kind, []):
		if (on_day < 0 or int(e["day"]) == on_day) and String(e["text"]).find(needle) != -1:
			return true
	return false


## Display lines (newest last): authentic entries + story presentation
## overlays (marked "overlay" in the dicts from display_entries()).
func display_entries(kind: String, last: int = 14) -> Array:
	var out: Array = []
	for e in entries.get(kind, []):
		out.append(e.merged({"overlay": false}))
	var st: Node = get_tree().get_first_node_in_group(&"story_events") if is_inside_tree() else null
	if st != null and st.has_method("record_overlays"):
		for o in st.record_overlays(kind):
			var tt: String = String(o["t"])
			out.append({"day": int(o.get("day", day())), "t": tt, "text": String(o["text"]), "overlay": true, "m": int(tt.get_slice(":", 0)) * 60 + int(tt.get_slice(":", 1))})
	# Round 45: ordered by real station minutes (a late night past 00:00
	# still sorts after the evening).
	out.sort_custom(func(a, b): return int(a["day"]) < int(b["day"]) or (int(a["day"]) == int(b["day"]) and int(a.get("m", 0)) < int(b.get("m", 0))))
	return out.slice(maxi(out.size() - last, 0))


func lines(kind: String, last: int = 14) -> Array:
	var out: Array = [String(TITLES.get(kind, kind.to_upper()))]
	var ents: Array = display_entries(kind, last)
	if ents.is_empty():
		out.append("  (no entries)")
	for e in ents:
		out.append("  D%d %s  %s" % [int(e["day"]), e["t"], e["text"]])
	return out


# ------------------------------------------------------------- polling
func _process(delta: float) -> void:
	_poll += delta
	if _poll < 0.25:
		return
	_poll = 0.0
	var main: Node = _main()
	if main == null:
		return
	_poll_airlock(main.get_node_or_null("AirlockChamber"))
	_poll_seal(main.get_node_or_null("Equipment/HatchSeal"))
	_poll_cameras(main.get_node_or_null("CameraNetwork"))
	_poll_environment(main)
	_poll_room(main)


func _poll_airlock(a: Node) -> void:
	if a == null:
		return
	var s := {"inner": bool(a.inner_open), "outer": bool(a.outer_open), "seq": String(a.sequence), "vac": float(a.psi) < 0.5, "full": float(a.psi) > 14.0}
	if _air.is_empty():
		_air = s
		return
	if s["seq"] != _air["seq"]:
		if s["seq"] != "":
			record("airlock", "Cycle %s started" % String(s["seq"]).to_upper())
		else:
			record("airlock", "Cycle %s complete" % String(_air["seq"]).to_upper())
	for k in ["inner", "outer"]:
		if s[k] != _air[k]:
			record("airlock", "%s hatch %s" % ["Inner" if k == "inner" else "Outer", "opened" if s[k] else "closed"])
	if s["vac"] and not _air["vac"]:
		record("airlock", "Chamber 14.7 -> 0.0 psi (vented)")
	if s["full"] and not _air["full"]:
		record("airlock", "Chamber 0.0 -> 14.7 psi (repressurized)")
	_air = s


func _poll_seal(hs: Node) -> void:
	if hs == null or not "test_state" in hs:
		return
	var t: String = String(hs.test_state)
	if t != _seal_state:
		if _seal_state != "" and t in ["pass", "fail"]:
			record("airlock", "Outer hatch seal test: %s" % t.to_upper())
		_seal_state = t


func _poll_cameras(net: Node) -> void:
	if net == null or not "offline" in net:
		return
	var off: Dictionary = net.offline
	for id in off:
		if not _cam_off.has(id):
			record("camera", "%s feed OFFLINE" % id)
	for id in _cam_off:
		if not off.has(id):
			record("camera", "%s feed restored" % id)
	_cam_off = off.duplicate()
	if _cam_check_day != day() and _dp != null and bool(_dp.get("day_active")):
		_cam_check_day = day()
		var n: int = net.CURATED.size() - off.size() if "CURATED" in net else 0
		record("camera", "Recording check: %d feeds online" % n)


func _poll_environment(main: Node) -> void:
	if _dp == null or not _dp.has_method("clock_minutes"):
		return
	var h: int = _dp.clock_minutes() / 60
	if h == _last_hour:
		return
	var first: bool = _last_hour == -1
	_last_hour = h
	if first and not bool(_dp.get("day_active")):
		return
	var env: Node = main.get_node_or_null("EnvironmentModel")
	var br: Node = main.get_node_or_null("Equipment/BreakerPanel")
	var bus: String = "BUS OK"
	if br != null and br.has_method("tripped_ids") and not br.tripped_ids().is_empty():
		bus = "TRIPPED " + ",".join(br.tripped_ids())
	if env != null:
		record("environment", "Cabin %.1f kPa · O2 %.1f kPa · air %s · %s" % [float(env.pressure_kpa), float(env.o2_kpa), ["normal", "poor", "LOW O2"][clampi(int(env.severity), 0, 2)], bus])


const FLOOR_ROOMS := {"ControlRoomFloor": &"control_room", "LivingFloor": &"living_quarters", "EngineeringFloor": &"engineering", "LifeSupportFloor": &"life_support", "StorageFloor": &"storage", "CommsFloor": &"communications", "AirlockTunnelFloor": &"airlock"}
var _room_rects: Array = []


## The room (module) a world point is in, from the real floor footprints.
func room_at(p: Vector3) -> StringName:
	if _room_rects.is_empty():
		var geo: Node = _main().get_node_or_null("Geometry") if _main() != null else null
		if geo == null:
			return &""
		for fname in FLOOR_ROOMS:
			var f: CSGBox3D = geo.get_node_or_null(fname) as CSGBox3D
			if f != null:
				var c: Vector3 = f.global_position
				_room_rects.append([Rect2(c.x - f.size.x * 0.5, c.z - f.size.z * 0.5, f.size.x, f.size.z), FLOOR_ROOMS[fname]])
	for r in _room_rects:
		if (r[0] as Rect2).has_point(Vector2(p.x, p.z)) and p.y < 3.2 and p.y > -0.5:
			return r[1]
	return &""


func _poll_room(main: Node) -> void:
	var cam: Node3D = main.get_node_or_null("Player/LookPivot/PitchPivot/Camera3D") as Node3D
	if cam == null:
		return
	var z: StringName = room_at(cam.global_position)
	if z == _room:
		return
	_room = z
	if ROOM_NAMES.has(z) and not rooms_today.has(z) and _dp != null and bool(_dp.get("day_active")):
		rooms_today[z] = true
		record("access", "%s · entered · TECH-1" % ROOM_NAMES[z])


## Has the technician been in `room` today (first-entry record)?
func visited_today(room: StringName) -> bool:
	return rooms_today.has(room)


# ---------------------------------------------------------- save / load
func state_dict() -> Dictionary:
	return {"entries": entries.duplicate(true), "rooms_today": rooms_today.keys().map(func(k): return String(k)), "cam_day": _cam_check_day}


func load_dict(d: Dictionary) -> void:
	var src: Dictionary = d.get("entries", {})
	for k in KINDS:
		entries[k] = []
		for e in Array(src.get(k, [])):
			if e is Dictionary:
				var tt: String = String(e.get("t", "--:--"))
				entries[k].append({"day": int(e.get("day", 1)), "t": tt, "text": String(e.get("text", "")), "m": int(e.get("m", int(tt.get_slice(":", 0)) * 60 + int(tt.get_slice(":", 1))))})
	rooms_today = {}
	for r in Array(d.get("rooms_today", [])):
		rooms_today[StringName(r)] = true
	_cam_check_day = int(d.get("cam_day", -1))
	_air = {}
	_seal_state = ""
	_last_hour = -1
