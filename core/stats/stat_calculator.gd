extends RefCounted
class_name StatCalculator

const C := preload("res://core/stats/stat_constants.gd")

# A small helper for building "breakdown" dictionaries.
static func _add_breakdown_line(arr: Array, label: String, value, extra: String = "") -> void:
    arr.append({"label": label, "value": value, "extra": extra})

# Build a full "stats snapshot" for the player, including:
# - final numeric values used by gameplay (max_hp, attack_power, ...)
# - human-friendly breakdown for CharacterHUD
#
# Inputs:
# - level: player level
# - base_primary: {"str":int, "agi":int, "end":int, "int":int, "per":int}
# - primary_per_level: same keys, per-level gain (int)
# - gear: dictionary of flat stats/ratings (later equipment system will fill this)
# - buffs: array from PlayerBuffs.get_buffs_snapshot()
static func build_player_snapshot(
    level: int,
    base_primary: Dictionary,
    primary_per_level: Dictionary,
    gear: Dictionary,
    buffs: Array
) -> Dictionary:

    level = max(1, level)

    # ------------------
    # 1) Primary stats
    # ------------------
    var prim := {"str": 0, "agi": 0, "end": 0, "int": 0, "per": 0}
    var prim_break := {"str": [], "agi": [], "end": [], "int": [], "per": []}

    for k in prim.keys():
        var base_v: int = int(base_primary.get(k, 0))
        var per_lvl: int = int(primary_per_level.get(k, 0))
        var from_lvl: int = per_lvl * (level - 1)
        prim[k] = base_v + from_lvl
        _add_breakdown_line(prim_break[k], "base", base_v)
        if from_lvl != 0:
            _add_breakdown_line(prim_break[k], "level", from_lvl, "(%d×%d)" % [per_lvl, level - 1])

    # Apply flat primary mods from gear
    var gear_primary: Dictionary = gear.get("primary", {}) if gear.has("primary") else {}
    for k in prim.keys():
        var add_v: int = int(gear_primary.get(k, 0))
        if add_v != 0:
            prim[k] += add_v
            _add_breakdown_line(prim_break[k], "gear", add_v)

    # Apply flat primary mods from buffs
    for b in buffs:
        if not (b is Dictionary):
            continue
        var bd: Dictionary = b as Dictionary
        var id: String = String(bd.get("id", ""))
        var data: Dictionary = bd.get("data", {}) as Dictionary
        var bprim: Dictionary = data.get("primary", {}) as Dictionary
        for k in prim.keys():
            var add_v: int = int(bprim.get(k, 0))
            if add_v != 0:
                prim[k] += add_v
                _add_breakdown_line(prim_break[k], id, add_v)

    # ------------------
    # 2) Base derived (pre-percent)
    # ------------------
    var derived := {
        "max_hp": 0,
        "max_mana": 0,
        "hp_regen": 0.0,
        "mana_regen": 0.0,

        "attack_power": 0.0,
        "spell_power": 0.0,
        "defense": 0.0,
        "magic_resist": 0.0,

        "speed": 0,
        "attack_speed_rating": 0,
        "cast_speed_rating": 0,
        "crit_chance_rating": 0,
        "crit_damage_rating": 0,
    }

    var breakdown := {
        "max_hp": [],
        "max_mana": [],
        "hp_regen": [],
        "mana_regen": [],
        "attack_power": [],
        "spell_power": [],
        "defense": [],
        "magic_resist": [],
        "speed": [],
        "attack_speed_rating": [],
        "cast_speed_rating": [],
        "crit_chance_rating": [],
        "crit_damage_rating": [],
    }

    # MaxHP / MaxMana (ONLY from primary + mods)
    derived.max_hp = int(round(prim.end * C.HP_PER_END))
    _add_breakdown_line(breakdown.max_hp, "END", prim.end * C.HP_PER_END)

    derived.max_mana = int(round(prim.int * C.MANA_PER_INT))
    _add_breakdown_line(breakdown.max_mana, "INT", prim.int * C.MANA_PER_INT)

    # Regen (per second)
    derived.hp_regen = prim.end * C.HP_REGEN_PER_END
    _add_breakdown_line(breakdown.hp_regen, "END", prim.end * C.HP_REGEN_PER_END)

    derived.mana_regen = prim.int * C.MANA_REGEN_PER_INT
    _add_breakdown_line(breakdown.mana_regen, "INT", prim.int * C.MANA_REGEN_PER_INT)

    # Powers
    derived.attack_power = prim.str * C.AP_FROM_STR + prim.agi * C.AP_FROM_AGI
    _add_breakdown_line(breakdown.attack_power, "STR", prim.str * C.AP_FROM_STR)
    _add_breakdown_line(breakdown.attack_power, "AGI", prim.agi * C.AP_FROM_AGI)

    derived.spell_power = prim.int * C.SP_FROM_INT
    _add_breakdown_line(breakdown.spell_power, "INT", prim.int * C.SP_FROM_INT)

    # Defense / Resist units (player base is 0, gear can add)
    derived.defense = prim.str * C.DEF_FROM_STR + prim.end * C.DEF_FROM_END
    _add_breakdown_line(breakdown.defense, "STR", prim.str * C.DEF_FROM_STR)
    _add_breakdown_line(breakdown.defense, "END", prim.end * C.DEF_FROM_END)

    derived.magic_resist = prim.int * C.RES_FROM_INT + prim.end * C.RES_FROM_END
    _add_breakdown_line(breakdown.magic_resist, "INT", prim.int * C.RES_FROM_INT)
    _add_breakdown_line(breakdown.magic_resist, "END", prim.end * C.RES_FROM_END)

    # Speed ratings
    derived.speed = 0
    # SpeedRating only from gear/buffs

    derived.attack_speed_rating = prim.agi * C.AS_FROM_AGI
    _add_breakdown_line(breakdown.attack_speed_rating, "AGI", prim.agi * C.AS_FROM_AGI)
    derived.cast_speed_rating = prim.int * C.CS_FROM_INT
    _add_breakdown_line(breakdown.cast_speed_rating, "INT", prim.int * C.CS_FROM_INT)

    # Crit ratings
    derived.crit_chance_rating = prim.per * C.CRIT_FROM_PER + prim.agi * C.CRIT_FROM_AGI
    _add_breakdown_line(breakdown.crit_chance_rating, "PER", prim.per * C.CRIT_FROM_PER)
    _add_breakdown_line(breakdown.crit_chance_rating, "AGI", prim.agi * C.CRIT_FROM_AGI)

    derived.crit_damage_rating = prim.per * C.CDMG_FROM_PER
    _add_breakdown_line(breakdown.crit_damage_rating, "PER", prim.per * C.CDMG_FROM_PER)

    # ------------------
    # 3) Apply gear flat secondary
    # ------------------
    var gear_sec: Dictionary = gear.get("secondary", {}) if gear.has("secondary") else {}

    _apply_flat_secondary(derived, breakdown, gear_sec, "gear")

    # ------------------
    # 4) Apply buff flat secondary
    # ------------------
    var percent_mods := {
        "attack_power": 0.0,
        "spell_power": 0.0,
        "defense": 0.0,
        "magic_resist": 0.0,
    }

    for b in buffs:
        if not (b is Dictionary):
            continue
        var bd: Dictionary = b as Dictionary
        var id: String = String(bd.get("id", ""))
        var data: Dictionary = bd.get("data", {}) as Dictionary

        # legacy compatibility
        if data.has("attack_bonus"):
            _apply_flat_secondary(derived, breakdown, {"attack_power": int(data.get("attack_bonus", 0))}, id)

        var sec: Dictionary = data.get("secondary", {}) as Dictionary
        _apply_flat_secondary(derived, breakdown, sec, id)

        var perc: Dictionary = data.get("percent", {}) as Dictionary
        for pk in percent_mods.keys():
            if perc.has(pk):
                percent_mods[pk] += float(perc.get(pk, 0.0))

    # ------------------
    # 5) Percent buffs (two-phase)
    # ------------------
    _apply_percent_bonus(derived, breakdown, "attack_power", percent_mods.attack_power)
    _apply_percent_bonus(derived, breakdown, "spell_power", percent_mods.spell_power)
    _apply_percent_bonus(derived, breakdown, "defense", percent_mods.defense)
    _apply_percent_bonus(derived, breakdown, "magic_resist", percent_mods.magic_resist)

    # ------------------
    # 6) Conversions to % (for UI)
    # ------------------
    var atk_speed_pct: float = float(derived.attack_speed_rating) / C.AS_RATING_PER_1PCT
    var cast_speed_pct: float = float(derived.cast_speed_rating) / C.CS_RATING_PER_1PCT
    var cooldown_reduction_pct: float = 0.0
    if C.COOLDOWN_RATING_PER_1PCT > 0.0:
        cooldown_reduction_pct = float(derived.speed) / C.COOLDOWN_RATING_PER_1PCT
    var crit_chance_pct: float = min(float(derived.crit_chance_rating) / C.CRIT_RATING_PER_1PCT, 100.0)
    var crit_mult: float = 2.0 + (float(derived.crit_damage_rating) / C.CDMG_RATING_PER_0_01_MULT) * 0.01

    var phys_reduction_pct: float = _mitigation_pct(float(derived.defense))
    var mag_reduction_pct: float = _mitigation_pct(float(derived.magic_resist))

    # Build final snapshot
    return {
        "level": level,
        "primary": prim,
        "primary_breakdown": prim_break,
        "derived": derived,
        "derived_breakdown": breakdown,

        "attack_speed_pct": atk_speed_pct,
        "cast_speed_pct": cast_speed_pct,
        "cooldown_reduction_pct": cooldown_reduction_pct,
        "crit_chance_pct": crit_chance_pct,
        "crit_multiplier": crit_mult,

        # both keys for compatibility
        "physical_reduction_pct": phys_reduction_pct,
        "magic_reduction_pct": mag_reduction_pct,
        "defense_mitigation_pct": phys_reduction_pct,
        "magic_mitigation_pct": mag_reduction_pct,
    }


# ------------------------------------------------------------
# Stage 2 (Mobs/NPC): keep existing "base_attack / base_hp / base_def" workflow,
# but convert it into the same derived stats model used by the Player.
#
# This keeps your current scenes working (no mass re-tuning needed), while
# giving us unified formulas for damage/mitigation/crit/speed.
#
# Notes:
# - Mobs grow by level via these legacy numbers.
# - Internally we estimate Primary stats so derived values feel consistent.
# - Mobs can later switch to explicit Primary exports (we can add that in stage 3).
# ------------------------------------------------------------
static func build_mob_snapshot_from_legacy(
    level: int,
    base_attack: int,
    attack_per_level: int,
    base_max_hp: int,
    hp_per_level: int,
    base_defense: int,
    defense_per_level: int,
    base_magic_resist: int = 0,
    magic_resist_per_level: int = 0
) -> Dictionary:
    level = max(1, level)

    # Estimate "primary" from legacy numbers so derived formulas stay coherent.
    # Physical damage model: damage ~= AttackPower * AP_DAMAGE_SCALAR
    # AttackPower ~= STR*AP_FROM_STR (AGI/other primaries assumed 0 for mobs for now)
    var ap_from_attack: float = float(base_attack) / max(0.01, C.AP_DAMAGE_SCALAR)
    var str_base: int = int(round(ap_from_attack / max(0.01, C.AP_FROM_STR)))
    var ap_from_attack_pl: float = float(attack_per_level) / max(0.01, C.AP_DAMAGE_SCALAR)
    var str_pl: int = int(round(ap_from_attack_pl / max(0.01, C.AP_FROM_STR)))

    # HP model: MaxHP ~= END*HP_PER_END + STR*HP_PER_STR
    var end_base: int = int(round(max(0.0, float(base_max_hp) - float(str_base) * C.HP_PER_STR) / max(0.01, C.HP_PER_END)))
    var end_pl: int = int(round(float(hp_per_level) / max(0.01, C.HP_PER_END)))

    var base_primary := {
        "str": max(1, str_base),
        "agi": 0,
        "end": max(1, end_base),
        "int": 0,
        "per": 0,
    }
    var per_lvl := {
        "str": max(0, str_pl),
        "agi": 0,
        "end": max(0, end_pl),
        "int": 0,
        "per": 0,
    }

    # Base mitigation scaling (so mobs don't become "paper" at higher level).
    var def_v: int = max(0, base_defense + (level - 1) * defense_per_level)
    var res_v: int = max(0, base_magic_resist + (level - 1) * magic_resist_per_level)
    var gear := {
        "primary": {},
        "secondary": {
            "defense": def_v,
            "magic_resist": res_v,
            "speed": 0,
            "crit_chance_rating": 0,
            "crit_damage_rating": 0,
        }
    }

    return build_player_snapshot(level, base_primary, per_lvl, gear, [])


# ------------------------------------------------------------
# Stage 2+ (Mobs/NPC) — explicit Primary exports.
#
# Mobs/NPC:
# - Primary stats grow by level (base + per_level*(lvl-1))
# - No gear by default (can be added later)
# - Can have extra baseline mitigation growth (base_def/res + per_level)
# ------------------------------------------------------------
static func build_mob_snapshot_from_primary(
    level: int,
    base_primary: Dictionary,
    primary_per_level: Dictionary,
    base_defense: int = 0,
    defense_per_level: int = 0,
    base_magic_resist: int = 0,
    magic_resist_per_level: int = 0,
    extra_secondary: Dictionary = {},
    primary_multiplier: float = 1.0
) -> Dictionary:
    level = max(1, level)

    var def_v: int = max(0, base_defense + (level - 1) * defense_per_level)
    var res_v: int = max(0, base_magic_resist + (level - 1) * magic_resist_per_level)

    var gear := {
        "primary": {},
        "secondary": {
            "defense": def_v,
            "magic_resist": res_v,
        }
    }

    # Allow injecting extra secondary (e.g., speed, flat AP) if needed later.
    if extra_secondary != null:
        if not gear.has("secondary"):
            gear["secondary"] = {}
        for k in (extra_secondary as Dictionary).keys():
            gear["secondary"][k] = (extra_secondary as Dictionary)[k]

    var calc_level := level
    var calc_base_primary := base_primary
    var calc_primary_per_level := primary_per_level
    if primary_multiplier != 1.0:
        var adjusted_primary := {}
        for k in ["str", "agi", "end", "int", "per"]:
            var base_v: int = int(base_primary.get(k, 0))
            var per_lvl: int = int(primary_per_level.get(k, 0))
            var total_v: int = base_v + per_lvl * (level - 1)
            adjusted_primary[k] = int(floor(float(total_v) * primary_multiplier))
        calc_level = 1
        calc_base_primary = adjusted_primary
        calc_primary_per_level = {"str": 0, "agi": 0, "end": 0, "int": 0, "per": 0}

    return build_player_snapshot(calc_level, calc_base_primary, calc_primary_per_level, gear, [])


static func build_mob_snapshot_from_primary_values(
    level: int,
    primary: Dictionary,
    base_defense: int = 0,
    defense_per_level: int = 0,
    base_magic_resist: int = 0,
    magic_resist_per_level: int = 0
) -> Dictionary:
    level = max(1, level)

    var def_v: int = max(0, base_defense + (level - 1) * defense_per_level)
    var res_v: int = max(0, base_magic_resist + (level - 1) * magic_resist_per_level)

    var gear := {
        "primary": {},
        "secondary": {
            "defense": def_v,
            "magic_resist": res_v,
        }
    }

    var per_lvl := {"str": 0, "agi": 0, "end": 0, "int": 0, "per": 0}
    return build_player_snapshot(1, primary, per_lvl, gear, [])


static func _apply_flat_secondary(derived: Dictionary, breakdown: Dictionary, sec: Dictionary, source: String) -> void:
    if sec == null:
        return

    # "speed" influences AttackSpeedRating and CastSpeedRating (not a % itself)
    if sec.has("speed"):
        var v: int = int(sec.get("speed", 0))
        if v != 0:
            derived.speed += v
            _add_breakdown_line(breakdown.speed, source, v)
            # propagate to both ratings
            var as_add: int = v * C.AS_FROM_SPEED
            var cs_add: int = v * C.CS_FROM_SPEED
            derived.attack_speed_rating += as_add
            derived.cast_speed_rating += cs_add
            _add_breakdown_line(breakdown.attack_speed_rating, source + " (Speed)", as_add)
            _add_breakdown_line(breakdown.cast_speed_rating, source + " (Speed)", cs_add)

    var direct_keys := [
        "attack_power",
        "spell_power",
        "defense",
        "magic_resist",
        "crit_chance_rating",
        "crit_damage_rating",
        "attack_speed_rating",
        "cast_speed_rating",
        "max_hp",
        "max_mana",
        "hp_regen",
        "mana_regen",
    ]

    for k in direct_keys:
        if not sec.has(k):
            continue
        var v2 = sec.get(k)
        if typeof(v2) == TYPE_INT or typeof(v2) == TYPE_FLOAT:
            var addf: float = float(v2)
            if addf != 0.0:
                derived[k] += addf
                _add_breakdown_line(breakdown[k], source, addf)


static func _apply_percent_bonus(derived: Dictionary, breakdown: Dictionary, key: String, pct: float) -> void:
    if pct == 0.0:
        return
    var base_val: float = float(derived.get(key, 0.0))
    var add: float = base_val * pct
    derived[key] = base_val + add
    _add_breakdown_line(breakdown[key], "percent", add, "+%d%%" % int(round(pct * 100.0)))


static func _mitigation_pct(value: float) -> float:
    if value <= 0.0:
        return 0.0
    var mult: float = C.MITIGATION_K / (C.MITIGATION_K + value)
    var pct: float = 100.0 * (1.0 - mult)
    return clamp(pct, 0.0, C.MAX_MITIGATION_PCT)
