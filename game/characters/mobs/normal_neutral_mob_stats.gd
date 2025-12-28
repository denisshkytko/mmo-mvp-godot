extends Node
class_name NormalNeutralMobStats

enum BodySize { SMALL, MEDIUM, LARGE, HUMANOID }

var mob_level: int = 1
var body_size: int = BodySize.MEDIUM

# Эти поля заполняются на основе body_size
var base_attack: int = 5
var attack_per_level: int = 1

var base_max_hp: int = 40
var hp_per_level: int = 8

var base_defense: int = 1
var defense_per_level: int = 1

var max_hp: int = 40
var current_hp: int = 40
var defense_value: int = 1
var attack_value: int = 5

var is_dead: bool = false

# Пресеты по размерам (редактируемые в инспекторе через экспорт в Mob-скрипте, см. ниже)
func apply_body_preset(
	base_attack_in: int,
	attack_per_level_in: int,
	base_max_hp_in: int,
	hp_per_level_in: int,
	base_defense_in: int,
	defense_per_level_in: int
) -> void:
	base_attack = base_attack_in
	attack_per_level = attack_per_level_in
	base_max_hp = base_max_hp_in
	hp_per_level = hp_per_level_in
	base_defense = base_defense_in
	defense_per_level = defense_per_level_in

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

	# ВАЖНО: нейтрал не должен сбрасывать HP при пересчёте, чтобы реген работал корректно.
	current_hp = clamp(current_hp, 0, max_hp)

func apply_damage(raw_damage: int) -> bool:
	if is_dead:
		return false

	var dmg: int = max(1, raw_damage - defense_value)
	current_hp = max(0, current_hp - dmg)
	return current_hp <= 0

func heal_percent_per_second(delta: float, percent_per_sec: float) -> void:
	if is_dead:
		return
	if current_hp >= max_hp:
		return

	var heal_amount: int = int(round(float(max_hp) * percent_per_sec * delta))
	if heal_amount <= 0:
		heal_amount = 1
	current_hp = min(max_hp, current_hp + heal_amount)

func update_hp_bar(hp_fill: ColorRect) -> void:
	if hp_fill == null:
		return
	if max_hp <= 0:
		return
	var ratio: float = clamp(float(current_hp) / float(max_hp), 0.0, 1.0)
	hp_fill.size.x = 36.0 * ratio
