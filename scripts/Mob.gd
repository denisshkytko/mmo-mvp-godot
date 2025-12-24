extends CharacterBody2D

@onready var hp_fill: ColorRect = $"UI/HpFill"
@onready var target_marker: CanvasItem = $TargetMarker

@export var speed: float = 120.0
@export var aggro_radius: float = 350.0
@export var stop_distance: float = 45.0

# Level / Stats
@export var mob_level: int = 1

# базовые параметры моба (кривая роста чуть слабее игрока)
@export var base_max_hp: int = 50
@export var hp_per_level: int = 12
@export var base_defense: int = 1
@export var defense_per_level: int = 1

# коэффициент "моб слабее игрока" примерно на 10%
@export var strength_multiplier: float = 0.9

@export var corpse_scene: PackedScene
@export var xp_reward: int = 0  # 0 = авто (2 + mob_level)

var max_hp: int = 50
var current_hp: int = 50
var defense: int = 1

var player: Node2D


func _ready() -> void:
	_recalculate_stats_for_level()
	_update_hp_bar()

	player = get_tree().get_first_node_in_group("player") as Node2D


func _process(_delta: float) -> void:
	if target_marker == null:
		return

	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	var is_target: bool = false

	if gm != null and gm.has_method("get_target"):
		is_target = (gm.call("get_target") == self)

	target_marker.visible = is_target


func _physics_process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node2D
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var to_player: Vector2 = player.global_position - global_position
	var dist: float = to_player.length()

	# если далеко — не двигаемся
	if dist > aggro_radius:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# если близко — стоим (позже тут будет атака)
	if dist <= stop_distance:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# двигаемся к игроку
	velocity = to_player.normalized() * speed
	move_and_slide()


func _recalculate_stats_for_level() -> void:
	max_hp = int(round((base_max_hp + (mob_level - 1) * hp_per_level) * strength_multiplier))
	defense = int(round((base_defense + (mob_level - 1) * defense_per_level) * strength_multiplier))

	if max_hp < 10:
		max_hp = 10
	if defense < 1:
		defense = 1

	current_hp = max_hp


func take_damage(raw_damage: int) -> void:
	var dmg: int = max(1, raw_damage - defense)
	current_hp = max(0, current_hp - dmg)

	_update_hp_bar()

	if current_hp <= 0:
		die()


func die() -> void:
	# Spawn corpse + loot
	if corpse_scene != null:
		var corpse = corpse_scene.instantiate()
		get_parent().add_child(corpse)
		corpse.global_position = global_position

		corpse.loot_gold = 3
		corpse.loot_item_id = "loot_token"
		corpse.loot_item_count = 2

	# Give XP to player
	var p := get_tree().get_first_node_in_group("player")
	if p != null and p.has_method("add_xp"):
		p.add_xp(_get_xp_reward())

	# Clear target if this mob was selected
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm != null and gm.has_method("get_target") and gm.has_method("clear_target"):
		if gm.call("get_target") == self:
			gm.call("clear_target")

	queue_free()


func _get_xp_reward() -> int:
	if xp_reward > 0:
		return xp_reward
	return 2 + mob_level


func _update_hp_bar() -> void:
	if hp_fill == null:
		return

	var ratio := float(current_hp) / float(max_hp)
	ratio = clamp(ratio, 0.0, 1.0)
	hp_fill.size.x = 36.0 * ratio
