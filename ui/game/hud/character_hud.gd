extends Control

const NODE_CACHE := preload("res://core/runtime/node_cache.gd")

@onready var character_button: Button = $CharacterButton
@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/MarginContainer/VBoxContainer/TitleLabel
@onready var stats_text: RichTextLabel = $Panel/MarginContainer/VBoxContainer/ContentRow/StatsScroll/StatsText

@onready var tooltip_panel: Panel = $TooltipPanel
@onready var tooltip_rich: RichTextLabel = $TooltipPanel/Margin/TooltipText

var _player: Player = null
var _breakdown_cache: Dictionary = {}

func _ready() -> void:
	character_button.pressed.connect(_on_button)

	stats_text.bbcode_enabled = true
	stats_text.fit_content = true
	stats_text.meta_hover_started.connect(_on_meta_hover_started)
	stats_text.meta_hover_ended.connect(_on_meta_hover_ended)

	tooltip_rich.bbcode_enabled = true
	tooltip_rich.fit_content = true
	tooltip_panel.visible = false
	tooltip_rich.text = ""

	_player = NODE_CACHE.get_player(get_tree()) as Player
	if _player != null and _player.c_stats != null:
		_player.c_stats.stats_changed.connect(_on_stats_changed)

	_refresh()

func _on_button() -> void:
	panel.visible = not panel.visible
	if panel.visible:
		_refresh()
	else:
		_hide_tooltip()

func _on_stats_changed(_snapshot: Dictionary) -> void:
	if panel.visible:
		_refresh()

func _on_meta_hover_started(meta) -> void:
	if not panel.visible:
		return

	var key := String(meta)
	if not _breakdown_cache.has(key):
		return

	tooltip_panel.visible = true
	tooltip_rich.text = String(_breakdown_cache[key])
	_position_tooltip()

func _on_meta_hover_ended(_meta) -> void:
	_hide_tooltip()

func _hide_tooltip() -> void:
	tooltip_panel.visible = false
	tooltip_rich.text = ""

func _refresh() -> void:
	_player = NODE_CACHE.get_player(get_tree()) as Player
	_breakdown_cache.clear()
	_hide_tooltip()

	if _player == null:
		title_label.text = "Character"
		stats_text.text = "No player."
		return

	title_label.text = "%s  (Level %d)" % [String(_player.name), _player.level]

	var snap: Dictionary = {}
	if _player.has_method("get_stats_snapshot"):
		snap = _player.get_stats_snapshot()

	if snap.is_empty():
		stats_text.text = _fallback_text()
		return

	stats_text.text = _format_snapshot(snap)

func _fallback_text() -> String:
	return "HP %d/%d\nMana %d/%d\nAttack %d\nDefense %d" % [
		_player.current_hp, _player.max_hp,
		_player.mana, _player.max_mana,
		_player.attack, _player.defense,
	]

func _format_snapshot(snap: Dictionary) -> String:
	var p: Dictionary = snap.get("primary", {}) as Dictionary
	var d: Dictionary = snap.get("derived", {}) as Dictionary
	var b: Dictionary = snap.get("derived_breakdown", {}) as Dictionary

	var lines: Array[String] = []

	# Primary (single column, full names)
	lines.append("[b]Основные характеристики[/b]")
	lines.append("Сила %d" % int(p.get("str", 0)))
	lines.append("Ловкость %d" % int(p.get("agi", 0)))
	lines.append("Выносливость %d" % int(p.get("end", 0)))
	lines.append("Интеллект %d" % int(p.get("int", 0)))
	lines.append("Восприятие %d" % int(p.get("per", 0)))

	lines.append("")
	lines.append("[b]Здоровье и мана[/b]")
	lines.append(_line_with_breakdown("Макс. здоровье", "max_hp", d, b, ""))
	lines.append(_line_with_breakdown("Макс. мана", "max_mana", d, b, ""))
	lines.append(_line_with_breakdown("Восстановление здоровья", "hp_regen", d, b, "в секунду"))
	lines.append(_line_with_breakdown("Восстановление маны", "mana_regen", d, b, "в секунду"))

	lines.append("")
	lines.append("[b]Урон[/b]")
	lines.append(_line_with_breakdown("Сила атаки", "attack_power", d, b, "Увеличивает физический урон на это значение"))
	lines.append(_line_with_breakdown("Сила заклинаний", "spell_power", d, b, "Увеличивает магический урон и исцеление на это значение"))

	lines.append(_line_with_breakdown(
		"Рейтинг крит. шанса",
		"crit_chance_rating",
		d,
		b,
		"Шанс критического удара %.2f%%" % float(snap.get("crit_chance_pct", 0.0))
	))
	lines.append(_line_with_breakdown(
		"Рейтинг крит. урона",
		"crit_damage_rating",
		d,
		b,
		"Критический урон x%.2f" % float(snap.get("crit_multiplier", 2.0))
	))

	lines.append("")
	lines.append("[b]Скорость[/b]")
	lines.append(_line_with_breakdown(
		"Скорость",
		"speed",
		d,
		b,
		"Снижает время восстановления способностей на %.2f%%" % float(snap.get("cooldown_reduction_pct", 0.0))
	))
	lines.append(_line_with_breakdown(
		"Скорость атаки",
		"attack_speed_rating",
		d,
		b,
		"Увеличивает скорость атаки на %.2f%%" % float(snap.get("attack_speed_pct", 0.0))
	))
	lines.append(_line_with_breakdown(
		"Скорость произнесения",
		"cast_speed_rating",
		d,
		b,
		"Снижает время произнесения заклинаний на %.2f%%" % float(snap.get("cast_speed_pct", 0.0))
	))

	lines.append("")
	lines.append("[b]Защита[/b]")
	lines.append(_line_with_breakdown(
		"Защита",
		"defense",
		d,
		b,
		"Снижает получаемый физический урон на %.2f%%" % float(snap.get("defense_mitigation_pct", 0.0))
	))
	lines.append(_line_with_breakdown(
		"Маг. сопротивление",
		"magic_resist",
		d,
		b,
		"Снижает получаемый магический урон на %.2f%%" % float(snap.get("magic_mitigation_pct", 0.0))
	))

	return "\n".join(lines)

func _position_tooltip() -> void:
	# Place tooltip beside the character panel (outside), so it never affects layout.
	if tooltip_panel == null or panel == null:
		return

	var vp: Rect2 = get_viewport_rect()
	var ppos: Vector2 = panel.global_position
	var psz: Vector2 = panel.size

	# Size: keep stable; do not auto-expand based on text width.
	tooltip_panel.size = Vector2(360, max(200, psz.y))

	var desired := ppos + Vector2(psz.x + 12.0, 0.0)
	var tsize := tooltip_panel.size

	# If doesn't fit to the right -> move to the left
	if desired.x + tsize.x > vp.position.x + vp.size.x:
		desired.x = ppos.x - tsize.x - 12.0

	# Clamp vertically
	if desired.y + tsize.y > vp.position.y + vp.size.y:
		desired.y = vp.position.y + vp.size.y - tsize.y - 8.0
	if desired.y < vp.position.y:
		desired.y = vp.position.y + 8.0

	tooltip_panel.global_position = desired

func _line_with_breakdown(title: String, key: String, derived: Dictionary, breakdown: Dictionary, effect_text: String) -> String:
	var val = derived.get(key, 0)
	var val_str: String
	if typeof(val) == TYPE_FLOAT:
		val_str = String.num(val, 2)
	else:
		val_str = str(int(val))

	# Build breakdown text for tooltip
	var parts: Array[String] = []
	var flat_parts: Array[String] = []
	if breakdown.has(key):
		var arr: Array = breakdown[key] as Array
		for e in arr:
			if not (e is Dictionary):
				continue
			var dd: Dictionary = e as Dictionary
			var label: String = String(dd.get("label", ""))
			var v = dd.get("value", 0)
			var extra: String = String(dd.get("extra", ""))

			var vv: String = String.num(float(v), 2) if typeof(v) == TYPE_FLOAT else str(int(v))
			parts.append("%s %s%s" % [label, vv, "" if extra == "" else " " + extra])

			var short_label := _rus_short_label(label)
			flat_parts.append("%s %s" % [vv, short_label])

	# Main panel line: only title + total value (tooltip contains effect and sources)
	var summary := "[url=%s]%s %s[/url]" % [key, title, val_str]

	var tooltip_lines: Array[String] = []
	if effect_text != "":
		var src := ""
		if not flat_parts.is_empty():
			src = " (" + " + ".join(flat_parts) + ")"
		tooltip_lines.append("%s%s" % [effect_text, src])
	elif not flat_parts.is_empty():
		tooltip_lines.append("(" + " + ".join(flat_parts) + ")")

	if not parts.is_empty():
		tooltip_lines.append("\n" + "\n".join(parts))

	_breakdown_cache[key] = "\n".join(tooltip_lines).strip_edges()

	return summary

func _rus_short_label(label: String) -> String:
	var l := label.to_lower()
	if l.find("gear") != -1 or l.find("armor") != -1 or l.find("item") != -1:
		return "броня"
	if l == "str":
		return "сила"
	if l == "agi":
		return "ловкость"
	if l == "end":
		return "выносливость"
	if l == "int":
		return "интеллект"
	if l == "per":
		return "восприятие"
	return label
