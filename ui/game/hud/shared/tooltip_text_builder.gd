extends RefCounted
class_name TooltipTextBuilder

const PROG := preload("res://core/stats/progression.gd")

static func rarity_color_hex(rarity: String, typ: String) -> String:
	var r := rarity.to_lower()
	if r == "" and typ == "junk":
		r = "junk"
	match r:
		"junk":
			return "#8a8a8a"
		"common":
			return "#ffffff"
		"uncommon":
			return "#4ce06a"
		"rare":
			return "#4ca6e0"
		"epic":
			return "#d94cff"
		"legendary":
			return "#ffb84c"
		_:
			return "#ffffff"

static func format_money_bbcode(bronze_total: int) -> String:
	var total : int = max(0, int(bronze_total))
	var gold : int = int(total / 10000)
	var silver : int = int((total % 10000) / 100)
	var bronze : int = int(total % 100)

	var parts: Array[String] = []
	if gold > 0:
		parts.append(_money_part(gold, TranslationServer.translate("ui.common.currency.gold.short").format({"value": gold}), "#d7b25b"))
	if silver > 0:
		parts.append(_money_part(silver, TranslationServer.translate("ui.common.currency.silver.short").format({"value": silver}), "#c0c0c0"))
	parts.append(_money_part(bronze, TranslationServer.translate("ui.common.currency.bronze.short").format({"value": bronze}), "#c26b2b"))

	return "[outline_size=1][outline_color=#000000]%s[/outline_color][/outline_size]" % " ".join(parts)

static func _money_part(_value: int, text: String, color: String) -> String:
	return "[color=%s]%s[/color]" % [color, text]

static func build_item_tooltip(meta: Dictionary, count: int, player: Node) -> String:
	if meta.is_empty():
		return ""

	var item_name: String = String(meta.get("name", TranslationServer.translate("ui.tooltip.item_fallback")))
	var typ: String = String(meta.get("type", ""))
	var rarity: String = String(meta.get("rarity", ""))
	var req_lvl: int = int(meta.get("required_level", meta.get("item_level", 0)))
	var rarity_col: String = rarity_color_hex(rarity, typ)

	var lines: Array[String] = []
	var name_part := "[color=%s][b]%s[/b][/color]" % [rarity_col, item_name]
	lines.append(name_part + (" x%d" % count if count > 1 else ""))
	if rarity != "" and typ.to_lower() != "junk":
		lines.append(TranslationServer.translate("ui.tooltip.rarity").format({"value": "[color=%s]%s[/color]" % [rarity_col, rarity]}))

	var slot_name := _slot_label(meta, typ)
	if slot_name != "":
		lines.append(TranslationServer.translate("ui.tooltip.slot").format({"value": slot_name}))

	var show_req: bool = typ in ["weapon", "armor", "bag", "food", "drink", "potion", "accessory", "offhand", "shield"]
	var req_line := ""
	if show_req and req_lvl > 0:
		var p_lvl: int = 0
		if player != null and is_instance_valid(player) and ("level" in player):
			p_lvl = int(player.level)
		var lvl_line := TranslationServer.translate("ui.tooltip.required_level").format({"level": req_lvl})
		if p_lvl > 0 and p_lvl < req_lvl:
			lvl_line = "[color=#ff5555]%s[/color]" % lvl_line
		req_line = lvl_line

	if typ == "weapon" and meta.get("weapon") is Dictionary:
		var w: Dictionary = meta.get("weapon") as Dictionary
		var subtype := String(w.get("subtype", ""))
		if subtype != "":
			var subtype_label := _humanize_slot(subtype)
			var subtype_line := TranslationServer.translate("ui.tooltip.subtype").format({"value": subtype_label})
			if player != null and is_instance_valid(player) and ("class_id" in player):
				var allowed_types := PROG.get_allowed_weapon_types_for_class(String(player.class_id))
				if not allowed_types.has(subtype):
					subtype_line = TranslationServer.translate("ui.tooltip.subtype").format({"value": "[color=#ff5555]%s[/color]" % subtype_label})
			lines.append(subtype_line)

	if meta.has("armor") and meta.get("armor") is Dictionary:
		var a: Dictionary = meta.get("armor") as Dictionary
		var pa: int = int(a.get("physical_armor", 0))
		var ma: int = int(a.get("magic_armor", 0))
		var armor_class := String(a.get("class", "")).to_lower()
		if armor_class != "":
			var material_line := TranslationServer.translate("ui.tooltip.material").format({"value": armor_class})
			if player != null and is_instance_valid(player) and ("class_id" in player):
				var allowed := PROG.get_allowed_armor_classes_for_class(String(player.class_id))
				if armor_class != "" and not allowed.has(armor_class):
					material_line = "[color=#ff5555]%s[/color]" % material_line
			lines.append(material_line)
		var defense_line := _format_defense_line(pa, ma)
		if defense_line != "":
			lines.append(defense_line)
	if meta.has("offhand") and meta.get("offhand") is Dictionary:
		var oh: Dictionary = meta.get("offhand") as Dictionary
		var oh_pa: int = int(oh.get("physical_armor", 0))
		var oh_ma: int = int(oh.get("magic_armor", 0))
		var oh_defense_line := _format_defense_line(oh_pa, oh_ma)
		if oh_defense_line != "":
			lines.append(oh_defense_line)
	if meta.has("weapon") and meta.get("weapon") is Dictionary:
		var w: Dictionary = meta.get("weapon") as Dictionary
		var dmg: int = int(w.get("damage", 0))
		var spd: float = float(w.get("attack_interval", 1.0))
		lines.append(TranslationServer.translate("ui.tooltip.damage_speed").format({"damage": dmg, "speed": "%.2f" % spd}))
		if spd > 0.0:
			lines.append(TranslationServer.translate("ui.tooltip.dps").format({"value": "%.1f" % (float(dmg) / spd)}))

	if meta.has("stats_modifiers") and meta.get("stats_modifiers") is Dictionary:
		var sm: Dictionary = meta.get("stats_modifiers") as Dictionary
		for k in sm.keys():
			lines.append("%s: %+d" % [String(k), int(sm[k])])

	if meta.has("consumable") and meta.get("consumable") is Dictionary:
		var c: Dictionary = meta.get("consumable") as Dictionary
		if not c.is_empty():
			lines.append("")
			lines.append(TranslationServer.translate("ui.tooltip.effects"))
			for el in _format_consumable_effects(c):
				lines.append("  " + el)
			var cd_total := _get_consumable_cd_total(meta)
			if cd_total > 0.0:
				var cd_line := TranslationServer.translate("ui.tooltip.cooldown").format({"seconds": int(cd_total)})
				if player != null and player.has_method("get_consumable_cooldown_left"):
					var kind := _get_consumable_cd_kind(meta)
					var left := float(player.call("get_consumable_cooldown_left", kind))
					if left > 0.01:
						cd_line = TranslationServer.translate("ui.tooltip.cooldown_left").format({"seconds": int(cd_total), "left": "%.1f" % left})
				lines.append(cd_line)

	if req_line != "":
		lines.append(req_line)
	var price: int = int(meta.get("vendor_price_bronze", 0))
	if price > 0:
		lines.append(TranslationServer.translate("ui.tooltip.price").format({"value": format_money_bbcode(price)}))

	return "\n".join(lines)

static func _slot_label(meta: Dictionary, typ: String) -> String:
	match typ:
		"armor":
			if meta.get("armor") is Dictionary:
				return _humanize_slot(String((meta.get("armor") as Dictionary).get("slot", "")))
		"accessory":
			if meta.get("accessory") is Dictionary:
				return _humanize_slot(String((meta.get("accessory") as Dictionary).get("slot", "")))
		"shield":
			if meta.get("shield") is Dictionary:
				return _humanize_slot(String((meta.get("shield") as Dictionary).get("slot", "")))
		"offhand":
			if meta.get("offhand") is Dictionary:
				return _humanize_slot(String((meta.get("offhand") as Dictionary).get("slot", "")))
		"weapon":
			return "weapon"
	return ""

static func _humanize_slot(slot_id: String) -> String:
	if slot_id == "":
		return ""
	return slot_id.replace("_", " ")

static func _format_defense_line(physical: int, magic: int) -> String:
	var parts: Array[String] = []
	if physical > 0:
		parts.append(TranslationServer.translate("ui.tooltip.physical_defense").format({"value": physical}))
	if magic > 0:
		parts.append(TranslationServer.translate("ui.tooltip.magic_defense").format({"value": magic}))
	return "  ".join(parts)

static func _format_consumable_effects(consumable: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var instant: bool = bool(consumable.get("instant", false))
	var duration_sec: float = float(consumable.get("duration_sec", 0.0))

	var hp_total: int = int(consumable.get("hp_total", consumable.get("hp", 0)))
	var mp_total: int = int(consumable.get("mp_total", consumable.get("mp", 0)))
	if hp_total > 0:
		lines.append(TranslationServer.translate("ui.tooltip.hp_plus").format({"value": hp_total}))
	if mp_total > 0:
		lines.append(TranslationServer.translate("ui.tooltip.mana_plus").format({"value": mp_total}))
	if not instant and duration_sec > 0.0:
		lines.append(TranslationServer.translate("ui.tooltip.over_seconds").format({"seconds": "%.0f" % duration_sec}))

	return lines

static func _get_consumable_cd_kind(meta: Dictionary) -> String:
	var typ: String = String(meta.get("type", "")).to_lower()
	if typ == "potion":
		return "potion"
	if typ == "food" or typ == "drink":
		return "fooddrink"
	return ""

static func _get_consumable_cd_total(meta: Dictionary) -> float:
	var kind := _get_consumable_cd_kind(meta)
	if kind == "potion":
		return 5.0
	if kind == "fooddrink":
		return 10.0
	return 0.0
