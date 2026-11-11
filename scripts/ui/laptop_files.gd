extends RefCounted
## Round 38 Priority 9: the personal laptop's small fictional FILE SYSTEM and
## its PHOTOS. Everything is invented for this game: ordinary, believable,
## no horror foreshadowing. Photos are ORIGINAL stylized images drawn
## procedurally at runtime (simple painted shapes and gradients) -- no
## external imagery is used or implied to be real.

## path -> {type: "dir"|"txt"|"img"|"app"|"msg", ...}
## Round 43 Priority 13: a real personal computer's tree -- TOP folders
## (FOLDERS) and SUBFOLDERS ("Parent/Child" keys, listed inside their
## parent). Fewer documents, each with identity: family, travel, an old
## chat, training and procedures, the shift handover, archived reports.
## The story-relevant handover note lives ONCE (Work/Shift Handover); the
## desktop SHIFT HANDOVER shortcut links to that same record.
const FOLDERS := ["Personal", "Work", "Photos", "Messages", "Journal", "Entertainment"]
const HANDOVER_PATH := "Work/Shift Handover"
const HANDOVER_FILE := "handover_previous_technician.txt"
const FILES := {
	"Personal": [
		{"name": "packing_list_next_rotation.txt", "date": "2026-09-30", "type": "txt", "text": "PACKING (next rotation)\n- wool socks x4 (the good ones)\n- spare charger\n- basil seeds for the hydro tray\n- Mara's book, return it this time\n- the small speaker"},
		{"name": "galley_notes.txt", "date": "2026-10-04", "type": "txt", "text": "GALLEY\n- breakfast pouch in the morning, dinner tray after the shift\n- water first, always (the air is dry)\n- skip a meal and the afternoon goes slow\n- the red mug is MINE"},
		{"name": "goals.txt", "date": "2026-10-02", "type": "txt", "text": "This rotation:\n1. Sleep before midnight station time.\n2. Finish the bread course (theory only, sadly).\n3. Call Mum every third day.\n4. Keep the maintenance logs clean."},
	],
	"Personal/Family": [
		{"name": "maras_birthday.txt", "date": "2026-10-03", "type": "txt", "text": "MARA - BIRTHDAY (day 9 of the rotation)\nRecord a message on the comms window.\nShe wants the 'proper' version of the song, not the joke one.\nGift is already with Mum (the green scarf)."},
		{"name": "letter_from_mum.txt", "date": "2026-09-27", "type": "txt", "text": "Love,\nI packed the jam in the blue jar because the lid seals better.\nDad fixed the gate. It still squeaks, but on purpose now, he says.\nEat properly. Sleep properly. Write when you can.\n- Mum"},
		{"name": "pip_vet_card.txt", "date": "2026-05-14", "type": "txt", "text": "PIP - vaccination card (scanned)\nBreed: 'mostly terrier'\nWeight: 9.1 kg (Mara: 'he is big boned')\nNext check-up: after the rotation."},
	],
	"Personal/Travel": [
		{"name": "coast_trip_2024.txt", "date": "2024-08-18", "type": "txt", "text": "Coast trip, day 2.\nRained until four, then the clouds opened and the whole bay went orange.\nAte chips on the sea wall. Best day of the summer.\nNote to self: bring a proper jacket next time."},
		{"name": "train_ticket_scan.txt", "date": "2024-08-17", "type": "txt", "text": "RETURN TICKET  ·  Coach C, seat 41\nOutward 07:12  ·  Return 18:40\n(kept it for the scrapbook)"},
	],
	"Personal/Old Messages": [
		{"name": "chat_with_dev_2025.txt", "date": "2025-11-02", "type": "txt", "text": "Dev: you actually took the station job??\nme: six weeks on, two off. it's mostly filters and fuses\nDev: and space\nme: and space\nDev: bring me a rock\nme: there are no rocks, it's a station\nDev: bring me a station rock"},
	],
	"Photos": [
		{"name": "family_dinner.jpg", "date": "2025-12-24", "type": "img", "photo": "dinner", "caption": "Family dinner, last winter"},
		{"name": "old_house.jpg", "date": "2019-06-11", "type": "img", "photo": "house", "caption": "The house on Fenn Road"},
		{"name": "pip.jpg", "date": "2026-04-03", "type": "img", "photo": "dog", "caption": "Pip in the garden"},
		{"name": "coast_trip.jpg", "date": "2024-08-17", "type": "img", "photo": "coast", "caption": "Coast trip, evening"},
		{"name": "grandads_watch.jpg", "date": "2023-02-02", "type": "img", "photo": "watch", "caption": "Grandad's watch"},
		{"name": "biscuit_1998.jpg", "date": "1998-07-20", "type": "img", "photo": "cat", "caption": "Biscuit, our first cat (1998)"},
		{"name": "hill_picnic.jpg", "date": "2022-05-08", "type": "img", "photo": "hill", "caption": "Picnic on Hollow Hill"},
	],
	"Messages": [
		{"name": "inbox", "date": "", "type": "msg"},
	],
	"Journal": [
		{"name": "personal_log.txt", "date": "", "type": "log"},
		{"name": "first_week_notes.txt", "date": "2026-10-05", "type": "txt", "text": "First week notes.\nThe ventilation is louder than the simulator. You stop hearing it by day three.\nThe workstation map is the best thing on board."},
	],
	"Work": [
		{"name": "rotation_contract_summary.txt", "date": "2026-08-20", "type": "txt", "text": "ROTATION SUMMARY\nRole: Station maintenance technician\nShift: one compressed work period per station day,\n  over when the day's work is done\nMeals: breakfast and dinner (galley), water through the day\nRest: mandatory between shifts\nContact: Crew Scheduling"},
		{"name": "payslip_october.txt", "date": "2026-10-31", "type": "txt", "text": "PAYSLIP - OCTOBER\nBase rotation allowance ....... paid\nHazard supplement ............ paid\nLaundry deduction ............ 0.00\n\nThank you for your service."},
	],
	"Work/Shift Handover": [
		{"name": "handover_previous_technician.txt", "date": "2026-10-01", "type": "txt", "story": "handover_read", "text": "HANDOVER NOTE (previous rotation)\nWelcome aboard. The station is in good shape.\n- The breaker panel labels are right. Trust them.\n- Comms drifts after a solar fault; retune, it holds.\n- Keep the seal on the outer hatch clean after cargo.\n- I logged everything I saw. You should too.\n  Write it down even when it seems like nothing.\n- The corridor camera is the one I watched most.\nGood luck. Sleep properly."},
		{"name": "about_daily_notes.txt", "date": "2026-10-01", "type": "txt", "text": "DAILY NOTES\nThe ops desk (Ines) posts one shift note every morning.\nIt's on the desktop: TODAY'S NOTE. The checklist ticks itself\nfrom the station's own records - no need to tick anything."},
	],
	"Work/Station Procedures": [
		{"name": "handbook_eva_excerpt.txt", "date": "2026-08-22", "type": "txt", "text": "EVA - QUICK REFERENCE\n1. Suit up at the airlock locker (4.3 psi, pure O2).\n2. Cargo transfers and seal inspections must be finished.\n3. Step into the chamber, press OUT<<: inner hatch seals,\n   chamber vents 14.7 -> 0 psi, outer hatch opens.\n4. Tether A is clipped to hatch ring A1.\n   W: thrust toward your aim. S: brake.\n5. Two tethers: click the next ring (free tether clips),\n   then R releases the older one. Never release the last.\n6. At a work site grab the handhold to stabilise.\n7. Back in the chamber, press IN>>."},
		{"name": "breaker_reset.txt", "date": "2026-08-22", "type": "txt", "text": "BREAKER RESET (Engineering panel)\n1. Find the tripped breaker (amber flag).\n2. Remove the load first if the workstation shows an overload.\n3. Reset, watch the lamp go green.\n4. If it trips again: stop. Find the fault, don't fight it."},
		{"name": "airlock_checklist.txt", "date": "2026-08-22", "type": "txt", "text": "AIRLOCK - BEFORE YOU REST\n- outer hatch closed and dogged (lever down)\n- chamber at 14.7 psi\n- suit back on the yoke, straps buckled\n- seal test PASS on the panel"},
	],
	"Work/Training": [
		{"name": "certificate_maintenance_L2.txt", "date": "2026-07-30", "type": "txt", "text": "CERTIFICATE\nOrbital Maintenance, Level 2\nElectrical, life support, mechanical, communications, EVA.\nAssessor's note: 'Calm. Methodical. Talks to the equipment.'"},
		{"name": "training_note_filters.txt", "date": "2026-07-12", "type": "txt", "text": "TRAINING NOTE - filters\nUsed cartridge OUT before new cartridge IN.\nLabel the used one, bin it at the disposal chute.\nThe housing lamp tells the truth; the timer does not."},
	],
	"Work/Archived Reports": [
		{"name": "shift_report_prev_rotation_d41.txt", "date": "2026-09-24", "type": "txt", "text": "SHIFT REPORT · previous rotation · day 41\nFilter service Life Support ......... done\nComms retune after solar fault ....... done\nCorridor camera INT-02 ............... checked (nothing found)\nOuter hatch seal ...................... cleaned\nNotes: quiet day."},
		{"name": "shift_report_prev_rotation_d42.txt", "date": "2026-09-25", "type": "txt", "text": "SHIFT REPORT · previous rotation · day 42\nBreaker B-03 reset ................... done\nCargo docked, unpacked ............... done\nNotes: handover prepared. Station in good shape."},
	],
	"Entertainment": [
		{"name": "Cargo Drop", "date": "2026-09-12", "type": "app", "app": "game"},
		{"name": "Holdout", "date": "2026-09-28", "type": "app", "app": "holdout"},
		{"name": "readme_holdout.txt", "date": "2026-09-28", "type": "txt", "text": "HOLDOUT\nA spaceman holds an abandoned moon colony\nagainst things that came out of the dark.\nWASD moves; your weapon fires by itself.\nKills, waves and scrap pay credits; spend them\nin the ARMORY. Modules can be entered. P pauses."},
		{"name": "readme_cargo_drop.txt", "date": "2026-09-12", "type": "txt", "text": "CARGO DROP\nPack falling cargo loads into the bay.\nA full row is shipped. New, awkward loads\nappear as the level rises.\nArrows move, Up turns, Down soft-drops,\nSpace drops, P pauses. Playing pauses the shift clock."},
	],
}


## Round 39: FOUNDATION for future personal content (new photos, notes,
## small games, easter eggs, story-driven messages): other systems add
## entries at runtime instead of editing the constant table. Entries are
## appended after the built-in ones; a new folder appears in Files.
static var _extra: Dictionary = {}


static func register(folder: String, rec: Dictionary) -> void:
	if not _extra.has(folder):
		_extra[folder] = []
	for r in _extra[folder]:
		if String(r.get("name", "")) == String(rec.get("name", "")):
			return
	_extra[folder].append(rec)


static func folders() -> Array:
	var out: Array = FOLDERS.duplicate()
	for f in _extra:
		if not f in out and String(f).find("/") == -1:
			out.append(f)
	return out


## Direct subfolders of `folder` (names only).
static func subfolders(folder: String) -> Array:
	var out: Array = []
	for k in Array(FILES.keys()) + Array(_extra.keys()):
		var ks: String = String(k)
		if ks.begins_with(folder + "/") and ks.substr(folder.length() + 1).find("/") == -1 and not ks.substr(folder.length() + 1) in out:
			out.append(ks.substr(folder.length() + 1))
	return out


static func find(folder: String, file_name: String) -> Dictionary:
	for r in list(folder):
		if String(r.get("name", "")) == file_name:
			return r
	return {}


## Every photo, wherever it is filed.
static func all_photos() -> Array:
	return list("Photos")


static func list(folder: String) -> Array:
	return Array(FILES.get(folder, [])) + Array(_extra.get(folder, []))


## A small original painted image for each photo id (W x H, RGB8).
static func photo(id: String, w: int = 200, h: int = 132) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	match id:
		"dinner":
			_grad(img, Color(0.35, 0.2, 0.12), Color(0.18, 0.1, 0.07))
			_rect(img, Rect2i(0, 84, w, 48), Color(0.45, 0.3, 0.2))
			_rect(img, Rect2i(20, 74, 160, 14), Color(0.85, 0.82, 0.75))
			for i in 5:
				var x: int = 30 + i * 32
				_circle(img, Vector2i(x, 52), 11, Color(0.75, 0.55, 0.42).darkened(0.1 * (i % 2)))
				_rect(img, Rect2i(x - 12, 62, 24, 16), [Color(0.6, 0.2, 0.2), Color(0.2, 0.3, 0.55), Color(0.25, 0.45, 0.3), Color(0.55, 0.45, 0.2), Color(0.4, 0.25, 0.45)][i])
			_circle(img, Vector2i(160, 22), 8, Color(1.0, 0.85, 0.5))
		"house":
			_grad(img, Color(0.45, 0.65, 0.9), Color(0.8, 0.88, 0.95))
			_rect(img, Rect2i(0, 100, w, 32), Color(0.35, 0.55, 0.3))
			_rect(img, Rect2i(60, 58, 80, 46), Color(0.82, 0.78, 0.7))
			_tri(img, Vector2i(52, 60), Vector2i(148, 60), Vector2i(100, 30), Color(0.55, 0.25, 0.2))
			_rect(img, Rect2i(92, 78, 16, 26), Color(0.35, 0.22, 0.15))
			_rect(img, Rect2i(68, 68, 14, 12), Color(0.6, 0.75, 0.85))
			_rect(img, Rect2i(118, 68, 14, 12), Color(0.6, 0.75, 0.85))
			_circle(img, Vector2i(170, 78), 18, Color(0.25, 0.45, 0.25))
			_rect(img, Rect2i(167, 92, 6, 12), Color(0.35, 0.25, 0.15))
		"dog":
			_grad(img, Color(0.55, 0.75, 0.9), Color(0.75, 0.85, 0.7))
			_rect(img, Rect2i(0, 80, w, 52), Color(0.38, 0.6, 0.3))
			_circle(img, Vector2i(96, 82), 22, Color(0.62, 0.45, 0.28))
			_circle(img, Vector2i(124, 66), 13, Color(0.66, 0.48, 0.3))
			_circle(img, Vector2i(131, 70), 4, Color(0.15, 0.1, 0.08))
			_rect(img, Rect2i(80, 98, 6, 16), Color(0.55, 0.4, 0.25))
			_rect(img, Rect2i(106, 98, 6, 16), Color(0.55, 0.4, 0.25))
			_rect(img, Rect2i(116, 54, 6, 10), Color(0.45, 0.32, 0.2))
			_circle(img, Vector2i(40, 110), 6, Color(0.9, 0.85, 0.3))
		"coast":
			_grad(img, Color(0.95, 0.65, 0.45), Color(0.45, 0.35, 0.55))
			_circle(img, Vector2i(140, 62), 16, Color(1.0, 0.8, 0.45))
			_grad_rect(img, Rect2i(0, 70, w, 40), Color(0.25, 0.35, 0.55), Color(0.15, 0.22, 0.4))
			_rect(img, Rect2i(0, 108, w, 24), Color(0.75, 0.65, 0.5))
			_rect(img, Rect2i(30, 92, 3, 18), Color(0.15, 0.12, 0.12))
			_circle(img, Vector2i(31, 89), 3, Color(0.15, 0.12, 0.12))
		"watch":
			_grad(img, Color(0.3, 0.25, 0.22), Color(0.15, 0.12, 0.1))
			_rect(img, Rect2i(88, 0, 24, w), Color(0.35, 0.22, 0.12))
			_circle(img, Vector2i(100, 66), 34, Color(0.75, 0.65, 0.4))
			_circle(img, Vector2i(100, 66), 29, Color(0.92, 0.9, 0.84))
			_rect(img, Rect2i(99, 44, 2, 22), Color(0.1, 0.1, 0.1))
			_rect(img, Rect2i(100, 65, 16, 2), Color(0.1, 0.1, 0.1))
		"cat":
			_grad(img, Color(0.85, 0.78, 0.65), Color(0.6, 0.5, 0.4))
			_rect(img, Rect2i(0, 92, w, 40), Color(0.45, 0.32, 0.25))
			_circle(img, Vector2i(96, 86), 26, Color(0.9, 0.6, 0.3))
			_circle(img, Vector2i(120, 62), 15, Color(0.92, 0.62, 0.32))
			_tri(img, Vector2i(110, 52), Vector2i(116, 40), Vector2i(120, 52), Color(0.85, 0.55, 0.28))
			_tri(img, Vector2i(124, 52), Vector2i(130, 40), Vector2i(134, 52), Color(0.85, 0.55, 0.28))
			_circle(img, Vector2i(116, 62), 2, Color(0.1, 0.15, 0.1))
			_circle(img, Vector2i(126, 62), 2, Color(0.1, 0.15, 0.1))
		"hill":
			return wallpaper(w, h, 5)
		_:
			_grad(img, Color(0.2, 0.2, 0.2), Color(0.1, 0.1, 0.1))
	# A soft vignette so they read as photographs, not diagrams.
	for y in h:
		for x in w:
			var dx: float = (x - w * 0.5) / (w * 0.5)
			var dy: float = (y - h * 0.5) / (h * 0.5)
			var k: float = clampf(1.0 - 0.35 * (dx * dx + dy * dy), 0.55, 1.0)
			img.set_pixel(x, y, img.get_pixel(x, y) * k)
	return ImageTexture.create_from_image(img)


static func _grad(img: Image, top: Color, bottom: Color) -> void:
	_grad_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), top, bottom)


static func _grad_rect(img: Image, r: Rect2i, top: Color, bottom: Color) -> void:
	for y in range(r.position.y, mini(r.end.y, img.get_height())):
		var c: Color = top.lerp(bottom, float(y - r.position.y) / maxf(r.size.y - 1, 1))
		for x in range(r.position.x, mini(r.end.x, img.get_width())):
			img.set_pixel(x, y, c)


static func _rect(img: Image, r: Rect2i, c: Color) -> void:
	img.fill_rect(r.intersection(Rect2i(0, 0, img.get_width(), img.get_height())), c)


static func _circle(img: Image, ctr: Vector2i, rad: int, c: Color) -> void:
	for y in range(ctr.y - rad, ctr.y + rad + 1):
		for x in range(ctr.x - rad, ctr.x + rad + 1):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() and (x - ctr.x) * (x - ctr.x) + (y - ctr.y) * (y - ctr.y) <= rad * rad:
				img.set_pixel(x, y, c)


static func _tri(img: Image, a: Vector2i, b: Vector2i, c: Vector2i, col: Color) -> void:
	var minx: int = mini(a.x, mini(b.x, c.x))
	var maxx: int = maxi(a.x, maxi(b.x, c.x))
	var miny: int = mini(a.y, mini(b.y, c.y))
	var maxy: int = maxi(a.y, maxi(b.y, c.y))
	for y in range(miny, maxy + 1):
		for x in range(minx, maxx + 1):
			var p := Vector2(x, y)
			if Geometry2D.point_is_inside_triangle(p, Vector2(a), Vector2(b), Vector2(c)) and x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				img.set_pixel(x, y, col)



## Round 43 Priority 12: the desktop WALLPAPER -- an ORIGINAL painted
## landscape (procedural, not a copy of any photograph): a soft blue sky
## with drifting white clouds over rolling green hills in bright daylight.
## Generated at the laptop's render resolution (no enlarged, blurry image).
static func wallpaper(w: int = 960, h: int = 560, seed: int = 43) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var sky_top := Color(0.16, 0.42, 0.86)
	var sky_low := Color(0.62, 0.8, 0.97)
	for y in h:
		var c: Color = sky_top.lerp(sky_low, pow(float(y) / float(h), 0.8))
		for x in w:
			img.set_pixel(x, y, c)
	# Clouds: clusters of soft white puffs.
	for k in 7:
		var cx: float = rng.randf_range(0.0, w)
		var cy: float = rng.randf_range(h * 0.06, h * 0.36)
		var s: float = rng.randf_range(0.6, 1.3) * w / 960.0
		for p in 9:
			var px: float = cx + rng.randf_range(-90, 90) * s
			var py: float = cy + rng.randf_range(-18, 14) * s
			var r: float = rng.randf_range(22, 44) * s
			_puff(img, Vector2(px, py), r)
	# Rolling hills: a far, paler ridge and the big bright near hill.
	var far := PackedFloat32Array()
	var near := PackedFloat32Array()
	far.resize(w)
	near.resize(w)
	for x in w:
		var u: float = float(x) / float(w)
		far[x] = h * (0.62 - 0.05 * sin(u * 5.1 + 0.8) - 0.03 * sin(u * 11.0))
		near[x] = h * (0.74 - 0.16 * exp(-pow((u - 0.42) / 0.33, 2.0)) - 0.03 * sin(u * 7.3 + 1.7))
	for x in w:
		for y in range(int(far[x]), h):
			var t: float = float(y - far[x]) / float(h)
			img.set_pixel(x, y, Color(0.36, 0.62, 0.32).lerp(Color(0.3, 0.52, 0.27), t))
		for y in range(int(near[x]), h):
			var t2: float = clampf(float(y - near[x]) / (h * 0.35), 0.0, 1.0)
			# Sunlit crest -> deeper green slope, a little texture.
			var g: Color = Color(0.47, 0.78, 0.25).lerp(Color(0.24, 0.55, 0.16), t2)
			g = g.darkened(0.05 * sin(float(x) * 0.07 + float(y) * 0.11) * sin(float(y) * 0.05))
			img.set_pixel(x, y, g)
	return ImageTexture.create_from_image(img)


static func _puff(img: Image, ctr: Vector2, r: float) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	for y in range(maxi(int(ctr.y - r), 0), mini(int(ctr.y + r) + 1, h)):
		for x in range(maxi(int(ctr.x - r), 0), mini(int(ctr.x + r) + 1, w)):
			var d: float = Vector2(x, y).distance_to(ctr) / r
			if d < 1.0:
				var a: float = clampf((1.0 - d) * 2.2, 0.0, 0.92)
				var shade: float = clampf((float(y) - ctr.y) / r * 0.5 + 0.5, 0.0, 1.0)
				var cloud := Color(1.0, 1.0, 1.0).lerp(Color(0.86, 0.9, 0.95), shade)
				img.set_pixel(x, y, img.get_pixel(x, y).lerp(cloud, a))


# ======================================================================
# Round 45 Priorities 17-18: the previous technician's SHIFT NOTE ARCHIVE.
# A FINITE set written during THEIR rotation (dated September, rotation 4)
# -- nobody is writing new ones. One more becomes available each station
# day (note k on day k); earlier ones never disappear. Mostly ordinary;
# a few lines only matter later (the airlock-tunnel port, seen across the
# courtyard from the Control Room window).
# ======================================================================
const HANDOVER_NOTES := [
	["2026-09-15", "SHIFT NOTE · R.V. · rotation 4, day 33\nFilter housing L-3 at 60%. Fine for a week.\nBreaker B-02 tripped once at 14:20. Reset, no cause found.\nStock: 16GA wire, 4 left. Order more.\nBasil: alive. Barely."],
	["2026-09-16", "SHIFT NOTE · R.V. · day 34\nComms retuned after the morning solar fault. Holds at 63.\nCleaned the outer hatch seal; grit from the last cargo.\nThe galley timer is slow. Still."],
	["2026-09-17", "SHIFT NOTE · R.V. · day 35\nQuiet shift. Vent grille in Life Support cleaned.\nINT-02 drifted left after the power cycle. Nudged it back.\nDreamt about the house again."],
	["2026-09-18", "SHIFT NOTE · R.V. · day 36\nThermal survey: TB-A terminal 2 runs warm. Torqued it.\nCargo day. Seal checked after.\nThe fans changed pitch at 03:00 and woke me up."],
	["2026-09-19", "SHIFT NOTE · R.V. · day 37\nCoolant manifold OK. Storage audit: 2 spare filters.\nHeard the airlock latch at 22:40. Log shows nothing. Thermal, probably.\n(Writing it down anyway.)"],
	["2026-09-20", "SHIFT NOTE · R.V. · day 38\nSolar wing L hinge stiff again. EVA if it gets worse.\nSent Mum the photo of the planet. She says it looks cold."],
	["2026-09-21", "SHIFT NOTE · R.V. · day 39\nEVA: freed the L hinge. Tether A1 -> L3. Fine.\nFrom outside, the airlock tunnel port looked dark.\nI'd left the light on. Checked after: it was on."],
	["2026-09-22", "SHIFT NOTE · R.V. · day 40\nRoutine rounds. All readings match.\nI keep looking at the tunnel port from the Control Room window.\nNothing there. Of course."],
	["2026-09-23", "SHIFT NOTE · R.V. · day 41\nB-03 overload, my fault: two loads at once.\nNew rule: one load at a time.\nThe corridor camera is the one I watch most."],
	["2026-09-24", "SHIFT NOTE · R.V. · day 42\nLast full shift. Handover tomorrow.\nIf you're reading this: the station is good. Trust the labels.\nSleep properly. Don't stand at the window too long."],
]


## Released archive notes on `day` (note k needs day >= k), as file records.
static func handover_records(day: int) -> Array:
	var out: Array = []
	for k in mini(day, HANDOVER_NOTES.size()):
		out.append({"name": "shift_note_%02d.txt" % (k + 1), "date": HANDOVER_NOTES[k][0], "type": "txt", "text": HANDOVER_NOTES[k][1], "handover": k + 1})
	return out
