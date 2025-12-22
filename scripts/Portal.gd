extends Area2D

@export var target_scene: String = ""
@export var target_spawn_name: String = "SpawnPoint"

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm == null:
		push_error("GameManager not found in group 'game_manager'.")
		return

	gm.load_zone(target_scene, target_spawn_name)
