@tool
extends "res://game/world/spawners/base_spawner_group.gd"

class_name NnmSpawnerGroup
const COMBAT_RANGES := preload("res://core/combat/combat_ranges.gd")

const MOB_SCENE: PackedScene = preload("res://game/characters/mobs/NormalNeutralMob.tscn")

enum Behavior { GUARD, PATROL }
enum BodySize { SMALL, MEDIUM, LARGE, HUMANOID }

@export_group("Neutral Setup")
@export var loot_profile_animals: LootProfile = preload("res://core/loot/profiles/loot_profile_neutral_animal_default.tres") as LootProfile
@export var loot_profile_humanoids: LootProfile = preload("res://core/loot/profiles/loot_profile_neutral_humanoid_default.tres") as LootProfile
@export var level_min: int = 1
@export var level_max: int = 1
@export_enum("Small", "Medium", "Large", "Humanoid")
var body_size: int:
	get:
		return _body_size_internal
	set(v):
		_body_size_internal = int(v)
		spell_preset_id = _sanitize_spell_preset_for_class(spell_preset_id)
		notify_property_list_changed()
@export var skin_id: String = ""
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
var _spell_preset_id_internal: String = "none"
var _body_size_internal: int = BodySize.MEDIUM


func _get_property_list() -> Array[Dictionary]:
	var props: Array[Dictionary] = []
	props.append({
		"name": "Neutral Setup/spell_preset_id",
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": _build_spell_preset_hint(),
		"usage": PROPERTY_USAGE_DEFAULT,
	})
	return props

func _set(property: StringName, value: Variant) -> bool:
	if String(property) == "Neutral Setup/spell_preset_id":
		spell_preset_id = String(value)
		return true
	return false

func _get(property: StringName) -> Variant:
	if String(property) == "Neutral Setup/spell_preset_id":
		return spell_preset_id
	return null

func _build_spell_preset_hint() -> String:
	if _get_current_class_id() == "hunter":
		return "none:Нет,hunter_hunter"
	return "none:Нет"

func _get_spawn_scene() -> PackedScene:
	return MOB_SCENE


func _compute_level() -> int:
	var lvl: int = level_min
	if level_max > level_min:
		lvl = randi_range(level_min, level_max)
	return lvl


func _call_apply_spawn_init(mob: Node, point: SpawnPoint, level: int) -> bool:
	var chosen_profile: LootProfile = loot_profile_animals
	if body_size == BodySize.HUMANOID:
		chosen_profile = loot_profile_humanoids
	if chosen_profile == null:
		# Safety: never spawn a neutral mob without a loot profile.
		chosen_profile = preload("res://core/loot/profiles/loot_profile_neutral_animal_default.tres") as LootProfile

	var class_id := ""
	var profile_id := ""
	if body_size == BodySize.HUMANOID:
		class_id = "hunter"
		profile_id = "humanoid_hostile"
	else:
		class_id = "beast"
		match body_size:
			BodySize.SMALL:
				profile_id = "beast_small"
			BodySize.MEDIUM:
				profile_id = "beast_medium"
			BodySize.LARGE:
				profile_id = "beast_large"

	if OS.is_debug_build() and level == 1:
		print("[SPAWN][NNM] body_size=", body_size, " class_id=", class_id, " profile_id=", profile_id)
	var abilities_for_level := MobSpellPresetDB.resolve_ability_ids_for_level(spell_preset_id, class_id, level)
	var preset_name_key := MobSpellPresetDB.get_preset_name_key(spell_preset_id)

	mob.call_deferred(
		"apply_spawn_init",
		point.global_position,
		behavior,
		-1.0, # leash_distance is defined on the mob itself
		COMBAT_RANGES.PATROL_RADIUS,
		patrol_pause_seconds,
		-1.0, # move_speed is defined on the mob itself
		level,
		body_size,
		skin_id,
		chosen_profile,
		class_id,
		profile_id,
		mob_variant,
		abilities_for_level,
		preset_name_key
	)
	return true

func _get_current_class_id() -> String:
	if body_size == BodySize.HUMANOID:
		return "hunter"
	return "beast"

func _sanitize_spell_preset_for_class(value: String) -> String:
	var class_id := _get_current_class_id()
	return MobSpellPresetDB.get_allowed_preset_id(value, class_id)
