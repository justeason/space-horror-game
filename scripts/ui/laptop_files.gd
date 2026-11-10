extends RefCounted
## Round 38 Priority 9: the personal laptop's small fictional FILE SYSTEM and
## its PHOTOS. Everything is invented for this game: ordinary, believable,
## no horror foreshadowing. Photos are ORIGINAL stylized images drawn
## procedurally at runtime (simple painted shapes and gradients) -- no
## external imagery is used or implied to be real.

## path -> {type: "dir"|"txt"|"img"|"app"|"msg", ...}
const FOLDERS := ["Personal", "Photos", "Messages", "Journal", "Documents", "Entertainment"]
const FILES := {
	"Personal": [
		{"name": "packing_list_next_rotation.txt", "date": "2026-09-30", "type": "txt", "text": "PACKING (next rotation)\n- wool socks x4 (the good ones)\n- spare charger\n- basil seeds for the hydro tray\n- Mara's book, return it this time\n- the small speaker"},
		{"name": "galley_notes.txt", "date": "2026-10-04", "type": "txt", "text": "GALLEY\n- water first, always (the air is dry)\n- lentil packs: add hot water, wait, stir\n- skip a meal and the afternoon goes slow\n- the red mug is MINE"},
		{"name": "goals.txt", "date": "2026-10-02", "type": "txt", "text": "This rotation:\n1. Sleep before midnight station time.\n2. Finish the bread course (theory only, sadly).\n3. Call Mum every third day.\n4. Keep the maintenance logs clean."},
	],
	"Photos": [
		{"name": "family_dinner.jpg", "date": "2025-12-24", "type": "img", "photo": "dinner", "caption": "Family dinner, last winter"},
		{"name": "old_house.jpg", "date": "2019-06-11", "type": "img", "photo": "house", "caption": "The house on Fenn Road"},
		{"name": "pip.jpg", "date": "2026-04-03", "type": "img", "photo": "dog", "caption": "Pip in the garden"},
		{"name": "coast_trip.jpg", "date": "2024-08-17", "type": "img", "photo": "coast", "caption": "Coast trip, evening"},
		{"name": "grandads_watch.jpg", "date": "2023-02-02", "type": "img", "photo": "watch", "caption": "Grandad's watch"},
	],
	"Messages": [
		{"name": "inbox", "date": "", "type": "msg"},
	],
	"Journal": [
		{"name": "personal_log.txt", "date": "", "type": "log"},
		{"name": "first_week_notes.txt", "date": "2026-10-05", "type": "txt", "text": "First week notes.\nThe ventilation is louder than the simulator. You stop hearing it by day three.\nThe workstation map is the best thing on board."},
	],
	"Documents": [
		{"name": "rotation_contract_summary.txt", "date": "2026-08-20", "type": "txt", "text": "ROTATION SUMMARY\nRole: Station maintenance technician\nShift: one compressed work period per station day,\n  over when the day's work is done\nMeals: eat and drink every day (galley)\nRest: mandatory between shifts\nContact: Crew Scheduling"},
		{"name": "payslip_october.txt", "date": "2026-10-31", "type": "txt", "text": "PAYSLIP - OCTOBER\nBase rotation allowance ....... paid\nHazard supplement ............ paid\nLaundry deduction ............ 0.00\n\nThank you for your service."},
		{"name": "handover_previous_technician.txt", "date": "2026-10-01", "type": "txt", "story": "handover_read", "text": "HANDOVER NOTE (previous rotation)\nWelcome aboard. The station is in good shape.\n- The breaker panel labels are right. Trust them.\n- Comms drifts after a solar fault; retune, it holds.\n- Keep the seal on the outer hatch clean after cargo.\n- I logged everything I saw. You should too.\n  Write it down even when it seems like nothing.\n- The corridor camera is the one I watched most.\nGood luck. Sleep properly."},
		{"name": "handbook_eva_excerpt.txt", "date": "2026-08-22", "type": "txt", "text": "EVA - QUICK REFERENCE\n1. Suit up at the airlock locker (4.3 psi, pure O2).\n2. Cargo transfers and seal inspections must be finished.\n3. Step into the chamber, press OUT<<: inner hatch seals,\n   chamber vents 14.7 -> 0 psi, outer hatch opens.\n4. Tether A is clipped to hatch ring A1.\n   W: thrust toward your aim. S: brake.\n5. Two tethers: click the next ring (free tether clips),\n   then R releases the older one. Never release the last.\n6. At a work site grab the handhold to stabilise.\n7. Back in the chamber, press IN>>."},
	],
	"Entertainment": [
		{"name": "Cargo Drop", "date": "2026-09-12", "type": "app", "app": "game"},
		{"name": "Holdout", "date": "2026-09-28", "type": "app", "app": "holdout"},
		{"name": "readme_holdout.txt", "date": "2026-09-28", "type": "txt", "text": "HOLDOUT\nSurvive the waves. WASD moves; the sidearm\nfires by itself at the nearest zombie.\nKills and cleared waves pay credits;\nspend them on upgrades between waves.\nP pauses. Credits are only for this game."},
		{"name": "readme_cargo_drop.txt", "date": "2026-09-12", "type": "txt", "text": "CARGO DROP\nPack falling cargo loads into the bay.\nA full row is shipped. New, awkward loads\nappear as the level rises.\nArrows move, Up turns, Down soft-drops,\nSpace drops, P pauses."},
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
		if not f in out:
			out.append(f)
	return out


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
