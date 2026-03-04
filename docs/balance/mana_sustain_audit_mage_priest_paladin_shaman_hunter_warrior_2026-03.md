# Mana sustain audit (Mage + Priest + Paladin + Shaman + Hunter + Warrior, 2026-03)

Assumptions: no gear, no consumables, current class progression, GCD=1.0s, mana regen active in combat.

## KPI system (reusable)

- **Quick spend 12s**: mana spent in first 12s of active rotation (target <= 35%).
- **Sustain 60s**: mana left after 60s (target >= 20%).
- **Status**: `OK` / `WARN` / `RISK` by thresholds above.

## Mage / profile `dps`

| Level | Resource pool | Passive regen/s | Resource after 12s | Resource after 60s | Quick spend 12s | Status |
|---:|---:|---:|---:|---:|---:|:---:|
| 20 | 1155 | 7.7 | 99.8% | 100.0% | 0.2% | OK |
| 40 | 2055 | 13.7 | 100.0% | 100.0% | 0.0% | OK |
| 60 | 2955 | 19.7 | 100.0% | 100.0% | 0.0% | OK |

## Priest / profile `dps`

| Level | Resource pool | Passive regen/s | Resource after 12s | Resource after 60s | Quick spend 12s | Status |
|---:|---:|---:|---:|---:|---:|:---:|
| 20 | 825 | 5.5 | 95.6% | 78.8% | 4.4% | OK |
| 40 | 1425 | 9.5 | 98.8% | 93.8% | 1.2% | OK |
| 60 | 2025 | 13.5 | 100.0% | 100.0% | 0.0% | OK |

## Priest / profile `heal_group`

| Level | Resource pool | Passive regen/s | Resource after 12s | Resource after 60s | Quick spend 12s | Status |
|---:|---:|---:|---:|---:|---:|:---:|
| 20 | 825 | 5.5 | 87.6% | 38.2% | 12.4% | OK |
| 40 | 1425 | 9.5 | 96.1% | 80.4% | 3.9% | OK |
| 60 | 2025 | 13.5 | 100.0% | 100.0% | 0.0% | OK |

## Paladin / profile `dps`

| Level | Resource pool | Passive regen/s | Resource after 12s | Resource after 60s | Quick spend 12s | Status |
|---:|---:|---:|---:|---:|---:|:---:|
| 20 | 750 | 5.0 | 100.0% | 100.0% | 0.0% | OK |
| 40 | 1350 | 9.0 | 98.2% | 95.9% | 1.8% | OK |
| 60 | 1950 | 13.0 | 99.7% | 100.0% | 0.3% | OK |

## Paladin / profile `heal_group`

| Level | Resource pool | Passive regen/s | Resource after 12s | Resource after 60s | Quick spend 12s | Status |
|---:|---:|---:|---:|---:|---:|:---:|
| 20 | 750 | 5.0 | 99.0% | 95.2% | 1.0% | OK |
| 40 | 1350 | 9.0 | 100.0% | 100.0% | 0.0% | OK |
| 60 | 1950 | 13.0 | 100.0% | 100.0% | 0.0% | OK |

## Shaman / profile `dps`

| Level | Resource pool | Passive regen/s | Resource after 12s | Resource after 60s | Quick spend 12s | Status |
|---:|---:|---:|---:|---:|---:|:---:|
| 20 | 1035 | 6.9 | 98.0% | 89.8% | 2.0% | OK |
| 40 | 1935 | 12.9 | 100.0% | 100.0% | 0.0% | OK |
| 60 | 2835 | 18.9 | 100.0% | 100.0% | 0.0% | OK |

## Shaman / profile `heal_group`

| Level | Resource pool | Passive regen/s | Resource after 12s | Resource after 60s | Quick spend 12s | Status |
|---:|---:|---:|---:|---:|---:|:---:|
| 20 | 1035 | 6.9 | 100.0% | 100.0% | 0.0% | OK |
| 40 | 1935 | 12.9 | 100.0% | 100.0% | 0.0% | OK |
| 60 | 2835 | 18.9 | 100.0% | 100.0% | 0.0% | OK |

## Hunter / profile `dps`

| Level | Resource pool | Passive regen/s | Resource after 12s | Resource after 60s | Quick spend 12s | Status |
|---:|---:|---:|---:|---:|---:|:---:|
| 20 | 578 | 3.9 | 85.3% | 31.4% | 14.7% | OK |
| 40 | 1028 | 6.9 | 97.6% | 92.8% | 2.4% | OK |
| 60 | 1478 | 9.9 | 99.8% | 99.8% | 0.2% | OK |

## Warrior / profile `dps`

| Level | Resource pool | Passive regen/s | Resource after 12s | Resource after 60s | Quick spend 12s | Status |
|---:|---:|---:|---:|---:|---:|:---:|
| 20 | 100 | 0.0 | 100.0% | 100.0% | 0.0% | OK |
| 40 | 100 | 0.0 | 89.3% | 96.0% | 10.7% | OK |
| 60 | 100 | 0.0 | 89.3% | 92.0% | 10.7% | OK |

## Notes

- Priest profiles include simplified mana return from `Power Absorption` (`value_pct`).
- Paladin baseline does not force long-duration buff pre-application (`Lights Guidance`); values are conservative.
- Paladin `Path of Righteous Fury` mana-on-hit from autos is not modeled explicitly here (conservative estimate).
- Shaman heal profile includes Water Devotion mana-over-time stance contribution in sustain estimate.
- Hunter profile includes only active-cast rotation and does not model bonus mana from every possible on-hit interaction (conservative estimate).
- Warrior profile uses rage economy model (max=100, no mana-regen) with rage gain from dealt/taken hits and auto-attack cadence assumptions.
- Results are balancing guardrails; final tuning should still be validated by encounter playtests.
