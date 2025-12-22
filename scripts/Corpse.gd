extends Area2D

@onready var hint: Label = $Hint
@onready var visual: ColorRect = $Visual

@export var interact_radius: float = 60.0
@export var despawn_seconds: float = 30.0
var _life_timer: float = 0.0

# Лут трупа (MVP)
var loot_gold: int = 0
var loot_item_id: String = "loot_token"
var loot_item_count: int = 0
var _base_color: Color
var _blink_timer: float = 0.0
var _blink_on: bool = false
var _blink_color: Color


var _player_in_range: Node = null

func _ready() -> void:
	_blink_color = _base_color.lightened(0.35)
	_life_timer = despawn_seconds
	_base_color = visual.color
	hint.visible = false
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)

func _process(delta: float) -> void:
	var ui_node: Node = get_tree().get_first_node_in_group("loot_ui")

	# Despawn timer (paused while looting this corpse)
	var looting_this: bool = false
	if ui_node != null and ui_node.has_method("is_looting_corpse"):
		looting_this = bool(ui_node.call("is_looting_corpse", self))

	if not looting_this:
		_life_timer -= delta
		if _life_timer <= 0.0:
			queue_free()
			return

	# Blink only if corpse is visible on screen
	if _is_on_screen():
		_blink_timer += delta
		if _blink_timer >= 1.0:
			_blink_timer = 0.0
			_blink_on = not _blink_on

		visual.color = _blink_color if _blink_on else _base_color
	else:
		# when not visible, keep base color (no blinking)
		visual.color = _base_color
		_blink_timer = 0.0
		_blink_on = false

	# E = loot (toggle window) only if player is in range
	if _player_in_range != null and Input.is_action_just_pressed("loot"):
		if ui_node != null and ui_node.has_method("toggle_for_corpse"):
			ui_node.call("toggle_for_corpse", self)


func _on_enter(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = body
		hint.visible = true


func _on_exit(body: Node) -> void:
	if body == _player_in_range:
		_player_in_range = null
		hint.visible = false


func _is_on_screen() -> bool:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return true  # если камеры нет, считаем видимым

	var half_size: Vector2 = get_viewport_rect().size * 0.5 * cam.zoom
	var rect := Rect2(cam.global_position - half_size, half_size * 2.0)
	return rect.has_point(global_position)


func loot_all_to_player(player: Node) -> void:
	if player == null:
		return

	# золото
	if loot_gold > 0 and player.has_method("add_gold"):
		player.add_gold(loot_gold)

	# предмет
	if loot_item_count > 0 and player.has_method("add_item"):
		player.add_item(loot_item_id, loot_item_count)

	# после обыска исчезаем
	queue_free()
