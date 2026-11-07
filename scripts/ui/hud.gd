class_name Hud
extends CanvasLayer

## Order panel and hints. The buttons are big so they will also suit the iPad later.
## All text goes through tr(); retranslate() refreshes the fixed labels after a language change.

signal action(name: String)

const HINT := "LMB: select (drag a box, Shift adds). RMB: move, attack or heal your own, Shift+RMB: queue a target. Space: pause. Wheel or pinch: zoom; right-drag, cursor at the edge, arrows or two fingers: camera; Q/E: rotate. M: maps, N: sound, F11: window/fullscreen."
const TOOLTIPS := {
	"pause": "Tactical pause: the game stops, but you can still give orders.",
	"speed": "Game speed: ×0.5, ×1 or ×2.",
	"attack": "Attack: the next click on an enemy makes it the target. Shift adds it to a queue of up to 3 targets.",
	"point": "Fire at a point: shoot at a cell instead of a unit. Use it to break walls or to shell a spot.",
	"stop": "Stop: cancel movement and all targets.",
	"hold": "Hold position: do not move even if the target is out of range. Without it the unit closes in on its target.",
	"fire_mode": "How to fire without orders. On order: only at the assigned target. Return fire: at whoever hit it. At will: at the nearest enemy (accuracy −30%).",
}
const MODE_HINTS := {
	"attack": "Attack: click an enemy.",
	"point": "Fire at a point: click a cell, for example a wall.",
	"place": "Construction: click next to your base. Shift places another one, RMB or Esc cancels.",
}

var status_label: Label
var info_label: Label
var hint_label: Label
var pause_label: Label
var end_panel: PanelContainer
var end_label: Label
var buttons := {}
var next_button: Button
var menu_panel: PanelContainer
var faction_buttons := {}
var level_buttons: Array[Button] = []
var language_buttons := {}
## Fixed texts: [control, property, Callable that returns the text in the current language].
var _texts: Array = []
var prod_row: HFlowContainer
var _prod_ids: Array = []
var _prod_buttons: Array[Button] = []


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font_size = 18
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.09, 0.1, 0.85)
	panel_style.set_content_margin_all(8)
	theme.set_stylebox("panel", "PanelContainer", panel_style)
	root.theme = theme
	# Texts are translated explicitly with tr(), so Godot must not translate them again.
	root.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(root)

	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	root.add_child(top)
	var top_box := VBoxContainer.new()
	top.add_child(top_box)
	status_label = Label.new()
	top_box.add_child(status_label)
	hint_label = Label.new()
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.add_theme_font_size_override("font_size", 15)
	hint_label.modulate = Color(1, 1, 1, 0.75)
	top_box.add_child(hint_label)

	var bottom := PanelContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(bottom)
	var bottom_box := VBoxContainer.new()
	bottom.add_child(bottom_box)
	info_label = Label.new()
	bottom_box.add_child(info_label)
	prod_row = HFlowContainer.new()
	bottom_box.add_child(prod_row)
	var row := HFlowContainer.new()
	bottom_box.add_child(row)
	for spec in [["pause", ""], ["speed", ""], ["attack", "Attack (A)"],
			["point", "Fire at point (G)"], ["stop", "Stop (S)"], ["hold", "Hold position (H)"],
			["fire_mode", ""]]:
		var b := Button.new()
		if spec[1] != "":
			_bind(b, "text", spec[1])
		b.custom_minimum_size = Vector2(0, 48)
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = spec[0] in ["attack", "point", "hold"]
		_bind(b, "tooltip_text", TOOLTIPS[spec[0]])
		var n: String = spec[0]
		b.pressed.connect(func(): action.emit(n))
		row.add_child(b)
		buttons[n] = b

	pause_label = Label.new()
	_bind(pause_label, "text", "TACTICAL PAUSE: give your orders")
	pause_label.add_theme_font_size_override("font_size", 26)
	pause_label.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	pause_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	pause_label.position.y = 90
	pause_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pause_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pause_label)

	end_panel = PanelContainer.new()
	end_panel.set_anchors_preset(Control.PRESET_CENTER)
	end_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	end_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(end_panel)
	var end_box := VBoxContainer.new()
	end_panel.add_child(end_box)
	end_label = Label.new()
	end_label.add_theme_font_size_override("font_size", 32)
	end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_box.add_child(end_label)
	next_button = _menu_button(end_box, "Next map", "next")
	_menu_button(end_box, "Restart (R)", "restart")
	_menu_button(end_box, "Choose map", "menu")

	# Map menu: the campaign goes in order, but any map can be opened right away.
	menu_panel = PanelContainer.new()
	menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	menu_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	menu_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(menu_panel)
	var menu_box := VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", 6)
	menu_panel.add_child(menu_box)
	var title := Label.new()
	title.text = "IMPERIAL STRUGGLE"
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_box.add_child(title)
	var sub := Label.new()
	_bind(sub, "text", "Campaign: 10 maps. After a victory the next one starts. M: menu, Esc: back to battle.")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(1, 1, 1, 0.75)
	menu_box.add_child(sub)
	# Side choice: Empire or Rebels.
	var side_row := HBoxContainer.new()
	side_row.alignment = BoxContainer.ALIGNMENT_CENTER
	menu_box.add_child(side_row)
	var side_label := Label.new()
	_bind(side_label, "text", "Play as:")
	side_row.add_child(side_label)
	for f in ["empire", "rebels"]:
		var b := _menu_button(side_row, BattleView.FACTIONS[f].name, "faction:" + f)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(220, 50)
		faction_buttons[f] = b
	var level_row := HBoxContainer.new()
	level_row.alignment = BoxContainer.ALIGNMENT_CENTER
	menu_box.add_child(level_row)
	var level_label := Label.new()
	_bind(level_label, "text", "Enemy:")
	level_row.add_child(level_label)
	for i in World.AI_LEVELS.size():
		var b := _menu_button(level_row, World.AI_LEVELS[i].name, "level:%d" % i)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(150, 50)
		level_buttons.append(b)
	var grid := GridContainer.new()
	grid.columns = 2
	menu_box.add_child(grid)
	for i in Scenario.count():
		var m: Dictionary = Scenario.MAPS[i]
		var b := _menu_button(grid, "", "map:%d" % i)
		_bind(b, "text", func() -> String: return "%d. %s — %s" % [i + 1, tr(m.name), tr(m.desc)])
		b.custom_minimum_size = Vector2(520, 46)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# Interface language; the language names are always shown in their own language.
	var lang_row := HBoxContainer.new()
	lang_row.alignment = BoxContainer.ALIGNMENT_CENTER
	menu_box.add_child(lang_row)
	var lang_label := Label.new()
	_bind(lang_label, "text", "Language:")
	lang_row.add_child(lang_label)
	for l: Array in I18n.LANGUAGES:
		var b := _menu_button(lang_row, "", "lang:" + l[0])
		b.text = l[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(150, 50)
		language_buttons[l[0]] = b
	retranslate()


## Sets all fixed texts again in the current language.
func retranslate() -> void:
	for e: Array in _texts:
		var c: Callable = e[2]
		e[0].set(e[1], c.call())
	_prod_ids = []


## Remembers a fixed text: src is an English string for tr() or a Callable that builds the text.
func _bind(control: Object, property: String, src: Variant) -> void:
	var c: Callable = src if src is Callable else func() -> String: return tr(src)
	_texts.append([control, property, c])
	control.set(property, c.call())


func refresh(game: Node) -> void:
	var w: World = game.world
	var t := int(w.time)
	status_label.text = tr("Crystals: %d · %02d:%02d · speed ×%s · ours: %d · enemies: %d") % [
		w.credits[0], t / 60, t % 60, str(game.SPEEDS[game.speed_idx]),
		w.count_mobile(0), w.count_mobile(1)]
	hint_label.text = tr(MODE_HINTS.get(game.mode, HINT))
	if game.notice_left > 0.0:
		hint_label.text = game.notice
	_refresh_actions(game.context_actions())
	pause_label.visible = game.paused and w.winner == -1
	buttons.pause.text = tr("Resume (Space)") if game.paused else tr("Pause (Space)")
	buttons.speed.text = tr("Speed ×%s (1–3)") % str(game.SPEEDS[game.speed_idx])
	buttons.attack.set_pressed_no_signal(game.mode == "attack")
	buttons.point.set_pressed_no_signal(game.mode == "point")

	var p: SimUnit = game.primary()
	var has_sel := p != null and not p.is_structure()
	var can_order := p != null and p.can_fight() and p.team == 0
	for n in ["attack", "point", "stop", "fire_mode"]:
		buttons[n].disabled = not can_order
	buttons.stop.disabled = not (can_order or has_sel)
	buttons.hold.disabled = not has_sel
	if can_order:
		buttons.hold.set_pressed_no_signal(p.hold_position and has_sel)
		buttons.fire_mode.text = tr("Fire: %s (F)") % tr(SimUnit.FIRE_MODE_NAMES[p.fire_mode])
	else:
		buttons.hold.set_pressed_no_signal(false)
		buttons.fire_mode.text = tr("Fire (F)")

	if p != null and p.is_structure():
		var line := tr("%s · health %d/%d") % [tr(p.stats().name), ceili(p.hp), int(p.max_hp)]
		if not p.is_complete():
			line += tr(" · building %d%%") % roundi(p.build_progress * 100.0)
		elif p.can_fight():
			var aim_t := w.get_unit(p.aim_id)
			line += tr(" · fire: %s · target: %s") % [tr(SimUnit.FIRE_MODE_NAMES[p.fire_mode]),
				tr(aim_t.stats().name) if aim_t != null else tr("point" if p.aim_pos != null else "none")]
		elif not p.queue.is_empty():
			var names: Array[String] = []
			for q: String in p.queue:
				names.append(tr(UnitTypes.DATA[q].name))
			line += tr(" · queue: %s (%d%%)") % [", ".join(names), roundi(p.queue_progress * 100.0)]
		info_label.text = line
	elif not has_sel:
		var e: SimUnit = w.get_unit(game.inspect_id)
		if e != null:
			var line := tr("Enemy: %s · health %d/%d") % [tr(e.stats().name), ceili(e.hp), int(e.max_hp)]
			if e.is_structure() and not e.is_complete():
				line += tr(" · under construction")
			elif not e.is_structure():
				line += tr(" · morale %d") % int(e.morale)
			info_label.text = line
		else:
			info_label.text = tr("Nothing selected")
	elif game.selected.size() == 1:
		var target := tr("none")
		var aim_unit := w.get_unit(p.aim_id)
		if aim_unit != null:
			target = tr(aim_unit.stats().name) + (tr(" (picked itself)") if p.aim_auto else "")
		elif p.aim_pos != null:
			target = tr("point")
		info_label.text = tr("%s · health %d/%d · morale %d · target: %s") % [
			tr(p.stats().name), ceili(p.hp), int(p.max_hp), int(p.morale), target]
		if p.is_support():
			var who := w.get_unit(p.assist_id)
			var medic: bool = p.type == "medic"
			var doing := ("%s: %s" % [tr("heals" if medic else "repairs"), tr(who.stats().name)]) if who != null \
				else tr("looking for someone to heal" if medic else "looking for something to repair")
			info_label.text = tr("%s · health %d/%d · %s") % [tr(p.stats().name), ceili(p.hp), int(p.max_hp), doing]
		if p.type == "harvester":
			info_label.text = tr("%s · health %d/%d · cargo %d/%d") % [
				tr(p.stats().name), ceili(p.hp), int(p.max_hp), int(p.cargo), int(p.stats().capacity)]
	else:
		info_label.text = tr("Selected: %d") % game.selected.size()

	menu_panel.visible = game.in_menu
	for f in faction_buttons:
		faction_buttons[f].set_pressed_no_signal(game.player_faction == f)
	for i in level_buttons.size():
		level_buttons[i].set_pressed_no_signal(game.ai_difficulty == i)
	for l in language_buttons:
		language_buttons[l].set_pressed_no_signal(I18n.current() == l)
	end_panel.visible = w.winner != -1 and not game.in_menu
	if w.winner != -1:
		var last: bool = game.map_index >= Scenario.count() - 1
		if w.winner == 0:
			end_label.text = tr("Campaign complete!") if last else tr("Victory! Map %d of %d") % [
				game.map_index + 1, Scenario.count()]
		else:
			end_label.text = tr("Defeat")
		next_button.visible = w.winner == 0 and not last
	var m: Dictionary = Scenario.MAPS[game.map_index]
	status_label.text = tr("%s · Map %d: %s · AI: %s · %s") % [tr(BattleView.FACTIONS[game.player_faction].name),
		game.map_index + 1, tr(m.name), tr(World.AI_LEVELS[game.ai_difficulty].name).to_lower(), status_label.text]


## Rebuilds the row of construction and production buttons only when the set changes.
func _refresh_actions(actions: Array) -> void:
	var ids: Array = actions.map(func(a): return a.id)
	if ids != _prod_ids:
		for b in _prod_buttons:
			b.queue_free()
		_prod_buttons.clear()
		_prod_ids = ids
		for a in actions:
			var b := Button.new()
			b.custom_minimum_size = Vector2(0, 44)
			b.focus_mode = Control.FOCUS_NONE
			b.toggle_mode = String(a.id).begins_with("build:")
			var n: String = a.id
			b.pressed.connect(func(): action.emit(n))
			prod_row.add_child(b)
			_prod_buttons.append(b)
	for i in actions.size():
		var b := _prod_buttons[i]
		b.text = actions[i].text
		b.disabled = not actions[i].enabled
		b.set_pressed_no_signal(actions[i].pressed)


func _menu_button(parent: Control, text: String, id: String) -> Button:
	var b := Button.new()
	if text != "":
		_bind(b, "text", text)
	b.custom_minimum_size = Vector2(280, 50)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): action.emit(id))
	parent.add_child(b)
	return b
