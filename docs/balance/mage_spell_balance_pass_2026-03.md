# Mage spell balance pass (2026-03)

This pass tunes mage spells against the current no-gear/no-buff baseline where autos alone tend to lose vs hostile mobs from mid-levels onward.

## Method

- Use existing progression and stat formulas for player and hostile targets.
- Compare practical spell throughput by rank unlock levels with current cast time, cooldown, and resource costs.
- Keep class identity (control + sustained magic DPS), avoid extreme burst spikes.

## Changes

### Fireball
- Mid/high-rank cast times reduced:
  - L24–42: `2.0 -> 1.5`
  - L48–60: `3.0 -> 2.0`
- Rationale: core filler should not become non-viable at high levels.

### Frostbolt
- Flat damage increased by ~20% at all ranks (`10..100 -> 12..120`).
- Cast times reduced:
  - L26–44: `2.0 -> 1.6`
  - L50–56: `3.0 -> 2.2`
- Rationale: keep single-target control spell competitive with Fireball and autos.

### Fire Blast
- Mana cost reduced: `12% -> 10%`.
- Flat damage increased by ~50% (`20..90 -> 30..135`).
- Rationale: instant burst button should feel impactful on cooldown.

### Hailstorm
- Cooldown reduced: `10s -> 8s`.
- Cast times reduced:
  - L8–24: `3.0 -> 2.5`
  - L32–48: `4.0 -> 3.0`
  - L56: `5.0 -> 3.5`
- Flat damage increased by ~40% (`10..70 -> 14..98`).
- Rationale: AoE/channeled-style nuke needed better throughput for practical use.

### Frost Wind
- Cooldown reduced: `10s -> 8s`.
- Mana cost reduced: `16% -> 12%`.
- Flat damage increased by ~33% (`15..105 -> 20..140`).
- Rationale: utility slow spell now has meaningful damage contribution.

### Meteor
- Cooldown reduced: `15s -> 12s`.
- Cast time reduced: `5.0 -> 4.0`.
- Flat damage increased: `200/350 -> 230/400`.
- Rationale: late-game capstone should reward long cast with stronger payoff.

## Expected effect

- Mage single-target spell rotation has better real DPS at levels 30+.
- Control spells are no longer purely defensive choices.
- High-level spells (Hailstorm/Meteor) provide clear power spikes without changing global stat formulas.
