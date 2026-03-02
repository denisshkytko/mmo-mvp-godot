@tool
extends "res://game/world/spawners/base_spawner_group.gd"

class_name NamSpawnerGroup
const COMBAT_RANGES := preload("res://core/combat/combat_ranges.gd")

const MOB_SCENE: PackedScene = preload("res://game/characters/mobs/NormalAggressiveMob.tscn")
## LootProfile is a global class (class_name). Avoid shadowing.

enum Behavior { GUARD, PATROL }

@export_group("Mob Setup")
@export var loot_profile: LootProfile = preload("res://core/loot/profiles/loot_profile_aggressive_default.tres") as LootProfile
@export var level_min: int = 1
@export var level_max: int = 1
@export_enum("Paladin", "Warrior", "Shaman", "Mage", "Priest", "Hunter")
var class_choice: int:
	get:
		return _class_choice_internal
	set(v):
		_class_choice_internal = int(v)
		spell_preset_id = _sanitize_spell_preset_for_class(spell_preset_id)
		notify_property_list_changed()
var spell_preset_id: String = "none":
	get:
		return _spell_preset_id_internal
	set(v):
		_spell_preset_id_internal = _sanitize_spell_preset_for_class(v)
@export_enum("Normal", "Rare", "Elite") var mob_variant: int = 0


@export_group("Behavior After Spawn")
@export_enum("Guard", "Patrol") var behavior: int = Behavior.GUARD
@export var patrol_radius: float = COMBAT_RANGES.PATROL_RADIUS
@export var patrol_pause_seconds: float = 1.5

# Class selection config
const CLASS_IDS := ["paladin", "warrior", "shaman", "mage", "priest", "hunter"]
const C_PALADIN := 0
const C_WARRIOR := 1
const C_SHAMAN := 2
const C_MAGE := 3
const C_PRIEST := 4
const C_HUNTER := 5

var _class_choice_internal: int = C_PALADIN
var _spell_preset_id_internal: String = "none"

# BaseSpawnerGroup уже содержит respawn_seconds


func _get_property_list() -> Array[Dictionary]:
	var props: Array[Dictionary] = []
	props.append({
		"name": "Mob Setup/spell_preset_id",
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": _build_spell_preset_hint(),
		"usage": PROPERTY_USAGE_DEFAULT,
	})
	return props

func _set(property: StringName, value: Variant) -> bool:
	if String(property) == "Mob Setup/spell_preset_id":
		spell_preset_id = String(value)
		return true
	return false

func _get(property: StringName) -> Variant:
	if String(property) == "Mob Setup/spell_preset_id":
		return spell_preset_id
	return null

func _build_spell_preset_hint() -> String:
	var cls := _get_current_class_id()
	match cls:
		"mage":
			return "none:Нет,mage_fire_caster,mage_ice_caster"
		"hunter":
			return "none:Нет,hunter_hunter"
		"warrior":
			return "none:Нет,warrior_warrior"
		"priest":
			return "none:Нет,priest_novice"
		"paladin":
			return "none:Нет,paladin_knight"
		"shaman":
			return "none:Нет,shaman_elementalist"
		_:
			return "none:Нет"


func _get_spawn_scene() -> PackedScene:
	return MOB_SCENE


func _compute_level() -> int:
	var lvl: int = level_min
	if level_max > level_min:
		lvl = randi_range(level_min, level_max)
	return lvl


func _call_apply_spawn_init(mob: Node, point: SpawnPoint, level: int) -> bool:
	# ВАЖНО: не задаём aggro_radius из группы, чтобы ты мог менять
	# его в каждой сущности отдельно (в инспекторе самого моба).
	# Поэтому aggro_radius_in = -1.0.
	var class_id: String = CLASS_IDS[_class_choice_internal]
	var profile_id := "humanoid_hostile"
	var abilities_for_level := MobSpellPresetDB.resolve_ability_ids_for_level(spell_preset_id, class_id, level)
	var preset_name_key := MobSpellPresetDB.get_preset_name_key(spell_preset_id)
	mob.call_deferred(
		"apply_spawn_init",
		point.global_position,
		behavior,
		-1.0, # aggro_radius не задаём
		-1.0, # leash_distance is defined on the mob itself
		COMBAT_RANGES.PATROL_RADIUS,
		patrol_pause_seconds,
		-1.0, # move_speed is defined on the mob itself
		level,
		"",              # mob_id больше не используется
		loot_profile,
		class_id,
		profile_id,
		mob_variant,
		abilities_for_level,
		preset_name_key
	)
	return true

func _get_current_class_id() -> String:
	return CLASS_IDS[_class_choice_internal]

func _sanitize_spell_preset_for_class(value: String) -> String:
	var class_id := _get_current_class_id()
	return MobSpellPresetDB.get_allowed_preset_id(value, class_id)
