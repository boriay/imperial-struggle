class_name SimUnit
extends RefCounted

enum FireMode { HOLD, RETURN, FREE }

const FIRE_MODE_NAMES := ["on order", "return fire", "at will"]

var id := 0
var team := 0
var type := ""
## Position in cells; the center of cell (x, y) is (x + 0.5, y + 0.5).
var pos := Vector2.ZERO
var hp := 0.0
var max_hp := 0.0
var morale := 100.0
var path := PackedVector2Array()
var chasing := false
## Came to help: does not get closer to the target than this (0 = no limit).
var help_stop := 0.0
## The hard AI pulled this wounded unit back for healing.
var ai_retreat := false
## The hard AI sent this unit to raid harvesters.
var ai_raider := false
var repath_left := 0.0
var target_queue: Array[int] = []
var attack_point: Variant = null
var fire_mode := FireMode.RETURN
var hold_position := false
var reload_left := 0.0
var facing := 0.0
var turret := 0.0
var last_attacker := -1
## When and at whom the unit last fired: this is how neighbours know a fight is on.
var fired_at := -100.0
var fired_target := -1
var moving := false
## How many seconds the unit has been trying to move while barely moving.
var stuck_time := 0.0
var _progress_pos := Vector2.ZERO

# Buildings: top-left cell, construction progress and production queue.
var origin := Vector2i.ZERO
var build_progress := 1.0
var queue: Array[String] = []
var queue_progress := 0.0

# Harvester.
var cargo := 0.0
var harvest_state := "seek"
var harvest_cell := Vector2i(-1, -1)
## The player sent the harvester by hand; gathering resumes when it arrives.
## Same for the medic and the engineer: while following an order they do not look for wounded.
var manual := false

# Medic and engineer: whom it heals or repairs, and whether healing is happening right now.
var assist_id := -1
## The player has already seen this enemy building: in the fog it shows at its last known place.
var seen := false
var healing := false

# What the unit does this tick; the renderer reads it.
var aim_id := -1
var aim_pos: Variant = null
var aim_auto := false


func stats() -> Dictionary:
	return UnitTypes.DATA[type]


func cell() -> Vector2i:
	return Vector2i(floori(pos.x), floori(pos.y))


func is_armored() -> bool:
	return stats().armored


func is_structure() -> bool:
	return stats().get("structure", false)


func is_complete() -> bool:
	return build_progress >= 1.0


func can_fight() -> bool:
	return stats().range > 0.0


func is_support() -> bool:
	return stats().has("heal_rate")


## A medic heals infantry; an engineer repairs vehicles and finished buildings.
func can_assist(t: SimUnit) -> bool:
	if not is_support() or t == null or t == self or t.team != team or t.hp <= 0.0:
		return false
	if stats().heals == "infantry":
		return not t.is_armored()
	return t.is_armored() and t.is_complete()
