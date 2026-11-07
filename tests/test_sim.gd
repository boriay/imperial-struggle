extends SceneTree

## Run: godot --headless --path . --script res://tests/test_sim.gd

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func _init() -> void:
	test_line_of_fire()
	test_hit_chance()
	test_tank_armor()
	test_pathing()
	test_target_queue()
	test_head_on()
	test_harvest()
	test_two_harvesters_keep_mining()
	test_build_and_produce()
	test_turret()
	test_support()
	test_sell()
	test_sound_events()
	test_base_slots()
	test_help_allies()
	test_full_battle()
	test_maps()
	test_hard_ai()
	test_language()
	print("failures: ", failures)
	quit(1 if failures > 0 else 0)


func _blank() -> World:
	var w := World.new()
	w.setup(20, 20, 42)
	w.ai_teams = []
	w.ai_economy = []
	return w


func test_line_of_fire() -> void:
	print("line of fire")
	var w := _blank()
	w.add_wall(Vector2i(5, 5))
	var cover := w.line_info(Vector2(2.5, 5.5), Vector2(6.5, 5.5))
	check(cover.cover and not cover.blocked, "a wall next to the target gives cover")
	var blocked := w.line_info(Vector2(2.5, 5.5), Vector2(8.5, 5.5))
	check(blocked.blocked, "a wall in the middle blocks the line of fire")
	var own := w.line_info(Vector2(4.5, 5.5), Vector2(8.5, 5.5))
	check(not own.blocked and not own.cover, "an own wall does not block fire")


func test_hit_chance() -> void:
	print("hit chance")
	var w := _blank()
	var a := w.spawn("rifleman", 0, Vector2i(2, 2))
	var near := w.spawn("rifleman", 1, Vector2i(6, 2))
	var far := w.spawn("rifleman", 1, Vector2i(12, 2))
	check(w.preview_chance(a.id, far.id) == 0.0, "out of range the chance is 0")
	var open := w.preview_chance(a.id, near.id)
	w.add_wall(Vector2i(5, 2))
	var covered := w.preview_chance(a.id, near.id)
	check(open > 0.4 and covered < open, "cover lowers the chance (%.2f -> %.2f)" % [open, covered])


func test_tank_armor() -> void:
	print("tank armor")
	var w := _blank()
	var tank := w.spawn("tank", 1, Vector2i(10, 10))
	tank.facing = PI
	var front := w.spawn("grenadier", 0, Vector2i(8, 10))
	var hp0 := tank.hp
	w._damage(tank, front, 1.0)
	var front_dmg := hp0 - tank.hp
	front.pos = Vector2(12.5, 10.5)
	hp0 = tank.hp
	w._damage(tank, front, 1.0)
	var rear_dmg := hp0 - tank.hp
	check(is_equal_approx(front_dmg, 70.0) and is_equal_approx(rear_dmg, 210.0),
		"front 70, rear 210 (got %.0f and %.0f)" % [front_dmg, rear_dmg])


func test_pathing() -> void:
	print("pathing")
	var w := _blank()
	for y in range(0, 15):
		w.add_wall(Vector2i(5, y))
	var u := w.spawn("rifleman", 0, Vector2i(2, 2))
	w.cmd_move([u.id], Vector2i(8, 2))
	for i in 600:
		w.tick()
	check(u.cell() == Vector2i(8, 2), "goes around the wall, unit at %s" % u.cell())


func test_target_queue() -> void:
	print("target queue")
	var w := _blank()
	var a := w.spawn("tank", 0, Vector2i(2, 10))
	var t1 := w.spawn("rifleman", 1, Vector2i(6, 10))
	var t2 := w.spawn("rifleman", 1, Vector2i(6, 12))
	t1.fire_mode = SimUnit.FireMode.HOLD
	t2.fire_mode = SimUnit.FireMode.HOLD
	w.cmd_attack([a.id], t1.id)
	w.cmd_attack([a.id], t2.id, true)
	check(a.target_queue.size() == 2, "two targets in the queue")
	for i in 3000:
		w.tick()
		if w.winner != -1:
			break
	check(w.winner == 0, "the tank destroyed both queued targets in %.0f s" % w.time)


func test_head_on() -> void:
	print("head-on")
	var w := _blank()
	var a := w.spawn("harvester", 0, Vector2i(2, 10))
	var b := w.spawn("harvester", 1, Vector2i(16, 10))
	w.cmd_move([a.id], Vector2i(16, 10))
	w.cmd_move([b.id], Vector2i(2, 10))
	for i in 400:
		w.tick()
	check(a.cell() == Vector2i(16, 10) and b.cell() == Vector2i(2, 10),
		"oncoming harvesters passed each other (%s, %s)" % [a.cell(), b.cell()])
	# A narrow passage between walls: one has to give way and go around.
	w = _blank()
	for x in range(5, 15):
		w.add_wall(Vector2i(x, 9))
		w.add_wall(Vector2i(x, 11))
	a = w.spawn("tank", 0, Vector2i(2, 10))
	b = w.spawn("tank", 1, Vector2i(17, 10))
	a.fire_mode = SimUnit.FireMode.HOLD
	b.fire_mode = SimUnit.FireMode.HOLD
	w.cmd_move([a.id], Vector2i(17, 10))
	w.cmd_move([b.id], Vector2i(2, 10))
	for i in 1200:
		w.tick()
	check(a.cell().x >= 15 and b.cell().x <= 4,
		"tanks in a narrow passage did not get stuck for good (%s, %s)" % [a.cell(), b.cell()])


func test_two_harvesters_keep_mining() -> void:
	print("two harvesters")
	var w := _blank()
	w.spawn_structure("hq", 0, Vector2i(9, 9))
	w.add_crystal_field(Vector2i(3, 3), 7)
	w.add_crystal_field(Vector2i(16, 16), 7)
	w.spawn("harvester", 0, Vector2i(8, 12))
	w.spawn("harvester", 0, Vector2i(12, 8))
	var checkpoints: Array[int] = []
	for minute in 4:
		for i in 600:
			w.tick()
		checkpoints.append(w.credits[0])
	var grew := true
	for i in range(1, checkpoints.size()):
		grew = grew and checkpoints[i] > checkpoints[i - 1]
	check(grew, "two harvesters deliver crystals every minute: %s" % [checkpoints])


func test_harvest() -> void:
	print("harvest")
	var w := _blank()
	w.spawn_structure("hq", 0, Vector2i(2, 2))
	w.add_crystal(Vector2i(9, 3), 500.0)
	var h := w.spawn("harvester", 0, Vector2i(5, 5))
	for i in 600:
		w.tick()
	check(w.credits[0] >= 100, "the harvester brought %d crystals in 60 s" % w.credits[0])
	check(w.crystals[Vector2i(9, 3)] < 500.0, "the field shrank")
	w.cmd_move([h.id], Vector2i(15, 15))
	for i in 200:
		w.tick()
	check(h.harvest_state != "seek" or h.cargo > 0.0 or not h.manual, "gathering resumes after a manual order")


func test_build_and_produce() -> void:
	print("build and produce")
	var w := _blank()
	var hq := w.spawn_structure("hq", 0, Vector2i(2, 2))
	w.credits[0] = 1000
	check(not w.cmd_build(0, "barracks", Vector2i(18, 18)), "cannot build far from the base")
	check(not w.cmd_build(0, "barracks", Vector2i(3, 3)), "cannot build on an occupied spot")
	check(w.cmd_build(0, "barracks", Vector2i(6, 2)), "barracks started")
	check(w.credits[0] == 800, "barracks cost 200")
	var barracks: SimUnit = null
	for u: SimUnit in w.units.values():
		if u.type == "barracks":
			barracks = u
	check(not w.cmd_produce(barracks.id, "rifleman"), "an unfinished barracks does not produce")
	for i in 210:
		w.tick()
	check(barracks.is_complete(), "barracks finished in 20 s")
	check(w.cmd_produce(barracks.id, "rifleman"), "rifleman ordered")
	check(not w.cmd_produce(barracks.id, "tank"), "the barracks does not make tanks")
	for i in 90:
		w.tick()
	check(w.count_type(0, "rifleman") == 1, "the rifleman came out of the barracks")
	check(not w.cmd_produce(hq.id, "harvester"), "the HQ does not make harvesters")
	w.cmd_produce(barracks.id, "grenadier")
	w.cmd_cancel_production(barracks.id)
	check(w.credits[0] == 750, "cancelling refunds the money (%d)" % w.credits[0])
	check(w.cmd_build(0, "factory", Vector2i(2, 6)), "factory started")
	var factory: SimUnit = null
	for u: SimUnit in w.units.values():
		if u.type == "factory":
			factory = u
	for i in 310:
		w.tick()
	check(w.cmd_produce(factory.id, "harvester"), "the factory makes harvesters")
	check(w.cmd_produce(factory.id, "tank"), "and tanks")


func test_turret() -> void:
	print("turret")
	var w := _blank()
	w.spawn_structure("hq", 0, Vector2i(2, 2))
	w.spawn_structure("hq", 1, Vector2i(17, 17))
	w.credits[0] = 1000
	check(w.cmd_build(0, "turret", Vector2i(5, 5)), "turret started")
	check(w.credits[0] == 850, "turret costs 150")
	var t: SimUnit = null
	for u: SimUnit in w.units.values():
		if u.type == "turret":
			t = u
	var enemy := w.spawn("rifleman", 1, Vector2i(10, 5))
	enemy.fire_mode = SimUnit.FireMode.HOLD
	for i in 30:
		w.tick()
	check(enemy.hp == enemy.max_hp, "an unfinished turret does not fire")
	for i in 125:
		w.tick()
	check(t.is_complete(), "turret finished in 15 s")
	for i in 150:
		w.tick()
	check(t.hp > 0.0 and w.get_unit(enemy.id) == null, "the turret killed the rifleman on its own")
	check(t.pos == Vector2(5.5, 5.5), "the turret stays in place")
	var tank := w.spawn("tank", 1, Vector2i(9, 8))
	tank.fire_mode = SimUnit.FireMode.HOLD
	var r2 := w.spawn("rifleman", 1, Vector2i(9, 6))
	r2.fire_mode = SimUnit.FireMode.HOLD
	w.cmd_attack([t.id], tank.id)
	for i in 30:
		w.tick()
	check(t.aim_id == tank.id and r2.hp == r2.max_hp, "the turret hits the assigned target, not the nearest one")
	check(t.pos == Vector2(5.5, 5.5), "the turret did not move to the target")


func test_support() -> void:
	print("medic and engineer")
	var w := _blank()
	var hq := w.spawn_structure("hq", 0, Vector2i(2, 2))
	w.spawn_structure("hq", 1, Vector2i(17, 17))
	w.credits[0] = 1000
	check(w.cmd_produce(hq.id, "medic"), "the HQ makes a medic")
	check(w.cmd_produce(hq.id, "engineer"), "the HQ makes an engineer")
	for i in 200:
		w.tick()
	var medic: SimUnit = null
	var eng: SimUnit = null
	for u: SimUnit in w.units.values():
		if u.type == "medic": medic = u
		if u.type == "engineer": eng = u
	check(medic != null and eng != null, "the medic and the engineer came out of the HQ")
	var soldier := w.spawn("rifleman", 0, Vector2i(6, 8))
	soldier.hp = 10.0
	var tank := w.spawn("tank", 0, Vector2i(9, 4))
	tank.hp = 100.0
	hq.hp = hq.max_hp - 50.0
	for i in 200:
		w.tick()
	check(soldier.hp == soldier.max_hp, "the medic healed the rifleman on its own (%d)" % soldier.hp)
	check(tank.hp > 200.0, "the engineer repairs the tank on its own (%d)" % tank.hp)
	check(medic.can_assist(soldier) and not medic.can_assist(tank), "the medic heals only infantry")
	check(eng.can_assist(hq) and not eng.can_assist(soldier), "the engineer repairs vehicles and buildings")
	var enemy := w.spawn("rifleman", 1, Vector2i(12, 12))
	enemy.hp = 10.0
	check(not medic.can_assist(enemy), "enemies are not healed")
	for i in 150:
		w.tick()
	w.cmd_assist([eng.id], hq.id)
	for i in 100:
		w.tick()
	check(hq.hp == hq.max_hp, "the engineer repaired the HQ on order")


func test_sell() -> void:
	print("sell")
	var w := _blank()
	var hq := w.spawn_structure("hq", 0, Vector2i(2, 2))
	w.spawn_structure("hq", 1, Vector2i(17, 17))
	var b := w.spawn_structure("barracks", 0, Vector2i(6, 2))
	w.credits[0] = 0
	check(w.sell_value(b) == 100, "an intact barracks sells for half its price")
	b.hp = b.max_hp / 2.0
	check(w.sell_value(b) == 50, "a damaged one sells for less")
	check(not w.cmd_sell(1, b.id), "cannot sell an enemy building")
	check(not w.cmd_sell(0, hq.id), "the HQ cannot be sold")
	check(w.cmd_sell(0, b.id) and w.credits[0] == 50 and w.get_unit(b.id) == null, "barracks sold")
	check(w.has_path(Vector2i(6, 2), Vector2i(7, 3)), "the spot is free after selling")


func test_sound_events() -> void:
	print("sound events")
	var w := _blank()
	w.spawn_structure("hq", 0, Vector2i(2, 2))
	w.spawn_structure("hq", 1, Vector2i(17, 17))
	w.credits[0] = 5000
	var types := func() -> Array: return w.events.map(func(e): return e.type)
	check(w.cmd_build(0, "factory", Vector2i(7, 2)) and types.call().has("build_started"), "starting construction emits an event")
	w.events.clear()
	var got_done := false
	for i in 400:
		w.tick()
		got_done = got_done or types.call().has("build_done")
		w.events.clear()
	check(got_done, "finishing construction emits an event")
	var f: SimUnit = null
	for u: SimUnit in w.units.values():
		if u.type == "factory":
			f = u
	w.cmd_produce(f.id, "tank")
	var made := {}
	for i in 600:
		w.tick()
		for e in w.events:
			if e.type == "produced":
				made = e
		w.events.clear()
	check(made.get("kind", "") == "tank" and made.has("pos"), "a new tank emits an event with its type")


func test_base_slots() -> void:
	print("base slots")
	for i in Scenario.count():
		var w := Scenario.build(i, 3)
		var ok := w.base_slots.size() == 6
		for a in w.base_slots:
			for b in w.base_slots:
				ok = ok and w.has_path(w.free_cell_near(a + Vector2i(3, 0), {}), w.free_cell_near(b + Vector2i(3, 0), {}))
		check(ok, "map %d: 6 base spots, all connected by land" % (i + 1))
	var seen_player := {}
	var seen_enemy := {}
	var distinct := true
	for s in range(1, 121):
		var w := Scenario.build(0, s)
		seen_player[w.player_slot] = true
		seen_enemy[w.enemy_slot] = true
		distinct = distinct and w.player_slot != w.enemy_slot
		var hq_cell := Vector2i(-1, -1)
		for u: SimUnit in w.units.values():
			if u.type == "hq" and u.team == 1:
				hq_cell = u.origin
		distinct = distinct and hq_cell == w.base_slots[w.enemy_slot]
	check(seen_player.size() == 6 and seen_enemy.size() == 6, "the player and the enemy spawn on any of the 6 spots")
	check(distinct, "the player and the enemy always get different spots, and the HQ stands on its spot")


func test_help_allies() -> void:
	print("help allies")
	var w := _blank()
	w.spawn_structure("hq", 0, Vector2i(1, 1))
	w.spawn_structure("hq", 1, Vector2i(17, 17))
	var front := w.spawn("rifleman", 0, Vector2i(10, 10))
	var idle := w.spawn("rifleman", 0, Vector2i(4, 10))
	var holder := w.spawn("rifleman", 0, Vector2i(4, 12))
	holder.hold_position = true
	var ordered := w.spawn("rifleman", 0, Vector2i(4, 8))
	ordered.fire_mode = SimUnit.FireMode.HOLD
	var far := w.spawn("rifleman", 0, Vector2i(1, 18))
	var enemy := w.spawn("tank", 1, Vector2i(14, 10))
	enemy.fire_mode = SimUnit.FireMode.HOLD
	w.cmd_attack([front.id], enemy.id)
	for i in 40:
		w.tick()
	check(idle.target_queue.has(enemy.id), "a free neighbour went to help")
	check(holder.target_queue.is_empty() and holder.pos == Vector2(4.5, 12.5), "the unit holding position stayed put")
	check(ordered.target_queue.is_empty(), "a unit with fire on order does not join in")
	check(far.target_queue.is_empty(), "a distant unit did not notice the fight")
	for i in 100:
		w.tick()
	check(idle.pos.distance_to(enemy.pos) > 4.6, "the helper does not walk right up to the enemy (%.1f)" % idle.pos.distance_to(enemy.pos))


func test_full_battle() -> void:
	print("full battle")
	var results := {0: 0, 1: 0, -1: 0}
	var total_time := 0.0
	for s in range(1, 11):
		var w := Scenario.build(s)
		w.ai_teams = [0, 1]
		w.ai_economy = [0, 1]
		w.ai_aggressive = [0]
		while w.winner == -1 and w.time < 6000.0:
			w.tick()
		results[w.winner] += 1
		total_time += w.time
	print("  player/enemy wins and draws: ", results, ", average length %.0f s" % (total_time / 10.0))
	check(results[-1] == 0, "every AI-vs-AI battle with economy ends within 100 minutes")


func test_hard_ai() -> void:
	print("hard ai")
	var wins := 0
	for s in range(5):
		var w := Scenario.build(s * 2, 500 + s * 2)
		w.ai_teams = [0, 1]
		w.ai_economy = [0, 1]
		w.ai_aggressive = [0]
		w.ai_level = {0: 1, 1: 2}
		while w.winner == -1 and w.time < 6000.0:
			w.tick()
		if w.winner == 1:
			wins += 1
	check(wins >= 3, "hard AI beats normal (%d of 5)" % wins)


func test_maps() -> void:
	print("maps")
	for i in Scenario.count():
		var w := Scenario.build(i, 11)
		var hqs := []
		for u: SimUnit in w.units.values():
			if u.type == "hq":
				hqs.append(u)
		var a := w.free_cell_near(World.cell_of(hqs[0].pos), {})
		var b := w.free_cell_near(World.cell_of(hqs[1].pos), {})
		var ok := hqs.size() == 2 and w.has_path(a, b) and w.crystals.size() >= 20
		w.ai_teams = [0, 1]
		w.ai_economy = [0, 1]
		w.ai_aggressive = [0]
		while w.winner == -1 and w.time < 6000.0:
			w.tick()
		check(ok and w.winner != -1, "map %d \"%s\": passable, AI battle over in %.0f s (team %d won)" % [
			i + 1, Scenario.MAPS[i].name, w.time, w.winner])


func test_language() -> void:
	print("language")
	# Keep the player's own choice: the test switches languages and puts it back.
	var before := FileAccess.get_file_as_string(I18n.SETTINGS_PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(I18n.SETTINGS_PATH))
	I18n.setup()
	check(I18n.current() == "en", "the default language is English")
	check(TranslationServer.translate("Tank") == "Tank", "English shows the source strings")
	I18n.set_language("ru")
	check(TranslationServer.translate("Tank") == "Танк", "Russian translates unit names")
	check(TranslationServer.translate("Crystals: %d · %02d:%02d · speed ×%s · ours: %d · enemies: %d") % [5, 1, 2, "1", 3, 4]
		== "Кристаллы: 5 · 01:02 · скорость ×1 · наши: 3 · враги: 4", "Russian status line keeps its format")
	TranslationServer.set_locale("en")
	I18n.setup()
	check(I18n.current() == "ru", "the chosen language is restored on the next launch")
	var missing := []
	for m: Dictionary in Scenario.MAPS:
		for key: String in [m.name, m.desc]:
			if not I18n.RU.has(key):
				missing.append(key)
	for t: String in UnitTypes.DATA:
		if not I18n.RU.has(UnitTypes.DATA[t].name):
			missing.append(UnitTypes.DATA[t].name)
	for l: Dictionary in World.AI_LEVELS:
		if not I18n.RU.has(l.name):
			missing.append(l.name)
	for n: String in SimUnit.FIRE_MODE_NAMES:
		if not I18n.RU.has(n):
			missing.append(n)
	check(missing.is_empty(), "every map, unit, AI level and fire mode has a Russian name %s" % [missing])
	if before != "":
		var f := FileAccess.open(I18n.SETTINGS_PATH, FileAccess.WRITE)
		f.store_string(before)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(I18n.SETTINGS_PATH))
	TranslationServer.set_locale("en")
