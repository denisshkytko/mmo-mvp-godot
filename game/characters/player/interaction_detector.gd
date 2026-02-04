extends Area2D
class_name InteractionDetector

signal interactable_changed(available: bool, target: Node)

@export var max_distance: float = 80.0

var current_interactable: Node = null
var interact_available: bool = false

var _candidates: Array[Node2D] = []
var _player: Node2D = null


func _ready() -> void:
	_player = get_parent() as Node2D
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _physics_process(_delta: float) -> void:
	_update_current_interactable()


func try_interact(player_node: Node) -> void:
	if current_interactable == null or not is_instance_valid(current_interactable):
		return
	if current_interactable.has_method("try_interact"):
		current_interactable.call("try_interact", player_node)


func _on_area_entered(area: Area2D) -> void:
	_add_candidate(area)


func _on_area_exited(area: Area2D) -> void:
	_remove_candidate(area)


func _on_body_entered(body: Node2D) -> void:
	_add_candidate(body)


func _on_body_exited(body: Node2D) -> void:
	_remove_candidate(body)


func _add_candidate(node: Node2D) -> void:
	if node == null or not node.has_method("try_interact"):
		return
	if node == _player:
		return
	if _candidates.has(node):
		return
	_candidates.append(node)


func _remove_candidate(node: Node2D) -> void:
	if node == null:
		return
	_candidates.erase(node)


func _update_current_interactable() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_parent() as Node2D
	if _player == null:
		return

	var best_node: Node = null
	var best_dist: float = INF

	for candidate in _candidates:
		if candidate == null or not is_instance_valid(candidate):
			continue
		if candidate == _player:
			continue
		if candidate is Node2D:
			var dist := (candidate as Node2D).global_position.distance_to(_player.global_position)
			if dist > max_distance:
				continue
			if not _can_interact_with(candidate, _player):
				continue
			if dist < best_dist:
				best_dist = dist
				best_node = candidate

	var available := best_node != null
	if best_node != current_interactable or available != interact_available:
		current_interactable = best_node
		interact_available = available
		emit_signal("interactable_changed", interact_available, current_interactable)


func _can_interact_with(node: Node, player_node: Node) -> bool:
	if node.has_method("can_interact_with"):
		return bool(node.call("can_interact_with", player_node))
	return true
