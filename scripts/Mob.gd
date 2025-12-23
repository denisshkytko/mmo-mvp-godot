extends CharacterBody2D

@onready var hp_fill: ColorRect = $"UI/HpFill"

@export var speed: float = 120.0
@export var aggro_radius: float = 350.0
@export var stop_distance: float = 45.0
@export var max_hp: int = 100
@export var corpse_scene: PackedScene
@export var xp_reward: int = 3


var current_hp: int
var player: Node2D

func _ready() -> void:
	current_hp = max_hp
	_update_hp_bar()
	player = get_tree().get_first_node_in_group("player") as Node2D


func _physics_process(_delta: float) -> void:
	if player == null:
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


func take_damage(amount: int) -> void:
	current_hp -= amount
	_update_hp_bar()
	print("Mob HP:", current_hp)

	if current_hp <= 0:
		die()


func die() -> void:
	if corpse_scene != null:
		var corpse = corpse_scene.instantiate()
		get_parent().add_child(corpse)
		corpse.global_position = global_position

		# MVP лут
		corpse.loot_gold = 3
		corpse.loot_item_id = "loot_token"
		corpse.loot_item_count = 2

	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("add_xp"):
		player.add_xp(xp_reward)

	queue_free()


func _update_hp_bar() -> void:
	if hp_fill == null:
		return

	var ratio := float(current_hp) / float(max_hp)
	ratio = clamp(ratio, 0.0, 1.0)

	hp_fill.size.x = 36.0 * ratio
