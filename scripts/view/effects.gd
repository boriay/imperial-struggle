class_name Effects
extends Node3D

## Explosions, muzzle flashes, dust, smoke and marks on the ground. All procedural:
## the soft smoke and fire sprite blobs are drawn into a texture at startup.

const SCORCH_LIFE := 40.0
const MAX_SCORCHES := 60

var _puff_tex: ImageTexture
var _scorch_tex: ImageTexture
var _smoke_mat: StandardMaterial3D
var _fire_mat: StandardMaterial3D
var _flash_mat: StandardMaterial3D
var _debris_mat: StandardMaterial3D
var _scorch_mat: StandardMaterial3D
var _live: Array = []  # {node, life, kind}
var _scorches: Array = []
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 42
	_puff_tex = _make_puff()
	_scorch_tex = _make_scorch()
	_smoke_mat = _particle_mat(_puff_tex, false)
	_fire_mat = _particle_mat(_puff_tex, true)
	_flash_mat = _particle_mat(_puff_tex, true)
	_debris_mat = StandardMaterial3D.new()
	_debris_mat.albedo_color = Color(0.12, 0.11, 0.1)
	_debris_mat.roughness = 1.0
	_scorch_mat = StandardMaterial3D.new()
	_scorch_mat.albedo_texture = _scorch_tex
	_scorch_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_scorch_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_scorch_mat.vertex_color_use_as_albedo = true
	_scorch_mat.albedo_color = Color(1, 1, 1, 1)


func _process(delta: float) -> void:
	for e in _live:
		e.life -= delta
		if e.has("light"):
			var l: OmniLight3D = e.light
			l.light_energy = maxf(0.0, l.light_energy - delta * e.fade)
		if e.life <= 0.0:
			e.node.queue_free()
	_live = _live.filter(func(e): return e.life > 0.0)
	for s in _scorches:
		s.life -= delta
		var m: MeshInstance3D = s.node
		var mat: StandardMaterial3D = m.material_override
		mat.albedo_color.a = clampf(s.life / 8.0, 0.0, 1.0) * s.alpha
		if s.life <= 0.0:
			m.queue_free()
	_scorches = _scorches.filter(func(s): return s.life > 0.0)


## Explosion: a flash of light, a fireball, smoke clouds, flying debris and soot on the ground.
func explosion(p: Vector2, size: float) -> void:
	var at := Vector3(p.x, 0.05, p.y)
	var root := Node3D.new()
	root.position = at
	add_child(root)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.65, 0.3)
	light.light_energy = 3.0 * size
	light.omni_range = 3.0 + size * 2.0
	light.position.y = 0.6
	root.add_child(light)

	var fire := _burst(_fire_mat, 14 + int(size * 8), 0.55 + size * 0.15, 0.15 * size,
		Vector3(0, 1, 0), 70.0, 0.8 * size, 1.8 * size, Vector3(0, 0.6, 0), 0.5 * size, 1.3 * size)
	var fg := Gradient.new()
	fg.offsets = PackedFloat32Array([0.0, 0.15, 0.5, 1.0])
	fg.colors = PackedColorArray([Color(1.0, 0.95, 0.75, 1.0), Color(1.0, 0.6, 0.15, 0.95),
		Color(0.55, 0.18, 0.04, 0.6), Color(0.1, 0.05, 0.02, 0.0)])
	fire.color_ramp = fg
	root.add_child(fire)

	var smoke := _burst(_smoke_mat, 16 + int(size * 10), 2.6 + size, 0.25 * size,
		Vector3(0, 1, 0), 35.0, 0.4 * size, 1.0 * size, Vector3(0.12, 0.35, 0), 0.8 * size, 2.2 * size)
	smoke.damping_min = 0.4
	smoke.damping_max = 0.8
	var sg := Gradient.new()
	sg.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	sg.colors = PackedColorArray([Color(0.12, 0.1, 0.09, 0.0), Color(0.16, 0.15, 0.14, 0.95), Color(0.38, 0.35, 0.32, 0.0)])
	smoke.color_ramp = sg
	root.add_child(smoke)

	var debris := CPUParticles3D.new()
	debris.one_shot = true
	debris.explosiveness = 1.0
	debris.amount = 4 + int(size * 4)
	debris.lifetime = 1.4
	debris.direction = Vector3(0, 1, 0)
	debris.spread = 60.0
	debris.initial_velocity_min = 2.0 * size
	debris.initial_velocity_max = 4.5 * size
	debris.gravity = Vector3(0, -9.8, 0)
	debris.angular_velocity_min = -400
	debris.angular_velocity_max = 400
	debris.scale_amount_min = 0.5
	debris.scale_amount_max = 1.4
	var dm := BoxMesh.new()
	dm.size = Vector3(0.035, 0.02, 0.03) * maxf(1.0, size * 0.8)
	dm.material = _debris_mat
	debris.mesh = dm
	debris.emitting = true
	root.add_child(debris)
	_live.append({"node": root, "life": 3.0 + size * 1.5, "light": light, "fade": 3.0 * size / 0.35})
	scorch(p, 0.6 + size * 0.7, 0.85)


## Muzzle flash and a puff of smoke. dir is the shot direction on the ground.
func muzzle(p: Vector2, height: float, dir: Vector2, size: float) -> void:
	var root := Node3D.new()
	root.position = Vector3(p.x, height, p.y)
	add_child(root)
	var flash := _burst(_flash_mat, 4, 0.07, 0.02, Vector3(dir.x, 0, dir.y), 15.0,
		0.5, 1.0, Vector3.ZERO, 0.18 * size, 0.3 * size)
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.9, 0.55, 1.0))
	g.set_color(1, Color(1.0, 0.45, 0.1, 0.0))
	flash.color_ramp = g
	root.add_child(flash)
	var puff := _burst(_smoke_mat, 3 + int(size * 3), 0.9 + size * 0.6, 0.03, Vector3(dir.x, 0.4, dir.y), 25.0,
		0.3 * size, 0.7 * size, Vector3(0, 0.3, 0), 0.12 * size, 0.45 * size)
	var pg := Gradient.new()
	pg.set_color(0, Color(0.6, 0.57, 0.52, 0.55))
	pg.set_color(1, Color(0.6, 0.57, 0.52, 0.0))
	puff.color_ramp = pg
	root.add_child(puff)
	var entry := {"node": root, "life": 2.0}
	if size >= 1.0:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.75, 0.4)
		light.light_energy = 1.6
		light.omni_range = 2.5
		root.add_child(light)
		entry.light = light
		entry.fade = 1.6 / 0.08
	_live.append(entry)


## A spurt of dust from a miss or a bullet hitting the ground.
func dust(p: Vector2, size: float) -> void:
	var root := Node3D.new()
	root.position = Vector3(p.x, 0.03, p.y)
	add_child(root)
	var d := _burst(_smoke_mat, 4 + int(size * 4), 0.9, 0.05 * size, Vector3(0, 1, 0), 40.0,
		0.4 * size, 1.1 * size, Vector3(0, -0.6, 0), 0.1 * size, 0.35 * size)
	var g := Gradient.new()
	g.set_color(0, Color(0.5, 0.42, 0.31, 0.7))
	g.set_color(1, Color(0.5, 0.42, 0.31, 0.0))
	d.color_ramp = g
	root.add_child(d)
	_live.append({"node": root, "life": 1.5})


## A dark soot mark on the ground that slowly fades.
func scorch(p: Vector2, radius: float, alpha: float) -> void:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * radius * 2.0
	q.orientation = PlaneMesh.FACE_Y
	m.mesh = q
	var mat: StandardMaterial3D = _scorch_mat.duplicate()
	mat.albedo_color = Color(1, 1, 1, alpha)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position = Vector3(p.x, 0.012 + _scorches.size() * 0.0002, p.y)
	m.rotation.y = _rng.randf() * TAU
	add_child(m)
	_scorches.append({"node": m, "life": SCORCH_LIFE, "alpha": alpha})
	while _scorches.size() > MAX_SCORCHES:
		_scorches[0].node.queue_free()
		_scorches.remove_at(0)


## Lasting smoke over a destroyed vehicle; the owner node decides when to remove it.
func wreck_smoke() -> CPUParticles3D:
	var s := CPUParticles3D.new()
	s.amount = 16
	s.lifetime = 3.5
	s.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	s.emission_sphere_radius = 0.12
	s.direction = Vector3(0, 1, 0)
	s.spread = 10.0
	s.initial_velocity_min = 0.3
	s.initial_velocity_max = 0.55
	s.gravity = Vector3(0.35, 0.15, 0.1)
	s.scale_amount_min = 0.5
	s.scale_amount_max = 0.8
	var c := Curve.new()
	c.add_point(Vector2(0, 0.4))
	c.add_point(Vector2(1, 2.6))
	s.scale_amount_curve = c
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.1, 1.0])
	g.colors = PackedColorArray([Color(1.0, 0.5, 0.15, 0.9), Color(0.1, 0.09, 0.08, 0.9), Color(0.28, 0.26, 0.24, 0.0)])
	s.color_ramp = g
	s.mesh = _quad(_smoke_mat)
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return s


## Dust from under tracks and wheels; on while the vehicle moves.
func track_dust() -> CPUParticles3D:
	var s := CPUParticles3D.new()
	s.amount = 14
	s.lifetime = 1.4
	s.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	s.emission_box_extents = Vector3(0.05, 0.02, 0.32)
	s.direction = Vector3(-1, 0.6, 0)
	s.spread = 25.0
	s.initial_velocity_min = 0.2
	s.initial_velocity_max = 0.5
	s.gravity = Vector3(0, 0.05, 0)
	s.local_coords = false
	s.scale_amount_min = 0.2
	s.scale_amount_max = 0.4
	var c := Curve.new()
	c.add_point(Vector2(0, 0.5))
	c.add_point(Vector2(1, 1.6))
	s.scale_amount_curve = c
	var g := Gradient.new()
	g.set_color(0, Color(0.52, 0.44, 0.33, 0.45))
	g.set_color(1, Color(0.52, 0.44, 0.33, 0.0))
	s.color_ramp = g
	s.mesh = _quad(_smoke_mat)
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.emitting = false
	return s


# --- internals ---------------------------------------------------------------

func _burst(mat: Material, amount: int, lifetime: float, radius: float, dir: Vector3, spread: float,
		v_min: float, v_max: float, gravity: Vector3, s_min: float, s_max: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = amount
	p.lifetime = lifetime
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = maxf(0.01, radius)
	p.direction = dir.normalized() if dir.length() > 0.0 else Vector3.UP
	p.spread = spread
	p.initial_velocity_min = v_min
	p.initial_velocity_max = v_max
	p.gravity = gravity
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = s_min
	p.scale_amount_max = s_max
	var c := Curve.new()
	c.add_point(Vector2(0, 0.5))
	c.add_point(Vector2(1, 1.5))
	p.scale_amount_curve = c
	p.angle_min = 0
	p.angle_max = 360
	p.mesh = _quad(mat)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = true
	return p


func _quad(mat: Material) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = mat
	return q


func _particle_mat(tex: Texture2D, additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.disable_receive_shadows = true
	return m


## A soft blob with a ragged edge for smoke and fire.
func _make_puff() -> ImageTexture:
	var n := FastNoiseLite.new()
	n.seed = 9
	n.frequency = 0.09
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = sqrt(a) * a * (0.7 + 0.7 * (n.get_noise_2d(x, y) * 0.5 + 0.5))
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


## Soot: a dark uneven blob with splash rays.
func _make_scorch() -> ImageTexture:
	var n := FastNoiseLite.new()
	n.seed = 21
	n.frequency = 0.06
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var v := Vector2(x - 63.5, y - 63.5)
			var d := v.length() / 63.5
			var rays := 0.5 + 0.5 * sin(v.angle() * 9.0 + n.get_noise_2d(x, y) * 3.0)
			var edge := 0.55 + 0.25 * rays + 0.2 * n.get_noise_2d(x * 2.0, y * 2.0)
			var a := clampf((edge - d) / 0.25, 0.0, 1.0) * 0.85
			img.set_pixel(x, y, Color(0.05, 0.04, 0.035, a))
	return ImageTexture.create_from_image(img)
