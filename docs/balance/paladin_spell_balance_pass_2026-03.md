# Paladin spell balance pass (2026-03) / Баланс-проход по заклинаниям храмовника (2026-03)

## RU

Этот проход применяет уже отработанную систему (`throughput + tempo + resource pressure + role identity`) к храмовнику.

Цель: усилить читаемость роли паладина как **гибридного фронтлайн-класса** (melee pressure + точечный/групповой сейв), без превращения в «второго жреца» по pure-heal или «второго воина» по чистому физическому burst.

### Основные изменения

#### Healing toolkit
- **Healing Light**: `50..450 -> 65..585`, cast `3/4/5 -> 2.5/3.2/4.0`, cost `16 -> 14`.
- **Radiant Touch**: `35..110 -> 45..165`, high-rank cast `2.0 -> 1.6`, cost `8 -> 9`.

#### Damage / pressure
- **Judging Flame**: `50..150 -> 75..225`, high-rank cast `2.0 -> 1.5`.
- **Light's Verdict**: `200/300/400 -> 240/360/500`, cooldown `10s -> 9s`, cost `12 -> 14`.
- **Storm of Light**: magic add `50/100/150 -> 70/130/190`, phys pct `100/110/120 -> 100/115/130`, cooldown `10s -> 8s`, cost `12 -> 14`.
- **Strike of Light**: magic add `5..65 -> 8..86`, phys pct `80..110 -> 85..115`.
- **Light Execution**: execute pct `250 -> 300`, cooldown `6s -> 5s`, cost `8 -> 10`.


#### Auras (checked and tuned)
- **Aura of Light Protection**: `DEF 50..350 -> 60..420`, `RES 25..175 -> 35..245`.
- **Aura of Tempering**: `50/65/80/95 -> 60/80/100/120` physical bonus.
- **Concentration Aura**: added high-rank scaling (`10%` at L22, `16%` at L50).

#### Buffs / stances / mana economy
- **Lightbound Might**: `10..70 -> 12..84`.
- **Light's Guidance** (mana regen buff): `5/7/9/11/13/15 -> 7/10/13/16/19/22`.
- **Prayer to the Light**: cooldown `120s -> 90s`.
- **Path of Righteous Fury**: mana-on-hit `1% -> 2%`, threat `5% -> 6%`.

### Ожидаемый эффект

- Храмовник сильнее в длинных боях как гибрид: лучше поддержка группы и стабильнее ресурсная кривая.
- Burst-окна стали ощутимее, но дополнительно ограничены cost на сильных кнопках.
- Выбор между stance/утилити лучше отражает роль фронтлайна с поддержкой, а не чистого хилера/кастера.

---

## EN

This pass applies the established framework (`throughput + tempo + resource pressure + role identity`) to paladin.

Goal: strengthen paladin identity as a **hybrid frontline class** (melee pressure + targeted/group saves), without turning it into a pure priest-like healer or pure warrior-like physical burst class.

### Main changes

#### Healing toolkit
- **Healing Light**: `50..450 -> 65..585`, cast `3/4/5 -> 2.5/3.2/4.0`, cost `16 -> 14`.
- **Radiant Touch**: `35..110 -> 45..165`, high-rank cast `2.0 -> 1.6`, cost `8 -> 9`.

#### Damage / pressure
- **Judging Flame**: `50..150 -> 75..225`, high-rank cast `2.0 -> 1.5`.
- **Light's Verdict**: `200/300/400 -> 240/360/500`, cooldown `10s -> 9s`, cost `12 -> 14`.
- **Storm of Light**: magic add `50/100/150 -> 70/130/190`, phys pct `100/110/120 -> 100/115/130`, cooldown `10s -> 8s`, cost `12 -> 14`.
- **Strike of Light**: magic add `5..65 -> 8..86`, phys pct `80..110 -> 85..115`.
- **Light Execution**: execute pct `250 -> 300`, cooldown `6s -> 5s`, cost `8 -> 10`.


#### Auras (checked and tuned)
- **Aura of Light Protection**: `DEF 50..350 -> 60..420`, `RES 25..175 -> 35..245`.
- **Aura of Tempering**: `50/65/80/95 -> 60/80/100/120` physical bonus.
- **Concentration Aura**: added high-rank scaling (`10%` at L22, `16%` at L50).

#### Buffs / stances / mana economy
- **Lightbound Might**: `10..70 -> 12..84`.
- **Light's Guidance** (mana regen buff): `5/7/9/11/13/15 -> 7/10/13/16/19/22`.
- **Prayer to the Light**: cooldown `120s -> 90s`.
- **Path of Righteous Fury**: mana-on-hit `1% -> 2%`, threat `5% -> 6%`.

### Expected effect

- Paladin performs better in long fights as a hybrid: stronger support and steadier resource curve.
- Burst windows are stronger but constrained by higher costs on premium buttons.
- Stance/utility choices better match a support-frontline role instead of pure healer/caster behavior.
