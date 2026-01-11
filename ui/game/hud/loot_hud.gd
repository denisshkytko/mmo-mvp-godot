extends CanvasLayer

# LootHUD for Corpse v2 loot (loot_gold + loot_slots).
# - Shows gold as a normal loot row (no extra label)
# - Shows item icons + names from DataDB
# - "Collect all" and per-row collect
# - Tooltip panel rendered beside the window (not under mouse)

@onready var panel: Control = $Panel
@onready var scroll: ScrollContainer = $Panel/Scroll
@onready var grid: GridContainer = $Panel/Scroll/Grid
@onready var loot_all_button: Button = $Panel/LootAllButton
@onready var close_button: Button = $Panel/CloseButton

@onready var tooltip_panel: Panel = $TooltipPanel
@onready var tooltip_text: Label = $TooltipPanel/Text

var _corpse: Node = null
var _player: Node = null

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
	# Prevent RichTextLabel from keeping an old scroll/offset between hover updates.
	# (This was the root cause of the "text keeps drifting upward" bug.)
	_reset_tooltip_scroll()
	tooltip_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

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

	# Bind slot UI
	for i in range(grid.get_child_count()):
		var slot_panel: Panel = grid.get_child(i) as Panel
		if slot_panel == null:
			continue
		var b: Button = slot_panel.get_node_or_null("Button") as Button
		if b != null:
			b.pressed.connect(_on_slot_pressed.bind(i))
			b.mouse_entered.connect(_on_slot_hover.bind(i))
			b.mouse_exited.connect(_hide_tooltip)
			b.mouse_filter = Control.MOUSE_FILTER_STOP

	panel.mouse_exited.connect(_hide_tooltip)


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
		var label: Label = slot_panel.get_node_or_null("Text") as Label
		var b: Button = slot_panel.get_node_or_null("Button") as Button

		if i >= _view_map.size():
			slot_panel.visible = false
			if label != null:
				label.text = ""
			if b != null:
				b.disabled = true
				b.icon = null
			continue

		slot_panel.visible = true
		if b != null:
			b.disabled = false
			b.text = "Take"
			b.icon = null

		var map_d: Dictionary = _view_map[i] as Dictionary
		var t: String = String(map_d.get("type", ""))

		if t == "gold":
			if label != null:
				label.text = "Gold: %s" % _format_money_bronze(gold)
			if b != null:
				b.text = "Take"
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
				label.text = "%s x%d" % [item_name, count]
			if b != null:
				b.icon = icon_tex


func _get_icon(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _icon_cache.has(path):
		return _icon_cache[path] as Texture2D
	var tex: Texture2D = null
	var res: Resource = load(path)
	if res is Texture2D:
		tex = res as Texture2D

	# Scale icons down to fit the 60x50 "Take" button area.
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

func _on_slot_hover(view_index: int) -> void:
	_show_tooltip_for_view(view_index)


func _show_tooltip_for_view(view_index: int) -> void:
	if _corpse == null or not is_instance_valid(_corpse):
		_hide_tooltip()
		return
	if view_index < 0 or view_index >= _view_map.size():
		_hide_tooltip()
		return

	var m: Dictionary = _view_map[view_index] as Dictionary
	var t: String = String(m.get("type", ""))

	var text_out: String = ""
	if t == "gold":
		var corpse_typed := _as_corpse(_corpse)
		var gold_amount: int = corpse_typed.loot_gold if corpse_typed != null else (int(_corpse.get("loot_gold")) if ("loot_gold" in _corpse) else 0)
		text_out = "Gold\n" + _format_money_bronze(gold_amount)
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

	# Update tooltip text in a way that fully resets internal state.
	# Setting .text alone can keep previous scroll offset in some Godot versions.
	if tooltip_text.has_method("clear"):
		tooltip_text.call("clear")
	# Also clear plain text field to fully reset internal state.
	tooltip_text.text = ""
	if tooltip_text.has_method("add_text"):
		tooltip_text.call("add_text", text_out)
	else:
		tooltip_text.text = text_out

	tooltip_panel.visible = true
	# Defer layout + scroll reset to the next frame so the control has updated its content
	# (prevents "text walks upward" across repeated hovers).
	call_deferred("_apply_tooltip_layout")


func _hide_tooltip() -> void:
	tooltip_panel.visible = false
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
	var label_size: Vector2 = tooltip_text.get_combined_minimum_size()
	var height: float = max(32.0, float(label_size.y) + 16.0)
	tooltip_panel.size = Vector2(width, height)

	_position_tooltip_beside_panel()

func _reset_tooltip_scroll() -> void:
	# Label tooltip has no scroll.
	pass

func _position_tooltip_beside_panel() -> void:
	# Tooltip is anchored to the loot window: to the right with a small gap,
	# aligned by the top edge. Tooltip is allowed to go off-screen.
	if not tooltip_panel.visible:
		return
	var pr := panel.get_global_rect()
	var gap := 8.0
	var pos := pr.position + Vector2(pr.size.x + gap, 0.0)
	tooltip_panel.global_position = pos


func _build_item_tooltip_text(item: Dictionary) -> String:
	if item.is_empty():
		return "Unknown item"

	var lines: Array[String] = []
	lines.append(String(item.get("name", "Item")))

	var t: String = String(item.get("type", ""))
	var r: String = String(item.get("rarity", ""))
	var rl: int = int(item.get("required_level", 1))
	if t != "":
		lines.append("Type: " + t + ("  (" + r + ")" if r != "" else ""))
	lines.append("Required level: " + str(rl))

	# Base gear stats (armor/weapon)
	if t == "armor":
		var a: Variant = item.get("armor", {})
		if a is Dictionary and not (a as Dictionary).is_empty():
			var ad: Dictionary = a as Dictionary
			lines.append("")
			lines.append("Armor:")
			if ad.has("slot"):
				lines.append("  Slot: " + str(ad.get("slot")))
			if ad.has("class"):
				lines.append("  Class: " + str(ad.get("class")))
			var pa: int = int(ad.get("physical_armor", 0))
			var ma: int = int(ad.get("magic_armor", 0))
			if pa != 0:
				lines.append("  Physical armor: " + str(pa))
			if ma != 0:
				lines.append("  Magic armor: " + str(ma))
	elif t == "weapon":
		var w: Variant = item.get("weapon", {})
		if w is Dictionary and not (w as Dictionary).is_empty():
			var wd: Dictionary = w as Dictionary
			lines.append("")
			lines.append("Weapon:")
			if wd.has("subtype"):
				lines.append("  Type: " + str(wd.get("subtype")))
			var dmg: int = int(wd.get("damage", 0))
			var interval: float = float(wd.get("attack_interval", 1.0))
			var handed: int = int(wd.get("handed", 1))
			if dmg != 0:
				lines.append("  Damage: " + str(dmg))
			if interval > 0.0:
				lines.append("  Speed: " + str(snapped(interval, 0.01)) + "s")
				var dps: float = float(dmg) / interval if dmg > 0 else 0.0
				if dps > 0.0:
					lines.append("  DPS: " + str(snapped(dps, 0.1)))
			lines.append("  Hands: " + ("2H" if handed >= 2 else "1H"))

	# Equipment stats
	var stats: Variant = item.get("stats_modifiers", {})
	if stats is Dictionary and not (stats as Dictionary).is_empty():
		lines.append("")
		lines.append("Stats:")
		var sd: Dictionary = stats as Dictionary
		# Support both nested schema (primary/derived) and flat key:value schema.
		if sd.has("primary") or sd.has("derived"):
			var prim: Variant = sd.get("primary", {})
			if prim is Dictionary:
				for k in (prim as Dictionary).keys():
					lines.append("  " + str(k) + ": " + str(int((prim as Dictionary)[k])))
			var der: Variant = sd.get("derived", {})
			if der is Dictionary:
				for k in (der as Dictionary).keys():
					lines.append("  " + str(k) + ": " + str(int((der as Dictionary)[k])))
		else:
			for k in sd.keys():
				lines.append("  " + str(k) + ": " + str(sd[k]))

	# Consumable effects
	var cons: Variant = item.get("consumable", {})
	if cons is Dictionary and not (cons as Dictionary).is_empty():
		lines.append("")
		lines.append("Effects:")
		for k in (cons as Dictionary).keys():
			lines.append("  " + str(k) + ": " + str((cons as Dictionary)[k]))

	# Value
	var price: int = int(item.get("vendor_price_bronze", 0))
	lines.append("")
	lines.append("Value: " + _format_money_bronze(price))

	return "\n".join(lines)


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
