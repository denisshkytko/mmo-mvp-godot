extends RefCounted
class_name StatConstants

# ------------------------------------------------------------
# Stage 1 (Player) — MMO-style "rating" system.
#
# Rules (as requested):
# - Only PRIMARY stats grow directly with level: STR/AGI/END/INT/PER.
# - All secondary stats have base value 0 and are derived from:
#     primary_at_level + gear_mods + buff_mods (+ percent buffs)
# - SpeedRating is a pure secondary: only from gear/buffs.
#
# These numbers are an initial balance pass. They are centralized here
# so we can tune them without touching gameplay code.
# ------------------------------------------------------------

# --- Primary -> base pools (no per-level pool growth here) ---
const HP_PER_END: float = 20.0
const HP_PER_STR: float = 0.0

const MANA_PER_INT: float = 6.0

# --- Primary -> regen (per second, can be fractional) ---
const HP_REGEN_PER_END: float = 0.03
const HP_REGEN_PER_STR: float = 0.0

const MANA_REGEN_PER_INT: float = 0.04

# --- Primary -> powers (units) ---
const AP_FROM_STR: float = 0.5
const AP_FROM_AGI: float = 0.15

const SP_FROM_INT: float = 2.2

# How much AttackPower translates into raw physical damage.
const AP_DAMAGE_SCALAR: float = 0.35

# How much SpellPower translates into raw spell damage / healing.
const SP_DAMAGE_SCALAR: float = 0.40

# --- Primary -> defenses (units) ---
const DEF_FROM_STR: float = 0.2
const DEF_FROM_END: float = 0.7
const DEF_FROM_AGI: float = 0.0

const RES_FROM_END: float = 0.2
const RES_FROM_INT: float = 0.9

# Mitigation curve constant for converting Defense/Resist to %.
# reduction = 1 - K/(K + defense)
const MITIGATION_K: float = 150.0
const MAX_MITIGATION_PCT: float = 85.0

const OFFHAND_MULT: float = 0.75
const MOB_UNARMED_AP_MULT: float = 1.5

# --- Speed ratings ---
const AS_FROM_AGI: int = 10
const CS_FROM_INT: int = 10

const AS_FROM_SPEED: int = 1
const CS_FROM_SPEED: int = 1

const AS_RATING_PER_1PCT: float = 100.0
const CS_RATING_PER_1PCT: float = 120.0

# --- Cooldown reduction from SpeedRating ---
# Speed is a secondary stat coming only from gear/buffs.
# It also reduces skill cooldowns (MMO-style).
const COOLDOWN_RATING_PER_1PCT: float = 100.0

# --- Crit ratings ---
const BASE_CRIT_CHANCE_PCT: float = 10.0
const CRIT_FROM_PER: int = 7
const CRIT_FROM_AGI: int = 3
const CRIT_RATING_PER_1PCT: float = 100.0

# Crit damage:
# - base crit multiplier is x2.0
# - extra comes only from PER via rating -> multiplier
const CDMG_FROM_PER: int = 5
const CDMG_RATING_PER_0_01_MULT: float = 100.0  # 100 rating -> +0.01 multiplier
