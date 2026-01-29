extends RefCounted

enum MobVariant {
	NORMAL = 0,
	RARE = 1,
	ELITE = 2,
}

static func primary_mult(variant: int) -> float:
	match variant:
		MobVariant.RARE:
			return 2.0
		MobVariant.ELITE:
			return 3.5
		_:
			return 1.0

static func defense_mult(variant: int) -> float:
	match variant:
		MobVariant.RARE:
			return 1.5
		MobVariant.ELITE:
			return 2.0
		_:
			return 1.0

static func xp_mult(variant: int) -> float:
	match variant:
		MobVariant.RARE:
			return 1.5
		MobVariant.ELITE:
			return 2.0
		_:
			return 1.0

static func gold_mult(variant: int) -> float:
	match variant:
		MobVariant.RARE:
			return 2.0
		MobVariant.ELITE:
			return 3.5
		_:
			return 1.0

static func clamp_variant(variant: int) -> int:
	match variant:
		MobVariant.NORMAL, MobVariant.RARE, MobVariant.ELITE:
			return variant
		_:
			return MobVariant.NORMAL
