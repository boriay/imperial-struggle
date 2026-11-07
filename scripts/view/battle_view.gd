class_name BattleView
extends Node3D

## 3D rendering of the field with a tilted camera. Simulation cell (x, y) is
## the point (x, 0, y) in 3D; one cell equals one meter.

const PITCH := deg_to_rad(48.0)
const DIST_MIN := 6.0
const DIST_MAX := 36.0
## Sides. Empire: dark metal, rounded shapes, red markings.
## Rebels: light grey-blue paint, angular faceted shapes.
const FACTIONS := {
	"empire": {"name": "Empire", "body": Color(0.13, 0.135, 0.125), "dark": Color(0.06, 0.06, 0.055),
		"accent": Color(0.85, 0.18, 0.14), "angular": false},
	"rebels": {"name": "Rebels", "body": Color(0.3, 0.44, 0.6), "dark": Color(0.15, 0.2, 0.27),
		"accent": Color(0.5, 0.82, 1.0), "angular": true},
}
const EMPIRE_BODY := Color(0.13, 0.135, 0.125)
const EMPIRE_DARK := Color(0.06, 0.06, 0.055)
const CRYSTAL_COLOR := Color(0.25, 0.95, 0.8)
const TRACK_A := 0.38
const TRACK_R := 0.11
const TRACK_Y := 0.12
## Ground in the style of a scorched wasteland: sand, dry clay, bare rock patches,
## burnt spots and cracks. All procedural, no textures.
const GROUND_SHADER := """
shader_type spatial;
render_mode specular_disabled;
uniform float grid_strength = 0.0;
uniform float tint = 1.0;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
// Pebbles: a random point in every grid cell with a round stone of varying size around it.
float pebbles(vec2 p) {
	vec2 i = floor(p);
	float best = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = i + vec2(float(x), float(y));
			float r = hash(c + 3.7);
			float dens = noise(c * 0.07) * 0.5;
			if (r < 0.72 + dens) continue;
			vec2 o = vec2(hash(c), hash(c + 1.3)) * 0.7 + 0.15;
			float rad = 0.05 + 0.5 * (r - 0.72) * hash(c + 9.1);
			float d = length(p - c - o) / rad;
			best = max(best, sqrt(max(0.0, 1.0 - d * d)));
		}
	}
	return best;
}
// Height of the fine relief: bumps, sand ripples and pebbles. Used for lighting only.
float relief(vec2 p, float sandy) {
	float h = fbm(p * 0.8) * 0.5 + fbm(p * 3.1) * 0.15;
	h += sandy * 0.05 * sin(p.x * 5.0 + p.y * 2.0 + fbm(p * 0.7) * 6.0);
	return h + pebbles(p * 3.0) * 0.06 * (1.0 - sandy * 0.6);
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wpos.xz;
	vec3 sand = vec3(0.5, 0.42, 0.31);
	vec3 clay = vec3(0.33, 0.27, 0.2);
	vec3 rock = vec3(0.37, 0.36, 0.33);
	float sandy = smoothstep(0.35, 0.65, fbm(p * 0.3));
	vec3 col = mix(clay, sand, sandy);
	float rocky = smoothstep(0.6, 0.72, fbm(p * 0.16 + 7.0));
	col = mix(col, rock, rocky);
	col *= 0.86 + 0.24 * fbm(p * 2.5);
	// Dark patches of damp ground and pale burnt-out spots.
	col = mix(col, vec3(0.16, 0.13, 0.1), smoothstep(0.68, 0.82, fbm(p * 0.45 + 3.1)) * 0.45);
	col = mix(col, vec3(0.6, 0.54, 0.43), smoothstep(0.7, 0.85, fbm(p * 0.6 + 9.4)) * 0.25);
	// Small pebbles.
	float pb = pebbles(p * 3.0);
	col = mix(col, rock * (0.75 + 0.4 * hash(floor(p * 3.0))), smoothstep(0.0, 0.4, pb) * (1.0 - sandy * 0.6) * 0.55);
	// Thin cracks, only in clay and rock.
	float crack = abs(fbm(p * 1.1 + 11.0) - 0.5);
	col *= 1.0 - 0.18 * (1.0 - sandy) * (1.0 - smoothstep(0.0, 0.008, crack));
	vec2 g = abs(fract(p) - 0.5);
	col *= 1.0 - grid_strength * step(0.485, max(g.x, g.y));
	float e = 0.04;
	float h0 = relief(p, sandy);
	float hx = relief(p + vec2(e, 0.0), sandy) - h0;
	float hz = relief(p + vec2(0.0, e), sandy) - h0;
	vec3 n = normalize(vec3(-hx / e * 0.6, 1.0, -hz / e * 0.6));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = col * tint;
	ROUGHNESS = 1.0;
}
"""

var camera: Camera3D
var focus := Vector3.ZERO
var yaw := 0.0
var dist := 18.0

var _wall_nodes := {}
var _crystal_nodes := {}
var _unit_nodes := {}
var _materials := {}
var _wall_rock_meshes: Array[ArrayMesh] = []
## Each team's side and marking colors; set by the game before build().
var factions := ["empire", "rebels"]
var team_colors := [Color(0.85, 0.18, 0.14), Color(0.5, 0.82, 1.0)]
# Current style while a model is being built: hull color, dark parts color and faceting.
var _body := EMPIRE_BODY
var _dark := EMPIRE_DARK
var _angular := false
var _faction := "empire"
var _fog_img: Image
var _fog_tex: ImageTexture
var _fog_vals := PackedFloat32Array()
var effects: Effects
var _time := 0.0
## Bodies and wrecks: {node, life, kind}.
var _dead: Array = []


func build(world: World) -> void:
	for c in get_children():
		c.queue_free()
	_wall_nodes.clear()
	_crystal_nodes.clear()
	_unit_nodes.clear()

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.32, 0.26, 0.2)
	# Desert light: bluish ambient sky light, warm sun, light haze.
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.66, 0.75)
	e.ambient_light_energy = 0.38
	e.fog_enabled = true
	e.fog_light_color = Color(0.55, 0.46, 0.36)
	e.fog_density = 0.004
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.15
	e.tonemap_white = 6.0
	# Glow of flashes, fire and crystals.
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.glow_strength = 0.9
	e.glow_bloom = 0.02
	e.glow_hdr_threshold = 1.1
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.08
	e.adjustment_saturation = 0.92
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(-30), 0)
	sun.light_color = Color(1.0, 0.88, 0.72)
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.shadow_blur = 1.6
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)

	var shader := Shader.new()
	shader.code = GROUND_SHADER
	var size := Vector2(world.width, world.height)
	var outer := MeshInstance3D.new()
	var outer_mesh := PlaneMesh.new()
	outer_mesh.size = size * 3.0
	outer.mesh = outer_mesh
	outer.position = Vector3(size.x / 2, -0.02, size.y / 2)
	var om := ShaderMaterial.new()
	om.shader = shader
	om.set_shader_parameter("grid_strength", 0.0)
	om.set_shader_parameter("tint", 0.6)
	outer.material_override = om
	add_child(outer)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size
	ground.mesh = plane
	ground.position = Vector3(size.x / 2, 0, size.y / 2)
	var gm := ShaderMaterial.new()
	gm.shader = shader
	ground.material_override = gm
	add_child(ground)

	effects = Effects.new()
	add_child(effects)
	_dead.clear()

	_add_scenery(world)

	_build_walls(world)
	_build_water(world)
	_build_fog(world)

	camera = Camera3D.new()
	camera.fov = 35.0
	camera.far = 200.0
	add_child(camera)
	camera.make_current()
	focus = Vector3(size.x / 2, 0, size.y / 2)
	yaw = 0.0
	dist = 15.0
	update_camera()


func update_camera() -> void:
	var offset := Vector3(0, sin(PITCH), cos(PITCH)) * dist
	camera.position = focus + offset.rotated(Vector3.UP, yaw)
	camera.look_at(focus, Vector3.UP)


func clamp_focus(world: World) -> void:
	focus.x = clampf(focus.x, 0.0, world.width)
	focus.z = clampf(focus.z, 0.0, world.height)
	focus.y = 0.0


## The "right" and "forward" directions on the ground relative to the screen.
func ground_right() -> Vector3:
	return Vector3.RIGHT.rotated(Vector3.UP, yaw)


func ground_forward() -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, yaw)


func screen_to_ground(screen_pos: Vector2) -> Vector2:
	var o := camera.project_ray_origin(screen_pos)
	var n := camera.project_ray_normal(screen_pos)
	if absf(n.y) < 0.0001:
		return Vector2(o.x, o.z)
	var t := -o.y / n.y
	var p := o + n * t
	return Vector2(p.x, p.z)


func project(p: Vector2, height: float) -> Vector2:
	return camera.unproject_position(Vector3(p.x, height, p.y))


func is_visible_point(p: Vector2, height: float) -> bool:
	return not camera.is_position_behind(Vector3(p.x, height, p.y))


## Updates the 3D objects from the world state. pos_of gives the smoothed unit position.
func sync(world: World, pos_of: Callable, selected: Array, delta: float) -> void:
	if _wall_nodes.size() != world.walls.size():
		_sync_walls(world)
	_update_fog(world, delta)
	for c: Vector2i in _wall_nodes:
		var k: float = world.walls[c] / World.WALL_HP
		var node: Node3D = _wall_nodes[c]
		node.scale.y = 0.45 + 0.55 * k
		node.visible = world.cell_explored(c)

	for c: Vector2i in _crystal_nodes.keys():
		if not world.crystals.has(c):
			_crystal_nodes[c].queue_free()
			_crystal_nodes.erase(c)
	for c: Vector2i in world.crystals:
		var node: Node3D = _crystal_nodes.get(c)
		if node == null:
			node = _make_crystals(c)
			_crystal_nodes[c] = node
			add_child(node)
		node.scale = Vector3.ONE * (0.45 + 0.55 * clampf(world.crystals[c] / World.CRYSTAL_AMOUNT, 0.0, 1.3))
		node.visible = world.cell_explored(c)

	_time = world.time
	for id: int in _unit_nodes.keys():
		if not world.units.has(id):
			_kill_node(_unit_nodes[id])
			_unit_nodes.erase(id)
	for u: SimUnit in world.units.values():
		var node: Node3D = _unit_nodes.get(u.id)
		if node == null:
			node = _make_unit(u)
			_unit_nodes[u.id] = node
			add_child(node)
		node.visible = world.unit_visible(u) or u.seen
		var p: Vector2 = pos_of.call(u)
		var last: Vector2 = node.get_meta("last", p)
		var moved := p.distance_to(last)
		node.set_meta("last", p)
		node.position = Vector3(p.x, 0, p.y)
		node.get_node("Ring").visible = selected.has(u.id)
		if u.is_structure():
			var body: Node3D = node.get_node("Body")
			body.scale.y = 0.25 + 0.75 * u.build_progress
			for smoke in body.find_children("Smoke*", "CPUParticles3D", false, false):
				smoke.emitting = u.is_complete()
			if u.type == "turret":
				var rec: float = maxf(0.0, node.get_meta("recoil", 0.0) - delta * 5.0)
				node.set_meta("recoil", rec)
				var tur: Node3D = body.get_node("Turret")
				tur.rotation.y = -u.turret
				tur.position.x = -cos(u.turret) * rec * 0.06
				tur.position.z = -sin(u.turret) * rec * 0.06
			continue
		_animate(u, node, moved, delta)
	_update_dead(delta)


## Animation: smooth turns, a stride with bending knees, raising the weapon and recoil for infantry,
## moving tracks, hull pitch when speeding up and braking, gun recoil for vehicles.
func _animate(u: SimUnit, node: Node3D, moved: float, delta: float) -> void:
	var phase: float = node.get_meta("phase", 0.0) + moved
	node.set_meta("phase", phase)
	var walking: float = node.get_meta("walk", 0.0)
	walking = move_toward(walking, 1.0 if moved > 0.0005 else 0.0, delta * 5.0)
	node.set_meta("walk", walking)
	var recoil: float = maxf(0.0, node.get_meta("recoil", 0.0) - delta * 5.0)
	node.set_meta("recoil", recoil)
	var smooth := 1.0 - exp(-delta * 7.0)
	match u.type:
		"tank", "harvester":
			var hull: Node3D = node.get_node("Hull")
			hull.rotation.y = lerp_angle(hull.rotation.y, -u.facing, smooth)
			# Pitch: speeding up lifts the nose, braking dips it, a shot rocks it back.
			var speed := moved / maxf(delta, 0.001)
			var prev_speed: float = node.get_meta("speed", 0.0)
			node.set_meta("speed", lerpf(prev_speed, speed, 1.0 - exp(-delta * 4.0)))
			var accel := (speed - prev_speed)
			var pitch: float = node.get_meta("pitch", 0.0)
			var want := clampf(accel * 0.05, -0.05, 0.05) - recoil * 0.06
			pitch = lerpf(pitch, want, 1.0 - exp(-delta * 6.0))
			node.set_meta("pitch", pitch)
			hull.rotation.z = pitch
			hull.position.y = absf(sin(phase * 6.0)) * 0.008 * walking
			var dust: CPUParticles3D = node.get_node_or_null("Hull/Dust")
			if dust:
				dust.emitting = walking > 0.4
			if u.type == "tank":
				var turret: Node3D = node.get_node("Turret")
				turret.rotation.y = -u.turret
				turret.rotation.z = pitch
				turret.position = Vector3(0, 0.5 + hull.position.y, 0) \
					- Vector3(cos(u.turret), 0, sin(u.turret)) * recoil * 0.07
				_animate_tracks(node, phase)
			else:
				for w: Node3D in node.get_meta("wheels"):
					w.rotation.z = -phase / 0.14
				node.get_node("Hull/Load").visible = u.cargo > 0.5
		_:
			var body: Node3D = node.get_node("Body")
			var aiming: bool = u.can_fight() and _time - u.fired_at < 2.0 and moved < 0.0005
			var face := u.turret if aiming or moved < 0.0005 else u.facing
			body.rotation.y = lerp_angle(body.rotation.y, -face, smooth)
			var aim: float = node.get_meta("aim", 0.0)
			aim = move_toward(aim, 1.0 if aiming else 0.0, delta * 4.0)
			node.set_meta("aim", aim)
			var s := sin(phase * 8.0)
			var swing := s * 0.55 * walking
			var legl: Node3D = body.get_node("LegL")
			var legr: Node3D = body.get_node("LegR")
			legl.rotation.z = swing
			legr.rotation.z = -swing
			# The knee bends when the leg swings back and leaves the ground.
			legl.get_node("Knee").rotation.z = -maxf(0.0, -s) * 0.9 * walking
			legr.get_node("Knee").rotation.z = -maxf(0.0, s) * 0.9 * walking
			var torso: Node3D = body.get_node("Torso")
			# Leaning forward on the move, a slight kick back when firing, breathing when standing.
			torso.rotation.z = -0.1 * walking + recoil * 0.12
			torso.position.y = absf(s) * 0.018 * walking + sin(_time * 2.2 + u.id) * 0.003 * (1.0 - walking)
			var arml: Node3D = torso.get_node("ArmL")
			var armr: Node3D = torso.get_node("ArmR")
			var gun: Node3D = torso.get_node("Gun")
			var rest: Vector3 = gun.get_meta("rest")
			if u.type == "medic" or u.type == "engineer":
				arml.rotation.z = -swing * 0.8
				armr.rotation.z = lerpf(swing * 0.5 + 0.3, 1.2, aim)
				armr.get_node("Elbow").rotation.z = lerpf(0.5, 0.3, aim)
				arml.get_node("Elbow").rotation.z = 0.25 + 0.2 * walking
				gun.position = rest + Vector3(0.06 + 0.12 * aim, 0.03 * aim, 0)
				gun.rotation.z = 0.0
			elif u.type == "grenadier":
				# Launcher on the shoulder; when firing it points straight along the aim line.
				arml.rotation.z = lerpf(0.9 - swing * 0.2, 1.25, aim)
				arml.get_node("Elbow").rotation.z = lerpf(1.0, 0.7, aim)
				armr.rotation.z = lerpf(0.6, 0.9, aim)
				armr.get_node("Elbow").rotation.z = 1.3
				gun.position = rest - Vector3(recoil * 0.04, 0, 0)
				gun.rotation.z = lerpf(-0.12, 0.0, aim)
			else:
				# Rifle: at the hip, muzzle down, on the move; at the shoulder when firing.
				arml.rotation.z = lerpf(0.55 - swing * 0.15, 1.3, aim)
				arml.get_node("Elbow").rotation.z = lerpf(1.0, 0.35, aim)
				armr.rotation.z = lerpf(0.35, 0.85, aim)
				armr.get_node("Elbow").rotation.z = lerpf(1.1, 0.9, aim)
				gun.position = rest.lerp(Vector3(0.09, 0.57, 0.035), aim) - Vector3(recoil * 0.03, 0, 0)
				gun.rotation.z = lerpf(-0.45, 0.0, aim) + recoil * 0.15


## Recoil for the shooter: infantry jerk, a tank's gun recoils and its hull rocks.
func recoil(id: int) -> void:
	var node: Node3D = _unit_nodes.get(id)
	if node:
		node.set_meta("recoil", 1.0)


func _animate_tracks(node: Node3D, phase: float) -> void:
	var links: Array = node.get_meta("links")
	var n := links.size() / 2
	var perim := 4.0 * TRACK_A + TAU * TRACK_R
	for i in links.size():
		var link: Node3D = links[i]
		var s := phase * 1.0 + perim * float(i % n) / n
		var pt := _track_point(s, TRACK_A, TRACK_R)
		link.position.x = pt.x
		link.position.y = TRACK_Y + pt.y
	for w: Node3D in node.get_meta("wheels"):
		w.rotation.z = -phase / TRACK_R


## A point on the track oval: the top moves forward, the bottom stays on the ground.
static func _track_point(s: float, a: float, r: float) -> Vector2:
	s = fposmod(s, 4.0 * a + TAU * r)
	if s < 2.0 * a:
		return Vector2(-a + s, r)
	s -= 2.0 * a
	if s < PI * r:
		var ang := PI / 2.0 - s / r
		return Vector2(a + r * cos(ang), r * sin(ang))
	s -= PI * r
	if s < 2.0 * a:
		return Vector2(a - s, -r)
	s -= 2.0 * a
	var ang2 := -PI / 2.0 - s / r
	return Vector2(-a + r * cos(ang2), r * sin(ang2))


func spawn_blast(p: Vector2, size: float, _life: float) -> void:
	effects.explosion(p, size)


## A killed unit does not vanish at once: an infantryman falls, a vehicle stays as a burning wreck.
func _kill_node(node: Node3D) -> void:
	var kind: String = node.get_meta("kind", "")
	if not node.visible or kind == "" or node.get_meta("structure", false):
		node.queue_free()
		return
	node.get_node("Ring").visible = false
	if kind == "tank" or kind == "harvester":
		var burnt := StandardMaterial3D.new()
		burnt.albedo_color = Color(0.06, 0.055, 0.05)
		burnt.roughness = 1.0
		for m in node.find_children("*", "MeshInstance3D", true, false):
			m.material_override = burnt
		var dust: CPUParticles3D = node.get_node_or_null("Hull/Dust")
		if dust:
			dust.emitting = false
		var smoke := effects.wreck_smoke()
		smoke.position.y = 0.45
		node.add_child(smoke)
		var turret: Node3D = node.get_node_or_null("Turret")
		if turret:
			turret.rotation.z = 0.12
			turret.rotation.y += 0.4
		_dead.append({"node": node, "life": 25.0, "kind": "wreck", "t": 0.0})
	else:
		_dead.append({"node": node, "life": 10.0, "kind": "body", "t": 0.0,
			"dir": 1.0 if (node.get_instance_id() % 2) == 0 else -1.0})


func _update_dead(delta: float) -> void:
	for d in _dead:
		d.life -= delta
		d.t += delta
		var node: Node3D = d.node
		if d.kind == "body":
			var body: Node3D = node.get_node("Body")
			var k := clampf(d.t / 0.45, 0.0, 1.0)
			k = k * k
			body.rotation.z = d.dir * PI / 2.0 * 0.95 * k
			body.position.y = 0.03 * k
			var legs := 1.0 - k
			body.get_node("LegL").rotation.z *= legs
			body.get_node("LegR").rotation.z *= legs
		# Sinks into the ground during the last two seconds.
		if d.life < 2.0:
			node.position.y = -0.5 * (1.0 - d.life / 2.0)
		if d.life <= 0.0:
			node.queue_free()
	_dead = _dead.filter(func(d): return d.life > 0.0)


## A thin wall with a rounded top: a post in every cell and spans
## to neighbouring wall cells. For the simulation the cell is still whole.
func _build_walls(world: World) -> void:
	for n: Node3D in _wall_nodes.values():
		n.queue_free()
	_wall_nodes.clear()
	for c: Vector2i in world.walls:
		_add_wall_node(world, c)


## Removes destroyed walls and rebuilds the neighbours whose spans led to them.
func _sync_walls(world: World) -> void:
	var redo := {}
	for c: Vector2i in _wall_nodes.keys():
		if not world.walls.has(c):
			_wall_nodes[c].queue_free()
			_wall_nodes.erase(c)
			redo[c - Vector2i(1, 0)] = true
			redo[c - Vector2i(0, 1)] = true
	for c: Vector2i in redo:
		if _wall_nodes.has(c):
			_wall_nodes[c].queue_free()
			_wall_nodes.erase(c)
			_add_wall_node(world, c)


func _add_wall_node(world: World, c: Vector2i) -> void:
	var root := Node3D.new()
	root.position = Vector3(c.x + 0.5, 0, c.y + 0.5)
	var spans: Array[float] = []
	for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
		if world.walls.has(c + d):
			spans.append(0.0 if d.x == 1 else -PI / 2)
	var shade := 0.9 + 0.1 * float((c.x * 7 + c.y * 13) % 5) / 4.0
	match world.wall_style:
		1: _wall_sandbags(root, spans, shade, c)
		2: _wall_fence(root, spans)
		3: _wall_stone(root, spans, shade, c)
		_: _wall_concrete(root, spans, shade, c)
	add_child(root)
	_wall_nodes[c] = root


func _span_node(root: Node3D, angle: float) -> Node3D:
	var span := Node3D.new()
	span.rotation.y = angle
	root.add_child(span)
	return span


## Concrete: square posts and slabs with chipped edges, sticking-out rebar, rubble at the base.
func _wall_concrete(root: Node3D, spans: Array[float], shade: float, c: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = c.x * 73856 + c.y * 19349
	var concrete := Color(0.34, 0.32, 0.29) * shade
	var rebar := Color(0.25, 0.13, 0.07)
	var post_h := rng.randf_range(0.66, 0.74)
	root.add_child(_box(Vector3(0.26, post_h, 0.26), Vector3(0, post_h / 2, 0), concrete))
	root.add_child(_box(Vector3(0.3, 0.05, 0.3), Vector3(0, post_h, 0), concrete.lightened(0.06)))
	root.add_child(_box(Vector3(0.34, 0.08, 0.34), Vector3(0, 0.04, 0), concrete.darkened(0.35)))
	for angle in spans:
		var span := _span_node(root, angle)
		# A slab of three pieces of different heights: the top is chipped.
		for k in 3:
			var hgt := 0.56 - rng.randf_range(0.0, 0.14) * float(rng.randf() < 0.5)
			var x0 := 0.13 + k * 0.25
			span.add_child(_box(Vector3(0.26, hgt, 0.16), Vector3(x0 + 0.125, hgt / 2, 0),
				concrete.darkened(rng.randf_range(0.0, 0.1))))
			if hgt < 0.5:
				for r in 2:
					var bar := _cyl(0.008, 0.14, Vector3(x0 + 0.06 + r * 0.12, hgt + 0.05, rng.randf_range(-0.04, 0.04)), rebar)
					bar.rotation.z = rng.randf_range(-0.4, 0.4)
					span.add_child(bar)
		span.add_child(_box(Vector3(0.75, 0.025, 0.18), Vector3(0.5, 0.02, 0), concrete.darkened(0.35)))
		# Concrete rubble at the base.
		for k in 2:
			var chunk := _box(Vector3.ONE * rng.randf_range(0.05, 0.09),
				Vector3(rng.randf_range(0.2, 0.8), 0.03, rng.randf_range(0.12, 0.2) * (1.0 if rng.randf() < 0.5 else -1.0)),
				concrete.darkened(0.15))
			chunk.rotation = Vector3(rng.randf() * PI, rng.randf() * PI, 0)
			span.add_child(chunk)


## Sandbags: low rows of flattened bags.
func _wall_sandbags(root: Node3D, spans: Array[float], shade: float, c: Vector2i) -> void:
	var bag := Color(0.34, 0.3, 0.22) * shade
	for row in 3:
		var b := _sphere(0.2, Vector3(0, 0.09 + row * 0.15, 0), bag.darkened(0.08 * ((row + c.x) % 2)))
		b.scale = Vector3(1.1, 0.45, 0.9)
		root.add_child(b)
	for angle in spans:
		var span := _span_node(root, angle)
		for row in 3:
			for k in 2:
				var x := 0.33 + 0.34 * k + (0.17 if row % 2 == 1 else 0.0)
				var b := _sphere(0.19, Vector3(minf(x, 0.85), 0.09 + row * 0.15, 0), bag.darkened(0.06 * ((row + k) % 2)))
				b.scale = Vector3(1.0, 0.45, 0.8)
				span.add_child(b)


## Metal fence: posts, a mesh panel and barbed wire on top.
func _wall_fence(root: Node3D, spans: Array[float]) -> void:
	var metal := Color(0.16, 0.17, 0.17)
	root.add_child(_cyl(0.045, 0.85, Vector3(0, 0.42, 0), metal))
	root.add_child(_sphere(0.06, Vector3(0, 0.86, 0), metal))
	root.add_child(_cyl(0.12, 0.06, Vector3(0, 0.03, 0), Color(0.12, 0.11, 0.1)))
	for angle in spans:
		var span := _span_node(root, angle)
		var panel := _box(Vector3(1.0, 0.62, 0.03), Vector3(0.5, 0.42, 0), Color(0.1, 0.11, 0.11))
		span.add_child(panel)
		for y in [0.14, 0.42, 0.72]:
			var rail := _cyl(0.02, 1.0, Vector3(0.5, y, 0), metal.lightened(0.15))
			rail.rotation.z = PI / 2
			span.add_child(rail)
		for k in 3:
			var coil := _team_band(0.06, 0.075, Vector3(0.2 + 0.3 * k, 0.86, 0), Vector3.ONE, Color(0.3, 0.3, 0.28))
			coil.rotation.x = PI / 2
			coil.rotation.y = PI / 2
			span.add_child(coil)


## Stone masonry: chipped blocks laid in two rows, small stones in the gaps.
func _wall_stone(root: Node3D, spans: Array[float], shade: float, c: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = c.x * 92821 + c.y * 68917
	var mat := _stone_wall_mat(shade)
	_wall_rock(root, mat, rng, Vector3(0, 0.2, 0), Vector3(0.48, 0.44, 0.44))
	_wall_rock(root, mat, rng, Vector3(0.0, 0.5, 0), Vector3(0.34, 0.3, 0.32))
	for angle in spans:
		var span := _span_node(root, angle)
		for k in 3:
			var r := rng.randf_range(0.34, 0.42)
			_wall_rock(span, mat, rng, Vector3(0.28 + 0.24 * k, r * 0.45, rng.randf_range(-0.03, 0.03)),
				Vector3(r * 1.1, r, r))
			if k < 2:
				var t := rng.randf_range(0.24, 0.3)
				_wall_rock(span, mat, rng, Vector3(0.4 + 0.24 * k, r * 0.85 + t * 0.3, 0), Vector3(t * 1.2, t, t))


func _wall_rock(parent: Node3D, mat: Material, rng: RandomNumberGenerator, pos: Vector3, size: Vector3) -> void:
	var m := MeshInstance3D.new()
	m.mesh = _wall_rock_meshes[rng.randi() % _wall_rock_meshes.size()]
	m.material_override = mat
	m.position = pos
	m.rotation.y = rng.randf() * TAU
	m.scale = size
	parent.add_child(m)


func _stone_wall_mat(shade: float) -> Material:
	var key := "stonewall%.2f" % shade
	if not _materials.has(key):
		var mat := _rock_material()
		mat.set_shader_parameter("shade", shade)
		_materials[key] = mat
	if _wall_rock_meshes.is_empty():
		for v in 4:
			_wall_rock_meshes.append(_rock_mesh(777 + v * 13))
	return _materials[key]


## Water as one MultiMesh: a dark surface with sun glints.
func _blur_pass(src: PackedFloat32Array, w: int, h: int, kernel: PackedFloat32Array,
		step: Vector2i) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(src.size())
	var r := kernel.size() / 2
	for y in h:
		for x in w:
			var acc := 0.0
			for k in kernel.size():
				var px := clampi(x + (k - r) * step.x, 0, w - 1)
				var py := clampi(y + (k - r) * step.y, 0, h - 1)
				acc += src[py * w + px] * kernel[k]
			out[y * w + x] = acc
	return out


## Water is drawn as one plane over the whole map. The water cell mask is upscaled
## with cubic interpolation and the shader cuts it at 0.5: cell corners
## get rounded, while straight shores run exactly along cell borders.
func _build_water(world: World) -> void:
	if world.water.is_empty():
		return
	const RES := 8
	const SUB := 2  # mask pixels per cell before blurring
	var mw := (world.width + 2) * SUB
	var mh := (world.height + 2) * SUB
	var raw := PackedFloat32Array()
	raw.resize(mw * mh)
	for c: Vector2i in world.water:
		for sy in SUB:
			for sx in SUB:
				raw[((c.y + 1) * SUB + sy) * mw + (c.x + 1) * SUB + sx] = 1.0
	# Gaussian blur of about half a cell: the cell steps smooth out into a soft shore.
	var kernel := PackedFloat32Array([0.06, 0.24, 0.4, 0.24, 0.06])
	raw = _blur_pass(raw, mw, mh, kernel, Vector2i(1, 0))
	raw = _blur_pass(raw, mw, mh, kernel, Vector2i(0, 1))
	var mask := Image.create(mw, mh, false, Image.FORMAT_L8)
	for y in mh:
		for x in mw:
			var v := raw[y * mw + x]
			mask.set_pixel(x, y, Color(v, v, v))
	mask.resize((world.width + 2) * RES, (world.height + 2) * RES, Image.INTERPOLATE_CUBIC)
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, specular_schlick_ggx;
uniform sampler2D mask : filter_linear, repeat_disable;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float wave(vec2 p, float t) {
	return sin(p.x * 1.7 + t * 1.1) * 0.5 + sin(p.y * 2.3 - t * 0.8) * 0.3 + sin((p.x + p.y) * 3.1 + t * 1.7) * 0.2;
}
void fragment() {
	float m = texture(mask, UV).r;
	if (m < 0.36) discard;
	float t = TIME;
	float w = wave(wpos.xz, t);
	vec3 deep = vec3(0.04, 0.12, 0.15);
	vec3 light = vec3(0.10, 0.24, 0.26);
	vec3 water = mix(deep, light, w * 0.5 + 0.5);
	// Deeper towards the middle; light foam and dark wet sand at the shore.
	water = mix(water, deep * 0.7, smoothstep(0.6, 1.0, m) * 0.5);
	float foam = smoothstep(0.5, 0.53, m) * (1.0 - smoothstep(0.53, 0.6, m));
	water = mix(water, vec3(0.45, 0.5, 0.45), foam * (0.5 + 0.3 * sin(t * 2.0 + wpos.x * 3.0 + wpos.z * 2.0)));
	float is_water = smoothstep(0.48, 0.52, m);
	ALBEDO = mix(vec3(0.17, 0.12, 0.07), water, is_water);
	ALPHA = mix(smoothstep(0.36, 0.48, m) * 0.6, 1.0, is_water);
	float e = 0.08;
	vec2 g = vec2(wave(wpos.xz + vec2(e, 0.0), t) - w, wave(wpos.xz + vec2(0.0, e), t) - w) / e;
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(vec3(-g.x * 0.08 * is_water, 1.0, -g.y * 0.08 * is_water)), 0.0)).xyz);
	ROUGHNESS = mix(0.9, 0.08, is_water);
	SPECULAR = mix(0.2, 0.9, is_water);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("mask", ImageTexture.create_from_image(mask))
	var plane := PlaneMesh.new()
	plane.size = Vector2(world.width + 2, world.height + 2)
	var inst := MeshInstance3D.new()
	inst.mesh = plane
	inst.position = Vector3(world.width / 2.0, 0.012, world.height / 2.0)
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)


## Fog of war: a plane above the ground with a per-cell mask. The mask smoothly follows
## visibility; linear filtering gives soft edges and noise gives fog wisps.
func _build_fog(world: World) -> void:
	_fog_img = Image.create(world.width, world.height, false, Image.FORMAT_L8)
	_fog_vals.resize(world.width * world.height)
	for i in _fog_vals.size():
		_fog_vals[i] = _fog_target(world, i)
	_write_fog(world)
	_fog_tex = ImageTexture.create_from_image(_fog_img)
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform sampler2D fog : filter_linear, repeat_disable;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float f = texture(fog, UV).r;
	float n = noise(wpos.xz * 0.6 + TIME * 0.05) * 0.6 + noise(wpos.xz * 1.7 - TIME * 0.08) * 0.4;
	ALBEDO = mix(vec3(0.02, 0.02, 0.025), vec3(0.09, 0.08, 0.07), n * f);
	ALPHA = clamp(f * (0.85 + 0.25 * n), 0.0, 0.97);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.render_priority = 10
	mat.set_shader_parameter("fog", _fog_tex)
	var plane := PlaneMesh.new()
	plane.size = Vector2(world.width, world.height)
	var inst := MeshInstance3D.new()
	inst.name = "Fog"
	inst.mesh = plane
	inst.position = Vector3(world.width / 2.0, 0.1, world.height / 2.0)
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)


## 0 = visible, 0.7 = explored but not visible now, 1 = unexplored.
func _fog_target(world: World, i: int) -> float:
	if world.visible[i] == 1:
		return 0.0
	return 0.7 if world.explored[i] == 1 else 1.0


func _update_fog(world: World, delta: float) -> void:
	if _fog_img == null:
		return
	var changed := false
	for i in _fog_vals.size():
		var t := _fog_target(world, i)
		if _fog_vals[i] != t:
			_fog_vals[i] = move_toward(_fog_vals[i], t, delta * 2.5)
			changed = true
	if changed:
		_write_fog(world)
		_fog_tex.update(_fog_img)


func _write_fog(world: World) -> void:
	for y in world.height:
		for x in world.width:
			var v := _fog_vals[y * world.width + x]
			_fog_img.set_pixel(x, y, Color(v, v, v))


## Rocks along the map edge and small debris on the field: decoration only, they do not block movement.
## The rocks are a few procedural faceted boulders placed through a MultiMesh:
## large boulders in two or three rows with gravel between them, the bottom sunk into the sand.
const ROCK_VARIANTS := 6

func _add_scenery(world: World) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1997
	var w := float(world.width)
	var h := float(world.height)
	var placed: Array = []  # [position, size]
	for row in 3:
		var inner := 0.5 + row * 1.1
		var outer := inner + 1.1
		var t := -2.0
		while t < w + 2.0:
			placed.append([Vector2(t, -rng.randf_range(inner, outer)), _rock_size(rng, row)])
			placed.append([Vector2(t, h + rng.randf_range(inner, outer)), _rock_size(rng, row)])
			t += rng.randf_range(0.6, 1.3) * (1.0 + row * 0.3)
		t = -2.0
		while t < h + 2.0:
			placed.append([Vector2(-rng.randf_range(inner, outer), t), _rock_size(rng, row)])
			placed.append([Vector2(w + rng.randf_range(inner, outer), t), _rock_size(rng, row)])
			t += rng.randf_range(0.6, 1.3) * (1.0 + row * 0.3)
	# Gravel at the foot of the rocks.
	var count := placed.size()
	for i in count:
		for k in 2:
			var base: Vector2 = placed[i][0]
			var off := Vector2(rng.randf_range(-1.2, 1.2), rng.randf_range(-1.2, 1.2))
			placed.append([base + off, rng.randf_range(0.12, 0.3)])
	# Sparse pebbles on the field itself.
	for i in 90:
		var p := Vector2(rng.randf_range(0.0, w), rng.randf_range(0.0, h))
		var c := World.cell_of(p)
		if world.walls.has(c) or world.water.has(c):
			continue
		placed.append([p, rng.randf_range(0.08, 0.2)])

	var buckets: Array = []
	for v in ROCK_VARIANTS:
		buckets.append([])
	for item in placed:
		buckets[rng.randi() % ROCK_VARIANTS].append(item)
	var mat := _rock_material()
	for v in ROCK_VARIANTS:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _rock_mesh(4242 + v * 31)
		mm.instance_count = buckets[v].size()
		for i in buckets[v].size():
			var pos: Vector2 = buckets[v][i][0]
			var size: float = buckets[v][i][1]
			var basis := Basis(Vector3.UP, rng.randf() * TAU) \
				* Basis(Vector3.RIGHT, rng.randf_range(-0.2, 0.2)) \
				* Basis.from_scale(Vector3(rng.randf_range(0.8, 1.3), rng.randf_range(0.6, 1.1),
					rng.randf_range(0.8, 1.3)) * size)
			mm.set_instance_transform(i, Transform3D(basis, Vector3(pos.x, -size * 0.22, pos.y)))
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		inst.material_override = mat
		add_child(inst)


func _rock_size(rng: RandomNumberGenerator, row: int) -> float:
	# The row nearest the field is lower, the far rows are big boulders.
	return rng.randf_range(0.7, 1.2) + row * rng.randf_range(0.4, 0.8)


## Boulder: a sphere dented by noise and flattened at the bottom, with flat facets.
func _rock_mesh(seed: int) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 1.6
	noise.fractal_octaves = 3
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 12
	sphere.rings = 7
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var cuts: Array[Vector3] = []
	for i in 3:
		cuts.append(Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 1), rng.randf_range(-1, 1)).normalized())
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	# Identical seam points must move the same way, otherwise the rock gets holes.
	for i in verts.size():
		var v := verts[i]
		var n := v.normalized() if v.length() > 0.0001 else Vector3.UP
		var k := 1.0 + noise.get_noise_3dv(n * 1.3) * 0.35
		v = n * 0.5 * k
		# Chips: cut the boulder with a few planes to get flat facets.
		for cut in cuts:
			var depth := v.dot(cut) - 0.4
			if depth > 0.0:
				v -= cut * depth
		if v.y < -0.15:
			v.y = -0.15 + (v.y + 0.15) * 0.3
		verts[i] = v
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in idx:
		st.add_vertex(verts[i])
	st.generate_normals()
	return st.commit()


func _rock_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode diffuse_burley;
uniform float shade = 1.0;
varying vec3 wpos;
varying vec3 wnorm;
float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	float n = noise(wpos * 3.0) * 0.5 + noise(wpos * 9.0) * 0.3 + noise(wpos * 27.0) * 0.2;
	// Rock strata by height and lichen/scale patches.
	float strata = sin(wpos.y * 18.0 + noise(wpos * 1.5) * 6.0) * 0.5 + 0.5;
	vec3 stone = mix(vec3(0.13, 0.12, 0.11), vec3(0.26, 0.23, 0.2), n);
	stone = mix(stone, stone * 0.75, strata * 0.35);
	stone = mix(stone, vec3(0.3, 0.22, 0.14), smoothstep(0.62, 0.8, noise(wpos * 2.2 + 5.0)) * 0.6);
	// Sand blown onto the top of the rocks; shadow and dust at the bottom near the ground.
	float top = smoothstep(0.75, 0.98, wnorm.y + (n - 0.5) * 0.3);
	stone = mix(stone, vec3(0.42, 0.32, 0.2), top * 0.35);
	stone = mix(stone, vec3(0.36, 0.27, 0.17), (1.0 - smoothstep(0.0, 0.2, wpos.y)) * 0.4);
	ALBEDO = stone * shade * 1.25;
	ROUGHNESS = 0.92 - top * 0.05;
	// Small pits: perturb the normal with noise.
	vec3 bump = vec3(noise(wpos * 14.0), noise(wpos * 14.0 + 3.1), noise(wpos * 14.0 + 7.7)) - 0.5;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(bump * 0.35, 0.0)).xyz);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	return mat


func _make_unit(u: SimUnit) -> Node3D:
	var root := Node3D.new()
	var f: Dictionary = FACTIONS[factions[u.team]]
	_faction = factions[u.team]
	_body = f.body
	_dark = f.dark
	_angular = f.angular
	var col: Color = f.accent

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	var r := 0.36
	if u.type == "turret":
		r = 0.62
	elif u.is_structure():
		r = 1.3
	elif u.type == "tank" or u.type == "harvester":
		r = 0.62
	torus.inner_radius = r
	torus.outer_radius = r + 0.06
	ring.mesh = torus
	ring.name = "Ring"
	ring.position.y = 0.03
	ring.scale.y = 0.2
	ring.material_override = _plain_mat(Color(1, 1, 1))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)

	root.set_meta("kind", u.type)
	root.set_meta("structure", u.is_structure())
	match u.type:
		"tank": _make_tank(root, col)
		"harvester": _make_harvester(root, col)
		"hq", "barracks", "factory", "turret": _make_building(root, u.type, col)
		_: _make_soldier(root, u.type, col)
	_faction = "empire"
	_body = EMPIRE_BODY
	_dark = EMPIRE_DARK
	_angular = false
	return root


func _make_tank(root: Node3D, col: Color) -> void:
	var hull := Node3D.new()
	hull.name = "Hull"
	hull.scale = Vector3.ONE * 1.15
	root.add_child(hull)
	var links: Array = []
	var wheels: Array = []
	for side in [-1.0, 1.0]:
		var z: float = 0.3 * side
		hull.add_child(_capsule_x(TRACK_R - 0.015, 2.0 * (TRACK_A + TRACK_R), Vector3(0, TRACK_Y, z), _dark))
		for i in 4:
			var pivot := Node3D.new()
			pivot.position = Vector3(-0.3 + 0.2 * i, TRACK_Y, z + 0.08 * side)
			hull.add_child(pivot)
			var disc := _cyl(0.075, 0.04, Vector3.ZERO, Color(0.1, 0.1, 0.09))
			disc.rotation.x = PI / 2
			pivot.add_child(disc)
			pivot.add_child(_box(Vector3(0.13, 0.025, 0.05), Vector3(0, 0, 0.0), Color(0.3, 0.28, 0.24)))
			wheels.append(pivot)
		for i in 12:
			var link := _box(Vector3(0.05, 0.03, 0.2), Vector3(0, TRACK_Y, z), Color(0.04, 0.04, 0.035))
			hull.add_child(link)
			links.append(link)
	# Hull: the lower part between the tracks, a sloped glacis plate, fenders over the tracks,
	# an engine deck with a grille and an exhaust at the back.
	hull.add_child(_box(Vector3(0.86, 0.16, 0.44), Vector3(0, 0.2, 0), _body))
	var glacis := _box(Vector3(0.26, 0.04, 0.44), Vector3(0.5, 0.26, 0), _body)
	glacis.rotation.z = -0.55
	hull.add_child(glacis)
	hull.add_child(_box(Vector3(0.78, 0.07, 0.62), Vector3(-0.02, 0.31, 0), _body.lightened(0.03)))
	for side in [-1.0, 1.0]:
		hull.add_child(_box(Vector3(0.98, 0.025, 0.17), Vector3(0, 0.28, 0.31 * side), _dark))
		hull.add_child(_box(Vector3(0.9, 0.09, 0.02), Vector3(0, 0.22, 0.395 * side), _body))
		hull.add_child(_box(Vector3(0.5, 0.025, 0.006), Vector3(0.05, 0.22, 0.405 * side), col))
		hull.add_child(_box(Vector3(0.12, 0.05, 0.08), Vector3(-0.15, 0.315, 0.31 * side), Color(0.09, 0.085, 0.07)))
	for i in 4:
		hull.add_child(_box(Vector3(0.02, 0.012, 0.36), Vector3(-0.25 - i * 0.04, 0.35, 0), _dark))
	var exhaust := _cyl(0.025, 0.12, Vector3(-0.45, 0.33, 0.18), Color(0.12, 0.08, 0.05))
	exhaust.rotation.z = PI / 2
	hull.add_child(exhaust)
	for z in [-0.14, 0.14]:
		hull.add_child(_sphere(0.025, Vector3(0.56, 0.31, z), Color(0.7, 0.65, 0.5)))
	root.set_meta("links", links)
	root.set_meta("wheels", wheels)
	var dust := effects.track_dust()
	dust.name = "Dust"
	dust.position = Vector3(-0.45, 0.05, 0)
	hull.add_child(dust)

	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position.y = 0.5
	turret.scale = Vector3.ONE * 1.15
	root.add_child(turret)
	# Cast turret: a flattened body with a sloped front, a gun mantlet, a long barrel
	# with a muzzle brake, a commander's cupola, a stowage box at the back and an antenna.
	var cast := _sphere(0.23, Vector3(0.0, 0.0, 0), _body.lightened(0.06))
	cast.scale = Vector3(1.25, 0.45, 1.0)
	turret.add_child(cast)
	turret.add_child(_box(Vector3(0.3, 0.1, 0.36), Vector3(-0.05, 0.0, 0), _body.lightened(0.06)))
	turret.add_child(_box(Vector3(0.18, 0.08, 0.3), Vector3(-0.27, 0.0, 0), _dark))
	turret.add_child(_box(Vector3(0.36, 0.015, 0.005), Vector3(-0.05, 0.0, 0.181), col))
	turret.add_child(_box(Vector3(0.36, 0.015, 0.005), Vector3(-0.05, 0.0, -0.181), col))
	turret.add_child(_box(Vector3(0.08, 0.09, 0.12), Vector3(0.27, 0.0, 0), _dark))
	turret.add_child(_capsule_x(0.028, 0.62, Vector3(0.58, 0.0, 0), Color(0.1, 0.1, 0.095)))
	var brake := _cyl(0.04, 0.08, Vector3(0.9, 0.0, 0), Color(0.07, 0.07, 0.065))
	brake.rotation.z = PI / 2
	turret.add_child(brake)
	turret.add_child(_cyl(0.06, 0.06, Vector3(-0.08, 0.09, 0.08), _body))
	turret.add_child(_cyl(0.065, 0.015, Vector3(-0.08, 0.125, 0.08), _dark))
	turret.add_child(_cyl(0.006, 0.5, Vector3(-0.25, 0.3, -0.1), Color(0.1, 0.1, 0.1)))
	for side in [-1.0, 1.0]:
		var emblem := _cyl(0.045, 0.01, Vector3(-0.08, 0.0, 0.187 * side), col if _faction == "empire" else col.darkened(0.2))
		emblem.rotation.x = PI / 2
		turret.add_child(emblem)


func _make_harvester(root: Node3D, col: Color) -> void:
	var hull := Node3D.new()
	hull.name = "Hull"
	hull.scale = Vector3.ONE * 1.1
	root.add_child(hull)
	var dust := effects.track_dust()
	dust.name = "Dust"
	dust.position = Vector3(-0.42, 0.05, 0)
	hull.add_child(dust)
	var wheels: Array = []
	for side in [-1.0, 1.0]:
		for i in 3:
			var pivot := Node3D.new()
			pivot.position = Vector3(-0.32 + 0.32 * i, 0.14, 0.3 * side)
			hull.add_child(pivot)
			var tyre := _cyl(0.14, 0.1, Vector3.ZERO, Color(0.05, 0.05, 0.05))
			tyre.rotation.x = PI / 2
			pivot.add_child(tyre)
			var hub := _box(Vector3(0.2, 0.04, 0.11), Vector3.ZERO, Color(0.32, 0.3, 0.26))
			pivot.add_child(hub)
			wheels.append(pivot)
	# A six-wheel frame, a glazed cab at the front, a hopper body at the back,
	# a collector scoop over the front, an exhaust pipe behind the cab.
	hull.add_child(_box(Vector3(1.0, 0.1, 0.42), Vector3(0, 0.22, 0), _dark))
	for side in [-1.0, 1.0]:
		hull.add_child(_box(Vector3(1.0, 0.03, 0.14), Vector3(0, 0.3, 0.3 * side), _body))
	hull.add_child(_box(Vector3(0.3, 0.26, 0.5), Vector3(0.33, 0.43, 0), _body.lightened(0.05)))
	var glass := _box(Vector3(0.02, 0.1, 0.42), Vector3(0.485, 0.48, 0), Color(0.2, 0.32, 0.36))
	glass.rotation.z = 0.25
	hull.add_child(glass)
	hull.add_child(_box(Vector3(0.2, 0.08, 0.02), Vector3(0.36, 0.48, 0.251), Color(0.2, 0.32, 0.36)))
	hull.add_child(_box(Vector3(0.2, 0.08, 0.02), Vector3(0.36, 0.48, -0.251), Color(0.2, 0.32, 0.36)))
	hull.add_child(_box(Vector3(0.1, 0.03, 0.62), Vector3(0.6, 0.18, 0), Color(0.22, 0.2, 0.16)))
	hull.add_child(_cyl(0.025, 0.3, Vector3(0.15, 0.58, 0.2), Color(0.12, 0.08, 0.05)))
	var hopper := _box(Vector3(0.58, 0.24, 0.56), Vector3(-0.17, 0.42, 0), _body)
	hull.add_child(hopper)
	for side in [-1.0, 1.0]:
		hull.add_child(_box(Vector3(0.58, 0.04, 0.006), Vector3(-0.17, 0.48, 0.283 * side), col))
		for i in 3:
			hull.add_child(_box(Vector3(0.02, 0.22, 0.015), Vector3(-0.38 + i * 0.2, 0.42, 0.285 * side), _dark))
	# Load: a heap of crystal shards in the hopper.
	var load := Node3D.new()
	load.name = "Load"
	load.position = Vector3(-0.17, 0.58, 0)
	hull.add_child(load)
	var lr := RandomNumberGenerator.new()
	lr.seed = 77
	for i in 9:
		var shard := _cyl(0.0, lr.randf_range(0.16, 0.26), Vector3(lr.randf_range(-0.2, 0.2), 0.05,
			lr.randf_range(-0.2, 0.2)), CRYSTAL_COLOR)
		var cm := shard.mesh as CylinderMesh
		cm.top_radius = 0.0
		cm.bottom_radius = lr.randf_range(0.03, 0.05)
		cm.radial_segments = 5
		shard.rotation = Vector3(lr.randf_range(-0.7, 0.7), lr.randf() * TAU, lr.randf_range(-0.7, 0.7))
		shard.material_override = _crystal_mat()
		load.add_child(shard)
	root.set_meta("wheels", wheels)


func _make_soldier(root: Node3D, type: String, col: Color) -> void:
	# Human proportions: the legs are almost half the height, the head about one seventh.
	# Knees and elbows are separate nodes so the stride and the firing stance look alive.
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var armor := _body.lightened(0.06)
	var boot := Color(0.05, 0.045, 0.04)
	var skin := Color(0.55, 0.43, 0.34)
	for leg_name in ["LegL", "LegR"]:
		var hip := Node3D.new()
		hip.name = leg_name
		hip.position = Vector3(0, 0.37, -0.045 if leg_name == "LegL" else 0.045)
		body.add_child(hip)
		hip.add_child(_capsule(0.04, 0.2, Vector3(0, -0.095, 0), _dark))
		var knee := Node3D.new()
		knee.name = "Knee"
		knee.position.y = -0.185
		hip.add_child(knee)
		knee.add_child(_capsule(0.034, 0.17, Vector3(0, -0.085, 0), _dark.lightened(0.03)))
		knee.add_child(_capsule(0.04, 0.08, Vector3(0, -0.15, 0), boot))
		var toe := _sphere(0.036, Vector3(0.035, -0.175, 0), boot)
		toe.scale = Vector3(1.6, 0.55, 1.0)
		knee.add_child(toe)
	var torso := Node3D.new()
	torso.name = "Torso"
	body.add_child(torso)
	# Pelvis, chest in body armor, a belt with pouches, a backpack.
	torso.add_child(_box(Vector3(0.11, 0.07, 0.15), Vector3(0, 0.39, 0), _dark))
	torso.add_child(_capsule(0.072, 0.25, Vector3(0, 0.5, 0), _body))
	var vest := _box(Vector3(0.13, 0.17, 0.165), Vector3(0.008, 0.51, 0), armor)
	torso.add_child(vest)
	torso.add_child(_team_band(0.07, 0.092, Vector3(0, 0.45, 0), Vector3(1, 0.6, 1), col))
	torso.add_child(_cyl(0.083, 0.03, Vector3(0, 0.405, 0), Color(0.08, 0.07, 0.05)))
	for z in [-0.045, 0.0, 0.045]:
		torso.add_child(_box(Vector3(0.025, 0.04, 0.035), Vector3(0.075, 0.5, z), Color(0.12, 0.11, 0.08)))
	if type != "medic" and type != "engineer":
		torso.add_child(_box(Vector3(0.07, 0.13, 0.12), Vector3(-0.1, 0.52, 0), _dark))
		torso.add_child(_capsule_x(0.025, 0.13, Vector3(-0.1, 0.6, 0), Color(0.2, 0.19, 0.14)))
	# Head: neck, face, a helmet with a chin strap and a dark visor.
	var head := Node3D.new()
	head.name = "Head"
	head.position.y = 0.635
	torso.add_child(head)
	head.add_child(_cyl(0.022, 0.04, Vector3(0, 0.0, 0), skin.darkened(0.1)))
	head.add_child(_sphere(0.04, Vector3(0.008, 0.045, 0), skin))
	if type == "engineer":
		var cap := _sphere(0.052, Vector3(-0.003, 0.07, 0), Color(0.75, 0.42, 0.08))
		cap.scale = Vector3(1.15, 0.62, 1.1)
		head.add_child(cap)
		head.add_child(_cyl(0.06, 0.006, Vector3(0.0, 0.058, 0), Color(0.75, 0.42, 0.08)))
	else:
		var helmet := _sphere(0.05, Vector3(-0.004, 0.068, 0), armor)
		helmet.scale = Vector3(1.08, 0.8, 1.04)
		head.add_child(helmet)
		head.add_child(_box(Vector3(0.012, 0.016, 0.06), Vector3(0.046, 0.05, 0), Color(0.05, 0.08, 0.09)))
	if type == "medic":
		head.add_child(_box(Vector3(0.075, 0.02, 0.004), Vector3(0, 0.072, 0.052), Color(0.75, 0.74, 0.7)))
	for arm_name in ["ArmL", "ArmR"]:
		var side := -1.0 if arm_name == "ArmL" else 1.0
		var shoulder := Node3D.new()
		shoulder.name = arm_name
		shoulder.position = Vector3(0, 0.595, 0.092 * side)
		torso.add_child(shoulder)
		var pad := _sphere(0.038, Vector3(0, 0.0, 0.006 * side), armor)
		pad.scale = Vector3(1.1, 0.75, 1.0)
		shoulder.add_child(pad)
		shoulder.add_child(_capsule(0.026, 0.15, Vector3(0, -0.07, 0), _body))
		shoulder.add_child(_team_band(0.024, 0.033, Vector3(0, -0.06, 0), Vector3(1, 0.4, 1), col))
		var elbow := Node3D.new()
		elbow.name = "Elbow"
		elbow.position.y = -0.14
		shoulder.add_child(elbow)
		elbow.add_child(_capsule(0.024, 0.13, Vector3(0, -0.065, 0), armor))
		elbow.add_child(_sphere(0.02, Vector3(0.0, -0.135, 0), skin))
	# The Gun node holds the weapon: lowered at the hip on the move, raised to the shoulder when firing.
	var gun := Node3D.new()
	gun.name = "Gun"
	gun.position = Vector3(0.07, 0.47, 0.04)
	torso.add_child(gun)
	var metal := Color(0.08, 0.08, 0.075)
	match type:
		"grenadier":
			gun.position = Vector3(0.0, 0.6, 0.075)
			gun.add_child(_capsule_x(0.03, 0.42, Vector3(0.05, 0.0, 0), Color(0.14, 0.15, 0.11)))
			gun.add_child(_box(Vector3(0.05, 0.035, 0.016), Vector3(0.1, 0.035, 0.03), Color(0.06, 0.06, 0.06)))
			var bell := _cyl(0.038, 0.05, Vector3(-0.17, 0.0, 0), Color(0.07, 0.07, 0.06))
			bell.rotation.z = PI / 2
			gun.add_child(bell)
			var warhead := _sphere(0.034, Vector3(0.27, 0.0, 0), Color(0.2, 0.22, 0.14))
			warhead.scale = Vector3(1.6, 1, 1)
			gun.add_child(warhead)
		"medic":
			# No weapon: a bag with a cross on the back and a first-aid kit in hand.
			torso.add_child(_box(Vector3(0.08, 0.13, 0.13), Vector3(-0.1, 0.52, 0), Color(0.75, 0.74, 0.7)))
			torso.add_child(_box(Vector3(0.004, 0.07, 0.022), Vector3(-0.142, 0.53, 0), Color(0.15, 0.6, 0.25)))
			torso.add_child(_box(Vector3(0.004, 0.022, 0.07), Vector3(-0.142, 0.53, 0), Color(0.15, 0.6, 0.25)))
			gun.position = Vector3(0.0, 0.4, 0.12)
			gun.add_child(_box(Vector3(0.08, 0.055, 0.035), Vector3.ZERO, Color(0.75, 0.74, 0.7)))
		"engineer":
			torso.add_child(_box(Vector3(0.08, 0.11, 0.14), Vector3(-0.1, 0.51, 0), Color(0.45, 0.3, 0.08)))
			torso.add_child(_cyl(0.018, 0.15, Vector3(-0.1, 0.62, 0.04), Color(0.3, 0.3, 0.28)))
			gun.add_child(_capsule_x(0.01, 0.2, Vector3(0.08, 0.0, 0), Color(0.15, 0.15, 0.14)))
			gun.add_child(_sphere(0.016, Vector3(0.19, 0.0, 0), Color(0.9, 0.6, 0.2)))
		_:
			# Rifle: barrel, receiver, magazine, stock and handguard.
			gun.add_child(_capsule_x(0.008, 0.16, Vector3(0.22, 0.012, 0), metal))
			gun.add_child(_box(Vector3(0.16, 0.035, 0.022), Vector3(0.08, 0.0, 0), Color(0.12, 0.11, 0.09)))
			var mag := _box(Vector3(0.022, 0.06, 0.015), Vector3(0.09, -0.04, 0), metal)
			mag.rotation.z = 0.25
			gun.add_child(mag)
			gun.add_child(_box(Vector3(0.09, 0.04, 0.018), Vector3(-0.04, -0.008, 0), Color(0.2, 0.14, 0.08)))
	gun.set_meta("rest", gun.position)


## 2×2-cell buildings: rounded dark bodies, team color on the rings.
func _make_building(root: Node3D, type: String, col: Color) -> void:
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var pad := Color(0.1, 0.095, 0.085)
	match type:
		"barracks": body.add_child(_box(Vector3(2.3, 0.12, 1.15), Vector3(0, 0.06, 0), pad))
		"turret": body.add_child(_cyl(0.5, 0.12, Vector3(0, 0.06, 0), pad))
		_: body.add_child(_cyl(0.98, 0.12, Vector3(0, 0.06, 0), pad))
	match type:
		"hq":
			var dome := _sphere(0.8, Vector3(0, 0.12, 0), _body.lightened(0.04))
			dome.scale = Vector3(1.0, 0.75, 1.0)
			body.add_child(dome)
			body.add_child(_team_band(0.78, 0.86, Vector3(0, 0.2, 0), Vector3(1, 0.4, 1), col))
			body.add_child(_cyl(0.03, 1.1, Vector3(0.2, 1.0, 0.2), Color(0.1, 0.1, 0.1)))
			body.add_child(_sphere(0.06, Vector3(0.2, 1.56, 0.2), col.lightened(0.3)))
			# Windows around the dome.
			for i in 8:
				var ang := TAU * i / 8.0 + 0.2
				var frame := _box(Vector3(0.05, 0.13, 0.19), Vector3(cos(ang) * 0.69, 0.4, sin(ang) * 0.69), _dark)
				frame.rotation.y = -ang
				frame.rotation.z = 0.6
				body.add_child(frame)
				var win := _box(Vector3(0.03, 0.09, 0.14), Vector3(0.02, 0, 0), Color.WHITE)
				win.material_override = _window_mat()
				frame.add_child(win)
			# The side's banner on a flagpole.
			body.add_child(_cyl(0.02, 1.5, Vector3(-0.55, 0.75, 0.5), _dark))
			var flag := _box(Vector3(0.34, 0.22, 0.015), Vector3(-0.37, 1.35, 0.5), col)
			body.add_child(flag)
			if _faction == "empire":
				# Imperial emblem: a dark circle with a red diamond star on the banner and above the entrance.
				body.add_child(_cyl(0.07, 0.02, Vector3(-0.37, 1.35, 0.51), _dark))
				var star := _box(Vector3(0.07, 0.07, 0.02), Vector3(-0.37, 1.35, 0.52), col.lightened(0.2))
				star.rotation.z = PI / 4
				body.add_child(star)
				body.add_child(_sphere(0.05, Vector3(-0.55, 1.52, 0.5), Color(0.6, 0.48, 0.2)))
			# An entrance with a canopy, sandbags at the entrance, a guyed radio mast.
			body.add_child(_box(Vector3(0.3, 0.32, 0.36), Vector3(0.82, 0.22, 0), _body))
			body.add_child(_box(Vector3(0.04, 0.24, 0.2), Vector3(0.975, 0.2, 0), Color(0.03, 0.03, 0.03)))
			body.add_child(_box(Vector3(0.36, 0.03, 0.44), Vector3(0.86, 0.4, 0), _dark))
			for z in [-0.3, -0.18, 0.18, 0.3]:
				var bag := _capsule_x(0.06, 0.22, Vector3(1.05, 0.08, z), Color(0.38, 0.32, 0.22))
				bag.rotation.y = PI / 2
				body.add_child(bag)
			var dish := _sphere(0.22, Vector3(-0.35, 0.75, -0.2), _dark)
			dish.scale = Vector3(1.0, 0.3, 1.0)
			body.add_child(dish)
		"barracks":
			# A long narrow hangar-style barracks along the x axis.
			var hut := _capsule_x(0.42, 2.25, Vector3(0, 0.15, 0), _body)
			hut.scale = Vector3(1.0, 0.95, 1.0)
			body.add_child(hut)
			for x in [-0.75, -0.25, 0.25, 0.75]:
				var rib := _team_band(0.38, 0.44, Vector3(x, 0.15, 0), Vector3(1.0, 0.15, 1.0), col)
				rib.rotation.z = PI / 2
				body.add_child(rib)
			for side in [-1.0, 1.0]:
				for x in [-0.9, -0.5, 0.0, 0.5, 0.9]:
					var frame := _box(Vector3(0.18, 0.12, 0.05), Vector3(x, 0.34, 0.33 * side), _dark)
					frame.rotation.x = -0.6 * side
					body.add_child(frame)
					var win := _box(Vector3(0.13, 0.08, 0.03), Vector3(0, 0, 0.02 * side), Color.WHITE)
					win.material_override = _window_mat()
					frame.add_child(win)
			var door := _sphere(0.17, Vector3(1.12, 0.2, 0), Color(0.04, 0.04, 0.04))
			door.scale = Vector3(0.3, 1.0, 1.0)
			body.add_child(door)
			body.add_child(_box(Vector3(0.1, 0.5, 0.06), Vector3(-1.05, 0.55, 0.0), _dark))
		"turret":
			# An octagonal concrete base and an armored rotating turret with twin barrels.
			var base := _cyl(0.4, 0.38, Vector3(0, 0.25, 0), Color(0.2, 0.19, 0.17))
			(base.mesh as CylinderMesh).radial_segments = 8
			(base.mesh as CylinderMesh).bottom_radius = 0.46
			body.add_child(base)
			body.add_child(_team_band(0.36, 0.42, Vector3(0, 0.42, 0), Vector3(1, 0.35, 1), col))
			var head := Node3D.new()
			head.name = "Turret"
			head.position.y = 0.55
			body.add_child(head)
			var dome := _sphere(0.3, Vector3.ZERO, _body)
			dome.scale = Vector3(1.15, 0.6, 1.0)
			head.add_child(dome)
			head.add_child(_box(Vector3(0.34, 0.16, 0.36), Vector3(0.1, 0.02, 0), _dark))
			for z in [-0.07, 0.07]:
				head.add_child(_capsule_x(0.035, 0.6, Vector3(0.48, 0.03, z), Color(0.1, 0.1, 0.1)))
				head.add_child(_cyl(0.045, 0.08, Vector3(0.78, 0.03, z), Color(0.06, 0.06, 0.06)))
			head.get_child(head.get_child_count() - 1).rotation.z = PI / 2
			head.get_child(head.get_child_count() - 3).rotation.z = PI / 2
			head.add_child(_sphere(0.05, Vector3(-0.12, 0.17, 0.12), col.lightened(0.3)))
		"factory":
			# The factory is angular: a rectangular workshop, a sawtooth roof, smoking chimneys.
			body.add_child(_box(Vector3(1.85, 0.7, 1.5), Vector3(0.05, 0.47, 0), _body))
			body.add_child(_box(Vector3(1.9, 0.08, 1.55), Vector3(0.05, 0.86, 0), _dark))
			for i in 3:
				var tooth := _box(Vector3(0.5, 0.05, 1.5), Vector3(-0.55 + 0.6 * i, 1.0, 0), _body.lightened(0.05))
				tooth.rotation.z = deg_to_rad(28)
				body.add_child(tooth)
				body.add_child(_box(Vector3(0.04, 0.26, 1.5), Vector3(-0.33 + 0.6 * i, 1.0, 0), Color(0.35, 0.33, 0.2)))
			body.add_child(_box(Vector3(1.86, 0.08, 1.52), Vector3(0.05, 0.62, 0), col))
			body.add_child(_box(Vector3(0.06, 0.5, 0.9), Vector3(0.98, 0.37, 0), Color(0.03, 0.03, 0.03)))
			body.add_child(_box(Vector3(0.5, 0.5, 0.5), Vector3(-0.7, 0.37, 0.75), _dark))
			for z in [-0.45, 0.45]:
				body.add_child(_box(Vector3(0.22, 1.1, 0.22), Vector3(-0.6, 1.25, z), _dark))
				body.add_child(_box(Vector3(0.26, 0.06, 0.26), Vector3(-0.6, 1.78, z), Color(0.2, 0.18, 0.15)))
				var smoke := _smoke()
				smoke.name = "Smoke"
				smoke.position = Vector3(-0.6, 1.85, z)
				body.add_child(smoke)


func _smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 18
	p.lifetime = 3.0
	p.preprocess = 3.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.06
	p.direction = Vector3(0.3, 1, 0)
	p.spread = 12.0
	p.gravity = Vector3(0.15, 0.25, 0)
	p.initial_velocity_min = 0.25
	p.initial_velocity_max = 0.45
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.35))
	curve.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.18, 0.17, 0.16, 0.7))
	grad.set_color(1, Color(0.3, 0.28, 0.26, 0.0))
	p.color_ramp = grad
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	mesh.radial_segments = 8
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	p.mesh = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _make_crystals(c: Vector2i) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(c.x + 0.5, 0, c.y + 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = c.x * 73856093 ^ c.y * 19349663
	for i in rng.randi_range(3, 5):
		var m := MeshInstance3D.new()
		var prism := CylinderMesh.new()
		prism.top_radius = 0.0
		prism.bottom_radius = rng.randf_range(0.06, 0.11)
		prism.height = rng.randf_range(0.25, 0.5)
		prism.radial_segments = 6
		prism.rings = 1
		m.mesh = prism
		m.material_override = _crystal_mat()
		m.position = Vector3(rng.randf_range(-0.3, 0.3), prism.height * 0.45, rng.randf_range(-0.3, 0.3))
		m.rotation = Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4))
		root.add_child(m)
	return root


func _team_band(inner: float, outer: float, pos: Vector3, scl: Vector3, col: Color) -> MeshInstance3D:
	var band := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	if _angular:
		mesh.ring_segments = 4
		mesh.rings = 6
	band.mesh = mesh
	band.position = pos
	band.scale = scl
	band.material_override = _mat(col)
	return band


func _window_mat() -> StandardMaterial3D:
	if not _materials.has("window"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.55, 0.4, 0.2)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.62, 0.25)
		m.emission_energy_multiplier = 0.55
		_materials["window"] = m
	return _materials["window"]


func _crystal_mat() -> StandardMaterial3D:
	if not _materials.has("crystal"):
		var m := StandardMaterial3D.new()
		m.albedo_color = CRYSTAL_COLOR.darkened(0.35)
		m.emission_enabled = true
		m.emission = CRYSTAL_COLOR.darkened(0.2)
		m.emission_energy_multiplier = 0.45
		m.roughness = 0.2
		m.metallic_specular = 0.9
		_materials["crystal"] = m
	return _materials["crystal"]


func _box(size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = pos
	m.material_override = _mat(col)
	return m


func _cyl(radius: float, height: float, pos: Vector3, col: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 6 if _angular else 16
	m.mesh = c
	m.position = pos
	m.material_override = _mat(col)
	return m


func _sphere(radius: float, pos: Vector3, col: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 6 if _angular else 16
	s.rings = 3 if _angular else 8
	m.mesh = s
	m.position = pos
	m.material_override = _mat(col)
	return m


func _capsule(radius: float, height: float, pos: Vector3, col: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = maxf(height, radius * 2.0)
	c.radial_segments = 6 if _angular else 16
	c.rings = 1 if _angular else 4
	m.mesh = c
	m.position = pos
	m.material_override = _mat(col)
	return m


## A capsule lying along the X axis (forward for a unit).
func _capsule_x(radius: float, length: float, pos: Vector3, col: Color) -> MeshInstance3D:
	var m := _capsule(radius, length, pos, col)
	m.rotation.z = PI / 2
	return m


## Shared material for vehicles and buildings: painted metal with grime, dust on top,
## streaks and darkening near the ground. One shader, only the paint color changes.
const PAINT_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec3 paint : source_color;
varying vec3 lpos;
varying vec3 wpos;
varying vec3 wnorm;
float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() {
	lpos = VERTEX;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	float n = noise(lpos * 4.0) * 0.6 + noise(lpos * 11.0) * 0.4;
	vec3 col = paint * (0.88 + 0.24 * n);
	// Grime streaks running down and paint chips down to dark metal.
	float streak = noise(vec3(lpos.x * 30.0, lpos.y * 3.0, lpos.z * 30.0));
	col = mix(col, col * 0.6, smoothstep(0.55, 0.85, streak) * 0.5);
	float chip = smoothstep(0.8, 0.84, noise(lpos * 17.0 + 3.0));
	col = mix(col, col * 0.55, chip * 0.5);
	// Wasteland dust on horizontal surfaces and near the ground.
	float up = smoothstep(0.5, 0.95, wnorm.y);
	vec3 dust = vec3(0.42, 0.33, 0.22);
	col = mix(col, dust, up * (0.1 + 0.15 * n));
	col = mix(col, dust * 0.8, (1.0 - smoothstep(0.0, 0.2, wpos.y)) * 0.3);
	ALBEDO = col;
	METALLIC = mix(0.35, 0.7, chip);
	ROUGHNESS = clamp(0.55 + 0.3 * n + up * 0.2 - chip * 0.2, 0.0, 1.0);
	SPECULAR = 0.45;
}
"""
var _paint_shader: Shader


func _mat(col: Color) -> Material:
	var key := col.to_html()
	if not _materials.has(key):
		if _paint_shader == null:
			_paint_shader = Shader.new()
			_paint_shader.code = PAINT_SHADER
		var m := ShaderMaterial.new()
		m.shader = _paint_shader
		m.set_shader_parameter("paint", col)
		_materials[key] = m
	return _materials[key]


func _plain_mat(col: Color) -> StandardMaterial3D:
	var key := "plain" + col.to_html()
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_materials[key] = m
	return _materials[key]
