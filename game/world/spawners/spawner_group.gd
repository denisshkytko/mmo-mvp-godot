extends Node2D
class_name SpawnerGroup

@export var mob_id: String = ""
@export var loot_table_id: String = ""
@export var level_min: int = 0
@export var level_max: int = 0

# Не менять задание эти параметров через индексы
@export_enum("Guard", "Patrol") var behavior: int = 0
@export var aggro_radius: float = -1.0
@export var leash_distance: float = -1.0
@export var patrol_radius: float = -1.0
@export var patrol_pause_seconds: float = -1.0
@export_enum("Melee", "Ranged") var attack_mode: int = -1

func _ready() -> void:
	_apply_to_children()

func _apply_to_children() -> void:
	for c in get_children():
		if c == null:
			continue
		if not (c is Spawner):
			continue

		var s := c as Spawner

		# применяем только если в спавнере значение "пустое" или дефолтное
		if mob_id != "" and s.mob_id == "":
			s.mob_id = mob_id
		if loot_table_id != "" and s.loot_table_id == "":
			s.loot_table_id = loot_table_id

		if level_min > 0 and s.level_min <= 0:
			s.level_min = level_min
		if level_max > 0 and s.level_max <= 0:
			s.level_max = level_max
		
		if attack_mode >= 0:
			s.attack_mode = attack_mode
		# behavior всегда задаётся через enum-поле behavior (0 Guard / 1 Patrol)
		s.behavior = behavior

		if aggro_radius > 0:
			s.aggro_radius = aggro_radius
		if leash_distance > 0:
			s.leash_distance = leash_distance
		if patrol_radius > 0:
			s.patrol_radius = patrol_radius
		if patrol_pause_seconds > 0:
			s.patrol_pause_seconds = patrol_pause_seconds
