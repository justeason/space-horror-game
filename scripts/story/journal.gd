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

var entries: Array = []            # [{key, day, t, text, kind, arg}]
var _keys: Dictionary = {}
## Round 45 Priorities 14-15: the INTERACTIVE journal. One PAGE per day,
## composed only from that day's real entries (above); the player "writes"
## it by pressing any keys -- each press reveals the next few characters of
## the character's own words. pages: [{day, text, typed, keys: [entry keys]}]
var pages: Array = []
const CHARS_PER_KEY := 3
const MAX_SENTENCES := 5
const KIND_ORDER := ["odd", "story", "family", "work", "day"]

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
	"corridor_presence": "Someone walked across the Junction on the corridor camera. Out of Comms, into Engineering. I was the only one awake.",
	"window_mismatch": "The window and the camera didn't agree about the hull outside. I looked twice.",
	"wrong_reading": "The wall panel said the pressure was low. The workstation said it wasn't.",
	"hatch_handle": "A knock from the airlock. On the chamber camera the hatch lever moved.",
	"note_extra_item": "There was a line in today's note I didn't recognise. Then it was gone.",
	"phantom_cycle": "I heard the airlock cycle. I didn't cycle it.",
	"access_ghost": "The access log says someone went into a room today. I don't think it was me.",
	"family_misremember": "Mara's letter mentions something I don't remember telling her.",
	"window_figure": "I thought I saw someone behind the airlock tunnel port. It moved wrong. Then it was gone.",
	"basil_return": "The basil is green again. I watched it die. I haven't watered it since.",
	"peripheral_figure": "Turned round too fast and thought someone was standing at the edge of the room. Nobody.",
}
const CHECKED := {
	"corridor_presence": "Went to the Junction. Nobody. Just the doorways.",
	"hatch_handle": "Went to the airlock. The lever was down, exactly as it should be.",
	"wrong_reading": "Compared the panel with the workstation. They still disagreed.",
	"phantom_cycle": "Went to the airlock. Pressure normal, both hatches as I left them.",
	"access_ghost": "Went and looked. Nothing moved, nothing missing.",
	"window_figure": "I went to the tunnel. Empty. The glass was clean. The suit was where it always is.",
}
const CONTRA := {
	"note_archive": "The note archive says the note was never edited.",
	"airlock_log": "The airlock log has no cycle at that time. None.",
	"access_log": "The access log has the entry. I wasn't there.",
	"environment_log": "The environment log shows normal pressure all day.",
	"sent_mail": "My sent letter says what I remember. Not what she quoted.",
	"camera_log": "The cameras saw nothing. Nobody but me.",
}


# ------------------------------------------------- Simplified Chinese
## Post-Round-45: the journal follows the game language. Entries keep their
## English text (saves unchanged); a page is rendered from each entry's KEY
## in the language active when the page is composed -- and, like a real
## diary, an already-composed page is never rewritten.
const ZH_FIRST_JOB := {
	"vent": "今天第一次清理通风格栅。灰尘像灰色的毛毡一样剥落下来。",
	"breaker": "第一次复位断路器。照手册说的，先找到了原因。",
	"seal": "清理了外舱门的密封圈。关门的声音听得出不一样。",
	"data": "把一个数据模块送过了整个空间站。感觉像个快递员。",
	"thermal": "热成像巡检完成。冷点正好在图上标的位置。",
	"power": "平衡了电源母线。数字终于都是绿色的了。",
	"antenna": "第一次出舱。那颗星球很大，也很安静。",
	"lens": "清理了船体外的一个摄像头镜头。严格来说，它一直在看着我。",
	"solar_clean": "擦了一块太阳能板。奇怪的活儿，像在擦太阳的镜子。",
	"solar_coupler": "重新安装了一个太阳能耦合器。戴着手套，每颗螺栓都大了一倍。",
	"solar_hinge": "松开了一个卡住的太阳能铰链。翼板像门一样转开了。",
	"patch_bay": "在通讯跳线架里找到了那个松动的插头。小东西，大区别。",
	"emerg_lights": "测试了枢纽舱的应急灯。有一盏坏了，换掉了。",
	"junction_panel": "测量了枢纽配电盘。有一个接头松了。",
	"backup_rx": "备用接收机测试。B 通道噪声很大，记录下来了。",
}
const ZH_SHIFT := [
	"第%d天结束。%s今晚空间站更安静了。",
	"第%d天。%s吃了饭，看了仪表，没什么可报告的。",
	"第%d天结束了。%s手上一股触点清洁剂的味道。",
	"第%d天完成。%s如果仔细听，风扇的声音像下雨。",
]
const ZH_OBSERVED := {
	"corridor_presence": "走廊摄像头里有人穿过了枢纽舱。从通讯舱出来，进了工程舱。可醒着的只有我一个。",
	"window_mismatch": "舷窗和摄像头对船体外面的样子说法不一致。我看了两遍。",
	"wrong_reading": "墙上的面板说气压偏低。工作站说没有。",
	"hatch_handle": "气闸那边传来敲击声。舱室摄像头里，舱门把手动了。",
	"note_extra_item": "今天的便条里有一行我不认得。后来它就不见了。",
	"phantom_cycle": "我听到气闸在循环。我没有启动它。",
	"access_ghost": "门禁记录说今天有人进了一个房间。我觉得那不是我。",
	"family_misremember": "Mara 的信里提到一件我不记得告诉过她的事。",
	"window_figure": "我好像看到气闸通道的观察窗后面有人。它动得不对劲。然后就不见了。",
	"basil_return": "罗勒又绿了。我亲眼看着它死掉的。之后我一次都没浇过水。",
	"peripheral_figure": "转身太快，以为屋子边上站着一个人。没人。",
}
const ZH_CHECKED := {
	"corridor_presence": "我去了枢纽舱。没有人。只有那几个门洞。",
	"hatch_handle": "去了气闸。把手是放下的，完全正常。",
	"wrong_reading": "把面板和工作站对比了一下。它们还是对不上。",
	"phantom_cycle": "去了气闸。气压正常，两道舱门都和我离开时一样。",
	"access_ghost": "去看了。什么都没动，什么都没少。",
	"window_figure": "我去了通道。空的。玻璃很干净。宇航服还在老地方。",
}
const ZH_CONTRA := {
	"note_archive": "便条存档说那张便条从没被修改过。",
	"airlock_log": "气闸日志在那个时间没有任何循环记录。一条都没有。",
	"access_log": "门禁记录里有那一条。我不在那里。",
	"environment_log": "环境日志显示全天气压正常。",
	"sent_mail": "我寄出的信写的是我记得的内容。不是她引用的那句。",
	"camera_log": "摄像头什么都没拍到。只有我。",
}
const ZH_MILESTONE := {
	"phase_2": "我现在熟悉这里了。也许正因为这样，小事才显得格外突出。",
	"phase_3": "我开始把每件事的时间都记下来。以防万一。",
	"chapter_1": "全都写下来了。不管那是什么，它现在已经在日志里了。",
}
const ZH_QUIET := ["没发生什么事。空间站一切照常运转。", "普通的一天。吃饭，干活，盯着仪表。", "很安静。我喜欢安静。"]


static func _zh() -> bool:
	return String(preload("res://scripts/station/game_settings.gd").get_value("language")).begins_with("zh")


func _day_label(day: int) -> String:
	return ("第%d天" % day) if _zh() else ("DAY %d" % day)


## The sentence for one entry in the current language (English = as saved).
func entry_text(e: Dictionary) -> String:
	var en: String = String(e.get("text", ""))
	if not _zh():
		return en
	var key: String = String(e.get("key", ""))
	var head: String = key.get_slice(":", 0)
	var rest: String = key.substr(head.length() + 1)
	var arg: String = String(e.get("arg", ""))
	var zh: String = ""
	match head:
		"shift":
			var n: int = int(arg) if arg != "" else _count_from_en(en)
			var what: String = "很平静。" if n == 0 else ("完成了一项工作。" if n == 1 else "完成了%d项工作。" % n)
			zh = pick(ZH_SHIFT, key) % [int(rest), what]
		"first":
			zh = String(ZH_FIRST_JOB.get(rest, "第一次完成%s工作。慢慢上手了。" % rest.replace("_", " ")))
		"emergency":
			zh = "今天电源过载报警。我可不想习惯这种声音。"
		"reply":
			var who: String = arg if arg != "" else en.trim_prefix("Wrote back to ").trim_suffix(".")
			zh = "给%s回了信。" % String({"Mum": "妈妈"}.get(who, who))
		"obs":
			zh = String(ZH_OBSERVED.get(rest, ""))
		"check":
			zh = String(ZH_CHECKED.get(rest, ""))
		"contra":
			zh = String(ZH_CONTRA.get(rest.get_slice(":", 1), "记录和我看到的对不上。"))
		"ms":
			zh = String(ZH_MILESTONE.get(rest, ""))
	return zh if zh != "" else en


static func _count_from_en(en: String) -> int:
	if en.find("Closed one job") != -1:
		return 1
	var rx := RegEx.create_from_string("Closed (\\d+) jobs")
	var m := rx.search(en)
	return int(m.get_string(1)) if m != null else 0


func _ready() -> void:
	add_to_group(&"journal")
	add_to_group(&"r35_equipment")


func _dp() -> Node:
	return get_tree().get_first_node_in_group(&"day_plan") if is_inside_tree() else null


func has(key: String) -> bool:
	return _keys.has(key)


## Writes one entry for `key` (once, ever). Returns true when written.
func write(key: String, text: String, kind: String = "day", day: int = -1, arg: String = "") -> bool:
	if _keys.has(key) or text == "":
		return false
	var dp: Node = _dp()
	var d: int = day if day > 0 else (int(dp.day_number) if dp != null else 1)
	_keys[key] = true
	entries.append({"key": key, "day": d, "t": dp.clock_text_hhmm() if dp != null and dp.has_method("clock_text_hhmm") else "", "text": text, "kind": kind, "arg": arg})
	return true


static func pick(arr: Array, key: String) -> String:
	return String(arr[absi(hash(key)) % arr.size()])


# ------------------------------------------------------------- sources
func on_shift_summary(day: int, closed: int) -> void:
	var what: String = "Quiet one." if closed == 0 else ("Closed one job." if closed == 1 else "Closed %d jobs." % closed)
	write("shift:%d" % day, pick(SHIFT, "shift:%d" % day) % [day, what], "day", day, str(closed))


func on_order_closed(type: String) -> void:
	write("first:" + type, String(FIRST_JOB.get(type, "First %s job done. Getting the feel of it." % type.replace("_", " "))), "work")


func on_emergency(day: int) -> void:
	write("emergency:%d" % day, "Power overload alarm today. Not a sound I want to get used to.", "work", day)


func on_letter(conv: String, to: String) -> void:
	write("reply:" + conv, "Wrote back to %s." % to, "family", -1, to)


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


# ------------------------------------------------------------ pages
func _page(day: int) -> Dictionary:
	for p in pages:
		if int(p["day"]) == day:
			return p
	var np := {"day": day, "text": "", "typed": 0, "keys": []}
	pages.append(np)
	return np


## Brings the page of `day` up to date with that day's real entries
## (append-only: typed text is never rewritten; bounded length).
func compose(day: int) -> Dictionary:
	var p: Dictionary = _page(day)
	var todays: Array = entries.filter(func(e): return int(e["day"]) == day and not (e["key"] in p["keys"]))
	todays.sort_custom(func(a, b): return KIND_ORDER.find(String(a["kind"])) < KIND_ORDER.find(String(b["kind"])))
	for e in todays:
		if p["keys"].size() >= MAX_SENTENCES:
			break
		var t: String = entry_text(e)
		var stop: String = "。" if _zh() else ". "
		if String(e["kind"]) == "day" and String(p["text"]) != "":
			t = t.substr(t.find(stop) + stop.length()) if t.find(stop) != -1 else t
		p["text"] = (String(p["text"]) + ("" if _zh() else " ") + t).strip_edges()
		p["keys"].append(e["key"])
	if String(p["text"]) == "":
		p["text"] = pick(ZH_QUIET if _zh() else ["Nothing much happened. The station hummed along.", "Ordinary day. Ate, worked, watched the gauges.", "Quiet. I like quiet."], "quiet:%d" % day)
		p["keys"].append("quiet:%d" % day)
	return p


## The entry waiting to be written: the earliest unfinished page up to `day`.
func pending_page(day: int) -> Dictionary:
	# Every day with real entries gets its page (yesterday's shift summary
	# is written on the morning after), plus today's.
	var days: Dictionary = {day: true}
	for e in entries:
		if int(e["day"]) <= day:
			days[int(e["day"])] = true
	for d in days:
		compose(int(d))
	pages.sort_custom(func(a, b): return int(a["day"]) < int(b["day"]))
	for p in pages:
		if int(p["day"]) <= day and int(p["typed"]) < String(p["text"]).length():
			return p
	return {}


func page_done(p: Dictionary) -> bool:
	return int(p.get("typed", 0)) >= String(p.get("text", "")).length()


## One key press: reveals the next few characters (bounded).
func type_keys(day: int, presses: int = 1) -> Dictionary:
	var p: Dictionary = pending_page(day)
	if p.is_empty():
		return {}
	p["typed"] = mini(int(p["typed"]) + CHARS_PER_KEY * presses, String(p["text"]).length())
	return p


func page_lines(day: int) -> Array:
	var out: Array = []
	var cur: Dictionary = pending_page(day)
	if not cur.is_empty():
		out.append(_day_label(int(cur["day"])))
		out.append(String(cur["text"]).left(int(cur["typed"])) + "_")
		out.append("")
		out.append(("（按任意键书写）" if _zh() else "(type any keys to write)") if int(cur["typed"]) == 0 else "")
	var done: Array = pages.filter(func(p): return page_done(p) and String(p["text"]) != "")
	done.reverse()
	for p in done.slice(0, 4):
		out.append("%s — %s" % [_day_label(int(p["day"])), p["text"]])
	if out.is_empty():
		out.append("还没有可写的。" if _zh() else "Nothing to write yet.")
	return out


func lines(last: int = 12) -> Array:
	var out: Array = []
	var es: Array = entries.slice(maxi(entries.size() - last, 0))
	es.reverse()
	for e in es:
		out.append("DAY %d%s — %s" % [int(e["day"]), ("  " + String(e["t"])) if String(e["t"]) != "" else "", e["text"]])
	return out


func state_dict() -> Dictionary:
	return {"entries": entries.duplicate(true), "pages": pages.duplicate(true)}


func load_dict(d: Dictionary) -> void:
	entries = []
	_keys = {}
	for e in Array(d.get("entries", [])):
		if e is Dictionary and String(e.get("key", "")) != "" and not _keys.has(String(e["key"])):
			_keys[String(e["key"])] = true
			entries.append({"key": String(e["key"]), "day": int(e.get("day", 1)), "t": String(e.get("t", "")), "text": String(e.get("text", "")), "kind": String(e.get("kind", "day")), "arg": String(e.get("arg", ""))})
	pages = []
	for p in Array(d.get("pages", [])):
		if p is Dictionary:
			var txt: String = String(p.get("text", ""))
			pages.append({"day": int(p.get("day", 1)), "text": txt, "typed": clampi(int(p.get("typed", 0)), 0, txt.length()), "keys": Array(p.get("keys", [])).map(func(k): return String(k))})
