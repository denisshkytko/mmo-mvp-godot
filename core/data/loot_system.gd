extends Node

const LootGenerator := preload("res://core/loot/loot_generator.gd")
const LootProfile := preload("res://core/loot/loot_profile.gd")

func generate_loot_from_profile(profile: Resource, mob_level: int, context: Dictionary = {}) -> Dictionary:
	# Profile is expected to be LootProfile, but we accept Resource to keep call-sites simple.
	var lp: LootProfile = profile as LootProfile
	if lp == null:
		push_warning("LootSystem.generate_loot_from_profile: passed profile is not LootProfile. Returning empty loot.")
		return {"gold": 0, "slots": []}

	return LootGenerator.generate(lp, mob_level, context)
