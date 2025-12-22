extends CharacterBody2D

@export var speed: float = 200.0

func _physics_process(_delta: float) -> void:
	var input_vector := Vector2(
		Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left"),
		Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	)

	if input_vector.length() > 1.0:
		input_vector = input_vector.normalized()

	velocity = input_vector * speed
	move_and_slide()

# TEMP: debug attack for Stage 5.3 (will be replaced by real auto-attack + targeting)
func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("attack"):
		print("ATTACK pressed")
		_try_attack()


func _try_attack() -> void:
	var mobs = get_tree().get_nodes_in_group("mobs")
	print("mobs found:", mobs.size())

	for mob in mobs:
		if mob is Node2D:
			var dist = global_position.distance_to(mob.global_position)
			if dist < 60:
				mob.take_damage(25)
				break
