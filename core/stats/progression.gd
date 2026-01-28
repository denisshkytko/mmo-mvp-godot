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
		"base_primary": {"str": 12.0, "agi": 8.0, "end": 12.0, "int": 12.0, "per": 7.0},
		"per_level": {"str": 1.2, "agi": 0.8, "end": 1.2, "int": 1.2, "per": 0.8},
		"resource_type": "mana",
		"base_melee_attack_interval": 1.60,
		"attack_role": "melee",
		"allowed_armor_classes": ["cloth", "leather", "mail"],
		"base_equipment": {
			"shirt": "armor_common_cloth_shirt_rl01_0545",
			"chest": "armor_common_cloth_chest_rl01_0698",
			"legs": "armor_common_mail_legs_rl01_0509",
			"boots": "armor_common_mail_boots_rl01_0599",
		},
		"allowed_weapon_types": [
			"sword_1h",
			"sword_2h",
			"mace_1h",
			"mace_2h",
			"shield",
			"offhand",
		],
	},
	"shaman": {
		"base_primary": {"str": 8.0, "agi": 9.0, "end": 9.0, "int": 10.0, "per": 8.0},
		"per_level": {"str": 0.9, "agi": 0.8, "end": 1.0, "int": 1.4, "per": 0.7},
		"resource_type": "mana",
		"base_melee_attack_interval": 1.75,
		"npc_base_ranged_attack_interval": 1.75,
		"attack_role": "hybrid",
		"allowed_armor_classes": ["cloth", "leather"],
		"base_equipment": {
			"shirt": "armor_common_cloth_shirt_rl01_0545",
			"chest": "armor_common_cloth_chest_rl01_0698",
			"legs": "armor_common_leather_legs_rl01_0518",
		},
		"allowed_weapon_types": [
			"staff_2h",
			"mace_1h",
			"axe_1h",
			"shield",
			"offhand",
		],
	},
	"mage": {
		"base_primary": {"str": 5.0, "agi": 8.0, "end": 6.0, "int": 14.0, "per": 10.0},
		"per_level": {"str": 0.2, "agi": 0.8, "end": 0.9, "int": 1.7, "per": 1.2},
		"resource_type": "mana",
		"base_melee_attack_interval": 1.95,
		"npc_base_ranged_attack_interval": 1.60,
		"attack_role": "ranged",
		"allowed_armor_classes": ["cloth"],
		"base_equipment": {
			"shirt": "armor_common_cloth_shirt_rl01_0545",
			"chest": "armor_common_cloth_chest_rl01_0698",
		},
		"allowed_weapon_types": [
			"staff_2h",
			"wand_1h",
			"sword_1h",
			"dagger_1h",
			"offhand",
		],
	},
	"priest": {
		"base_primary": {"str": 6.0, "agi": 7.0, "end": 7.0, "int": 13.0, "per": 9.0},
		"per_level": {"str": 0.6, "agi": 0.7, "end": 0.9, "int": 1.3, "per": 1.1},
		"resource_type": "mana",
		"base_melee_attack_interval": 1.90,
		"npc_base_ranged_attack_interval": 1.70,
		"attack_role": "ranged",
		"allowed_armor_classes": ["cloth"],
		"base_equipment": {
			"shirt": "armor_common_cloth_shirt_rl01_0545",
			"chest": "armor_common_cloth_chest_rl01_0698",
		},
		"allowed_weapon_types": [
			"staff_2h",
			"wand_1h",
			"sword_1h",
			"mace_1h",
			"offhand",
		],
	},
	"hunter": {
		"base_primary": {"str": 9.0, "agi": 14.0, "end": 9.0, "int": 10.0, "per": 10.0},
		"per_level": {"str": 0.8, "agi": 1.4, "end": 0.9, "int": 1.0, "per": 1.2},
		"resource_type": "mana",
		"base_melee_attack_interval": 1.80,
		"npc_base_ranged_attack_interval": 1.70,
		"attack_role": "hybrid",
		"allowed_armor_classes": ["cloth", "leather"],
		"base_equipment": {
			"shirt": "armor_common_cloth_shirt_rl01_0545",
			"chest": "armor_common_cloth_chest_rl01_0698",
			"legs": "armor_common_leather_legs_rl01_0518",
		},
		"allowed_weapon_types": [
			"bow_2h",
			"crossbow_2h",
			"dagger_1h",
			"sword_1h",
			"axe_1h",
		],
	},
	"warrior": {
		"base_primary": {"str": 14.0, "agi": 10.0, "end": 13.0, "int": 4.0, "per": 6.0},
		"per_level": {"str": 1.4, "agi": 1.0, "end": 1.3, "int": 0.3, "per": 0.6},
		"resource_type": "rage",
		"base_melee_attack_interval": 1.50,
		"attack_role": "melee",
		"allowed_armor_classes": ["cloth", "leather", "mail"],
		"base_equipment": {
			"shirt": "armor_common_cloth_shirt_rl01_0545",
			"chest": "armor_common_cloth_chest_rl01_0698",
			"legs": "armor_common_mail_legs_rl01_0509",
			"boots": "armor_common_mail_boots_rl01_0599",
		},
		"allowed_weapon_types": [
			"sword_1h",
			"sword_2h",
			"axe_1h",
			"axe_2h",
			"mace_1h",
			"mace_2h",
			"dagger_1h",
			"shield",
		],
	},
	"beast": {
		"base_primary": {"str": 11.0, "agi": 10.0, "end": 9.0, "int": 2.0, "per": 6.0},
		"per_level": {"str": 1.2, "agi": 1.1, "end": 0.9, "int": 0.2, "per": 0.6},
		"resource_type": "rage",
		"base_melee_attack_interval": 1.70,
		"attack_role": "melee",
		"allowed_armor_classes": [],
		"base_equipment": {},
		"allowed_weapon_types": [],
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

static func get_class_data(class_id: String) -> Dictionary:
	return get_class_def(class_id)

static func get_resource_type_for_class(class_id: String) -> String:
	var d: Dictionary = get_class_data(class_id)
	var t := String(d.get("resource_type", "mana")).strip_edges()
	return t if t != "" else "mana"

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
			return 0.25
		"beast_medium":
			return 0.75
		"beast_large":
			return 1.25
		_:
			return 1.0

static func calc_primary_at_level(level: int, base_primary: Dictionary, per_level: Dictionary) -> Dictionary:
	level = clamp(level, 1, MAX_LEVEL)
	var out := {}
	for k in ["str", "agi", "end", "int", "per"]:
		var base_v: float = float(base_primary.get(k, 0.0))
		var per_v: float = float(per_level.get(k, 0.0))
		out[k] = base_v + per_v * float(level - 1)
	return out

static func floor_primary(p: Dictionary) -> Dictionary:
	return {
		"str": int(floor(float(p.get("str", 0.0)))),
		"agi": int(floor(float(p.get("agi", 0.0)))),
		"end": int(floor(float(p.get("end", 0.0)))),
		"int": int(floor(float(p.get("int", 0.0)))),
		"per": int(floor(float(p.get("per", 0.0)))),
	}

static func get_primary_for_entity(level: int, class_id: String, profile_id: String) -> Dictionary:
	var class_def := get_class_def(class_id)
	var base_primary: Dictionary = class_def.get("base_primary", {}) as Dictionary
	var per_level: Dictionary = class_def.get("per_level", {}) as Dictionary
	var primary := calc_primary_at_level(level, base_primary, per_level)
	var mult: float = get_primary_multiplier(profile_id, level)
	var out := {}
	for k in ["str", "agi", "end", "int", "per"]:
		var v: float = float(primary.get(k, 0))
		primary[k] = v * mult
	out = floor_primary(primary)
	for k in out.keys():
		out[k] = max(0, int(out.get(k, 0)))
	return out

static func get_base_primary_float(class_id: String) -> Dictionary:
	var def := get_class_def(class_id)
	return (def.get("base_primary", {}) as Dictionary).duplicate(true)

static func get_per_level_float(class_id: String) -> Dictionary:
	var def := get_class_def(class_id)
	return (def.get("per_level", {}) as Dictionary).duplicate(true)

static func get_base_primary_int(class_id: String) -> Dictionary:
	return floor_primary(get_base_primary_float(class_id))

static func get_per_level_int(class_id: String) -> Dictionary:
	return floor_primary(get_per_level_float(class_id))

static func get_base_primary(class_id: String) -> Dictionary:
	return get_base_primary_int(class_id)

static func get_per_level(class_id: String) -> Dictionary:
	return get_per_level_int(class_id)

static func get_attack_role_for_class(class_id: String) -> String:
	if not is_valid_class_id(class_id):
		return "melee"
	var def := CLASS_TABLE.get(class_id, {}) as Dictionary
	var role := String(def.get("attack_role", "melee")).strip_edges()
	return role if role != "" else "melee"

static func get_base_melee_attack_interval_for_class(class_id: String) -> float:
	if not is_valid_class_id(class_id):
		return 1.80
	var def := CLASS_TABLE.get(class_id, {}) as Dictionary
	return float(def.get("base_melee_attack_interval", 1.80))

static func get_npc_base_ranged_attack_interval_for_class(class_id: String) -> float:
	if not is_valid_class_id(class_id):
		return 1.80
	var def := CLASS_TABLE.get(class_id, {}) as Dictionary
	return float(def.get("npc_base_ranged_attack_interval", 1.80))

static func get_allowed_weapon_types_for_class(class_id: String) -> Array[String]:
	if not is_valid_class_id(class_id):
		return []
	var def := CLASS_TABLE.get(class_id, {}) as Dictionary
	var allowed: Array[String] = []
	var raw: Variant = def.get("allowed_weapon_types", [])
	if raw is Array:
		for entry in raw:
			var val := String(entry).strip_edges()
			if val != "":
				allowed.append(val)
	return allowed

static func get_allowed_armor_classes_for_class(class_id: String) -> Array[String]:
	if not is_valid_class_id(class_id):
		return []
	var def := CLASS_TABLE.get(class_id, {}) as Dictionary
	var allowed: Array[String] = []
	var raw: Variant = def.get("allowed_armor_classes", [])
	if raw is Array:
		for entry in raw:
			var val := String(entry).strip_edges()
			if val != "":
				allowed.append(val)
	return allowed

static func get_base_equipment_for_class(class_id: String) -> Dictionary:
	var def := get_class_def(class_id)
	var equip := def.get("base_equipment", {}) as Dictionary
	return equip.duplicate(true)
