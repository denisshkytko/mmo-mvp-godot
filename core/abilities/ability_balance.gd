extends RefCounted
class_name AbilityBalance

# Runtime normalization layer for offensive abilities.
# Goals:
# - fast casts are less efficient,
# - long casts / long cooldowns are rewarded,
# - magic school does not consistently outperform physical school.

static func apply_damage_balance(base_damage: int, rank_data: RankData, context: Dictionary, school: String) -> int:
	if base_damage <= 0 or rank_data == null:
		return base_damage

	var cast_time: float = max(0.0, float(rank_data.cast_time_sec))
	var cooldown: float = max(0.0, float(rank_data.cooldown_sec))
	var resource_cost: float = max(0.0, float(rank_data.resource_cost))

	var cast_factor: float = _cast_factor(cast_time)
	var cooldown_factor: float = _cooldown_factor(cooldown)
	var resource_factor: float = _resource_factor(resource_cost)
	var school_factor: float = _school_factor(school)
	var class_factor: float = _class_factor(context)

	var total_factor: float = cast_factor * cooldown_factor * resource_factor * school_factor * class_factor
	# Keep room for manual spell tuning in data while preventing extremes from normalization.
	total_factor = clamp(total_factor, 0.70, 1.45)
	return max(1, int(round(float(base_damage) * total_factor)))


static func _cast_factor(cast_time: float) -> float:
	if cast_time <= 0.5:
		return 0.82
	if cast_time <= 1.0:
		return 0.90
	if cast_time <= 2.0:
		return 1.00
	if cast_time <= 3.0:
		return 1.12
	if cast_time <= 4.0:
		return 1.24
	return 1.32


static func _cooldown_factor(cooldown: float) -> float:
	if cooldown < 3.0:
		return 1.00
	if cooldown < 6.0:
		return 1.05
	if cooldown < 10.0:
		return 1.12
	if cooldown < 20.0:
		return 1.20
	return 1.28


static func _resource_factor(cost: float) -> float:
	if cost <= 0.0:
		return 1.0
	# +0..10% reward for expensive casts.
	var t: float = clamp(cost / 40.0, 0.0, 1.0)
	return 1.0 + t * 0.10


static func _school_factor(school: String) -> float:
	# Slight down-bias for magic to keep parity with physical in broad average.
	return 0.94 if String(school).to_lower() == "magic" else 1.0


static func _class_factor(context: Dictionary) -> float:
	if context == null:
		return 1.0
	var def_v: Variant = context.get("ability_def", null)
	if def_v == null or not (def_v is AbilityDefinition):
		return 1.0
	var def: AbilityDefinition = def_v as AbilityDefinition
	match String(def.class_id).to_lower():
		"mage", "priest":
			return 0.96
		"hunter", "warrior":
			return 1.03
		_:
			return 1.0
