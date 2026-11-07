extends Node

## Screenshots to check rendering:
## xvfb-run godot --path . --fixed-fps 30 res://tests/screenshot.tscn -- <folder>

var game: Node3D
var frame := 0
var out_dir := "user://"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	game = load("res://main.tscn").instantiate()
	add_child(game)


func _process(_d: float) -> void:
	frame += 1
	if frame == 3:
		_save("menu.png")
		game.forced_slots = [5, 2]
		game.new_game(OS.get_environment("SHOT_MAP").to_int())
	if frame == 5:
		game.world.rng.seed = 7
		var hq: SimUnit = null
		for u: SimUnit in game.world.units.values():
			if u.team == 0 and u.type == "hq":
				hq = u
		for dx in range(2, 6):
			if game.world.cmd_build(0, "barracks", World.cell_of(hq.pos) + Vector2i(dx, 3)):
				break
		var army := []
		for u: SimUnit in game.world.units.values():
			if u.team == 0 and u.can_fight():
				army.append(u.id)
		game.world.cmd_move(army, World.cell_of(hq.pos) + Vector2i(10, 0))
		game.speed_idx = 2
	if frame == 330:
		for u: SimUnit in game.world.units.values():
			if u.team == 0 and u.type == "harvester":
				game.selected = [u.id]
				game.view.focus = Vector3(u.pos.x + 1.5, 0, u.pos.y - 1.0)
				game.view.dist = 8.0
				game.view.update_camera()
		game.mode = "place"
		game.place_type = "factory"
		game.hover_screen = game.view.project(Vector2(game.view.focus.x + 1.0, game.view.focus.z - 1.5), 0.0)
		game.paused = true
	if frame == 335:
		_save("shot1.png")
	if frame == 336:
		game.mode = ""
		game.paused = false
		game.view.dist = 34.0
		game.view.focus = Vector3(game.world.width / 2.0, 0, game.world.height / 2.0)
		game.view.update_camera()
		var army := []
		for u: SimUnit in game.world.units.values():
			if u.team == 0 and u.can_fight():
				army.append(u.id)
		game.selected = army
		for u: SimUnit in game.world.units.values():
			if u.team == 1 and not u.is_structure():
				game.world.cmd_attack(army, u.id, true)
	if frame == 690:
		for u: SimUnit in game.world.units.values():
			if u.team == 1 and not u.is_structure():
				game.selected = []
				game.order_select_at(game.view.project(game.render_pos(u), 0.27), false)
				game.hover_screen = game.view.project(game.render_pos(u), 0.27)
				break
	if frame == 700:
		_save("shot2.png")
		get_tree().quit()


func _save(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name))
	print("saved ", name, " t=", game.world.time, " units ", game.world.units.size(),
		" credits ", game.world.credits)
