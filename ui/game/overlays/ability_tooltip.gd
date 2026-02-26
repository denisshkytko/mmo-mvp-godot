extends Control
class_name AbilityTooltip

const OFFSET := Vector2(12, 10)

@onready var panel: PanelContainer = $Panel
@onready var name_label: Label = $Panel/Margin/VBox/Name
@onready var rank_label: Label = $Panel/Margin/VBox/Rank
@onready var description_label: RichTextLabel = $Panel/Margin/VBox/Description
@onready var close_button: Button = $CloseButton

var _scene_min_size: Vector2 = Vector2.ZERO

func _ready() -> void:
	add_to_group("ability_tooltip_singleton")
	visible = false
	_scene_min_size = custom_minimum_size
	_style_tooltip_panel()
	if description_label != null:
		description_label.bbcode_enabled = true
		description_label.fit_content = true
		description_label.scroll_active = false
	if close_button != null and not close_button.pressed.is_connected(hide_tooltip):
		close_button.pressed.connect(hide_tooltip)

func show_for(ability_id: String, rank: int, global_pos: Vector2) -> void:
	var db := get_node_or_null("/root/AbilityDB")
	var ability: AbilityDefinition = null
	if db != null and db.has_method("get_ability"):
		ability = db.call("get_ability", ability_id)
	if ability == null:
		name_label.text = ability_id
		rank_label.text = ""
		description_label.text = ""
		visible = true
		move_to_front()
		call_deferred("_show_and_position", global_pos + OFFSET)
		return

	var player: Player = get_tree().get_first_node_in_group("player") as Player
	var requested_rank: int = max(1, rank)
	var max_rank: int = max(1, ability.get_max_rank())
	var shown_rank: int = clampi(requested_rank, 1, max_rank)

	var rank_data: RankData = null
	if db.has_method("get_rank_data"):
		rank_data = db.call("get_rank_data", ability_id, shown_rank)

	name_label.text = ability.get_display_name()
	rank_label.text = tr("ability.common.rank").format({
		"current": shown_rank,
		"max": ability.get_max_rank(),
	})
	description_label.text = _build_tooltip_text(ability, rank_data, shown_rank, player)
	visible = true
	move_to_front()
	call_deferred("_show_and_position", global_pos + OFFSET)

func hide_tooltip() -> void:
	visible = false

func _show_and_position(target_pos: Vector2) -> void:
	# First open can have stale/min-height layout; let UI settle before measuring.
	custom_minimum_size.y = 0.0
	size.y = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	_position_tooltip(target_pos)

func _build_tooltip_text(def: AbilityDefinition, rank_data: RankData, rank: int, player: Player) -> String:
	if rank_data == null:
		return def.get_description_template()
	var spell_power: float = 0.0
	var base_phys: int = 0
	var max_resource: int = 0
	var resource_label: String = tr("ability.common.resource_fallback")
	if player != null and player.has_method("get_stats_snapshot"):
		var snap: Dictionary = player.call("get_stats_snapshot") as Dictionary
		spell_power = float((snap.get("derived", {}) as Dictionary).get("spell_power", 0.0))
		max_resource = int(snap.get("max_resource", snap.get("max_mana", 0)))
	if player != null and player.c_combat != null:
		base_phys = int(player.c_combat.get_attack_damage())
	if player != null and "c_resource" in player and player.c_resource != null:
		max_resource = int(player.c_resource.max_resource)
		resource_label = String(player.c_resource.label_name)
	if max_resource <= 0 and player != null and "max_mana" in player:
		max_resource = int(player.max_mana)

	var lines: Array[String] = []
	lines.append("")
	var params: Array[String] = []
	if rank_data.cast_time_sec > 0.0:
		var cast_time_eff: float = rank_data.cast_time_sec
		if player != null and player.has_method("get_stats_snapshot"):
			var cast_snap: Dictionary = player.call("get_stats_snapshot") as Dictionary
			var cast_speed_pct: float = float(cast_snap.get("cast_speed_pct", 0.0))
			cast_time_eff = rank_data.cast_time_sec * (1.0 / (1.0 + cast_speed_pct / 100.0))
		params.append(tr("ability.common.cast_time").format({"seconds": "%.1f" % cast_time_eff}))
	if rank_data.cooldown_sec > 0.0:
		params.append(tr("ability.common.cooldown").format({"seconds": "%.1f" % rank_data.cooldown_sec}))
	if rank_data.resource_cost > 0:
		var abs_cost: int = int(ceil(float(max_resource) * float(rank_data.resource_cost) / 100.0))
		if abs_cost > 0:
			params.append(tr("ability.common.cost").format({"amount": abs_cost, "resource": resource_label}))
	if not params.is_empty():
		for p in params:
			lines.append(p)

	var effect := _effect_line(def, rank_data, spell_power, base_phys)
	if effect.strip_edges() != "":
		if not params.is_empty():
			lines.append("")
		lines.append(effect)
	return "\n".join(lines)

func _effect_line(def: AbilityDefinition, rank_data: RankData, spell_power: float, base_phys: int) -> String:
	if def == null:
		return ""
	var ability_id: String = def.id
	var scales_with_spell_power: bool = _ability_scales_with_spell_power(def, ability_id)
	var scaled_flat: int = int(rank_data.value_flat)
	var scaled_flat2: int = int(rank_data.value_flat_2)
	if scales_with_spell_power:
		scaled_flat += int(round(spell_power))
		scaled_flat2 += int(round(spell_power))
	return _format_effect_from_template(def.get_description_template(), rank_data, scaled_flat, scaled_flat2)


func _ability_scales_with_spell_power(def: AbilityDefinition, ability_id: String) -> bool:
	if def == null:
		return false
	# Some abilities are typed as active/aoe but still use spell_power_flat effects.
	if ability_id == "lights_verdict" or ability_id == "storm_of_light" or ability_id == "earths_wrath" or ability_id == "lightning":
		return true
	if def.ability_type != "damage" and def.ability_type != "heal":
		return false
	match ability_id:
		# Explicitly non-spell-power formulas.
		"lucky_shot", "aimed_shot", "suppressive_shot", "panjagan", "dirty_strike", "armor_break", "light_execution":
			return false
		_:
			return true


func _format_effect_from_template(template: String, rank_data: RankData, scaled_flat: int, scaled_flat2: int) -> String:
	if template.strip_edges() == "":
		return ""
	var out := template
	out = out.replace("{X}", str(scaled_flat))
	out = out.replace("{X2}", str(int(rank_data.value_flat_2)))
	out = out.replace("{M}", str(scaled_flat2))
	out = out.replace("{P}", str(int(round(rank_data.value_pct))))
	out = out.replace("{P2}", str(int(round(rank_data.value_pct_2))))
	out = out.replace("{N}", str(int((rank_data.flags as Dictionary).get("max_targets", 0))))
	out = out.replace("{T}", str(int(round(rank_data.value_pct))))
	out = out.replace("{HP}", str(int(round(rank_data.value_pct))))
	out = out.replace("{MP}", str(int(round(rank_data.value_pct_2))))
	out = out.replace("{D}", str(int(round(rank_data.duration_sec))))
	return out
func _position_tooltip(target_pos: Vector2) -> void:
	if not visible:
		return
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var base_size := _scene_min_size
	if base_size == Vector2.ZERO:
		base_size = custom_minimum_size
	if base_size == Vector2.ZERO:
		base_size = Vector2(260.0, 90.0)
	var content_size := get_combined_minimum_size()
	var target_size := Vector2(max(base_size.x, content_size.x), max(base_size.y, content_size.y))
	custom_minimum_size = target_size
	size = target_size
	var pos := target_pos
	pos.x = clamp(pos.x, 0.0, max(0.0, vp_size.x - size.x))
	pos.y = clamp(pos.y, 0.0, max(0.0, vp_size.y - size.y))
	global_position = pos

func _style_tooltip_panel() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.85)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	if panel != null:
		panel.add_theme_stylebox_override("panel", sb)
