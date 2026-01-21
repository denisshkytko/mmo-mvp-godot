@tool
extends "res://game/world/spawners/base_spawner_group.gd"
class_name FnpcSpawnerGroup

const NPC_SCENE: PackedScene = preload("res://game/characters/npcs/FactionNPC.tscn")
const DEFAULT_PROJECTILE: PackedScene = preload("res://game/characters/mobs/projectiles/HomingProjectile.tscn")

enum Behavior { GUARD, PATROL }
enum FighterType { CIVILIAN, MELEE, RANGED }
enum InteractionType { NONE, MERCHANT, QUEST, TRAINER }

@export_group("Faction NPC Setup")
@export_enum("blue", "red", "yellow", "green") var faction_id: String = "blue"
@export_enum("Civilian", "Melee", "Ranged") var fighter_type: int = FighterType.CIVILIAN:
	set(v):
		fighter_type = int(v)
		var allowed := _get_allowed_map_for_type(fighter_type)
		if not allowed.has(_class_choice_internal):
			_class_choice_internal = _default_choice_for_type(fighter_type)
			validation_error = ""
		_validate_current_choice()
@export_enum("None", "Merchant", "Quest", "Trainer") var interaction_type: int = InteractionType.NONE

@export var loot_profile: LootProfile = preload("res://core/loot/profiles/loot_profile_faction_gold_only.tres") as LootProfile
@export var level_min: int = 1
@export var level_max: int = 1
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

const CLASS_IDS := ["paladin", "warrior", "shaman", "mage", "priest", "hunter"]
const C_PALADIN := 0
const C_WARRIOR := 1
const C_SHAMAN := 2
const C_MAGE := 3
const C_PRIEST := 4
const C_HUNTER := 5

const ALLOWED_MELEE := {C_PALADIN: true, C_WARRIOR: true, C_SHAMAN: true}
const ALLOWED_RANGED := {C_MAGE: true, C_PRIEST: true, C_HUNTER: true}

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
		_apply_default_if_uninitialized()
		_validate_current_choice()


func _call_apply_spawn_init(mob: Node, point: SpawnPoint, level: int) -> void:
	if validation_error != "":
		push_error("Faction NPC spawner misconfigured: " + validation_error)
		return

	var class_id: String = CLASS_IDS[_class_choice_internal]
	var profile_id: String = "npc_citizen" if fighter_type == FighterType.CIVILIAN else "humanoid_hostile"

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


func _get_allowed_map_for_type(t: int) -> Dictionary:
	match t:
		FighterType.RANGED:
			return ALLOWED_RANGED
		FighterType.CIVILIAN, FighterType.MELEE:
			return ALLOWED_MELEE
	return ALLOWED_MELEE


func _allowed_names_for_type(t: int) -> String:
	var names: Array[String] = []
	var allowed := _get_allowed_map_for_type(t)
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
	var allowed := _get_allowed_map_for_type(fighter_type)
	if allowed.has(v):
		_class_choice_internal = v
		validation_error = ""
	else:
		var msg := "invalid class for fighter type. allowed: " + _allowed_names_for_type(fighter_type)
		validation_error = msg
		push_error(msg)
		notify_property_list_changed()


func _validate_current_choice() -> void:
	var allowed := _get_allowed_map_for_type(fighter_type)
	if allowed.has(_class_choice_internal):
		validation_error = ""
	else:
		var msg := "current class not allowed for fighter type. allowed: " + _allowed_names_for_type(fighter_type)
		validation_error = msg
		push_error(msg)


func _apply_default_if_uninitialized() -> void:
	var allowed := _get_allowed_map_for_type(fighter_type)
	if allowed.has(_class_choice_internal):
		return
	_class_choice_internal = _default_choice_for_type(fighter_type)


func _default_choice_for_type(t: int) -> int:
	match t:
		FighterType.RANGED:
			return C_MAGE
		FighterType.CIVILIAN:
			return C_SHAMAN
		_:
			return C_PALADIN
