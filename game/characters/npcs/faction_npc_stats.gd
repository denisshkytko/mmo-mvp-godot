extends Node
class_name FactionNPCStats

const STAT_CALC := preload("res://core/stats/stat_calculator.gd")
const STAT_CONST := preload("res://core/stats/stat_constants.gd")
const PROG := preload("res://core/stats/progression.gd")

enum FighterType { CIVILIAN, FIGHTER, MAGE }

var npc_level: int = 1
var fighter_type: int = FighterType.FIGHTER
var class_id: String = ""
var growth_profile_id: String = ""

var base_primary: Dictionary = {"str": 10, "agi": 0, "end": 6, "int": 0, "per": 0}
var primary_per_level: Dictionary = {"str": 2, "agi": 0, "end": 1, "int": 0, "per": 0}

# Baseline mitigation growth for NPCs
var base_defense: int = 2
var defense_per_level: int = 1
var base_magic_resist: int = 0
var magic_resist_per_level: int = 0

var max_hp: int = 50
var current_hp: int = 50
var attack_value: int = 6
var defense_value: int = 2
var is_dead: bool = false

var _snapshot: Dictionary = {}

func apply_primary_preset(
	base_primary_in: Dictionary,
	primary_per_level_in: Dictionary,
	base_defense_in: int,
	defense_per_level_in: int,
	base_magic_resist_in: int,
	magic_resist_per_level_in: int
) -> void:
	base_primary = base_primary_in.duplicate(true)
	primary_per_level = primary_per_level_in.duplicate(true)
	base_defense = base_defense_in
	defense_per_level = defense_per_level_in
	base_magic_resist = base_magic_resist_in
	magic_resist_per_level = magic_resist_per_level_in


func recalc(level:int) -> void:
	npc_level = max(1, level)

	var base_primary_use := base_primary
	var per_level_use := primary_per_level
	if class_id != "":
		var profile_id := growth_profile_id
		if profile_id == "":
			if fighter_type == FighterType.CIVILIAN:
				profile_id = "npc_citizen"
			else:
				profile_id = "humanoid_hostile"
		var primary_int := PROG.get_primary_for_entity(npc_level, class_id, profile_id)
		_snapshot = STAT_CALC.build_mob_snapshot_from_primary_values(
			npc_level,
			primary_int,
			base_defense,
			defense_per_level,
			base_magic_resist,
			magic_resist_per_level
		)
	else:
		if OS.is_debug_build() and npc_level == 1:
			print("Faction NPC legacy primary path (class_id empty).")
		_snapshot = STAT_CALC.build_mob_snapshot_from_primary(
			npc_level,
			base_primary_use,
			per_level_use,
			base_defense,
			defense_per_level,
			base_magic_resist,
			magic_resist_per_level
		)

	var d: Dictionary = _snapshot.get("derived", {}) as Dictionary
	max_hp = int(d.get("max_hp", max_hp))
	attack_value = int(round(float(d.get("attack_power", attack_value))))
	defense_value = int(round(float(d.get("defense", defense_value))))
	current_hp = clamp(current_hp, 0, max_hp)

func apply_damage(raw: int) -> bool:
	if is_dead:
		return false

	var d: Dictionary = _snapshot.get("derived", {}) as Dictionary
	var def_v: float = float(d.get("defense", defense_value))
	var mult: float = STAT_CONST.MITIGATION_K / (STAT_CONST.MITIGATION_K + max(0.0, def_v))
	var dmg: int = max(1, int(round(float(raw) * mult)))
	current_hp = max(0, current_hp - dmg)
	return current_hp <= 0

func get_stats_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)
