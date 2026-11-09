extends SceneTree
## Round 41 Priority 18: the harder CARGO DROP -- shape library (L, T, Z,
## long, asymmetric, five-crate loads), tiers by level, fair seeded
## manifest bag, rotation + wall kicks, edge collision, row shipping and
## scoring, ghost / next preview, pause, and the saved paused run (with a
## corrupt snapshot rejected).
const Game = preload("res://scripts/ui/cargo_drop_game.gd")
var _ok := true


func _init() -> void:
	var g: Control = Game.new()
	get_root().add_child(g)
	await process_frame
	g.visible = true
	_library(g)
	_rotation(g)
	_collision(g)
	_scoring(g)
	_progression(g)
	_fairness(g)
	_fuzz(g)
	_pause_save(g)
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _library(g: Control) -> void:
	var names: Array = g.SHAPES.keys()
	_check("shape library: %d loads" % names.size(), names.size() >= 16)
	for n in ["ELL", "JAY", "TEE", "ZIG", "ZAG", "ROD4", "ROD5", "LONG_ELL", "EFF", "ENN", "STAIR", "WYE"]:
		_check("has %s" % n, g.SHAPES.has(n))
	var five: int = names.filter(func(n): return Array(g.SHAPES[n][1]).size() == 5).size()
	_check("five-crate (larger / awkward) loads: %d" % five, five >= 8)
	var asym := 0
	for n in names:
		var c: Array = g.SHAPES[n][1]
		var mirrored: Array = c.map(func(v): return Vector2i(Game._extent(c).x - 1 - v.x, v.y))
		if not _same_any_rotation(c, mirrored):
			asym += 1
	_check("asymmetric (chiral) loads: %d" % asym, asym >= 4)


func _norm(c: Array) -> Array:
	var minx: int = c.map(func(v): return v.x).min()
	var miny: int = c.map(func(v): return v.y).min()
	var out: Array = c.map(func(v): return v - Vector2i(minx, miny))
	out.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	return out


func _same_any_rotation(a: Array, b: Array) -> bool:
	var r: Array = b
	for k in 4:
		if _norm(r) == _norm(a):
			return true
		r = Game.rotated(r)
	return false


func _rotation(g: Control) -> void:
	var ok := true
	for n in g.SHAPES:
		var c: Array = g.SHAPES[n][1]
		var r: Array = c
		for k in 4:
			r = Game.rotated(r)
			var e: Vector2i = Game._extent(r)
			ok = ok and e.x <= g.COLS and r.size() == c.size()
		ok = ok and _norm(r) == _norm(c)
	_check("every load: 4 turns return it to itself, every rotation fits the bay", ok)
	g.restart(5)
	g.grid[0].fill(-1)
	g.piece = Array(g.SHAPES["ROD4"][1]).duplicate()
	g.piece_pos = Vector2i(0, 5)
	g.action("rotate")
	_check("turn at the wall works (kick) and stays inside", g.board_valid() and g.piece.map(func(v): return v.x + g.piece_pos.x).min() >= 0)
	g.piece = Array(g.SHAPES["ROD4"][1]).duplicate()
	g.piece_pos = Vector2i(g.COLS - 4, 5)
	g.action("rotate")
	g.action("rotate")
	_check("turns near the right wall stay inside", g.board_valid() and g.piece.map(func(v): return v.x + g.piece_pos.x).max() < g.COLS)


func _collision(g: Control) -> void:
	g.restart(6)
	for i in 20:
		g.action("left")
	var minx: int = g.piece.map(func(v): return v.x + g.piece_pos.x).min()
	_check("left wall stops the load (x %d)" % minx, minx == 0)
	for i in 20:
		g.action("right")
	var maxx: int = g.piece.map(func(v): return v.x + g.piece_pos.x).max()
	_check("right wall stops the load (x %d)" % maxx, maxx == g.COLS - 1)
	var ghost: Vector2i = g.ghost_pos()
	var cells_before: int = _filled(g)
	var shape: Array = g.piece.duplicate()
	g.action("drop")
	_check("hard drop lands exactly at the ghost", _filled(g) == cells_before + shape.size() and shape.all(func(v): return int(g.grid[(v + ghost).y][(v + ghost).x]) != -1))
	_check("NEXT preview names the following load", g.SHAPES.has(g.next_name))


func _filled(g: Control) -> int:
	var n := 0
	for row in g.grid:
		for v in row:
			if int(v) != -1:
				n += 1
	return n


func _scoring(g: Control) -> void:
	g.restart(7)
	for r in [g.ROWS - 1, g.ROWS - 2]:
		for c in g.COLS:
			g.grid[r][c] = 0
		g.grid[r][0] = -1
	g.piece = [Vector2i(0, 0), Vector2i(0, 1)]
	g.piece_pos = Vector2i(0, 0)
	g.score = 0
	g.action("drop")
	_check("two rows shipped at once: 300 x level 1 + drop bonus (score %d)" % g.score, g.lines == 2 and g.score >= 300 and g.score < 360 and g.grid[g.ROWS - 1].all(func(v): return int(v) == -1))
	var s0: int = g.score
	g.action("down")
	_check("soft drop +1", g.score == s0 + 1)


func _progression(g: Control) -> void:
	var l1: Array = Game.unlocked_for_level(1)
	var l6: Array = Game.unlocked_for_level(6)
	_check("level 1 manifest: only simple loads (%d)" % l1.size(), l1.size() == 6 and not l1.has("TEE") and not l1.has("STAIR"))
	_check("level 2 adds tee / zig / zag", Game.unlocked_for_level(2).has("TEE") and Game.unlocked_for_level(2).has("ZAG"))
	_check("level 4 adds five-crate loads, level 6 the awkward ones", Game.unlocked_for_level(4).has("LONG_ELL") and not Game.unlocked_for_level(4).has("STAIR") and l6.has("STAIR") and l6.size() == g.SHAPES.size())
	g.restart(8)
	g.lines = 5
	for c in g.COLS:
		g.grid[g.ROWS - 1][c] = 0
	g.grid[g.ROWS - 1][0] = -1
	g.piece = [Vector2i(0, 0)]
	g.piece_pos = Vector2i(0, 0)
	var f0: float = g.fall_interval()
	g.action("drop")
	_check("6 rows -> level 2, faster fall (%.2f -> %.2f s)" % [f0, g.fall_interval()], g.level == 2 and g.fall_interval() < f0)
	g.restart(9)
	var early: Array = []
	for i in 30:
		early.append(g.piece_name)
		g._spawn()
	_check("early game: never a tier-2/3 load in the first 30", early.all(func(n): return int(g.SHAPES[n][0]) == 0))


func _fairness(g: Control) -> void:
	g.restart(11)
	var seq: Array = []
	for i in 18:
		seq.append(g.piece_name)
		g._spawn()
	var bags_ok := true
	for b in 3:
		var bag: Array = seq.slice(b * 6, b * 6 + 6)
		bag.sort()
		var want: Array = Game.unlocked_for_level(1)
		want.sort()
		bags_ok = bags_ok and bag == want
	_check("manifest bag: every simple load exactly once per bag of 6", bags_ok)
	g.restart(11)
	var seq2: Array = []
	for i in 18:
		seq2.append(g.piece_name)
		g._spawn()
	_check("same seed -> same sequence (deterministic)", seq == seq2)


func _fuzz(g: Control) -> void:
	g.restart(12)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var acts := ["left", "right", "rotate", "down", "drop"]
	var ok := true
	for i in 1500:
		if g.game_over:
			g.restart(rng.randi() % 1000)
		g.action(acts[rng.randi() % acts.size()])
		ok = ok and g.board_valid()
	_check("1500 random actions: the board is never invalid", ok)


func _pause_save(g: Control) -> void:
	g.restart(13)
	g.action("drop")
	g.action("drop")
	g.action("pause")
	_check("pause stops input", g.paused)
	var pos0: Vector2i = g.piece_pos
	g.action("left")
	_check("...moves ignored while paused", g.piece_pos == pos0)
	var snap: Dictionary = g.state_dict()
	var json: Dictionary = JSON.parse_string(JSON.stringify(snap))
	var grid0: Array = g.grid.duplicate(true)
	g.restart(77)
	_check("restored run validates and loads PAUSED", g.load_state(json) and g.paused and g.grid == grid0 and g.piece_name == snap["piece"])
	_check("restored board valid", g.board_valid())
	var bad: Dictionary = json.duplicate(true)
	bad["grid"] = bad["grid"].slice(0, 5)
	var g2: Array = g.grid.duplicate(true)
	_check("corrupt snapshot rejected (board untouched)", not g.load_state(bad) and g.grid == g2)
	var bad2: Dictionary = json.duplicate(true)
	bad2["piece"] = "NOT_A_SHAPE"
	_check("unknown load rejected", not g.load_state(bad2))


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
