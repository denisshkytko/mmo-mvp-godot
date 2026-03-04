# Mana sustain audit (Mage + Priest + Paladin, 2026-03)

Assumptions: no gear, no consumables, current class progression, GCD=1.0s, mana regen active in combat.

## KPI system (reusable)

- **Quick spend 12s**: mana spent in first 12s of active rotation (target <= 35%).
- **Sustain 60s**: mana left after 60s (target >= 20%).
- **Status**: `OK` / `WARN` / `RISK` by thresholds above.

## Mage / profile `dps`

| Level | Mana pool | Regen/s | Mana after 12s | Mana after 60s | Quick spend 12s | Status |
|---:|---:|---:|---:|---:|---:|:---:|
| 20 | 1155 | 7.7 | 99.8% | 100.0% | 0.2% | OK |
| 40 | 2055 | 13.7 | 100.0% | 100.0% | 0.0% | OK |
| 60 | 2955 | 19.7 | 100.0% | 100.0% | 0.0% | OK |

## Priest / profile `dps`

| Level | Mana pool | Regen/s | Mana after 12s | Mana after 60s | Quick spend 12s | Status |
|---:|---:|---:|---:|---:|---:|:---:|
| 20 | 825 | 5.5 | 95.6% | 78.8% | 4.4% | OK |
| 40 | 1425 | 9.5 | 100.0% | 100.0% | 0.0% | OK |
| 60 | 2025 | 13.5 | 100.0% | 100.0% | 0.0% | OK |

## Priest / profile `heal_group`

| Level | Mana pool | Regen/s | Mana after 12s | Mana after 60s | Quick spend 12s | Status |
|---:|---:|---:|---:|---:|---:|:---:|
| 20 | 825 | 5.5 | 87.6% | 38.2% | 12.4% | OK |
| 40 | 1425 | 9.5 | 96.1% | 80.4% | 3.9% | OK |
| 60 | 2025 | 13.5 | 100.0% | 100.0% | 0.0% | OK |

## Paladin / profile `dps`

| Level | Mana pool | Regen/s | Mana after 12s | Mana after 60s | Quick spend 12s | Status |
|---:|---:|---:|---:|---:|---:|:---:|
| 20 | 750 | 5.0 | 100.0% | 100.0% | 0.0% | OK |
| 40 | 1350 | 9.0 | 99.1% | 99.0% | 0.9% | OK |
| 60 | 1950 | 13.0 | 100.0% | 100.0% | 0.0% | OK |

## Paladin / profile `heal_group`

| Level | Mana pool | Regen/s | Mana after 12s | Mana after 60s | Quick spend 12s | Status |
|---:|---:|---:|---:|---:|---:|:---:|
| 20 | 750 | 5.0 | 99.0% | 95.2% | 1.0% | OK |
| 40 | 1350 | 9.0 | 100.0% | 100.0% | 0.0% | OK |
| 60 | 1950 | 13.0 | 100.0% | 100.0% | 0.0% | OK |

## Notes

- Priest profiles include simplified mana return from `Power Absorption` (`value_pct`).
- Paladin baseline does not force long-duration buff pre-application (`Lights Guidance`); values are conservative.
- Paladin `Path of Righteous Fury` mana-on-hit from autos is not modeled explicitly here (conservative estimate).
- Results are balancing guardrails; final tuning should still be validated by encounter playtests.
