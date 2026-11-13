extends RefCounted
## Round 49: the Deck B WORK-ORDER REGISTRY (and the Round 49 design-bible
## gap tasks). DayPlan merges these into its own order schedule (one
## scheduler, one order list): DayPlan.ORDER_TYPES-shaped entries plus
##   room      the Deck B room (map / workstation duty room)
##   tier      Deck B access tier needed (clearance.deck_b_tier()); 0 = a
##             Deck A task gated by the ordinary clearance LEVEL `level`
##   family    proficiency family credited on close
##   freq      routine (scheduled now and then) | occasional (rarer) |
##             fault (raised only when the authoritative model has a real
##             fault) | story (raised only by a story beat)
##   cooldown  minimum days between two scheduled orders of this type
##   design    the GAME_DESIGN.md task id it implements, if any
## A type is only listed here once its procedure is PLAYABLE end to end.

const TYPES := {
	# B-01 Lower Junction
	&"b01_lights": {"tag": "EM LIGHT B", "title": "Lower deck emergency lighting test", "room": &"b01", "tier": 1, "family": "electrical", "category": "B", "weight": 2, "priority": 1, "freq": "routine", "cooldown": 6},
	&"b01_utility": {"tag": "BUS B", "title": "Utility distribution verification (Bus B)", "room": &"b01", "tier": 1, "family": "electrical", "category": "B", "weight": 2, "priority": 2, "freq": "routine", "cooldown": 4},
	&"b01_repeater": {"tag": "REPEATER", "title": "Lower deck comms repeater inspection", "room": &"b01", "tier": 1, "family": "communications", "category": "A", "weight": 1, "priority": 1, "freq": "occasional", "cooldown": 8},
	# Round 50: design-bible gaps on the lower junction.
	&"e12_short": {"tag": "SHORT", "title": "Electrical short: Bus B circuit", "room": &"b01", "tier": 1, "family": "electrical", "category": "C", "weight": 3, "priority": 3, "freq": "fault", "cooldown": 5, "design": "E12"},
	&"m06_interference": {"tag": "RF NOISE", "title": "Interference investigation (RPT-B link)", "room": &"b01", "tier": 1, "family": "communications", "category": "C", "weight": 3, "priority": 1, "freq": "occasional", "cooldown": 9, "design": "M06"},
	&"l09_pressure": {"tag": "PRESSURE", "title": "Pressure loss: find, isolate and repair", "room": &"b01", "tier": 1, "family": "life_support", "category": "D", "weight": 3, "priority": 3, "freq": "fault", "cooldown": 5, "design": "L09"},
	&"l10_co2": {"tag": "CO2", "title": "CO2 rise investigation (lower deck air)", "room": &"b01", "tier": 1, "family": "life_support", "category": "C", "weight": 3, "priority": 3, "freq": "fault", "cooldown": 4, "design": "L10"},
	# Round 50: the airlock / hull design-bible gaps (Deck A equipment,
	# gated like every lower-deck job: Deck B tier 1 = Chapter Two).
	&"a01_suit": {"tag": "SUIT CHECK", "title": "EVA suit inspection (A-1)", "room": &"airlock", "tier": 1, "family": "mechanical", "category": "B", "weight": 2, "priority": 2, "freq": "occasional", "cooldown": 7, "design": "A01"},
	&"a06_hull": {"tag": "HULL", "title": "Hull damage: assess and repair", "room": &"airlock", "tier": 1, "family": "mechanical", "category": "D", "weight": 3, "priority": 2, "freq": "fault", "cooldown": 3, "design": "A06"},
	# B-02 Water Recovery
	&"b02_filter": {"tag": "WATER FLT", "title": "Water recovery: filter bed service", "room": &"b02", "tier": 1, "family": "life_support", "category": "C", "weight": 3, "priority": 2, "freq": "fault", "cooldown": 3},
	&"b02_sample": {"tag": "WATER QA", "title": "Water quality sample", "room": &"b02", "tier": 1, "family": "life_support", "category": "B", "weight": 2, "priority": 1, "freq": "routine", "cooldown": 3},
	&"b02_pump": {"tag": "WATER PMP", "title": "Water pump diagnosis", "room": &"b02", "tier": 1, "family": "mechanical", "category": "C", "weight": 3, "priority": 2, "freq": "occasional", "cooldown": 6, "design": "L08"},
	&"b02_flow": {"tag": "LOW FLOW", "title": "Water flow restoration", "room": &"b02", "tier": 1, "family": "life_support", "category": "B", "weight": 2, "priority": 2, "freq": "occasional", "cooldown": 5},
	&"b02_tank": {"tag": "TANKS", "title": "Water storage tank inspection", "room": &"b02", "tier": 1, "family": "life_support", "category": "A", "weight": 1, "priority": 1, "freq": "routine", "cooldown": 5},
	# B-03 Thermal Control
	&"b03_inspect": {"tag": "COOLANT", "title": "Cooling loop inspection", "room": &"b03", "tier": 1, "family": "mechanical", "category": "B", "weight": 2, "priority": 1, "freq": "routine", "cooldown": 4, "design": "E08"},
	&"b03_balance": {"tag": "BALANCE", "title": "Coolant flow balancing", "room": &"b03", "tier": 1, "family": "mechanical", "category": "B", "weight": 2, "priority": 2, "freq": "occasional", "cooldown": 5},
	&"b03_pump": {"tag": "PUMP SND", "title": "Coolant pump sound diagnosis", "room": &"b03", "tier": 1, "family": "mechanical", "category": "C", "weight": 3, "priority": 2, "freq": "occasional", "cooldown": 7},
	&"b03_radiator": {"tag": "RADIATOR", "title": "Radiator fault trace", "room": &"b03", "tier": 1, "family": "mechanical", "category": "C", "weight": 3, "priority": 2, "freq": "occasional", "cooldown": 8},
	&"b03_overheat": {"tag": "OVERHEAT", "title": "Overheat stabilisation (coolant loop)", "room": &"b03", "tier": 1, "family": "mechanical", "category": "C", "weight": 3, "priority": 3, "freq": "fault", "cooldown": 6, "design": "E11"},
	# B-04 Workshop
	&"b04_bench": {"tag": "BENCH", "title": "Component bench test", "room": &"b04", "tier": 2, "family": "electrical", "category": "B", "weight": 2, "priority": 1, "freq": "routine", "cooldown": 4},
	&"b04_reassembly": {"tag": "ASSEMBLY", "title": "Precision reassembly: valve actuator", "room": &"b04", "tier": 2, "family": "mechanical", "category": "C", "weight": 3, "priority": 1, "freq": "occasional", "cooldown": 6},
	&"b04_torque": {"tag": "TORQUE", "title": "Torque verification: mounting plate", "room": &"b04", "tier": 2, "family": "mechanical", "category": "B", "weight": 2, "priority": 1, "freq": "occasional", "cooldown": 5},
	&"b04_fab": {"tag": "FAB CAL", "title": "Fabricator calibration and test part", "room": &"b04", "tier": 2, "family": "mechanical", "category": "B", "weight": 2, "priority": 1, "freq": "occasional", "cooldown": 7},
	&"b04_tools": {"tag": "TOOLS", "title": "Workshop tool inspection", "room": &"b04", "tier": 2, "family": "mechanical", "category": "A", "weight": 1, "priority": 1, "freq": "routine", "cooldown": 7},
	&"b04_recondition": {"tag": "RECOND", "title": "Recondition a damaged component", "room": &"b04", "tier": 2, "family": "mechanical", "category": "C", "weight": 3, "priority": 2, "freq": "fault", "cooldown": 3},
	# B-05 Payload Laboratory
	&"b05_seal": {"tag": "GLOVEBOX", "title": "Glovebox seal test", "room": &"b05", "tier": 3, "family": "life_support", "category": "B", "weight": 2, "priority": 1, "freq": "routine", "cooldown": 6},
	&"b05_transfer": {"tag": "SAMPLE TX", "title": "Sample transfer into the glovebox", "room": &"b05", "tier": 3, "family": "life_support", "category": "B", "weight": 2, "priority": 1, "freq": "occasional", "cooldown": 5},
	&"b05_optics": {"tag": "OPTICS", "title": "Optical bench calibration", "room": &"b05", "tier": 3, "family": "electrical", "category": "B", "weight": 2, "priority": 1, "freq": "occasional", "cooldown": 6},
	&"b05_incubator": {"tag": "INCUBATOR", "title": "Instrument temperature check (incubator drift)", "room": &"b05", "tier": 3, "family": "mechanical", "category": "D", "weight": 3, "priority": 2, "freq": "occasional", "cooldown": 7},
	&"b05_specimen": {"tag": "SPECIMEN", "title": "Specimen documentation", "room": &"b05", "tier": 3, "family": "life_support", "category": "B", "weight": 2, "priority": 1, "freq": "routine", "cooldown": 4},
	&"b05_power": {"tag": "PAYLOAD PWR", "title": "Payload power verification (reroute Bus B)", "room": &"b05", "tier": 3, "family": "electrical", "category": "D", "weight": 3, "priority": 2, "freq": "fault", "cooldown": 6, "design": "E10"},
	# B-06 Hydroponics
	&"b06_lights": {"tag": "GROW LT", "title": "Grow-light inspection", "room": &"b06", "tier": 3, "family": "electrical", "category": "B", "weight": 2, "priority": 1, "freq": "occasional", "cooldown": 6},
	&"b06_nutrient": {"tag": "NUTRIENT", "title": "Nutrient solution sample", "room": &"b06", "tier": 3, "family": "life_support", "category": "B", "weight": 2, "priority": 1, "freq": "routine", "cooldown": 4},
	&"b06_irrigation": {"tag": "IRRIGATE", "title": "Irrigation diagnosis", "room": &"b06", "tier": 3, "family": "life_support", "category": "C", "weight": 3, "priority": 2, "freq": "occasional", "cooldown": 6},
	&"b06_clean": {"tag": "TRAYS", "title": "Growth tray cleaning", "room": &"b06", "tier": 3, "family": "life_support", "category": "A", "weight": 1, "priority": 1, "freq": "occasional", "cooldown": 7},
	&"b06_observe": {"tag": "PLANTS", "title": "Plant health observation", "room": &"b06", "tier": 3, "family": "life_support", "category": "A", "weight": 1, "priority": 1, "freq": "routine", "cooldown": 5},
	# B-07 Medical / Exercise
	&"b07_health": {"tag": "HEALTH", "title": "Health monitor check", "room": &"b07", "tier": 3, "family": "life_support", "category": "A", "weight": 1, "priority": 1, "freq": "routine", "cooldown": 6},
	&"b07_dosimeter": {"tag": "DOSIMETER", "title": "Radiation dosimeter read", "room": &"b07", "tier": 3, "family": "life_support", "category": "A", "weight": 1, "priority": 1, "freq": "routine", "cooldown": 7},
	&"b07_supplies": {"tag": "MED SUPPLY", "title": "Medical supply inspection", "room": &"b07", "tier": 3, "family": "life_support", "category": "B", "weight": 2, "priority": 1, "freq": "occasional", "cooldown": 9},
	&"b07_ergo": {"tag": "ERGOMETER", "title": "Exercise equipment calibration", "room": &"b07", "tier": 3, "family": "mechanical", "category": "B", "weight": 2, "priority": 1, "freq": "occasional", "cooldown": 9},
	&"b07_kit": {"tag": "FIRST AID", "title": "Emergency kit inventory", "room": &"b07", "tier": 3, "family": "life_support", "category": "B", "weight": 2, "priority": 1, "freq": "occasional", "cooldown": 10},
	# B-08 Cargo / Docking Support
	&"b08_manifest": {"tag": "MANIFEST", "title": "Shipment manifest inspection", "room": &"b08", "tier": 2, "family": "mechanical", "category": "C", "weight": 3, "priority": 1, "freq": "fault", "cooldown": 1},
	&"b08_restraint": {"tag": "RESTRAINT", "title": "Cargo restraint check", "room": &"b08", "tier": 2, "family": "mechanical", "category": "B", "weight": 2, "priority": 1, "freq": "routine", "cooldown": 5},
	&"b08_discrepancy": {"tag": "DISCREP", "title": "Shipment discrepancy", "room": &"b08", "tier": 2, "family": "mechanical", "category": "B", "weight": 2, "priority": 2, "freq": "fault", "cooldown": 1, "design": "S03"},
	&"b08_seal": {"tag": "BERTH SEAL", "title": "Docking seal verification", "room": &"b08", "tier": 2, "family": "mechanical", "category": "B", "weight": 2, "priority": 1, "freq": "occasional", "cooldown": 7},
	&"b08_transfer": {"tag": "TRANSFER", "title": "Component transfer to destinations", "room": &"b08", "tier": 2, "family": "mechanical", "category": "D", "weight": 3, "priority": 1, "freq": "fault", "cooldown": 1},
	&"b08_damaged": {"tag": "DAMAGED", "title": "Damaged container inspection", "room": &"b08", "tier": 2, "family": "mechanical", "category": "B", "weight": 2, "priority": 2, "freq": "fault", "cooldown": 1},
	# B-09 Data Archive
	&"b09_racks": {"tag": "RACKS", "title": "Data rack inspection", "room": &"b09", "tier": 4, "family": "communications", "category": "A", "weight": 1, "priority": 1, "freq": "routine", "cooldown": 6},
	&"b09_cartridge": {"tag": "CARTRIDGE", "title": "Archive cartridge replacement", "room": &"b09", "tier": 4, "family": "communications", "category": "C", "weight": 3, "priority": 2, "freq": "occasional", "cooldown": 7},
	&"b09_backup": {"tag": "BACKUP", "title": "Backup verification", "room": &"b09", "tier": 4, "family": "communications", "category": "B", "weight": 2, "priority": 1, "freq": "routine", "cooldown": 5},
	&"b09_correlate": {"tag": "RECORDS", "title": "Historical record correlation", "room": &"b09", "tier": 4, "family": "communications", "category": "B", "weight": 2, "priority": 1, "freq": "occasional", "cooldown": 6, "design": "C07"},
	&"b09_fans": {"tag": "ARCH FAN", "title": "Archive cooling fan service", "room": &"b09", "tier": 4, "family": "mechanical", "category": "B", "weight": 2, "priority": 1, "freq": "occasional", "cooldown": 8},
	&"b09_unknown": {"tag": "UNKNOWN", "title": "Unknown archive entry investigation", "room": &"b09", "tier": 4, "family": "communications", "category": "B", "weight": 2, "priority": 1, "freq": "story", "cooldown": 99},
	# Round 49 design-bible gaps on the shared systems.
	&"e11_battery": {"tag": "BATT TEMP", "title": "Battery overheating", "room": &"engineering", "tier": 1, "family": "electrical", "category": "C", "weight": 3, "priority": 3, "freq": "fault", "cooldown": 4, "design": "E11"},
	&"l06_condensation": {"tag": "CONDENSE", "title": "Condensation investigation (service spine)", "room": &"b01", "tier": 1, "family": "life_support", "category": "B", "weight": 2, "priority": 1, "freq": "occasional", "cooldown": 8, "design": "L06"},
}

## Every task the round's brief names, with its status (the coverage
## matrix reads this; nothing here is scheduled).
const PLANNED := {
	&"b02_sample_reprocess": "covered inside b02_sample (reprocess on FAIL)",
}


static func is_deck_b(t: StringName) -> bool:
	return TYPES.has(t)


static func entry(t: StringName) -> Dictionary:
	return TYPES.get(t, {})


static func room_of(t: StringName) -> StringName:
	return StringName(TYPES.get(t, {}).get("room", &""))
