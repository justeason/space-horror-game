extends Node
## Round 44 Priorities 5-6: FAMILY CORRESPONDENCE with replies.
##
## A small, hand-written conversation tree (CONVERSATIONS): a letter
## arrives on its day (or once its gate opens), the technician reads it and
## picks one of 2-4 short replies, the reply is recorded in the thread, and
## the family member's answer -- written for THAT choice -- arrives on the
## next station day. Deterministic: no rolls, so a load never changes an
## answer; a reply is stored once (sending twice is refused); a scheduled
## answer never disappears.
##
## Knowledge rules: a reply that mentions station strangeness ("needs":
## "observed") is only offered once the technician has really SEEN an
## anomaly (story evidence); the "distracted" letter itself only arrives
## after that. Family never learns station events except from what the
## player chose to write. Hiding it ("I'm fine") is as valid as telling.
##
## Horror foundation (Priority 6): story_events.gd may add a PRESENTATION
## line to a delivered answer (family_overlay()) -- e.g. a detail the
## player never wrote. The stored thread (the player's real reply, the real
## answer) is never altered; "Sent letters" always shows what was sent.

const CONVERSATIONS := {
	"mara_eating": {"subject": "eating?", "from": "Mara (sister)", "short": "Mara", "day": 2, "gate": "",
		"text": "How's life up there? Still eating properly?",
		"options": [
			{"id": "A", "text": "Everything's fine. Just busy.", "answer": "Busy is good. Mum says busy is how you know they need you. Eat something green, if they have green."},
			{"id": "B", "text": "The station's quiet. I miss home.", "answer": "We miss you too. Pip sleeps by your door every night. I'll send a photo of him being dramatic about it."},
			{"id": "C", "text": "Long shift today. I'll write more tomorrow.", "answer": "Go to sleep, then! Tomorrow means tomorrow. I'm holding you to it."},
		]},
	"mum_sleep": {"subject": "sleeping?", "from": "Mum", "short": "Mum", "day": 4, "gate": "",
		"text": "The blue jar of jam is waiting for you. Are you sleeping properly up there? Be honest.",
		"options": [
			{"id": "A", "text": "Sleeping fine. The bunk's better than it looks.", "answer": "Good. Your father says no bunk can be worse than the camping trip. He's still sorry about the camping trip."},
			{"id": "B", "text": "Not great. The fans are loud.", "answer": "Try the earplugs I packed in the side pocket. The orange ones. You never check the side pocket."},
			{"id": "C", "text": "Honestly? Some nights.", "answer": "Thank you for being honest. Call when you can, even for five minutes. Five minutes is plenty."},
		]},
	"dev_quiz": {"subject": "quiz", "from": "Dev", "short": "Dev", "day": 5, "gate": "",
		"text": "Pub quiz rematch when you're back. What do you miss most down here? I'm writing a bonus round.",
		"options": [
			{"id": "A", "text": "Rain.", "answer": "Rain! It's rained here for a week. I'll bottle some for you."},
			{"id": "B", "text": "Real bread.", "answer": "I'm on loaf four. They're getting better. Loaf one is now a doorstop."},
			{"id": "C", "text": "Talking to people who aren't the station computer.", "answer": "The station computer is probably better at the quiz than Karl. Low bar."},
		]},
	"mara_distracted": {"subject": "far away", "from": "Mara (sister)", "short": "Mara", "day": 3, "gate": "observed",
		"text": "Your last messages sounded far away. Is everything okay up there?",
		"options": [
			{"id": "A", "text": "I'm fine. Just tired.", "answer": "Okay. Tired is allowed. Sleep, eat, and tell me if 'tired' turns into something else."},
			{"id": "B", "text": "Something strange happened on the station.", "needs": "observed", "answer": "Strange how? You don't have to explain. Write it down, like you always do. And look after yourself."},
			{"id": "C", "text": "I'd rather not talk about it.", "answer": "That's fine. I'm not going anywhere. Pip and I will be right here."},
		]},
}
const ORDER := ["mara_eating", "mum_sleep", "dev_quiz", "mara_distracted"]

## conv id -> {state: "read"|"replied", choice, reply_day, answer_day, arrived_day, answer_read}
var threads: Dictionary = {}
signal replied(conv: String, choice: String)


func _ready() -> void:
	add_to_group(&"family_mail")
	add_to_group(&"r35_equipment")


func _dp() -> Node:
	return get_tree().get_first_node_in_group(&"day_plan") if is_inside_tree() else null


func _story() -> Node:
	return get_tree().get_first_node_in_group(&"story_events") if is_inside_tree() else null


func day() -> int:
	var dp: Node = _dp()
	return int(dp.day_number) if dp != null else 1


## The day of the technician's first SEEN anomaly (-1 = none yet).
func observed_day() -> int:
	var st: Node = _story()
	if st == null or not "evidence" in st:
		return -1
	var d: int = -1
	for e in st.evidence:
		if String(e.get("kind", "")) == "observation" and (d == -1 or int(e["day"]) < d):
			d = int(e["day"])
	return d


func arrival_day(conv: String) -> int:
	var c: Dictionary = CONVERSATIONS[conv]
	if String(c["gate"]) == "observed":
		var od: int = observed_day()
		return -1 if od < 0 else maxi(int(c["day"]), od + 1)
	return int(c["day"])


func arrived(conv: String) -> bool:
	if threads.has(conv):
		return true
	var a: int = arrival_day(conv)
	return a > 0 and day() >= a


func available() -> Array:
	return ORDER.filter(func(c): return arrived(c))


## Replies the character can honestly give now.
func options(conv: String) -> Array:
	var od: int = observed_day()
	return Array(CONVERSATIONS[conv]["options"]).filter(func(o): return String(o.get("needs", "")) != "observed" or od >= 0)


func state(conv: String) -> String:
	if not arrived(conv):
		return "none"
	return String(threads.get(conv, {}).get("state", "unread"))


func mark_read(conv: String) -> void:
	if not arrived(conv):
		return
	if not threads.has(conv):
		threads[conv] = {"state": "read", "arrived_day": day(), "choice": "", "reply_day": -1, "answer_day": -1, "answer_read": false}
	if answer_delivered(conv):
		threads[conv]["answer_read"] = true


## Send a reply. Refused if not arrived, already replied, or not an option now.
func reply(conv: String, choice: String) -> bool:
	if not arrived(conv) or state(conv) == "replied":
		return false
	var ok := false
	for o in options(conv):
		if o["id"] == choice:
			ok = true
	if not ok:
		return false
	mark_read(conv)
	var t: Dictionary = threads[conv]
	t["state"] = "replied"
	t["choice"] = choice
	t["reply_day"] = day()
	t["answer_day"] = day() + 1
	replied.emit(conv, choice)
	var j: Node = get_tree().get_first_node_in_group(&"journal") if is_inside_tree() else null
	if j != null:
		j.on_letter(conv, String(CONVERSATIONS[conv]["short"]))
	return true


func option_text(conv: String, choice: String) -> String:
	for o in CONVERSATIONS[conv]["options"]:
		if o["id"] == choice:
			return String(o["text"])
	return ""


func answer_delivered(conv: String) -> bool:
	var t: Dictionary = threads.get(conv, {})
	return String(t.get("state", "")) == "replied" and day() >= int(t.get("answer_day", 999999))


func answer_text(conv: String) -> String:
	var t: Dictionary = threads.get(conv, {})
	for o in CONVERSATIONS[conv]["options"]:
		if o["id"] == String(t.get("choice", "")):
			return String(o["answer"])
	return ""


func unread_count() -> int:
	var n := 0
	for c in available():
		if state(c) == "unread" or (answer_delivered(c) and not bool(threads[c].get("answer_read", false))):
			n += 1
	return n


## Thread as display lines (authentic + story presentation overlay).
func thread_lines(conv: String) -> Array:
	var c: Dictionary = CONVERSATIONS[conv]
	var out: Array = ["%s" % c["from"], "", String(c["text"])]
	var t: Dictionary = threads.get(conv, {})
	if String(t.get("state", "")) == "replied":
		out.append("")
		out.append("You (day %d): %s" % [int(t["reply_day"]), option_text(conv, String(t["choice"]))])
		if answer_delivered(conv):
			out.append("")
			var ans: String = answer_text(conv)
			var st: Node = _story()
			if st != null and st.has_method("family_overlay"):
				var ov: String = st.family_overlay(conv)
				if ov != "":
					ans += " " + ov
			out.append("%s (day %d): %s" % [c["short"], int(t["answer_day"]), ans])
		else:
			out.append("")
			out.append("(sent — waiting for a reply)")
	return out


## The authentic record of what was sent (never overlaid).
func sent_lines() -> Array:
	var out: Array = ["SENT LETTERS"]
	for conv in ORDER:
		var t: Dictionary = threads.get(conv, {})
		if String(t.get("state", "")) == "replied":
			out.append("  day %d → %s: \"%s\"" % [int(t["reply_day"]), CONVERSATIONS[conv]["short"], option_text(conv, String(t["choice"]))])
	if out.size() == 1:
		out.append("  (nothing sent yet)")
	return out


func state_dict() -> Dictionary:
	return {"threads": threads.duplicate(true)}


func load_dict(d: Dictionary) -> void:
	threads = {}
	var src: Dictionary = d.get("threads", {})
	for k in src:
		if CONVERSATIONS.has(String(k)) and src[k] is Dictionary:
			var t: Dictionary = src[k]
			threads[String(k)] = {"state": String(t.get("state", "read")), "arrived_day": int(t.get("arrived_day", 1)), "choice": String(t.get("choice", "")),
				"reply_day": int(t.get("reply_day", -1)), "answer_day": int(t.get("answer_day", -1)), "answer_read": bool(t.get("answer_read", false))}
