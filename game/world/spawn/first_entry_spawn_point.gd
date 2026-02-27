extends Marker2D
class_name FirstEntrySpawnPoint

@export_enum("Синяя", "Красная") var faction: String = "Синяя"

func get_faction_id() -> String:
	return "red" if faction == "Красная" else "blue"
