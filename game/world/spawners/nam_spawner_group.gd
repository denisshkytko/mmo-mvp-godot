@tool
extends "res://game/world/spawners/base_spawner_group.gd"
class_name NamSpawnerGroup

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
		_abilities_internal = _filter_abilities_for_class(_abilities_internal)
@export var abilities: Array[String]:
	get:
		return _abilities_internal
	set(value):
		_abilities_internal = _filter_abilities_for_class(value)
@export_enum("Normal", "Rare", "Elite") var mob_variant: int = 0


@export_group("Behavior After Spawn")
@export_enum("Guard", "Patrol") var behavior: int = Behavior.GUARD
@export var patrol_radius: float = 140.0
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
var _abilities_internal: Array[String] = []

# BaseSpawnerGroup уже содержит respawn_seconds


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
		"",              # mob_id больше не используется
		loot_profile,
		class_id,
		profile_id,
		mob_variant,
		_abilities_internal
	)
	return true

func _get_current_class_id() -> String:
	return CLASS_IDS[_class_choice_internal]

func _filter_abilities_for_class(values: Array[String]) -> Array[String]:
	var out: Array[String] = []
	var class_id := _get_current_class_id()
	var db: Node = null
	if is_inside_tree():
		db = get_node_or_null("/root/AbilityDB")
	for ability_id in values:
		if ability_id == "":
			continue
		if db != null and db.has_method("get_ability"):
			var def: AbilityDefinition = db.call("get_ability", ability_id)
			if def != null and (class_id == "" or def.class_id == class_id):
				out.append(ability_id)
		else:
			out.append(ability_id)
	return out
