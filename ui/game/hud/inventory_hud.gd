extends CanvasLayer

@onready var panel: Control = $Panel
@onready var gold_label: Label = $Panel/GoldLabel
@onready var grid: GridContainer = $Panel/Grid

@onready var base_bag_button: Button = $BagBar/BaseBagButton
@onready var bag_full_dialog: AcceptDialog = $BagFullDialog

var player: Node = null
var _is_open: bool = true


func _ready() -> void:
	# Inventory HUD should always show the bag bar.
	add_to_group("inventory_ui")
	player = get_tree().get_first_node_in_group("player")

	if base_bag_button != null:
		base_bag_button.pressed.connect(_toggle_inventory)

	# Start open by default (matching previous behavior).
	_set_open(_is_open)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_inventory"):
		_toggle_inventory()

	if _is_open:
		_refresh()


func _toggle_inventory() -> void:
	_set_open(not _is_open)


func _set_open(v: bool) -> void:
	_is_open = v
	# BagBar lives outside the panel and is always visible.
	panel.visible = _is_open


func _refresh() -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return
	if not player.has_method("get_inventory_snapshot"):
		return

	var snap: Dictionary = player.get_inventory_snapshot()
	gold_label.text = "Gold: %s" % _format_money_bronze(int(snap.get("gold", 0)))

	var slots: Array = snap.get("slots", [])
	for i in range(grid.get_child_count()):
		var slot_panel: Panel = grid.get_child(i) as Panel
		if slot_panel == null:
			continue
		var label: Label = slot_panel.get_node_or_null("Text") as Label
		if label == null:
			continue

		if i >= slots.size():
			label.text = ""
			continue
		var slot: Variant = slots[i]
		if slot == null:
			label.text = ""
			continue
		if not (slot is Dictionary):
			label.text = ""
			continue

		var id: String = String((slot as Dictionary).get("id", ""))
		var count: int = int((slot as Dictionary).get("count", 0))
		if id == "" or count <= 0:
			label.text = ""
			continue

		var item_name: String = id
		var db := get_node_or_null("/root/DataDB")
		if db != null and db.has_method("get_item_name"):
			item_name = String(db.call("get_item_name", id))

		label.text = "%s x%d" % [item_name, count]


func show_bag_full(text: String = "Bag is full") -> void:
	if bag_full_dialog == null:
		return
	bag_full_dialog.dialog_text = text
	bag_full_dialog.popup_centered()


func _format_money_bronze(total_bronze: int) -> String:
	var bronze: int = max(total_bronze, 0)
	var gold: int = bronze / 10000
	bronze -= gold * 10000
	var silver: int = bronze / 100
	bronze -= silver * 100
	var parts: Array[String] = []
	if gold > 0:
		parts.append(str(gold) + "g")
	if silver > 0 or gold > 0:
		parts.append(str(silver) + "s")
	parts.append(str(bronze) + "b")
	return " ".join(parts)
