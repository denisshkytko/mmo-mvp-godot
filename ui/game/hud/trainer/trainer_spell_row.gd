extends HBoxContainer

const TOOLTIP_TEXT_BUILDER := preload("res://ui/game/hud/tooltip_text_builder.gd")

signal name_clicked(ability_id: String)
signal learn_clicked(ability_id: String)

var ability_id: String = ""

@onready var icon_rect: TextureRect = $Icon
@onready var name_button: LinkButton = $NameBtn
@onready var rank_label: Label = $RankLabel
@onready var learn_button: Button = $LearnButton
@onready var cost_label: RichTextLabel = $CostLabel

func _ready() -> void:
	if name_button != null and not name_button.pressed.is_connected(_on_name_pressed):
		name_button.pressed.connect(_on_name_pressed)
	if learn_button != null and not learn_button.pressed.is_connected(_on_learn_pressed):
		learn_button.pressed.connect(_on_learn_pressed)
	if cost_label != null:
		cost_label.bbcode_enabled = true
		cost_label.fit_content = true
		cost_label.scroll_active = false

func set_data(definition: AbilityDefinition, current_rank: int, max_rank: int, cost: int, can_learn: bool) -> void:
	if definition == null:
		return
	ability_id = definition.id
	if icon_rect != null:
		icon_rect.texture = definition.icon
	if name_button != null:
		name_button.text = definition.get_display_name()
	if rank_label != null:
		rank_label.text = "R%d/%d" % [current_rank, max_rank]
	if learn_button != null:
		if current_rank >= max_rank:
			learn_button.text = "Макс"
			learn_button.disabled = true
			if cost_label != null:
				cost_label.text = ""
		else:
			learn_button.text = "Изучить"
			learn_button.disabled = not can_learn
			if cost_label != null:
				cost_label.text = TOOLTIP_TEXT_BUILDER.format_money_bbcode(cost)

func _on_name_pressed() -> void:
	emit_signal("name_clicked", ability_id)

func _on_learn_pressed() -> void:
	emit_signal("learn_clicked", ability_id)
