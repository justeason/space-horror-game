extends Node
## Round 42 Priority 34: the ORBITAL LIGHTING CYCLE.
## The station circles the planet: a long sunlit pass, then the planet's
## shadow (eclipse), then sunrise. One authoritative orbit clock (saved, so
## a load never re-randomises the sunlight) drives:
##   - the exterior SUN (exterior_builder.gd's DirectionalLight3D, which
##     lights only the exterior layer): its direction drifts slowly across
##     the sunlit pass and its energy fades through a short penumbra into
##     darkness and back -- seen identically through the observation port
##     and on every exterior camera (one light, one world: the horror
##     window/camera contradiction stays a deliberate event, never a
##     lighting mismatch);
##   - SOLAR GENERATION (solar_arrays.gd multiplies sun_factor()): the
##     battery reserve carries the station through the eclipse (no
##     blackout; the interior lights stay on the normal circuits) and
##     recharges in sunlight.
## Timing is compressed for play (ORBIT_S real seconds per orbit).

const ORBIT_S := 360.0
const ECLIPSE_S := 70.0
const PENUMBRA_S := 12.0
const SUN_ENERGY := 1.6

## The orbit is DERIVED from the station clock (each shift starts at
## sunrise; DayPlan shift time, which
## is itself saved) plus a constant `offset_s` (saved; set by tools / the
## developer layer). So a load reproduces the same sunlight exactly and the
## saved orbit state never drifts frame to frame.
var phase_s: float = 0.0          # 0 = just after sunrise
var offset_s: float = 0.0
var _sun: DirectionalLight3D


func _ready() -> void:
	add_to_group(&"orbital_cycle")
	add_to_group(&"r35_equipment")


func _find_sun() -> DirectionalLight3D:
	if _sun == null or not is_instance_valid(_sun):
		var ext: Node = get_tree().get_first_node_in_group(&"exterior") if is_inside_tree() else null
		_sun = ext.get("sun") if ext != null else null
	return _sun


## 1 in full sunlight, 0 in the planet's shadow, eased through a penumbra.
func sun_factor() -> float:
	var lit_end: float = ORBIT_S - ECLIPSE_S
	var t: float = fposmod(phase_s, ORBIT_S)
	if t < lit_end:
		return clampf((lit_end - t) / PENUMBRA_S, 0.0, 1.0)      # fades into the shadow
	var to_sunrise: float = ORBIT_S - t
	return clampf(1.0 - to_sunrise / PENUMBRA_S, 0.0, 1.0)       # sunrise at the end of the eclipse


func in_eclipse() -> bool:
	return sun_factor() < 0.5


func seconds_to_eclipse() -> float:
	var t: float = fposmod(phase_s, ORBIT_S)
	return maxf(ORBIT_S - ECLIPSE_S - t, 0.0)


func _clock_s() -> float:
	var dp: Node = get_tree().get_first_node_in_group(&"day_plan") if is_inside_tree() else null
	if dp == null:
		return 0.0
	return float(dp.shift_elapsed_s) + (float(dp.awake_after_shift_s) if dp.shift_ended else 0.0)


func _process(_delta: float) -> void:
	phase_s = fposmod(_clock_s() + offset_s, ORBIT_S)
	_apply()


func _apply() -> void:
	var sun: DirectionalLight3D = _find_sun()
	if sun == null:
		return
	var k: float = fposmod(phase_s, ORBIT_S) / (ORBIT_S - ECLIPSE_S)
	sun.rotation_degrees = Vector3(-38.0 + 8.0 * sin(k * PI), 105.0 + 55.0 * clampf(k, 0.0, 1.0), 0.0)
	sun.light_energy = SUN_ENERGY * sun_factor()
	sun.visible = sun.light_energy > 0.01


func state_dict() -> Dictionary:
	return {"offset_s": offset_s}


## {"offset_s"} from a save, or {"phase_s"} to put the orbit at a phase NOW.
func load_dict(d: Dictionary) -> void:
	if d.has("phase_s"):
		offset_s = fposmod(float(d["phase_s"]) - _clock_s(), ORBIT_S)
	else:
		offset_s = fposmod(float(d.get("offset_s", 0.0)), ORBIT_S)
	phase_s = fposmod(_clock_s() + offset_s, ORBIT_S)
	_apply()
