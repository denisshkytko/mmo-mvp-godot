extends RefCounted
class_name Progression

const MAX_LEVEL: int = 60
const HOSTILE_TARGET_MULT: float = 2.2

const CLASS_IDS: Array = [
	"paladin",
	"shaman",
	"mage",
	"priest",
	"hunter",
	"warrior",
	"beast",
]

const PROFILE_IDS: Array = [
	"player_default",
	"npc_citizen",
	"humanoid_hostile",
	"beast_small",
	"beast_medium",
	"beast_large",
]

const DEBUG_LOGS: bool = false

const CLASS_TABLE: Dictionary = {
	"paladin": {
		"base_primary": {"str": 12, "agi": 8, "end": 11, "int": 8, "per": 7},
		"per_level": {"str": 2, "agi": 1, "end": 2, "int": 1, "per": 1},
		"resource_type": "mana",
	},
	"shaman": {
		"base_primary": {"str": 8, "agi": 9, "end": 9, "int": 10, "per": 8},
		"per_level": {"str": 1, "agi": 1, "end": 1, "int": 2, "per": 1},
		"resource_type": "mana",
	},
	"mage": {
		"base_primary": {"str": 5, "agi": 8, "end": 6, "int": 14, "per": 10},
		"per_level": {"str": 0, "agi": 1, "end": 1, "int": 3, "per": 2},
		"resource_type": "mana",
	},
	"priest": {
		"base_primary": {"str": 6, "agi": 7, "end": 7, "int": 13, "per": 9},
		"per_level": {"str": 1, "agi": 1, "end": 1, "int": 2, "per": 2},
		"resource_type": "mana",
	},
	"hunter": {
		"base_primary": {"str": 8, "agi": 13, "end": 8, "int": 7, "per": 10},
		"per_level": {"str": 1, "agi": 2, "end": 1, "int": 1, "per": 2},
		"resource_type": "mana",
	},
	"warrior": {
		"base_primary": {"str": 13, "agi": 9, "end": 12, "int": 5, "per": 6},
		"per_level": {"str": 3, "agi": 1, "end": 2, "int": 0, "per": 1},
		"resource_type": "rage",
	},
	"beast": {
		"base_primary": {"str": 11, "agi": 10, "end": 9, "int": 2, "per": 6},
		"per_level": {"str": 2, "agi": 2, "end": 1, "int": 0, "per": 1},
		"resource_type": "rage",
	},
}

static func is_valid_class_id(class_id: String) -> bool:
	return CLASS_TABLE.has(class_id)

static func is_valid_profile_id(profile_id: String) -> bool:
	return PROFILE_IDS.has(profile_id)

static func get_class_def(class_id: String) -> Dictionary:
	if not is_valid_class_id(class_id):
		push_warning("Progression: invalid class_id '%s', falling back to warrior." % class_id)
		return CLASS_TABLE.get("warrior", {}).duplicate(true)
	return CLASS_TABLE.get(class_id, {}).duplicate(true)

static func get_primary_multiplier(profile_id: String, level: int) -> float:
	level = clamp(level, 1, MAX_LEVEL)
	match profile_id:
		"player_default", "npc_citizen":
			return 1.0
		"humanoid_hostile":
			if level <= 10:
				return 1.0
			var t: float = float(level - 10) / float(MAX_LEVEL - 10)
			var ease: float = t * t * (3.0 - 2.0 * t)
			var mult: float = 1.0 + (HOSTILE_TARGET_MULT - 1.0) * ease
			if DEBUG_LOGS and (level == 10 or level == 60):
				print("Progression hostile mult lvl=%d -> %.3f" % [level, mult])
			return mult
		"beast_small":
			return 0.75
		"beast_medium":
			return 1.05
		"beast_large":
			if level <= 10:
				return 1.0
			var t2: float = float(level - 10) / float(MAX_LEVEL - 10)
			var ease2: float = t2 * t2 * (3.0 - 2.0 * t2)
			return 1.0 + (2.0 - 1.0) * ease2
		_:
			return 1.0

static func calc_primary_at_level(level: int, base_primary: Dictionary, per_level: Dictionary) -> Dictionary:
	level = clamp(level, 1, MAX_LEVEL)
	var out := {}
	for k in ["str", "agi", "end", "int", "per"]:
		var base_v: int = int(base_primary.get(k, 0))
		var per_v: int = int(per_level.get(k, 0))
		out[k] = base_v + per_v * (level - 1)
	return out

static func get_primary_for_entity(level: int, class_id: String, profile_id: String) -> Dictionary:
	var class_def := get_class_def(class_id)
	var base_primary: Dictionary = class_def.get("base_primary", {}) as Dictionary
	var per_level: Dictionary = class_def.get("per_level", {}) as Dictionary
	var primary := calc_primary_at_level(level, base_primary, per_level)
	var mult: float = get_primary_multiplier(profile_id, level)
	var out := {}
	for k in ["str", "agi", "end", "int", "per"]:
		var v: float = float(primary.get(k, 0))
		out[k] = max(0, int(round(v * mult)))
	return out

static func get_base_primary(class_id: String) -> Dictionary:
	var def := get_class_def(class_id)
	return (def.get("base_primary", {}) as Dictionary).duplicate(true)

static func get_per_level(class_id: String) -> Dictionary:
	var def := get_class_def(class_id)
	return (def.get("per_level", {}) as Dictionary).duplicate(true)
