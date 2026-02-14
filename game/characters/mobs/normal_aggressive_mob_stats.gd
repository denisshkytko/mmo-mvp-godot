extends Node
class_name NormalAggresiveMobStats

const STAT_CALC := preload("res://core/stats/stat_calculator.gd")
const PROG := preload("res://core/stats/progression.gd")
const MOB_VARIANT := preload("res://core/stats/mob_variant.gd")

var mob_level: int = 1

var base_primary: Dictionary = {"str": 10, "agi": 0, "end": 6, "int": 0, "per": 0}
var primary_per_level: Dictionary = {"str": 2, "agi": 0, "end": 1, "int": 0, "per": 0}
var class_id: String = ""
var growth_profile_id: String = ""
var mob_variant: int = MOB_VARIANT.MobVariant.NORMAL

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

	var variant := MOB_VARIANT.clamp_variant(mob_variant)
	var primary_multiplier := MOB_VARIANT.primary_mult(variant)
	var defense_multiplier := MOB_VARIANT.defense_mult(variant)

	var base_primary_use := base_primary
	var per_level_use := primary_per_level
	if class_id != "":
		var profile_id := growth_profile_id if growth_profile_id != "" else "humanoid_hostile"
		var primary_int := PROG.get_primary_for_entity(mob_level, class_id, profile_id)
		primary_int = _scale_primary(primary_int, primary_multiplier)
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
			print("Aggressive mob legacy primary path (class_id empty).")
		base_primary_use = _scale_primary(base_primary_use, primary_multiplier)
		per_level_use = _scale_primary(per_level_use, primary_multiplier)
		_snapshot = STAT_CALC.build_mob_snapshot_from_primary(
			mob_level,
			base_primary_use,
			per_level_use,
			base_defense,
			defense_per_level,
			base_magic_resist,
			magic_resist_per_level
		)

	_apply_rage_mana_override()
	_apply_defense_multiplier(defense_multiplier)

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

func _apply_rage_mana_override() -> void:
	if class_id == "":
		return
	if PROG.get_resource_type_for_class(class_id) != "rage":
		return
	var derived: Dictionary = _snapshot.get("derived", {}) as Dictionary
	derived["max_mana"] = 0
	derived["mana_regen"] = 0
	_snapshot["derived"] = derived

func _scale_primary(primary: Dictionary, mult: float) -> Dictionary:
	if mult == 1.0:
		return primary.duplicate(true)
	var out: Dictionary = {}
	for key in primary.keys():
		out[key] = float(primary.get(key, 0)) * mult
	return out

func _apply_defense_multiplier(mult: float) -> void:
	if mult == 1.0:
		return
	var derived: Dictionary = _snapshot.get("derived", {}) as Dictionary
	var defense := float(derived.get("defense", defense_value)) * mult
	var magic_resist := float(derived.get("magic_resist", 0.0)) * mult
	derived["defense"] = defense
	derived["magic_resist"] = magic_resist
	_snapshot["derived"] = derived
	var phys_reduction := STAT_CALC._mitigation_pct(defense)
	var magic_reduction := STAT_CALC._mitigation_pct(magic_resist)
	_snapshot["physical_reduction_pct"] = phys_reduction
	_snapshot["magic_reduction_pct"] = magic_reduction
	_snapshot["defense_mitigation_pct"] = phys_reduction
	_snapshot["magic_mitigation_pct"] = magic_reduction

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



var _status_effects: Dictionary = {}

func tick_status_effects(delta: float) -> void:
	if _status_effects.is_empty():
		return
	var to_remove: Array[String] = []
	for k in _status_effects.keys():
		var id: String = String(k)
		var entry: Dictionary = _status_effects[id] as Dictionary
		var left: float = float(entry.get("time_left", 0.0))
		if left >= 999999.0:
			continue
		left -= delta
		if left <= 0.0:
			to_remove.append(id)
		else:
			entry["time_left"] = left
			_status_effects[id] = entry
	if to_remove.is_empty():
		return
	for id in to_remove:
		_status_effects.erase(id)

func add_or_refresh_buff(id: String, duration_sec: float, data: Dictionary = {}, ability_id: String = "", source: String = "") -> void:
	if id == "":
		return
	var left := duration_sec
	if left <= 0.0:
		left = 999999.0
	_status_effects[id] = {
		"time_left": left,
		"data": data.duplicate(true),
		"ability_id": ability_id if ability_id != "" else String(data.get("ability_id", "")),
		"source": source if source != "" else String(data.get("source", "")),
	}

func get_buffs_snapshot() -> Array:
	var arr: Array = []
	for k in _status_effects.keys():
		var id: String = String(k)
		var entry: Dictionary = _status_effects[id] as Dictionary
		arr.append({
			"id": id,
			"time_left": float(entry.get("time_left", 0.0)),
			"data": entry.get("data", {}) as Dictionary,
			"ability_id": String(entry.get("ability_id", "")),
			"source": String(entry.get("source", "")),
		})
	return arr

func get_attack_speed_multiplier() -> float:
	var mult: float = 1.0
	for k in _status_effects.keys():
		var id: String = String(k)
		var entry: Dictionary = _status_effects[id] as Dictionary
		var data: Dictionary = entry.get("data", {}) as Dictionary
		var cur: float = float(data.get("attack_speed_multiplier", 1.0))
		if cur > 0.0 and cur != 1.0:
			mult *= cur
	if mult <= 0.0:
		return 1.0
	return mult
func get_stats_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)

func apply_damage(raw_physical_damage: int) -> bool:
	if is_dead:
		return false

	var reduction_pct: float
	if _snapshot.has("physical_reduction_pct"):
		reduction_pct = float(_snapshot.get("physical_reduction_pct", 0.0))
	else:
		var d: Dictionary = _snapshot.get("derived", {}) as Dictionary
		var def_v: float = float(d.get("defense", defense_value))
		reduction_pct = STAT_CALC._mitigation_pct(def_v)
	var dmg: int = int(ceil(float(raw_physical_damage) * (1.0 - reduction_pct / 100.0)))
	dmg = max(1, dmg)

	current_hp = max(0, current_hp - dmg)
	return current_hp <= 0

func update_hp_bar(hp_fill: ColorRect) -> void:
	if hp_fill == null:
		return
	if max_hp <= 0:
		return

	var ratio: float = clamp(float(current_hp) / float(max_hp), 0.0, 1.0)
	hp_fill.size.x = 36.0 * ratio
