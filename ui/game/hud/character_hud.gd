extends Control
class_name CharacterHUD

@onready var character_button: Button = $CharacterButton
@onready var panel: Panel = $Panel
@onready var stats_text: RichTextLabel = $Panel/MarginContainer/VBoxContainer/StatsText

func _ready() -> void:
	character_button.pressed.connect(_on_character_button_pressed)

func _on_character_button_pressed() -> void:
	panel.visible = not panel.visible
	if panel.visible:
		_refresh()

func _refresh() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		stats_text.text = "Player not found."
		return

	# Если в будущем ты добавишь у игрока метод snapshot — он подхватится автоматически
	if player.has_method("get_stats_snapshot"):
		var d: Dictionary = player.call("get_stats_snapshot")
		stats_text.text = _format_from_dict(d)
		return

	var lines: Array[String] = []
	lines.append("Name: %s" % str(_safe_get(player, "character_name", "Unknown")))
	lines.append("Class: %s" % str(_safe_get(player, "character_class", "Paladin")))
	lines.append("Level: %s" % str(_safe_get(player, "level", _safe_call(player, "get_level", 1))))
	lines.append("XP: %s" % str(_safe_get(player, "xp", _safe_call(player, "get_xp", 0))))
	lines.append("Gold: %s" % str(_safe_get(player, "gold", _safe_call(player, "get_gold", 0))))
	lines.append("")
	lines.append("HP: %s / %s" % [
		str(_safe_get(player, "hp", _safe_call(player, "get_hp", "?"))),
		str(_safe_get(player, "max_hp", _safe_call(player, "get_max_hp", "?")))
	])
	lines.append("Attack: %s" % str(_safe_get(player, "attack", _safe_call(player, "get_attack", "?"))))
	lines.append("Defense: %s" % str(_safe_get(player, "defense", _safe_call(player, "get_defense", "?"))))

	stats_text.text = "\n".join(lines)

func _format_from_dict(d: Dictionary) -> String:
	var lines: Array[String] = []
	for k in d.keys():
		lines.append("%s: %s" % [str(k), str(d[k])])
	return "\n".join(lines)

func _safe_call(obj: Object, method: StringName, fallback) -> Variant:
	if obj != null and obj.has_method(method):
		return obj.call(method)
	return fallback

func _safe_get(obj: Object, prop: StringName, fallback) -> Variant:
	if obj == null:
		return fallback
	var v: Variant = obj.get(prop)
	return fallback if v == null else v
