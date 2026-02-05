extends PanelContainer
class_name AbilityTooltip

const OFFSET := Vector2(12, 10)

@onready var name_label: Label = $Margin/VBox/Name
@onready var rank_label: Label = $Margin/VBox/Rank
@onready var description_label: RichTextLabel = $Margin/VBox/Description

func _ready() -> void:
	add_to_group("ability_tooltip_singleton")
	visible = false
	if description_label != null:
		description_label.bbcode_enabled = true
		description_label.fit_content = true
		description_label.scroll_active = false

func show_for(ability_id: String, rank: int, global_pos: Vector2) -> void:
	var db := get_node_or_null("/root/AbilityDB")
	var ability: AbilityDefinition = null
	if db != null and db.has_method("get_ability"):
		ability = db.call("get_ability", ability_id)
	if ability != null:
		name_label.text = ability.get_display_name()
		rank_label.text = "Rank %d/%d" % [rank, ability.get_max_rank()]
		description_label.text = ability.description
	else:
		name_label.text = ability_id
		rank_label.text = ""
		description_label.text = ""
	visible = true
	call_deferred("_position_tooltip", global_pos + OFFSET)

func hide_tooltip() -> void:
	visible = false

func _position_tooltip(target_pos: Vector2) -> void:
	if not visible:
		return
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	size = get_combined_minimum_size()
	var pos := target_pos
	pos.x = clamp(pos.x, 0.0, max(0.0, vp_size.x - size.x))
	pos.y = clamp(pos.y, 0.0, max(0.0, vp_size.y - size.y))
	global_position = pos
