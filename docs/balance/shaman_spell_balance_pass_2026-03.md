# Shaman spell balance pass (2026-03) / Баланс-проход по заклинаниям шамана (2026-03)

## RU

Этот проход охватывает **всю линейку заклинаний шамана** по той же системе, что уже применялась к магу/жрецу/храмовнику: throughput, tempo, resource pressure и role identity.

Цель: сохранить идентичность шамана как гибридного класса (элементальный pressure + гибкое исцеление + групповые ауры/стойки), без перекоса в одну «универсально лучшую» ротацию.

### Изменения по всем заклинаниям

#### Damage / pressure
- **Lightning**: `15..150 -> 20..200`, high-rank cast `2.0/3.0 -> 1.6/2.2`.
- **Chain Lightning**: `100/200/300 -> 140/260/380`, cast `2.0/2.5/3.0 -> 1.8/2.2/2.6`, cost `12 -> 14`.
- **Earth's Wrath**: `20..140 -> 30..210`, cooldown curve `7..5 -> 6..4`.
- **Searing Strike**: phys+magic scaling increased (`P 60..120 -> 65..125`, `M 15..45 -> 18..54`).

#### Healing toolkit
- **Healing Touch**: `45..450 -> 60..600`, cast `3/4/5 -> 2.5/3.2/4.0`, cost `12 -> 14`.
- **Lesser Heal**: `45..225 -> 60..300`, cast `1.5 -> 1.4`, cost `8 -> 9`.
- **Life Surge**: `100/200/300 -> 140/260/380`, cast `3.0 -> 2.6`, cost `16 -> 18`.

#### Auras / buffs / stances / utility
- **Wind Spirit Devotion**: `5..40 -> 6..48` (AGI/PER aura).
- **Earth Spirit Devotion**: `8..48 -> 10..60` (STR/END aura).
- **Spirit of Insight**: `10/15/20 -> 12/18/24` cast-speed aura.
- **Stone Fists**: `AP 25..175 -> 30..210`, threat `5% -> 6%`.
- **Stone Skin**: `10/15/20/25/30 -> 12/18/24/30/36`, cost `12 -> 10`.
- **Tailwind**: move speed `40% -> 45%`, cost `12 -> 10`.
- **Water Devotion**: mana-per-tick `1.0% -> 1.5%` (cast speed bonus kept at `20%`).
- **Spirits Aid**: passive cooldown `900s -> 600s`.
- **Call of Spirits**: cast `5.0 -> 4.0`, cost `16 -> 14`, revive `20/20 -> 30/30`.

### Ожидаемый эффект

- Шаман получает более ровную и практичную связку «дпс + поддержка» в соло и группе.
- Длинные касты лечения/кастающего dps лучше окупаются фактическим эффектом.
- Ауры и стойки дают более выраженный вклад в групповую полезность без потери выбора.

---

## EN

This pass covers the **entire shaman spell kit** with the same framework used for mage/priest/paladin: throughput, tempo, resource pressure, and role identity.

Goal: preserve shaman as a hybrid class (elemental pressure + flexible healing + group auras/stances) without a single dominant rotation.

### Full spell list changes

#### Damage / pressure
- **Lightning**: `15..150 -> 20..200`, high-rank cast `2.0/3.0 -> 1.6/2.2`.
- **Chain Lightning**: `100/200/300 -> 140/260/380`, cast `2.0/2.5/3.0 -> 1.8/2.2/2.6`, cost `12 -> 14`.
- **Earth's Wrath**: `20..140 -> 30..210`, cooldown curve `7..5 -> 6..4`.
- **Searing Strike**: phys+magic scaling increased (`P 60..120 -> 65..125`, `M 15..45 -> 18..54`).

#### Healing toolkit
- **Healing Touch**: `45..450 -> 60..600`, cast `3/4/5 -> 2.5/3.2/4.0`, cost `12 -> 14`.
- **Lesser Heal**: `45..225 -> 60..300`, cast `1.5 -> 1.4`, cost `8 -> 9`.
- **Life Surge**: `100/200/300 -> 140/260/380`, cast `3.0 -> 2.6`, cost `16 -> 18`.

#### Auras / buffs / stances / utility
- **Wind Spirit Devotion**: `5..40 -> 6..48` (AGI/PER aura).
- **Earth Spirit Devotion**: `8..48 -> 10..60` (STR/END aura).
- **Spirit of Insight**: `10/15/20 -> 12/18/24` cast-speed aura.
- **Stone Fists**: `AP 25..175 -> 30..210`, threat `5% -> 6%`.
- **Stone Skin**: `10/15/20/25/30 -> 12/18/24/30/36`, cost `12 -> 10`.
- **Tailwind**: move speed `40% -> 45%`, cost `12 -> 10`.
- **Water Devotion**: mana-per-tick `1.0% -> 1.5%` (cast speed bonus unchanged at `20%`).
- **Spirits Aid**: passive cooldown `900s -> 600s`.
- **Call of Spirits**: cast `5.0 -> 4.0`, cost `16 -> 14`, revive `20/20 -> 30/30`.

### Expected effect

- Shaman gets a smoother practical mix of damage and support in solo/group scenarios.
- Long-cast healing and caster-pressure spells better match their actual combat payoff.
- Auras and stances provide clearer group value without collapsing player choice.
