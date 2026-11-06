extends RefCounted
## Round 32: one place that names every spare type for the player
## (work orders, workstation room info, wristwatch, panel feedback).

const SHORT := {&"wire_control_16ga": "16GA", &"wire_signal_22ga": "22GA SIG", &"filter_cartridge": "FILTER"}


static func display(id: StringName, color_name: String = "") -> String:
	match id:
		&"wire_signal_22ga":
			return "Signal Cable (22-gauge shielded)"
		&"filter_cartridge":
			return "Filter Cartridge L02"
		_:
			return "Control Wire (16-gauge, %s)" % color_name.to_lower() if color_name != "" else "Control Wire (16-gauge)"


static func short(id: StringName) -> String:
	return SHORT.get(id, "PART")
