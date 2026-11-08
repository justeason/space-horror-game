extends RefCounted
## Round 36: shared TEST helper (not a test itself). Performs a complete
## filter-housing service through the station's own public mechanical calls,
## whatever service VARIANT is armed (loose / seized latch, cocked
## cartridge, different replacement start rotation). The caller must already
## be carrying the clean cartridge. Returns the number of actions used, or
## -1 if the procedure did not complete within a sane bound.

static func solve(station: Node) -> int:
	var S = station.Stage
	var actions := 0
	if station.stage() == S.ISOLATE:
		station.toggle_isolate()
		actions += 1
	var guard := 0
	while station.stage() == S.OPEN_LATCHES and guard < 12:
		for idx in [1, 2]:
			if not station.latch_open(idx):
				station.toggle_latch(idx)
				actions += 1
		guard += 1
	guard = 0
	while station.stage() == S.REMOVE_OLD and guard < 10:
		var r: Dictionary = station.remove_old_cartridge()
		actions += 1
		if not r.get("turned", false) and not r.get("removed", false):
			return -1   # missing part
		guard += 1
	guard = 0
	while station.stage() == S.ALIGN_INSERT and guard < 10:
		var diff: float = absf(wrapf(station.cartridge_angle_deg() - station.target_angle_deg(), -180.0, 180.0))
		if diff <= station.tolerance_deg():
			station.attempt_insert()
		else:
			station.rotate_cartridge(1)
		actions += 1
		guard += 1
	guard = 0
	while station.stage() == S.CLOSE_LATCHES and guard < 6:
		for idx in [1, 2]:
			if station.latch_open(idx):
				station.toggle_latch(idx)
				actions += 1
		guard += 1
	if station.stage() == S.RESTORE:
		station.toggle_isolate()
		actions += 1
	return actions if station.stage() == S.COMPLETE else -1
