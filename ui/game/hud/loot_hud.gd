extends CanvasLayer

const TOOLTIP_BUILDER := preload("res://ui/game/hud/tooltip_text_builder.gd")
# LootHUD for Corpse v2 loot (loot_gold + loot_slots).
# - Shows gold as a normal loot row (no extra label)
# - Shows item icons + names from DataDB
# - "Collect all" and per-row collect
# - Tooltip panel rendered beside the window (not under mouse)
const SLOT_COUNT := 6

@onready var panel: Control = $Panel
@onready var scroll: ScrollContainer = $Panel/Scroll
@onready var grid: GridContainer = $Panel/Scroll/Grid
@onready var loot_all_button: Button = $Panel/LootAllButton
@onready var close_button: Button = $Panel/CloseButton

@onready var tooltip_panel: Panel = $TooltipPanel
@onready var tooltip_text: RichTextLabel = $TooltipPanel/Margin/VBox/Text
@onready var tooltip_close_button: Button = $TooltipPanel/CloseButton

var _corpse: Node = null
var _player: Node = null
var _tooltip_view_index: int = -1
var _tooltip_seq: int = 0
var _tooltip_layer: CanvasLayer = null
var _slots_built: bool = false

# UI index -> {type:"gold"} OR {type:"item", slot_index:int}
var _view_map: Array = []

var _range_check_timer: float = 0.0
var _icon_cache: Dictionary = {} # icon_path -> Texture2D


# --- Draggable window state (Loot Panel) ---
const _UI_CFG_PATH := "user://ui_state.cfg"
const _UI_SECTION := "LootHUD"
const _UI_KEY_PANEL_POS := "panel_pos"

var _dragging := false
var _drag_offset := Vector2.ZERO


func _as_corpse(n: Node) -> Corpse:
	# Prefer typed access to Corpse vars. Relying on `"var" in obj` is brittle
	# for script vars that are not exported/stored as properties.
	return n as Corpse


func _ready() -> void:
	panel.visible = false
	tooltip_panel.visible = false
	_ensure_tooltip_layer()
	# Prevent RichTextLabel from keeping an old scroll/offset between hover updates.
	# (This was the root cause of the "text keeps drifting upward" bug.)
	_reset_tooltip_scroll()
	tooltip_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_panel.mouse_filter = Control.MOUSE_FILTER_PASS

	# Make tooltip styling stable and readable
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
	tooltip_panel.add_theme_stylebox_override("panel", sb)

	_player = get_tree().get_first_node_in_group("player")
	loot_all_button.pressed.connect(_on_loot_all_pressed)
	close_button.pressed.connect(close)
	if tooltip_close_button != null:
		tooltip_close_button.pressed.connect(_hide_tooltip)

	# Bind slot UI
	_ensure_slots()
	for i in range(grid.get_child_count()):
		var slot_panel: Panel = grid.get_child(i) as Panel
		if slot_panel == null:
			continue
		var take_button: Button = slot_panel.get_node_or_null("Row/TakeButton") as Button
		if take_button != null:
			take_button.pressed.connect(_on_slot_pressed.bind(i))
			take_button.mouse_filter = Control.MOUSE_FILTER_STOP
		var name_label: RichTextLabel = slot_panel.get_node_or_null("Row/Name") as RichTextLabel
		if name_label != null:
			name_label.bbcode_enabled = true
			name_label.fit_content = false
			name_label.scroll_active = false
			name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
			if name_label.has_method("set_text_overrun_behavior"):
				name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			name_label.gui_input.connect(_on_slot_tapped.bind(i))
			name_label.mouse_filter = Control.MOUSE_FILTER_STOP
		var count_label: Label = slot_panel.get_node_or_null("Row/Count") as Label
		if count_label != null:
			count_label.autowrap_mode = TextServer.AUTOWRAP_OFF
			count_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			count_label.clip_text = true
			count_label.mouse_filter = Control.MOUSE_FILTER_STOP
		var icon_rect: TextureRect = slot_panel.get_node_or_null("Row/Icon") as TextureRect
		if icon_rect != null:
			icon_rect.gui_input.connect(_on_slot_tapped.bind(i))
			icon_rect.mouse_filter = Control.MOUSE_FILTER_STOP


	# Draggable loot window (only when clicking on the panel background / title area)
	panel.gui_input.connect(_on_panel_gui_input)
	_load_panel_position()
	_clamp_panel_to_viewport()
	_position_tooltip_beside_panel()


func _process(delta: float) -> void:
	if panel.visible and (_corpse == null or not is_instance_valid(_corpse)):
		close()
		return

	if not panel.visible:
		return

	if _corpse == null or not is_instance_valid(_corpse):
		close()
		return

	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			close()
			return

	_range_check_timer -= delta
	if _range_check_timer > 0.0:
		return
	_range_check_timer = 0.1

	# Close if too far from corpse
	var corpse_typed := _as_corpse(_corpse)
	if corpse_typed != null and (_corpse is Node2D) and (_player is Node2D):
		var corpse_pos: Vector2 = (_corpse as Node2D).global_position
		var player_pos: Vector2 = (_player as Node2D).global_position
		var radius: float = float(corpse_typed.interact_radius)
		if player_pos.distance_to(corpse_pos) > radius:
			close()
			return

	_refresh()

func open_for_corpse(corpse: Node) -> void:
	if panel.visible and _corpse == corpse:
		return
	_corpse = corpse
	panel.visible = true
	_range_check_timer = 0.0
	_clamp_panel_to_viewport()
	_position_tooltip_beside_panel()
	_refresh()

func close() -> void:
	panel.visible = false
	_corpse = null
	_hide_tooltip()


func toggle_for_corpse(corpse: Node) -> void:
	if panel.visible and _corpse == corpse:
		close()
	else:
		open_for_corpse(corpse)


func is_looting_corpse(corpse: Node) -> bool:
	return panel.visible and _corpse == corpse



# -----------------------------------------------------------------------------
# Draggable Loot Panel + position persistence
# -----------------------------------------------------------------------------

func _load_panel_position() -> void:
	var cf := ConfigFile.new()
	var err := cf.load(_UI_CFG_PATH)
	if err != OK:
		return
	var v: Variant = cf.get_value(_UI_SECTION, _UI_KEY_PANEL_POS, null)
	if v is Vector2:
		panel.global_position = v

func _save_panel_position() -> void:
	var cf := ConfigFile.new()
	# Ignore load errors; we always write a fresh file.
	cf.load(_UI_CFG_PATH)
	cf.set_value(_UI_SECTION, _UI_KEY_PANEL_POS, panel.global_position)
	cf.save(_UI_CFG_PATH)

func _clamp_panel_to_viewport() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var screen := vp.get_visible_rect().size
	# Keep the loot window fully within the visible screen.
	var sz := panel.size
	var gp := panel.global_position
	gp.x = clamp(gp.x, 0.0, max(0.0, screen.x - sz.x))
	gp.y = clamp(gp.y, 0.0, max(0.0, screen.y - sz.y))
	panel.global_position = gp


func _mark_input_handled() -> void:
	# loot_hud.gd is not necessarily a Control, so we can't call accept_event().
	# Mark input as handled via the viewport.
	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()

func _on_panel_gui_input(event: InputEvent) -> void:
	if not panel.visible:
		return

	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			# Start dragging only when clicking on the panel background or title label,
			# not on interactive controls (buttons, scroll area, slots).
			var hovered := get_viewport().gui_get_hovered_control()
			if hovered == panel or (hovered != null and hovered.name == "Title" and hovered.get_parent() == panel):
				_dragging = true
				_drag_offset = panel.global_position - get_viewport().get_mouse_position()
				_mark_input_handled()
		else:
			if _dragging:
				_dragging = false
				_clamp_panel_to_viewport()
				_save_panel_position()
				_position_tooltip_beside_panel()
				_mark_input_handled()

	elif event is InputEventMouseMotion and _dragging:
		var mouse := get_viewport().get_mouse_position()
		panel.global_position = mouse + _drag_offset
		_clamp_panel_to_viewport()
		_position_tooltip_beside_panel()
		_mark_input_handled()

func _ensure_slots() -> void:
	if _slots_built:
		return
	if grid == null:
		return
	var template: Panel = grid.get_node_or_null("LootSlot0") as Panel
	if template == null:
		return
	for i in range(1, SLOT_COUNT):
		var clone := template.duplicate() as Panel
		clone.name = "LootSlot%d" % i
		grid.add_child(clone)
	_slots_built = true

func _refresh() -> void:
	if _corpse == null:
		return

	var slots: Array = []
	var gold: int = 0
	var corpse_typed := _as_corpse(_corpse)
	if corpse_typed != null:
		slots = corpse_typed.loot_slots
		gold = corpse_typed.loot_gold
	else:
		# Fallback for unexpected node types
		if "loot_slots" in _corpse:
			var v: Variant = _corpse.get("loot_slots")
			if v is Array:
				slots = v as Array
		if "loot_gold" in _corpse:
			gold = int(_corpse.get("loot_gold"))

	# If empty => close (mark_looted handled by corpse logic elsewhere)
	if (gold <= 0) and (slots == null or slots.is_empty()):
		if _corpse.has_method("mark_looted"):
			_corpse.call("mark_looted")
		close()
		return

	_view_map.clear()
	if gold > 0:
		_view_map.append({"type": "gold"})
	for si in range(slots.size()):
		var s: Variant = slots[si]
		if s is Dictionary and String((s as Dictionary).get("type", "")) == "item":
			_view_map.append({"type": "item", "slot_index": si})

	# Scroll behavior
	if _view_map.size() <= 4:
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	else:
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

	# Fill fixed 6 UI slots
	for i in range(grid.get_child_count()):
		var slot_panel: Panel = grid.get_child(i) as Panel
		if slot_panel == null:
			continue
		var label: RichTextLabel = slot_panel.get_node_or_null("Row/Name") as RichTextLabel
		var count_label: Label = slot_panel.get_node_or_null("Row/Count") as Label
		var take_button: Button = slot_panel.get_node_or_null("Row/TakeButton") as Button
		var icon_rect: TextureRect = slot_panel.get_node_or_null("Row/Icon") as TextureRect

		if i >= _view_map.size():
			slot_panel.visible = false
			if label != null:
				label.text = ""
			if count_label != null:
				count_label.text = ""
			if take_button != null:
				take_button.disabled = true
			if icon_rect != null:
				icon_rect.texture = null
			continue

		slot_panel.visible = true
		if take_button != null:
			take_button.disabled = false
			take_button.text = "Take"
		if icon_rect != null:
			icon_rect.texture = null

		var map_d: Dictionary = _view_map[i] as Dictionary
		var t: String = String(map_d.get("type", ""))

		if t == "gold":
			if label != null:
				label.text = "Gold: %s" % TOOLTIP_BUILDER.format_money_bbcode(gold)
			if count_label != null:
				count_label.text = ""
			if take_button != null:
				take_button.text = "Take"
				# Optional icon: if you later add a gold item/icon in DB, hook it here.

		elif t == "item":
			var si2: int = int(map_d.get("slot_index", -1))
			if si2 < 0 or si2 >= slots.size():
				slot_panel.visible = false
				continue
			var item_d: Dictionary = slots[si2] as Dictionary
			var id: String = String(item_d.get("id", ""))
			var count: int = int(item_d.get("count", 0))

			var item_name: String = id
			var icon_tex: Texture2D = null
			var db := get_node_or_null("/root/DataDB")
			if db != null and db.has_method("get_item"):
				var meta: Dictionary = db.call("get_item", id)
				if not meta.is_empty():
					item_name = String(meta.get("name", id))
					# Support both legacy schema (icon_path) and new DB schema (icon)
					var ip: String = String(meta.get("icon_path", meta.get("icon", "")))
					if not ip.is_empty():
						icon_tex = _get_icon(ip)

			if label != null:
				label.text = item_name
			if count_label != null:
				count_label.text = "x%d" % count
			if icon_rect != null:
				icon_rect.texture = icon_tex


func _get_icon(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _icon_cache.has(path):
		return _icon_cache[path] as Texture2D
	var tex: Texture2D = null
	var res: Resource = load(path)
	if res is Texture2D:
		tex = res as Texture2D

	# Scale icons down to fit the loot row icon area.
	# This keeps UI readable even if source icons are 128/256px.
	var out: Texture2D = tex
	if tex != null:
		var img: Image = tex.get_image()
		if img != null and not img.is_empty():
			var target: int = 40
			var w: int = img.get_width()
			var h: int = img.get_height()
			if w > target or h > target:
				# Do not shadow CanvasLayer.scale (warning treated as error in this project).
				var icon_scale: float = min(float(target) / float(w), float(target) / float(h))
				var nw: int = max(1, int(round(w * icon_scale)))
				var nh: int = max(1, int(round(h * icon_scale)))
				img.resize(nw, nh, Image.INTERPOLATE_LANCZOS)
				out = ImageTexture.create_from_image(img)
	_icon_cache[path] = out
	return out


func _on_slot_pressed(view_index: int) -> void:
	_hide_tooltip()
	if _corpse == null or _player == null:
		return
	if view_index < 0 or view_index >= _view_map.size():
		return

	var corpse: Node = _corpse
	var corpse_typed := _as_corpse(corpse)
	var gold: int = 0
	var slots: Array = []
	if corpse_typed != null:
		gold = corpse_typed.loot_gold
		slots = corpse_typed.loot_slots
	else:
		gold = int(corpse.get("loot_gold")) if ("loot_gold" in corpse) else 0
		if "loot_slots" in corpse:
			var v: Variant = corpse.get("loot_slots")
			if v is Array:
				slots = v as Array

	var m: Dictionary = _view_map[view_index] as Dictionary
	var t: String = String(m.get("type", ""))

	if t == "gold":
		if gold > 0 and _player.has_method("add_gold"):
			_player.call("add_gold", gold)
		if corpse_typed != null:
			corpse_typed.loot_gold = 0
		else:
			corpse.set("loot_gold", 0)

	elif t == "item":
		var si: int = int(m.get("slot_index", -1))
		if si >= 0 and si < slots.size():
			var item_d: Dictionary = slots[si] as Dictionary
			var id: String = String(item_d.get("id", ""))
			var count: int = int(item_d.get("count", 0))
			if id != "" and count > 0 and _player.has_method("add_item"):
				# add_item returns how many did NOT fit into the inventory.
				var remaining: int = int(_player.call("add_item", id, count))
				if remaining <= 0:
					slots.remove_at(si)
				else:
					# Partially looted: leave the remainder in the corpse.
					item_d["count"] = remaining
					slots[si] = item_d
					_notify_bag_full()
			# Persist updated slots back to corpse.
			if corpse_typed != null:
				corpse_typed.loot_slots = slots
			else:
				corpse.set("loot_slots", slots)

	# Close if empty now
	var empty_now: bool = false
	if corpse.has_method("has_loot"):
		empty_now = not bool(corpse.call("has_loot"))
	else:
		var gold_after: int = int(corpse.get("loot_gold")) if ("loot_gold" in corpse) else 0
		var slots_after: Array = corpse.get("loot_slots") if ("loot_slots" in corpse) else []
		empty_now = (gold_after <= 0) and (slots_after == null or slots_after.is_empty())

	if empty_now:
		if corpse.has_method("mark_looted"):
			corpse.call("mark_looted")
		close()
		return

	_refresh()

func _on_loot_all_pressed() -> void:
	_hide_tooltip()
	if _corpse == null or _player == null:
		return
	if _corpse.has_method("loot_all_to_player"):
		_corpse.call("loot_all_to_player", _player)
	# If some items didn't fit, keep HUD open and refresh.
	if _corpse != null and is_instance_valid(_corpse) and _corpse.has_method("has_loot"):
		if bool(_corpse.call("has_loot")):
			_notify_bag_full()
			_refresh()
			return
	close()


func _notify_bag_full() -> void:
	var inv_ui := get_tree().get_first_node_in_group("inventory_ui")
	if inv_ui != null and inv_ui.has_method("show_bag_full"):
		inv_ui.call("show_bag_full")


# -----------------------------------------------------------------------------
# Tooltip (panel beside LootHUD)
# -----------------------------------------------------------------------------

func _on_slot_tapped(event: InputEvent, view_index: int) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index != MOUSE_BUTTON_LEFT or not mouse.pressed:
			return
	elif event is InputEventScreenTouch:
		if not (event as InputEventScreenTouch).pressed:
			return
	else:
		return
	if view_index < 0 or view_index >= _view_map.size():
		_hide_tooltip()
		return
	if tooltip_panel.visible and _tooltip_view_index == view_index:
		_hide_tooltip()
		return
	_hide_tooltip()
	_tooltip_view_index = -1
	_show_tooltip_for_view(view_index)


func _show_tooltip_for_view(view_index: int) -> void:
	_tooltip_seq += 1
	var seq := _tooltip_seq
	if OS.is_debug_build():
		print("LootHUD tooltip start seq=", seq, " view=", view_index)
	if _corpse == null or not is_instance_valid(_corpse):
		_hide_tooltip()
		return
	if view_index < 0 or view_index >= _view_map.size():
		_hide_tooltip()
		return

	var m: Dictionary = _view_map[view_index] as Dictionary
	var t: String = String(m.get("type", ""))

	var text_out: String = ""
	var target_view := view_index
	if t == "gold":
		var corpse_typed := _as_corpse(_corpse)
		var gold_amount: int = corpse_typed.loot_gold if corpse_typed != null else (int(_corpse.get("loot_gold")) if ("loot_gold" in _corpse) else 0)
		text_out = "Gold\n" + TOOLTIP_BUILDER.format_money_bbcode(gold_amount)
	elif t == "item":
		var corpse_typed2 := _as_corpse(_corpse)
		var slots: Array = corpse_typed2.loot_slots if corpse_typed2 != null else (_corpse.get("loot_slots") if ("loot_slots" in _corpse) else [])
		var si: int = int(m.get("slot_index", -1))
		if si < 0 or si >= slots.size():
			_hide_tooltip()
			return
		var item_d: Dictionary = slots[si] as Dictionary
		var id: String = String(item_d.get("id", ""))
		if id == "":
			_hide_tooltip()
			return
		var db := get_node_or_null("/root/DataDB")
		var item: Dictionary = {}
		if db != null and db.has_method("get_item"):
			item = db.call("get_item", id)
		text_out = _build_item_tooltip_text(item)

	if text_out.strip_edges().is_empty():
		_hide_tooltip()
		return

	tooltip_panel.visible = false
	tooltip_panel.custom_minimum_size = Vector2(tooltip_panel.custom_minimum_size.x, 0)
	tooltip_panel.size = Vector2(tooltip_panel.size.x, 0)
	tooltip_text.text = ""

	# RichTextLabel: assign BBCode via .text (bbcode_enabled=true).
	# Clear first to avoid any stale layout.
	if tooltip_text.has_method("clear"):
		tooltip_text.call("clear")
	tooltip_text.text = text_out

	# Warm-up layout while hidden visually so measurements are valid.
	var prev_modulate := tooltip_panel.modulate
	tooltip_panel.visible = true
	tooltip_panel.modulate = Color(prev_modulate.r, prev_modulate.g, prev_modulate.b, 0.0)
	await get_tree().process_frame
	if seq != _tooltip_seq or not is_instance_valid(tooltip_panel) or not tooltip_panel.visible or _tooltip_view_index != -1 and _tooltip_view_index != target_view:
		if OS.is_debug_build():
			print("LootHUD tooltip cancel seq=", seq, " view=", view_index)
		return
	await get_tree().process_frame
	if seq != _tooltip_seq or not is_instance_valid(tooltip_panel) or not tooltip_panel.visible or _tooltip_view_index != -1 and _tooltip_view_index != target_view:
		if OS.is_debug_build():
			print("LootHUD tooltip cancel seq=", seq, " view=", view_index)
		return
	await _apply_tooltip_layout()
	if seq != _tooltip_seq or not is_instance_valid(tooltip_panel) or not tooltip_panel.visible or _tooltip_view_index != -1 and _tooltip_view_index != target_view:
		if OS.is_debug_build():
			print("LootHUD tooltip cancel seq=", seq, " view=", view_index)
		return
	# Lock final size before showing to avoid the first-frame resize flicker.
	var final_size := tooltip_panel.size
	tooltip_panel.custom_minimum_size = final_size
	tooltip_panel.size = final_size
	_position_tooltip_beside_panel()
	tooltip_panel.modulate = prev_modulate
	tooltip_panel.visible = true
	_tooltip_view_index = view_index
	if OS.is_debug_build():
		print("LootHUD tooltip shown seq=", seq, " view=", view_index)


func _hide_tooltip() -> void:
	tooltip_panel.visible = false
	_tooltip_view_index = -1
	_tooltip_seq += 1
	_reset_tooltip_scroll()


func _apply_tooltip_layout() -> void:
	# Fixed width tooltip; height grows to fit text.
	var width: float = 360.0
	tooltip_panel.size = Vector2(width, 10)
	tooltip_panel.custom_minimum_size = Vector2(width, 0)

	# Ensure the label wraps within the tooltip width.
	tooltip_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	tooltip_text.custom_minimum_size = Vector2(width - 20.0, 0)

	# Ask Godot for the wrapped text height and apply padding.
	# RichTextLabel exposes content height.
	var content_h: float = float(tooltip_text.get_content_height())
	if content_h <= 1.0 and tooltip_text.text.strip_edges() != "":
		await get_tree().process_frame
		content_h = float(tooltip_text.get_content_height())
	var min_from_label := tooltip_text.get_combined_minimum_size().y
	var height: float = max(32.0, max(content_h, min_from_label) + 16.0)
	tooltip_panel.size = Vector2(width, height)

func _reset_tooltip_scroll() -> void:
	# RichTextLabel can keep a previous scroll offset. Ensure it is reset.
	if tooltip_text == null:
		return
	if tooltip_text.has_method("scroll_to_line"):
		tooltip_text.call("scroll_to_line", 0)
	# Also force v_scroll to 0 if the scrollbar exists.
	var sb := tooltip_text.get_v_scroll_bar() if tooltip_text.has_method("get_v_scroll_bar") else null
	if sb != null:
		sb.value = 0

func _position_tooltip_beside_panel() -> void:
	# Tooltip is anchored beside the loot window, top-aligned, and clamped on screen.
	var pr := panel.get_global_rect()
	var vp := get_viewport().get_visible_rect().size
	var gap := 8.0
	var size := tooltip_panel.size
	var right_pos := pr.position + Vector2(pr.size.x + gap, 0.0)
	var left_pos := pr.position + Vector2(-gap - size.x, 0.0)
	var pos := right_pos
	if right_pos.x + size.x > vp.x - gap and left_pos.x >= gap:
		pos = left_pos
	elif right_pos.x + size.x > vp.x - gap:
		pos.x = max(gap, vp.x - size.x - gap)
	pos.y = clamp(pr.position.y, gap, vp.y - size.y - gap)
	tooltip_panel.global_position = pos

func _ensure_tooltip_layer() -> void:
	if tooltip_panel == null:
		return
	if _tooltip_layer == null:
		_tooltip_layer = CanvasLayer.new()
		_tooltip_layer.name = "TooltipLayer"
		_tooltip_layer.layer = 200
		add_child(_tooltip_layer)
	if tooltip_panel.get_parent() != _tooltip_layer:
		tooltip_panel.reparent(_tooltip_layer)


func _unhandled_input(event: InputEvent) -> void:
	if not panel.visible or not tooltip_panel.visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_hide_tooltip()
	elif event is InputEventScreenTouch:
		if (event as InputEventScreenTouch).pressed:
			_hide_tooltip()


func _build_item_tooltip_text(item: Dictionary) -> String:
	return TOOLTIP_BUILDER.build_item_tooltip(item, 1, _player)


func _rarity_color_hex(rarity: String, typ: String) -> String:
	var r := rarity.to_lower()
	if r == "" and typ == "junk":
		r = "junk"
	match r:
		"junk":
			return "#8a8a8a"
		"common":
			return "#ffffff"
		"uncommon":
			return "#3bdc3b"
		"rare":
			return "#4aa3ff"
		"epic":
			return "#a335ee"
		"legendary":
			return "#ff8000"
		_:
			return "#ffffff"


func _get_consumable_cd_total_for_item(item: Dictionary) -> float:
	var typ: String = String(item.get("type", "")).to_lower()
	if typ == "potion":
		return 5.0
	if typ == "food" or typ == "drink":
		return 10.0
	return 0.0


func _format_consumable_effects(c: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var instant: bool = bool(c.get("instant", false))
	if instant:
		var hp: int = int(c.get("hp", 0))
		var mp: int = int(c.get("mp", 0))
		if hp > 0:
			out.append("restores %d hp" % hp)
		if mp > 0:
			out.append("restores %d mp" % mp)
	else:
		var dur: int = int(c.get("duration_sec", 0))
		var hp_t: int = int(c.get("hp_total", 0))
		var mp_t: int = int(c.get("mp_total", 0))
		if hp_t > 0:
			if dur > 0:
				out.append("restores %d hp over %ds" % [hp_t, dur])
			else:
				out.append("restores %d hp" % hp_t)
		if mp_t > 0:
			if dur > 0:
				out.append("restores %d mp over %ds" % [mp_t, dur])
			else:
				out.append("restores %d mp" % mp_t)
	return out


func _format_money_bronze(total_bronze: int) -> String:
	var bronze: int = max(total_bronze, 0)
	var gold: int = int(bronze / 10000)
	bronze -= gold * 10000
	var silver: int = int(bronze / 100)
	bronze -= silver * 100
	var parts: Array[String] = []
	if gold > 0:
		parts.append(str(gold) + "g")
	if silver > 0 or gold > 0:
		parts.append(str(silver) + "s")
	parts.append(str(bronze) + "b")
	return " ".join(parts)
