extends Node
## Round 49: CHAPTER TWO / PHASE THREE story beats on the Lower Service
## Deck, run by the existing story director (story_events.gd: one registry,
## one daily arming roll, one active event, the same pacing / cooldown /
## dev layer / save). This module only implements each beat's live
## condition, start, per-frame update and SAFE stop. RULES:
##   * normal lower-deck routine first: no beat before the technician knows
##     the deck (>= 4 lower rooms visited, on >= 2 different days);
##   * presentation only: sounds at real equipment positions, a camera-only
##     figure, an extra / altered line on a display. Authoritative records,
##     inventory and equipment are never altered (the one exception is the
##     registered abnormal cargo variant, which MOVES a real part between
##     two real racks -- nothing is created or lost);
##   * every beat has a physical check (go there / read the record) and
##     several readings (equipment, sleep, memory, records, something else);
##   * no identity, no explanation: the unknown contact stays unknown.
## Implemented & ACTIVE: lower_sound_echo, lower_camera_crossing,
## cargo_missing_item, lab_sample_disagreement, archive_prev_record.
## Implemented, ACTIVE ONLY IN PHASE 3: archive_timestamp_drift,
## hydroponics_record_anomaly.
## Implemented, STORY-INACTIVE (developer preview only):
## unknown_signal_fragment, lower_layout_contradiction.

const L = preload("res://scripts/deck_b/deck_b_layout.gd")
const Foley = preload("res://scripts/audio/foley_synth.gd")
const PUMP_POS := Vector3(1.32, L.FLOOR_Y + 0.3, 9.75)
const ECHO_S := 7.0
const CROSS_PATH := [Vector3(2.75, L.FLOOR_Y, 9.55), Vector3(3.6, L.FLOOR_Y, 9.5), Vector3(4.6, L.FLOOR_Y, 9.5), Vector3(5.1, L.FLOOR_Y, 9.5)]
const IDS := [&"lower_sound_echo", &"lower_camera_crossing", &"cargo_missing_item", &"lab_sample_disagreement", &"archive_prev_record",
	&"archive_timestamp_drift", &"hydroponics_record_anomaly", &"unknown_signal_fragment", &"lower_layout_contradiction"]

var se: Node
var _t: float = 0.0
var _seen_s: float = 0.0
var _variant: String = "normal"
var _moved: Dictionary = {}        # cargo abnormal: {item, from, to}
var _props: Array = []
var _echo_auto: bool = false
var _sample_id: String = ""
var _rx_player: AudioStreamPlayer3D


func _root() -> Node:
	return se._root() if se != null else null


func sys() -> Node:
	return get_tree().get_first_node_in_group(&"deck_b_systems") if is_inside_tree() else null


func deck_b() -> Node:
	var r: Node = _root()
	return r.get_node_or_null("DeckB") if r != null else null


func room(id: StringName) -> Node:
	var d: Node = deck_b()
	return d.room_node(id) if d != null else null


func cam() -> Camera3D:
	return get_viewport().get_camera_3d() if get_viewport() != null else null


func familiar() -> bool:
	var s: Node = sys()
	return s != null and s.rooms_visited_total().size() >= 4 and s.deck_b_days() >= 2


func is_mine(id: StringName) -> bool:
	return id in IDS


# ---------------------------------------------------------- eligibility
## Extra Deck B prerequisites ("" = fine) -- on top of phase / cooldown.
func eligibility(id: StringName) -> String:
	if not se.chapter_one_complete():
		return "Chapter Two only (Chapter One not complete)"
	var clr: Node = get_tree().get_first_node_in_group(&"clearance")
	if clr == null or int(clr.deck_b_tier()) < 1:
		return "needs Lower Service Deck access"
	if not familiar():
		return "the technician must know the lower deck first (4 rooms, 2 days)"
	var s: Node = sys()
	match id:
		&"lower_camera_crossing":
			if int(clr.deck_b_tier()) < 1:
				return "no INT-12 access"
		&"cargo_missing_item":
			if _stowed_candidate().is_empty():
				return "no part placed by the technician on an earlier day"
		&"lab_sample_disagreement":
			if _recorded_specimen() == "":
				return "no specimen documented on an earlier day"
		&"archive_prev_record":
			var arc: Node = room(&"b09")
			if arc == null or not arc.tapes_read.has(0):
				return "R.V.'s first tape not heard yet"
			if not bool(se.state.get(&"lower_sound_echo", {}).get("seen", false)):
				return "needs the 'sound below' first"
		&"hydroponics_record_anomaly":
			var hy: Dictionary = s.hydro if s != null else {}
			if Array(hy.get("log", [])).is_empty():
				return "no hydroponics observations recorded yet"
	return ""


# ----------------------------------------------------------- live check
func ready_to_start(id: StringName) -> bool:
	var s: Node = sys()
	var c: Camera3D = cam()
	if s == null or c == null:
		return false
	var p: Vector3 = c.global_position
	var dp: Node = se._dp
	match id:
		&"lower_sound_echo":
			# Heard from elsewhere (Deck A, or the far end of Deck B), the
			# pump idle, not on the first lower-deck day of the week.
			return not s.water["processing"] and p.distance_to(PUMP_POS) > 6.0 and float(dp.shift_elapsed_s) > 60.0 and L.room_at(p) != &"b02"
		&"lower_camera_crossing":
			return se._watching("INT-12") and se._watch_s >= 4.0 and se.watched_before_today("INT-12")
		&"cargo_missing_item":
			var cand: Dictionary = _stowed_candidate()
			return not cand.is_empty() and L.room_at(p) != StringName(cand.get("room", "")) and float(dp.shift_elapsed_s) > 90.0
		&"lab_sample_disagreement":
			var lab: Node = room(&"b05")
			return lab != null and lab.stage >= 0 and String(lab.SPECIMENS[lab.stage][0]) == _recorded_specimen()
		&"archive_prev_record", &"archive_timestamp_drift":
			var arc: Node = room(&"b09")
			return arc != null and L.room_at(p) == &"b09" and arc.PAGES[arc.page] == "RECORDS"
		&"hydroponics_record_anomaly":
			return L.room_at(p) == &"b06"
	return false


# ---------------------------------------------------------------- start
func start(id: StringName, variant: String, dev: bool) -> bool:
	_t = 0.0
	_seen_s = 0.0
	_variant = variant
	var s: Node = sys()
	match id:
		&"lower_sound_echo":
			if s == null:
				return false
			# NORMAL: the WRS really runs a short automatic cycle (a real,
			# logged start: the plausible explanation is there to find).
			# ABNORMAL: the same sound, the pump never runs, no log entry.
			_echo_auto = variant != "abnormal"
			if _echo_auto:
				s.water["processing"] = true
				s._pump_start("auto cycle (priming check)")
			else:
				_play_at(&"echo_pump", _pump_start_stream(), PUMP_POS)
		&"lower_camera_crossing":
			var pr: Node3D = se._presence
			if pr == null:
				return false
			pr.walk(PackedVector3Array(CROSS_PATH), 2, 0.9 if variant == "abnormal" else 0.4)
		&"cargo_missing_item":
			var cand: Dictionary = _stowed_candidate()
			if cand.is_empty() and not dev:
				return false
			_cargo_begin(cand, variant)
		&"lab_sample_disagreement":
			var lab: Node = room(&"b05")
			if lab == null:
				return false
			_sample_id = _recorded_specimen() if _recorded_specimen() != "" else "S-102"
			var idx: int = 0
			for i in lab.SPECIMENS.size():
				if lab.SPECIMENS[i][0] == _sample_id:
					idx = i
			var true_class: int = int(lab.SPECIMENS[idx][2])
			# The SAME container presented with another catalogue number
			# (normal) or another structure (abnormal).
			var cat: String = String(lab.SPECIMENS[idx][1])
			var alt_cat: String = cat.left(cat.length() - 2) + cat.right(1) + cat.right(2).left(1)
			lab.shown_overlay[_sample_id] = {"catalogue": alt_cat, "class": true_class if variant != "abnormal" else (true_class + 1) % 4}
			if dev:
				lab.stage = idx
				lab.focus_err = 0.0
		&"archive_prev_record":
			var arc: Node = room(&"b09")
			if arc == null:
				return false
			arc.personnel_alt = true
		&"archive_timestamp_drift":
			var arc2: Node = room(&"b09")
			if arc2 == null:
				return false
			var d: int = se.day() + 1
			arc2.unknown_entry = {"text": "D%d 07:52 · B-02 · MF-2 bed service CLOSED · TECH-1 · verified" % d, "day": d, "story": "archive_timestamp_drift"}
		&"hydroponics_record_anomaly":
			var hyd: Node = room(&"b06")
			if hyd == null or s == null:
				return false
			var hlog: Array = s.hydro["log"]
			var last: Dictionary = hlog.back() if not hlog.is_empty() else {"day": se.day() - 1, "tray": 1}
			hyd.set_meta(&"story_line", "D%d 02:40 TRAY %s POOR — wilted, dark roots (TECH-1)" % [int(last["day"]), ["A", "B", "C"][int(last["tray"])]])
		&"unknown_signal_fragment":
			_rx_begin()
		&"lower_layout_contradiction":
			_layout_begin()
		_:
			return false
	return true


# --------------------------------------------------------------- update
## "" = still running; "seen" / "unseen" = stop now.
func update(id: StringName, delta: float, dev: bool) -> String:
	_t += delta
	var s: Node = sys()
	var c: Camera3D = cam()
	match id:
		&"lower_sound_echo":
			if _echo_auto and _t > 30.0 and s != null and s.water["processing"] and float(s.water["raw_l"]) < s.RAW_HIGH:
				s.water["processing"] = false
			if _t >= ECHO_S:
				return "seen"
		&"lower_camera_crossing":
			if se._watching("INT-12") and se._presence.is_shown():
				_seen_s += delta
			if (not se._watching("INT-12") and not dev) or _t > (12.0 if not dev else 30.0):
				return "seen" if _seen_s >= 1.0 else "unseen"
		&"cargo_missing_item":
			if c != null and not _moved.is_empty():
				var target: Node3D = _moved.get("look_at") as Node3D
				if target != null and is_instance_valid(target) and c.global_position.distance_to(target.global_position) < 2.5:
					_seen_s += delta
			if _seen_s >= 1.5:
				return "seen"
			if _t > 900.0:
				return "unseen"
		&"lab_sample_disagreement":
			var lab: Node = room(&"b05")
			if lab != null and lab.stage >= 0 and String(lab.SPECIMENS[lab.stage][0]) == _sample_id and absf(float(lab.focus_err)) <= 0.05:
				_seen_s += delta
			if _seen_s >= 2.0:
				return "seen"
			if _t > 300.0:
				return "unseen"
		&"archive_prev_record", &"archive_timestamp_drift":
			var arc: Node = room(&"b09")
			if arc != null and c != null and L.room_at(c.global_position) == &"b09" and arc.PAGES[arc.page] == "RECORDS":
				_seen_s += delta
			if _seen_s >= 2.5:
				return "seen"
			if _t > 600.0:
				return "unseen"
		&"hydroponics_record_anomaly":
			if c != null and L.room_at(c.global_position) == &"b06":
				_seen_s += delta
			if _seen_s >= 3.0:
				return "seen"
			if _t > 600.0:
				return "unseen"
		&"unknown_signal_fragment":
			if _t >= 6.0:
				return "seen"
		&"lower_layout_contradiction":
			if c != null and L.room_at(c.global_position) != &"b05" and L.room_at(c.global_position) != &"b01":
				_seen_s += delta
			if _t > 40.0:
				return "seen"
	return ""


# ----------------------------------------------------------------- stop
func stop(id: StringName, seen: bool, dev: bool) -> void:
	match id:
		&"lower_sound_echo":
			if seen and not dev:
				se._pending_investigation["lower_sound_echo"] = 300.0
		&"lower_camera_crossing":
			se._presence.hide_now()
			if seen and not dev:
				se._pending_investigation["lower_camera_crossing"] = 240.0
				se._record_overlay["camera"] = [{"day": se.day(), "t": se._dp.clock_text_hhmm(), "text": "INT-12 · motion, archive branch · 3 s · no tag"}]
		&"cargo_missing_item":
			# The NORMAL presentation (a transfer record nobody made) ends;
			# the ABNORMAL physical move stays (a real part in a real rack).
			se._record_overlay.erase("maintenance")
			if seen and not dev:
				se._pending_investigation["cargo_missing_item"] = 600.0
		&"lab_sample_disagreement":
			var lab: Node = room(&"b05")
			if lab != null:
				lab.shown_overlay.erase(_sample_id)
			if seen and not dev:
				se._add_evidence("lab_sample_disagreement", "contradiction", "%s showed a catalogue number / structure that differs from the record made on an earlier day." % _sample_id, "lab")
		&"archive_prev_record":
			var arc: Node = room(&"b09")
			if arc != null:
				arc.personnel_alt = false
			if seen and not dev:
				se._add_evidence("archive_prev_record", "contradiction", "R.V.'s P-201 entry exists in two versions: 'bled the pump' and 'nobody started it'.", "archive")
		&"archive_timestamp_drift":
			var arc2: Node = room(&"b09")
			if arc2 != null and String(arc2.unknown_entry.get("story", "")) == "archive_timestamp_drift":
				arc2.unknown_entry = {}
		&"hydroponics_record_anomaly":
			var hyd: Node = room(&"b06")
			if hyd != null:
				hyd.remove_meta(&"story_line")
		&"unknown_signal_fragment":
			if _rx_player != null:
				_rx_player.queue_free()
				_rx_player = null
			var rj: Node = room(&"b01")
			if rj != null and rj.has_meta(&"rx_fragment"):
				rj.remove_meta(&"rx_fragment")
		&"lower_layout_contradiction":
			for p in _props:
				if is_instance_valid(p):
					p.queue_free()
			_props = []


## Physical checks that resolve a pending investigation.
func check_done(k: String) -> bool:
	var c: Camera3D = cam()
	if c == null:
		return false
	var room_now: StringName = L.room_at(c.global_position)
	match k:
		"lower_sound_echo":
			if room_now == &"b02":
				var s: Node = sys()
				var st: Array = s.water["starts"] if s != null else []
				var logged_recent: bool = not st.is_empty() and int(st.back()["day"]) == se.day() and String(st.back()["why"]).begins_with("auto")
				if logged_recent:
					se._add_evidence("lower_sound_echo", "check", "WRS log: an automatic priming cycle at that time. A plausible source.", "b02")
				else:
					se._add_evidence("lower_sound_echo", "contradiction", "P-201 idle; the WRS log shows no start since earlier. Nothing ran.", "b02")
					se._add_milestone("ch2_records")
				return true
		"lower_camera_crossing":
			if room_now == &"b09" or (c.global_position.x > 2.6 and c.global_position.z > 9.0 and L.is_lower(c.global_position)):
				se._add_evidence("lower_camera_crossing", "check", "Archive branch empty. Access log: no B-09 entry today.", "b09")
				return true
		"cargo_missing_item":
			if room_now == StringName(_moved.get("room", "")) or room_now == &"b08":
				return true
	return false


# ------------------------------------------------------------- helpers
func _stowed_candidate() -> Dictionary:
	var s: Node = sys()
	if s == null or not "player_stows" in s:
		return {}
	for e in s.player_stows:
		if int(e.get("day", 0)) < se.day():
			var r: Node = _find_rack(String(e["rack"]))
			if r != null:
				for it in r.items():
					if String(it.name) == String(e["item"]):
						return e
	return {}


func _find_rack(n: String) -> Node:
	for r in get_tree().get_nodes_in_group(&"deck_b_rack"):
		if String(r.name) == n:
			return r
	return null


func _cargo_begin(cand: Dictionary, variant: String) -> void:
	var r: Node = _find_rack(String(cand.get("rack", "")))
	var item: Node3D = null
	if r != null:
		for it in r.items():
			if String(it.name) == String(cand.get("item", "")):
				item = it
	var serial: String = String(item.payload.get("serial", "?")) if item != null else "?"
	var m: int = maxi(int(se._dp.clock_minutes()) - 40, 8 * 60)
	se._record_overlay["maintenance"] = [{"day": se.day(), "t": "%02d:%02d" % [m / 60, m % 60], "text": "TRANSFER · %s → B-08 DEST QUARANTINE · TECH-1" % serial}]
	_moved = {"room": String(cand.get("room", "")), "look_at": r}
	if variant == "abnormal" and item != null:
		var dest: Node = _find_rack("DestQuarantine")
		if dest != null and dest.free_slot() != -1:
			dest.place(item, dest.free_slot())
			_moved["look_at"] = dest
			_moved["room"] = "b08"


func _recorded_specimen() -> String:
	var lab: Node = room(&"b05")
	if lab == null:
		return ""
	for sid in lab.recorded:
		if int(lab.recorded[sid].get("day", 0)) < se.day():
			return String(sid)
	return ""


func _pump_start_stream() -> AudioStream:
	var b := Foley._buf(ECHO_S)
	for i in b.size():
		var t: float = float(i) / Foley.SR
		var env: float = clampf(t / 1.2, 0.0, 1.0) * clampf((ECHO_S - t) / 1.0, 0.0, 1.0)
		var f: float = lerpf(20.0, 50.0, clampf(t / 1.2, 0.0, 1.0))
		b[i] = (sin(TAU * f * t) * 0.3 + sin(TAU * f * 3.0 * t) * 0.12) * env
	Foley._contact(b, 0.0, 0.05, 700.0, 1.0, 0.8, 41)
	Foley._modes(b, 0.0, [[160.0, 0.1, 0.5], [420.0, 0.06, 0.25]])
	return Foley.to_wav(b, 0.7)


func _play_at(kind: StringName, stream: AudioStream, pos: Vector3) -> void:
	var snd: Node = get_tree().get_first_node_in_group(&"station_sounds")
	if snd != null and snd.has_method("play_custom"):
		snd.play_custom(kind, stream, pos)


## STORY-INACTIVE: a weak, unidentified fragment on the lower-deck repeater
## (static, a few syllable-like envelopes, no words), timestamped.
func _rx_begin() -> void:
	var rj: Node3D = room(&"b01") as Node3D
	var b := Foley._buf(5.0)
	var r := RandomNumberGenerator.new()
	r.seed = 1977
	for i in b.size():
		var t: float = float(i) / Foley.SR
		var hiss: float = r.randf_range(-1.0, 1.0) * 0.25
		var syl: float = maxf(sin(TAU * 2.3 * t), 0.0) * (1.0 if fmod(t, 1.6) < 1.0 else 0.0)
		b[i] = hiss + sin(TAU * (180.0 + 40.0 * sin(TAU * 5.0 * t)) * t) * 0.18 * syl
	Foley._bandpass(b, 1400.0, 0.7)
	if rj != null:
		rj.set_meta(&"rx_fragment", "RX FRAGMENT 0.8 s · SRC --- · %s" % se._dp.clock_text_hhmm())
	_play_at(&"rx_fragment", Foley.to_wav(b, 0.6), Vector3(-4.95, L.FLOOR_Y + 1.85, 6.6))


## STORY-INACTIVE: in the north hall, a service hatch where there is none
## (event-local props only; the navigation graph and walls are untouched).
func _layout_begin() -> void:
	var root: Node3D = deck_b() as Node3D
	if root == null:
		return
	var p := Node3D.new()
	p.name = "LayoutContradictionProp"
	p.position = Vector3(-7.6, L.FLOOR_Y + 1.0, 12.08)
	p.rotation_degrees.y = 180.0
	root.add_child(p)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.8, 1.9, 0.04)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.32, 0.34)
	m.metallic = 0.7
	mi.material_override = m
	mi.layers = 1 << 13
	p.add_child(mi)
	var lb := Label3D.new()
	lb.text = "B-11  SERVICE ACCESS"
	lb.font_size = 18
	lb.pixel_size = 0.0011
	lb.position = Vector3(0, 1.1, 0.03)
	lb.layers = 1 << 13
	p.add_child(lb)
	_props.append(p)
