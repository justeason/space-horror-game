extends Control
## Round 38 Priority 10 / Round 41 Priority 18: CARGO DROP -- an ORIGINAL
## falling-cargo packing puzzle for the personal laptop (Entertainment).
## Own rules, names and art (crates, manifests, bays):
##   - CARGO SHAPES fall into a 10 x 15 bay; a FULL ROW is shipped;
##   - the SHAPE LIBRARY grows with the level (TIERS): early manifests are
##     small familiar crates (2x2 block, short / long rods, corners), then
##     tee, zig and zag four-crate loads, then five-crate long corners,
##     big tees, P / U and long rods, then awkward asymmetric loads (F, N,
##     stair, Y) -- every shape fits the bay in every rotation;
##   - FAIR SEQUENCE: a seeded MANIFEST BAG holds every unlocked shape once,
##     shuffled per bag (no droughts, no floods of hard pieces); the seed
##     makes a run reproducible (tests);
##   - controls: < > move, TURN (with small wall kicks), DOWN (soft drop,
##     +1/row), DROP (hard drop, +2/row), PAUSE, RESTART, EXIT; keyboard
##     arrows / A D, W / Up turn, S / Down soft, Space hard, P pause, R;
##   - a GHOST shows where the load will land; NEXT shows the next load;
##   - score: rows x level (100 / 300 / 500 / 800), level = 1 + rows / 6,
##     the fall speeds up with the level;
##   - placement / shipping sounds on the SFX bus.
## SAVE: the best score (laptop); an unfinished run is saved as a compact
## state and restored PAUSED -- validated on load (dimensions, cell values,
## the falling load must fit) or discarded for a clean restart.

signal exited
signal score_changed(score: int)

const COLS := 10
const ROWS := 15
const CELL := 12
## name -> [tier, cells]
const SHAPES := {
	"BLOCK": [0, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]],
	"ROD3": [0, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]],
	"ROD4": [0, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]],
	"CORNER": [0, [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)]],
	"ELL": [0, [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)]],
	"JAY": [0, [Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(0, 2)]],
	"TEE": [1, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)]],
	"ZIG": [1, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)]],
	"ZAG": [1, [Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)]],
	"LONG_ELL": [2, [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(1, 3)]],
	"BIG_TEE": [2, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(1, 2)]],
	"PEE": [2, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2)]],
	"CUP": [2, [Vector2i(0, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)]],
	"ROD5": [2, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)]],
	"EFF": [3, [Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2)]],
	"ENN": [3, [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(0, 3)]],
	"STAIR": [3, [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 2)]],
	"WYE": [3, [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3)]],
}
const SHAPE_ORDER := ["BLOCK", "ROD3", "ROD4", "CORNER", "ELL", "JAY", "TEE", "ZIG", "ZAG", "LONG_ELL", "BIG_TEE", "PEE", "CUP", "ROD5", "EFF", "ENN", "STAIR", "WYE"]
## Level at which each tier joins the manifest.
const TIER_LEVEL := [1, 2, 4, 6]
const COLORS := [Color(0.85, 0.55, 0.15), Color(0.3, 0.7, 0.85), Color(0.55, 0.8, 0.35), Color(0.8, 0.4, 0.55), Color(0.9, 0.8, 0.3), Color(0.55, 0.5, 0.9)]
const LINE_SCORE := [0, 100, 300, 500, 800]
const KICKS := [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-2, 0), Vector2i(2, 0), Vector2i(0, -1)]

var grid: Array = []          # ROWS x COLS of -1 or color index
var piece: Array = []         # cells (Vector2i), relative
var piece_name: String = ""
var piece_pos := Vector2i(3, 0)
var piece_color: int = 0
var next_name: String = ""
var score: int = 0
var lines: int = 0
var level: int = 1
var best: int = 0
var game_over: bool = false
var paused: bool = false
var seed: int = 0
var bag_index: int = 0
var _bag: Array = []
var _fall_t: float = 0.0
var _board: Control
var _next: Control
var _info: Label
var _sfx: AudioStreamPlayer
var _sounds: Dictionary = {}
var buttons := {}
var history: Array = []       # names of spawned loads (tests)


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(440, 190)
	_board = Control.new()
	_board.position = Vector2(6, 4)
	_board.size = Vector2(COLS * CELL, ROWS * CELL)
	_board.draw.connect(_draw_board)
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_board)
	_info = Label.new()
	_info.position = Vector2(COLS * CELL + 18, 2)
	_info.size = Vector2(150, 92)
	_info.add_theme_font_size_override("font_size", 11)
	_info.add_theme_color_override("font_color", Color(0.85, 0.9, 0.85))
	add_child(_info)
	var nl := Label.new()
	nl.text = "NEXT"
	nl.position = Vector2(COLS * CELL + 176, 2)
	nl.add_theme_font_size_override("font_size", 10)
	nl.add_theme_color_override("font_color", Color(0.85, 0.75, 0.45))
	add_child(nl)
	_next = Control.new()
	_next.position = Vector2(COLS * CELL + 176, 18)
	_next.size = Vector2(66, 54)
	_next.draw.connect(_draw_next)
	_next.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_next)
	var specs := [["left", "<", Vector2(0, 0)], ["rotate", "Turn", Vector2(1, 0)], ["right", ">", Vector2(2, 0)], ["down", "Down", Vector2(3, 0)],
		["drop", "Drop", Vector2(0, 1)], ["pause", "Pause", Vector2(1, 1)], ["restart", "Restart", Vector2(2, 1)], ["exit", "Exit", Vector2(3, 1)]]
	for s in specs:
		var b := Button.new()
		b.text = s[1]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 11)
		b.position = Vector2(COLS * CELL + 18 + s[2].x * 64, 112 + s[2].y * 32)
		b.size = Vector2(60, 28)
		var id: String = s[0]
		b.pressed.connect(func(): action(id))
		add_child(b)
		buttons[id] = b
	_build_over_panel()
	_build_sounds()
	restart()


var _over: PanelContainer
var _over_text: Label


func _build_over_panel() -> void:
	_over = PanelContainer.new()
	_over.name = "GameOver"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.03, 0.04, 0.92)
	sb.border_color = Color(0.95, 0.55, 0.15)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(8)
	_over.add_theme_stylebox_override("panel", sb)
	_over.position = Vector2(14, 40)
	_over.size = Vector2(COLS * CELL + 120, 112)
	add_child(_over)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_over.add_child(v)
	var t := Label.new()
	t.text = "GAME OVER"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 18)
	t.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	v.add_child(t)
	_over_text = Label.new()
	_over_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_text.add_theme_font_size_override("font_size", 11)
	v.add_child(_over_text)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 8)
	v.add_child(h)
	for spec in [["over_restart", "RESTART", "restart"], ["over_exit", "DESKTOP", "exit"]]:
		var b := Button.new()
		b.text = spec[1]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 11)
		var act: String = spec[2]
		b.pressed.connect(func(): action(act))
		h.add_child(b)
		buttons[spec[0]] = b
	_over.visible = false


func _build_sounds() -> void:
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "SFX"
	_sfx.volume_db = -10.0
	add_child(_sfx)
	_sounds["lock"] = _tone(0.06, func(t): return sin(t * TAU * 18.0) * pow(1.0 - t, 4.0) * 0.5)          # ~300 Hz thunk
	_sounds["ship"] = _tone(0.25, func(t): return sin(t * TAU * (130.0 if t < 0.5 else 195.0)) * pow(1.0 - fmod(t, 0.5) * 2.0, 2.0) * 0.45)   # 520 -> 780 Hz
	_sounds["turn"] = _tone(0.03, func(t): return sin(t * TAU * 45.0) * (1.0 - t) * 0.25)


func _tone(dur: float, f: Callable) -> AudioStreamWAV:
	var rate := 11025
	var n := int(rate * dur)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(f.call(float(i) / n), -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.data = bytes
	return s


func _play(kind: String) -> void:
	if _sfx != null and _sounds.has(kind) and is_inside_tree():
		_sfx.stream = _sounds[kind]
		_sfx.play()


func restart(p_seed: int = -1) -> void:
	grid = []
	for r in ROWS:
		var row: Array = []
		row.resize(COLS)
		row.fill(-1)
		grid.append(row)
	score = 0
	lines = 0
	level = 1
	game_over = false
	over_reason = ""
	paused = false
	seed = p_seed if p_seed >= 0 else int(Time.get_ticks_usec() % 1000000)
	bag_index = 0
	_bag = []
	history = []
	next_name = _draw_from_bag()
	_spawn()
	_refresh()


# ------------------------------------------------------------- manifest
static func unlocked_for_level(lv: int) -> Array:
	var out: Array = []
	for n in SHAPE_ORDER:
		if lv >= TIER_LEVEL[int(SHAPES[n][0])]:
			out.append(n)
	return out


func _draw_from_bag() -> String:
	if _bag.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed, bag_index])
		bag_index += 1
		_bag = unlocked_for_level(level)
		for i in range(_bag.size() - 1, 0, -1):
			var j: int = rng.randi() % (i + 1)
			var t = _bag[i]
			_bag[i] = _bag[j]
			_bag[j] = t
	return _bag.pop_front()


func _spawn() -> void:
	piece_name = next_name
	next_name = _draw_from_bag()
	history.append(piece_name)
	piece = Array(SHAPES[piece_name][1]).duplicate()
	piece_color = SHAPE_ORDER.find(piece_name) % COLORS.size()
	var w: int = _extent(piece).x
	piece_pos = Vector2i((COLS - w) / 2, 0)
	if not _fits(piece, piece_pos):
		_end_game("NO ROOM TO LOAD")


## Round 42 Priority 22: a real GAME OVER: no more spawning or falling,
## a clear screen with the final / best score, RESTART and DESKTOP.
var over_reason: String = ""


func _end_game(reason: String) -> void:
	game_over = true
	paused = false
	over_reason = reason
	best = maxi(best, score)
	score_changed.emit(best)
	_play("lock")
	_refresh()


static func _extent(cells: Array) -> Vector2i:
	var mx := 0
	var my := 0
	for c in cells:
		mx = maxi(mx, c.x)
		my = maxi(my, c.y)
	return Vector2i(mx + 1, my + 1)


static func rotated(cells: Array) -> Array:
	var rot: Array = cells.map(func(c): return Vector2i(-c.y, c.x))
	var minx: int = rot.map(func(c): return c.x).min()
	var miny: int = rot.map(func(c): return c.y).min()
	return rot.map(func(c): return c - Vector2i(minx, miny))


# ---------------------------------------------------------------- input
func action(id: String) -> void:
	match id:
		"pause":
			if not game_over:
				paused = not paused
		"restart": restart()
		"exit":
			paused = not game_over
			exited.emit()
		_:
			if paused or game_over:
				_refresh()
				return
			match id:
				"left": _move(Vector2i(-1, 0))
				"right": _move(Vector2i(1, 0))
				"rotate": _rotate()
				"down":
					if _move(Vector2i(0, 1)):
						score += 1
					else:
						_lock()
				"drop":
					var n := 0
					while _move(Vector2i(0, 1)):
						n += 1
					score += 2 * n
					_lock()
	_refresh()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if game_over and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			action("restart")
			accept_event()
			return
		var map := {KEY_LEFT: "left", KEY_A: "left", KEY_RIGHT: "right", KEY_D: "right", KEY_UP: "rotate", KEY_W: "rotate", KEY_DOWN: "down", KEY_S: "down", KEY_SPACE: "drop", KEY_R: "restart", KEY_P: "pause"}
		if map.has(event.keycode):
			action(map[event.keycode])
			accept_event()


func fall_interval() -> float:
	return maxf(0.12, 0.8 - 0.07 * (level - 1))


func _process(delta: float) -> void:
	if not is_visible_in_tree() or game_over or paused:
		return
	_fall_t += delta
	if _fall_t >= fall_interval():
		_fall_t = 0.0
		if not _move(Vector2i(0, 1)):
			_lock()
		_refresh()


func _fits(cells: Array, pos: Vector2i) -> bool:
	for c in cells:
		var p: Vector2i = c + pos
		if p.x < 0 or p.x >= COLS or p.y >= ROWS:
			return false
		if p.y >= 0 and int(grid[p.y][p.x]) != -1:
			return false
	return true


func _move(d: Vector2i) -> bool:
	if game_over or not _fits(piece, piece_pos + d):
		return false
	piece_pos += d
	return true


func _rotate() -> void:
	if game_over:
		return
	var rot: Array = rotated(piece)
	for k in KICKS:
		if _fits(rot, piece_pos + k):
			piece = rot
			piece_pos += k
			_play("turn")
			return


## Where the falling load would land (the ghost).
func ghost_pos() -> Vector2i:
	var p: Vector2i = piece_pos
	while _fits(piece, p + Vector2i(0, 1)):
		p += Vector2i(0, 1)
	return p


func _lock() -> void:
	if game_over:
		return
	var locked_out := false
	for c in piece:
		var p: Vector2i = c + piece_pos
		if p.y >= 0:
			grid[p.y][p.x] = piece_color
		else:
			locked_out = true
	# Round 42 Priority 22: a load that settles (partly) ABOVE the bay is a
	# top-out -- game over, not a silently clipped piece.
	if locked_out:
		_end_game("BAY FULL")
		return
	var cleared := 0
	var r := ROWS - 1
	while r >= 0:
		if grid[r].all(func(v): return int(v) != -1):
			grid.remove_at(r)
			var row: Array = []
			row.resize(COLS)
			row.fill(-1)
			grid.insert(0, row)
			cleared += 1
		else:
			r -= 1
	if cleared > 0:
		score += LINE_SCORE[mini(cleared, 4)] * level
		lines += cleared
		var new_level: int = 1 + lines / 6
		if new_level != level:
			level = new_level
			_bag = []           # the next manifest includes newly unlocked shapes
		_play("ship")
	else:
		_play("lock")
	if score > best:
		best = score
		score_changed.emit(best)
	_spawn()


# ---------------------------------------------------------------- views
func _refresh() -> void:
	var status: String = "GAME OVER" if game_over else ("PAUSED" if paused else "Fill a row to ship it.")
	if _over != null:
		_over.visible = game_over
		if game_over:
			_over_text.text = "%s\nFinal score %d   ·   Best %d\nRows %d   ·   Level %d" % [over_reason, score, best, lines, level]
	_info.text = "CARGO DROP\nScore %d   Best %d\nRows %d   Level %d\n%s" % [score, best, lines, level, status]
	_board.queue_redraw()
	if _next != null:
		_next.queue_redraw()


func _draw_board() -> void:
	_board.draw_rect(Rect2(Vector2.ZERO, _board.size), Color(0.05, 0.07, 0.08))
	for c in range(1, COLS):
		_board.draw_line(Vector2(c * CELL, 0), Vector2(c * CELL, _board.size.y), Color(0.09, 0.12, 0.13), 1.0)
	for r in ROWS:
		for c in COLS:
			var v: int = int(grid[r][c])
			if v != -1:
				_crate(_board, Vector2(c, r) * CELL, COLORS[v])
	if not game_over:
		var g: Vector2i = ghost_pos()
		for cell in piece:
			var p: Vector2i = cell + g
			if p.y >= 0:
				_board.draw_rect(Rect2(Vector2(p) * CELL + Vector2(1, 1), Vector2(CELL - 2, CELL - 2)), Color(COLORS[piece_color], 0.3), false, 1.0)
		for cell in piece:
			var p: Vector2i = cell + piece_pos
			if p.y >= 0:
				_crate(_board, Vector2(p) * CELL, COLORS[piece_color].lightened(0.15))
	_board.draw_rect(Rect2(Vector2.ZERO, _board.size), Color(0.4, 0.5, 0.5), false, 1.0)
	if paused:
		_board.draw_rect(Rect2(Vector2.ZERO, _board.size), Color(0, 0, 0, 0.45))


func _draw_next() -> void:
	_next.draw_rect(Rect2(Vector2.ZERO, _next.size), Color(0.05, 0.07, 0.08))
	_next.draw_rect(Rect2(Vector2.ZERO, _next.size), Color(0.4, 0.5, 0.5), false, 1.0)
	if next_name == "":
		return
	var cells: Array = SHAPES[next_name][1]
	var ext: Vector2i = _extent(cells)
	var cs := 10.0
	var off: Vector2 = (_next.size - Vector2(ext) * cs) * 0.5
	for c in cells:
		_crate(_next, off + Vector2(c) * cs, COLORS[SHAPE_ORDER.find(next_name) % COLORS.size()], cs)


func _crate(target: Control, at: Vector2, col: Color, cs: float = CELL) -> void:
	var r := Rect2(at + Vector2(1, 1), Vector2(cs - 2, cs - 2))
	target.draw_rect(r, col)
	target.draw_line(r.position, r.end, col.darkened(0.4), 1.0)
	target.draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), col.darkened(0.4), 1.0)


# ------------------------------------------------------------ save / load
## A compact snapshot of an unfinished run (restored PAUSED); {} when
## there is nothing worth keeping.
func state_dict() -> Dictionary:
	if game_over or (score == 0 and lines == 0 and history.size() <= 1):
		return {}
	return {"grid": grid.duplicate(true), "piece": piece_name, "cells": piece.map(func(c): return [c.x, c.y]), "pos": [piece_pos.x, piece_pos.y],
		"color": piece_color, "next": next_name, "score": score, "lines": lines, "level": level, "seed": seed, "bag_index": bag_index, "bag": _bag.duplicate()}


## Validates everything; on any inconsistency the run is discarded.
func load_state(d: Dictionary) -> bool:
	if d.is_empty():
		return false
	var g: Array = d.get("grid", [])
	if g.size() != ROWS:
		return false
	for row in g:
		if not (row is Array) or (row as Array).size() != COLS:
			return false
		for v in row:
			if int(v) < -1 or int(v) >= COLORS.size():
				return false
	if not SHAPES.has(String(d.get("piece", ""))) or not SHAPES.has(String(d.get("next", ""))):
		return false
	var cells: Array = Array(d.get("cells", [])).map(func(c): return Vector2i(int(c[0]), int(c[1])))
	if cells.size() != Array(SHAPES[String(d["piece"])][1]).size():
		return false
	var saved_grid: Array = []
	for row in g:
		saved_grid.append(Array(row).map(func(v): return int(v)))
	var old_grid: Array = grid
	grid = saved_grid
	var pos := Vector2i(int(d["pos"][0]), int(d["pos"][1]))
	if not _fits(cells, pos):
		grid = old_grid
		return false
	piece_name = String(d["piece"])
	piece = cells
	piece_pos = pos
	piece_color = clampi(int(d.get("color", 0)), 0, COLORS.size() - 1)
	next_name = String(d["next"])
	score = int(d.get("score", 0))
	lines = int(d.get("lines", 0))
	level = maxi(1, int(d.get("level", 1)))
	seed = int(d.get("seed", 0))
	bag_index = int(d.get("bag_index", 0))
	_bag = Array(d.get("bag", [])).filter(func(n): return SHAPES.has(String(n))).map(func(n): return String(n))
	game_over = false
	paused = true
	_refresh()
	return true


## Invariant check (tests): every cell is -1 or a colour; the falling load
## overlaps nothing.
func board_valid() -> bool:
	if grid.size() != ROWS:
		return false
	for row in grid:
		if row.size() != COLS or row.any(func(v): return int(v) < -1 or int(v) >= COLORS.size()):
			return false
	return game_over or _fits(piece, piece_pos)
