extends CharacterBody2D
class_name NormalNeutralMob

signal died(corpse: Corpse)

@onready var hp_fill: ColorRect = $"UI/HpFill"
@onready var target_marker: CanvasItem = $TargetMarker

@onready var c_ai: NormalNeutralMobAI = $Components/AI as NormalNeutralMobAI
@onready var c_combat: NormalNeutralMobCombat = $Components/Combat as NormalNeutralMobCombat
@onready var c_stats: NormalNeutralMobStats = $Components/Stats as NormalNeutralMobStats

enum BodySize { SMALL, MEDIUM, LARGE, HUMANOID }

@export_group("Neutral Defaults")
@export var base_xp: int = 3
@export var xp_per_level: int = 1

# общий параметр скорости (как ты хотел)
@export var move_speed: float = 115.0

# размер тела выбирается спавнером
var body_size: int = BodySize.MEDIUM
var mob_level: int = 1
var loot_table_id: String = "lt_neutral_low"
var skin_id: String = ""

var home_position: Vector2 = Vector2.ZERO

const CORPSE_SCENE: PackedScene = preload("res://game/world/corpses/Corpse.tscn")

# агрессия
var is_aggressive: bool = false
var aggressor: Node2D = null

# реген
var regen_active: bool = false
const REGEN_PCT_PER_SEC: float = 0.05

# ---------------------------
# ПРЕСЕТЫ СТАТОВ ПО BODY SIZE
# (без выпадающего “динамического скрытия”, просто группы параметров)
# ---------------------------
@export_group("Body SMALL")
@export var small_base_attack: int = 4
@export var small_attack_per_level: int = 1
@export var small_base_max_hp: int = 25
@export var small_hp_per_level: int = 6
@export var small_base_defense: int = 1
@export var small_defense_per_level: int = 1

@export_group("Body MEDIUM")
@export var medium_base_attack: int = 6
@export var medium_attack_per_level: int = 1
@export var medium_base_max_hp: int = 40
@export var medium_hp_per_level: int = 8
@export var medium_base_defense: int = 1
@export var medium_defense_per_level: int = 1

@export_group("Body LARGE")
@export var large_base_attack: int = 8
@export var large_attack_per_level: int = 2
@export var large_base_max_hp: int = 65
@export var large_hp_per_level: int = 12
@export var large_base_defense: int = 2
@export var large_defense_per_level: int = 1

@export_group("Body HUMANOID")
@export var humanoid_base_attack: int = 7
@export var humanoid_attack_per_level: int = 2
@export var humanoid_base_max_hp: int = 50
@export var humanoid_hp_per_level: int = 10
@export var humanoid_base_defense: int = 2
@export var humanoid_defense_per_level: int = 1

func _ready() -> void:
	if home_position == Vector2.ZERO:
		home_position = global_position

	# связь с AI: начало RETURN по leash → сброс агрессии + старт регена
	if c_ai != null:
		if not c_ai.leash_return_started.is_connected(_on_leash_return_started):
			c_ai.leash_return_started.connect(_on_leash_return_started)

	_apply_to_components()
	c_stats.recalculate_for_level(mob_level)
	c_stats.update_hp_bar(hp_fill)

func _process(_delta: float) -> void:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	var is_target: bool = false
	if gm != null and gm.has_method("get_target"):
		is_target = (gm.call("get_target") == self)
	if target_marker != null:
		target_marker.visible = is_target

func _physics_process(delta: float) -> void:
	if c_stats.is_dead:
		return

	_apply_to_components()

	# реген идёт только когда regen_active=true, и прекращается только когда HP=100%
	if regen_active and c_stats.current_hp < c_stats.max_hp:
		c_stats.heal_percent_per_second(delta, REGEN_PCT_PER_SEC)
		c_stats.update_hp_bar(hp_fill)
	elif regen_active and c_stats.current_hp >= c_stats.max_hp:
		regen_active = false

	# AI
	var target: Node2D = aggressor if is_aggressive else null
	c_ai.tick(delta, self, target, c_combat, is_aggressive)

	# атака только если агрессивен
	if is_aggressive and aggressor != null and is_instance_valid(aggressor):
		c_combat.tick(delta, self, aggressor, c_stats.attack_value)

func _on_leash_return_started() -> void:
	# как ты просил: агрессия сбрасывается сразу при "позвал домой"
	is_aggressive = false
	aggressor = null
	regen_active = true
	c_combat.reset_combat()

# ---------------------------
# Called by Spawner
# ---------------------------
func apply_spawn_init(
	spawn_pos: Vector2,
	behavior_in: int,
	leash_distance_in: float,
	patrol_radius_in: float,
	patrol_pause_in: float,
	speed_in: float,
	level_in: int,
	body_size_in: int,
	skin_id_in: String,
	loot_table_id_in: String
) -> void:
	home_position = spawn_pos
	global_position = spawn_pos
	skin_id = skin_id_in
	loot_table_id = loot_table_id_in
	move_speed = speed_in
	mob_level = max(1, level_in)
	body_size = body_size_in

	if c_ai != null:
		c_ai.behavior = behavior_in
		c_ai.leash_distance = leash_distance_in
		c_ai.patrol_radius = patrol_radius_in
		c_ai.patrol_pause_seconds = patrol_pause_in
		c_ai.speed = move_speed
		c_ai.home_position = home_position
		c_ai.reset_to_idle()

	_apply_to_components()
	c_stats.recalculate_for_level(mob_level)
	c_stats.current_hp = c_stats.max_hp
	c_stats.update_hp_bar(hp_fill)

	is_aggressive = false
	aggressor = null
	regen_active = false
	c_combat.reset_combat()

func _apply_to_components() -> void:
	if c_ai != null:
		c_ai.home_position = home_position
		c_ai.speed = move_speed

	# melee параметры (общие)
	c_combat.melee_stop_distance = 45.0
	c_combat.melee_attack_range = 55.0
	c_combat.melee_cooldown = 1.2

	# применяем пресет статов по размеру
	match body_size:
		BodySize.SMALL:
			c_stats.apply_body_preset(small_base_attack, small_attack_per_level, small_base_max_hp, small_hp_per_level, small_base_defense, small_defense_per_level)
		BodySize.MEDIUM:
			c_stats.apply_body_preset(medium_base_attack, medium_attack_per_level, medium_base_max_hp, medium_hp_per_level, medium_base_defense, medium_defense_per_level)
		BodySize.LARGE:
			c_stats.apply_body_preset(large_base_attack, large_attack_per_level, large_base_max_hp, large_hp_per_level, large_base_defense, large_defense_per_level)
		_:
			c_stats.apply_body_preset(humanoid_base_attack, humanoid_attack_per_level, humanoid_base_max_hp, humanoid_hp_per_level, humanoid_base_defense, humanoid_defense_per_level)

	c_stats.recalculate_for_level(mob_level)

# ---------------------------
# Damage API
# ---------------------------
func take_damage(raw_damage: int) -> void:
	# fallback, если кто-то бьёт без attacker
	take_damage_from(raw_damage, null)

func take_damage_from(raw_damage: int, attacker: Node2D) -> void:
	if c_stats.is_dead:
		return

	var died_now: bool = c_stats.apply_damage(raw_damage)
	c_stats.update_hp_bar(hp_fill)

	# нейтрал становится агрессивным на атакующего
	if attacker != null and is_instance_valid(attacker):
		is_aggressive = true
		aggressor = attacker
		regen_active = false
		c_ai.on_took_damage(self)
	else:
		# если attacker неизвестен — просто агр на игрока (если он есть)
		var p := get_tree().get_first_node_in_group("player") as Node2D
		if p != null:
			is_aggressive = true
			aggressor = p
			regen_active = false
			c_ai.on_took_damage(self)

	if died_now:
		_die()

func on_player_died() -> void:
	# чтобы нейтралы тоже отпускали
	is_aggressive = false
	aggressor = null
	regen_active = false
	c_combat.reset_combat()
	c_ai.force_return()
	velocity = Vector2.ZERO

# ---------------------------
# Death + loot/xp (как у агрессивного)
# ---------------------------
func _die() -> void:
	if c_stats.is_dead:
		return
	c_stats.is_dead = true

	var corpse: Corpse = null
	var inst := CORPSE_SCENE.instantiate()
	corpse = inst as Corpse
	if corpse != null:
		get_parent().add_child(corpse)
		corpse.global_position = global_position

		var loot: Dictionary = LootSystem.generate_loot(loot_table_id, mob_level)
		if corpse.has_method("set_loot_v2"):
			corpse.call("set_loot_v2", loot)
		else:
			corpse.loot_gold = int(loot.get("gold", 0))

	var p := get_tree().get_first_node_in_group("player")
	if p != null and p.has_method("add_xp"):
		p.add_xp(base_xp + mob_level * xp_per_level)

	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm != null and gm.has_method("get_target") and gm.has_method("clear_target"):
		if gm.call("get_target") == self:
			gm.call("clear_target")

	emit_signal("died", corpse)
	queue_free()
