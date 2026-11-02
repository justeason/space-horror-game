extends RefCounted
class_name HandMeshBuilder
## Round 20 Priority 2: replaces the CSG sphere-knuckle + cylinder-
## segment + sphere-tip finger construction (Round 19's own hand) --
## which produces a visible hard seam at every junction, since CSG
## union does not blend surfaces and each differently-curved primitive
## meeting at a shared plane reads as a ridge -- with a single
## continuously-lofted tube mesh per finger: a sequence of circular
## cross-section rings along a spine, with radius smoothly interpolated
## between control points (smoothstep, not linear, so the taper itself
## curves rather than kinking at each joint) and a gentle pinch at
## knuckle positions to suggest a joint WITHOUT an actual geometric
## seam, triangulated into one seamless ArrayMesh with per-vertex
## radial normals for smooth shading around AND along the tube. This is
## the literal, specific fix for "the raised hand and wristwatch still
## look like several cylinders connected together" -- not a CSG retune,
## a different modelling technique, per that feedback's own explicit
## instruction not to just add more primitives.
##
## Deliberately still a single STATIC mesh built once per instance (no
## Skeleton3D, no runtime deformation) -- see player_body.gd's own class
## doc comment for why a full skeletal migration was evaluated and
## declined again this round (the existing leg-swing/arm-gesture/lean
## animation logic is built entirely around named-node position/
## transform tweens, incompatible with bone-pose animation without a
## full reimplementation this round's scope does not allow). A lofted
## mesh is a genuinely different, smoother RESULT than CSG primitives
## without requiring that migration.
##
## Used by BOTH player_body.gd (the world-body hand, seen in the mirror
## and from outside) and first_person_watch_rig.gd (the camera-relative
## raised-hand view) -- the same builder, the same geometry technique,
## satisfying "shared appearance between first-person and world-body
## models" directly rather than maintaining two independently-tuned
## hand implementations that could drift apart.

const RING_SIDES: int = 10


## Builds one continuous tube mesh (a finger or thumb): `spine` is an
## Array of Vector3 control points (local space, base to tip), `radii`
## is a matching Array of float radii at each control point.
## `segments_per_span` subdivides smoothly between control points so
## the taper and any gentle bend reads as curved, not faceted into N
## straight pieces. Returns a MeshInstance3D ready to add as a child.
static func build_tube(mesh_name: String, spine: Array, radii: Array, segments_per_span: int, material: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var positions: Array[Vector3] = []
	var sample_radii: Array[float] = []
	var spans: int = spine.size() - 1
	for i in spans:
		var p0: Vector3 = spine[i]
		var p1: Vector3 = spine[i + 1]
		var r0: float = radii[i]
		var r1: float = radii[i + 1]
		for s in segments_per_span:
			var t: float = float(s) / float(segments_per_span)
			positions.append(p0.lerp(p1, t))
			var st_t: float = t * t * (3.0 - 2.0 * t)
			sample_radii.append(lerpf(r0, r1, st_t))
	positions.append(spine[spine.size() - 1])
	sample_radii.append(radii[radii.size() - 1])

	var ring_count: int = positions.size()
	var rings: Array = []
	for i in ring_count:
		var tangent: Vector3
		if i == 0:
			tangent = (positions[1] - positions[0]).normalized()
		elif i == ring_count - 1:
			tangent = (positions[i] - positions[i - 1]).normalized()
		else:
			tangent = (positions[i + 1] - positions[i - 1]).normalized()
		var ref_up: Vector3 = Vector3.UP if absf(tangent.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		var right: Vector3 = tangent.cross(ref_up).normalized()
		var up: Vector3 = right.cross(tangent).normalized()
		var ring_points: Array[Vector3] = []
		for k in RING_SIDES:
			var ang: float = TAU * float(k) / float(RING_SIDES)
			var offset: Vector3 = (right * cos(ang) + up * sin(ang)) * sample_radii[i]
			ring_points.append(positions[i] + offset)
		rings.append(ring_points)

	for i in (ring_count - 1):
		for k in RING_SIDES:
			var k2: int = (k + 1) % RING_SIDES
			var a: Vector3 = rings[i][k]
			var b: Vector3 = rings[i][k2]
			var c: Vector3 = rings[i + 1][k]
			var d: Vector3 = rings[i + 1][k2]
			var na: Vector3 = (a - positions[i]).normalized()
			var nb: Vector3 = (b - positions[i]).normalized()
			var nc: Vector3 = (c - positions[i + 1]).normalized()
			var nd: Vector3 = (d - positions[i + 1]).normalized()
			st.set_normal(na); st.add_vertex(a)
			st.set_normal(nb); st.add_vertex(b)
			st.set_normal(nc); st.add_vertex(c)
			st.set_normal(nb); st.add_vertex(b)
			st.set_normal(nd); st.add_vertex(d)
			st.set_normal(nc); st.add_vertex(c)

	# Rounded tip cap: a small fan converging to a point beyond the last
	# ring -- a soft fingertip, not a flat-cut cylinder end.
	var tip_tangent: Vector3 = (positions[ring_count - 1] - positions[ring_count - 2]).normalized()
	var tip_point: Vector3 = positions[ring_count - 1] + tip_tangent * sample_radii[ring_count - 1] * 0.9
	for k in RING_SIDES:
		var k2: int = (k + 1) % RING_SIDES
		var a: Vector3 = rings[ring_count - 1][k]
		var b: Vector3 = rings[ring_count - 1][k2]
		var na: Vector3 = ((a - positions[ring_count - 1]).normalized() + tip_tangent).normalized()
		var nb: Vector3 = ((b - positions[ring_count - 1]).normalized() + tip_tangent).normalized()
		st.set_normal(na); st.add_vertex(a)
		st.set_normal(nb); st.add_vertex(b)
		st.set_normal(tip_tangent); st.add_vertex(tip_point)

	# Base cap, tucked into the palm (mostly hidden) -- capped anyway so
	# there is no open hole visible at a grazing angle.
	var base_center: Vector3 = positions[0]
	var base_normal: Vector3 = -(positions[1] - positions[0]).normalized()
	for k in RING_SIDES:
		var k2: int = (k + 1) % RING_SIDES
		var a: Vector3 = rings[0][k]
		var b: Vector3 = rings[0][k2]
		st.set_normal(base_normal); st.add_vertex(b)
		st.set_normal(base_normal); st.add_vertex(a)
		st.set_normal(base_normal); st.add_vertex(base_center)

	st.set_material(material)
	var mesh: ArrayMesh = st.commit()
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	return instance


## Builds a complete hand (four fingers + thumb, as lofted tubes) as
## children of `root`. Canonical local frame matches the CSG hand it
## replaces: -Y points toward the fingertips, -Z is the palm's front
## face, X is hand width. `is_right` mirrors the thumb side and finger
## X-fan. The palm itself is NOT built here -- callers keep their own
## existing palm geometry (CSG boxes read fine as a flat-surfaced
## object; the "looks like primitives" complaint was specifically about
## the jointed fingers) and call this for the fingers/thumb only.
static func build_fingers_and_thumb(root: Node3D, is_right: bool, material: Material) -> void:
	var side: float = 1.0 if is_right else -1.0
	var finger_defs: Array = [
		{"n": "Index", "x": -0.024, "len": 0.052, "r0": 0.0092, "r1": 0.0045},
		{"n": "Middle", "x": -0.008, "len": 0.06, "r0": 0.0098, "r1": 0.0048},
		{"n": "Ring", "x": 0.008, "len": 0.056, "r0": 0.0092, "r1": 0.0045},
		{"n": "Pinky", "x": 0.024, "len": 0.044, "r0": 0.0078, "r1": 0.0038},
	]
	var knuckle_y: float = -0.065
	for def in finger_defs:
		var fx: float = def["x"] * side
		var length: float = def["len"]
		var r0: float = def["r0"]
		var r1: float = def["r1"]
		# Three control points (base, first-joint, tip) with a gentle
		# forward curl -- a relaxed hand, not a rigid rod -- and a mild
		# radius pinch at the mid control point (knuckle_r below)
		# standing in for a joint without any actual geometric seam.
		var base := Vector3(fx, knuckle_y, -0.012)
		var mid := Vector3(fx, knuckle_y - length * 0.55, -0.02 - length * 0.12)
		var tip := Vector3(fx, knuckle_y - length, -0.026 - length * 0.22)
		var r_mid: float = lerpf(r0, r1, 0.5) * 0.92
		var finger := build_tube("Finger" + def["n"], [base, mid, tip], [r0, r_mid, r1], 4, material)
		root.add_child(finger)

	var thumb_base := Vector3(0.03 * side, -0.036, 0.01)
	var thumb_mid := Vector3(0.05 * side, -0.05, 0.022)
	var thumb_tip := Vector3(0.066 * side, -0.062, 0.03)
	var thumb := build_tube("Thumb", [thumb_base, thumb_mid, thumb_tip], [0.0115, 0.0092, 0.0055], 4, material)
	root.add_child(thumb)


## Builds one finger/thumb tube directly from two existing, already-
## positioned anchor points (base and tip) -- for callers (e.g. the
## first-person watch rig) that already have hand-tuned knuckle/tip
## positions authored elsewhere and just need the OLD discrete sphere+
## cylinder+sphere assembly at those same anchors replaced with one
## smooth tube, without re-deriving a whole new hand layout. A gentle
## perpendicular curl is added at the midpoint (`curl_dir`, `curl_amount`)
## so the result reads as a relaxed curled finger rather than a straight
## rod between the two anchors.
static func build_finger_from_anchors(mesh_name: String, base_pos: Vector3, tip_pos: Vector3, base_radius: float, tip_radius: float, curl_dir: Vector3, curl_amount: float, material: Material) -> MeshInstance3D:
	var mid: Vector3 = base_pos.lerp(tip_pos, 0.5) + curl_dir.normalized() * curl_amount
	var mid_radius: float = lerpf(base_radius, tip_radius, 0.5) * 0.95
	return build_tube(mesh_name, [base_pos, mid, tip_pos], [base_radius, mid_radius, tip_radius], 4, material)
