extends Node3D

## Main scene: owns the simulation, hands it to the 3D view and turns input into orders.
## Input (mouse, trackpad, keys) only calls the order_* methods; later
## the iPad touch controls will call the same ones.

const CLICK_SLOP := 8.0
const PICK_RADIUS := 26.0
const ROTATE_SPEED := 1.6
const PAN_SPEED := 1.1
const EDGE_MARGIN := 10.0  # pixels at the window edge where the camera starts scrolling
const SPEEDS := [0.5, 1.0, 2.0]
const PLAYER := 0
const AIM_HEIGHT := 0.45

var world: World
var view: BattleView
var overlay: Overlay
var hud: Hud
var sfx: Sfx

var paused := false
var map_index := 0
## While the map menu is open, the game is stopped.
var in_menu := true
## The side the player plays; the enemy plays the other one.
var player_faction := "empire"
## Enemy level: 0 easy, 1 normal, 2 hard, 3 ruthless.
var ai_difficulty := 1
## For test scenes: fixed player and enemy spots (-1 = random).
var forced_slots := [-1, -1]
var speed_idx := 1
var acc := 0.0
var prev_pos := {}
var tracers: Array = []

var selected: Array = []
## Mode of the next click: "" normal, "attack" attack, "point" fire at a point,
## "place" place a building of place_type.
var mode := ""
var place_type := ""
## Enemy unit or building the player clicked to see what it is.
var inspect_id := -1
var notice := ""
var notice_left := 0.0
var hover_screen := Vector2(-9999, -9999)

var _left_down := false
var _left_start := Vector2.ZERO
var _box := false
var _middle_down := false
## Right button: dragging moves the map, a short click without dragging gives an order.
var _right_down := false
var _right_start := Vector2.ZERO
var _right_drag := false


func _ready() -> void:
	I18n.setup()
	view = BattleView.new()
	add_child(view)
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	overlay = Overlay.new()
	overlay.game = self
	layer.add_child(overlay)
	hud = Hud.new()
	add_child(hud)
	hud.action.connect(_on_hud_action)
	sfx = Sfx.new()
	add_child(sfx)
	new_game(0)
	in_menu = true


func new_game(index: int = map_index) -> void:
	map_index = clampi(index, 0, Scenario.count() - 1)
	in_menu = false
	world = Scenario.build(map_index, 0, forced_slots[0], forced_slots[1])
	world.ai_level[1] = ai_difficulty
	inspect_id = -1
	selected.clear()
	mode = ""
	paused = false
	acc = 0.0
	prev_pos.clear()
	tracers.clear()
	var enemy_faction := "rebels" if player_faction == "empire" else "empire"
	view.factions = [player_faction, enemy_faction]
	view.team_colors = [BattleView.FACTIONS[player_faction].accent.lightened(0.15),
		BattleView.FACTIONS[enemy_faction].accent.lightened(0.15)]
	view.build(world)
	for u: SimUnit in world.units.values():
		if u.team == PLAYER and u.type == "hq":
			view.focus = Vector3(u.pos.x, 0, u.pos.y)
	view.update_camera()


func _process(delta: float) -> void:
	if not paused and not in_menu and world.winner == -1:
		acc += delta * SPEEDS[speed_idx]
		while acc >= World.TICK:
			for u: SimUnit in world.units.values():
				prev_pos[u.id] = u.pos
			world.tick()
			acc -= World.TICK
		_drain_events()
	for t in tracers:
		t.life -= delta
	tracers = tracers.filter(func(t): return t.life > 0.0)
	selected = selected.filter(func(id): return world.units.has(id))
	notice_left = maxf(0.0, notice_left - delta)
	_camera_keys(delta)
	if not world.units.has(inspect_id) or not selected.is_empty() \
			or not world.unit_visible(world.get_unit(inspect_id)):
		inspect_id = -1
	view.sync(world, render_pos, selected + ([inspect_id] if inspect_id != -1 else []), delta)
	hud.refresh(self)
	overlay.queue_redraw()


func _drain_events() -> void:
	for e in world.events:
		match e.type:
			"shot":
				if not world.cell_visible(World.cell_of(e.from)) and not world.cell_visible(World.cell_of(e.to)):
					continue
				tracers.append({"from": e.from, "to": e.to, "hit": e.hit, "team": e.team,
					"heavy": e.kind != "rifleman", "life": 0.25})
				view.recoil(e.id)
				var dir := Vector2.from_angle(e.aim)
				var muzzle: Dictionary = MUZZLES.get(e.kind, MUZZLES.rifleman)
				view.effects.muzzle(e.from + dir * muzzle.reach, muzzle.height, dir, muzzle.size)
				if e.kind == "rifleman":
					if not e.hit:
						view.effects.dust(e.to, 0.6)
				else:
					view.effects.explosion(e.to, 0.45 if e.kind == "grenadier" else 0.6)
				sfx.play(SHOT_SOUNDS.get(e.kind, "rifle"), _sound_dist(e.from), -4.0 if e.kind == "rifleman" else 0.0)
				if e.kind == "grenadier" or e.kind == "tank" or e.kind == "turret":
					sfx.play("blast_small", _sound_dist(e.to), -8.0)
			"death":
				if world.cell_visible(World.cell_of(e.pos)):
					var blast := 0.7
					if e.kind == "tank" or e.kind == "harvester":
						blast = 1.6
					elif UnitTypes.DATA[e.kind].has("size"):
						blast = 2.4
					view.spawn_blast(e.pos, blast, 0.8)
					var big: bool = e.kind == "tank" or e.kind == "harvester" or UnitTypes.DATA[e.kind].has("size")
					sfx.play("blast_big" if big else "blast_small", _sound_dist(e.pos))
			"sold":
				view.spawn_blast(e.pos, 0.8, 0.5)
				if e.team == PLAYER:
					sfx.play("sold")
			"wall_destroyed":
				var wc := Vector2(e.cell) + Vector2(0.5, 0.5)
				view.spawn_blast(wc, 1.4, 0.8)
				if world.cell_visible(e.cell):
					sfx.play("blast_big", _sound_dist(wc), -3.0)
			"build_started", "build_done", "produced":
				# The bright construction signals are noticeably quieter than other sounds.
				var quiet := -12.0 if e.type != "produced" else 0.0
				if e.team == PLAYER:
					sfx.play(_event_sound(e), -1.0, quiet)
				elif world.cell_visible(World.cell_of(e.pos)):
					sfx.play(_event_sound(e), _sound_dist(e.pos), quiet - 6.0)
	world.events.clear()


## Where the muzzle is: forward offset from the unit center, height and flash size.
const MUZZLES := {
	"rifleman": {"reach": 0.33, "height": 0.57, "size": 0.5},
	"grenadier": {"reach": 0.35, "height": 0.6, "size": 0.8},
	"tank": {"reach": 1.08, "height": 0.5, "size": 1.0},
	"turret": {"reach": 0.75, "height": 0.75, "size": 1.0},
}
const SHOT_SOUNDS := {"rifleman": "rifle", "grenadier": "grenade", "tank": "cannon", "turret": "turret"}


func _event_sound(e: Dictionary) -> String:
	match e.type:
		"build_started":
			return "build_start"
		"build_done":
			return "build_done"
	return "tank_ready" if e.kind == "tank" or e.kind == "harvester" else "unit_ready"


## Distance from the screen center to the combat point, in cells.
func _sound_dist(p: Vector2) -> float:
	return p.distance_to(Vector2(view.focus.x, view.focus.z))


func render_pos(u: SimUnit) -> Vector2:
	var alpha := 0.0 if paused else clampf(acc / World.TICK, 0.0, 1.0)
	var prev: Vector2 = prev_pos.get(u.id, u.pos)
	return prev.lerp(u.pos, alpha)


# --- Orders (shared by every input method) --------------------------------

func order_select_at(screen_pos: Vector2, additive: bool) -> void:
	var u := unit_at(screen_pos)
	inspect_id = -1
	if u != null and u.team != PLAYER:
		selected.clear()
		inspect_id = u.id
	elif u != null and u.team == PLAYER:
		var p := primary()
		if u.is_structure() or (p != null and p.is_structure()):
			selected = [u.id]
		elif additive:
			if selected.has(u.id):
				selected.erase(u.id)
			else:
				selected.append(u.id)
		else:
			selected = [u.id]
	elif not additive:
		selected.clear()


func order_select_box(a: Vector2, b: Vector2, additive: bool) -> void:
	var r := Rect2(a, Vector2.ZERO).expand(b)
	if not additive:
		selected.clear()
	for u: SimUnit in world.units.values():
		var p := render_pos(u)
		if u.team == PLAYER and not u.is_structure() and view.is_visible_point(p, AIM_HEIGHT) \
				and r.has_point(view.project(p, AIM_HEIGHT)) and not selected.has(u.id):
			selected.append(u.id)


## Order at a screen point: attack the enemy under the cursor or move there.
func order_at(screen_pos: Vector2, queue: bool) -> void:
	if mode == "place":
		order_place(screen_pos, queue)
		return
	# Buildings take no orders, except the turret (it can fire at a chosen target).
	if selected.is_empty() or (primary().is_structure() and not primary().can_fight()):
		return
	var c := World.cell_of(view.screen_to_ground(screen_pos))
	if mode == "point":
		world.cmd_fire_point(selected, c)
		mode = ""
		return
	var u := unit_at(screen_pos)
	if u != null and u.team != PLAYER:
		world.cmd_attack(selected, u.id, queue)
	elif u != null and u.team == PLAYER and mode == "" and world.cmd_assist(selected, u.id):
		# Medics and engineers go to heal; the other selected units move to the same spot.
		var rest := selected.filter(func(id): return not world.get_unit(id).can_assist(u))
		world.cmd_move(rest, c)
	elif mode != "attack" and world.in_bounds(c):
		world.cmd_move(selected, c)
	mode = ""


## Top-left cell of a building placed with its center under the cursor.
func place_origin(screen_pos: Vector2) -> Vector2i:
	var g := view.screen_to_ground(screen_pos)
	var half: float = UnitTypes.DATA[place_type].size * 0.5
	return Vector2i(floori(g.x - half + 0.5), floori(g.y - half + 0.5))


func order_place(screen_pos: Vector2, keep_mode: bool) -> void:
	var cost: int = UnitTypes.DATA[place_type].cost
	if world.credits[PLAYER] < cost:
		show_notice(tr("Not enough crystals"))
	elif world.cmd_build(PLAYER, place_type, place_origin(screen_pos)):
		if not keep_mode:
			mode = ""
	else:
		show_notice(tr("You cannot build here: you need a free spot next to your base"))


func start_placing(type: String) -> void:
	if mode == "place" and place_type == type:
		mode = ""
		return
	place_type = type
	mode = "place"


func order_produce(type: String) -> void:
	var b := primary()
	if b == null or not b.is_structure():
		return
	if not world.cmd_produce(b.id, type):
		var cost: int = UnitTypes.DATA[type].cost
		if world.credits[PLAYER] < cost:
			show_notice(tr("Not enough crystals"))
		else:
			show_notice(tr("The queue is full or the unit limit is reached"))


## The game starts in exclusive fullscreen: on macOS it hides the menu bar and the Dock,
## so they do not pop up at the screen edge while scrolling the camera. F11 or Alt+Enter toggles a window.
func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)


func show_notice(text: String) -> void:
	notice = text
	notice_left = 2.5


## Panel buttons for the current selection: production in the selected building and construction.
func context_actions() -> Array:
	var res: Array = []
	var cr: int = world.credits[PLAYER]
	var b := primary()
	if b != null and b.is_structure() and b.is_complete():
		for t: String in b.stats().get("produces", []):
			var cost: int = UnitTypes.DATA[t].cost
			res.append({"id": "produce:" + t, "text": "%s (%d)" % [tr(UnitTypes.DATA[t].name), cost],
				"enabled": cr >= cost, "pressed": false})
		if not b.queue.is_empty():
			res.append({"id": "cancel", "text": tr("Cancel last"), "enabled": true, "pressed": false})
	if b != null and b.is_structure() and b.team == PLAYER and b.type != "hq":
		res.append({"id": "sell", "text": tr("Sell +%d (Del)") % world.sell_value(b), "enabled": true, "pressed": false})
	if world.count_type(PLAYER, "hq") > 0:
		var keys := {"barracks": "B", "factory": "T", "turret": "U"}
		for t: String in UnitTypes.BUILDABLE:
			var cost: int = UnitTypes.DATA[t].cost
			res.append({"id": "build:" + t,
				"text": tr("Build: %s (%d) (%s)") % [tr(UnitTypes.DATA[t].name), cost, keys[t]],
				"enabled": cr >= cost, "pressed": mode == "place" and place_type == t})
	return res


func order_sell() -> void:
	var b := primary()
	if b == null:
		return
	var value := world.sell_value(b)
	if world.cmd_sell(PLAYER, b.id):
		selected.clear()
		show_notice(tr("Building sold: +%d crystals") % value)


func order_stop() -> void:
	world.cmd_stop(selected)


func order_toggle_hold() -> void:
	var u := primary()
	if u != null:
		world.cmd_hold(selected, not u.hold_position)


func order_cycle_fire_mode() -> void:
	var u := primary()
	if u != null:
		world.cmd_fire_mode(selected, (u.fire_mode + 1) % 3)


func toggle_pause() -> void:
	paused = not paused


func cycle_speed() -> void:
	speed_idx = (speed_idx + 1) % SPEEDS.size()


func set_mode(m: String) -> void:
	mode = "" if mode == m or selected.is_empty() or not primary().can_fight() else m


func primary() -> SimUnit:
	return world.get_unit(selected[0]) if not selected.is_empty() else null


## Unit under a screen point: the closest on screen within PICK_RADIUS.
func unit_at(screen_pos: Vector2) -> SimUnit:
	var best: SimUnit = null
	var best_d := PICK_RADIUS
	for u: SimUnit in world.units.values():
		var p := render_pos(u)
		if not view.is_visible_point(p, AIM_HEIGHT) or not world.unit_visible(u):
			continue
		var k := 1.0
		if u.is_structure():
			k = 2.6
		elif u.is_armored():
			k = 1.5
		var d := view.project(p, AIM_HEIGHT * (1.0 if u.is_structure() else 0.6)).distance_to(screen_pos) / k
		if d < PICK_RADIUS and d < best_d:
			best = u
			best_d = d
	return best


func _on_hud_action(name: String) -> void:
	if name.begins_with("build:"):
		start_placing(name.substr(6))
		return
	if name.begins_with("produce:"):
		order_produce(name.substr(8))
		return
	if name.begins_with("faction:"):
		player_faction = name.substr(8)
		new_game(map_index)
		in_menu = true
		return
	if name.begins_with("level:"):
		ai_difficulty = int(name.substr(6))
		world.ai_level[1] = ai_difficulty
		return
	if name.begins_with("lang:"):
		I18n.set_language(name.substr(5))
		hud.retranslate()
		return
	if name.begins_with("map:"):
		new_game(int(name.substr(4)))
		return
	match name:
		"cancel":
			var b := primary()
			if b != null:
				world.cmd_cancel_production(b.id)
		"sell": order_sell()
		"pause": toggle_pause()
		"speed": cycle_speed()
		"attack": set_mode("attack")
		"point": set_mode("point")
		"stop": order_stop()
		"hold": order_toggle_hold()
		"fire_mode": order_cycle_fire_mode()
		"restart": new_game()
		"next": new_game(map_index + 1)
		"menu": in_menu = true


# --- Mouse, trackpad and keyboard (macOS) ---------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_mouse_button(event)
	elif event is InputEventMouseMotion:
		if _right_down and not _right_drag and event.position.distance_to(_right_start) > CLICK_SLOP:
			_right_drag = true
		if _middle_down or _right_drag:
			_drag_camera(hover_screen, event.position)
		hover_screen = event.position
		if _left_down and event.position.distance_to(_left_start) > CLICK_SLOP:
			_box = true
	elif event is InputEventPanGesture:
		var d: Vector2 = event.delta
		view.focus += (view.ground_right() * d.x - view.ground_forward() * d.y) * 0.04 * view.dist
		_after_camera_move()
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.position, event.factor)
	elif event is InputEventKey and event.pressed and not event.echo:
		_key(event)


func _mouse_button(e: InputEventMouseButton) -> void:
	match e.button_index:
		MOUSE_BUTTON_LEFT:
			if e.pressed:
				_left_down = true
				_left_start = e.position
				_box = false
			elif _left_down:
				_left_down = false
				var additive := e.shift_pressed
				if _box:
					order_select_box(_left_start, e.position, additive)
				elif mode != "":
					order_at(e.position, additive)
				else:
					var u := unit_at(e.position)
					if u != null and u.team != PLAYER and not selected.is_empty():
						order_at(e.position, additive)
					else:
						order_select_at(e.position, additive)
				_box = false
		MOUSE_BUTTON_RIGHT:
			if e.pressed:
				_right_down = true
				_right_drag = false
				_right_start = e.position
			elif _right_down:
				_right_down = false
				if _right_drag:
					_right_drag = false
				elif mode != "":
					mode = ""
				else:
					order_at(e.position, e.shift_pressed)
		MOUSE_BUTTON_MIDDLE:
			_middle_down = e.pressed
		MOUSE_BUTTON_WHEEL_UP:
			if e.pressed:
				_zoom_at(e.position, 1.1)
		MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed:
				_zoom_at(e.position, 1.0 / 1.1)


func _key(e: InputEventKey) -> void:
	match e.keycode:
		KEY_SPACE: toggle_pause()
		KEY_B: start_placing("barracks")
		KEY_T: start_placing("factory")
		KEY_U: start_placing("turret")
		KEY_DELETE, KEY_BACKSPACE: order_sell()
		KEY_A: set_mode("attack")
		KEY_G: set_mode("point")
		KEY_S: order_stop()
		KEY_H: order_toggle_hold()
		KEY_F: order_cycle_fire_mode()
		KEY_1: speed_idx = 0
		KEY_2: speed_idx = 1
		KEY_3: speed_idx = 2
		KEY_R:
			if world.winner != -1:
				new_game()
		KEY_M:
			in_menu = not in_menu
		KEY_F11:
			_toggle_fullscreen()
		KEY_ENTER:
			if e.alt_pressed:
				_toggle_fullscreen()
		KEY_N:
			sfx.muted = not sfx.muted
			show_notice(tr("Sound off") if sfx.muted else tr("Sound on"))
		KEY_ESCAPE:
			if in_menu:
				in_menu = false
			elif mode != "":
				mode = ""
			else:
				selected.clear()
		_:
			return
	get_viewport().set_input_as_handled()


func _camera_keys(delta: float) -> void:
	var dir := Vector2(
		Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	var rot := 0.0
	if Input.is_key_pressed(KEY_Q):
		rot -= 1.0
	if Input.is_key_pressed(KEY_E):
		rot += 1.0
	dir += _edge_dir()
	dir = dir.limit_length(1.0)
	if dir == Vector2.ZERO and rot == 0.0:
		return
	view.focus += (view.ground_right() * dir.x - view.ground_forward() * dir.y) \
		* PAN_SPEED * view.dist * delta
	view.yaw += rot * ROTATE_SPEED * delta
	_after_camera_move()


## Edge scrolling: the cursor at the window edge or beyond it. When the cursor leaves
## the window, Godot keeps its last position at the edge, and the camera keeps moving.
func _edge_dir() -> Vector2:
	# hover_screen keeps its initial value until the mouse has moved over the window.
	if in_menu or hover_screen.x < -9000.0 or not DisplayServer.window_is_focused():
		return Vector2.ZERO
	var p := get_viewport().get_mouse_position()
	var size := get_viewport().get_visible_rect().size
	var d := Vector2.ZERO
	if p.x <= EDGE_MARGIN:
		d.x = -1.0
	elif p.x >= size.x - EDGE_MARGIN:
		d.x = 1.0
	if p.y <= EDGE_MARGIN:
		d.y = -1.0
	elif p.y >= size.y - EDGE_MARGIN:
		d.y = 1.0
	return d


func _drag_camera(from: Vector2, to: Vector2) -> void:
	var a := view.screen_to_ground(from)
	var b := view.screen_to_ground(to)
	view.focus += Vector3(a.x - b.x, 0, a.y - b.y)
	_after_camera_move()


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := view.screen_to_ground(screen_pos)
	view.dist = clampf(view.dist / factor, BattleView.DIST_MIN, BattleView.DIST_MAX)
	view.update_camera()
	var after := view.screen_to_ground(screen_pos)
	view.focus += Vector3(before.x - after.x, 0, before.y - after.y)
	_after_camera_move()


func _after_camera_move() -> void:
	view.clamp_focus(world)
	view.update_camera()


# --- 2D layer over the field ----------------------------------------------

func draw_overlay(ci: CanvasItem) -> void:
	var font := ThemeDB.fallback_font

	# Aim lines: bright for the selected units, faint for the rest.
	for u: SimUnit in world.units.values():
		if u.aim_pos == null or not world.unit_visible(u):
			continue
		var sel := selected.has(u.id)
		var col: Color = view.team_colors[u.team]
		col.a = 0.9 if sel else 0.22
		var to: Vector2 = u.aim_pos
		var aim_unit := world.get_unit(u.aim_id)
		if aim_unit != null:
			to = render_pos(aim_unit)
		_line3(ci, render_pos(u), AIM_HEIGHT, to, AIM_HEIGHT, col, 2.0 if sel else 1.0, true)
		if u.attack_point != null and sel:
			var pc := Vector2(u.attack_point) + Vector2(0.5, 0.5)
			var s := view.project(pc, 0.9)
			ci.draw_arc(s, 14, 0, TAU, 20, col, 2.0)
			ci.draw_line(s - Vector2(18, 0), s + Vector2(18, 0), col, 2.0)
			ci.draw_line(s - Vector2(0, 18), s + Vector2(0, 18), col, 2.0)

	# Healing and repair: a pulsing green link and a plus over the one being healed.
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 120.0)
	for u: SimUnit in world.units.values():
		if not u.healing:
			continue
		var t := world.get_unit(u.assist_id)
		if t == null:
			continue
		var col := Color(0.4, 1.0, 0.45, 0.8 * pulse)
		_line3(ci, render_pos(u), 0.35, render_pos(t), 0.35, col, 2.0, false)
		var top := view.project(render_pos(t), 1.4 if t.is_structure() else 0.9)
		ci.draw_line(top - Vector2(6, 0), top + Vector2(6, 0), col, 3.0)
		ci.draw_line(top - Vector2(0, 6), top + Vector2(0, 6), col, 3.0)

	for t in tracers:
		var col: Color = view.team_colors[t.team].lightened(0.6)
		col.a = t.life / 0.25
		_line3(ci, t.from, AIM_HEIGHT, t.to, 0.3, col, 3.0 if t.heavy else 1.5, false)

	for u: SimUnit in world.units.values():
		var p := render_pos(u)
		if not view.is_visible_point(p, 1.0) or not world.unit_visible(u):
			continue
		var top := view.project(p, 1.15 if u.type == "tank" else 1.05)
		var w := 36.0
		if u.type == "turret":
			top = view.project(p, 1.2)
			w = 44.0
		elif u.is_structure():
			top = view.project(p, 1.9)
			w = 70.0
		var o := top + Vector2(-w / 2, -10)
		ci.draw_rect(Rect2(o - Vector2(1, 1), Vector2(w + 2, 11)), Color(0, 0, 0, 0.6))
		ci.draw_rect(Rect2(o, Vector2(w * u.hp / u.max_hp, 5)), Color(0.35, 0.9, 0.3))
		ci.draw_rect(Rect2(o + Vector2(0, 6), Vector2(w * u.morale / 100.0, 3)), Color(1.0, 0.85, 0.2))
		ci.draw_rect(Rect2(o + Vector2(-6, 0), Vector2(4, 9)), view.team_colors[u.team])
		if u.is_structure():
			if not u.is_complete():
				ci.draw_string(font, o + Vector2(0, 26), tr("building %d%%") % roundi(u.build_progress * 100.0),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
			elif not u.queue.is_empty() and u.team == PLAYER:
				ci.draw_rect(Rect2(o + Vector2(0, 12), Vector2(w * u.queue_progress, 4)), Color(0.3, 0.9, 1.0))
				ci.draw_string(font, o + Vector2(w + 4, 16), "×%d" % u.queue.size(),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		elif u.type == "harvester" and u.cargo > 0.0:
			ci.draw_rect(Rect2(o + Vector2(0, 12), Vector2(w * u.cargo / u.stats().capacity, 3)), Color(0.3, 0.95, 0.8))
		if u.hold_position and not u.is_structure():
			ci.draw_string(font, o + Vector2(w + 4, 9), tr("H"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

	# Target queue and hit chances for the first selected unit.
	var pu := primary()
	var hovered := unit_at(hover_screen)
	# Name under the cursor and name of the inspected enemy: the label stays while it is inspected.
	var inspected := world.get_unit(inspect_id)
	if inspected != null:
		_draw_name(ci, font, inspected)
	if hovered != null and hovered != inspected and mode != "place":
		_draw_name(ci, font, hovered)
	if pu != null and pu.is_support():
		var t := world.get_unit(pu.assist_id)
		if t != null:
			var pc := view.project(render_pos(t), 0.0) + Vector2(-16, 22)
			ci.draw_string(font, pc, tr("heals" if pu.type == "medic" else "repairs"),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.5, 1.0, 0.5))
	if pu != null and pu.can_fight():
		for i in pu.target_queue.size():
			var t := world.get_unit(pu.target_queue[i])
			if t != null:
				ci.draw_string(font, view.project(render_pos(t), 1.0) + Vector2(22, -2), str(i + 1),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.YELLOW)
		for t: SimUnit in world.units.values():
			if t.team == PLAYER or not world.unit_visible(t):
				continue
			var ch := world.preview_chance(pu.id, t.id)
			var is_hover := t == hovered
			if ch > 0.0 or is_hover:
				var txt := "%d%%" % roundi(ch * 100.0) if ch > 0.0 else tr("no line of fire")
				var col := Color.WHITE if is_hover else Color(1, 1, 1, 0.8)
				var s := view.project(render_pos(t), 0.0) + Vector2(-16, 22)
				ci.draw_string(font, s + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1,
					20 if is_hover else 16, Color(0, 0, 0, 0.8))
				ci.draw_string(font, s, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20 if is_hover else 16, col)

	if mode == "place":
		var origin := place_origin(hover_screen)
		var size: int = UnitTypes.DATA[place_type].size
		var ok := world.can_place(PLAYER, place_type, origin)
		var o := Vector2(origin)
		var pts := PackedVector2Array([
			view.project(o, 0.02), view.project(o + Vector2(size, 0), 0.02),
			view.project(o + Vector2(size, size), 0.02), view.project(o + Vector2(0, size), 0.02)])
		var col := Color(0.3, 1.0, 0.4, 0.35) if ok else Color(1.0, 0.3, 0.25, 0.35)
		ci.draw_colored_polygon(pts, col)
		pts.append(pts[0])
		ci.draw_polyline(pts, Color(col, 0.9), 2.0)

	if _box and _left_down:
		var r := Rect2(_left_start, Vector2.ZERO).expand(hover_screen)
		ci.draw_rect(r, Color(1, 1, 1, 0.1))
		ci.draw_rect(r, Color(1, 1, 1, 0.6), false, 1.5)


func _draw_name(ci: CanvasItem, font: Font, u: SimUnit) -> void:
	var h := 1.2 if u.type == "turret" else 1.9 if u.is_structure() else (1.15 if u.type == "tank" else 1.05)
	var label: String = tr(u.stats().name)
	if u.team != PLAYER:
		label = tr("Enemy: %s") % label
	var ls := view.project(render_pos(u), h) + Vector2(-label.length() * 4.0, -16)
	ci.draw_string(font, ls + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0, 0, 0, 0.85))
	ci.draw_string(font, ls, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, view.team_colors[u.team].lightened(0.5))


func _line3(ci: CanvasItem, a: Vector2, ha: float, b: Vector2, hb: float, col: Color,
		width: float, dashed: bool) -> void:
	if not view.is_visible_point(a, ha) or not view.is_visible_point(b, hb):
		return
	var sa := view.project(a, ha)
	var sb := view.project(b, hb)
	if dashed:
		ci.draw_dashed_line(sa, sb, col, width, 8.0)
	else:
		ci.draw_line(sa, sb, col, width)
