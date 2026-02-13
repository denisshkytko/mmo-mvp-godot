extends HBoxContainer

const TOOLTIP_BUILDER := preload("res://ui/game/hud/tooltip_text_builder.gd")

signal name_clicked(ability_id: String)
signal learn_clicked(ability_id: String)

var ability_id: String = ""

@onready var icon_rect: TextureRect = $Icon
@onready var name_button: LinkButton = $NameBtn
@onready var rank_label: Label = $RankLabel
@onready var cost_label: RichTextLabel = $CostLabel
@onready var learn_button: Button = $LearnButton

func _ready() -> void:
	if name_button != null and not name_button.pressed.is_connected(_on_name_pressed):
		name_button.pressed.connect(_on_name_pressed)
	if learn_button != null and not learn_button.pressed.is_connected(_on_learn_pressed):
		learn_button.pressed.connect(_on_learn_pressed)


func set_data(definition: AbilityDefinition, current_rank: int, max_rank: int, required_level: int, cost: int, can_learn: bool) -> void:
	if definition == null:
		return
	ability_id = definition.id
	if icon_rect != null:
		icon_rect.texture = definition.icon
	if name_button != null:
		name_button.text = definition.get_display_name()
	if rank_label != null:
		rank_label.text = "Req.Lvl %d" % required_level
	if cost_label != null:
		if current_rank >= max_rank:
			cost_label.clear()
		else:
			cost_label.text = TOOLTIP_BUILDER.format_money_bbcode(cost)
	if learn_button != null:
		if current_rank >= max_rank:
			learn_button.text = "Макс"
			learn_button.disabled = true
		else:
			learn_button.text = "Изучить"
			learn_button.disabled = not can_learn

func _on_name_pressed() -> void:
	emit_signal("name_clicked", ability_id)

func _on_learn_pressed() -> void:
	emit_signal("learn_clicked", ability_id)
