extends CanvasLayer

@onready var panel: Control = $Panel
@onready var gold_label: Label = $Panel/GoldLabel
@onready var grid: GridContainer = $Panel/Grid

var player: Node = null

func _ready() -> void:
	panel.visible = false
	player = get_tree().get_first_node_in_group("player")

func _process(_delta: float) -> void:
	# toggle inventory with I (ui_cancel often Esc; we’ll define our own action later)
	if Input.is_action_just_pressed("ui_inventory"):
		panel.visible = not panel.visible

	if panel.visible:
		_refresh()

func _refresh() -> void:
	if player == null:
		return
	if not player.has_method("get_inventory_snapshot"):
		return

	var snap: Dictionary = player.get_inventory_snapshot()
	gold_label.text = "gold: %d" % int(snap.get("gold", 0))

	var slots: Array = snap.get("slots", [])
	for i in range(min(grid.get_child_count(), slots.size())):
		var slot_panel: Panel = grid.get_child(i) as Panel
		var label: Label = slot_panel.get_node("Text") as Label

		var slot = slots[i]
		if slot == null:
			label.text = ""
		else:
			var id := String(slot.get("id", ""))
			var item_name := id
			if has_node("/root/DataDB"):
				var db := get_node("/root/DataDB")
				item_name = db.get_item_name(id)
			else:
				name = id
			label.text = "%s x%d" % [item_name, int(slot.get("count", 0))]
