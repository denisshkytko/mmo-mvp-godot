#!/usr/bin/env python3
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[2]

CLASS_INT = {
    "mage": {"base": 20.0, "per_level": 3.0},
    "priest": {"base": 17.0, "per_level": 2.0},
}

MANA_PER_INT = 15.0
MANA_REGEN_PER_INT = 0.1
SPELL_POWER_FROM_INT = 0.5
GCD_SEC = 1.0
LEVELS = [20, 40, 60]

ROTATIONS = {
    ("mage", "dps"): ["meteor", "hailstorm", "fire_blast", "frost_wind", "fireball"],
    ("priest", "dps"): ["radiance", "agony", "torment", "throe"],
    ("priest", "heal_group"): ["prayer_of_light", "radiance", "protective_barrier", "healing_stream", "heal"],
}

STANCE_BY_PROFILE = {
    ("mage", "dps"): None,
    ("priest", "dps"): "power_absorption",
    ("priest", "heal_group"): "power_absorption",
}


@dataclass
class RankData:
    required_level: int
    cooldown_sec: float
    cast_time_sec: float
    duration_sec: float
    resource_cost: int
    value_flat: int
    value_pct: float


@dataclass
class AbilityData:
    ability_id: str
    ability_type: str
    ranks: List[RankData]


def parse_ability_file(path: Path) -> AbilityData:
    lines = path.read_text(encoding="utf-8").splitlines()
    ability_id = ""
    ability_type = ""
    for line in lines:
        if line.startswith("id = ") and not ability_id:
            ability_id = line.split('"')[1]
        if line.startswith("ability_type = ") and not ability_type:
            ability_type = line.split('"')[1]

    ranks: List[RankData] = []
    cur: Dict[str, float] = {}
    in_rank = False
    keys = ["required_level", "cooldown_sec", "cast_time_sec", "duration_sec", "resource_cost", "value_flat", "value_pct"]

    for line in lines:
        if 'script_class="RankData"' in line:
            in_rank = True
            cur = {}
            continue
        if not in_rank:
            continue
        for k in keys:
            pref = f"{k} = "
            if line.startswith(pref):
                raw = line[len(pref):].strip()
                cur[k] = float(raw) if "." in raw else int(raw)
        if line.startswith("flags = "):
            in_rank = False
            ranks.append(
                RankData(
                    required_level=int(cur.get("required_level", 1)),
                    cooldown_sec=float(cur.get("cooldown_sec", 0.0)),
                    cast_time_sec=float(cur.get("cast_time_sec", 0.0)),
                    duration_sec=float(cur.get("duration_sec", 0.0)),
                    resource_cost=int(cur.get("resource_cost", 0)),
                    value_flat=int(cur.get("value_flat", 0)),
                    value_pct=float(cur.get("value_pct", 0.0)),
                )
            )

    return AbilityData(ability_id=ability_id, ability_type=ability_type, ranks=ranks)


def load_class_abilities(class_id: str) -> Dict[str, AbilityData]:
    out: Dict[str, AbilityData] = {}
    for path in sorted((ROOT / "core" / "data" / "abilities" / class_id).glob("*.tres")):
        a = parse_ability_file(path)
        out[a.ability_id] = a
    return out


def rank_for_level(ability: AbilityData, level: int) -> Optional[RankData]:
    chosen: Optional[RankData] = None
    for r in ability.ranks:
        if r.required_level <= level:
            chosen = r
    return chosen


def class_stats(class_id: str, level: int) -> Dict[str, float]:
    ci = CLASS_INT[class_id]
    stat_int = ci["base"] + ci["per_level"] * (level - 1)
    return {
        "int": stat_int,
        "max_mana": stat_int * MANA_PER_INT,
        "mana_regen": stat_int * MANA_REGEN_PER_INT,
        "spell_power": stat_int * SPELL_POWER_FROM_INT,
    }


def estimate_effect_amount(ability: AbilityData, rank: RankData, spell_power: float) -> int:
    # Generic approximation from current spell effects: base throughput ~= value_flat + spell_power.
    return max(0, rank.value_flat + int(round(spell_power)))


def get_stance_return_pcts(class_id: str, profile: str, level: int, abilities: Dict[str, AbilityData]) -> Tuple[float, float]:
    stance_id = STANCE_BY_PROFILE.get((class_id, profile))
    if not stance_id:
        return 0.0, 0.0
    stance = abilities.get(stance_id)
    if stance is None:
        return 0.0, 0.0
    stance_rank = rank_for_level(stance, level)
    if stance_rank is None:
        return 0.0, 0.0

    # For priest `power_absorption` value_pct powers mana returns on spell damage/heal.
    if stance_id == "power_absorption":
        return stance_rank.value_pct, stance_rank.value_pct
    return 0.0, 0.0


def simulate_profile(class_id: str, level: int, profile: str, duration_sec: float, abilities: Dict[str, AbilityData]) -> Dict[str, float]:
    stats = class_stats(class_id, level)
    mana = stats["max_mana"]
    mana_regen = stats["mana_regen"]
    spell_power = stats["spell_power"]
    return_pct_damage, return_pct_heal = get_stance_return_pcts(class_id, profile, level, abilities)

    t = 0.0
    cds: Dict[str, float] = {}

    while t < duration_sec:
        chosen: Optional[Tuple[str, AbilityData, RankData]] = None
        for aid in ROTATIONS[(class_id, profile)]:
            a = abilities.get(aid)
            if a is None:
                continue
            r = rank_for_level(a, level)
            if r is None:
                continue
            if cds.get(aid, 0.0) > t:
                continue
            if r.resource_cost > mana:
                continue
            chosen = (aid, a, r)
            break

        dt = GCD_SEC
        if chosen is not None:
            aid, a, r = chosen
            dt = max(GCD_SEC, r.cast_time_sec)
            mana -= r.resource_cost
            cds[aid] = t + r.cooldown_sec

            amount = estimate_effect_amount(a, r, spell_power)
            if amount > 0:
                if a.ability_type in {"damage", "active"}:
                    mana += amount * (return_pct_damage / 100.0)
                if a.ability_type in {"heal", "buff", "active"}:
                    mana += amount * (return_pct_heal / 100.0)

        mana += mana_regen * dt
        mana = max(0.0, min(stats["max_mana"], mana))
        t += dt
        if mana <= 0.01:
            break

    return {"mana_pct": (mana / stats["max_mana"] * 100.0) if stats["max_mana"] > 0 else 0.0}


def evaluate_status(quick_spend_pct: float, mana60_pct: float) -> str:
    if quick_spend_pct <= 35.0 and mana60_pct >= 20.0:
        return "OK"
    if quick_spend_pct <= 45.0 and mana60_pct >= 10.0:
        return "WARN"
    return "RISK"


def build_report() -> str:
    data = {"mage": load_class_abilities("mage"), "priest": load_class_abilities("priest")}

    lines: List[str] = []
    lines.append("# Mana sustain audit (Mage + Priest, 2026-03)")
    lines.append("")
    lines.append("Assumptions: no gear, no consumables, current class progression, GCD=1.0s, mana regen active in combat.")
    lines.append("")
    lines.append("## KPI system (reusable)")
    lines.append("")
    lines.append("- **Quick spend 12s**: mana spent in first 12s of active rotation (target <= 35%).")
    lines.append("- **Sustain 60s**: mana left after 60s (target >= 20%).")
    lines.append("- **Status**: `OK` / `WARN` / `RISK` by thresholds above.")
    lines.append("")

    for class_id, profile in [("mage", "dps"), ("priest", "dps"), ("priest", "heal_group")]:
        lines.append(f"## {class_id.capitalize()} / profile `{profile}`")
        lines.append("")
        lines.append("| Level | Mana pool | Regen/s | Mana after 12s | Mana after 60s | Quick spend 12s | Status |")
        lines.append("|---:|---:|---:|---:|---:|---:|:---:|")
        for lvl in LEVELS:
            st = class_stats(class_id, lvl)
            s12 = simulate_profile(class_id, lvl, profile, 12.0, data[class_id])
            s60 = simulate_profile(class_id, lvl, profile, 60.0, data[class_id])
            quick_spend = max(0.0, 100.0 - s12["mana_pct"])
            status = evaluate_status(quick_spend, s60["mana_pct"])
            lines.append(
                f"| {lvl} | {st['max_mana']:.0f} | {st['mana_regen']:.1f} | {s12['mana_pct']:.1f}% | {s60['mana_pct']:.1f}% | {quick_spend:.1f}% | {status} |"
            )
        lines.append("")

    lines.append("## Notes")
    lines.append("")
    lines.append("- Priest profiles include simplified mana return from `Power Absorption` (`value_pct`).")
    lines.append("- Results are intended as balancing guardrails; live tuning can refine assumptions per encounter type.")
    return "\n".join(lines) + "\n"


def main() -> None:
    out = ROOT / "docs" / "balance" / "mana_sustain_audit_mage_priest_2026-03.md"
    out.write_text(build_report(), encoding="utf-8")
    print(f"written: {out}")


if __name__ == "__main__":
    main()
