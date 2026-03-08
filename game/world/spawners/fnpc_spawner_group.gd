@tool
extends "res://game/world/spawners/base_spawner_group.gd"

class_name FnpcSpawnerGroup
const COMBAT_RANGES := preload("res://core/combat/combat_ranges.gd")

const NPC_SCENE: PackedScene = preload("res://game/characters/npcs/FactionNPC.tscn")
const DEFAULT_PROJECTILE: PackedScene = preload("res://game/characters/mobs/projectiles/HomingProjectile.tscn")
const MERCHANT_MODEL_SCENE: PackedScene = preload("res://game/characters/models/npcs/MerchantModel.tscn")
const TRAINER_MODEL_SCENE: PackedScene = preload("res://game/characters/models/npcs/TrainerModel.tscn")
const PALADIN_MODEL_SCENE: PackedScene = preload("res://game/characters/models/player/PaladinModel.tscn")
const WARRIOR_MODEL_SCENE: PackedScene = preload("res://game/characters/models/player/WarriorModel.tscn")
const SHAMAN_MODEL_SCENE: PackedScene = preload("res://game/characters/models/player/ShamanModel.tscn")
const MAGE_MODEL_SCENE: PackedScene = preload("res://game/characters/models/player/MageModel.tscn")
const PRIEST_MODEL_SCENE: PackedScene = preload("res://game/characters/models/player/PriestModel.tscn")
const HUNTER_MODEL_SCENE: PackedScene = preload("res://game/characters/models/player/HunterModel.tscn")

enum Behavior { GUARD, PATROL }
enum FighterType { CIVILIAN, COMBATANT }
enum InteractionType { NONE, MERCHANT, QUEST, TRAINER }
enum AttackRangeChoice { MELEE, RANGED }
enum ModelSceneChoice {
	NONE,
	MERCHANT,
	TRAINER,
	PALADIN,
	WARRIOR,
	SHAMAN,
	MAGE,
	PRIEST,
	HUNTER,
}

@export_group("Faction NPC Setup")
@export_enum("blue", "red", "yellow", "green") var faction_id: String = "blue"
@export_enum("Civilian", "Combatant") var fighter_type: int:
	get:
		return _fighter_type_internal
	set(v):
		_fighter_type_internal = clampi(int(v), FighterType.CIVILIAN, FighterType.COMBATANT)
		interaction_type = _sanitize_interaction_type(_interaction_type_internal)
		_sync_default_model_scene_choice()
		notify_property_list_changed()
@export_enum("None", "Merchant", "Quest", "Trainer") var interaction_type: int:
	get:
		return _interaction_type_internal
	set(v):
		_interaction_type_internal = _sanitize_interaction_type(int(v))
		_sync_default_model_scene_choice()
		notify_property_list_changed()
@export_enum("None", "Merchant", "Trainer", "Paladin", "Warrior", "Shaman", "Mage", "Priest", "Hunter") var model_scene_choice: int:
	get:
		return _model_scene_choice_internal
	set(v):
		_model_scene_choice_internal = clampi(int(v), ModelSceneChoice.NONE, ModelSceneChoice.HUNTER)
@export var merchant_preset: MerchantPreset = preload("res://core/trade/presets/merchant_preset_level_1.tres")

@export var loot_profile: LootProfile = preload("res://core/loot/profiles/loot_profile_faction_gold_only.tres") as LootProfile
@export var level_min: int = 1
@export var level_max: int = 1
@export_enum("Paladin", "Warrior", "Shaman", "Mage", "Priest", "Hunter")
var class_choice: int:
	get:
		return _class_choice_internal
	set(v):
		_class_choice_internal = int(v)
		attack_range_choice = _default_attack_range_for_class(_class_choice_internal)
		spell_preset_id = _sanitize_spell_preset_for_class(spell_preset_id)
		_sync_default_model_scene_choice()
		notify_property_list_changed()
@export var spell_preset_id: String = "none":
	get:
		return _spell_preset_id_internal
	set(v):
		_spell_preset_id_internal = _sanitize_spell_preset_for_class(v)
@export_enum("Normal", "Rare", "Elite") var mob_variant: int = 0
@export_enum("Melee", "Ranged") var attack_range_choice: int = AttackRangeChoice.MELEE

@export_group("Behavior After Spawn")
@export_enum("Guard", "Patrol") var behavior: int = Behavior.GUARD

@export var patrol_pause_seconds: float = 1.5

const CLASS_IDS := ["paladin", "warrior", "shaman", "mage", "priest", "hunter"]
const C_PALADIN := 0
const C_WARRIOR := 1
const C_SHAMAN := 2
const C_MAGE := 3
const C_PRIEST := 4
const C_HUNTER := 5
var _class_choice_internal: int = C_PALADIN
var _spell_preset_id_internal: String = "none"
var _fighter_type_internal: int = FighterType.CIVILIAN
var _interaction_type_internal: int = InteractionType.NONE
var _model_scene_choice_internal: int = ModelSceneChoice.NONE

func _validate_property(property: Dictionary) -> void:
	var prop_name := String(property.get("name", ""))
	if prop_name == "spell_preset_id":
		property["hint"] = PROPERTY_HINT_ENUM
		property["hint_string"] = _build_spell_preset_hint()
	elif prop_name == "interaction_type":
		property["hint"] = PROPERTY_HINT_ENUM
		property["hint_string"] = _build_interaction_hint()

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

func _build_interaction_hint() -> String:
	if _fighter_type_internal == FighterType.COMBATANT:
		return "None:0,Quest:2"
	return "None:0,Merchant:1,Quest:2,Trainer:3"

func _get_spawn_scene() -> PackedScene:
	return NPC_SCENE


func _compute_level() -> int:
	var lvl: int = level_min
	if level_max > level_min:
		lvl = randi_range(level_min, level_max)
	return lvl


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	# runtime: перед спавном проверяем валидность текущей конфигурации
	super._ready()


func _call_apply_spawn_init(mob: Node, point: SpawnPoint, level: int) -> bool:
	var class_id: String = CLASS_IDS[class_choice]
	var profile_id: String = "npc_citizen" if fighter_type == FighterType.CIVILIAN else "humanoid_hostile"
	var resolved_interaction := _sanitize_interaction_type(interaction_type)

	if OS.is_debug_build():
		print("[SPAWN][FNPC] type=", fighter_type, " class_id=", class_id, " profile_id=", profile_id, " lvl=", level, " point=", point.global_position)
	var abilities_for_level := MobSpellPresetDB.resolve_ability_ids_for_level(spell_preset_id, class_id, level)
	var preset_name_key := MobSpellPresetDB.get_preset_name_key(spell_preset_id)

	mob.call_deferred(
		"apply_spawn_init",
		point.global_position,
		faction_id,
		fighter_type,
		resolved_interaction,
		behavior,
		-1.0, # aggro_radius is defined on the NPC itself
		-1.0, # leash_distance is defined on the NPC itself
		patrol_pause_seconds,
		-1.0, # move_speed is defined on the NPC itself
		level,
		loot_profile,
		DEFAULT_PROJECTILE,
		class_id,
		profile_id,
		merchant_preset,
		mob_variant,
		attack_range_choice,
		abilities_for_level,
		preset_name_key,
		_resolve_model_scene_choice()
	)
	return true

func _get_current_class_id() -> String:
	return CLASS_IDS[_class_choice_internal]

func _sanitize_spell_preset_for_class(value: String) -> String:
	var class_id := _get_current_class_id()
	return MobSpellPresetDB.get_allowed_preset_id(value, class_id)

func _default_attack_range_for_class(choice: int) -> int:
	match choice:
		C_MAGE, C_PRIEST, C_HUNTER:
			return AttackRangeChoice.RANGED
		_:
			return AttackRangeChoice.MELEE

func _sanitize_interaction_type(value: int) -> int:
	var normalized := clampi(int(value), InteractionType.NONE, InteractionType.TRAINER)
	if _fighter_type_internal == FighterType.COMBATANT:
		if normalized == InteractionType.QUEST:
			return InteractionType.QUEST
		return InteractionType.NONE
	return normalized

func _sync_default_model_scene_choice() -> void:
	if _fighter_type_internal == FighterType.COMBATANT:
		if _interaction_type_internal == InteractionType.NONE:
			_model_scene_choice_internal = _resolve_class_model_scene_choice(_class_choice_internal)
		else:
			_model_scene_choice_internal = ModelSceneChoice.NONE
		return

	match _interaction_type_internal:
		InteractionType.NONE:
			_model_scene_choice_internal = _resolve_class_model_scene_choice(_class_choice_internal)
		InteractionType.MERCHANT:
			_model_scene_choice_internal = ModelSceneChoice.MERCHANT
		InteractionType.TRAINER:
			_model_scene_choice_internal = ModelSceneChoice.TRAINER
		InteractionType.QUEST:
			_model_scene_choice_internal = ModelSceneChoice.NONE
		_:
			_model_scene_choice_internal = ModelSceneChoice.NONE

func _resolve_class_model_scene_choice(choice: int) -> int:
	match clampi(choice, C_PALADIN, C_HUNTER):
		C_PALADIN:
			return ModelSceneChoice.PALADIN
		C_WARRIOR:
			return ModelSceneChoice.WARRIOR
		C_SHAMAN:
			return ModelSceneChoice.SHAMAN
		C_MAGE:
			return ModelSceneChoice.MAGE
		C_PRIEST:
			return ModelSceneChoice.PRIEST
		C_HUNTER:
			return ModelSceneChoice.HUNTER
		_:
			return ModelSceneChoice.WARRIOR

func _resolve_model_scene_choice() -> PackedScene:
	match clampi(_model_scene_choice_internal, ModelSceneChoice.NONE, ModelSceneChoice.HUNTER):
		ModelSceneChoice.MERCHANT:
			return MERCHANT_MODEL_SCENE
		ModelSceneChoice.TRAINER:
			return TRAINER_MODEL_SCENE
		ModelSceneChoice.PALADIN:
			return PALADIN_MODEL_SCENE
		ModelSceneChoice.WARRIOR:
			return WARRIOR_MODEL_SCENE
		ModelSceneChoice.SHAMAN:
			return SHAMAN_MODEL_SCENE
		ModelSceneChoice.MAGE:
			return MAGE_MODEL_SCENE
		ModelSceneChoice.PRIEST:
			return PRIEST_MODEL_SCENE
		ModelSceneChoice.HUNTER:
			return HUNTER_MODEL_SCENE
		_:
			return null
