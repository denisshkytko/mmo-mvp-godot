# Spell-power scaling compensation pass (2026-03) / Компенсационный проход после внедрения SP-скейлинга (2026-03)

## RU

После включения новой системы SP-скейлинга по времени каста (direct/DoT/heal/HoT) был выполнен первый компенсационный проход по `value_flat`, чтобы сохранить практическую эффективность быстрых и мгновенных кнопок без возврата к старому глобальному `+100% SP`.

### Что сделано

- Для способностей со `scaling_mode = spell_power_flat` повышен `value_flat` по каст-тайм корзинам:
  - direct/active: `+36 / +24 / +12 / +0` (instant/fast/medium/long),
  - heal: `+25 / +18 / +10 / +3`.
- Для DoT/HoT способностей, переведённых на `caster_spell_power_dot/hot`, добавлена базовая компенсация:
  - `torment`, `poisoned_arrow` (~`+20%` к dot total flat),
  - `healing_stream` (~`+15%` к hot total flat).

### Затронутые группы

- Mage: `fire_blast`, `fireball`, `frost_wind`, `frostbolt`.
- Priest: `agony`, `throe`, `radiance`, `torment`, `healing_stream`.
- Shaman: `lightning`, `chain_lightning`, `earths_wrath`, `lesser_heal`, `life_surge`, `searing_strike`.
- Paladin: `judging_flame`, `lights_verdict`, `storm_of_light`, `strike_of_light`.
- Hunter: `arcane_shot`, `poisoned_arrow`.

### Примечание

Это промежуточный этап. Дальше нужна точечная калибровка по классам (KPI + плейтесты) уже на новой SP-модели.

---

## EN

After enabling cast-time-bucket SP scaling (direct/DoT/heal/HoT), we ran a first compensation pass on `value_flat` to preserve practical output of fast/instant buttons without reverting to legacy global `+100% SP` behavior.

### What was done

- `value_flat` was increased for `scaling_mode = spell_power_flat` abilities by cast bucket:
  - direct/active: `+36 / +24 / +12 / +0` (instant/fast/medium/long),
  - heal: `+25 / +18 / +10 / +3`.
- Additional baseline compensation for DoT/HoT abilities migrated to `caster_spell_power_dot/hot`:
  - `torment`, `poisoned_arrow` (~`+20%` to dot total flat),
  - `healing_stream` (~`+15%` to hot total flat).

### Scope

- Mage: `fire_blast`, `fireball`, `frost_wind`, `frostbolt`.
- Priest: `agony`, `throe`, `radiance`, `torment`, `healing_stream`.
- Shaman: `lightning`, `chain_lightning`, `earths_wrath`, `lesser_heal`, `life_surge`, `searing_strike`.
- Paladin: `judging_flame`, `lights_verdict`, `storm_of_light`, `strike_of_light`.
- Hunter: `arcane_shot`, `poisoned_arrow`.

This is an interim step; class-by-class KPI/playtest calibration should follow on top of the new SP model.
