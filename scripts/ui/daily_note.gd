extends RefCounted
## Round 43 Priorities 10-11: the DAILY SHIFT NOTE on the personal laptop.
##
## One short note per day from the same, familiar author (the ground ops
## desk, "Ines"), quick to scan: today's priority, cargo, supplies, one
## ordinary reminder, and a small TODAY checklist. Everything is DERIVED --
## DayPlan stays the only work-order authority and the galley / hygiene /
## basil state comes from quarters_life.gd -- so nothing is ticked by hand
## and nothing can disagree with the equipment.
##
## HORROR FOUNDATION: build() is the AUTHENTIC note. Story-driven
## PRESENTATION overlays (story_events.gd laptop_overlays("daily_note"))
## are applied on top at display time only -- an extra checklist line, a
## replaced sentence -- and never written anywhere: the player's own
## Personal Log and the save file stay trustworthy. The archive record
## (record_lines()) always shows the authentic revision, which is what an
## investigation compares against.

const AUTHOR := "Ines · ops desk"
const REMINDERS := [
	"Stretch after the seal work. Your back will thank you.",
	"Mara's birthday is on day 9. Record something on the next comms window.",
	"Filters arrive in pairs. Store the spare at the back, label out.",
	"Hydrate before EVA, not after.",
	"Payroll closes on the 30th. Nothing to do, just so you know.",
	"Wipe the workstation keyboard. Everyone forgets.",
	"The galley timer is slow by a few seconds. Don't trust it for tea.",
	"Water the basil. It sulks if you forget.",
]


## {title, header: [lines], items: [{id, label, done}]}
static func build(dp: Node, q: Node) -> Dictionary:
	var day: int = int(dp.day_number) if dp != null else 1
	var header: Array = []
	header.append("Priority: %s" % (String(dp.today_title()) if dp != null else "routine checks"))
	# Round 44: TODAY also carries what Schedule used to show -- the open
	# jobs, compactly (DayPlan rows; no second task list).
	if dp != null:
		var open_rows: Array = dp.order_rows().filter(func(r): return not r.get("done", false) and String(r.get("id", "")) != "MEAL")
		if not open_rows.is_empty():
			var tags: Array = open_rows.slice(0, 4).map(func(r): return "%s (%s)" % [r["tag"], dp.ROOM_SHORT.get(StringName(r.get("room", &"")), "?")])
			header.append("Jobs: %s%s" % [", ".join(tags), "" if open_rows.size() <= 4 else " +%d" % (open_rows.size() - 4)])
	if dp != null and dp.has_method("cargo_port") and dp.cargo_port() != null:
		var nd: int = int(dp.next_cargo_day)
		header.append("Cargo: %s" % ("arrives TODAY — dock it before you rest" if nd == day or String(dp.cargo_duty) == "open" else "next drop day %d" % nd))
	var warn: Array = (Array(dp.supply_warnings()) if dp != null and dp.has_method("supply_warnings") else []).filter(func(w): return not String(w).to_upper().begins_with("CARGO"))
	header.append("Supplies: %s" % (String(warn[0]) if not warn.is_empty() else "stock OK"))
	if q != null and bool(q.get("missed_dinner")):
		header.append("You skipped dinner yesterday. Proper breakfast today.")
	header.append("Reminder: %s" % REMINDERS[(day - 1) % REMINDERS.size()])
	var items: Array = []
	var rs: Dictionary = q.routine_status() if q != null and q.has_method("routine_status") else {}
	items.append({"id": "brush", "label": "Brush teeth", "done": bool(rs.get("brush", false))})
	items.append({"id": "breakfast", "label": "Breakfast", "done": bool(rs.get("breakfast", false))})
	items.append({"id": "drink", "label": "Drink water", "done": bool(rs.get("drink", false))})
	if dp != null:
		var rows: Array = dp.order_rows().filter(func(r): return String(r.get("id", "")) != "MEAL")
		var done: int = rows.filter(func(r): return r.get("done", false)).size()
		if rows.is_empty():
			items.append({"id": "work", "label": "Station check-in", "done": dp.is_task_done(&"c01")})
		else:
			items.append({"id": "work", "label": "Work orders %d/%d" % [done, rows.size()], "done": done == rows.size()})
	items.append({"id": "dinner", "label": "Dinner (after the shift)", "done": bool(rs.get("dinner", false))})
	items.append({"id": "basil", "label": "Water the basil", "done": bool(rs.get("basil", false))})
	var status: String = ""
	if dp != null and dp.has_method("clock_text_hhmm"):
		status = " · %s · %s" % [dp.clock_text_hhmm(), "REST" if dp.shift_ended else "WORK %d%%" % int(round(dp.shift_progress() * 100.0))]
	return {"title": "SHIFT NOTE · DAY %d%s" % [day, status], "author": AUTHOR, "header": header, "items": items}


## The note as displayed: authentic content + presentation overlays.
## overlay: {kind: "extra_item"|"replace_line", text, match?}
static func lines(note: Dictionary, overlays: Array = []) -> Array:
	var out: Array = ["%s   ·   from %s" % [note["title"], note["author"]]]
	var header: Array = Array(note["header"]).duplicate()
	for o in overlays:
		if String(o.get("kind", "")) == "replace_line":
			for i in header.size():
				if String(header[i]).begins_with(String(o.get("match", "\u0000"))):
					header[i] = String(o["text"])
	out.append_array(header)
	out.append("— TODAY —")
	# Two checklist columns: the whole note fits one laptop screen.
	var cells: Array = []
	for it in note["items"]:
		cells.append("%s %s" % ["[x]" if it["done"] else "[ ]", it["label"]])
	for o in overlays:
		if String(o.get("kind", "")) == "extra_item":
			cells.append("[ ] %s" % o["text"])
	var i := 0
	while i < cells.size():
		var left: String = cells[i]
		if i + 1 < cells.size() and left.length() <= 26 and String(cells[i + 1]).length() <= 34:
			out.append(left.rpad(30) + String(cells[i + 1]))
			i += 2
		else:
			out.append(left)
			i += 1
	return out


## The archive record of today's note (always authentic): what an
## investigation compares the displayed note against.
static func record_lines(note: Dictionary, day: int) -> Array:
	var n: int = Array(note["items"]).size()
	return ["NOTE ARCHIVE · DAY %d" % day, "rev 1 · 07:58 · %s" % note["author"], "edits since issue: none", "checklist items issued: %d" % n, "", "Issued checklist:"] + Array(note["items"]).map(func(it): return "  - " + String(it["label"]))
