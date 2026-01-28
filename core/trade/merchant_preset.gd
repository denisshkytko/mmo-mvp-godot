extends Resource
class_name MerchantPreset

@export var title: String = ""
@export var items: Array[MerchantItemEntry] = []

func get_entries() -> Array[MerchantItemEntry]:
	return items
