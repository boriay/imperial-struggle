extends Node

## A large battle shot for the README:
## xvfb-run godot --path . --fixed-fps 30 --resolution 1920x1080 res://tests/battle.tscn -- <folder>
## Optional env: SHOT_FRAME (frame to save), FACTION, SHOT_MAP, YAW, DIST, FWD.

var game: Node3D
var frame := 0
var out_dir := "user://"
var mid := Vector2.ZERO


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	game = load("res://main.tscn").instantiate()
	add_child(game)


func _put(w: World, type: String, team: int, c: Vector2i, taken: Dictionary) -> SimUnit:
	var cell := w.free_cell_near(c, taken)
	taken[cell] = true
	var u := w.spawn(type, team, cell)
	u.fire_mode = SimUnit.FireMode.FREE
	return u


func _env(name: String, def: float) -> float:
	var v := OS.get_environment(name)
	return v.to_float() if v != "" else def


func _process(_d: float) -> void:
	frame += 1
	if frame == 3:
		if OS.get_environment("FACTION") != "":
			game.player_faction = OS.get_environment("FACTION")
		game.forced_slots = [5, 2]
		game.new_game(OS.get_environment("SHOT_MAP").to_int())
		var w: World = game.world
		w.rng.seed = 11
		var hq: SimUnit = null
		for u: SimUnit in w.units.values():
			if u.team == 0 and u.type == "hq":
				hq = u
		var center := Vector2(w.width, w.height) / 2.0
		var dir := (center - hq.pos).normalized()
		var side := Vector2(-dir.y, dir.x)
		var at := func(fwd: float, lat: float) -> Vector2i:
			return World.cell_of(hq.pos + dir * fwd + side * lat)
		w.spawn_structure("turret", 0, at.call(6.0, -3.0))
		w.spawn_structure("barracks", 0, at.call(2.0, 5.0))
		var taken := {}
		var ours := []
		for i in 3:
			ours.append(_put(w, "tank", 0, at.call(8.0, -4.0 + i * 4.0), taken).id)
		for i in 6:
			ours.append(_put(w, "rifleman", 0, at.call(10.0, -5.0 + i * 2.0), taken).id)
		for i in 3:
			ours.append(_put(w, "grenadier", 0, at.call(9.0, -3.0 + i * 3.0), taken).id)
		_put(w, "medic", 0, at.call(6.5, 1.0), taken)
		_put(w, "engineer", 0, at.call(6.0, 3.0), taken)
		var theirs := []
		for i in 3:
			theirs.append(_put(w, "tank", 1, at.call(20.0, -4.0 + i * 4.0), taken).id)
		for i in 7:
			theirs.append(_put(w, "rifleman", 1, at.call(18.0, -6.0 + i * 2.0), taken).id)
		for i in 3:
			theirs.append(_put(w, "grenadier", 1, at.call(19.0, -3.0 + i * 3.0), taken).id)
		w.cmd_move(ours, at.call(13.0, 0.0))
		w.cmd_move(theirs, at.call(12.0, 0.0))
		w.update_fog()
		mid = hq.pos + dir * _env("FWD", 13.0)
		game.view.yaw = _env("YAW", 0.0)
		game.view.focus = Vector3(mid.x, 0, mid.y)
		game.view.dist = _env("DIST", 15.0)
		game.view.update_camera()
		print("hq ", hq.pos, " dir ", dir, " map ", w.width, "x", w.height)
	# The README shot is frame 240: both armies are firing and two shells are exploding.
	var shot := int(_env("SHOT_FRAME", 240.0))
	if frame == shot:
		_save("battle.png")
		get_tree().quit()


func _save(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name))
	var a := 0
	var b := 0
	for u: SimUnit in game.world.units.values():
		if not u.is_structure():
			if u.team == 0: a += 1
			else: b += 1
	print("saved ", name, " t=", game.world.time, " ours ", a, " theirs ", b)
