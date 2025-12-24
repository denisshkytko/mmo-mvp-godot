extends CharacterBody2D

@onready var hp_fill: ColorRect = $"UI/HpFill"
@onready var target_marker: CanvasItem = $TargetMarker

@export var speed: float = 120.0
@export var aggro_radius: float = 350.0
@export var stop_distance: float = 45.0

# Level / Stats
@export var mob_level: int = 1

# Attack
@export var mob_attack_cooldown: float = 1.2
@export var base_attack: int = 8
@export var attack_per_level: int = 2

# Base stats
@export var base_max_hp: int = 50
@export var hp_per_level: int = 12
@export var base_defense: int = 1
@export var defense_per_level: int = 1

# mob slightly weaker than player
@export var strength_multiplier: float = 0.9

@export var corpse_scene: PackedScene
@export var xp_reward: int = 0  # 0 = auto (2 + mob_level)

var max_hp: int = 50
var current_hp: int = 50
var defense: int = 1
var attack: int = 8

var player: Node2D = null
var _attack_timer: float = 0.0


func _ready() -> void:
	_recalculate_stats_for_level()
	_update_hp_bar()

	player = get_tree().get_first_node_in_group("player") as Node2D


func _process(_delta: float) -> void:
	# Target marker
	if target_marker == null:
		return

	var gm: Node = get_tree().get_first_node_in_group("game_manager") as Node
	var is_target: bool = false

	if gm != null and gm.has_method("get_target"):
		# gm.call() returns Variant -> explicitly cast to Object then compare
		var tgt_obj: Object = gm.call("get_target") as Object
		is_target = (tgt_obj == self)

	target_marker.visible = is_target


func _physics_process(delta: float) -> void:
	_attack_timer = max(0.0, _attack_timer - delta)

	# Refresh player reference if needed
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node2D
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var to_player: Vector2 = player.global_position - global_position
	var dist: float = to_player.length()

	# 1) Too far: idle
	if dist > aggro_radius:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# 2) In attack range: stop + attack on cooldown
	if dist <= stop_distance:
		velocity = Vector2.ZERO
		move_and_slide()

		if _attack_timer <= 0.0 and player.has_method("take_damage"):
			player.call("take_damage", attack)
			_attack_timer = mob_attack_cooldown

		return

	# 3) Otherwise: chase
	velocity = to_player.normalized() * speed
	move_and_slide()


func _recalculate_stats_for_level() -> void:
	max_hp = int(round((base_max_hp + (mob_level - 1) * hp_per_level) * strength_multiplier))
	defense = int(round((base_defense + (mob_level - 1) * defense_per_level) * strength_multiplier))
	attack = int(round((base_attack + (mob_level - 1) * attack_per_level) * strength_multiplier))

	if max_hp < 10:
		max_hp = 10
	if defense < 1:
		defense = 1
	if attack < 1:
		attack = 1

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
		var corpse: Node2D = corpse_scene.instantiate() as Node2D
		get_parent().add_child(corpse)
		corpse.global_position = global_position

		# These properties exist in Corpse.gd
		corpse.set("loot_gold", 3)
		corpse.set("loot_item_id", "loot_token")
		corpse.set("loot_item_count", 2)

	# Give XP to player
	var p: Node = get_tree().get_first_node_in_group("player") as Node
	if p != null and p.has_method("add_xp"):
		p.call("add_xp", _get_xp_reward())

	# Clear target if this mob was selected
	var gm: Node = get_tree().get_first_node_in_group("game_manager") as Node
	if gm != null and gm.has_method("get_target") and gm.has_method("clear_target"):
		var tgt_obj: Object = gm.call("get_target") as Object
		if tgt_obj == self:
			gm.call("clear_target")

	queue_free()


func _get_xp_reward() -> int:
	if xp_reward > 0:
		return xp_reward
	return 2 + mob_level


func _update_hp_bar() -> void:
	if hp_fill == null:
		return

	var ratio: float = clamp(float(current_hp) / float(max_hp), 0.0, 1.0)
	hp_fill.size.x = 36.0 * ratio
