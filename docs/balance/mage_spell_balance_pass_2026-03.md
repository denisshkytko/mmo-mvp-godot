# Mage spell balance pass (2026-03) / Баланс-проход по заклинаниям мага (2026-03)

## RU

Этот баланс-проход настраивает заклинания мага относительно текущей базовой модели (без экипировки и без бафов), где автоатаки сами по себе с середины уровней часто проигрывают в боях против hostile-мобов.

### Методика

- Используются действующие формулы прогрессии и расчёта статов для игрока и враждебных целей.
- Сравнивается практическая эффективность заклинаний на уровнях открытия рангов: cast time, cooldown, resource cost и урон.
- Сохраняется идентичность класса (контроль + стабильный магический DPS), без перекоса в чрезмерный burst.

### Изменения

#### Fireball
- Уменьшено время каста на средних/высоких рангах:
  - L24–42: `2.0 -> 1.5`
  - L48–60: `3.0 -> 2.0`
- Обоснование: базовый "filler" не должен терять актуальность к высоким уровням.

#### Frostbolt
- Повышен flat-урон примерно на 20% на всех рангах (`10..100 -> 12..120`).
- Уменьшено время каста:
  - L26–44: `2.0 -> 1.6`
  - L50–56: `3.0 -> 2.2`
- Обоснование: заклинание контроля одиночной цели должно оставаться конкурентным относительно Fireball и автоатак.

#### Fire Blast
- Снижена стоимость ресурса: `12% -> 10%`.
- Повышен flat-урон примерно на 50% (`20..90 -> 30..135`).
- Обоснование: instant burst-кнопка должна ощущаться значимой при нажатии по кулдауну.

#### Hailstorm
- Снижен кулдаун: `10s -> 8s`.
- Уменьшено время каста:
  - L8–24: `3.0 -> 2.5`
  - L32–48: `4.0 -> 3.0`
  - L56: `5.0 -> 3.5`
- Повышен flat-урон примерно на 40% (`10..70 -> 14..98`).
- Обоснование: AoE/многоударный нук должен давать лучшую практическую отдачу.

#### Frost Wind
- Снижен кулдаун: `10s -> 8s`.
- Снижена стоимость ресурса: `16% -> 12%`.
- Повышен flat-урон примерно на 33% (`15..105 -> 20..140`).
- Обоснование: утилитарный slow-спелл теперь вносит ощутимый вклад в урон.

#### Meteor
- Снижен кулдаун: `15s -> 12s`.
- Уменьшено время каста: `5.0 -> 4.0`.
- Повышен flat-урон: `200/350 -> 230/400`.
- Обоснование: поздний «капстоун» должен заметнее вознаграждать длинный каст.

### Ожидаемый эффект

- Ротация мага по одиночной цели получает более стабильный реальный DPS на уровнях 30+.
- Контрольные спеллы перестают быть исключительно «оборонительным» выбором.
- Высокоуровневые кнопки (Hailstorm/Meteor) дают выраженные power-spike, не меняя глобальные формулы статов.

---

## EN

This pass tunes mage spells against the current no-gear/no-buff baseline where autos alone tend to lose vs hostile mobs from mid-levels onward.

### Method

- Use existing progression and stat formulas for player and hostile targets.
- Compare practical spell throughput by rank unlock levels with current cast time, cooldown, and resource costs.
- Keep class identity (control + sustained magic DPS), avoid extreme burst spikes.

### Changes

#### Fireball
- Mid/high-rank cast times reduced:
  - L24–42: `2.0 -> 1.5`
  - L48–60: `3.0 -> 2.0`
- Rationale: core filler should not become non-viable at high levels.

#### Frostbolt
- Flat damage increased by ~20% at all ranks (`10..100 -> 12..120`).
- Cast times reduced:
  - L26–44: `2.0 -> 1.6`
  - L50–56: `3.0 -> 2.2`
- Rationale: keep single-target control spell competitive with Fireball and autos.

#### Fire Blast
- Mana cost reduced: `12% -> 10%`.
- Flat damage increased by ~50% (`20..90 -> 30..135`).
- Rationale: instant burst button should feel impactful on cooldown.

#### Hailstorm
- Cooldown reduced: `10s -> 8s`.
- Cast times reduced:
  - L8–24: `3.0 -> 2.5`
  - L32–48: `4.0 -> 3.0`
  - L56: `5.0 -> 3.5`
- Flat damage increased by ~40% (`10..70 -> 14..98`).
- Rationale: AoE/channeled-style nuke needed better throughput for practical use.

#### Frost Wind
- Cooldown reduced: `10s -> 8s`.
- Mana cost reduced: `16% -> 12%`.
- Flat damage increased by ~33% (`15..105 -> 20..140`).
- Rationale: utility slow spell now has meaningful damage contribution.

#### Meteor
- Cooldown reduced: `15s -> 12s`.
- Cast time reduced: `5.0 -> 4.0`.
- Flat damage increased: `200/350 -> 230/400`.
- Rationale: late-game capstone should reward long cast with stronger payoff.

### Expected effect

- Mage single-target spell rotation has better real DPS at levels 30+.
- Control spells are no longer purely defensive choices.
- High-level spells (Hailstorm/Meteor) provide clear power spikes without changing global stat formulas.
