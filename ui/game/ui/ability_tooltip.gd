extends PanelContainer
class_name AbilityTooltip

const OFFSET := Vector2(12, 10)

@onready var name_label: Label = $Margin/VBox/Name
@onready var rank_label: Label = $Margin/VBox/Rank
@onready var description_label: RichTextLabel = $Margin/VBox/Description
@onready var close_button: Button = $CloseButton

func _ready() -> void:
	add_to_group("ability_tooltip_singleton")
	visible = false
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
	var player_rank: int = rank
	if player != null and player.c_spellbook != null:
		player_rank = max(1, player.c_spellbook.get_rank(ability_id))
	var max_rank: int = max(1, ability.get_max_rank())
	var shown_rank: int = clampi(player_rank, 1, max_rank)

	var rank_data: RankData = null
	if db.has_method("get_rank_data"):
		rank_data = db.call("get_rank_data", ability_id, shown_rank)

	name_label.text = ability.get_display_name()
	rank_label.text = "Rank %d/%d" % [shown_rank, ability.get_max_rank()]
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
		return def.description
	var spell_power: float = 0.0
	var base_phys: int = 0
	if player != null and player.has_method("get_stats_snapshot"):
		var snap: Dictionary = player.call("get_stats_snapshot") as Dictionary
		spell_power = float((snap.get("derived", {}) as Dictionary).get("spell_power", 0.0))
	if player != null and player.c_combat != null:
		base_phys = int(player.c_combat.get_attack_damage())

	var lines: Array[String] = []
	var params: Array[String] = []
	if rank_data.cast_time_sec > 0.0:
		params.append("Cast: %.1fs" % rank_data.cast_time_sec)
	if rank_data.cooldown_sec > 0.0:
		params.append("Cooldown: %.1fs" % rank_data.cooldown_sec)
	if rank_data.resource_cost > 0:
		params.append("Cost: %d%% Mana" % rank_data.resource_cost)
	if rank_data.duration_sec > 0.0:
		params.append("Duration: %.1fs" % rank_data.duration_sec)
	if not params.is_empty():
		lines.append("   ".join(params))

	var effect := _effect_line(def.id, rank_data, spell_power, base_phys)
	if effect.strip_edges() != "":
		if not lines.is_empty():
			lines.append("")
		lines.append(effect)
	return "\n".join(lines)

func _effect_line(ability_id: String, rank_data: RankData, spell_power: float, base_phys: int) -> String:
	var scaled_flat: int = int(rank_data.value_flat) + int(round(spell_power))
	var scaled_flat2: int = int(rank_data.value_flat_2) + int(round(spell_power))
	match ability_id:
		"healing_light", "radiant_touch", "lights_verdict_heal":
			return "Heals for %d health." % scaled_flat
		"judging_flame", "lights_verdict_damage":
			return "Deals %d magic damage." % scaled_flat
		"strike_of_light", "storm_of_light":
			return "Deals %.0f%% physical damage and %d magic damage." % [rank_data.value_pct, scaled_flat2]
		"path_of_righteousness":
			return "Autoattacks deal +%d bonus magic damage while active." % scaled_flat
		"aura_of_light_protection":
			return "Increases Physical Defense by %d and Magic Defense by %d." % [rank_data.value_flat, rank_data.value_flat_2]
		"lightbound_might":
			return "Increases Attack Power by %d for %d seconds." % [rank_data.value_flat, int(rank_data.duration_sec)]
		"sacred_barrier", "sacred_guard":
			return ""
		"lights_call":
			return "Revives with %.0f%% Health and %.0f%% Mana." % [rank_data.value_pct, rank_data.value_pct_2]
		"lights_guidance":
			return "Increases Mana Regeneration by %d per second for %d seconds." % [rank_data.value_flat, int(rank_data.duration_sec)]
		"path_of_righteous_fury":
			return "Restores %.0f%% of autoattack damage as Mana." % rank_data.value_pct
		"royal_oath":
			return "Increases core power by %.0f%% for %d seconds." % [rank_data.value_pct, int(rank_data.duration_sec)]
		"concentration_aura":
			return "Increases cast speed by %.0f%%." % rank_data.value_pct
		"path_of_light":
			return "Autoattacks heal you for %.0f%% of damage dealt." % rank_data.value_pct
		"aura_of_tempering":
			return "Increases Physical Damage by %d." % rank_data.value_flat
		"prayer_to_the_light":
			return "Restores %.0f%% of your maximum Mana." % rank_data.value_pct
		"light_execution":
			var hit := int(round(float(base_phys) * rank_data.value_pct_2 / 100.0))
			return "Deals %.0f%% physical damage (%d base) to targets below %.0f%% Health." % [rank_data.value_pct_2, hit, rank_data.value_pct]
		_:
			return "%s" % ability_id

func _position_tooltip(target_pos: Vector2) -> void:
	if not visible:
		return
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	size = get_combined_minimum_size()
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
	add_theme_stylebox_override("panel", sb)
