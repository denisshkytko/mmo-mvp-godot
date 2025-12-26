extends Node2D
class_name Graveyard

@onready var spawn_point: Marker2D = $SpawnPoint

func get_spawn_position() -> Vector2:
	return spawn_point.global_position
