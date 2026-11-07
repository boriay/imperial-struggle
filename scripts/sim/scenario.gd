class_name Scenario
extends RefCounted

## Ten campaign maps. Each map has 6 base spots: two at the top, two at the bottom,
## one on the left and one on the right. Maps are point-symmetric about the center (except the mazes),
## so every spot has a mirrored twin with the same approaches and crystal fields.
## The player and the enemy start on two different random spots.

const START_CREDITS := 400
const ENEMY_BONUS_PER_MAP := 60
const SLOT_COUNT := 6

const MAPS := [
	{"name": "Wasteland", "desc": "An open plain with ruined walls", "w": 84, "h": 58, "kind": "ruins", "style": 0},
	{"name": "River", "desc": "The river can only be crossed at fords", "w": 86, "h": 60, "kind": "river", "style": 1},
	{"name": "Lakes", "desc": "Lakes split the field into passages", "w": 88, "h": 60, "kind": "lakes", "style": 3},
	{"name": "Fortresses", "desc": "Every base is behind a ring of walls with gates", "w": 88, "h": 62, "kind": "forts", "style": 3},
	{"name": "Maze", "desc": "A maze of walls fills the middle of the map", "w": 90, "h": 62, "kind": "maze", "style": 2},
	{"name": "Canyon", "desc": "Three canyons between water, blocked by walls", "w": 92, "h": 62, "kind": "canyon", "style": 1},
	{"name": "City", "desc": "Blocks of ruins and streets between them", "w": 94, "h": 64, "kind": "city", "style": 0},
	{"name": "Marsh", "desc": "Many puddles and little cover", "w": 96, "h": 64, "kind": "marsh", "style": 1},
	{"name": "Channels", "desc": "Three rivers and narrow bridges across them", "w": 98, "h": 66, "kind": "channels", "style": 2},
	{"name": "Great Maze", "desc": "A maze across the whole map", "w": 100, "h": 68, "kind": "bigmaze", "style": 3},
]


static func count() -> int:
	return MAPS.size()


## player_slot / enemy_slot: -1 = random spot.
static func build(map_index: int = 0, seed_value: int = 0, player_slot := -1, enemy_slot := -1) -> World:
	var m: Dictionary = MAPS[clampi(map_index, 0, MAPS.size() - 1)]
	var W: int = m.w
	var H: int = m.h
	var w := World.new()
	w.setup(W, H, seed_value)
	w.wall_style = m.style
	var gen := RandomNumberGenerator.new()
	gen.seed = 1000 + map_index

	var walls := {}
	var water := {}
	var k := float(W * H) / (52.0 * 32.0)
	match m.kind:
		"ruins": _ruins(walls, gen, W, H, roundi(18 * k))
		"river": _river(water, gen, W, H)
		"lakes": _lakes(water, gen, W, H, roundi(6 * k), 2, 5)
		"forts":
			_forts(walls, W, H)
			_ruins(walls, gen, W, H, roundi(8 * k))
		"maze": _maze(walls, gen, 13, W - 13, H / 4, H - H / 4)
		"canyon": _canyon(walls, water, gen, W, H)
		"city": _city(walls, gen, W, H)
		"marsh":
			_lakes(water, gen, W, H, roundi(22 * k), 1, 2)
			_ruins(walls, gen, W, H, roundi(8 * k))
		"channels": _channels(water, gen, W, H)
		"bigmaze": _maze(walls, gen, 9, W - 9, 0, H)
	if not m.kind.ends_with("maze"):
		walls = _mirrored(walls, W, H)
		water = _mirrored(water, W, H)
	for c: Vector2i in water:
		w.add_water(c)
	for c: Vector2i in walls:
		w.add_wall(c)

	var slots := base_slots(W, H)
	for b in slots:
		_clear_area(w, Vector2(b) + Vector2.ONE, 6.5)
	for b in slots:
		_ensure_crossing(w, slots[5], b)

	if player_slot < 0 or player_slot >= SLOT_COUNT:
		player_slot = w.rng.randi_range(0, SLOT_COUNT - 1)
	if enemy_slot < 0 or enemy_slot == player_slot or enemy_slot >= SLOT_COUNT:
		enemy_slot = w.rng.randi_range(0, SLOT_COUNT - 2)
		if enemy_slot >= player_slot:
			enemy_slot += 1
	w.base_slots = slots
	w.player_slot = player_slot
	w.enemy_slot = enemy_slot
	var base0: Vector2i = slots[player_slot]
	var base1: Vector2i = slots[enemy_slot]

	# Crystal fields at every base spot in the left half (the right ones get the mirrored
	# twin) and shared fields closer to the center.
	for b in slots:
		if b.x < W / 2:
			for offset in [Vector2i(5, -6), Vector2i(5, 7), Vector2i(11, 1)]:
				_field_pair(w, gen, b + _toward_center(offset, b, W, H), W, H)
	_field_pair(w, gen, Vector2i(W / 2 - 7, H / 4 + 2), W, H)
	_field_pair(w, gen, Vector2i(W / 2 - 9, H / 2 - 1), W, H)
	_field_pair(w, gen, Vector2i(W / 2 - 3, H / 2 + 6), W, H)

	w.spawn_structure("hq", 0, base0)
	w.spawn_structure("hq", 1, base1)
	w.spawn_structure("barracks", 1, base1 + _toward_center(Vector2i(3, -4), base1, W, H))
	for spec in [[Vector2i(4, -2), "rifleman"], [Vector2i(4, 3), "rifleman"],
			[Vector2i(5, 1), "rifleman"], [Vector2i(3, 1), "tank"], [Vector2i(-1, 3), "harvester"]]:
		var c0 := w.free_cell_near(base0 + _toward_center(spec[0], base0, W, H), {})
		w.spawn(spec[1], 0, c0)
		var c1 := w.free_cell_near(base1 + _toward_center(spec[0], base1, W, H), {})
		w.spawn("grenadier" if spec[1] == "tank" else spec[1], 1, c1)
	w.credits = [START_CREDITS, START_CREDITS + ENEMY_BONUS_PER_MAP * map_index]
	w.update_fog()
	return w


## 6 HQ spots (top-left corner of the 2×2 HQ), clockwise: 0 top left,
## 1 top right, 2 right, 3 bottom right, 4 bottom left, 5 left.
## Pairs 0–3, 1–4 and 2–5 mirror each other about the center.
static func base_slots(W: int, H: int) -> Array[Vector2i]:
	var tl := Vector2i(W / 3 - 1, 4)
	var bl := Vector2i(W / 3 - 1, H - 6)
	var l := Vector2i(4, H / 2 - 1)
	var m := Vector2i(W - 2, H - 2)
	return [tl, m - bl, m - l, m - tl, bl, l]


## The "towards the map center" direction for a base: +x for the left, -x for the right, +y for the top, -y for the bottom ones.
static func _inward(base: Vector2i, W: int, H: int) -> Vector2i:
	if base.x < W / 4:
		return Vector2i(1, 0)
	if base.x > W - W / 4:
		return Vector2i(-1, 0)
	return Vector2i(0, 1) if base.y < H / 2 else Vector2i(0, -1)


## Offsets are given for the left base (+x is towards the center); for the others they are rotated.
static func _toward_center(offset: Vector2i, base: Vector2i, W: int, H: int) -> Vector2i:
	var d := _inward(base, W, H)
	# Rotation that maps (1, 0) onto d.
	return Vector2i(offset.x * d.x - offset.y * d.y, offset.x * d.y + offset.y * d.x)


# --- Terrain ---------------------------------------------------------------

static func _mirror(c: Vector2i, W: int, H: int) -> Vector2i:
	return Vector2i(W - 1 - c.x, H - 1 - c.y)


static func _mirrored(cells: Dictionary, W: int, H: int) -> Dictionary:
	var res := cells.duplicate()
	for c: Vector2i in cells:
		res[_mirror(c, W, H)] = true
	return res


static func _ruins(walls: Dictionary, gen: RandomNumberGenerator, W: int, H: int, n: int) -> void:
	for i in n:
		var start := Vector2i(gen.randi_range(10, W / 2 - 1), gen.randi_range(2, H - 3))
		var horizontal := gen.randf() < 0.5
		for k in gen.randi_range(3, 6):
			walls[start + (Vector2i(k, 0) if horizontal else Vector2i(0, k))] = true


static func _blob(cells: Dictionary, gen: RandomNumberGenerator, center: Vector2, r: float) -> void:
	# A smoothly wavy circle: no random jagged single cells.
	var phase := gen.randf() * TAU
	var lobes := gen.randi_range(2, 3)
	var stretch := gen.randf_range(0.8, 1.25)
	for y in range(floori(center.y - r * 1.5 - 1), ceili(center.y + r * 1.5 + 2)):
		for x in range(floori(center.x - r * 1.5 - 1), ceili(center.x + r * 1.5 + 2)):
			var v := Vector2(x + 0.5, y + 0.5) - center
			v.x /= stretch
			var wobble := 1.0 + 0.12 * sin(v.angle() * lobes + phase)
			if v.length() < r * wobble:
				cells[Vector2i(x, y)] = true


static func _lakes(water: Dictionary, gen: RandomNumberGenerator, W: int, H: int, n: int,
		r_min: int = 2, r_max: int = 4) -> void:
	for i in n:
		var c := Vector2(gen.randf_range(10, W / 2.0 - 1), gen.randf_range(2, H - 2))
		_blob(water, gen, c, gen.randf_range(r_min, r_max + 0.5))


static func _river(water: Dictionary, gen: RandomNumberGenerator, W: int, H: int) -> void:
	var phase := gen.randf() * TAU
	for y in H:
		var xc := W / 2 - 1 + roundi(sin(y * 0.25 + phase) * 2.0)
		for x in range(xc - 1, xc + 2):
			water[Vector2i(x, y)] = true
	# Fords: top, middle and (after mirroring) bottom.
	for ford in [H / 6 + gen.randi_range(-2, 2), H / 2 - 1]:
		for y in range(ford - 1, ford + 2):
			for x in range(W / 2 - 5, W / 2 + 5):
				water.erase(Vector2i(x, y))


static func _channels(water: Dictionary, gen: RandomNumberGenerator, W: int, H: int) -> void:
	for xc in [W / 4, W / 2 - 1]:
		for y in H:
			water[Vector2i(xc, y)] = true
			water[Vector2i(xc + 1, y)] = true
		for bridge in [gen.randi_range(3, H / 4), gen.randi_range(H / 4 + 4, H / 2 - 3)]:
			for y in range(bridge, bridge + 2):
				water.erase(Vector2i(xc, y))
				water.erase(Vector2i(xc + 1, y))


static func _forts(walls: Dictionary, W: int, H: int) -> void:
	for base: Vector2i in base_slots(W, H):
		if base.x >= W / 2:
			continue
		# The ring is given for the left base in its own coordinates (x towards the center), then rotated.
		var wall := []
		for x in range(-3, 11):
			wall.append(Vector2i(x, -7))
			wall.append(Vector2i(x, 8))
		for y in range(-7, 9):
			wall.append(Vector2i(10, y))
		for c: Vector2i in wall:
			var gate := (c.x == 10 and c.y >= -1 and c.y <= 2) or (c.x >= 5 and c.x <= 7 and absi(c.y) >= 7)
			if not gate:
				walls[base + _toward_center(c, base, W, H)] = true


## Three canyons (one per row of bases), separated by strips of water with rare land bridges;
## barricades across the canyons with a gap alternately at the top and at the bottom.
static func _canyon(walls: Dictionary, water: Dictionary, gen: RandomNumberGenerator, W: int, H: int) -> void:
	var band := H / 3
	for k in [1, 2]:
		var crossings := [gen.randi_range(14, W / 2 - 16), W / 2 - 4]
		var phase := gen.randf() * TAU
		for x in range(0, W / 2 + 1):
			var crossing := false
			for cx in crossings:
				if x >= cx and x < cx + 4:
					crossing = true
			if crossing:
				continue
			var mid: float = k * band + sin(x * 0.18 + phase) * 1.2
			for y in range(roundi(mid - 2.2), roundi(mid + 2.2)):
				water[Vector2i(x, y)] = true
	var i := 0
	for x in range(14, W / 2, 7):
		for row in 3:
			var y0 := row * band + 2
			var y1 := (row + 1) * band - 2
			var gap_top := (i + row) % 2 == 0
			for y in range(y0, y1):
				var in_gap := (y < y0 + 3) if gap_top else (y >= y1 - 3)
				if not in_gap:
					walls[Vector2i(x, y)] = true
		i += 1


static func _city(walls: Dictionary, gen: RandomNumberGenerator, W: int, H: int) -> void:
	for bx in range(11, W / 2, 7):
		for by in range(1, H - 4, 7):
			if gen.randf() < 0.2:
				continue
			var rect := Rect2i(bx, by, 4, 4)
			for x in range(rect.position.x, rect.end.x):
				for y in range(rect.position.y, rect.end.y):
					var edge := x == rect.position.x or y == rect.position.y \
						or x == rect.end.x - 1 or y == rect.end.y - 1
					if edge and gen.randf() < 0.8:
						walls[Vector2i(x, y)] = true


## A maze with 2-cell corridors between x0..x1, y0..y1, with entrances on the left and right.
static func _maze(walls: Dictionary, gen: RandomNumberGenerator, x0: int, x1: int, y0: int, y1: int) -> void:
	var nx := (x1 - x0 - 1) / 3
	var ny := (y1 - y0 - 1) / 3
	for x in range(x0, x0 + nx * 3 + 1):
		for y in range(y0, y0 + ny * 3 + 1):
			walls[Vector2i(x, y)] = true
	var visited := {}
	var stack: Array[Vector2i] = [Vector2i(0, 0)]
	visited[Vector2i(0, 0)] = true
	_carve_node(walls, x0, y0, Vector2i(0, 0))
	while not stack.is_empty():
		var cur: Vector2i = stack[stack.size() - 1]
		var options: Array[Vector2i] = []
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if n.x >= 0 and n.y >= 0 and n.x < nx and n.y < ny and not visited.has(n):
				options.append(n)
		if options.is_empty():
			stack.pop_back()
			continue
		var nxt: Vector2i = options[gen.randi_range(0, options.size() - 1)]
		visited[nxt] = true
		_carve_node(walls, x0, y0, nxt)
		# Opening between nodes.
		var a := Vector2i(x0 + 1 + cur.x * 3, y0 + 1 + cur.y * 3)
		var b := Vector2i(x0 + 1 + nxt.x * 3, y0 + 1 + nxt.y * 3)
		var mid := (a + b) / 2
		for dx in 2:
			for dy in 2:
				walls.erase(Vector2i(mini(a.x, b.x), mini(a.y, b.y)) + Vector2i(dx, dy) + (b - a).sign())
				walls.erase(mid + Vector2i(dx, dy))
		stack.append(nxt)
	# A few extra openings so there is more than one path, and entrances at the edges.
	for i in nx * ny / 6:
		var c := Vector2i(gen.randi_range(x0 + 1, x0 + nx * 3 - 1), gen.randi_range(y0 + 1, y0 + ny * 3 - 1))
		walls.erase(c)
		walls.erase(c + Vector2i(1, 0))
	for k in 3:
		var row := gen.randi_range(0, ny - 1)
		for side in [x0, x0 + nx * 3]:
			for dy in 2:
				walls.erase(Vector2i(side, y0 + 1 + row * 3 + dy))


static func _carve_node(walls: Dictionary, x0: int, y0: int, n: Vector2i) -> void:
	for dx in 2:
		for dy in 2:
			walls.erase(Vector2i(x0 + 1 + n.x * 3 + dx, y0 + 1 + n.y * 3 + dy))


# --- Bases, passages, crystals --------------------------------------------

static func _clear_area(w: World, center: Vector2, r: float) -> void:
	for y in range(floori(center.y - r), ceili(center.y + r)):
		for x in range(floori(center.x - r), ceili(center.x + r)):
			if Vector2(x + 0.5, y + 0.5).distance_to(center) <= r:
				w.clear_cell(Vector2i(x, y))


## If the bases are not connected by land, cuts an L-shaped 2-cell passage between them.
static func _ensure_crossing(w: World, base0: Vector2i, base1: Vector2i) -> void:
	var a := base0 + _toward_center(Vector2i(3, 0), base0, w.width, w.height)
	var b := base1 + _toward_center(Vector2i(3, 0), base1, w.width, w.height)
	if a == b or w.has_path(a, b):
		return
	var step := 1 if b.x >= a.x else -1
	for x in range(a.x, b.x + step, step):
		for dy in 2:
			w.clear_cell(Vector2i(x, a.y + dy))
	step = 1 if b.y >= a.y else -1
	for y in range(a.y, b.y + step, step):
		for dx in 2:
			w.clear_cell(Vector2i(b.x + dx, y))


static func _field_pair(w: World, gen: RandomNumberGenerator, center: Vector2i, W: int, H: int) -> void:
	var placed := 0
	var tries := 0
	while placed < 7 and tries < 200:
		tries += 1
		var c := center + Vector2i(gen.randi_range(-2, 2), gen.randi_range(-2, 2))
		var m := _mirror(c, W, H)
		if w.crystals.has(c) or w.is_blocked(c) or w.is_blocked(m):
			continue
		var amount := World.CRYSTAL_AMOUNT * gen.randf_range(0.7, 1.3)
		w.add_crystal(c, amount)
		w.add_crystal(m, amount)
		placed += 1
