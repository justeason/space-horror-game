extends Node
## Round 44 Priority 3: the technician's AUTOMATIC JOURNAL -- short, dated,
## first-person entries written from things the character ACTUALLY
## experienced: shifts closed, first jobs of a kind, emergencies, letters
## answered, anomalies noticed (only once SEEN -- never one that merely
## played unseen), places checked in person, records that contradicted
## what was seen, and the big turns of the story.
##
## Rules: every entry has a stable key (one entry per key, ever -- no
## duplicates on reload or on reopening the laptop); text is chosen
## deterministically from the key; nothing the character cannot know is
## written; the phase decides tone only. The player's own typed Personal
## Log is untouched (it lives on as PRIVATE NOTES inside the Journal app).

var entries: Array = []            # [{key, day, t, text, kind}]
var _keys: Dictionary = {}

const FIRST_JOB := {
	"vent": "First vent grille today. The dust comes off like grey felt.",
	"breaker": "Reset my first breaker. Found the cause first, like the handbook says.",
	"seal": "Cleaned the outer hatch seal. You can hear the difference when it closes.",
	"data": "Carried a data module across the station. Felt like a courier.",
	"thermal": "Thermal survey done. The cold spots were exactly where the map said.",
	"power": "Balanced the power bus. Numbers in the green, finally.",
	"antenna": "First time outside. The planet is very big and very quiet.",
	"lens": "Cleaned a camera lens out on the hull. It was watching me the whole time, technically.",
	"solar_clean": "Wiped a solar panel. Strange job, polishing the sun's mirror.",
	"solar_coupler": "Reseated a solar coupler. Gloves make every bolt twice as big.",
	"solar_hinge": "Freed a stiff solar hinge. The wing swung like a door.",
	"patch_bay": "Found the loose plug in the comms patch bay. Small thing, big difference.",
	"emerg_lights": "Tested the Junction emergency lights. One lamp was dead. Swapped it.",
	"junction_panel": "Measured the Junction distribution panel. One connector was loose.",
	"backup_rx": "Backup receiver test. Channel B was noisy. Logged it.",
}
const SHIFT := [
	"Day %d done. %s The station's quieter tonight.",
	"Day %d. %s Ate, checked the gauges, nothing to report.",
	"End of day %d. %s My hands smell of contact cleaner.",
	"Day %d finished. %s The fans sound like rain if you let them.",
]
const OBSERVED := {
	"corridor_presence": "I saw something on the corridor camera. Someone behind my chair. When I turned round, the passage was empty.",
	"window_mismatch": "The window and the camera didn't agree about the hull outside. I looked twice.",
	"wrong_reading": "The wall panel said the pressure was low. The workstation said it wasn't.",
	"hatch_handle": "A knock from the airlock. On the chamber camera the hatch lever moved.",
	"note_extra_item": "There was a line in today's note I didn't recognise. Then it was gone.",
	"phantom_cycle": "I heard the airlock cycle. I didn't cycle it.",
	"access_ghost": "The access log says someone went into a room today. I don't think it was me.",
	"family_misremember": "Mara's letter mentions something I don't remember telling her.",
}
const CHECKED := {
	"corridor_presence": "Looked behind me. Nothing. Just the doorway.",
	"hatch_handle": "Went to the airlock. The lever was down, exactly as it should be.",
	"wrong_reading": "Compared the panel with the workstation. They still disagreed.",
	"phantom_cycle": "Went to the airlock. Pressure normal, both hatches as I left them.",
	"access_ghost": "Went and looked. Nothing moved, nothing missing.",
}
const CONTRA := {
	"note_archive": "The note archive says the note was never edited.",
	"airlock_log": "The airlock log has no cycle at that time. None.",
	"access_log": "The access log has the entry. I wasn't there.",
	"environment_log": "The environment log shows normal pressure all day.",
	"sent_mail": "My sent letter says what I remember. Not what she quoted.",
}


func _ready() -> void:
	add_to_group(&"journal")
	add_to_group(&"r35_equipment")


func _dp() -> Node:
	return get_tree().get_first_node_in_group(&"day_plan") if is_inside_tree() else null


func has(key: String) -> bool:
	return _keys.has(key)


## Writes one entry for `key` (once, ever). Returns true when written.
func write(key: String, text: String, kind: String = "day", day: int = -1) -> bool:
	if _keys.has(key) or text == "":
		return false
	var dp: Node = _dp()
	var d: int = day if day > 0 else (int(dp.day_number) if dp != null else 1)
	_keys[key] = true
	entries.append({"key": key, "day": d, "t": dp.clock_text_hhmm() if dp != null and dp.has_method("clock_text_hhmm") else "", "text": text, "kind": kind})
	return true


static func pick(arr: Array, key: String) -> String:
	return String(arr[absi(hash(key)) % arr.size()])


# ------------------------------------------------------------- sources
func on_shift_summary(day: int, closed: int) -> void:
	var what: String = "Quiet one." if closed == 0 else ("Closed one job." if closed == 1 else "Closed %d jobs." % closed)
	write("shift:%d" % day, pick(SHIFT, "shift:%d" % day) % [day, what], "day", day)


func on_order_closed(type: String) -> void:
	write("first:" + type, String(FIRST_JOB.get(type, "First %s job done. Getting the feel of it." % type.replace("_", " "))), "work")


func on_emergency(day: int) -> void:
	write("emergency:%d" % day, "Power overload alarm today. Not a sound I want to get used to.", "work", day)


func on_letter(conv: String, to: String) -> void:
	write("reply:" + conv, "Wrote back to %s." % to, "family")


func on_observed(event_id: String) -> void:
	write("obs:" + event_id, String(OBSERVED.get(event_id, "")), "odd")


func on_checked(event_id: String) -> void:
	write("check:" + event_id, String(CHECKED.get(event_id, "")), "odd")


func on_contradiction(event_id: String, record_id: String) -> void:
	write("contra:%s:%s" % [event_id, record_id], String(CONTRA.get(record_id, "The records don't match what I saw.")), "odd")


func on_milestone(m: String) -> void:
	match m:
		"phase_2":
			write("ms:phase_2", "I know this place now. Maybe that's why the small things stand out.", "story")
		"phase_3":
			write("ms:phase_3", "I've started writing down the time of everything. Just in case.", "story")
		"chapter_1":
			write("ms:chapter_1", "Wrote it all down. Whatever it is, it's in the log now.", "story")


func lines(last: int = 12) -> Array:
	var out: Array = []
	var es: Array = entries.slice(maxi(entries.size() - last, 0))
	es.reverse()
	for e in es:
		out.append("DAY %d%s — %s" % [int(e["day"]), ("  " + String(e["t"])) if String(e["t"]) != "" else "", e["text"]])
	return out


func state_dict() -> Dictionary:
	return {"entries": entries.duplicate(true)}


func load_dict(d: Dictionary) -> void:
	entries = []
	_keys = {}
	for e in Array(d.get("entries", [])):
		if e is Dictionary and String(e.get("key", "")) != "" and not _keys.has(String(e["key"])):
			_keys[String(e["key"])] = true
			entries.append({"key": String(e["key"]), "day": int(e.get("day", 1)), "t": String(e.get("t", "")), "text": String(e.get("text", "")), "kind": String(e.get("kind", "day"))})
