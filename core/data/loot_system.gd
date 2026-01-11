extends Node

## LootGenerator and LootProfile are registered as global classes (class_name).
## Avoid shadowing them with local constants to keep the project warning-free.

func generate_loot_from_profile(profile: Resource, mob_level: int, context: Dictionary = {}) -> Dictionary:
	# Profile is expected to be LootProfile, but we accept Resource to keep call-sites simple.
	var lp: LootProfile = profile as LootProfile
	if lp == null:
		push_warning("LootSystem.generate_loot_from_profile: passed profile is not LootProfile. Returning empty loot.")
		return {"gold": 0, "slots": []}

	return LootGenerator.generate(lp, mob_level, context)
