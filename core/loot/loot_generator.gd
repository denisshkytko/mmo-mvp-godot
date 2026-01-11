extends RefCounted

class_name LootGenerator

## Procedural loot generator that pulls items from DataDB (items DB) using
## simple filter rules (LootProfile). This is meant to replace hand-built
## per-mob loot tables later, while staying Inspector-friendly.

## Returned format matches Corpse/LootHUD (v2):
## { "gold": int, "slots": [ {"type":"item","id":String,"count":int}, ... ] }

## Internal cached index (built lazily once per run)
static var _indexed: bool = false
static var _items_by_type: Dictionary = {}
static var _items_by_rarity: Dictionary = {}
static var _items_all: Array = []


static func generate(profile: LootProfile, level: int, context: Dictionary = {}) -> Dictionary:
	_ensure_index()

	var out: Dictionary = {"gold": 0, "slots": []}
	if profile == null:
		return out

	var max_total: int = max(int(profile.max_total_slots), 0)
	var duplicate_cap: int = max(int(profile.max_duplicate_per_item), 1)
	var picked_counts: Dictionary = {}

	# Special modes
	match profile.mode:
		LootProfile.Mode.FACTION_NPC_GOLD_ONLY:
			_generate_faction_gold_only(profile, level, out)
			return out
		LootProfile.Mode.NEUTRAL_ANIMAL:
			_generate_neutral_animal(profile, level, out, context, max_total, duplicate_cap, picked_counts)
			return out
		LootProfile.Mode.NEUTRAL_HUMANOID:
			_generate_neutral_humanoid(profile, level, out, context, max_total, duplicate_cap, picked_counts)
			return out
		_:
			pass

	# Default "aggressive" mode
	var gold_slot_used := false
	if profile.gold_enabled and max_total > 0 and randf() <= profile.gold_chance:
		out["gold"] = _roll_gold(profile, level)
		if out["gold"] > 0:
			gold_slot_used = true
			max_total -= 1

	# Junk
	if profile.junk_enabled and max_total > 0:
		_add_stackable_category(out, picked_counts, duplicate_cap, max_total, "junk", profile.junk_band, level,
			profile.junk_min_slots, profile.junk_max_slots, profile.junk_extra_slot_chance,
			profile.junk_stack_min, profile.junk_stack_max)

	# Materials (optional)
	if profile.materials_enabled and max_total > 0:
		_add_stackable_category(out, picked_counts, duplicate_cap, max_total, "material", profile.materials_band, level,
			profile.materials_min_slots, profile.materials_max_slots, profile.materials_extra_slot_chance,
			profile.materials_stack_min, profile.materials_stack_max)

	# Consumables
	if profile.consumables_enabled and max_total > 0:
		_add_consumables(out, picked_counts, duplicate_cap, max_total, profile.consumables_band, level,
			profile.consumables_min_slots, profile.consumables_max_slots, profile.consumables_extra_slot_chance,
			profile.consumables_stack_min, profile.consumables_stack_max)

	# Bags (rare)
	if profile.bags_enabled and max_total > 0 and randf() <= profile.bags_chance:
		_add_bag(out, picked_counts, duplicate_cap, max_total, profile.bags_band, level)

	# Equipment
	if profile.equipment_enabled and max_total > 0:
		_add_equipment(out, picked_counts, duplicate_cap, max_total, profile, level)

	return out


static func _generate_faction_gold_only(profile: LootProfile, level: int, out: Dictionary) -> void:
	# 25–33% chance to be empty; only gold otherwise.
	var empty_chance: float = clamp(1.0 - profile.gold_chance as float, 0.0, 1.0)
	if randf() <= empty_chance:
		out["gold"] = 0
		return
	out["gold"] = _roll_gold(profile, level)


static func _generate_neutral_animal(profile: LootProfile, level: int, out: Dictionary, context: Dictionary, max_total: int, duplicate_cap: int, picked_counts: Dictionary) -> void:
	# Only animal materials, always at least 1 slot.
	var body_size := str(context.get("body_size", "small"))
	var slots_budget := max_total
	if profile.gold_enabled and slots_budget > 0 and randf() <= profile.gold_chance:
		out["gold"] = _roll_gold(profile, level)
		if out["gold"] > 0:
			slots_budget -= 1

	# Decide how many material slots
	var slots := _roll_slots(profile.materials_min_slots, profile.materials_max_slots, profile.materials_extra_slot_chance)
	slots = max(slots, 1)
	slots = min(slots, slots_budget)

	# Stack size scaling by body size
	var stack_min := profile.materials_stack_min
	var stack_max := profile.materials_stack_max
	match body_size:
		"small":
			stack_min = max(stack_min, 1)
			stack_max = max(stack_max, 2)
		"medium":
			stack_min = max(stack_min, 2)
			stack_max = max(stack_max, 3)
		"large":
			stack_min = max(stack_min, 3)
			stack_max = max(stack_max, 4)
		_:
			pass

	_add_materials_filtered(out, picked_counts, duplicate_cap, slots, profile.materials_band, level, body_size, stack_min, stack_max)


static func _generate_neutral_humanoid(profile: LootProfile, level: int, out: Dictionary, _context: Dictionary, max_total: int, duplicate_cap: int, picked_counts: Dictionary) -> void:
	# Junk + gold, can be empty.
	var slots_budget := max_total
	# First generate junk slots; if none => no gold.
	var junk_slots := _roll_slots(profile.junk_min_slots, profile.junk_max_slots, profile.junk_extra_slot_chance)
	junk_slots = min(junk_slots, slots_budget)
	if junk_slots > 0:
		_add_stackable_category(out, picked_counts, duplicate_cap, slots_budget, "junk", profile.junk_band, level,
			junk_slots, junk_slots, 0.0, profile.junk_stack_min, profile.junk_stack_max)
		# Recompute remaining budget after additions
		slots_budget = max_total - int(out["slots"].size())
		if profile.gold_enabled and slots_budget > 0 and randf() <= profile.gold_chance:
			out["gold"] = _roll_gold(profile, level)
			if out["gold"] > 0:
				slots_budget -= 1
	else:
		out["gold"] = 0


static func _roll_gold(profile: LootProfile, level: int) -> int:
	var lvl: int = max(level, 1)

	var g_min: int = int(profile.gold_min_base + profile.gold_min_per_level * lvl)
	var g_max: int = int(profile.gold_max_base + profile.gold_max_per_level * lvl)

	if g_max < g_min:
		g_max = g_min

	return randi_range(g_min, g_max)


static func _roll_slots(min_slots: int, max_slots: int, extra_chance: float) -> int:
	var min_s : int = max(min_slots, 0)
	var max_s : int = max(max_slots, min_s)
	var slots := min_s
	for i in range(min_s, max_s):
		if randf() <= extra_chance:
			slots += 1
	return slots


static func _add_stackable_category(out: Dictionary, picked_counts: Dictionary, duplicate_cap: int, slots_budget: int, item_type: String, band: int, level: int,
		min_slots: int, max_slots: int, extra_slot_chance: float, stack_min: int, stack_max: int) -> void:
	if slots_budget <= 0:
		return
	var slots := _roll_slots(min_slots, max_slots, extra_slot_chance)
	slots = min(slots, slots_budget)
	if slots <= 0:
		return

	var tag := LootProfile.band_to_tag(band, level)
	var pool: Array = _items_by_type.get(item_type, [])
	var candidates: Array = []
	for it in pool:
		var tags: Array = it.get("tags", [])
		if tag in tags:
			candidates.append(it)
	if candidates.is_empty():
		return

	for _i in range(slots):
		var picked := _pick_item(candidates, picked_counts, duplicate_cap)
		if picked == null:
			break
		var q := randi_range(max(stack_min, 1), max(stack_max, max(stack_min, 1)))
		out["slots"].append({"type": "item", "id": picked.get("id", ""), "count": q})


static func _add_materials_filtered(out: Dictionary, picked_counts: Dictionary, duplicate_cap: int, slots: int, band: int, level: int, body_size: String, stack_min: int, stack_max: int) -> void:
	if slots <= 0:
		return
	var tag := LootProfile.band_to_tag(band, level)
	var pool: Array = _items_by_type.get("material", [])
	var candidates: Array = []
	for it in pool:
		var tags: Array = it.get("tags", [])
		if tag in tags and body_size in tags:
			candidates.append(it)
	if candidates.is_empty():
		# Fallback: ignore size tag if DB doesn't have it for some range
		for it in pool:
			var tags2: Array = it.get("tags", [])
			if tag in tags2:
				candidates.append(it)
	if candidates.is_empty():
		return

	for _i in range(slots):
		var picked := _pick_item(candidates, picked_counts, duplicate_cap)
		if picked == null:
			break
		var q := randi_range(max(stack_min, 1), max(stack_max, max(stack_min, 1)))
		out["slots"].append({"type": "item", "id": picked.get("id", ""), "count": q})


static func _add_consumables(out: Dictionary, picked_counts: Dictionary, duplicate_cap: int, slots_budget: int, band: int, level: int,
		min_slots: int, max_slots: int, extra_slot_chance: float, stack_min: int, stack_max: int) -> void:
	if slots_budget <= 0:
		return
	var slots := _roll_slots(min_slots, max_slots, extra_slot_chance)
	slots = min(slots, slots_budget)
	if slots <= 0:
		return

	var req_range := LootProfile.band_to_req_level_range(band, level)
	var pool: Array = []
	for t in ["food", "drink", "potion"]:
		pool += _items_by_type.get(t, [])
	var candidates: Array = []
	for it in pool:
		var req := int(it.get("required_level", 1))
		if req >= req_range.x and req <= req_range.y:
			candidates.append(it)
	if candidates.is_empty():
		return

	for _i in range(slots):
		var picked := _pick_item(candidates, picked_counts, duplicate_cap)
		if picked == null:
			break
		var q := randi_range(max(stack_min, 1), max(stack_max, max(stack_min, 1)))
		out["slots"].append({"type": "item", "id": picked.get("id", ""), "count": q})


static func _add_bag(out: Dictionary, picked_counts: Dictionary, duplicate_cap: int, slots_budget: int, band: int, level: int) -> void:
	if slots_budget <= 0:
		return
	var req_range := LootProfile.band_to_req_level_range(band, level)
	var pool: Array = _items_by_type.get("bag", [])
	var candidates: Array = []
	for it in pool:
		var req := int(it.get("required_level", 1))
		if req >= req_range.x and req <= req_range.y:
			candidates.append(it)
	if candidates.is_empty():
		return
	var picked := _pick_item(candidates, picked_counts, duplicate_cap)
	if picked == null:
		return
	out["slots"].append({"type": "item", "id": picked.get("id", ""), "count": 1})


static func _add_equipment(out: Dictionary, picked_counts: Dictionary, duplicate_cap: int, slots_budget: int, profile: LootProfile, level: int) -> void:
	if slots_budget <= 0:
		return
	var slots := _roll_slots(profile.equipment_min_slots, profile.equipment_max_slots, profile.equipment_extra_slot_chance)
	slots = min(slots, slots_budget)
	if slots <= 0:
		return

	# Required-level range
	var min_req := LootProfile.band_to_req_level_range(profile.equipment_min_req_band, level).x
	var max_req := LootProfile.band_to_req_level_range(profile.equipment_max_req_band, level).y
	if max_req < min_req:
		max_req = min_req

	# Dynamic rarity clamp by level
	var allow_rare := level >= 20
	var allow_epic := level >= 40
	var allow_legendary := level >= 60

	var weights := {
		"common": float(profile.w_common),
		"uncommon": float(profile.w_uncommon),
		"rare": float(profile.w_rare),
		"epic": float(profile.w_epic),
		"legendary": float(profile.w_legendary),
	}
	if not allow_rare:
		weights["rare"] = 0.0
	if not allow_epic:
		weights["epic"] = 0.0
	if not allow_legendary:
		weights["legendary"] = 0.0

	for _i in range(slots):
		var rarity := _weighted_choice(weights)
		var candidates: Array = _equipment_candidates(rarity, min_req, max_req)
		if candidates.is_empty():
			# fallback: try lower rarity
			for fb in ["uncommon", "common"]:
				candidates = _equipment_candidates(fb, min_req, max_req)
				if not candidates.is_empty():
					rarity = fb
					break
		if candidates.is_empty():
			break
		var picked := _pick_item(candidates, picked_counts, duplicate_cap)
		if picked == null:
			break
		out["slots"].append({"type": "item", "id": picked.get("id", ""), "count": 1})


static func _equipment_candidates(rarity: String, min_req: int, max_req: int) -> Array:
	var pools: Array = []
	# Armor/weapon/accessory/offhand
	for t in ["armor", "weapon", "accessory", "offhand"]:
		pools += _items_by_type.get(t, [])
	var out: Array = []
	for it in pools:
		if it.get("rarity", "common") != rarity:
			continue
		var req := int(it.get("required_level", 1))
		if req >= min_req and req <= max_req:
			out.append(it)
	return out


static func _pick_item(candidates: Array, picked_counts: Dictionary, duplicate_cap: int) -> Dictionary:
	if candidates.is_empty():
		return {}

	# Try a few times to respect duplicate cap
	for _k in range(12):
		var it: Dictionary = candidates[randi_range(0, candidates.size() - 1)] as Dictionary
		var id: String = str(it.get("id", ""))
		if id.is_empty():
			continue

		var c: int = int(picked_counts.get(id, 0))
		if c >= duplicate_cap:
			continue

		picked_counts[id] = c + 1
		return it

	return {}


static func _weighted_choice(weights: Dictionary) -> String:
	var total := 0.0
	for k in weights.keys():
		total += float(weights[k])
	if total <= 0.0:
		return "common"
	var r := randf() * total
	var acc := 0.0
	for k in weights.keys():
		acc += float(weights[k])
		if r <= acc:
			return str(k)
	return "common"


static func _ensure_index() -> void:
	if _indexed:
		return
	_indexed = true
	_items_by_type.clear()
	_items_by_rarity.clear()
	_items_all.clear()

	# DataDB is an autoload singleton
	var db := DataDB
	var dict := db.items
	for id in dict.keys():
		var it: Dictionary = dict[id]
		if not it.has("id"):
			it["id"] = str(id)
		_items_all.append(it)
		var t := str(it.get("type", ""))
		if not _items_by_type.has(t):
			_items_by_type[t] = []
		_items_by_type[t].append(it)
		var r := str(it.get("rarity", "common"))
		if not _items_by_rarity.has(r):
			_items_by_rarity[r] = []
		_items_by_rarity[r].append(it)

	# Synthetic pools
	_items_by_type["consumable"] = []
	_items_by_type["consumable"].append_array(_items_by_type.get("food", []))
	_items_by_type["consumable"].append_array(_items_by_type.get("drink", []))
	_items_by_type["consumable"].append_array(_items_by_type.get("potion", []))

	_items_by_type["equipment"] = []
	_items_by_type["equipment"].append_array(_items_by_type.get("armor", []))
	_items_by_type["equipment"].append_array(_items_by_type.get("weapon", []))
	_items_by_type["equipment"].append_array(_items_by_type.get("accessory", []))
	_items_by_type["equipment"].append_array(_items_by_type.get("offhand", []))
