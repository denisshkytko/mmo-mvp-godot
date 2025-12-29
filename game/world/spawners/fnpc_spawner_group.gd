extends "res://game/world/spawners/base_spawner_group.gd"
class_name FnpcSpawnerGroup

const NPC_SCENE: PackedScene = preload("res://game/characters/npcs/FactionNPC.tscn")
const DEFAULT_PROJECTILE: PackedScene = preload("res://game/characters/mobs/projectiles/HomingProjectile.tscn")

enum Behavior { GUARD, PATROL }
enum FighterType { CIVILIAN, FIGHTER, MAGE }
enum InteractionType { NONE, MERCHANT, QUEST, TRAINER }

@export_group("Faction NPC Setup")
@export_enum("blue", "red", "yellow", "green") var faction_id: String = "blue"
@export_enum("Civilian", "Fighter", "Mage") var fighter_type: int = FighterType.FIGHTER
@export_enum("None", "Merchant", "Quest", "Trainer") var interaction_type: int = InteractionType.NONE

@export var loot_table_id: String = "lt_guard_low"
@export var level_min: int = 1
@export var level_max: int = 1

@export_group("Behavior After Spawn")
@export_enum("Guard", "Patrol") var behavior: int = Behavior.GUARD

@export var patrol_radius: float = 140.0
@export var patrol_pause_seconds: float = 1.5


func _get_spawn_scene() -> PackedScene:
	return NPC_SCENE


func _compute_level() -> int:
	var lvl: int = level_min
	if level_max > level_min:
		lvl = randi_range(level_min, level_max)
	return lvl


func _call_apply_spawn_init(mob: Node, point: SpawnPoint, level: int) -> void:
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
		loot_table_id,
		DEFAULT_PROJECTILE
	)
