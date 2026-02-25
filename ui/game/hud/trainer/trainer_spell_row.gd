extends HBoxContainer

signal name_clicked(ability_id: String)
signal icon_clicked(ability_id: String)
signal learn_clicked(ability_id: String)

const COST_GOLD_COLOR := Color("d7b25b")
const COST_SILVER_COLOR := Color("c0c0c0")
const COST_BRONZE_COLOR := Color("c26b2b")

var ability_id: String = ""

@onready var icon_rect: TextureRect = $Icon
@onready var name_button: LinkButton = $NameBtn
@onready var rank_label: Label = $RankLabel
@onready var cost_box: HBoxContainer = $CostBox
@onready var cost_gold_label: Label = $CostBox/Gold
@onready var cost_silver_label: Label = $CostBox/Silver
@onready var cost_bronze_label: Label = $CostBox/Bronze
@onready var learn_button: Button = $LearnButton

func _ready() -> void:
	if name_button != null and not name_button.pressed.is_connected(_on_name_pressed):
		name_button.pressed.connect(_on_name_pressed)
	if icon_rect != null and not icon_rect.gui_input.is_connected(_on_icon_gui_input):
		icon_rect.gui_input.connect(_on_icon_gui_input)
	if learn_button != null and not learn_button.pressed.is_connected(_on_learn_pressed):
		learn_button.pressed.connect(_on_learn_pressed)
	call_deferred("_fit_name_button_width")


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_fit_name_button_width()


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
	if current_rank >= max_rank:
		_set_cost_visible(false)
	else:
		_set_cost_visible(true)
		_set_cost_value(cost)
	if learn_button != null:
		if current_rank >= max_rank:
			learn_button.text = "Макс"
			learn_button.disabled = true
		else:
			learn_button.text = "Изучить"
			learn_button.disabled = not can_learn
	call_deferred("_fit_name_button_width")


func _set_cost_visible(visible_value: bool) -> void:
	if cost_box != null:
		cost_box.visible = visible_value


func _set_cost_value(bronze_total: int) -> void:
	var total: int = max(0, bronze_total)
	var gold: int = int(total / 10000)
	var silver: int = int((total % 10000) / 100)
	var bronze: int = int(total % 100)

	if cost_gold_label != null:
		cost_gold_label.visible = gold > 0
		cost_gold_label.text = "%dg" % gold
		cost_gold_label.modulate = COST_GOLD_COLOR
	if cost_silver_label != null:
		cost_silver_label.visible = silver > 0
		cost_silver_label.text = "%ds" % silver
		cost_silver_label.modulate = COST_SILVER_COLOR
	if cost_bronze_label != null:
		cost_bronze_label.visible = true
		cost_bronze_label.text = "%db" % bronze
		cost_bronze_label.modulate = COST_BRONZE_COLOR

func _on_name_pressed() -> void:
	emit_signal("name_clicked", ability_id)

func _on_icon_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			emit_signal("icon_clicked", ability_id)

func _on_learn_pressed() -> void:
	emit_signal("learn_clicked", ability_id)


func _fit_name_button_width() -> void:
	if name_button == null:
		return
	var parent_scroll := _find_parent_scroll()
	if parent_scroll == null:
		return
	var spacing: float = float(get_theme_constant("separation"))
	var max_row_w: float = max(0.0, parent_scroll.size.x - 16.0)
	var occupied_other: float = 0.0
	if icon_rect != null:
		occupied_other += icon_rect.size.x
	if rank_label != null and rank_label.visible:
		if rank_label.text.strip_edges() == "":
			rank_label.custom_minimum_size.x = 1.0
		else:
			rank_label.custom_minimum_size.x = 0.0
		occupied_other += rank_label.get_combined_minimum_size().x
	if cost_box != null and cost_box.visible:
		occupied_other += cost_box.get_combined_minimum_size().x
	if learn_button != null and learn_button.visible:
		occupied_other += learn_button.get_combined_minimum_size().x
	# Four gaps between five columns in row.
	occupied_other += spacing * 4.0
	var name_w: float = max(1.0, max_row_w - occupied_other)
	name_button.custom_minimum_size.x = name_w


func _find_parent_scroll() -> ScrollContainer:
	var n: Node = get_parent()
	while n != null:
		if n is ScrollContainer:
			return n as ScrollContainer
		n = n.get_parent()
	return null

