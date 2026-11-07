class_name World
extends RefCounted

## All game logic, without rendering or input. The simulation step is fixed,
## so the same code works for macOS, iPad and networked play.

const TICK := 0.1
const WALL_HP := 100.0
const CRYSTAL_AMOUNT := 200.0
## AI levels. Normal is the original opponent. Hard does not cheat but plays smarter:
## thinks more often, focuses fire on suitable targets, pulls the wounded back to a medic,
## keeps more harvesters and turrets, attacks in bigger waves with support.
const AI_LEVELS := [
	{"name": "Easy", "period": 2.0, "aggro": 7.0, "wave": 9, "turrets": 0, "harvesters": 1,
		"support": 0, "smart": false, "tank_chance": 0.3, "barracks_queue": 1,
		"extra_buildings": 0, "income": 1.0, "build_speed": 1.0},
	{"name": "Normal", "period": 1.0, "aggro": 9.0, "wave": 6, "turrets": 2, "harvesters": 2,
		"support": 1, "smart": false, "tank_chance": 0.5, "barracks_queue": 2,
		"extra_buildings": 0, "income": 1.0, "build_speed": 1.0},
	{"name": "Hard", "period": 0.5, "aggro": 12.0, "wave": 8, "turrets": 3, "harvesters": 4,
		"support": 2, "smart": true, "tank_chance": 0.75, "barracks_queue": 3,
		"extra_buildings": 1, "income": 1.0, "build_speed": 1.0},
	{"name": "Ruthless", "period": 0.4, "aggro": 13.0, "wave": 8, "turrets": 4, "harvesters": 4,
		"support": 2, "smart": true, "tank_chance": 0.8, "barracks_queue": 3,
		"extra_buildings": 2, "income": 1.5, "build_speed": 1.3},
]
## A free unit goes to help an ally that is firing no further than HELP_RANGE cells away.
const HELP_RANGE := 8.0
const HELP_RECENT := 3.0
const MAX_QUEUE := 3
const MAX_PRODUCTION_QUEUE := 5
const UNIT_CAP := 30
const BUILD_RADIUS := 10.0
const DROPOFF_DIST := 2.3
const NO_CELL := Vector2i(-1, -1)
const STUCK_SECONDS := 1.5

var width := 0
## Base spots on the map, the player's and the enemy's spot (see Scenario.base_slots).
var base_slots: Array[Vector2i] = []
var player_slot := -1
var enemy_slot := -1
var height := 0
var walls := {}
## Wall look on the map: 0 concrete, 1 sandbags, 2 metal fence, 3 stone.
var wall_style := 0
## Water: no walking or building on it, but you can shoot across it.
var water := {}
var crystals := {}
var structure_cells := {}
var units := {}
var credits: Array[int] = [0, 0]
var next_id := 1
var time := 0.0
var winner := -1
## Tick events for the renderer: shots, deaths, destroyed walls.
var events: Array = []
var ai_teams: Array[int] = [1]
## AI teams that attack across the whole map, not only nearby enemies.
var ai_aggressive: Array[int] = []
## AI level per team (index into AI_LEVELS), normal by default.
var ai_level := {0: 1, 1: 1}
var _raid_timer := {}
## AI teams that build their base and order troops themselves.
var ai_economy: Array[int] = [1]

## Fog of war for team fog_team: visible = seen now, explored = seen at some point.
## The AI is not limited by the fog.
var fog_team := 0
var visible := PackedByteArray()
var explored := PackedByteArray()
var astar := AStarGrid2D.new()
var rng := RandomNumberGenerator.new()
var _ai_timer := 0.0
var _teams_spawned := {}


func setup(w: int, h: int, seed_value: int = 0) -> void:
	width = w
	height = h
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	visible.resize(w * h)
	explored.resize(w * h)
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()


func update_fog() -> void:
	visible.fill(0)
	for u: SimUnit in units.values():
		if u.team != fog_team or u.hp <= 0.0:
			continue
		var r: float = u.stats().get("vision", 6.0)
		var c := u.pos
		for y in range(maxi(0, floori(c.y - r)), mini(height, ceili(c.y + r) + 1)):
			for x in range(maxi(0, floori(c.x - r)), mini(width, ceili(c.x + r) + 1)):
				if Vector2(x + 0.5, y + 0.5).distance_squared_to(c) <= r * r:
					visible[y * width + x] = 1
					explored[y * width + x] = 1
	for u: SimUnit in units.values():
		if u.team != fog_team and u.is_structure() and unit_visible(u):
			u.seen = true


func cell_visible(c: Vector2i) -> bool:
	return in_bounds(c) and visible[c.y * width + c.x] == 1


func cell_explored(c: Vector2i) -> bool:
	return in_bounds(c) and explored[c.y * width + c.x] == 1


## Whether the player sees the unit now. Own units are always visible, a building if any of its cells is visible.
func unit_visible(u: SimUnit) -> bool:
	if u.team == fog_team:
		return true
	if u.is_structure():
		for c in footprint(u.type, u.origin):
			if cell_visible(c):
				return true
		return false
	return cell_visible(cell_of(u.pos))


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func is_blocked(c: Vector2i) -> bool:
	return not in_bounds(c) or walls.has(c) or water.has(c) or structure_cells.has(c)


func add_wall(c: Vector2i) -> void:
	if in_bounds(c):
		walls[c] = WALL_HP
		astar.set_point_solid(c, true)


func add_water(c: Vector2i) -> void:
	if in_bounds(c):
		walls.erase(c)
		water[c] = true
		astar.set_point_solid(c, true)


func clear_cell(c: Vector2i) -> void:
	walls.erase(c)
	water.erase(c)
	if in_bounds(c) and not structure_cells.has(c):
		astar.set_point_solid(c, false)


## Whether there is a land path between two cells.
func has_path(a: Vector2i, b: Vector2i) -> bool:
	var pts := astar.get_id_path(a, b)
	return not pts.is_empty() and pts[pts.size() - 1] == b


func add_crystal(c: Vector2i, amount: float = CRYSTAL_AMOUNT) -> void:
	if in_bounds(c) and not is_blocked(c):
		crystals[c] = amount


## A small random crystal field around a point.
func add_crystal_field(center: Vector2i, count: int) -> void:
	var placed := 0
	var tries := 0
	while placed < count and tries < 200:
		tries += 1
		var c := center + Vector2i(rng.randi_range(-2, 2), rng.randi_range(-2, 2))
		if not crystals.has(c) and not is_blocked(c):
			add_crystal(c, CRYSTAL_AMOUNT * rng.randf_range(0.7, 1.3))
			placed += 1


func spawn(type: String, team: int, c: Vector2i) -> SimUnit:
	var u := SimUnit.new()
	u.id = next_id
	next_id += 1
	u.type = type
	u.team = team
	u.pos = Vector2(c) + Vector2(0.5, 0.5)
	u.max_hp = u.stats().hp
	u.hp = u.max_hp
	u.facing = (Vector2(width, height) / 2.0 - u.pos).angle() if width > 0 else 0.0
	u.turret = u.facing
	units[u.id] = u
	_teams_spawned[team] = true
	return u


## A building takes a size×size square of cells starting at origin.
func spawn_structure(type: String, team: int, origin: Vector2i, complete := true) -> SimUnit:
	var size: int = UnitTypes.DATA[type].size
	var u := spawn(type, team, origin)
	u.origin = origin
	u.pos = Vector2(origin) + Vector2(size, size) * 0.5
	u.facing = 0.0
	for c in footprint(type, origin):
		structure_cells[c] = u.id
		astar.set_point_solid(c, true)
	if u.can_fight():
		u.hold_position = true
		u.fire_mode = SimUnit.FireMode.FREE
	if not complete:
		u.build_progress = 0.0
		u.hp = u.max_hp * 0.1
	return u


func footprint(type: String, origin: Vector2i) -> Array[Vector2i]:
	var size: int = UnitTypes.DATA[type].size
	var cells: Array[Vector2i] = []
	for dy in size:
		for dx in size:
			cells.append(origin + Vector2i(dx, dy))
	return cells


func get_unit(id: int) -> SimUnit:
	return units.get(id)


func count_team(team: int) -> int:
	var n := 0
	for u: SimUnit in units.values():
		if u.team == team:
			n += 1
	return n


func count_mobile(team: int) -> int:
	var n := 0
	for u: SimUnit in units.values():
		if u.team == team and not u.is_structure():
			n += 1
	return n


func count_type(team: int, type: String, include_queued := false) -> int:
	var n := 0
	for u: SimUnit in units.values():
		if u.team != team:
			continue
		if u.type == type:
			n += 1
		if include_queued:
			n += u.queue.count(type)
	return n


# --- Orders --------------------------------------------------------------

func cmd_move(ids: Array, dest: Vector2i) -> void:
	var taken := {}
	for id: int in ids:
		var u := get_unit(id)
		if u == null or u.is_structure():
			continue
		var c := free_cell_near(dest, taken)
		if c == NO_CELL:
			continue
		taken[c] = true
		u.target_queue.clear()
		u.attack_point = null
		u.chasing = false
		u.help_stop = 0.0
		if u.is_support():
			u.manual = true
			u.assist_id = -1
		if u.type == "harvester":
			u.manual = true
			if crystals.has(c):
				u.manual = false
				u.harvest_cell = c
				u.harvest_state = "go"
		_set_path(u, c)


func cmd_attack(ids: Array, target_id: int, queue := false) -> void:
	var t := get_unit(target_id)
	if t == null:
		return
	for id: int in ids:
		var u := get_unit(id)
		if u == null or u.team == t.team or not u.can_fight():
			continue
		u.attack_point = null
		if queue:
			if not u.target_queue.has(target_id) and u.target_queue.size() < MAX_QUEUE:
				u.target_queue.append(target_id)
		else:
			u.target_queue.clear()
			u.target_queue.append(target_id)
			u.path = PackedVector2Array()
			u.chasing = false
		u.help_stop = 0.0


## A medic or an engineer goes to an own unit or building and heals it.
func cmd_assist(ids: Array, target_id: int) -> bool:
	var t := get_unit(target_id)
	var any := false
	for id: int in ids:
		var u := get_unit(id)
		if u == null or not u.can_assist(t):
			continue
		u.assist_id = target_id
		u.manual = false
		u.path = PackedVector2Array()
		any = true
	return any


func cmd_fire_point(ids: Array, c: Vector2i) -> void:
	for id: int in ids:
		var u := get_unit(id)
		if u == null or not u.can_fight():
			continue
		u.target_queue.clear()
		u.attack_point = c
		u.path = PackedVector2Array()
		u.chasing = false
		u.help_stop = 0.0


func cmd_stop(ids: Array) -> void:
	for id: int in ids:
		var u := get_unit(id)
		if u == null:
			continue
		u.assist_id = -1
		u.target_queue.clear()
		u.attack_point = null
		u.path = PackedVector2Array()
		u.chasing = false
		u.help_stop = 0.0


func cmd_hold(ids: Array, value: bool) -> void:
	for id: int in ids:
		if get_unit(id) != null and get_unit(id).is_structure():
			continue
		var u := get_unit(id)
		if u != null:
			u.hold_position = value


func cmd_fire_mode(ids: Array, mode: int) -> void:
	for id: int in ids:
		var u := get_unit(id)
		if u != null:
			u.fire_mode = mode


## Whether a building can be placed: the spot is free and an own building is nearby.
func can_place(team: int, type: String, origin: Vector2i) -> bool:
	for c in footprint(type, origin):
		if is_blocked(c) or crystals.has(c):
			return false
	var size: int = UnitTypes.DATA[type].size
	var rect := Rect2(Vector2(origin), Vector2(size, size)).grow(0.3)
	var near_base := false
	for u: SimUnit in units.values():
		if not u.is_structure() and rect.has_point(u.pos):
			return false
		if u.team == team and u.is_structure() \
				and u.pos.distance_to(rect.get_center()) <= BUILD_RADIUS:
			near_base = true
	return near_base


func cmd_build(team: int, type: String, origin: Vector2i) -> bool:
	if not UnitTypes.BUILDABLE.has(type):
		return false
	var cost: int = UnitTypes.DATA[type].cost
	if credits[team] < cost or not can_place(team, type, origin):
		return false
	credits[team] -= cost
	var b := spawn_structure(type, team, origin, false)
	events.append({"type": "build_started", "pos": b.pos, "team": team, "kind": type})
	return true


func cmd_produce(building_id: int, type: String) -> bool:
	var b := get_unit(building_id)
	if b == null or not b.is_structure() or not b.is_complete():
		return false
	if not b.stats().get("produces", []).has(type) or b.queue.size() >= MAX_PRODUCTION_QUEUE:
		return false
	var cost: int = UnitTypes.DATA[type].cost
	if credits[b.team] < cost or _mobile_and_queued(b.team) >= UNIT_CAP:
		return false
	credits[b.team] -= cost
	b.queue.append(type)
	return true


func cmd_cancel_production(building_id: int) -> void:
	var b := get_unit(building_id)
	if b == null or b.queue.is_empty():
		return
	var type: String = b.queue.pop_back()
	credits[b.team] += UnitTypes.DATA[type].cost
	if b.queue.is_empty():
		b.queue_progress = 0.0


## How much a building sells for: half the price, reduced by damage,
## plus the full cost of whatever is queued. The HQ cannot be sold.
func sell_value(b: SimUnit) -> int:
	if b == null or not b.is_structure() or b.type == "hq":
		return 0
	var v: float = b.stats().cost * 0.5 * clampf(b.hp / b.max_hp, 0.0, 1.0)
	for q: String in b.queue:
		v += UnitTypes.DATA[q].cost
	return int(v)


func cmd_sell(team: int, building_id: int) -> bool:
	var b := get_unit(building_id)
	if b == null or b.team != team or not b.is_structure() or b.type == "hq":
		return false
	credits[team] += sell_value(b)
	units.erase(b.id)
	for c in footprint(b.type, b.origin):
		structure_cells.erase(c)
		astar.set_point_solid(c, walls.has(c) or water.has(c))
	events.append({"type": "sold", "pos": b.pos, "team": b.team, "kind": b.type})
	return true


func _mobile_and_queued(team: int) -> int:
	var n := 0
	for u: SimUnit in units.values():
		if u.team == team:
			n += u.queue.size() + (0 if u.is_structure() else 1)
	return n


# --- Shooting ------------------------------------------------------------

## Ray from the shooter to the target: a wall next to the target gives cover, a wall next
## to the shooter does not block (it fires from behind its own cover), other
## walls block the line of fire.
func line_info(from: Vector2, to: Vector2) -> Dictionary:
	var res := {"blocked": false, "cover": false}
	var fc := cell_of(from)
	var tc := cell_of(to)
	var steps := ceili(from.distance_to(to) / 0.2)
	var seen := {}
	for i in range(1, steps):
		var c := cell_of(from.lerp(to, float(i) / steps))
		if c == fc or seen.has(c):
			continue
		seen[c] = true
		if not walls.has(c) or _cheb(c, fc) <= 1:
			continue
		if _cheb(c, tc) <= 1:
			res.cover = true
		else:
			res.blocked = true
			break
	return res


func hit_chance(u: SimUnit, aim: Vector2, is_point: bool, auto: bool) -> float:
	var s := u.stats()
	var rng_cells: float = s.range
	if rng_cells <= 0.0:
		return 0.0
	var d := u.pos.distance_to(aim)
	if d > rng_cells + 0.01:
		return 0.0
	var los := line_info(u.pos, aim)
	if los.blocked:
		return 0.0
	var c: float = s.accuracy * (1.0 - 0.4 * d / rng_cells)
	if los.cover and not is_point:
		c *= 0.6
	if u.moving:
		c *= 0.5
	if auto and not u.is_structure():  # the turret aims automatically, no penalty
		c *= 0.7
	return clampf(c, 0.05, 0.95)


## Hit chance shown to the player, as if the target were set by hand.
func preview_chance(shooter_id: int, target_id: int) -> float:
	var u := get_unit(shooter_id)
	var t := get_unit(target_id)
	if u == null or t == null or u.team == t.team:
		return 0.0
	return hit_chance(u, _aim_pos_of(u, t), false, false)


## Aim point: for a building, the point of its edge closest to the shooter.
func _aim_pos_of(u: SimUnit, t: SimUnit) -> Vector2:
	if not t.is_structure():
		return t.pos
	var half: float = t.stats().size * 0.5 - 0.15
	return Vector2(clampf(u.pos.x, t.pos.x - half, t.pos.x + half),
		clampf(u.pos.y, t.pos.y - half, t.pos.y + half))


# --- Tick ----------------------------------------------------------------

func tick() -> void:
	if winner != -1:
		return
	time += TICK
	var list := units.values()
	for u: SimUnit in list:
		if u.is_structure():
			_update_structure(u)
		else:
			_update_unit(u)
	_separate(list)
	for u: SimUnit in list:
		if not u.is_structure():
			_check_stuck(u)
	for u: SimUnit in list:
		if u.hp <= 0.0:
			_kill(u)
	if int(round(time / TICK)) % 5 == 0:
		_help_allies()
		update_fog()
	_ai_timer -= TICK
	if _ai_timer <= 0.0:
		_ai_timer = AI_LEVELS[ai_level.get(1, 1)].period
		for team in ai_teams:
			_ai(team)
		for team in ai_economy:
			_ai_build(team)
	_check_winner()


func _update_structure(b: SimUnit) -> void:
	if b.hp <= 0.0:
		return
	if not b.is_complete():
		var step: float = TICK / b.stats().build_time * _ai_bonus(b.team, "build_speed")
		b.build_progress = minf(1.0, b.build_progress + step)
		b.hp = minf(b.max_hp, b.hp + b.max_hp * 0.9 * step)
		if b.is_complete():
			events.append({"type": "build_done", "pos": b.pos, "team": b.team, "kind": b.type})
		return
	if b.can_fight():
		# The turret fights like a unit, it just never moves (hold_position).
		_update_unit(b)
		return
	if b.queue.is_empty():
		return
	var type: String = b.queue[0]
	b.queue_progress += TICK / UnitTypes.DATA[type].build_time * _ai_bonus(b.team, "build_speed")
	if b.queue_progress < 1.0:
		return
	var c := free_cell_near(cell_of(b.pos), {})
	if c == NO_CELL:
		return
	b.queue.pop_front()
	b.queue_progress = 0.0
	var u := spawn(type, b.team, c)
	u.facing = (Vector2(width, height) / 2.0 - u.pos).angle()
	u.turret = u.facing
	events.append({"type": "produced", "id": u.id, "team": b.team, "kind": type, "pos": u.pos})


func _update_unit(u: SimUnit) -> void:
	if u.hp <= 0.0:
		return
	var s := u.stats()
	u.reload_left = maxf(0.0, u.reload_left - TICK)
	u.morale = minf(100.0, u.morale + TICK)

	if u.type == "harvester":
		_update_harvester(u)
	if u.is_support():
		_update_support(u)

	while not u.target_queue.is_empty() and get_unit(u.target_queue[0]) == null:
		u.target_queue.pop_front()

	var target: SimUnit = null
	var aim: Variant = null
	var auto := false
	if not u.target_queue.is_empty():
		target = get_unit(u.target_queue[0])
	elif u.attack_point != null:
		aim = Vector2(u.attack_point) + Vector2(0.5, 0.5)
	elif u.can_fight():
		target = _auto_target(u)
		auto = target != null
	if target != null:
		aim = _aim_pos_of(u, target)
	u.aim_id = target.id if target != null else -1
	u.aim_pos = aim
	u.aim_auto = auto

	# Close in on the assigned target if it is out of range.
	if aim != null and not auto and not u.hold_position:
		# A helper does not get closer to the enemy than the ally it is helping.
		var near_enough := u.help_stop > 0.0 and u.pos.distance_to(aim) <= u.help_stop
		if _can_reach_fire(u, aim) or near_enough:
			if u.chasing:
				u.path = PackedVector2Array()
				u.chasing = false
		else:
			u.repath_left -= TICK
			if u.path.is_empty() or (u.chasing and u.repath_left <= 0.0):
				_set_path(u, free_cell_near(cell_of(aim), {}))
				u.chasing = true
				u.repath_left = 1.0

	u.moving = false
	if not u.path.is_empty():
		var next := u.path[0]
		var dir := next - u.pos
		var step: float = s.speed * TICK
		if dir.length() <= step:
			u.pos = next
			u.path.remove_at(0)
		else:
			var heading := _steer(u, dir.normalized())
			_nudge(u, heading * step)
			dir = heading
		if dir.length() > 0.001:
			u.facing = dir.angle()
		u.moving = true

	var aligned := true
	if aim != null:
		var want := (Vector2(aim) - u.pos).angle()
		if s.has("turret_speed"):
			var diff := wrapf(want - u.turret, -PI, PI)
			var max_turn := deg_to_rad(s.turret_speed) * TICK
			if absf(diff) <= max_turn:
				u.turret = want
			else:
				u.turret += signf(diff) * max_turn
			aligned = absf(wrapf(want - u.turret, -PI, PI)) < deg_to_rad(4.0)
		else:
			u.turret = want
	elif not s.has("turret_speed"):
		u.turret = u.facing

	if aim != null and aligned and u.reload_left <= 0.0:
		var chance := hit_chance(u, aim, target == null, auto)
		if chance > 0.0:
			_fire(u, target, aim, chance)
			u.reload_left = s.reload


## Idle player units come on their own to help a neighbour that is fighting.
## Leave alone those that hold position, fire only on order or are already busy.
func _help_allies() -> void:
	for u: SimUnit in units.values():
		if ai_teams.has(u.team) or not u.can_fight() or u.is_structure() or u.hp <= 0.0:
			continue
		if u.hold_position or u.fire_mode == SimUnit.FireMode.HOLD or not u.path.is_empty() \
				or not u.target_queue.is_empty() or u.attack_point != null or u.aim_id != -1:
			continue
		var best: SimUnit = null
		var best_d := HELP_RANGE
		var best_stop := 0.0
		for f: SimUnit in units.values():
			if f.team != u.team or f == u or time - f.fired_at > HELP_RECENT:
				continue
			var enemy := get_unit(f.fired_target)
			if enemy == null or enemy.team == u.team:
				continue
			var d := u.pos.distance_to(f.pos)
			if d < best_d:
				best = enemy
				best_d = d
				best_stop = f.pos.distance_to(enemy.pos)
		if best != null:
			cmd_attack([u.id], best.id)
			u.help_stop = maxf(u.stats().range, best_stop)


## Medic and engineer: walk up to the target and heal it; without a target look for
## the nearest wounded nearby. Enemies and oneself cannot be healed.
func _update_support(u: SimUnit) -> void:
	u.healing = false
	if u.manual:
		if not u.path.is_empty():
			return
		u.manual = false
	var t := get_unit(u.assist_id)
	if t != null and (not u.can_assist(t) or t.hp >= t.max_hp):
		t = null
	if t == null:
		u.assist_id = -1
		t = _nearest_wounded(u)
		if t == null:
			return
		u.assist_id = t.id
	var spot := _aim_pos_of(u, t)
	var reach := 0.7 if t.is_structure() else 0.9
	if u.pos.distance_to(spot) > reach:
		u.repath_left -= TICK
		if u.path.is_empty() or u.repath_left <= 0.0:
			_set_path(u, free_cell_near(cell_of(spot), {}))
			u.repath_left = 1.0
			if u.path.is_empty():
				u.path.append(spot)
		return
	u.path = PackedVector2Array()
	u.facing = (spot - u.pos).angle()
	u.turret = u.facing
	u.healing = true
	t.hp = minf(t.max_hp, t.hp + u.stats().heal_rate * TICK)


func _nearest_wounded(u: SimUnit) -> SimUnit:
	var best: SimUnit = null
	var best_d: float = u.stats().assist_range
	for o: SimUnit in units.values():
		if o.hp >= o.max_hp or not u.can_assist(o):
			continue
		var d := u.pos.distance_to(o.pos)
		if d < best_d:
			best = o
			best_d = d
	return best


## A harvester drives between crystals and the nearest own HQ on its own.
func _update_harvester(u: SimUnit) -> void:
	if u.manual:
		if not u.path.is_empty():
			return
		u.manual = false
		u.harvest_state = "return" if u.cargo > 0.0 else "seek"
	var cap: float = u.stats().capacity
	match u.harvest_state:
		"seek":
			if u.cargo >= cap:
				u.harvest_state = "return"
				return
			var c := _nearest_crystal(u.pos)
			if c == NO_CELL:
				if u.cargo > 0.0:
					u.harvest_state = "return"
				return
			u.harvest_cell = c
			_set_path(u, c)
			u.harvest_state = "go"
		"go":
			if not crystals.has(u.harvest_cell):
				u.harvest_state = "seek"
			elif u.pos.distance_to(Vector2(u.harvest_cell) + Vector2(0.5, 0.5)) < 0.8:
				u.path = PackedVector2Array()
				u.harvest_state = "mine"
			elif u.path.is_empty():
				_set_path(u, u.harvest_cell)
		"mine":
			if not crystals.has(u.harvest_cell):
				u.harvest_state = "seek" if u.cargo < cap else "return"
				return
			var take := minf(u.stats().harvest_rate * TICK, minf(crystals[u.harvest_cell], cap - u.cargo))
			crystals[u.harvest_cell] -= take
			u.cargo += take
			if crystals[u.harvest_cell] <= 0.01:
				crystals.erase(u.harvest_cell)
			if u.cargo >= cap - 0.01:
				u.harvest_state = "return"
		"return":
			var hq := _nearest_dropoff(u)
			if hq == null:
				return
			if u.pos.distance_to(hq.pos) <= DROPOFF_DIST:
				credits[u.team] += roundi(u.cargo * _ai_bonus(u.team, "income"))
				events.append({"type": "delivered", "team": u.team, "amount": roundi(u.cargo)})
				u.cargo = 0.0
				u.path = PackedVector2Array()
				u.harvest_state = "seek"
			elif u.path.is_empty():
				_set_path(u, free_cell_near(cell_of(hq.pos), {}))


func _nearest_crystal(p: Vector2, exclude := NO_CELL) -> Vector2i:
	var best := NO_CELL
	var best_d := INF
	for c: Vector2i in crystals:
		if c == exclude:
			continue
		var d := p.distance_squared_to(Vector2(c) + Vector2(0.5, 0.5))
		if d < best_d:
			best = c
			best_d = d
	return best


func _nearest_dropoff(u: SimUnit) -> SimUnit:
	var best: SimUnit = null
	var best_d := INF
	for b: SimUnit in units.values():
		if b.team == u.team and b.type == "hq" and b.is_complete():
			var d := u.pos.distance_to(b.pos)
			if d < best_d:
				best = b
				best_d = d
	return best


## Pushes apart units that ended up on top of each other.
func _separate(list: Array) -> void:
	for i in list.size():
		var a: SimUnit = list[i]
		if a.is_structure():
			continue
		for j in range(i + 1, list.size()):
			var b: SimUnit = list[j]
			if b.is_structure():
				continue
			var min_d := 0.8 if a.is_armored() or b.is_armored() else 0.6
			var d := b.pos - a.pos
			var l := d.length()
			if l >= min_d:
				continue
			var dir := d / l if l > 0.001 else Vector2.RIGHT.rotated(float(a.id + b.id))
			var push := dir * (min_d - l) * 0.5
			_nudge(a, -push)
			_nudge(b, push)


## Avoidance: if another unit is close straight ahead, the unit keeps to the right.
## Oncoming units both turn to their own right and pass side by side.
func _steer(u: SimUnit, want: Vector2) -> Vector2:
	for o: SimUnit in units.values():
		if o == u or o.is_structure():
			continue
		var rel := o.pos - u.pos
		var d := rel.length()
		if d > 1.2 or d < 0.001:
			continue
		var ahead := rel.dot(want)
		if ahead > 0.0 and absf(want.cross(rel)) < 0.75:
			var turned := want.rotated(deg_to_rad(60.0))
			if not is_blocked(cell_of(u.pos + turned * 0.5)):
				return turned
			return want.rotated(deg_to_rad(-60.0))
	return want


## If a unit with a route stays in place for long, it rebuilds the path, shifts
## slightly sideways, and a harvester picks other crystals.
func _check_stuck(u: SimUnit) -> void:
	if u.path.is_empty() or u.hp <= 0.0:
		u.stuck_time = 0.0
		u._progress_pos = u.pos
		return
	var goal := u.path[u.path.size() - 1]
	if u.pos.distance_to(goal) < u._progress_pos.distance_to(goal) - 0.25 \
			or u.pos.distance_to(u._progress_pos) > 1.5:
		u.stuck_time = 0.0
		u._progress_pos = u.pos
		return
	u.stuck_time += TICK
	if u.stuck_time < STUCK_SECONDS:
		return
	u.stuck_time = 0.0
	u._progress_pos = u.pos
	var dest := cell_of(u.path[u.path.size() - 1])
	var side := Vector2.from_angle(u.facing).orthogonal() * rng.randf_range(0.3, 0.6)
	_nudge(u, side if rng.randf() < 0.5 else -side)
	if u.type == "harvester" and u.harvest_state == "go":
		var alt := _nearest_crystal(u.pos, u.harvest_cell)
		if alt != NO_CELL:
			u.harvest_cell = alt
			dest = alt
	_set_path(u, dest)


func _nudge(u: SimUnit, v: Vector2) -> void:
	var np := u.pos + v
	if not is_blocked(cell_of(np)):
		u.pos = np


func _can_reach_fire(u: SimUnit, aim: Vector2) -> bool:
	var rng_cells: float = u.stats().range
	if u.pos.distance_to(aim) > rng_cells:
		return false
	return not line_info(u.pos, aim).blocked


func _auto_target(u: SimUnit) -> SimUnit:
	match u.fire_mode:
		SimUnit.FireMode.HOLD:
			return null
		SimUnit.FireMode.RETURN:
			var a := get_unit(u.last_attacker)
			if a != null and a.team != u.team and hit_chance(u, a.pos, false, true) > 0.0:
				return a
			return null
	# Free fire: nearest units first, buildings only if no units are near.
	var best: SimUnit = null
	var best_d := INF
	for e: SimUnit in units.values():
		if e.team == u.team or e.hp <= 0.0:
			continue
		var d := u.pos.distance_to(e.pos) + (20.0 if e.is_structure() else 0.0)
		if d < best_d and hit_chance(u, _aim_pos_of(u, e), false, true) > 0.0:
			best = e
			best_d = d
	return best


func _fire(u: SimUnit, target: SimUnit, aim: Vector2, chance: float) -> void:
	var s := u.stats()
	var hit := rng.randf() < chance
	var impact := aim
	if not hit:
		impact = aim + Vector2(rng.randf_range(-0.7, 0.7), rng.randf_range(-0.7, 0.7))
	if target != null:
		if hit:
			_damage(target, u, 1.0)
	elif hit:
		var c := cell_of(aim)
		if walls.has(c):
			walls[c] -= s.dmg_wall
			if walls[c] <= 0.0:
				_destroy_wall(c)
				if u.attack_point == c:
					u.attack_point = null
	if hit and s.splash:
		for o: SimUnit in units.values():
			if o != target and o.hp > 0.0 and not o.is_structure() and o.pos.distance_to(impact) < 0.8:
				_damage(o, u, 0.5)
	u.fired_at = time
	u.fired_target = target.id if target != null else -1
	events.append({
		"type": "shot", "from": u.pos, "to": impact, "hit": hit,
		"team": u.team, "kind": u.type, "id": u.id, "aim": u.turret,
	})


func _damage(t: SimUnit, u: SimUnit, factor: float) -> void:
	var s := u.stats()
	var dmg: float = s.dmg_armor if t.is_armored() else s.dmg_inf
	if t.is_armored() and not t.is_structure():
		# Armor: the front takes half damage, the rear takes three times what the front does.
		var diff := absf(wrapf((u.pos - t.pos).angle() - t.facing, -PI, PI))
		if diff < PI / 4.0:
			dmg *= 0.5
		elif diff > PI * 0.75:
			dmg *= 1.5
	t.hp -= dmg * factor
	t.morale = maxf(0.0, t.morale - 10.0)
	if u.team != t.team:
		t.last_attacker = u.id


func _kill(u: SimUnit) -> void:
	units.erase(u.id)
	if u.is_structure():
		for c in footprint(u.type, u.origin):
			structure_cells.erase(c)
			astar.set_point_solid(c, walls.has(c) or water.has(c))
	events.append({"type": "death", "pos": u.pos, "team": u.team, "kind": u.type, "id": u.id,
		"facing": u.facing, "turret": u.turret})
	for o: SimUnit in units.values():
		if o.team == u.team and o.pos.distance_to(u.pos) < 3.0:
			o.morale = maxf(0.0, o.morale - 5.0)


func _destroy_wall(c: Vector2i) -> void:
	walls.erase(c)
	astar.set_point_solid(c, false)
	events.append({"type": "wall_destroyed", "cell": c})


## A team loses when it has no units and no buildings left.
func _check_winner() -> void:
	if not (_teams_spawned.has(0) and _teams_spawned.has(1)):
		return
	if count_team(1) == 0:
		winner = 0
	elif count_team(0) == 0:
		winner = 1


## Simple opponent: fires freely, answers its attacker, goes for
## the nearest enemy within AI_AGGRO_RANGE cells, and attacks once it has a squad.
func _ai(team: int) -> void:
	var lv: Dictionary = AI_LEVELS[ai_level.get(team, 1)]
	var idle: Array = []
	var intruder: SimUnit = _ai_intruder(team) if lv.smart else null
	if lv.smart:
		_ai_raid(team)
	for u: SimUnit in units.values():
		if u.team != team or not u.can_fight() or u.is_structure():
			continue
		u.fire_mode = SimUnit.FireMode.FREE
		if lv.smart and _ai_smart_unit(u):
			continue
		if u.ai_raider and not u.target_queue.is_empty():
			continue
		# Enemy at the base: defend it with everyone not already fighting.
		if intruder != null and u.target_queue.is_empty():
			cmd_attack([u.id], intruder.id)
			continue
		if not u.target_queue.is_empty() or _auto_target(u) != null:
			continue
		var attacker := get_unit(u.last_attacker)
		if attacker != null and attacker.team != team:
			cmd_attack([u.id], attacker.id)
			continue
		var nearest := _nearest_enemy(u)
		if nearest == null:
			continue
		if u.pos.distance_to(nearest.pos) <= lv.aggro or ai_aggressive.has(team):
			cmd_attack([u.id], nearest.id)
		else:
			idle.append(u)
	var wave_needed: int = lv.wave
	if lv.smart:
		# The first waves are small and early, later the squads grow.
		wave_needed = clampi(4 + int(time / 150.0), 4, lv.wave + 4)
	if idle.size() >= wave_needed:
		if lv.smart:
			_ai_wave(team, idle)
		else:
			for u: SimUnit in idle:
				var nearest := _nearest_enemy(u)
				if nearest != null:
					cmd_attack([u.id], nearest.id)


## Hard AI for a single fighter. Returns true if the unit already got an order.
func _ai_smart_unit(u: SimUnit) -> bool:
	# A wounded unit falls back to its medic or engineer and returns once healed.
	if u.ai_retreat:
		if u.hp >= u.max_hp * 0.8:
			u.ai_retreat = false
		else:
			return true
	if u.hp < u.max_hp * 0.3:
		var helper := _nearest_helper(u)
		if helper != null and helper.pos.distance_to(u.pos) > 1.5:
			u.ai_retreat = true
			cmd_move([u.id], cell_of(helper.pos))
			helper.assist_id = u.id
			return true
	# Target choice among enemies in range: finish off the weak, hit a suitable type,
	# shoot where allies are shooting.
	var best: SimUnit = null
	var best_score := -INF
	var current := get_unit(u.target_queue[0]) if not u.target_queue.is_empty() else null
	var current_score := -INF
	var anti_armor: bool = u.stats().dmg_armor > u.stats().dmg_inf
	for e: SimUnit in units.values():
		if e.team == u.team or e.hp <= 0.0:
			continue
		if hit_chance(u, _aim_pos_of(u, e), false, false) <= 0.0:
			continue
		var score := 2.0 * (1.0 - e.hp / e.max_hp)
		if e.is_armored() == anti_armor:
			score += 1.0
		if e.is_structure():
			score -= 2.5 if e.can_fight() == false else 0.5
		if e.is_support():
			score += 0.8
		if e.type == "harvester":
			score += 1.0
		for o: SimUnit in units.values():
			if o.team == u.team and o != u and not o.target_queue.is_empty() and o.target_queue[0] == e.id:
				score += 0.4
		if e == current:
			current_score = score
		if score > best_score:
			best = e
			best_score = score
	if best != null and best != current and best_score > current_score + 0.5:
		cmd_attack([u.id], best.id)
		return true
	return best != null


func _ai_bonus(team: int, key: String) -> float:
	if not ai_teams.has(team):
		return 1.0
	return AI_LEVELS[ai_level.get(team, 1)][key]


## An enemy that got closer than 8 cells to the team's buildings.
func _ai_intruder(team: int) -> SimUnit:
	for b: SimUnit in units.values():
		if b.team != team or not b.is_structure():
			continue
		for e: SimUnit in units.values():
			if e.team != team and not e.is_structure() and e.pos.distance_to(b.pos) < 8.0:
				return e
	return null


## Once a minute a pair of riflemen goes hunting the enemy harvesters.
func _ai_raid(team: int) -> void:
	_raid_timer[team] = _raid_timer.get(team, 90.0) - AI_LEVELS[ai_level.get(team, 1)].period
	if _raid_timer[team] > 0.0:
		return
	_raid_timer[team] = 60.0
	var prey: SimUnit = null
	var raiders: Array = []
	for u: SimUnit in units.values():
		if u.team != team and u.type == "harvester":
			prey = u
		elif u.team == team and u.type == "rifleman" and u.target_queue.is_empty() and raiders.size() < 2:
			raiders.append(u)
	if prey == null or raiders.size() < 2:
		return
	for r: SimUnit in raiders:
		r.ai_raider = true
		cmd_attack([r.id], prey.id)


func _nearest_helper(u: SimUnit) -> SimUnit:
	var best: SimUnit = null
	var nd := INF
	for o: SimUnit in units.values():
		if o.team == u.team and o.can_assist(u) and o.pos.distance_to(u.pos) < nd:
			best = o
			nd = o.pos.distance_to(u.pos)
	return best


## Hard AI wave: everyone hits the one target nearest to the squad, support follows.
func _ai_wave(team: int, idle: Array) -> void:
	var center := Vector2.ZERO
	for u: SimUnit in idle:
		center += u.pos
	center /= idle.size()
	var target: SimUnit = null
	var nd := INF
	for e: SimUnit in units.values():
		if e.team != team and e.pos.distance_to(center) < nd:
			target = e
			nd = e.pos.distance_to(center)
	if target == null:
		return
	var ids := idle.map(func(u): return u.id)
	cmd_attack(ids, target.id)
	var support: Array = []
	for o: SimUnit in units.values():
		if o.team == team and o.is_support():
			support.append(o.id)
	cmd_move(support, cell_of(center.lerp(target.pos, 0.3)))


func _nearest_enemy(u: SimUnit) -> SimUnit:
	var best: SimUnit = null
	var nd := INF
	for e: SimUnit in units.values():
		if e.team != u.team and u.pos.distance_to(e.pos) < nd:
			best = e
			nd = u.pos.distance_to(e.pos)
	return best


## AI economy: builds a barracks and a factory, keeps two harvesters, then troops.
func _ai_build(team: int) -> void:
	var hq: SimUnit = null
	var barracks: Array = []
	var factories: Array = []
	for u: SimUnit in units.values():
		if u.team != team:
			continue
		match u.type:
			"hq": hq = u
			"barracks": barracks.append(u)
			"factory": factories.append(u)
	if hq == null:
		return
	if barracks.is_empty():
		_ai_place(team, "barracks", hq)
		return
	if factories.is_empty():
		if credits[team] >= UnitTypes.DATA.factory.cost:
			_ai_place(team, "factory", hq)
		return
	var lv: Dictionary = AI_LEVELS[ai_level.get(team, 1)]
	var factory: SimUnit = factories[0]
	if count_type(team, "harvester", true) < lv.harvesters:
		cmd_produce(factory.id, "harvester")
		return
	if count_type(team, "turret") < lv.turrets and credits[team] >= UnitTypes.DATA.turret.cost + 100 \
			and rng.randf() < 0.4:
		_ai_place_turret(team, hq)
		return
	for t in ["medic", "engineer"]:
		if count_type(team, t, true) < lv.support and credits[team] >= UnitTypes.DATA[t].cost + 150:
			cmd_produce(hq.id, t)
	# Strong levels expand production: more barracks and factories when there is a surplus.
	if barracks.size() < 1 + lv.extra_buildings and credits[team] >= UnitTypes.DATA.barracks.cost + 250:
		_ai_place(team, "barracks", hq)
		return
	if factories.size() < 1 + lv.extra_buildings and credits[team] >= UnitTypes.DATA.factory.cost + 300:
		_ai_place(team, "factory", hq)
		return
	for f: SimUnit in factories:
		if f.queue.is_empty() and rng.randf() < lv.tank_chance:
			cmd_produce(f.id, "tank")
	for br: SimUnit in barracks:
		if br.queue.size() < lv.barracks_queue:
			cmd_produce(br.id, "grenadier" if rng.randf() < 0.3 else "rifleman")


## The AI places turrets in front of its HQ, on the enemy's side.
func _ai_place_turret(team: int, hq: SimUnit) -> void:
	var c := cell_of(hq.pos)
	var ahead := (Vector2(width, height) / 2.0 - hq.pos).normalized()
	var side := ahead.orthogonal()
	for i in 20:
		var o := c + Vector2i((ahead * rng.randi_range(3, 6) + side * rng.randi_range(-5, 5)).round())
		if cmd_build(team, "turret", o):
			return


func _ai_place(team: int, type: String, near: SimUnit) -> void:
	var c := cell_of(near.pos)
	for r in range(3, 9):
		for i in 12:
			var o := c + Vector2i(rng.randi_range(-r, r), rng.randi_range(-r, r))
			if cmd_build(team, type, o):
				return


# --- Helpers -------------------------------------------------------------

func _set_path(u: SimUnit, c: Vector2i) -> void:
	u.path = PackedVector2Array()
	if c == NO_CELL:
		return
	var pts := astar.get_point_path(u.cell(), c, true)
	for i in range(1, pts.size()):
		u.path.append(pts[i] + Vector2(0.5, 0.5))


func free_cell_near(dest: Vector2i, taken: Dictionary) -> Vector2i:
	for r in range(0, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := dest + Vector2i(dx, dy)
				if not is_blocked(c) and not taken.has(c):
					return c
	return NO_CELL


static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.y))


static func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
