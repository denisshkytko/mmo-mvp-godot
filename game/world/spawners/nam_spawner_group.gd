extends "res://game/world/spawners/base_spawner_group.gd"
class_name NamSpawnerGroup

const MOB_SCENE: PackedScene = preload("res://game/characters/mobs/NormalAggressiveMob.tscn")
## LootProfile is a global class (class_name). Avoid shadowing.

enum Behavior { GUARD, PATROL }
enum AttackMode { MELEE, RANGED }

@export_group("Mob Setup")
@export var loot_profile: LootProfile = preload("res://core/loot/profiles/loot_profile_aggressive_default.tres") as LootProfile
@export var level_min: int = 1
@export var level_max: int = 1
@export_enum("Melee", "Ranged") var attack_mode: int = AttackMode.MELEE
@export_enum("Auto", "paladin", "shaman", "mage", "priest", "hunter", "warrior") var class_id_override: String = "Auto"


@export_group("Behavior After Spawn")
@export_enum("Guard", "Patrol") var behavior: int = Behavior.GUARD
@export var patrol_radius: float = 140.0
@export var patrol_pause_seconds: float = 1.5

# BaseSpawnerGroup уже содержит respawn_seconds


func _get_spawn_scene() -> PackedScene:
	return MOB_SCENE


func _compute_level() -> int:
	var lvl: int = level_min
	if level_max > level_min:
		lvl = randi_range(level_min, level_max)
	return lvl


func _call_apply_spawn_init(mob: Node, point: SpawnPoint, level: int) -> void:
	# ВАЖНО: не задаём aggro_radius из группы, чтобы ты мог менять
	# его в каждой сущности отдельно (в инспекторе самого моба).
	# Поэтому aggro_radius_in = -1.0.
	var class_id := class_id_override.strip_edges()
	if class_id == "" or class_id == "Auto":
		if attack_mode == AttackMode.MELEE:
			var melee_pool := ["warrior", "paladin"]
			class_id = melee_pool[randi() % melee_pool.size()]
		else:
			var ranged_pool := ["hunter", "mage", "shaman", "priest"]
			class_id = ranged_pool[randi() % ranged_pool.size()]
	var profile_id := "humanoid_hostile"
	mob.call_deferred(
		"apply_spawn_init",
		point.global_position,
		behavior,
		-1.0, # aggro_radius не задаём
		-1.0, # leash_distance is defined on the mob itself
		patrol_radius,
		patrol_pause_seconds,
		-1.0, # move_speed is defined on the mob itself
		level,
		attack_mode,
		"",              # mob_id больше не используется
		loot_profile,
		class_id,
		profile_id
	)
