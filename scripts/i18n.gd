class_name I18n
extends RefCounted

## Interface languages. The strings in the code are English and are shown through tr();
## the Russian translation is the RU table below. The chosen language is saved to
## user://settings.cfg and restored on the next launch. The default is English.

const LANGUAGES := [["en", "English"], ["ru", "Русский"]]
const DEFAULT := "en"
const SETTINGS_PATH := "user://settings.cfg"

const RU := {
	# Units, buildings, sides, AI levels, fire modes.
	"Rifleman": "Стрелок",
	"Grenadier": "Гранатомётчик",
	"Tank": "Танк",
	"Harvester": "Харвестер",
	"Medic": "Медик",
	"Engineer": "Ремонтник",
	"HQ": "Штаб",
	"Barracks": "Казарма",
	"Factory": "Завод",
	"Turret": "Турель",
	"Empire": "Империя",
	"Rebels": "Повстанцы",
	"Easy": "Лёгкий",
	"Normal": "Обычный",
	"Hard": "Сложный",
	"Ruthless": "Безжалостный",
	"on order": "по приказу",
	"return fire": "ответный",
	"at will": "свободный",

	# Maps.
	"Wasteland": "Пустошь",
	"An open plain with ruined walls": "Открытая равнина с руинами стен",
	"River": "Река",
	"The river can only be crossed at fords": "Реку можно перейти только по бродам",
	"Lakes": "Озёра",
	"Lakes split the field into passages": "Озёра делят поле на проходы",
	"Fortresses": "Крепости",
	"Every base is behind a ring of walls with gates": "Каждая база за кольцом стен с воротами",
	"Maze": "Лабиринт",
	"A maze of walls fills the middle of the map": "Середину карты занимает лабиринт стен",
	"Canyon": "Каньон",
	"Three canyons between water, blocked by walls": "Три каньона между водой, перегороженные стенами",
	"City": "Город",
	"Blocks of ruins and streets between them": "Кварталы руин и улицы между ними",
	"Marsh": "Болота",
	"Many puddles and little cover": "Множество луж и редкие укрытия",
	"Channels": "Протоки",
	"Three rivers and narrow bridges across them": "Три реки и узкие мосты через них",
	"Great Maze": "Большой лабиринт",
	"A maze across the whole map": "Лабиринт через всю карту",

	# Order panel and hints.
	"LMB: select (drag a box, Shift adds). RMB: move, attack or heal your own, Shift+RMB: queue a target. Space: pause. Wheel or pinch: zoom; right-drag, cursor at the edge, arrows or two fingers: camera; Q/E: rotate. M: maps, N: sound, F11: window/fullscreen.":
		"ЛКМ — выбрать (рамка, Shift — добавить). ПКМ — идти, атаковать или лечить своего, Shift+ПКМ — в очередь целей. Пробел — пауза. Колесо или щипок — масштаб, протяжка правой кнопкой, курсор у края, стрелки или два пальца — камера, Q/E — поворот. M — карты, N — звук, F11 — окно/весь экран.",
	"Tactical pause: the game stops, but you can still give orders.": "Тактическая пауза: игра стоит, а приказы отдавать можно.",
	"Game speed: ×0.5, ×1 or ×2.": "Скорость игры: ×0,5, ×1 или ×2.",
	"Attack: the next click on an enemy makes it the target. Shift adds it to a queue of up to 3 targets.":
		"Атаковать: следующий клик по врагу назначит его целью. Shift — добавить в очередь до 3 целей.",
	"Fire at a point: shoot at a cell instead of a unit. Use it to break walls or to shell a spot.":
		"Огонь по точке: стрелять в клетку, а не в юнита. Нужен, чтобы ломать стены или накрыть место взрывом.",
	"Stop: cancel movement and all targets.": "Стоп: отменить движение и все цели.",
	"Hold position: do not move even if the target is out of range. Without it the unit closes in on its target.":
		"Держать позицию: не сходить с места, даже если цель вне досягаемости. Без этого юнит сам подходит к цели.",
	"How to fire without orders. On order: only at the assigned target. Return fire: at whoever hit it. At will: at the nearest enemy (accuracy −30%).":
		"Как стрелять без приказа. По приказу: только по назначенной цели. Ответный: по тому, кто попал. Свободный: по ближайшему врагу (точность −30%).",
	"Attack: click an enemy.": "Атака: кликните по врагу.",
	"Fire at a point: click a cell, for example a wall.": "Огонь по точке: кликните по клетке, например по стене.",
	"Construction: click next to your base. Shift places another one, RMB or Esc cancels.":
		"Постройка: кликните рядом со своей базой. Shift — поставить ещё одно, ПКМ или Esc — отмена.",
	"Pause (Space)": "Пауза (Пробел)",
	"Resume (Space)": "Продолжить (Пробел)",
	"Speed ×%s (1–3)": "Скорость ×%s (1–3)",
	"Attack (A)": "Атака (A)",
	"Fire at point (G)": "Огонь по точке (G)",
	"Stop (S)": "Стоп (S)",
	"Hold position (H)": "Держать позицию (H)",
	"Fire (F)": "Огонь (F)",
	"Fire: %s (F)": "Огонь: %s (F)",
	"TACTICAL PAUSE: give your orders": "ТАКТИЧЕСКАЯ ПАУЗА — отдавайте приказы",
	"Cancel last": "Отменить последний",
	"Sell +%d (Del)": "Продать +%d (Del)",
	"Build: %s (%d) (%s)": "Построить: %s (%d) (%s)",

	# Status and info lines.
	"Crystals: %d · %02d:%02d · speed ×%s · ours: %d · enemies: %d": "Кристаллы: %d · %02d:%02d · скорость ×%s · наши: %d · враги: %d",
	"%s · Map %d: %s · AI: %s · %s": "%s · Карта %d: %s · ИИ: %s · %s",
	"%s · health %d/%d": "%s · здоровье %d/%d",
	" · building %d%%": " · стройка %d%%",
	" · fire: %s · target: %s": " · огонь: %s · цель: %s",
	" · queue: %s (%d%%)": " · очередь: %s (%d%%)",
	"Enemy: %s · health %d/%d": "Противник: %s · здоровье %d/%d",
	" · under construction": " · строится",
	" · morale %d": " · мораль %d",
	"Nothing selected": "Никто не выбран",
	" (picked itself)": " (сам выбрал)",
	"%s · health %d/%d · morale %d · target: %s": "%s · здоровье %d/%d · мораль %d · цель: %s",
	"%s · health %d/%d · %s": "%s · здоровье %d/%d · %s",
	"%s · health %d/%d · cargo %d/%d": "%s · здоровье %d/%d · груз %d/%d",
	"looking for someone to heal": "ищет, кого лечить",
	"looking for something to repair": "ищет, кого чинить",
	"Selected: %d": "Выбрано: %d",
	"point": "точка",
	"none": "нет",
	"heals": "лечит",
	"repairs": "чинит",

	# Notices and labels over the field.
	"Not enough crystals": "Не хватает кристаллов",
	"You cannot build here: you need a free spot next to your base": "Здесь строить нельзя: нужно свободное место рядом с базой",
	"The queue is full or the unit limit is reached": "Очередь полна или достигнут предел юнитов",
	"Building sold: +%d crystals": "Здание продано: +%d кристаллов",
	"Sound off": "Звук выключен",
	"Sound on": "Звук включён",
	"building %d%%": "стройка %d%%",
	"no line of fire": "нет линии огня",
	"Enemy: %s": "Враг: %s",
	"H": "Д",

	# Menu and end of battle.
	"Campaign: 10 maps. After a victory the next one starts. M: menu, Esc: back to battle.":
		"Кампания: 10 карт. После победы начинается следующая. M — меню, Esc — назад в бой.",
	"Play as:": "Играть за:",
	"Enemy:": "Противник:",
	"Language:": "Язык:",
	"Next map": "Следующая карта",
	"Restart (R)": "Начать заново (R)",
	"Choose map": "Выбор карты",
	"Campaign complete!": "Кампания пройдена!",
	"Victory! Map %d of %d": "Победа! Карта %d из %d",
	"Defeat": "Поражение",
}

static var _registered := false


## Registers the translations and switches to the saved language. Called once at startup.
static func setup() -> void:
	if not _registered:
		var t := Translation.new()
		t.locale = "ru"
		for key: String in RU:
			t.add_message(key, RU[key])
		TranslationServer.add_translation(t)
		_registered = true
	# Godot would otherwise follow the system language; the game starts in English
	# until the player picks another language.
	TranslationServer.set_locale(saved_language())


static func current() -> String:
	return TranslationServer.get_locale().substr(0, 2)


static func saved_language() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		var lang: String = cfg.get_value("general", "language", DEFAULT)
		for l: Array in LANGUAGES:
			if l[0] == lang:
				return lang
	return DEFAULT


## Switches the interface language and remembers the choice for the next launch.
static func set_language(lang: String) -> void:
	TranslationServer.set_locale(lang)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("general", "language", lang)
	cfg.save(SETTINGS_PATH)
