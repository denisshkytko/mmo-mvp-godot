extends Node
class_name NormalAggresiveMobStats

var mob_level: int = 1

var base_attack: int = 8
var attack_per_level: int = 2

var base_max_hp: int = 50
var hp_per_level: int = 12

var base_defense: int = 1
var defense_per_level: int = 1

var max_hp: int = 50
var current_hp: int = 50
var defense_value: int = 1
var attack_value: int = 8

var is_dead: bool = false

func recalculate_for_level(level: int) -> void:
	mob_level = max(1, level)

	max_hp = int(base_max_hp + (mob_level - 1) * hp_per_level)
	defense_value = int(base_defense + (mob_level - 1) * defense_per_level)
	attack_value = int(base_attack + (mob_level - 1) * attack_per_level)

	if max_hp < 10:
		max_hp = 10
	if defense_value < 1:
		defense_value = 1
	if attack_value < 1:
		attack_value = 1

	current_hp = max_hp

func apply_damage(raw_damage: int) -> bool:
	if is_dead:
		return false

	var dmg: int = max(1, raw_damage - defense_value)
	current_hp = max(0, current_hp - dmg)

	return current_hp <= 0

func update_hp_bar(hp_fill: ColorRect) -> void:
	if hp_fill == null:
		return
	if max_hp <= 0:
		return

	var ratio: float = clamp(float(current_hp) / float(max_hp), 0.0, 1.0)
	hp_fill.size.x = 36.0 * ratio
