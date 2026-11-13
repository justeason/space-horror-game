extends SceneTree
## Round 50: design-bible gaps on the Lower Junction, played end to end on
## real equipment driving the authoritative Deck B models.
##   E12 ELECTRICAL SHORT  a ground fault really trips its Bus B breaker;
##       resetting into it re-trips (counted); terminals are refused while
##       LIVE / not locked out / 0 V unverified; inspect -> repair clears
##       the model fault; restore = unlock, reset, read under load.
##   M06 INTERFERENCE      RPT-B noise from a real source (vent fan motor /
##       grow-light PWM); listening, channel comparison and switching
##       equipment identify it; the fix (or retune) really quiets the link;
##       a report that never reproduces closes "not reproduced".
##   L10 CO2 SPIKE         a CO2 model (technician, exercise, plants,
##       CDRA-B scrubber, VF-B2 airflow); the three causes (scrubber /
##       sensor / airflow) are told apart by comparing CS-B with the
##       scrubber inlet and closed with the matching outcome; an E12 short
##       on B3 starves the scrubber (cross-system chain).
const L = preload("res://scripts/deck_b/deck_b_layout.gd")
var _ok := true
var main: Node
var dp: Node
var s: Node
var lj: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	main.get_node("StationAI").set_enabled(false)
	dp = main.get_node("DayPlan")
	s = main.get_node("DeckB/DeckBSystems")
	lj = main.get_node("DeckB/Rooms/LowerJunction")
	var clr: Node = main.get_node("DayPlan/Clearance")
	clr.load_dict({"level": 3})
	clr.dev_set_deck_b(4)
	await _e12()
	await _m06()
	await _l10()
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _order(t: StringName) -> Dictionary:
	for i in range(dp.orders.size() - 1, -1, -1):
		if StringName(dp.orders[i]["type"]) == t:
			return dp.orders[i]
	return {}


func _wait_closed(t: StringName, max_s: float = 3.0) -> Dictionary:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(max_s * 1000.0):
		await process_frame
		if String(_order(t).get("status", "")) == "done":
			break
	return _order(t)


func _click(id: String) -> void:
	lj.on_part(StringName(id))


func _e12() -> void:
	var o: Dictionary = dp.raise_order(&"e12_short", "test")
	var c: int = lj.sc_circuit
	_check("E12 raised: a REAL ground fault on %s trips its breaker" % ("B%d" % (c + 1)), not o.is_empty() and c >= 2 and int(s.power["short"]) == c and not s.power["on"][c])
	_check("...and the scrubber/plants on B3 really lose power when it is B3", c != 2 or not s.powered(2))
	_click("ldp_cover")
	lj.sel = c
	lj._read()
	_check("LDP-B meter identifies it: '%s'" % lj._meter_text().replace("\n", " · "), lj._meter_text().find("GROUND FAULT") != -1)
	_click("brk%d" % c)
	await process_frame
	_check("resetting into the fault re-trips at once (counted)", not s.power["on"][c] and lj.sc_reset_into_fault == 1)
	_click("tb_cover")
	_click("term0")
	_check("a LIVE circuit's terminal is refused (B1 on)", s.power["on"][0] and not lj.sc_inspected[0])
	_click("term%d" % c)
	_check("off but NOT locked out: refused", not lj.sc_found)
	_click("lock%d" % c)
	_check("lockout tag applied (visible)", s.power["lockout"][c] and lj._lock_tags[c].visible if lj._lock_tags.size() > c else s.power["lockout"][c])
	_click("term%d" % c)
	_check("0 V not verified yet: refused", not lj.sc_found)
	lj.sc_proved = false               # (opening the cover auto-read live B1)
	lj.sel = c
	lj._read()
	_check("LIVE-DEAD-LIVE: a dead reading with an unproven meter does NOT count", not lj.sc_zero)
	lj.sel = 0
	lj._read()
	_check("meter proven on a live circuit (B1)", lj.sc_proved)
	lj.sel = c
	lj._read()
	_check("meter: '%s' -> 0 V verified" % lj._meter_text().replace("\n", " · "), lj.sc_zero and lj._meter_text().find("LOCKED OUT") != -1)
	_click("brk%d" % c)
	_check("a locked-out breaker cannot be reset", not s.power["on"][c])
	_click("term%d" % c)
	_check("inspection finds the cause (%s)" % lj.sc_cause, lj.sc_found and not lj.sc_fixed)
	_click("term%d" % c)
	_click("term%d" % c)
	_check("repair clears the model's ground fault", lj.sc_fixed and int(s.power["short"]) == -1)
	var st: String = JSON.stringify(lj.state_dict())
	lj.load_dict(JSON.parse_string(st))
	_check("mid-procedure state survives a save/load round trip", JSON.stringify(lj.state_dict()) == st)
	_click("lock%d" % c)
	_check("lockout stays while TB-B is open", s.power["lockout"][c])
	_click("tb_cover")
	_click("lock%d" % c)
	_click("brk%d" % c)
	await process_frame
	_check("unlocked + reset: %s holds" % ("B%d" % (c + 1)), s.power["on"][c] and s.powered(c))
	lj.sel = c
	lj._read()
	_click("ldp_cover")
	var od: Dictionary = await _wait_closed(&"e12_short")
	_check("E12 closed '%s'; record: '%s'" % [od.get("outcome", ""), String(s.service_log.back().get("action", "")).left(70)], String(od.get("status", "")) == "done" and String(od.get("outcome", "")) == "repaired" and String(s.service_log.back().get("action", "")).find("1 reset into the fault") != -1)


func _m06() -> void:
	# ---- Source: the vent fan motor (loose suppression capacitor).
	dp.raise_order(&"m06_interference", "test")
	lj.rf_source = "vent"
	lj.rf_cap_ok = false
	lj.vent_on = true
	s.air["vent_switch"] = true
	_click("rpt_listen")
	_check("M06: the headset needs the access door open", lj.rf_log.is_empty())
	_click("rpt_door")
	_click("rpt_listen")
	_check("CH B: %s (%.0f dB)" % [lj._rf_pattern(1), float(lj.rf_log.back()[1])], float(lj.rf_log.back()[1]) > -70.0 and lj._rf_pattern(1).begins_with("steady"))
	_check("the capacitor signature is UNSTABLE (crackle bursts) — not the fan's rhythm", lj._rf_pattern(1).find("irregular") != -1)
	lj._refresh()
	_check("the link really degrades (LOW)", lj._rpt_bars.text.find("LOW") != -1)
	_click("fan_switch")
	await process_frame
	_click("rpt_listen")
	_check("fan OFF -> the buzz is gone on the same channel (compared)", lj._rf_compared())
	_click("rpt_door")
	await process_frame
	_check("cannot close with the vent simply left off", String(_order(&"m06_interference")["status"]) == "open")
	_click("fan_switch")
	_click("fan_cap")
	_check("terminal cover refused while the fan runs", not lj.rf_cap_ok)
	_click("fan_switch")
	_click("fan_cap")
	_click("fan_switch")
	await process_frame
	_check("capacitor reseated, fan back on, CH B clean (%.0f dB)" % lj._rf_noise(1), lj.rf_cap_ok and lj.vent_on and lj._rf_noise(1) < -90.0)
	var od: Dictionary = await _wait_closed(&"m06_interference")
	_check("closed '%s' (source removed)" % od.get("outcome", ""), String(od.get("outcome", "")) == "repaired")
	# ---- Source: grow-light PWM (dimmed banks); fixed by retuning to CH A.
	dp.raise_order(&"m06_interference", "test")
	lj.rf_source = "pwm"
	lj.rf_cap_ok = true
	s.hydro["light"] = [0.6, 0.6, 0.6]
	_click("rpt_door")
	_click("rpt_listen")
	_check("PWM: '%s' on CH B" % lj._rf_pattern(1), lj._rf_pattern(1).begins_with("pulsed"))
	s.hydro["light"] = [1.0, 1.0, 1.0]
	_click("rpt_listen")
	_check("banks at full (no PWM) -> clean: the pattern follows the grow lights", lj._rf_compared())
	s.hydro["light"] = [0.6, 0.6, 0.6]
	_click("rpt_tune")
	_click("rpt_tune")
	_click("rpt_listen")
	_check("CH A compared: clean (%.0f dB)" % lj._rf_noise(0), lj.rf_tune == 0 and lj._rf_noise(0) < -90.0)
	_click("rpt_set")
	_click("rpt_door")
	od = await _wait_closed(&"m06_interference")
	_check("closed '%s': %s" % [od.get("outcome", ""), String(s.service_log.back().get("action", ""))], String(od.get("outcome", "")) == "repaired" and String(s.service_log.back().get("action", "")).find("CH A") != -1)
	# ---- Source: the vent fan housing's loose bonding strap (rhythmic).
	dp.raise_order(&"m06_interference", "test")
	lj.rf_source = "fan"
	lj.rf_bond_ok = false
	lj.rf_cap_ok = true
	_click("rpt_door")
	lj.rf_tune = 0
	_click("rpt_listen")
	_check("FAN: '%s' on CH A only (%.0f dB; CH B %.0f dB)" % [lj._rf_pattern(0), lj._rf_noise(0), lj._rf_noise(1)], lj._rf_pattern(0).begins_with("rhythmic") and lj._rf_noise(0) > -75.0 and lj._rf_noise(1) < -90.0)
	_click("fan_switch")
	_click("fan_bond")
	_click("fan_switch")
	await process_frame
	_click("rpt_listen")
	_check("bonding strap refitted (fan off to work on it), fan back ON, CH A clean", lj.rf_bond_ok and lj.vent_on and lj._rf_noise(0) < -90.0 and lj._rf_compared())
	_click("rpt_door")
	od = await _wait_closed(&"m06_interference")
	_check("closed '%s': %s" % [od.get("outcome", ""), String(s.service_log.back().get("fault", ""))], String(od.get("outcome", "")) == "repaired" and String(s.service_log.back().get("fault", "")).find("bonding") != -1)
	# ---- PWM: switching the grow lights OFF is not a fix.
	dp.raise_order(&"m06_interference", "test")
	lj.rf_source = "pwm"
	lj.rf_bond_ok = true
	s.hydro["light"] = [0.6, 0.6, 0.6]
	_click("rpt_door")
	lj.rf_tune = 1
	_click("rpt_listen")
	s.hydro["light"] = [0.0, 0.0, 0.0]
	_click("rpt_listen")
	_click("rpt_door")
	await process_frame
	await process_frame
	_check("grow lights simply switched OFF: the order stays OPEN", String(_order(&"m06_interference")["status"]) == "open")
	s.hydro["light"] = [1.0, 1.0, 1.0]
	await process_frame
	od = await _wait_closed(&"m06_interference")
	_check("banks at full (out of the PWM range, plants still lit) -> '%s'" % od.get("outcome", ""), String(od.get("outcome", "")) == "repaired")
	# ---- The three headset signatures are technically distinct.
	var sig := {}
	for k in ["hum", "fan", "pwm"]:
		sig[k] = _signature(lj.rf_stream(k))
	_check("audio: hum has a strong 96 Hz line (%.2f) the others lack (fan %.2f, pwm %.2f)" % [sig["hum"]["c96"], sig["fan"]["c96"], sig["pwm"]["c96"]], sig["hum"]["c96"] > 3.0 * maxf(sig["fan"]["c96"], sig["pwm"]["c96"]))
	_check("audio: fan's loudness envelope is periodic at 24 Hz (%.2f) — hum / pwm not (%.2f / %.2f)" % [sig["fan"]["env24"], sig["hum"]["env24"], sig["pwm"]["env24"]], sig["fan"]["env24"] > 2.0 * maxf(sig["hum"]["env24"], sig["pwm"]["env24"]))
	_check("audio: pwm is a 120 Hz click comb (%.2f)" % sig["pwm"]["env120"], sig["pwm"]["env120"] > 2.0 * maxf(sig["hum"]["env120"], sig["fan"]["env120"]))
	_check("audio: every signature peaks below 0.6 full scale (hum %.2f, fan %.2f, pwm %.2f)" % [sig["hum"]["peak"], sig["fan"]["peak"], sig["pwm"]["peak"]], sig["hum"]["peak"] < 0.6 and sig["fan"]["peak"] < 0.6 and sig["pwm"]["peak"] < 0.6)
	# ---- Not reproduced.
	dp.raise_order(&"m06_interference", "test")
	lj.rf_source = ""
	_click("rpt_door")
	for k in 3:
		_click("rpt_listen")
		_click("rpt_tune")
	_click("rpt_door")
	od = await _wait_closed(&"m06_interference")
	_check("nothing on any channel -> '%s'" % od.get("outcome", ""), String(od.get("outcome", "")) == "not_reproduced")


## Technical audio signature of a loop: correlation with a 96 Hz sine,
## the 24 Hz / 120 Hz periodicity of the loudness envelope, the peak.
func _signature(st: AudioStreamWAV) -> Dictionary:
	var data: PackedByteArray = st.data
	var n: int = mini(data.size() / 2, 22050)
	var sr: float = float(st.mix_rate)
	var x := PackedFloat32Array()
	x.resize(n)
	var peak := 0.0
	for i in n:
		var v: int = data.decode_s16(i * 2)
		x[i] = float(v) / 32768.0
		peak = maxf(peak, absf(x[i]))
	var c := 0.0
	var ss := 0.0
	for i in n:
		c += x[i] * sin(TAU * 96.0 * i / sr)
		ss += x[i] * cos(TAU * 96.0 * i / sr)
	var env := func(f: float) -> float:
		var a := 0.0
		var b := 0.0
		var m := 0.0
		for i in n:
			var e: float = x[i] * x[i]
			m += e
			a += e * sin(TAU * f * i / sr)
			b += e * cos(TAU * f * i / sr)
		return sqrt(a * a + b * b) / maxf(m, 0.000001)
	return {"c96": sqrt(c * c + ss * ss) / n * 100.0, "env24": env.call(24.0), "env120": env.call(120.0), "peak": peak}


func _l10() -> void:
	# The model: equilibrium, exercise, plants.
	s.hydro["light"] = [0.0, 0.0, 0.0]
	var eq0: float = s.co2_equilibrium(s.co2_production())
	var med: Node = main.get_node("DeckB/Rooms/MedicalBay")
	med.exercising = true
	var p_ex: float = s.co2_production()
	med.exercising = false
	s.hydro["light"] = [1.0, 1.0, 1.0]
	var p_lit: float = s.co2_production()
	_check("L10 model: nominal equilibrium %.0f ppm (< caution); exercise raises production (%.1f -> %.1f ppm/s); lit trays lower it (%.1f)" % [eq0, s.CO2_BASE, p_ex, p_lit], eq0 < 4200.0 and p_ex > s.CO2_BASE and p_lit < s.CO2_BASE)
	# Cross-system chain: a B3 ground fault starves the scrubber.
	s.inject_short(2, "terminal")
	s.step(0.01)
	_check("B3 ground fault -> CDRA-B unpowered -> cause 'power'", s.air_fault() == "power")
	var c0: float = float(s.air["co2"])
	for i in 400: s.step(0.25)
	_check("...and CO2 really climbs (%.0f -> %.0f ppm)" % [c0, float(s.air["co2"])], float(s.air["co2"]) > c0 + 500.0)
	s.clear_short()
	s.power["on"][2] = true
	s.air["co2"] = 2600.0
	# ---- Cause: SENSOR (CS-B drift; the true air is fine).
	s.inject_air_fault("sensor")
	dp.raise_order(&"l10_co2", "test")
	_check("sensor case raised: CS-B %.0f ppm vs true %.0f" % [s.co2_reading(), float(s.air["co2"])], lj.co2_cause == "sensor" and s.co2_reading() > s.CO2_CAUTION)
	_click("csb_read")
	_click("csb_cal")
	_check("calibration refused before comparing with the scrubber inlet", float(s.air["sensor_bias"]) > 500.0)
	_click("cdra_read")
	_click("csb_cal")
	_click("csb_cal")
	_check("zero + span: CS-B agrees with the inlet", float(s.air["sensor_bias"]) == 0.0)
	var od: Dictionary = await _wait_closed(&"l10_co2")
	_check("closed '%s'" % od.get("outcome", ""), String(od.get("outcome", "")) == "sensor_fault")
	# ---- Cause: SCRUBBER (bed saturated, auto-cycle valve stuck).
	s.inject_air_fault("bed")
	s.air["co2"] = 5700.0
	dp.raise_order(&"l10_co2", "test")
	_click("csb_read")
	_click("cdra_valve")
	_check("valve refused before reading the CDRA-B panel", s.air["swap_stuck"])
	_click("cdra_read")
	_check("CDRA-B shows the stuck auto-cycle: '%s'" % lj._cdra_text().replace("\n", " · "), lj._cdra_text().find("AUTO-CYCLE FAULT") != -1)
	var old_bed: int = int(s.air["active"])
	_click("cdra_valve")
	await process_frame
	for i in 80: s.step(0.25)
	od = await _wait_closed(&"l10_co2")
	_check("beds swapped, CO2 falling (%.0f ppm) -> closed '%s'" % [s.co2_reading(), od.get("outcome", "")], int(s.air["active"]) != old_bed and String(od.get("outcome", "")) == "repaired")
	for i in 200: s.step(0.25)
	_check("the saturated bed regenerates to 100 %", float(s.air["beds"][old_bed]) >= 0.99)
	# ---- Cause: AIRFLOW (VF-B2 thermal cutout).
	s.inject_air_fault("airflow")
	s.air["co2"] = 5700.0
	dp.raise_order(&"l10_co2", "test")
	_click("csb_read")
	_click("cdra_read")
	_check("CDRA-B shows AIRFLOW LOW", lj._cdra_text().find("AIRFLOW LOW") != -1)
	_click("fan_reset")
	_check("cutout reset refused while the switch is ON", s.air["fan_cutout"])
	_click("fan_switch")
	_click("fan_reset")
	_click("fan_switch")
	await process_frame
	for i in 80: s.step(0.25)
	od = await _wait_closed(&"l10_co2")
	_check("airflow restored -> closed '%s' (%s)" % [od.get("outcome", ""), String(s.service_log.back().get("fault", ""))], String(od.get("outcome", "")) == "repaired" and String(s.service_log.back().get("fault", "")).find("thermal cutout") != -1)
	# Round 50 audit: once the cause is fixed the CO2 is still above the
	# caution line for a while -- that recovery must not raise a fresh order.
	s.air["co2"] = maxf(float(s.air["co2"]), 5600.0)
	for i in 6:
		s._check_faults()
	_check("recovering after a real fix: no fresh L10 order while CO2 settles (%.0f ppm)" % s.co2_reading(), not dp.has_open_order(&"l10_co2") and bool(s.air["recovering"]))
	s.inject_air_fault("airflow")
	s._check_faults()
	_check("...but a NEW fault ends the recovery and raises L10 again", dp.has_open_order(&"l10_co2"))
	s.air["fan_cutout"] = false
	lj.task_rearm(&"l10_co2", 0)
	for o2 in dp.orders:
		if o2["type"] == "l10_co2" and o2["status"] == "open":
			o2["status"] = "done"
	# The daily roll can raise these faults by itself (deterministic).
	var seen := {}
	for d in range(10, 400):
		var roll: int = absi(hash([d, "deckb_fault"])) % 100
		if roll >= 10 and roll < 13: seen["short"] = true
		if roll >= 13 and roll < 17: seen["air"] = true
	_check("the daily fault roll reaches both new faults", seen.has("short") and seen.has("air"))


func _check(label: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + label)
	if not cond:
		_ok = false
