extends Resource
class_name MerchantPreset

const TITLES: Array[String] = ["Товары для 1 уровня"]

@export_enum("Товары для 1 уровня") var preset_id: int = 0
@export var title: String = ""
@export var items: Array[MerchantItemEntry] = []

func get_entries() -> Array[MerchantItemEntry]:
	return items

func get_title() -> String:
	if title != "":
		return title
	if preset_id >= 0 and preset_id < TITLES.size():
		return TITLES[preset_id]
	return ""
