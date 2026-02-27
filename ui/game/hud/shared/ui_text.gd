extends RefCounted
class_name UIText

static func stack_count(count: int) -> String:
	return TranslationServer.translate("ui.common.stack_count").format({"count": int(max(0, count))})

static func item_with_stack(name: String, count: int) -> String:
	if int(count) <= 1:
		return name
	return TranslationServer.translate("ui.common.item_with_stack").format({
		"name": name,
		"stack": stack_count(count),
	})

static func class_display_name(class_id: String) -> String:
	var clean := String(class_id).strip_edges().to_lower()
	if clean == "":
		clean = "adventurer"
	var key := "ui.class.%s" % clean
	var translated := TranslationServer.translate(key)
	if translated == key:
		return TranslationServer.translate("ui.class.adventurer")
	return translated

static func faction_display_name(faction_id: String) -> String:
	var clean := String(faction_id).strip_edges().to_lower()
	if clean == "":
		clean = "blue"
	var key := "ui.faction.%s" % clean
	var translated := TranslationServer.translate(key)
	if translated == key:
		return TranslationServer.translate("ui.faction.blue")
	return translated
