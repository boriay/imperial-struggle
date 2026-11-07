class_name UnitTypes
extends RefCounted

## Base stats. Range in cells, reload and build time
## in seconds, speed in cells per second, cost in crystals.
const DATA := {
	"rifleman": {
		"vision": 7.0,
		"name": "Rifleman", "hp": 50.0, "range": 5.0, "reload": 3.0,
		"speed": 1.0, "accuracy": 0.75, "dmg_inf": 20.0, "dmg_armor": 4.0,
		"dmg_wall": 4.0, "splash": false, "armored": false,
		"cost": 50, "build_time": 8.0,
	},
	"grenadier": {
		"vision": 6.0,
		"name": "Grenadier", "hp": 50.0, "range": 3.0, "reload": 6.0,
		"speed": 1.0, "accuracy": 0.6, "dmg_inf": 40.0, "dmg_armor": 140.0,
		"dmg_wall": 80.0, "splash": true, "armored": false,
		"cost": 80, "build_time": 10.0,
	},
	"tank": {
		"vision": 8.0,
		"name": "Tank", "hp": 300.0, "range": 7.0, "reload": 5.0,
		"speed": 1.43, "accuracy": 0.7, "dmg_inf": 70.0, "dmg_armor": 120.0,
		"dmg_wall": 100.0, "splash": true, "armored": true, "turret_speed": 60.0,
		"cost": 250, "build_time": 20.0,
	},
	"harvester": {
		"vision": 5.0,
		"name": "Harvester", "hp": 220.0, "range": 0.0, "reload": 1.0,
		"speed": 1.2, "accuracy": 0.0, "dmg_inf": 0.0, "dmg_armor": 0.0,
		"dmg_wall": 0.0, "splash": false, "armored": true,
		"cost": 150, "build_time": 15.0, "capacity": 50.0, "harvest_rate": 10.0,
	},
	# Support: they do not shoot and look for wounded within assist_range cells on their own.
	"medic": {
		"vision": 6.0,
		"name": "Medic", "hp": 40.0, "range": 0.0, "reload": 1.0,
		"speed": 1.1, "accuracy": 0.0, "dmg_inf": 0.0, "dmg_armor": 0.0,
		"dmg_wall": 0.0, "splash": false, "armored": false,
		"cost": 60, "build_time": 8.0,
		"heal_rate": 6.0, "heals": "infantry", "assist_range": 7.0,
	},
	"engineer": {
		"vision": 6.0,
		"name": "Engineer", "hp": 45.0, "range": 0.0, "reload": 1.0,
		"speed": 1.0, "accuracy": 0.0, "dmg_inf": 0.0, "dmg_armor": 0.0,
		"dmg_wall": 0.0, "splash": false, "armored": false,
		"cost": 80, "build_time": 10.0,
		"heal_rate": 15.0, "heals": "armor", "assist_range": 7.0,
	},
	"hq": {
		"vision": 7.0,
		"name": "HQ", "hp": 1200.0, "range": 0.0, "reload": 1.0, "speed": 0.0,
		"accuracy": 0.0, "dmg_inf": 0.0, "dmg_armor": 0.0, "dmg_wall": 0.0,
		"splash": false, "armored": true, "structure": true, "size": 2,
		"cost": 0, "build_time": 1.0, "produces": ["medic", "engineer"],
	},
	"barracks": {
		"vision": 5.0,
		"name": "Barracks", "hp": 500.0, "range": 0.0, "reload": 1.0, "speed": 0.0,
		"accuracy": 0.0, "dmg_inf": 0.0, "dmg_armor": 0.0, "dmg_wall": 0.0,
		"splash": false, "armored": true, "structure": true, "size": 2,
		"cost": 200, "build_time": 20.0, "produces": ["rifleman", "grenadier"],
	},
	"factory": {
		"vision": 5.0,
		"name": "Factory", "hp": 800.0, "range": 0.0, "reload": 1.0, "speed": 0.0,
		"accuracy": 0.0, "dmg_inf": 0.0, "dmg_armor": 0.0, "dmg_wall": 0.0,
		"splash": false, "armored": true, "structure": true, "size": 2,
		"cost": 350, "build_time": 30.0, "produces": ["tank", "harvester"],
	},
	# Turret: stays in place and fires at the nearest enemy on its own, but a target can
	# also be set by hand. Own walls nearby do not block its fire.
	"turret": {
		"vision": 8.0,
		"name": "Turret", "hp": 450.0, "range": 7.0, "reload": 2.5, "speed": 0.0,
		"accuracy": 0.75, "dmg_inf": 30.0, "dmg_armor": 70.0, "dmg_wall": 30.0,
		"splash": false, "armored": true, "structure": true, "size": 1,
		"turret_speed": 90.0, "cost": 150, "build_time": 15.0, "produces": [],
	},
}

## What the player can build.
const BUILDABLE := ["barracks", "factory", "turret"]
