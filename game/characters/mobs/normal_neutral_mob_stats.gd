extends Node
class_name NormalNeutralMobStats

const STAT_CALC := preload("res://core/stats/stat_calculator.gd")
const STAT_CONST := preload("res://core/stats/stat_constants.gd")

enum BodySize { SMALL, MEDIUM, LARGE, HUMANOID }

var mob_level: int = 1
var body_size: int = BodySize.MEDIUM

# Эти поля заполняются на основе body_size
var base_primary: Dictionary = {"str": 8, "agi": 0, "end": 5, "int": 0, "per": 0}
var primary_per_level: Dictionary = {"str": 1, "agi": 0, "end": 1, "int": 0, "per": 0}

# Baseline mitigation growth for mobs (so they don't become too "paper")
var base_defense: int = 1
var defense_per_level: int = 1
var base_magic_resist: int = 0
var magic_resist_per_level: int = 0

var max_hp: int = 40
var current_hp: int = 40
var defense_value: int = 1
var attack_value: int = 5

var is_dead: bool = false

var _snapshot: Dictionary = {}

# Пресеты по размерам (редактируемые в инспекторе через экспорт в Mob-скрипте)
func apply_body_preset(
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

func recalculate_for_level(level: int) -> void:
	mob_level = max(1, level)

	_snapshot = STAT_CALC.build_mob_snapshot_from_primary(
		mob_level,
		base_primary,
		primary_per_level,
		base_defense,
		defense_per_level,
		base_magic_resist,
		magic_resist_per_level
	)

	var d: Dictionary = _snapshot.get("derived", {}) as Dictionary
	max_hp = int(d.get("max_hp", max_hp))
	defense_value = int(round(float(d.get("defense", defense_value))))
	attack_value = int(round(float(d.get("attack_power", attack_value))))

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

	var d: Dictionary = _snapshot.get("derived", {}) as Dictionary
	var def_v: float = float(d.get("defense", defense_value))
	var mult: float = STAT_CONST.MITIGATION_K / (STAT_CONST.MITIGATION_K + max(0.0, def_v))
	var dmg: int = max(1, int(round(float(raw_damage) * mult)))
	current_hp = max(0, current_hp - dmg)
	return current_hp <= 0

func get_stats_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)

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
