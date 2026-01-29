extends "res://game/world/spawners/base_spawner_group.gd"
class_name NnmSpawnerGroup

const MOB_SCENE: PackedScene = preload("res://game/characters/mobs/NormalNeutralMob.tscn")

enum Behavior { GUARD, PATROL }
enum BodySize { SMALL, MEDIUM, LARGE, HUMANOID }

@export_group("Neutral Setup")
@export var loot_profile_animals: LootProfile = preload("res://core/loot/profiles/loot_profile_neutral_animal_default.tres") as LootProfile
@export var loot_profile_humanoids: LootProfile = preload("res://core/loot/profiles/loot_profile_neutral_humanoid_default.tres") as LootProfile
@export var level_min: int = 1
@export var level_max: int = 1
@export_enum("Small", "Medium", "Large", "Humanoid") var body_size: int = BodySize.MEDIUM
@export var skin_id: String = ""
@export_enum("Normal", "Rare", "Elite") var mob_variant: int = 0

@export_group("Behavior After Spawn")
@export_enum("Guard", "Patrol") var behavior: int = Behavior.GUARD
@export var patrol_radius: float = 140.0
@export var patrol_pause_seconds: float = 1.5


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

	mob.call_deferred(
		"apply_spawn_init",
		point.global_position,
		behavior,
		-1.0, # leash_distance is defined on the mob itself
		patrol_radius,
		patrol_pause_seconds,
		-1.0, # move_speed is defined on the mob itself
		level,
		body_size,
		skin_id,
		chosen_profile,
		class_id,
		profile_id,
		mob_variant
	)
	return true
