extends CharacterBody2D

@export var speed: float = 120.0
@export var aggro_radius: float = 350.0
@export var stop_distance: float = 45.0

@export var max_hp: int = 100
var current_hp: int

var player: Node2D


func _ready() -> void:
	current_hp = max_hp
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
	print("Mob HP:", current_hp)

	if current_hp <= 0:
		die()

func die() -> void:
	queue_free()
