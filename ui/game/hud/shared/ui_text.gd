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
