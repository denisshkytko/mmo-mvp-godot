@tool
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
@export_enum("Melee", "Ranged") var attack_mode: int = AttackMode.MELEE:
	set(v):
		attack_mode = int(v)
		var allowed := _get_allowed_map_for_mode(attack_mode)
		if not allowed.has(_class_choice_internal):
			_class_choice_internal = _default_choice_for_mode(attack_mode)
			validation_error = ""
		_validate_current_choice()
@export_enum("Paladin", "Warrior", "Shaman", "Mage", "Priest", "Hunter")
var class_choice: int:
	get:
		return _class_choice_internal
	set(v):
		_try_set_class_choice(int(v))
@export var validation_error: String = ""


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

const ALLOWED_MELEE := {C_PALADIN: true, C_WARRIOR: true, C_SHAMAN: true}
const ALLOWED_RANGED := {C_MAGE: true, C_PRIEST: true, C_HUNTER: true}

var _class_choice_internal: int = C_PALADIN

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
	if validation_error != "":
		push_error("Aggressive spawner misconfigured: " + validation_error)
		if is_instance_valid(mob):
			mob.queue_free()
		return false

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
		attack_mode,
		"",              # mob_id больше не используется
		loot_profile,
		class_id,
		profile_id
	)
	return true


func _get_allowed_map_for_mode(mode: int) -> Dictionary:
	return ALLOWED_RANGED if mode == AttackMode.RANGED else ALLOWED_MELEE


func _allowed_names_for_mode(mode: int) -> String:
	var names: Array[String] = []
	var allowed := _get_allowed_map_for_mode(mode)
	for idx in allowed.keys():
		match int(idx):
			C_PALADIN:
				names.append("Paladin")
			C_WARRIOR:
				names.append("Warrior")
			C_SHAMAN:
				names.append("Shaman")
			C_MAGE:
				names.append("Mage")
			C_PRIEST:
				names.append("Priest")
			C_HUNTER:
				names.append("Hunter")
	names.sort()
	return ", ".join(names)


func _try_set_class_choice(v: int) -> void:
	var allowed := _get_allowed_map_for_mode(attack_mode)
	if allowed.has(v):
		_class_choice_internal = v
		validation_error = ""
	else:
		var msg := "invalid class for attack mode. allowed: " + _allowed_names_for_mode(attack_mode)
		validation_error = msg
		push_error(msg)
		notify_property_list_changed()


func _validate_current_choice() -> void:
	var allowed := _get_allowed_map_for_mode(attack_mode)
	if allowed.has(_class_choice_internal):
		validation_error = ""
	else:
		var msg := "current class not allowed for attack mode. allowed: " + _allowed_names_for_mode(attack_mode)
		validation_error = msg
		push_error(msg)


func _default_choice_for_mode(mode: int) -> int:
	return C_MAGE if mode == AttackMode.RANGED else C_PALADIN
