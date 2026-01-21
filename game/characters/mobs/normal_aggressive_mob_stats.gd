extends Node
class_name NormalAggresiveMobStats

const STAT_CALC := preload("res://core/stats/stat_calculator.gd")
const STAT_CONST := preload("res://core/stats/stat_constants.gd")
const PROG := preload("res://core/stats/progression.gd")

var mob_level: int = 1

var base_primary: Dictionary = {"str": 10, "agi": 0, "end": 6, "int": 0, "per": 0}
var primary_per_level: Dictionary = {"str": 2, "agi": 0, "end": 1, "int": 0, "per": 0}
var class_id: String = ""
var growth_profile_id: String = ""

# Baseline mitigation growth for mobs (so they don't become too "paper")
var base_defense: int = 0
var defense_per_level: int = 1
var base_magic_resist: int = 0
var magic_resist_per_level: int = 0

var max_hp: int = 50
var current_hp: int = 50
var defense_value: int = 1
# Unify naming with other units (NNM/NPC/mob scripts expect attack_value)
var attack_value: int = 0

var is_dead: bool = false

var _snapshot: Dictionary = {}

func recalculate_for_level(level: int) -> void:
	mob_level = max(1, level)

	var base_primary_use := base_primary
	var per_level_use := primary_per_level
	if class_id != "":
		var profile_id := growth_profile_id if growth_profile_id != "" else "humanoid_hostile"
		var primary_int := PROG.get_primary_for_entity(mob_level, class_id, profile_id)
		if OS.is_debug_build() and (mob_level == 10 or mob_level == 60):
			var mult := PROG.get_primary_multiplier(profile_id, mob_level)
			print("Aggressive mob L%d mult=%.2f primary=%s" % [mob_level, mult, str(primary_int)])
		_snapshot = STAT_CALC.build_mob_snapshot_from_primary_values(
			mob_level,
			primary_int,
			base_defense,
			defense_per_level,
			base_magic_resist,
			magic_resist_per_level
		)
	else:
		if OS.is_debug_build() and mob_level == 1:
			print("Aggressive mob legacy primary path.")
		_snapshot = STAT_CALC.build_mob_snapshot_from_primary(
			mob_level,
			base_primary_use,
			per_level_use,
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
	if defense_value < 0:
		defense_value = 0
	if attack_value < 1:
		attack_value = 1

	current_hp = max_hp

func setup_primary_profile(
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

func get_stats_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)

func apply_damage(raw_physical_damage: int) -> bool:
	if is_dead:
		return false

	var d: Dictionary = _snapshot.get("derived", {}) as Dictionary
	var def_v: float = float(d.get("defense", defense_value))
	var mult: float = STAT_CONST.MITIGATION_K / (STAT_CONST.MITIGATION_K + max(0.0, def_v))
	var dmg: int = max(1, int(round(float(raw_physical_damage) * mult)))

	current_hp = max(0, current_hp - dmg)
	return current_hp <= 0

func update_hp_bar(hp_fill: ColorRect) -> void:
	if hp_fill == null:
		return
	if max_hp <= 0:
		return

	var ratio: float = clamp(float(current_hp) / float(max_hp), 0.0, 1.0)
	hp_fill.size.x = 36.0 * ratio
