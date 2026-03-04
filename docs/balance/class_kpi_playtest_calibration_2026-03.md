# Class KPI + playtest calibration pass (2026-03)

## Scope

Targeted follow-up after SP-scaling rollout:
- keep unified framework,
- make small per-class cost corrections where spam/sustain looked too free,
- explicitly record that non-linear rank growth is allowed when justified by gameplay.

## Data changes (targeted)

### Mage
- `fireball`: increased `resource_cost` at higher ranks (24+), with non-linear steps by rank.

### Priest
- `throe`: increased `resource_cost` on mid/high ranks (22+).
- `heal`: increased `resource_cost` on higher ranks (36+).
- `healing_stream`: increased `resource_cost` on higher ranks (34+).

### Paladin
- `strike_of_light`: increased `resource_cost` on 26+ ranks.
- `storm_of_light`: increased `resource_cost` on all ranks (40/50/60) with stronger top-rank pressure.

### Shaman
- `lightning`: increased `resource_cost` on 26+ ranks.
- `lesser_heal`: increased `resource_cost` on 36+ ranks.

### Hunter
- `arcane_shot`: increased `resource_cost` on 34+ ranks.

## KPI check (audit)

Command:
- `python3 tools/balance/mana_sustain_audit.py`

Result:
- audit regenerated successfully,
- no profile moved into `WARN/RISK`,
- several profiles still show very high sustain at level 40/60 (expected with current conservative model and simplified rotation assumptions).

## Playtest checklist (next)

1. Run 20/40/60 dungeon-length combats for each profile (`dps`, `heal_group`) and capture:
   - average resource at 15s / 30s / 60s,
   - number of forced idle GCDs from OOM/rage shortage,
   - usage share of filler vs cooldown abilities.
2. Validate whether high-sustain KPI rows are truly overperforming in live combat, or only in simplified script assumptions.
3. Apply second micro-pass only where gameplay confirms over-sustain.

## Notes

- Non-linear per-rank growth is **allowed but optional**; use only when needed to solve specific breakpoint issues.
- Keep default preference for simple linear growth if gameplay quality is already acceptable.
