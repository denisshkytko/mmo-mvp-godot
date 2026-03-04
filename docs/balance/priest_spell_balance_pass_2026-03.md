# Priest spell balance pass (2026-03) / Баланс-проход по заклинаниям жреца (2026-03)

## RU

Этот проход обновляет **всю линейку заклинаний жреца** с учётом актуальной модели роста игрока/мобов и уже обновлённого мага.

Цель: сохранить уникальность жреца как гибридного support/caster (sustain, контроль, защита, командное лечение), не делая его «вторым магом» по burst-DPS.

### Принципы

- Относительно мага у жреца ниже пиковый burst, но выше ценность sustained pressure (DoT/контроль) и командной выживаемости.
- Улучшены «дорогие» по времени/ресурсу кнопки, чтобы их фактическая отдача соответствовала риску.
- Стойки разведены по ролям: `Inner Fire` (урон+деф) и `Power Absorption` (ресурсная устойчивость).

### Изменения по всем заклинаниям

#### Damage/Control
- **Throe**: flat-урон `15..120 -> 20..160`, ускорены средние/высокие ранги каста (`1.0 -> 0.9`, финал `1.5 -> 1.2`).
- **Agony**: flat-урон `50..250 -> 70..350`, cooldown `8s -> 7s`.
- **Torment**: DoT total flat `30..240 -> 45..360`, cooldown `10s -> 8s`.
- **Fear**: cooldown `40s -> 36s`, resource cost `16 -> 14`.

#### Direct/HoT/AoE healing
- **Heal**: `75..345 -> 95..440`, high-rank cast time `2.0 -> 1.6`, финал `3.0 -> 2.2`.
- **Healing Stream**: `25..225 -> 35..315`, средние ранги каста `1.0 -> 0.8`, финал `1.5 -> 1.2`.
- **Radiance** (AoE heal+damage): `100/200 -> 140/280`, cooldown `15s -> 12s`.
- **Prayer of Light**: `250 -> 380`, cast time `5.0 -> 4.0`.

#### Экономика ресурса / манакосты
- **Throe**: `8 -> 8` (оставлен как базовый filler по цене).
- **Agony**: `8 -> 9`.
- **Torment**: `8 -> 10`.
- **Heal**: `8 -> 9`.
- **Healing Stream**: `8 -> 10`.
- **Protective Barrier**: `12 -> 14`.
- **Prayer of Light**: `16 -> 18`.
- Обоснование: после буста throughput скорректированы манакосты для лучшего anti-spam-контроля, сохраняя sustain-роль жреца.

#### Buffs/Stances/Defensive utility
- **Fortitude**: END `5..30 -> 6..36`, regen tick `2..12 -> 3..18`.
- **Protective Barrier**: absorb `150..750 -> 190..950`.
- **Inner Fire**: magic crit damage bonus `50/60/70/80 -> 35/45/55/65`, incoming damage reduction `10/15/20/25 -> 8/12/16/20`.
- **Power Absorption**: mana returns `5/10 -> 8/14` (heal/spell dmg and hit triggers).

### Ожидаемый эффект

- Жрец ощутимо сильнее в sustain-роли и групповом сейве.
- Разница с магом читается лучше: меньше burst-пиков, больше стабильной ценности через лечение/DoT/utility.
- Внутри линейки жреца «долгие» и «дорогие» кнопки дают более предсказуемую и адекватную отдачу.

---

## EN

This pass updates the **entire priest spell kit** against the current player/mob growth model and the already-updated mage baseline.

Goal: keep priest identity as a hybrid support/caster (sustain, control, protection, group healing) without turning it into a mage-like burst caster.

### Principles

- Compared to mage, priest has lower burst peaks but stronger sustained pressure (DoT/control) and team survivability value.
- High-risk/high-cost abilities were buffed so practical output better matches their cost.
- Stances now have clearer separation: `Inner Fire` (damage+defense) vs `Power Absorption` (resource sustain).

### Full spell list changes

#### Damage/Control
- **Throe**: flat damage `15..120 -> 20..160`, mid/high-rank cast speedups (`1.0 -> 0.9`, final `1.5 -> 1.2`).
- **Agony**: flat damage `50..250 -> 70..350`, cooldown `8s -> 7s`.
- **Torment**: DoT total flat `30..240 -> 45..360`, cooldown `10s -> 8s`.
- **Fear**: cooldown `40s -> 36s`, resource cost `16 -> 14`.

#### Direct/HoT/AoE healing
- **Heal**: `75..345 -> 95..440`, high-rank cast time `2.0 -> 1.6`, final `3.0 -> 2.2`.
- **Healing Stream**: `25..225 -> 35..315`, mid-rank cast time `1.0 -> 0.8`, final `1.5 -> 1.2`.
- **Radiance** (AoE heal+damage): `100/200 -> 140/280`, cooldown `15s -> 12s`.
- **Prayer of Light**: `250 -> 380`, cast time `5.0 -> 4.0`.

#### Resource economy / mana costs
- **Throe**: `8 -> 8` (kept as baseline filler cost).
- **Agony**: `8 -> 9`.
- **Torment**: `8 -> 10`.
- **Heal**: `8 -> 9`.
- **Healing Stream**: `8 -> 10`.
- **Protective Barrier**: `12 -> 14`.
- **Prayer of Light**: `16 -> 18`.
- Rationale: after throughput buffs, mana costs were adjusted for stronger anti-spam control while preserving priest sustain identity.

#### Buffs/Stances/Defensive utility
- **Fortitude**: END `5..30 -> 6..36`, regen tick `2..12 -> 3..18`.
- **Protective Barrier**: absorb `150..750 -> 190..950`.
- **Inner Fire**: magic crit damage bonus `50/60/70/80 -> 35/45/55/65`, incoming damage reduction `10/15/20/25 -> 8/12/16/20`.
- **Power Absorption**: mana returns `5/10 -> 8/14` (heal/spell damage and hit triggers).

### Expected effect

- Priest gains stronger sustain role performance and group-saving value.
- Class contrast vs mage becomes clearer: lower burst spikes, higher stable value via healing/DoT/utility.
- High-cost priest buttons now provide more reliable practical payoff.
