extends Control
## Round 38 Priority 10: CARGO DROP -- a small ORIGINAL falling-crate puzzle
## for the personal laptop (Entertainment folder). Own rules and art:
##   - crates fall in short shapes of 1-3 crates (single, pair, three-in-a-
##     row, corner) onto an 8 x 12 cargo bay;
##   - a FULL ROW is "shipped" (cleared) and scores 100 per row (x rows);
##   - the bay fills -> "BAY FULL", restart.
## Clickable buttons (< > rotate drop) and keyboard (arrows, Space) -- keys
## arrive while the laptop is zoomed (sleep_state forwards them into the
## laptop SubViewport). Ticks only while visible and not paused.

signal exited
signal score_changed(score: int)

const COLS := 8
const ROWS := 12
const CELL := 15
const SHAPES := [
	[Vector2i(0, 0)],
	[Vector2i(0, 0), Vector2i(1, 0)],
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
	[Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)],
]
const COLORS := [Color(0.85, 0.55, 0.15), Color(0.3, 0.7, 0.85), Color(0.55, 0.8, 0.35), Color(0.8, 0.4, 0.55)]

var grid: Array = []          # ROWS x COLS of -1 or color index
var piece: Array = []         # cells (Vector2i), relative
var piece_pos := Vector2i(3, 0)
var piece_color: int = 0
var score: int = 0
var best: int = 0
var game_over: bool = false
var _fall_t: float = 0.0
var _rng := RandomNumberGenerator.new()
var _board: Control
var _info: Label
var buttons := {}


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(440, 190)
	_board = Control.new()
	_board.position = Vector2(8, 4)
	_board.size = Vector2(COLS * CELL, ROWS * CELL)
	_board.draw.connect(_draw_board)
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_board)
	_info = Label.new()
	_info.position = Vector2(COLS * CELL + 22, 4)
	_info.size = Vector2(300, 80)
	_info.add_theme_font_size_override("font_size", 12)
	_info.add_theme_color_override("font_color", Color(0.85, 0.9, 0.85))
	add_child(_info)
	var specs := [["left", "<", Vector2(0, 0)], ["rotate", "Turn", Vector2(1, 0)], ["right", ">", Vector2(2, 0)], ["drop", "Drop", Vector2(0, 1)], ["restart", "Restart", Vector2(1, 1)], ["exit", "Exit", Vector2(2, 1)]]
	for s in specs:
		var b := Button.new()
		b.text = s[1]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 11)
		b.position = Vector2(COLS * CELL + 22 + s[2].x * 62, 96 + s[2].y * 30)
		b.size = Vector2(58, 26)
		var id: String = s[0]
		b.pressed.connect(func(): action(id))
		add_child(b)
		buttons[id] = b
	restart()


func restart() -> void:
	grid = []
	for r in ROWS:
		var row: Array = []
		row.resize(COLS)
		row.fill(-1)
		grid.append(row)
	score = 0
	game_over = false
	_rng.seed = Time.get_ticks_usec()
	_spawn()
	_refresh()


func action(id: String) -> void:
	match id:
		"left": _move(Vector2i(-1, 0))
		"right": _move(Vector2i(1, 0))
		"rotate": _rotate()
		"drop":
			while _move(Vector2i(0, 1)):
				pass
			_lock()
		"down":
			if not _move(Vector2i(0, 1)):
				_lock()
		"restart": restart()
		"exit": exited.emit()
	_refresh()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var map := {KEY_LEFT: "left", KEY_A: "left", KEY_RIGHT: "right", KEY_D: "right", KEY_UP: "rotate", KEY_W: "rotate", KEY_DOWN: "down", KEY_S: "down", KEY_SPACE: "drop", KEY_R: "restart"}
		if map.has(event.keycode):
			action(map[event.keycode])
			accept_event()


func _process(delta: float) -> void:
	if not is_visible_in_tree() or game_over:
		return
	_fall_t += delta
	if _fall_t >= maxf(0.25, 0.8 - score / 2000.0):
		_fall_t = 0.0
		if not _move(Vector2i(0, 1)):
			_lock()
		_refresh()


func _spawn() -> void:
	var i: int = _rng.randi() % SHAPES.size()
	piece = SHAPES[i].duplicate()
	piece_color = i
	piece_pos = Vector2i(3, 0)
	if not _fits(piece, piece_pos):
		game_over = true
		best = maxi(best, score)
		score_changed.emit(best)


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
	var rot: Array = piece.map(func(c): return Vector2i(-c.y, c.x))
	var minx: int = rot.map(func(c): return c.x).min()
	var miny: int = rot.map(func(c): return c.y).min()
	rot = rot.map(func(c): return c - Vector2i(minx, miny))
	if _fits(rot, piece_pos):
		piece = rot


func _lock() -> void:
	if game_over:
		return
	for c in piece:
		var p: Vector2i = c + piece_pos
		if p.y >= 0:
			grid[p.y][p.x] = piece_color
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
	score += 100 * cleared * cleared
	if score > best:
		best = score
		score_changed.emit(best)
	_spawn()


func _refresh() -> void:
	_info.text = "CARGO DROP\nShipped: %d\nBest: %d\n%s" % [score, best, "BAY FULL - Restart" if game_over else "Fill a row to ship it."]
	_board.queue_redraw()


func _draw_board() -> void:
	_board.draw_rect(Rect2(Vector2.ZERO, _board.size), Color(0.05, 0.07, 0.08))
	for r in ROWS:
		for c in COLS:
			var v: int = int(grid[r][c])
			if v != -1:
				_crate(Vector2(c, r), COLORS[v])
	if not game_over:
		for cell in piece:
			var p: Vector2i = cell + piece_pos
			if p.y >= 0:
				_crate(Vector2(p.x, p.y), COLORS[piece_color].lightened(0.15))
	_board.draw_rect(Rect2(Vector2.ZERO, _board.size), Color(0.4, 0.5, 0.5), false, 1.0)


func _crate(cell: Vector2, col: Color) -> void:
	var r := Rect2(cell * CELL + Vector2(1, 1), Vector2(CELL - 2, CELL - 2))
	_board.draw_rect(r, col)
	_board.draw_line(r.position, r.end, col.darkened(0.4), 1.0)
	_board.draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), col.darkened(0.4), 1.0)
