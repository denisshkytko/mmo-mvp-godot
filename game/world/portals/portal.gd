extends Area2D
class_name Portal

@export_file("*.tscn") var target_zone_path: String
@export var spawn_name: String = "SpawnPoint"

var _gm: Node = null

func _ready() -> void:
	_gm = get_tree().get_first_node_in_group("game_manager")
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body == null or not body.is_in_group("player"):
		return

	if _gm == null or not is_instance_valid(_gm):
		_gm = get_tree().get_first_node_in_group("game_manager")
		if _gm == null:
			return

	if target_zone_path == "":
		return

	if _gm.has_method("load_zone"):
		_gm.call("load_zone", target_zone_path, spawn_name)
