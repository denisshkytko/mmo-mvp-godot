extends Resource

class_name LootProfile

## LootProfile is a "filter preset" for procedural loot generation.
## It is meant to be configured from the Inspector (SpawnerGroups) and
## keeps the generation rules readable and consistent.

enum Mode {
	AGGRESSIVE,
	NEUTRAL_ANIMAL,
	NEUTRAL_HUMANOID,
	FACTION_NPC_GOLD_ONLY,
}

enum LevelBand {
	AUTO_BY_LEVEL,
	B01_09,
	B10_19,
	B20_29,
	B30_39,
	B40_49,
	B50_59,
	B60,
}

@export var mode: Mode = Mode.AGGRESSIVE

@export_group("Gold")
@export var gold_enabled: bool = true
@export_range(0.0, 1.0, 0.01) var gold_chance: float = 0.85
@export var gold_min_base: int = 0
@export var gold_min_per_level: int = 2
@export var gold_max_base: int = 3
@export var gold_max_per_level: int = 4

@export_group("Junk")
@export var junk_enabled: bool = true
@export var junk_band: LevelBand = LevelBand.AUTO_BY_LEVEL
@export var junk_min_slots: int = 0
@export var junk_max_slots: int = 2
@export_range(0.0, 1.0, 0.01) var junk_extra_slot_chance: float = 0.45
@export var junk_stack_min: int = 1
@export var junk_stack_max: int = 2

@export_group("Materials")
@export var materials_enabled: bool = false
@export var materials_band: LevelBand = LevelBand.AUTO_BY_LEVEL
@export var materials_min_slots: int = 1
@export var materials_max_slots: int = 2
@export_range(0.0, 1.0, 0.01) var materials_extra_slot_chance: float = 0.35
@export var materials_stack_min: int = 1
@export var materials_stack_max: int = 2

@export_group("Consumables")
@export var consumables_enabled: bool = true
@export var consumables_band: LevelBand = LevelBand.AUTO_BY_LEVEL
@export var consumables_min_slots: int = 0
@export var consumables_max_slots: int = 1
@export_range(0.0, 1.0, 0.01) var consumables_extra_slot_chance: float = 0.25
@export var consumables_stack_min: int = 1
@export var consumables_stack_max: int = 3

@export_group("Bags")
@export var bags_enabled: bool = true
@export var bags_band: LevelBand = LevelBand.AUTO_BY_LEVEL
@export_range(0.0, 1.0, 0.001) var bags_chance: float = 0.015

@export_group("Equipment")
@export var equipment_enabled: bool = true
@export var equipment_min_req_band: LevelBand = LevelBand.AUTO_BY_LEVEL
@export var equipment_max_req_band: LevelBand = LevelBand.AUTO_BY_LEVEL
@export var equipment_min_slots: int = 0
@export var equipment_max_slots: int = 1
@export_range(0.0, 1.0, 0.01) var equipment_extra_slot_chance: float = 0.15

@export_subgroup("Rarity Weights")
@export_range(0.0, 10.0, 0.01) var w_common: float = 1.0
@export_range(0.0, 10.0, 0.01) var w_uncommon: float = 0.55
@export_range(0.0, 10.0, 0.01) var w_rare: float = 0.18
@export_range(0.0, 10.0, 0.01) var w_epic: float = 0.06
@export_range(0.0, 10.0, 0.01) var w_legendary: float = 0.01

@export_group("Global")
@export var max_duplicate_per_item: int = 2
@export var max_total_slots: int = 6


static func band_to_tag(band: int, level: int) -> String:
	var b := band
	if b == LevelBand.AUTO_BY_LEVEL:
		b = band_from_level(level)
	match b:
		LevelBand.B01_09: return "01_09"
		LevelBand.B10_19: return "10_19"
		LevelBand.B20_29: return "20_29"
		LevelBand.B30_39: return "30_39"
		LevelBand.B40_49: return "40_49"
		LevelBand.B50_59: return "50_59"
		LevelBand.B60: return "60"
		_: return "01_09"


static func band_from_level(level: int) -> int:
	if level <= 9:
		return LevelBand.B01_09
	if level <= 19:
		return LevelBand.B10_19
	if level <= 29:
		return LevelBand.B20_29
	if level <= 39:
		return LevelBand.B30_39
	if level <= 49:
		return LevelBand.B40_49
	if level <= 59:
		return LevelBand.B50_59
	return LevelBand.B60


static func band_to_req_level_range(band: int, level: int) -> Vector2i:
	var b := band
	if b == LevelBand.AUTO_BY_LEVEL:
		b = band_from_level(level)
	match b:
		LevelBand.B01_09: return Vector2i(1, 9)
		LevelBand.B10_19: return Vector2i(10, 19)
		LevelBand.B20_29: return Vector2i(20, 29)
		LevelBand.B30_39: return Vector2i(30, 39)
		LevelBand.B40_49: return Vector2i(40, 49)
		LevelBand.B50_59: return Vector2i(50, 59)
		LevelBand.B60: return Vector2i(60, 60)
		_: return Vector2i(1, 9)
