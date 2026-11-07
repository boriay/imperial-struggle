extends Node

## Close-up of the factory, the barracks and soldiers.

var game: Node3D
var frame := 0


func _ready() -> void:
	game = load("res://main.tscn").instantiate()
	add_child(game)


func _process(_d: float) -> void:
	frame += 1
	if frame == 3:
		if OS.get_environment("FACTION") != "":
			game.player_faction = OS.get_environment("FACTION")
		game.forced_slots = [5, 2]
		game.new_game(0)
		var w: World = game.world
		var hq: SimUnit = null
		for u: SimUnit in w.units.values():
			if u.team == 0 and u.type == "hq":
				hq = u
		var c := World.cell_of(hq.pos)
		w.spawn_structure("factory", 0, c + Vector2i(4, -4))
		w.spawn_structure("barracks", 0, c + Vector2i(4, 2))
		w.spawn_structure("turret", 0, c + Vector2i(7, -2))
		var enemy := w.spawn("tank", 1, c + Vector2i(9, 1))
		enemy.fire_mode = SimUnit.FireMode.HOLD
		game.inspect_id = enemy.id
		w.spawn("rifleman", 1, c + Vector2i(10, 3)).fire_mode = SimUnit.FireMode.HOLD
		w.spawn("harvester", 1, c + Vector2i(11, 0))
		w.spawn_structure("turret", 1, c + Vector2i(12, 4))
		w.spawn_structure("barracks", 1, c + Vector2i(10, 6))
		w.update_fog()
		for i in 4:
			w.spawn("rifleman", 0, c + Vector2i(8, -1 + i))
		var hurt := w.spawn("grenadier", 0, c + Vector2i(5, 1))
		hurt.hp = 10.0
		w.spawn("medic", 0, c + Vector2i(6, 1))
		w.spawn("engineer", 0, c + Vector2i(2, 2))
		hq.hp = hq.max_hp * 0.6
		var army := []
		for u: SimUnit in w.units.values():
			if u.team == 0 and u.type == "rifleman":
				army.append(u.id)
		w.cmd_move(army, c + Vector2i(14, 0))
		game.view.focus = Vector3(hq.pos.x + 4.0, 0, hq.pos.y - 0.5)
		game.view.dist = 11.0
		game.view.update_camera()
	var out: String = OS.get_cmdline_user_args()[0]
	if OS.get_environment("FX") != "":
		_fx(out)
		return
	if frame == 90:
		get_viewport().get_texture().get_image().save_png(out)
		game.view.focus += Vector3(4.0, 0, 3.0)
		game.view.update_camera()
	if frame == 94:
		get_viewport().get_texture().get_image().save_png(out.replace(".png", "2.png"))
		game.view.focus = Vector3(game.world.width * 0.4, 0, game.world.height / 2.0)
		game.view.dist = 34.0
		game.view.update_camera()
	if frame == 98:
		get_viewport().get_texture().get_image().save_png(out.replace(".png", "3.png"))
		get_tree().quit()


## FX=1: close-up of an explosion and a destroyed tank, frames during and after the blast.
func _fx(out: String) -> void:
	var w: World = game.world
	if frame == 60:
		for u: SimUnit in w.units.values():
			if u.team == 1 and u.type == "tank":
				game.view.focus = Vector3(u.pos.x, 0, u.pos.y)
				game.view.dist = 7.0
				game.view.update_camera()
				w._kill(u)
				break
	if frame == 66:
		get_viewport().get_texture().get_image().save_png(out)
	if frame == 78:
		get_viewport().get_texture().get_image().save_png(out.replace(".png", "2.png"))
	if frame == 200:
		get_viewport().get_texture().get_image().save_png(out.replace(".png", "3.png"))
		get_tree().quit()
