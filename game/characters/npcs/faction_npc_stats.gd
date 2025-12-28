extends Node
class_name FactionNPCStats

enum FighterType { CIVILIAN, FIGHTER, MAGE }

var npc_level: int = 1
var fighter_type: int = FighterType.FIGHTER

var base_attack: int = 6
var attack_per_level: int = 1
var base_max_hp: int = 50
var hp_per_level: int = 10
var base_defense: int = 2
var defense_per_level: int = 1

var max_hp: int = 50
var current_hp: int = 50
var attack_value: int = 6
var defense_value: int = 2
var is_dead: bool = false

func apply_preset(a0:int, a_pl:int, hp0:int, hp_pl:int, d0:int, d_pl:int) -> void:
	base_attack=a0; attack_per_level=a_pl
	base_max_hp=hp0; hp_per_level=hp_pl
	base_defense=d0; defense_per_level=d_pl

func recalc(level:int) -> void:
	npc_level = max(1, level)
	max_hp = int(base_max_hp + (npc_level-1)*hp_per_level)
	attack_value = int(base_attack + (npc_level-1)*attack_per_level)
	defense_value = int(base_defense + (npc_level-1)*defense_per_level)
	current_hp = clamp(current_hp, 0, max_hp)

func apply_damage(raw: int) -> bool:
	if is_dead:
		return false

	var dmg: int = max(1, raw - defense_value)
	current_hp = max(0, current_hp - dmg)
	return current_hp <= 0
