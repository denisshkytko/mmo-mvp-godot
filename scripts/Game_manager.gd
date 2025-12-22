extends Node

@onready var zone_container: Node = $"../ZoneContainer"

var player: Node2D

func _ready() -> void:
	player = get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		push_error("Player not found in group 'player'.")
		return

func load_zone(zone_scene_path: String, spawn_name: String = "SpawnPoint") -> void:
	if zone_scene_path == "" or zone_scene_path == null:
		push_error("Zone path is empty.")
		return

	var zone_scene: PackedScene = load(zone_scene_path)
	if zone_scene == null:
		push_error("Failed to load zone: " + zone_scene_path)
		return

	# удалить текущую зону
	for child in zone_container.get_children():
		child.queue_free()

	# создать новую
	var new_zone: Node2D = zone_scene.instantiate() as Node2D
	zone_container.add_child(new_zone)

	# найти точку спавна по имени
	var spawn: Node = new_zone.get_node_or_null(spawn_name)
	if spawn is Marker2D:
		player.global_position = (spawn as Marker2D).global_position
	else:
		# fallback: стандартный SpawnPoint
		var default_spawn: Node = new_zone.get_node_or_null("SpawnPoint")
		if default_spawn is Marker2D:
			player.global_position = (default_spawn as Marker2D).global_position
		else:
			player.global_position = new_zone.global_position

	# 4) Переносим игрока внутрь новой зоны
	# (если игрок был дочерним в старой зоне, он мог удалиться вместе с ней)
	# Поэтому: делаем игрока дочерним World один раз и больше не трогаем
