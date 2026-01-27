@tool
extends "res://game/world/spawners/base_spawner_group.gd"
class_name FnpcSpawnerGroup

const NPC_SCENE: PackedScene = preload("res://game/characters/npcs/FactionNPC.tscn")
const DEFAULT_PROJECTILE: PackedScene = preload("res://game/characters/mobs/projectiles/HomingProjectile.tscn")

enum Behavior { GUARD, PATROL }
enum FighterType { CIVILIAN, COMBATANT }
enum InteractionType { NONE, MERCHANT, QUEST, TRAINER }

@export_group("Faction NPC Setup")
@export_enum("blue", "red", "yellow", "green") var faction_id: String = "blue"
@export_enum("Civilian", "Combatant") var fighter_type: int = FighterType.CIVILIAN
@export_enum("None", "Merchant", "Quest", "Trainer") var interaction_type: int = InteractionType.NONE

@export var loot_profile: LootProfile = preload("res://core/loot/profiles/loot_profile_faction_gold_only.tres") as LootProfile
@export var level_min: int = 1
@export var level_max: int = 1
@export_enum("Paladin", "Warrior", "Shaman", "Mage", "Priest", "Hunter")
var class_choice: int:
	get:
		return _class_choice_internal
	set(v):
		_class_choice_internal = int(v)

@export_group("Behavior After Spawn")
@export_enum("Guard", "Patrol") var behavior: int = Behavior.GUARD

@export var patrol_radius: float = 140.0
@export var patrol_pause_seconds: float = 1.5

const CLASS_IDS := ["paladin", "warrior", "shaman", "mage", "priest", "hunter"]
const C_PALADIN := 0
const C_WARRIOR := 1
const C_SHAMAN := 2
const C_MAGE := 3
const C_PRIEST := 4
const C_HUNTER := 5

var _class_choice_internal: int = C_SHAMAN


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
	var class_id: String = CLASS_IDS[_class_choice_internal]
	var profile_id: String = "npc_citizen" if fighter_type == FighterType.CIVILIAN else "humanoid_hostile"

	if OS.is_debug_build():
		print("[SPAWN][FNPC] type=", fighter_type, " class_id=", class_id, " profile_id=", profile_id, " lvl=", level, " point=", point.global_position)

	mob.call_deferred(
		"apply_spawn_init",
		point.global_position,
		faction_id,
		fighter_type,
		interaction_type,
		behavior,
		-1.0, # aggro_radius is defined on the NPC itself
		-1.0, # leash_distance is defined on the NPC itself
		patrol_radius,
		patrol_pause_seconds,
		-1.0, # move_speed is defined on the NPC itself
		level,
		loot_profile,
		DEFAULT_PROJECTILE,
		class_id,
		profile_id
	)
	return true
