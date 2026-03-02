extends RefCounted
class_name MobSpellPresetDB

const NONE_ID := "none"

const _PRESETS := {
	"mage_fire_caster": preload("res://core/data/mob_spell_presets/mage_fire_caster.tres"),
	"mage_ice_caster": preload("res://core/data/mob_spell_presets/mage_ice_caster.tres"),
	"hunter_hunter": preload("res://core/data/mob_spell_presets/hunter_hunter.tres"),
	"warrior_warrior": preload("res://core/data/mob_spell_presets/warrior_warrior.tres"),
	"priest_novice": preload("res://core/data/mob_spell_presets/priest_novice.tres"),
	"paladin_knight": preload("res://core/data/mob_spell_presets/paladin_knight.tres"),
	"shaman_elementalist": preload("res://core/data/mob_spell_presets/shaman_elementalist.tres"),
}

static func get_preset(preset_id: String) -> MobSpellPreset:
	if preset_id == "" or preset_id == NONE_ID:
		return null
	if not _PRESETS.has(preset_id):
		return null
	return _PRESETS[preset_id] as MobSpellPreset

static func get_preset_name_key(preset_id: String) -> String:
	var p := get_preset(preset_id)
	return p.name_key if p != null else ""

static func get_allowed_preset_id(preset_id: String, class_id: String) -> String:
	if preset_id == "" or preset_id == NONE_ID:
		return NONE_ID
	var p := get_preset(preset_id)
	if p == null:
		return NONE_ID
	if class_id != "" and p.class_id != "" and p.class_id != class_id:
		return NONE_ID
	return preset_id

static func resolve_ability_ids_for_level(preset_id: String, class_id: String, mob_level: int) -> Array[String]:
	var out: Array[String] = []
	var allowed_id := get_allowed_preset_id(preset_id, class_id)
	if allowed_id == NONE_ID:
		return out
	var p := get_preset(allowed_id)
	if p == null:
		return out
	if mob_level <= 10:
		return out
	if p.primary_ability_id != "":
		out.append(p.primary_ability_id)
	if mob_level >= 31 and p.secondary_ability_id_1 != "":
		out.append(p.secondary_ability_id_1)
	if mob_level >= 51 and p.secondary_ability_id_2 != "":
		out.append(p.secondary_ability_id_2)
	return out
