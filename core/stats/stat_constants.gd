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

const MANA_PER_INT: float = 15.0

# --- Primary -> regen (per second, can be fractional) ---
const HP_REGEN_PER_END: float = 0.1
const HP_REGEN_PER_STR: float = 0.0

const MANA_REGEN_PER_INT: float = 0.1

# --- Primary -> powers (units) ---
const AP_FROM_STR: float = 2.0
const AP_FROM_AGI: float = 1.0

const SP_FROM_INT: float = 1.0

# How much AttackPower translates into raw physical damage.
const AP_DAMAGE_SCALAR: float = 0.35

# How much SpellPower translates into raw spell damage / healing.
const SP_DAMAGE_SCALAR: float = 0.40

# --- Primary -> defenses (units) ---
const DEF_FROM_STR: float = 0.5
const DEF_FROM_END: float = 1.0
const DEF_FROM_AGI: float = 0.0

const RES_FROM_END: float = 0.5
const RES_FROM_INT: float = 1.0

# --- New defense ratings ---
const EVADE_FROM_AGI: float = 2.0
const EVADE_FROM_PER: float = 1.0
const BLOCK_CHANCE_FROM_STR: float = 2.0
const BLOCK_CHANCE_FROM_PER: float = 1.0
const BLOCK_VALUE_FROM_STR: float = 1.0

# Mitigation curve constant for converting Defense/Resist to %.
const MITIGATION_K: float = 100.0
const MAX_MITIGATION_PCT: float = 85.0

const OFFHAND_MULT: float = 0.75
const MOB_UNARMED_AP_MULT: float = 1.5

# --- Speed ratings ---
const AS_FROM_AGI: float = 2.0
const CS_FROM_INT: float = 1.0

const AS_FROM_SPEED: int = 1
const CS_FROM_SPEED: int = 1

const HASTE_AS_K: float = 80.0
const HASTE_CS_K: float = 80.0

# --- Cooldown reduction from SpeedRating ---
# Speed is a secondary stat coming only from gear/buffs.
# It also reduces skill cooldowns (MMO-style).
const HASTE_CDR_K: float = 150.0

# --- Crit ratings ---
const BASE_CRIT_CHANCE_PCT: float = 0.0
const CRIT_FROM_PER: float = 1.5
const CRIT_FROM_AGI: float = 1.0
const CRIT_K: float = 60.0

# Crit damage:
# - base crit multiplier is x1.5
# - bonus is converted from crit damage rating via DR curve
const BASE_CRIT_MULTIPLIER: float = 1.5
const CDMG_FROM_PER: float = 2.5
const CDMG_K: float = 100.0

const EVADE_K: float = 120.0
const BLOCK_K: float = 80.0
